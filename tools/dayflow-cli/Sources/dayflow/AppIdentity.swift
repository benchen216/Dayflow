import Foundation

/// The Dayflow+ build this CLI ships inside. Must match the app's
/// AppDataDirectory.name and PRODUCT_BUNDLE_IDENTIFIER.
enum AppIdentity {
  static let dataDirectoryName = "DayflowPlus"
  static let bundleIdentifier = "com.benchen216.DayflowPlus"
}
