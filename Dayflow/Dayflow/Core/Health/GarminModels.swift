//
//  GarminModels.swift
//  Dayflow
//
//  What Dayflow keeps from the Garmin Connect Personal API: one row per day (stress, Body
//  Battery, last night's HRV) and timestamped samples (Body Battery levels, HRV readings taken
//  during sleep). Decoding is kept apart from the network so it can be tested with saved
//  responses.
//
//  Garmin's daily Body Battery report only carries a handful of points per day (around the
//  moments the level changed direction), so the "curve" is coarse. HRV readings come every
//  five minutes, but only while asleep.
//

import Foundation

struct GarminDay: Equatable, Sendable {
  /// The user's local calendar day, "yyyy-MM-dd", as Garmin labels it.
  let calendarDate: String
  var stressLevel: Int?
  var restStressSeconds: Int?
  var lowStressSeconds: Int?
  var mediumStressSeconds: Int?
  var highStressSeconds: Int?
  var bodyBatteryCharged: Int?
  var bodyBatteryDrained: Int?
  /// HRV is labeled with the morning the night's sleep ended.
  var hrvLastNight: Int?
  var hrvWeeklyAverage: Int?
  var hrvLastNightHigh: Int?
  var hrvStatus: String?
  var hrvBaselineLow: Int?
  var hrvBaselineHigh: Int?

  init(calendarDate: String) {
    self.calendarDate = calendarDate
  }

  var hasData: Bool {
    stressLevel != nil || bodyBatteryCharged != nil || bodyBatteryDrained != nil
      || hrvLastNight != nil
  }
}

struct GarminSample: Equatable, Sendable {
  enum Kind: String, Sendable, CaseIterable {
    case bodyBattery = "body_battery"
    case hrv
  }

  let kind: Kind
  let timestamp: Date
  let value: Int
}

enum GarminDecoding {
  /// `/usersummary-service/stats/stress/daily/{start}/{end}`
  static func stressDays(from data: Data) throws -> [GarminDay] {
    guard let rows = try json(data) as? [[String: Any]] else { return [] }
    return rows.compactMap { row in
      guard let date = row["calendarDate"] as? String else { return nil }
      let values = row["values"] as? [String: Any] ?? [:]
      var day = GarminDay(calendarDate: date)
      // Garmin uses negative levels for days without enough readings.
      day.stressLevel = int(values["overallStressLevel"]).flatMap { $0 >= 0 ? $0 : nil }
      day.restStressSeconds = int(values["restStressDuration"])
      day.lowStressSeconds = int(values["lowStressDuration"])
      day.mediumStressSeconds = int(values["mediumStressDuration"])
      day.highStressSeconds = int(values["highStressDuration"])
      return day
    }
  }

  /// `/wellness-service/wellness/bodyBattery/reports/daily`
  static func bodyBattery(from data: Data) throws -> (days: [GarminDay], samples: [GarminSample])
  {
    guard let rows = try json(data) as? [[String: Any]] else { return ([], []) }
    var days: [GarminDay] = []
    var samples: [GarminSample] = []
    for row in rows {
      guard let date = row["date"] as? String else { continue }
      var day = GarminDay(calendarDate: date)
      day.bodyBatteryCharged = int(row["charged"])
      day.bodyBatteryDrained = int(row["drained"])
      days.append(day)
      samples += bodyBatterySamples(in: row)
    }
    return (days, samples)
  }

  /// Reads `bodyBatteryValuesArray` using the column order the descriptors give. Points
  /// without a level are gaps and are skipped.
  static func bodyBatterySamples(in row: [String: Any]) -> [GarminSample] {
    let descriptors = row["bodyBatteryValueDescriptorDTOList"] as? [[String: Any]] ?? []
    func column(_ key: String) -> Int? {
      descriptors.first { $0["bodyBatteryValueDescriptorKey"] as? String == key }
        .flatMap { int($0["bodyBatteryValueDescriptorIndex"]) }
    }
    guard let timeColumn = column("timestamp"), let levelColumn = column("bodyBatteryLevel"),
      let values = row["bodyBatteryValuesArray"] as? [[Any]]
    else { return [] }

    return values.compactMap { point in
      guard point.count > max(timeColumn, levelColumn),
        let millis = double(point[timeColumn]), let level = int(point[levelColumn])
      else { return nil }
      return GarminSample(
        kind: .bodyBattery, timestamp: Date(timeIntervalSince1970: millis / 1000), value: level)
    }
  }

