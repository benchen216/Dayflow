//
//  DeviceAppSession.swift
//  Dayflow
//
//  App usage from the user's other Apple devices (iPhone, iPad), rebuilt from
//  foreground/background events. A session is one stretch of an app on screen.
//

import Foundation

struct DeviceAppSession: Equatable, Sendable {
  let deviceID: String
  let bundleID: String
  let start: Date
  let end: Date

  var duration: TimeInterval { end.timeIntervalSince(start) }
}

struct UsageDevice: Equatable, Sendable {
  let deviceID: String
  /// Hardware model such as "iPhone17,1", when Biome's sync peers name it.
  let model: String?
  /// Newest event seen from this device; the honest "last synced" time.
  let lastEventAt: Date?
  let importedAt: Date?

  var kind: UsageDeviceKind { UsageDeviceKind(model: model) }
}

enum UsageDeviceKind: String, Sendable {
  case iPhone
  case iPad
  case other

  init(model: String?) {
    guard let model else {
      self = .other
      return
    }
    if model.hasPrefix("iPhone") {
      self = .iPhone
    } else if model.hasPrefix("iPad") {
      self = .iPad
    } else {
      self = .other
    }
  }

  var displayName: String {
    switch self {
    case .iPhone: return "iPhone"
    case .iPad: return "iPad"
    case .other: return String(localized: "Other device")
    }
  }
}

enum DeviceAppSessionBuilder {
  /// A foreground event with no matching background event (the device slept,
  /// or the stream rotated) is closed by the next event, but never stretched
  /// past this.
  static let maxSessionDuration: TimeInterval = 3 * 60 * 60
  static let minSessionDuration: TimeInterval = 1

  /// Screens that mean "not using an app": the lock screen, wallpaper editor,
  /// screenshot preview, and small system sheets (Face ID, AirPods, Wallet).
  static func isExcluded(_ event: AppInFocusEvent) -> Bool {
    if event.kind == AppInFocusEvent.systemOverlayKind { return true }
    let bundleID = event.bundleID
    if excludedBundleIDs.contains(bundleID) { return true }
    if bundleID.hasPrefix("com.apple.springboard") { return true }
    return bundleID.hasPrefix("com.apple.") && bundleID.hasSuffix("UIService")
  }

  private static let excludedBundleIDs: Set<String> = [
    "com.apple.SleepLockScreen",
    "com.apple.ScreenshotServicesService",
    "com.apple.PosterBoard",
    "com.apple.HeadphoneProxService",
    "com.apple.loginwindow",
  ]

  /// Pairs events into sessions. Only one app is in front at a time on a
  /// phone, so a new foreground event (or the lock screen) ends whatever was
  /// open.
  static func sessions(from events: [AppInFocusEvent], deviceID: String) -> [DeviceAppSession] {
    let ordered = events.enumerated().sorted {
      $0.element.timestamp == $1.element.timestamp
        ? $0.offset < $1.offset : $0.element.timestamp < $1.element.timestamp
    }.map(\.element)

    var sessions: [DeviceAppSession] = []
    var open: (bundleID: String, start: Date)?

    func close(at end: Date) {
      guard let current = open else { return }
      open = nil
      let cappedEnd = min(end, current.start.addingTimeInterval(maxSessionDuration))
      guard cappedEnd.timeIntervalSince(current.start) >= minSessionDuration else { return }
      sessions.append(
        DeviceAppSession(
          deviceID: deviceID, bundleID: current.bundleID, start: current.start, end: cappedEnd))
    }

    for event in ordered {
      let excluded = isExcluded(event)
      if event.isStarting {
        // A repeated foreground event for the app already open is noise.
        if open?.bundleID == event.bundleID { continue }
        close(at: event.timestamp)
        if !excluded {
          open = (event.bundleID, event.timestamp)
        }
      } else if open?.bundleID == event.bundleID {
        close(at: event.timestamp)
      }
    }
    // A session still open at the end of the stream is in progress (or was cut
    // off by sync); it's picked up on a later import once its end arrives.
    return sessions
  }
}
