//
//  GarminCredentials.swift
//  Dayflow
//
//  Where the Garmin Connect developer key lives: the macOS Keychain, never UserDefaults or a file.
//

import Foundation

enum GarminCredentials {
  private static let provider = "garmin-connect"

  static var hasKey: Bool { key != nil }

  static var key: String? { KeychainManager.shared.retrieve(for: provider) }

  /// Strips whitespace and surrounding quotes, which come along when a value is copied out of an
  /// .env file. Returns nil when nothing usable is left.
  static func cleaned(_ raw: String) -> String? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    return trimmed.isEmpty ? nil : trimmed
  }

  @discardableResult
  static func save(_ raw: String) -> Bool {
    guard let key = cleaned(raw) else { return false }
    return KeychainManager.shared.store(key, for: provider)
  }

  @discardableResult
  static func remove() -> Bool {
    KeychainManager.shared.delete(for: provider)
  }
}
