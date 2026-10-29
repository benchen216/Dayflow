import Foundation
import GRDB

extension StorageManager {
  /// Sessions from other devices that overlap [start, end), oldest first.
  func fetchDeviceAppSessions(from start: Date, to end: Date) -> [DeviceAppSession] {
    (try? timedRead("fetchDeviceAppSessions") { db in
      try Row.fetchAll(
        db,
        sql: """
              SELECT device_id, bundle_id, start_ts, end_ts
              FROM device_app_sessions
              WHERE start_ts < ? AND end_ts > ?
              ORDER BY start_ts ASC
          """,
        arguments: [Int(end.timeIntervalSince1970), Int(start.timeIntervalSince1970)]
      ).map { row in
        DeviceAppSession(
          deviceID: row["device_id"],
          bundleID: row["bundle_id"],
          start: Date(timeIntervalSince1970: TimeInterval(row["start_ts"] as Int)),
          end: Date(timeIntervalSince1970: TimeInterval(row["end_ts"] as Int))
        )
      }
    }) ?? []
  }

  func fetchUsageDevices() -> [UsageDevice] {
    (try? timedRead("fetchUsageDevices") { db in
      try Row.fetchAll(
        db,
        sql: """
              SELECT device_id, model, last_event_ts, imported_at
              FROM device_usage_devices
              ORDER BY device_id
          """
      ).map { row in
        let lastEvent: Int? = row["last_event_ts"]
        let importedAt: Int? = row["imported_at"]
        return UsageDevice(
          deviceID: row["device_id"],
          model: row["model"],
          lastEventAt: lastEvent.map { Date(timeIntervalSince1970: TimeInterval($0)) },
          importedAt: importedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        )
      }
    }) ?? []
  }

  /// The source signature recorded at the last import, so unchanged devices
  /// can be skipped without re-reading their files.
  func deviceUsageSourceSignature(deviceID: String) -> String? {
    try? timedRead("deviceUsageSourceSignature") { db in
      try String.fetchOne(
        db,
        sql: "SELECT source_signature FROM device_usage_devices WHERE device_id = ?",
        arguments: [deviceID]
      )
    }
  }

  /// Replaces a device's sessions from `coveredFrom` onward with `sessions`.
  /// Older rows stay: Biome prunes old segments, and Dayflow keeps the history.
  func replaceDeviceAppSessions(
    _ sessions: [DeviceAppSession],
    deviceID: String,
    model: String?,
    coveredFrom: Date?,
    lastEventAt: Date?,
    sourceSignature: String
  ) throws {
    try timedWrite("replaceDeviceAppSessions") { db in
      if let coveredFrom {
        try db.execute(
          sql: "DELETE FROM device_app_sessions WHERE device_id = ? AND start_ts >= ?",
          arguments: [deviceID, Int(coveredFrom.timeIntervalSince1970)]
        )
      }

      let insert = try db.makeStatement(
        sql: """
              INSERT INTO device_app_sessions(device_id, bundle_id, start_ts, end_ts)
              VALUES (?, ?, ?, ?)
              ON CONFLICT(device_id, start_ts) DO UPDATE SET
                  bundle_id = excluded.bundle_id,
                  end_ts = excluded.end_ts
          """)
      for session in sessions where session.deviceID == deviceID {
        try insert.execute(arguments: [
          deviceID,
          session.bundleID,
          Int(session.start.timeIntervalSince1970),
          Int(session.end.timeIntervalSince1970),
        ])
      }

      try db.execute(
        sql: """
              INSERT INTO device_usage_devices(
                  device_id, model, last_event_ts, imported_at, source_signature
              )
              VALUES (?, ?, ?, ?, ?)
              ON CONFLICT(device_id) DO UPDATE SET
                  model = COALESCE(excluded.model, device_usage_devices.model),
                  last_event_ts = MAX(
                      COALESCE(excluded.last_event_ts, 0),
                      COALESCE(device_usage_devices.last_event_ts, 0)
                  ),
                  imported_at = excluded.imported_at,
                  source_signature = excluded.source_signature
          """,
        arguments: [
          deviceID,
          model,
          lastEventAt.map { Int($0.timeIntervalSince1970) },
          Int(Date().timeIntervalSince1970),
          sourceSignature,
        ])
    }
  }

  func deleteAllDeviceUsage() {
    try? timedWrite("deleteAllDeviceUsage") { db in
      try db.execute(sql: "DELETE FROM device_app_sessions")
      try db.execute(sql: "DELETE FROM device_usage_devices")
    }
  }
}