  /// `/hrv-service/hrv/daily/{start}/{end}`. The body is the literal `null` when there is
  /// nothing yet.
  static func hrvDays(from data: Data) throws -> [GarminDay] {
    guard let body = try json(data) as? [String: Any],
      let summaries = body["hrvSummaries"] as? [[String: Any]]
    else { return [] }
    return summaries.compactMap(hrvDay)
  }

  /// `/hrv-service/hrv/{date}`: the summary plus the readings taken during sleep.
  static func hrvReadings(from data: Data) throws -> [GarminSample] {
    guard let body = try json(data) as? [String: Any],
      let readings = body["hrvReadings"] as? [[String: Any]]
    else { return [] }
    return readings.compactMap { reading in
      guard let value = int(reading["hrvValue"]),
        let time = (reading["readingTimeGMT"] as? String).flatMap(gmtDate)
      else { return nil }
      return GarminSample(kind: .hrv, timestamp: time, value: value)
    }
  }

  private static func hrvDay(_ summary: [String: Any]) -> GarminDay? {
    guard let date = summary["calendarDate"] as? String else { return nil }
    var day = GarminDay(calendarDate: date)
    day.hrvLastNight = int(summary["lastNightAvg"])
    day.hrvWeeklyAverage = int(summary["weeklyAvg"])
    day.hrvLastNightHigh = int(summary["lastNight5MinHigh"])
    day.hrvStatus = summary["status"] as? String
    let baseline = summary["baseline"] as? [String: Any] ?? [:]
    day.hrvBaselineLow = int(baseline["balancedLow"])
    day.hrvBaselineHigh = int(baseline["balancedUpper"])
    return day
  }

  /// Folds the per-endpoint rows into one row per day. Later values fill fields earlier ones
  /// left empty.
  static func merge(_ groups: [GarminDay]...) -> [GarminDay] {
    var byDate: [String: GarminDay] = [:]
    var order: [String] = []
    for day in groups.joined() {
      guard var merged = byDate[day.calendarDate] else {
        byDate[day.calendarDate] = day
        order.append(day.calendarDate)
        continue
      }
      merged.stressLevel = merged.stressLevel ?? day.stressLevel
      merged.restStressSeconds = merged.restStressSeconds ?? day.restStressSeconds
      merged.lowStressSeconds = merged.lowStressSeconds ?? day.lowStressSeconds
      merged.mediumStressSeconds = merged.mediumStressSeconds ?? day.mediumStressSeconds
      merged.highStressSeconds = merged.highStressSeconds ?? day.highStressSeconds
      merged.bodyBatteryCharged = merged.bodyBatteryCharged ?? day.bodyBatteryCharged
      merged.bodyBatteryDrained = merged.bodyBatteryDrained ?? day.bodyBatteryDrained
      merged.hrvLastNight = merged.hrvLastNight ?? day.hrvLastNight
      merged.hrvWeeklyAverage = merged.hrvWeeklyAverage ?? day.hrvWeeklyAverage
      merged.hrvLastNightHigh = merged.hrvLastNightHigh ?? day.hrvLastNightHigh
      merged.hrvStatus = merged.hrvStatus ?? day.hrvStatus
      merged.hrvBaselineLow = merged.hrvBaselineLow ?? day.hrvBaselineLow
      merged.hrvBaselineHigh = merged.hrvBaselineHigh ?? day.hrvBaselineHigh
      byDate[day.calendarDate] = merged
    }
    return order.compactMap { byDate[$0] }
  }

  // MARK: - Helpers

  private static func json(_ data: Data) throws -> Any? {
    let trimmed = data.drop { $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }
    if trimmed.isEmpty { return nil }
    let value = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    return value is NSNull ? nil : value
  }

  private static func int(_ value: Any?) -> Int? {
    guard let number = value as? NSNumber, !(value is NSNull) else { return nil }
    return number.intValue
  }

  private static func double(_ value: Any?) -> Double? {
    (value as? NSNumber)?.doubleValue
  }

  /// Garmin's `...GMT` strings look like "2026-10-28T17:52:08.0" with no zone suffix.
  static func gmtDate(_ string: String) -> Date? {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "GMT")
    for format in ["yyyy-MM-dd'T'HH:mm:ss.S", "yyyy-MM-dd'T'HH:mm:ss.SSS", "yyyy-MM-dd'T'HH:mm:ss"] {
      formatter.dateFormat = format
      if let date = formatter.date(from: string) { return date }
    }
    return nil
  }
}
