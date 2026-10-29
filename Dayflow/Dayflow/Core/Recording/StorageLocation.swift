//
//  StorageLocation.swift
//  Dayflow
//
//  Where the large media files go: screen recordings, timelapses and voice notes.
//  The user can point them at another folder, such as a mounted NAS share. The
//  database and its backups always stay in Application Support because SQLite's WAL
//  mode isn't safe on network volumes.
//
//  The folder is resolved once per launch (`activeBase`) because the storage managers
//  keep their paths for the life of the process. A change in Settings applies after a
//  restart.
//

import Foundation

enum StorageLocation {
  static let preferenceKey = "customMediaStoragePath"

  /// Application Support/<app>, home of the database and the default media folders.
  static var defaultBase: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent(AppDataDirectory.name, isDirectory: true)
  }

  /// The folder the user chose, or nil to use the default.
  static var customBase: URL? {
    get {
      guard let path = UserDefaults.standard.string(forKey: preferenceKey), !path.isEmpty else {
        return nil
      }
      return URL(fileURLWithPath: path, isDirectory: true)
    }
    set {
      if let newValue {
        UserDefaults.standard.set(newValue.path, forKey: preferenceKey)
      } else {
        UserDefaults.standard.removeObject(forKey: preferenceKey)
      }
    }
  }

  /// What this launch is using. Fixed on first access.
  static let activeBase: URL = resolvedBase()

  /// A folder was chosen but can't be reached right now, for example an unmounted NAS.
  static var isCustomUnavailable: Bool {
    guard let custom = customBase else { return false }
    return !isUsable(custom)
  }

  /// The chosen folder differs from the one in use, so a restart is needed.
  static var needsRestart: Bool {
    resolvedBase().standardizedFileURL.path != activeBase.standardizedFileURL.path
  }

  /// Folder for one kind of media, such as "recordings".
  static func directory(_ name: String) -> URL {
    activeBase.appendingPathComponent(name, isDirectory: true)
  }

  static func isUsable(_ url: URL, fileManager: FileManager = .default) -> Bool {
    var isDirectory: ObjCBool = false
    return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
      && isDirectory.boolValue && fileManager.isWritableFile(atPath: url.path)
  }

  /// Fails with a readable error when `url` can't hold new files.
  static func validate(_ url: URL, fileManager: FileManager = .default) throws {
    guard isUsable(url, fileManager: fileManager) else {
      throw StorageLocationError.notWritable
    }
    // isWritableFile can say yes for a share that is read-only to this user.
    let probe = url.appendingPathComponent(".dayflow-write-test-\(UUID().uuidString)")
    do {
      try Data().write(to: probe)
      try? fileManager.removeItem(at: probe)
    } catch {
      throw StorageLocationError.notWritable
    }
  }

  private static func resolvedBase() -> URL {
    if let custom = customBase, isUsable(custom) {
      return custom.appendingPathComponent(AppDataDirectory.name, isDirectory: true)
    }
    return defaultBase
  }
}

enum StorageLocationError: LocalizedError {
  case notWritable

  var errorDescription: String? {
    String(
      localized: "storage.location.notWritable",
      defaultValue: "Dayflow can't write to that folder. Pick another one.")
  }
}
