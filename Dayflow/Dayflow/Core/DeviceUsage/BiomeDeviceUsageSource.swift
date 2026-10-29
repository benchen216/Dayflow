//
//  BiomeDeviceUsageSource.swift
//  Dayflow
//
//  Finds the Screen Time data macOS already syncs from the user's iPhone and
//  iPad. With "Share Across Devices" on in Screen Time settings, iCloud drops
//  each device's App.InFocus events into
//  ~/Library/Biome/streams/restricted/App.InFocus/remote/<device id>/.
//  Reading there needs Full Disk Access.
//
//  Biome doesn't record which hardware a device id is. Its sync peers table
//  links the id to a rapport id, and knowledgeC's sync peers table links that
//  same rapport id to a model ("iPhone17,1"), so the two are joined here.
//

import Foundation
import GRDB

enum DeviceUsageAccess: Equatable, Sendable {
  case available
  /// Biome is there but macOS refused to list it.
  case needsFullDiskAccess
  /// No remote streams at all: Screen Time sharing is off, or no other devices.
  case noSyncedDevices
}

struct BiomeDeviceStream: Equatable, Sendable {
  let deviceID: String
  let model: String?
  /// Segment files in the device directory, oldest name first.
  let files: [URL]
  /// Changes whenever a segment file is added, removed, or appended to.
  let signature: String
}

struct BiomeDeviceUsageSource: Sendable {
  let homeDirectory: URL

  init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
    self.homeDirectory = homeDirectory
  }

  var remoteStreamsRoot: URL {
    homeDirectory.appendingPathComponent(
      "Library/Biome/streams/restricted/App.InFocus/remote", isDirectory: true)
  }

  private var biomeSyncDatabase: URL {
    homeDirectory.appendingPathComponent("Library/Biome/sync/sync.db")
  }

  private var knowledgeDatabase: URL {
    homeDirectory.appendingPathComponent("Library/Application Support/Knowledge/knowledgeC.db")
  }

  func checkAccess() -> DeviceUsageAccess {
    // Without Full Disk Access macOS still lists restricted/ itself and only
    // refuses the stream directories inside it, so probe the one we read.
    do {
      let remote = try FileManager.default.contentsOfDirectory(atPath: remoteStreamsRoot.path)
      return remote.isEmpty ? .noSyncedDevices : .available
    } catch {
      return Self.isPermissionError(error) ? .needsFullDiskAccess : .noSyncedDevices
    }
  }

  /// iPhone and iPad streams. Other Macs and Watches are left out: Dayflow
  /// already records this Mac, and a Watch's "screen time" isn't meaningful.
  /// A device whose model can't be looked up is kept rather than dropped, so
  /// an unreadable knowledgeC doesn't hide every phone.
  func deviceStreams() throws -> [BiomeDeviceStream] {
    let fileManager = FileManager.default
    let deviceIDs = try fileManager.contentsOfDirectory(atPath: remoteStreamsRoot.path)
    let models = deviceModels()

    return deviceIDs.sorted().compactMap { deviceID in
      let model = models[deviceID]
      if model != nil, UsageDeviceKind(model: model) == .other { return nil }

      let directory = remoteStreamsRoot.appendingPathComponent(deviceID, isDirectory: true)
      let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
      guard
        let entries = try? fileManager.contentsOfDirectory(
          at: directory, includingPropertiesForKeys: keys)
      else { return nil }

      // Segment files are named by creation time; "tombstone" is a directory
      // of deletions and is skipped by the regular-file check.
      var files: [(url: URL, size: Int, modified: TimeInterval)] = []
      for url in entries {
        guard let values = try? url.resourceValues(forKeys: Set(keys)),
          values.isRegularFile == true
        else { continue }
        files.append(
          (
            url, values.fileSize ?? 0,
            values.contentModificationDate?.timeIntervalSince1970 ?? 0
          ))
      }
      guard !files.isEmpty else { return nil }
      files.sort { $0.url.lastPathComponent < $1.url.lastPathComponent }

      let signature = files.map {
        "\($0.url.lastPathComponent):\($0.size):\(Int($0.modified))"
      }.joined(separator: "|")
      return BiomeDeviceStream(
        deviceID: deviceID, model: model, files: files.map(\.url), signature: signature)
    }
  }

  /// Decoded events for one device. A segment that fails to parse is skipped
  /// so one bad file doesn't hide the rest of the day.
  func events(in stream: BiomeDeviceStream) -> (events: [AppInFocusEvent], failedFiles: Int) {
    var events: [AppInFocusEvent] = []
    var failedFiles = 0
    for file in stream.files {
      do {
        let records = try SEGBReader.records(atPath: file.path)
        events.append(contentsOf: records.compactMap { AppInFocusEventDecoder.decode($0.payload) })
      } catch {
        failedFiles += 1
      }
    }
    return (events, failedFiles)
  }

  /// Biome device id → hardware model.
  func deviceModels() -> [String: String] {
    guard let biome = Self.openReadOnly(biomeSyncDatabase),
      let knowledge = Self.openReadOnly(knowledgeDatabase)
    else { return [:] }

    let rapportByDevice: [String: String] =
      (try? biome.read { db in
        var result: [String: String] = [:]
        let rows = try Row.fetchAll(
          db,
          sql: """
                SELECT device_identifier, ids_device_identifier
                FROM DevicePeer
                WHERE ids_device_identifier IS NOT NULL
            """)
        for row in rows {
          if let device: String = row["device_identifier"], let rapport: String = row["ids_device_identifier"] {
            result[device] = rapport
          }
        }
        return result
      }) ?? [:]

    let modelByRapport: [String: String] =
      (try? knowledge.read { db in
        var result: [String: String] = [:]
        let rows = try Row.fetchAll(
          db,
          sql: """
                SELECT ZRAPPORTID, ZMODEL
                FROM ZSYNCPEER
                WHERE ZRAPPORTID IS NOT NULL AND ZMODEL IS NOT NULL
            """)
        for row in rows {
          if let rapport: String = row["ZRAPPORTID"], let model: String = row["ZMODEL"] {
            result[rapport] = model
          }
        }
        return result
      }) ?? [:]

    return rapportByDevice.compactMapValues { modelByRapport[$0] }
  }

  private static func openReadOnly(_ url: URL) -> DatabaseQueue? {
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    var configuration = Configuration()
    configuration.readonly = true
    configuration.label = "BiomeDeviceUsageSource"
    return try? DatabaseQueue(path: url.path, configuration: configuration)
  }

  static func isPermissionError(_ error: Error) -> Bool {
    let nsError = error as NSError
    if nsError.domain == NSCocoaErrorDomain, nsError.code == NSFileReadNoPermissionError {
      return true
    }
    if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError,
      underlying.domain == NSPOSIXErrorDomain,
      underlying.code == Int(EPERM) || underlying.code == Int(EACCES)
    {
      return true
    }
    return false
  }
}
