//
//  GarminSyncService.swift
//  Dayflow
//
//  Pulls the last week of Garmin stress, Body Battery, HRV and heart rate into Dayflow's
//  database when the app opens and every six hours after, so the Day summary and voice notes
//  can show them next to mood. Runs only while a Garmin key is saved.
//

import Foundation

extension Notification.Name {
  static let garminDataUpdated = Notification.Name("garminDataUpdated")
}

enum GarminSyncOutcome: Equatable, Sendable {
  case synced(days: Int, samples: Int)
  case keyRejected
  case failed(String)
}

@MainActor
final class GarminSyncService: ObservableObject {
  static let shared = GarminSyncService()

  static let syncInterval: TimeInterval = 6 * 60 * 60
  static let daysToFetch = 7

  /// Cached so views don't read the Keychain on every render.
  @Published private(set) var hasKey = false
  @Published private(set) var isSyncing = false
  @Published private(set) var lastOutcome: GarminSyncOutcome?
  @Published private(set) var lastSyncedAt: Date?

  private var timer: Timer?
  private let api = GarminAPI()

  private init() {
    lastSyncedAt = StorageManager.shared.garminLastFetchedAt()
  }

  /// Reads the Keychain once at launch. Skipped when the app is only hosting unit tests: a
  /// test build is signed differently, so the Keychain would stop it with a permission prompt.
  func startIfEnabled() {
    guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
    hasKey = GarminCredentials.hasKey
    guard hasKey else { return }
    start()
  }

  /// Called after the key is saved or removed in Settings.
  func keyChanged() {
    lastOutcome = nil
    hasKey = GarminCredentials.hasKey
    let api = api
    Task {
      await api.reset()
      if hasKey { start() } else { stop() }
    }
  }

  func syncNow() {
    guard !isSyncing, hasKey else { return }
    isSyncing = true
    let api = api
    let days = Self.recentDays(Self.daysToFetch, endingAt: Date())
    Task.detached(priority: .utility) {
      let outcome = await Self.sync(api: api, days: days, storage: StorageManager.shared)
      await MainActor.run {
        self.isSyncing = false
        self.lastOutcome = outcome
        if case .synced = outcome {
          self.lastSyncedAt = Date()
          NotificationCenter.default.post(name: .garminDataUpdated, object: nil)
        }
      }
    }
  }

  private func start() {
    stop()
    syncNow()
    timer = Timer.scheduledTimer(withTimeInterval: Self.syncInterval, repeats: true) { _ in
      Task { @MainActor in GarminSyncService.shared.syncNow() }
    }
  }

  private func stop() {
    timer?.invalidate()
    timer = nil
  }

  nonisolated static func sync(api: GarminAPI, days: [String], storage: StorageManager) async
    -> GarminSyncOutcome
  {
    do {
      let result = try await api.fetch(days: days)
      try storage.saveGarmin(days: result.days, samples: result.samples)
      return .synced(days: result.days.filter(\.hasData).count, samples: result.samples.count)
    } catch GarminAPIError.keyRejected {
      return .keyRejected
    } catch GarminAPIError.http(let status) {
      return .failed("Garmin answered HTTP \(status).")
    } catch {
      return .failed(error.localizedDescription)
    }
  }

  /// "yyyy-MM-dd" for the `count` local calendar days ending with `date`, oldest first.
  nonisolated static func recentDays(
    _ count: Int, endingAt date: Date, calendar: Calendar = .current
  ) -> [String] {
    (0..<count).reversed().compactMap { offset in
      calendar.date(byAdding: .day, value: -offset, to: date).map {
        calendarDateString($0, calendar: calendar)
      }
    }
  }

  nonisolated static func calendarDateString(_ date: Date, calendar: Calendar = .current)
    -> String
  {
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
  }
}
