//
//  DeviceUsageSummary.swift
//  Dayflow
//
//  Turns raw sessions from other devices into what the UI shows: a day's
//  total and top apps, and merged blocks for the timeline lane.
//

import Foundation

struct DeviceAppUsage: Equatable, Identifiable, Sendable {
  let bundleID: String
  let duration: TimeInterval
  let sessionCount: Int

  var id: String { bundleID }
  var displayName: String { DeviceAppNames.displayName(for: bundleID) }
}

struct DeviceUsageDaySummary: Equatable, Sendable {
  let total: TimeInterval
  let pickups: Int
  let topApps: [DeviceAppUsage]
  let devices: [UsageDevice]

  static let empty = DeviceUsageDaySummary(total: 0, pickups: 0, topApps: [], devices: [])

  /// Newest event across the devices that contributed, for "last synced".
  var lastSyncedAt: Date? { devices.compactMap(\.lastEventAt).max() }
}

/// A stretch of phone use on the timeline: sessions with short gaps merged.
struct DeviceUsageBlock: Equatable, Identifiable, Sendable {
  let start: Date
  let end: Date
  let apps: [DeviceAppUsage]

  var id: String { "\(Int(start.timeIntervalSince1970))" }
  var duration: TimeInterval { end.timeIntervalSince(start) }
}

enum DeviceUsageSummaryBuilder {
  /// Sessions closer together than this read as one sitting with the phone.
  static let blockMergeGap: TimeInterval = 3 * 60
  /// Blocks shorter than this would be invisible lines on the timeline.
  static let minimumBlockDuration: TimeInterval = 2 * 60
  /// A new session at least this long after the previous one counts as
  /// picking the phone up again.
  static let pickupGap: TimeInterval = 60

  static func clip(_ sessions: [DeviceAppSession], start: Date, end: Date) -> [DeviceAppSession] {
    sessions.compactMap { session in
      let clippedStart = max(session.start, start)
      let clippedEnd = min(session.end, end)
      guard clippedEnd > clippedStart else { return nil }
      return DeviceAppSession(
        deviceID: session.deviceID, bundleID: session.bundleID, start: clippedStart,
        end: clippedEnd)
    }
  }

  static func appUsage(_ sessions: [DeviceAppSession]) -> [DeviceAppUsage] {
    var durations: [String: TimeInterval] = [:]
    var counts: [String: Int] = [:]
    for session in sessions {
      durations[session.bundleID, default: 0] += session.duration
      counts[session.bundleID, default: 0] += 1
    }
    return durations.map {
      DeviceAppUsage(bundleID: $0.key, duration: $0.value, sessionCount: counts[$0.key] ?? 0)
    }.sorted {
      $0.duration == $1.duration ? $0.bundleID < $1.bundleID : $0.duration > $1.duration
    }
  }

  static func daySummary(
    sessions: [DeviceAppSession],
    dayStart: Date,
    dayEnd: Date,
    devices: [UsageDevice],
    topAppLimit: Int = 5
  ) -> DeviceUsageDaySummary {
    let clipped = clip(sessions, start: dayStart, end: dayEnd).sorted { $0.start < $1.start }
    let contributing = Set(clipped.map(\.deviceID))

    var pickups = 0
    var lastEndByDevice: [String: Date] = [:]
    for session in clipped {
      if let lastEnd = lastEndByDevice[session.deviceID],
        session.start.timeIntervalSince(lastEnd) < pickupGap
      {
        // Switching apps without putting the phone down.
      } else {
        pickups += 1
      }
      lastEndByDevice[session.deviceID] = max(
        lastEndByDevice[session.deviceID] ?? session.end, session.end)
    }

    return DeviceUsageDaySummary(
      total: clipped.reduce(0) { $0 + $1.duration },
      pickups: pickups,
      topApps: Array(appUsage(clipped).prefix(topAppLimit)),
      devices: devices.filter { contributing.contains($0.deviceID) }
    )
  }

