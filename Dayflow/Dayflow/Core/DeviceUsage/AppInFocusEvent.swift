//
//  AppInFocusEvent.swift
//  Dayflow
//
//  Decodes one record of Biome's App.InFocus stream. Each record is a small
//  protobuf message; the fields used here were checked against knowledgeC's
//  /app/usage totals for the same hours on the local Mac:
//
//    2  varint   1 for apps, 3 for system overlays (Control Center, App Library)
//    3  varint   1 when the app came to the foreground, 0 when it left
//    4  double   event time, seconds since 2001-01-01
//    6  string   bundle identifier
//
//  Everything else (launch reason, app version, …) is skipped.
//

import Foundation

struct AppInFocusEvent: Equatable {
  let bundleID: String
  let timestamp: Date
  let isStarting: Bool
  /// Raw field 2; nil when the record doesn't carry it.
  let kind: Int?

  static let systemOverlayKind = 3
}

enum AppInFocusEventDecoder {
  private enum Field {
    static let kind = 2
    static let isStarting = 3
    static let timestamp = 4
    static let bundleID = 6
  }

  static func decode(_ payload: Data) -> AppInFocusEvent? {
    var reader = ProtobufReader(bytes: [UInt8](payload))
    var bundleID: String?
    var timestamp: Double?
    var isStarting: Bool?
    var kind: Int?

    while !reader.isAtEnd {
      guard let (field, value) = reader.nextField() else { return nil }
      switch (field, value) {
      case (Field.kind, .varint(let raw)):
        kind = Int(truncatingIfNeeded: raw)
      case (Field.isStarting, .varint(let raw)):
        isStarting = raw != 0
      case (Field.timestamp, .fixed64(let raw)):
        timestamp = Double(bitPattern: raw)
      case (Field.bundleID, .bytes(let raw)):
        bundleID = String(bytes: raw, encoding: .utf8)
      default:
        continue
      }
    }

    guard let bundleID, !bundleID.isEmpty, let timestamp, let isStarting,
      timestamp.isFinite, timestamp > 0
    else { return nil }
    return AppInFocusEvent(
      bundleID: bundleID,
      timestamp: Date(timeIntervalSinceReferenceDate: timestamp),
      isStarting: isStarting,
      kind: kind
    )
  }
}

/// Just enough protobuf wire-format reading for flat messages.
struct ProtobufReader {
  enum Value: Equatable {
    case varint(UInt64)
    case fixed64(UInt64)
    case fixed32(UInt32)
    case bytes([UInt8])
  }

  private let bytes: [UInt8]
  private var index = 0

  init(bytes: [UInt8]) {
    self.bytes = bytes
  }

  var isAtEnd: Bool { index >= bytes.count }

  /// The next field, or nil when the data is malformed or uses a wire type
  /// this reader doesn't know (groups are long deprecated).
  mutating func nextField() -> (Int, Value)? {
    guard let key = readVarint() else { return nil }
    let field = Int(key >> 3)
    switch key & 0x7 {
    case 0:
      return readVarint().map { (field, .varint($0)) }
    case 1:
      return readFixed(width: 8).map { (field, .fixed64($0)) }
    case 2:
      guard let length = readVarint(), length <= UInt64(bytes.count - index) else { return nil }
      let end = index + Int(length)
      defer { index = end }
      return (field, .bytes(Array(bytes[index..<end])))
    case 5:
      return readFixed(width: 4).map { (field, .fixed32(UInt32($0))) }
    default:
      return nil
    }
  }

  private mutating func readVarint() -> UInt64? {
    var result: UInt64 = 0
    var shift: UInt64 = 0
    while index < bytes.count, shift < 64 {
      let byte = bytes[index]
      index += 1
      result |= UInt64(byte & 0x7F) << shift
      if byte & 0x80 == 0 { return result }
      shift += 7
    }
    return nil
  }

  private mutating func readFixed(width: Int) -> UInt64? {
    guard index + width <= bytes.count else { return nil }
    var result: UInt64 = 0
    for offset in 0..<width {
      result |= UInt64(bytes[index + offset]) << (8 * UInt64(offset))
    }
    index += width
    return result
  }
}
