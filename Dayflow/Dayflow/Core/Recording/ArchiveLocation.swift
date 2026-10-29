//
//  ArchiveLocation.swift
//  Dayflow
//
//  Where old recordings and timelapses go instead of being deleted. When the local folders pass
//  their size limit, the oldest files are moved here (a NAS share, a cloud-synced folder, an
//  external drive) and the database is pointed at the new path, so they still play while the
//  folder is reachable. With no archive folder set, the oldest files are deleted as before.
//

import Foundation

enum ArchiveLocation {
  static let preferenceKey = "archiveFolderPath"

  /// The folder the user chose, whether or not it can be reached right now.
  static var configuredBase: URL? {
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

  static var isConfigured: Bool { configuredBase != nil }

  /// The archive folder when it can take files now, nil when unset or unreachable (an unmounted
  /// NAS). Callers must not delete anything just because this is nil while `isConfigured`.
  static var availableBase: URL? {
    guard let base = configuredBase, StorageLocation.isUsable(base) else { return nil }
    return base
  }

  /// Folder for one kind of media inside the archive, such as "recordings".
  static func directory(_ name: String, in base: URL) -> URL {
    base.appendingPathComponent(AppDataDirectory.name, isDirectory: true)
      .appendingPathComponent(name, isDirectory: true)
  }

  /// The archive can't live inside the folder Dayflow cleans, or it would be cleaned.
  static func validate(_ url: URL, storageBase: URL = StorageLocation.activeBase) throws {
    try StorageLocation.validate(url)
    let archive = url.standardizedFileURL.resolvingSymlinksInPath().path
    let storage = storageBase.standardizedFileURL.resolvingSymlinksInPath().path
    if archive == storage || archive.hasPrefix(storage + "/") || storage.hasPrefix(archive + "/") {
      throw ArchiveLocationError.overlapsStorage
    }
  }

  /// Copies `source` into `folder`, checks the copy is the same size, runs `afterCopy` (where the
  /// caller repoints its records), then removes `source`. The original is only removed once the
  /// copy is verified and `afterCopy` succeeded; if either fails the copy is removed and the
  /// original stays. Returns where the file now is.
  @discardableResult
  static func move(
    _ source: URL, into folder: URL, fileManager: FileManager = .default,
    afterCopy: (URL) throws -> Void = { _ in }
  ) throws -> URL {
    try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
    let destination = uniqueDestination(for: source.lastPathComponent, in: folder, fileManager)
    let sourceSize = try fileSize(source, fileManager)

    do {
      try fileManager.copyItem(at: source, to: destination)
      guard try fileSize(destination, fileManager) == sourceSize else {
        throw ArchiveLocationError.copyMismatch
      }
      try afterCopy(destination)
    } catch {
      try? fileManager.removeItem(at: destination)
      throw error
    }
    try fileManager.removeItem(at: source)
    return destination
  }

  private static func fileSize(_ url: URL, _ fileManager: FileManager) throws -> Int64 {
    let size = try fileManager.attributesOfItem(atPath: url.path)[.size] as? NSNumber
    return size?.int64Value ?? 0
  }

  /// Never overwrites: a name already in the archive gets a numbered suffix.
  private static func uniqueDestination(
    for name: String, in folder: URL, _ fileManager: FileManager
  ) -> URL {
    var candidate = folder.appendingPathComponent(name)
    guard fileManager.fileExists(atPath: candidate.path) else { return candidate }
    let base = (name as NSString).deletingPathExtension
    let ext = (name as NSString).pathExtension
    var number = 2
    repeat {
      let numbered = ext.isEmpty ? "\(base)-\(number)" : "\(base)-\(number).\(ext)"
      candidate = folder.appendingPathComponent(numbered)
      number += 1
    } while fileManager.fileExists(atPath: candidate.path)
    return candidate
  }
}

enum ArchiveLocationError: LocalizedError {
  case overlapsStorage
  case copyMismatch

  var errorDescription: String? {
    switch self {
    case .overlapsStorage:
      return String(
        localized: "storage.archive.overlap",
        defaultValue:
          "The archive can't be the storage folder or inside it. Pick a different folder.")
    case .copyMismatch:
      return "The archived copy didn't match the original."
    }
  }
}