  /// Merged blocks across all devices, for drawing beside the timeline.
  static func blocks(sessions: [DeviceAppSession], dayStart: Date, dayEnd: Date)
    -> [DeviceUsageBlock]
  {
    let clipped = clip(sessions, start: dayStart, end: dayEnd).sorted { $0.start < $1.start }
    var groups: [[DeviceAppSession]] = []
    var groupEnd: Date?
    for session in clipped {
      if let end = groupEnd, session.start.timeIntervalSince(end) <= blockMergeGap {
        groups[groups.count - 1].append(session)
        groupEnd = max(end, session.end)
      } else {
        groups.append([session])
        groupEnd = session.end
      }
    }

    return groups.compactMap { group in
      guard let first = group.first else { return nil }
      let end = group.map(\.end).max() ?? first.end
      guard end.timeIntervalSince(first.start) >= minimumBlockDuration else { return nil }
      return DeviceUsageBlock(start: first.start, end: end, apps: appUsage(group))
    }
  }
}

/// Human names for iOS bundle ids. There's no offline way to ask the system
/// for an iOS app's name on a Mac, so common apps are listed and the rest
/// fall back to the most telling part of the bundle id.
enum DeviceAppNames {
  private static let known: [String: String] = [
    "com.apple.mobilesafari": "Safari",
    "com.apple.camera": "Camera",
    "com.apple.mobilecal": "Calendar",
    "com.apple.Preferences": "Settings",
    "com.apple.mobileslideshow": "Photos",
    "com.apple.InCallService": "Phone call",
    "com.apple.mobilephone": "Phone",
    "com.apple.AppStore": "App Store",
    "com.apple.mobiletimer": "Clock",
    "com.apple.calculator": "Calculator",
    "com.apple.MobileSMS": "Messages",
    "com.apple.Health": "Health",
    "com.apple.Home": "Home",
    "com.apple.findmy": "Find My",
    "com.apple.Passbook": "Wallet",
    "com.apple.Maps": "Apple Maps",
    "com.apple.mobilemail": "Mail",
    "com.apple.Fitness": "Fitness",
    "com.apple.shortcuts": "Shortcuts",
    "com.apple.Bridge": "Watch",
    "com.apple.weather": "Weather",
    "com.apple.reminders": "Reminders",
    "com.apple.mobilenotes": "Notes",
    "com.apple.VoiceMemos": "Voice Memos",
    "com.apple.Music": "Music",
    "com.apple.podcasts": "Podcasts",
    "com.apple.tv": "TV",
    "com.apple.news": "News",
    "com.apple.iBooks": "Books",
    "com.apple.facetime": "FaceTime",
    "com.burbn.instagram": "Instagram",
    "com.burbn.barcelona": "Threads",
    "com.google.ios.youtube": "YouTube",
    "com.google.Maps": "Google Maps",
    "com.google.Gmail": "Gmail",
    "com.google.chrome.ios": "Chrome",
    "com.google.GoogleMobile": "Google",
    "jp.naver.line": "LINE",
    "com.hammerandchisel.discord": "Discord",
    "com.spotify.client": "Spotify",
    "com.facebook.Facebook": "Facebook",
    "com.facebook.Messenger": "Messenger",
    "net.whatsapp.WhatsApp": "WhatsApp",
    "ph.telegra.Telegraph": "Telegram",
    "com.zhiliaoapp.musically": "TikTok",
    "com.atebits.Tweetie2": "X",
    "com.reddit.Reddit": "Reddit",
    "com.netflix.Netflix": "Netflix",
    "com.tinyspeck.chatlyio": "Slack",
    "notion.id": "Notion",
    "com.openai.chat": "ChatGPT",
    "com.anthropic.claude": "Claude",
    "com.microsoft.Office.Outlook": "Outlook",
    "com.linkedin.LinkedIn": "LinkedIn",
    "com.ubercab.UberClient": "Uber",
  ]

  private static let genericComponents: Set<String> = [
    "app", "apps", "client", "ios", "iphone", "ipad", "mobile", "universal", "main",
  ]

  static func displayName(for bundleID: String) -> String {
    if let name = known[bundleID] { return name }
    let components = bundleID.split(separator: ".").map(String.init)
    let meaningful = components.dropFirst().reversed().first {
      !genericComponents.contains($0.lowercased())
    }
    guard let name = meaningful ?? components.last, !name.isEmpty else { return bundleID }
    return name.prefix(1).uppercased() + name.dropFirst()
  }
}
