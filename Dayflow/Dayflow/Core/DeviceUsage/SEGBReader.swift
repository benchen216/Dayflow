//
//  SEGBReader.swift
//  Dayflow
//
//  Reads Apple's SEGB v2 container, the on-disk format Biome uses for its
//  event streams (~/Library/Biome/streams/...). The format is private and
//  undocumented; this mirrors the layout described by ccl_segb:
//
//    [0..32)   header: "SEGB", entry count (u32 LE), creation time (f64), padding
//    [32..)    records: crc32 (u32), unknown (u32), payload, padded to 4 bytes
//    trailer   `count` 16-byte entries at the end of the file, newest first:
//              end offset relative to byte 32 (u32), state (u32), created (f64)
//
//  Only state 1 ("written") entries carry live payloads. Anything that doesn't
//  match this shape is rejected rather than guessed at, so an OS update that
//  changes the format surfaces as an import error instead of bad data.
//

import Foundation

struct SEGBRecord: Equatable {
  /// Seconds since 2001-01-01 (Cocoa reference date), as Biome stores it.
  let createdAt: Double
  let payload: Data
}

enum SEGBReaderError: Error, Equatable {
  case badMagic
  case truncated
  case badEntry(index: Int)
}

enum SEGBReader {
  static let magic = Data("SEGB".utf8)
  static let headerSize = 32
  static let trailerEntrySize = 16
  static let recordHeaderSize = 8
  static let writtenState: UInt32 = 1

  static func records(atPath path: String) throws -> [SEGBRecord] {
    let data = try Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe)
    return try records(in: data)
  }

  static func records(in data: Data) throws -> [SEGBRecord] {
    let bytes = [UInt8](data)
    guard bytes.count >= headerSize else { throw SEGBReaderError.truncated }
    guard Data(bytes[0..<4]) == magic else { throw SEGBReaderError.badMagic }

    let count = Int(readUInt32(bytes, at: 4))
    let trailerStart = bytes.count - count * trailerEntrySize
    guard count >= 0, trailerStart >= headerSize else { throw SEGBReaderError.truncated }

    // The trailer lists entries newest-first; walk it oldest-first so each
    // record starts where the previous one ended.
    var records: [SEGBRecord] = []
    records.reserveCapacity(count)
    var recordStart = 0
    for index in (0..<count).reversed() {
      let entryOffset = trailerStart + index * trailerEntrySize
      let end = Int(readUInt32(bytes, at: entryOffset))
      let state = readUInt32(bytes, at: entryOffset + 4)
      let createdAt = readFloat64(bytes, at: entryOffset + 8)

      let payloadStart = headerSize + recordStart + recordHeaderSize
      let payloadEnd = headerSize + end
      let isInBounds = payloadStart <= payloadEnd && payloadEnd <= trailerStart
      guard isInBounds else {
        // A full segment closes with a non-written entry whose end offset is
        // 0. Only a written entry out of bounds means the layout is wrong.
        if state == writtenState { throw SEGBReaderError.badEntry(index: count - 1 - index) }
        continue
      }

      if state == writtenState {
        records.append(
          SEGBRecord(createdAt: createdAt, payload: Data(bytes[payloadStart..<payloadEnd])))
      }
      recordStart = (end + 3) & ~3
    }
    return records
  }

  private static func readUInt32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
    UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2]) << 16
      | UInt32(bytes[offset + 3]) << 24
  }

  private static func readFloat64(_ bytes: [UInt8], at offset: Int) -> Double {
    var raw: UInt64 = 0
    for shift in 0..<8 {
      raw |= UInt64(bytes[offset + shift]) << (8 * UInt64(shift))
    }
    return Double(bitPattern: raw)
  }
}
