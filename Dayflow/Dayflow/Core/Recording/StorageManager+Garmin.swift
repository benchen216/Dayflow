import Foundation
import GRDB

extension StorageManager {
  /// Upserts days and samples. Fields Garmin left empty this time keep what was stored before.
  func saveGarmin(days: [GarminDay], samples: [GarminSample]) throws {
    try timedWrite("saveGarmin") { db in
      let upsertDay = try db.makeStatement(
        sql: """
              INSERT INTO garmin_days(
                  calendar_date, stress_level, rest_stress_seconds, low_stress_seconds,
                  medium_stress_seconds, high_stress_seconds, body_battery_charged,
                  body_battery_drained, hrv_last_night, hrv_weekly_avg, hrv_last_night_high,
                  hrv_status, hrv_baseline_low, hrv_baseline_high, fetched_at
              )
              VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
              ON CONFLICT(calendar_date) DO UPDATE SET
                  stress_level = COALESCE(excluded.stress_level, stress_level),
                  rest_stress_seconds = COALESCE(excluded.rest_stress_seconds, rest_stress_seconds),
                  low_stress_seconds = COALESCE(excluded.low_stress_seconds, low_stress_seconds),
                  medium_stress_seconds = COALESCE(excluded.medium_stress_seconds, medium_stress_seconds),
                  high_stress_seconds = COALESCE(excluded.high_stress_seconds, high_stress_seconds),
                  body_battery_charged = COALESCE(excluded.body_battery_charged, body_battery_charged),
                  body_battery_drained = COALESCE(excluded.body_battery_drained, body_battery_drained),
                  hrv_last_night = COALESCE(excluded.hrv_last_night, hrv_last_night),
                  hrv_weekly_avg = COALESCE(excluded.hrv_weekly_avg, hrv_weekly_avg),
                  hrv_last_night_high = COALESCE(excluded.hrv_last_night_high, hrv_last_night_high),
                  hrv_status = COALESCE(excluded.hrv_status, hrv_status),
                  hrv_baseline_low = COALESCE(excluded.hrv_baseline_low, hrv_baseline_low),
                  hrv_baseline_high = COALESCE(excluded.hrv_baseline_high, hrv_baseline_high),
                  fetched_at = excluded.fetched_at
          """)
      let fetchedAt = Int(Date().timeIntervalSince1970)
      for day in days {
        try upsertDay.execute(arguments: [
          day.calendarDate, day.stressLevel, day.restStressSeconds, day.lowStressSeconds,
          day.mediumStressSeconds, day.highStressSeconds, day.bodyBatteryCharged,
          day.bodyBatteryDrained, day.hrvLastNight, day.hrvWeeklyAverage, day.hrvLastNightHigh,
          day.hrvStatus, day.hrvBaselineLow, day.hrvBaselineHigh, fetchedAt,
        ])
      }

      let upsertSample = try db.makeStatement(
        sql: """
              INSERT INTO garmin_samples(kind, ts, value) VALUES (?, ?, ?)
              ON CONFLICT(kind, ts) DO UPDATE SET value = excluded.value
          """)
      for sample in samples {
        try upsertSample.execute(arguments: [
          sample.kind.rawValue, Int(sample.timestamp.timeIntervalSince1970), sample.value,
        ])
      }
    }
  }

  func fetchGarminDay(_ calendarDate: String) -> GarminDay? {
    try? timedRead("fetchGarminDay") { db in
      try Row.fetchOne(
        db, sql: "SELECT * FROM garmin_days WHERE calendar_date = ?", arguments: [calendarDate]
      ).map { row in
        var day = GarminDay(calendarDate: row["calendar_date"])
        day.stressLevel = row["stress_level"]
        day.restStressSeconds = row["rest_stress_seconds"]
        day.lowStressSeconds = row["low_stress_seconds"]
        day.mediumStressSeconds = row["medium_stress_seconds"]
        day.highStressSeconds = row["high_stress_seconds"]
        day.bodyBatteryCharged = row["body_battery_charged"]
        day.bodyBatteryDrained = row["body_battery_drained"]
        day.hrvLastNight = row["hrv_last_night"]
        day.hrvWeeklyAverage = row["hrv_weekly_avg"]
        day.hrvLastNightHigh = row["hrv_last_night_high"]
        day.hrvStatus = row["hrv_status"]
        day.hrvBaselineLow = row["hrv_baseline_low"]
        day.hrvBaselineHigh = row["hrv_baseline_high"]
        return day
      }
    } ?? nil
  }

  /// Samples of one kind in [start, end), oldest first.
  func fetchGarminSamples(_ kind: GarminSample.Kind, from start: Date, to end: Date)
    -> [GarminSample]
  {
    (try? timedRead("fetchGarminSamples") { db in
      try Row.fetchAll(
        db,
        sql: """
              SELECT ts, value FROM garmin_samples
              WHERE kind = ? AND ts >= ? AND ts < ?
              ORDER BY ts ASC
          """,
        arguments: [
          kind.rawValue, Int(start.timeIntervalSince1970), Int(end.timeIntervalSince1970),
        ]
      ).map { row in
        GarminSample(
          kind: kind, timestamp: Date(timeIntervalSince1970: TimeInterval(row["ts"] as Int)),
          value: row["value"])
      }
    }) ?? []
  }

  /// The sample of one kind closest in time to `date`, within `window` either side.
  func fetchGarminSample(_ kind: GarminSample.Kind, nearest date: Date, within window: TimeInterval)
    -> GarminSample?
  {
    let samples = fetchGarminSamples(
      kind, from: date.addingTimeInterval(-window), to: date.addingTimeInterval(window))
    return samples.min {
      abs($0.timestamp.timeIntervalSince(date)) < abs($1.timestamp.timeIntervalSince(date))
    }
  }

  func garminLastFetchedAt() -> Date? {
    (try? timedRead("garminLastFetchedAt") { db in
      try Int.fetchOne(db, sql: "SELECT MAX(fetched_at) FROM garmin_days")
    }).flatMap { $0 }.map { Date(timeIntervalSince1970: TimeInterval($0)) }
  }

  func deleteAllGarmin() {
    try? timedWrite("deleteAllGarmin") { db in
      try db.execute(sql: "DELETE FROM garmin_days")
      try db.execute(sql: "DELETE FROM garmin_samples")
    }
  }
}
