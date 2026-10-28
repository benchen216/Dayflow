//
//  DeviceUsageSyncService.swift
//  Dayflow
//
//  Copies iPhone/iPad Screen Time from Biome into Dayflow's database on a
//  timer, so the Day summary, timeline, and the dayflow CLI/MCP can read it
//  without Full Disk Access of their own.
//
//  iCloud delivers the remote streams in batches, often hours apart. Nothing
//  here is real-time; the UI shows each device's newest event instead.
//

import Foundation

extension Notification.Name {
  static let deviceUsageDataUpdated = Notification.Name("deviceUsageDataUpdated")
}

enum DeviceUsagePreferences {
  private static let enabledKey = "deviceUsageImportEnabled"

  /// Off until the user turns it on: it needs Full Disk Access, which is a
  /// bigger ask than the rest of Dayflow makes.
  static var isEnabled: Bool {
    get { UserDefaults.standard.bool(forKey: enabledKey) }
    set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
  }
}

struct DeviceUsageImportResult: Equatable, Sendable {
  var access: DeviceUsageAccess
  var devicesImported = 0
  var devicesUnchanged = 0
  var sessionsWritten = 0
  var failedFiles = 0
}

@MainActor
final class DeviceUsageSyncService: ObservableObject {
  static let shared = DeviceUsageSyncService()

  static let syncInterval: TimeInterval = 15 * 60

  @Published private(set) var access: DeviceUsageAccess = .noSyncedDevices
  @Published private(set) var isSyncing = false
  @Published private(set) var lastResult: DeviceUsageImportResult?

  private var timer: Timer?
  private let source = BiomeDeviceUsageSource()

  func startIfEnabled() {
    guard DeviceUsagePreferences.isEnabled else { return }
    start()
  }

  func setEnabled(_ enabled: Bool) {
    DeviceUsagePreferences.isEnabled = enabled
    AnalyticsService.shared.capture("device_usage_import_toggled", ["enabled": enabled])
    if enabled {
      start()
    } else {
      stop()
      // Turning import off also forgets what was imported, so the timeline,
      // Daily brief, and MCP tools stop seeing phone data right away. Biome
      // keeps the source, so turning it back on re-imports it.
      lastResult = nil
      Task.detached(priority: .utility) {
        StorageManager.shared.deleteAllDeviceUsage()
        await MainActor.run {
          NotificationCenter.default.post(name: .deviceUsageDataUpdated, object: nil)
        }
      }
    }
  }

  func refreshAccess() {
    let source = source
    Task.detached(priority: .utility) {
      let access = source.checkAccess()
      await MainActor.run { self.access = access }
    }
  }

  func syncNow() {
    guard !isSyncing else { return }
    isSyncing = true
    let source = source
    Task.detached(priority: .utility) {
      let result = Self.importAll(source: source, storage: StorageManager.shared)
      await MainActor.run {
        self.isSyncing = false
        self.access = result.access
        self.lastResult = result
        if result.sessionsWritten > 0 {
          NotificationCenter.default.post(name: .deviceUsageDataUpdated, object: nil)
        }
      }
    }
  }

  private func start() {
    stop()
    syncNow()
    timer = Timer.scheduledTimer(withTimeInterval: Self.syncInterval, repeats: true) { _ in
      Task { @MainActor in DeviceUsageSyncService.shared.syncNow() }
    }
  }

  private func stop() {
    timer?.invalidate()
    timer = nil
  }

  /// One pass over every synced iPhone/iPad. Devices whose files haven't
  /// changed since the last pass are skipped.
  nonisolated static func importAll(
    source: BiomeDeviceUsageSource,
    storage: StorageManager
  ) -> DeviceUsageImportResult {
    var result = DeviceUsageImportResult(access: source.checkAccess())
    guard result.access == .available else { return result }

    let streams: [BiomeDeviceStream]
    do {
      streams = try source.deviceStreams()
    } catch {
      result.access =
        BiomeDeviceUsageSource.isPermissionError(error) ? .needsFullDiskAccess : .noSyncedDevices
      return result
    }

    for stream in streams {
      if storage.deviceUsageSourceSignature(deviceID: stream.deviceID) == stream.signature {
        result.devicesUnchanged += 1
        continue
      }

      let decoded = source.events(in: stream)
      result.failedFiles += decoded.failedFiles
      let sessions = DeviceAppSessionBuilder.sessions(
        from: decoded.events, deviceID: stream.deviceID)
      let timestamps = decoded.events.map(\.timestamp)
      // With an unreadable segment the decoded range has a hole, so don't
      // delete anything, and leave the signature unset so the next pass retries.
      let isComplete = decoded.failedFiles == 0

      do {
        try storage.replaceDeviceAppSessions(
          sessions,
          deviceID: stream.deviceID,
          model: stream.model,
          coveredFrom: isComplete ? timestamps.min() : nil,
          lastEventAt: timestamps.max(),
          sourceSignature: isComplete ? stream.signature : ""
        )
        result.devicesImported += 1
        result.sessionsWritten += sessions.count
      } catch {
        print("⚠️ DeviceUsageSyncService: failed to store \(stream.deviceID): \(error)")
      }
    }
    return result
  }
}
