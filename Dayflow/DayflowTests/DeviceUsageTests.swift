import XCTest

@testable import Dayflow

/// Builds SEGB files and App.InFocus payloads in memory, so tests never need
/// a real (personal) Biome stream.
private enum SEGBFixture {
  struct Entry {
    var payload: Data
    var state: UInt32 = 1
    var createdAt: Double = 800_000_000
  }

  /// `closingSentinel` adds the end=0, state=4 entry Biome writes when a
  /// segment fills up.
  static func file(_ entries: [Entry], closingSentinel: Bool = false) -> Data {
    var body = Data()
    var trailer: [(end: UInt32, state: UInt32, createdAt: Double)] = []
    for entry in entries {
      body.append(le32(0xDEAD_BEEF))  // crc, unchecked
      body.append(le32(10))  // unknown header word
      body.append(entry.payload)
      trailer.append((UInt32(body.count), entry.state, entry.createdAt))
      while body.count % 4 != 0 { body.append(0) }
    }
    if closingSentinel {
      trailer.append((0, 4, 0))
    }

    var data = Data("SEGB".utf8)
    data.append(le32(UInt32(trailer.count)))
    data.append(le64(800_000_000))
    data.append(Data(count: 16))
    data.append(body)
    data.append(Data(count: 64))  // unused space before the trailer
    for item in trailer.reversed() {  // newest first, like Biome
      data.append(le32(item.end))
      data.append(le32(item.state))
      data.append(le64(item.createdAt))
    }
    return data
  }

  static func appEvent(
    bundleID: String, at time: Date, starting: Bool, kind: UInt64 = 1
  ) -> Data {
    var data = Data()
    data.append(key(1, wire: 2))
    data.append(lengthDelimited(Data("SBSceneLayoutWorkspaceTransaction".utf8)))
    data.append(key(2, wire: 0))
    data.append(varint(kind))
    data.append(key(3, wire: 0))
    data.append(varint(starting ? 1 : 0))
    data.append(key(4, wire: 1))
    data.append(le64(time.timeIntervalSinceReferenceDate))
    data.append(key(6, wire: 2))
    data.append(lengthDelimited(Data(bundleID.utf8)))
    data.append(key(9, wire: 2))
    data.append(lengthDelimited(Data("1.0".utf8)))
    data.append(key(13, wire: 0))
    data.append(varint(1))
    return data
  }

  private static func key(_ field: UInt64, wire: UInt64) -> Data { varint(field << 3 | wire) }

  private static func lengthDelimited(_ bytes: Data) -> Data {
    varint(UInt64(bytes.count)) + bytes
  }

  private static func varint(_ value: UInt64) -> Data {
    var value = value
    var data = Data()
    repeat {
      var byte = UInt8(value & 0x7F)
      value >>= 7
      if value != 0 { byte |= 0x80 }
      data.append(byte)
    } while value != 0
    return data
  }

  private static func le32(_ value: UInt32) -> Data {
    withUnsafeBytes(of: value.littleEndian) { Data($0) }
  }

  private static func le64(_ value: Double) -> Data {
    withUnsafeBytes(of: value.bitPattern.littleEndian) { Data($0) }
  }
}

private let base = Date(timeIntervalSince1970: 1_790_000_000)

private func t(_ minutes: Double) -> Date { base.addingTimeInterval(minutes * 60) }

private func event(_ bundleID: String, _ minutes: Double, _ starting: Bool, kind: Int? = 1)
  -> AppInFocusEvent
{
  AppInFocusEvent(bundleID: bundleID, timestamp: t(minutes), isStarting: starting, kind: kind)
}

final class SEGBReaderTests: XCTestCase {
  func testReadsWrittenRecordsInOrderAndSkipsDeletedOnes() throws {
    let file = SEGBFixture.file([
      .init(payload: Data([1, 2, 3])),
      .init(payload: Data([4, 5, 6, 7, 8]), state: 3),
      .init(payload: Data([9]), createdAt: 812_000_000),
    ])

    let records = try SEGBReader.records(in: file)

    XCTAssertEqual(records.map(\.payload), [Data([1, 2, 3]), Data([9])])
    XCTAssertEqual(records.last?.createdAt, 812_000_000)
  }

  func testSkipsTheSentinelThatClosesAFullSegment() throws {
    let file = SEGBFixture.file(
      [.init(payload: Data([1, 2, 3])), .init(payload: Data([4]))], closingSentinel: true)

    XCTAssertEqual(try SEGBReader.records(in: file).map(\.payload), [Data([1, 2, 3]), Data([4])])
  }

  func testRejectsFilesThatAreNotSEGB() {
    XCTAssertThrowsError(try SEGBReader.records(in: Data(repeating: 0, count: 64))) {
      XCTAssertEqual($0 as? SEGBReaderError, .badMagic)
    }
    XCTAssertThrowsError(try SEGBReader.records(in: Data("SEGB".utf8))) {
      XCTAssertEqual($0 as? SEGBReaderError, .truncated)
    }
  }

  func testRejectsEntryPointingPastTheTrailer() {
    var file = SEGBFixture.file([.init(payload: Data([1, 2, 3]))])
    let trailerStart = file.count - 16
    file.replaceSubrange(trailerStart..<trailerStart + 4, with: [0xFF, 0xFF, 0x00, 0x00])

    XCTAssertThrowsError(try SEGBReader.records(in: file)) {
      XCTAssertEqual($0 as? SEGBReaderError, .badEntry(index: 0))
    }
  }
}

final class AppInFocusEventDecoderTests: XCTestCase {
  func testDecodesBundleTimestampDirectionAndKind() {
    let payload = SEGBFixture.appEvent(
      bundleID: "com.burbn.instagram", at: t(5), starting: true, kind: 3)

    let decoded = AppInFocusEventDecoder.decode(payload)

    XCTAssertEqual(decoded?.bundleID, "com.burbn.instagram")
    XCTAssertEqual(
      decoded?.timestamp.timeIntervalSince1970 ?? 0, t(5).timeIntervalSince1970, accuracy: 0.001)
    XCTAssertEqual(decoded?.isStarting, true)
    XCTAssertEqual(decoded?.kind, 3)
  }

  func testReturnsNilForTruncatedOrIncompletePayloads() {
    let payload = SEGBFixture.appEvent(bundleID: "com.spotify.client", at: t(0), starting: false)
    XCTAssertNil(AppInFocusEventDecoder.decode(payload.prefix(payload.count - 3)))
    XCTAssertNil(AppInFocusEventDecoder.decode(Data([0x18, 0x01])))  // no bundle or time
  }

  func testRoundTripsThroughASEGBFile() throws {
    let file = SEGBFixture.file([
      .init(payload: SEGBFixture.appEvent(bundleID: "jp.naver.line", at: t(0), starting: true)),
      .init(payload: SEGBFixture.appEvent(bundleID: "jp.naver.line", at: t(2), starting: false)),
    ])

    let events = try SEGBReader.records(in: file).compactMap {
      AppInFocusEventDecoder.decode($0.payload)
    }

    XCTAssertEqual(events.map(\.isStarting), [true, false])
    XCTAssertEqual(
      DeviceAppSessionBuilder.sessions(from: events, deviceID: "phone").map(\.duration), [120])
  }
}

final class DeviceAppSessionBuilderTests: XCTestCase {
  func testPairsForegroundAndBackgroundEvents() {
    let sessions = DeviceAppSessionBuilder.sessions(
      from: [
        event("com.burbn.instagram", 0, true),
        event("com.burbn.instagram", 3, false),
        event("com.google.Maps", 4, true),
        event("com.google.Maps", 5, false),
      ], deviceID: "phone")

    XCTAssertEqual(sessions.map(\.bundleID), ["com.burbn.instagram", "com.google.Maps"])
    XCTAssertEqual(sessions.map(\.duration), [180, 60])
  }

  func testLockScreenEndsTheOpenAppAndIsNotCounted() {
    let sessions = DeviceAppSessionBuilder.sessions(
      from: [
        event("com.google.ios.youtube", 0, true),
        event("com.apple.SleepLockScreen", 10, true),
        event("com.apple.SleepLockScreen", 40, false),
      ], deviceID: "phone")

    XCTAssertEqual(sessions.count, 1)
    XCTAssertEqual(sessions.first?.duration, 600)
  }

  func testSystemOverlaysAndServiceSheetsAreExcluded() {
    XCTAssertTrue(DeviceAppSessionBuilder.isExcluded(event("com.apple.control-center", 0, true, kind: 3)))
    XCTAssertTrue(DeviceAppSessionBuilder.isExcluded(event("com.apple.springboard.today-view", 0, true)))
    XCTAssertTrue(DeviceAppSessionBuilder.isExcluded(event("com.apple.PassbookUIService", 0, true)))
    XCTAssertFalse(DeviceAppSessionBuilder.isExcluded(event("com.apple.mobilesafari", 0, true)))
    XCTAssertFalse(DeviceAppSessionBuilder.isExcluded(event("com.apple.InCallService", 0, true)))
  }

  func testUnmatchedForegroundIsClosedByNextAppAndDuplicatesIgnored() {
    let sessions = DeviceAppSessionBuilder.sessions(
      from: [
        event("com.spotify.client", 0, true),
        event("com.spotify.client", 1, true),
        event("com.apple.MobileSMS", 6, true),
        event("com.apple.MobileSMS", 7, false),
      ], deviceID: "phone")

    XCTAssertEqual(sessions.map(\.bundleID), ["com.spotify.client", "com.apple.MobileSMS"])
    XCTAssertEqual(sessions.first?.duration, 360)
  }

  func testLongUnmatchedSessionIsCappedAndTrailingOpenSessionIsDropped() {
    let sessions = DeviceAppSessionBuilder.sessions(
      from: [
        event("com.netflix.Netflix", 0, true),
        event("com.apple.mobilesafari", 600, true),
      ], deviceID: "phone")

    XCTAssertEqual(sessions.count, 1)
    XCTAssertEqual(sessions.first?.duration, DeviceAppSessionBuilder.maxSessionDuration)
  }

  func testOutOfOrderEventsAreSortedBeforePairing() {
    let sessions = DeviceAppSessionBuilder.sessions(
      from: [
        event("com.google.Gmail", 2, false),
        event("com.google.Gmail", 0, true),
      ], deviceID: "phone")

    XCTAssertEqual(sessions.map(\.duration), [120])
  }
}

final class DeviceUsageSummaryBuilderTests: XCTestCase {
  private func session(_ bundleID: String, _ start: Double, _ end: Double, device: String = "phone")
    -> DeviceAppSession
  {
    DeviceAppSession(deviceID: device, bundleID: bundleID, start: t(start), end: t(end))
  }

  func testDaySummaryClipsToTheDayAndRanksApps() {
    let devices = [
      UsageDevice(deviceID: "phone", model: "iPhone17,1", lastEventAt: t(90), importedAt: nil),
      UsageDevice(deviceID: "ipad", model: "iPad13,4", lastEventAt: t(10), importedAt: nil),
    ]
    let summary = DeviceUsageSummaryBuilder.daySummary(
      sessions: [
        session("com.burbn.instagram", -10, 10),  // starts before the day
        session("com.burbn.instagram", 20, 30),
        session("jp.naver.line", 30.5, 45),  // app switch, same pickup
      ],
      dayStart: t(0), dayEnd: t(60), devices: devices)

    XCTAssertEqual(summary.total, 34.5 * 60, accuracy: 0.001)
    XCTAssertEqual(summary.pickups, 2)
    XCTAssertEqual(summary.topApps.map(\.bundleID), ["com.burbn.instagram", "jp.naver.line"])
    XCTAssertEqual(summary.topApps.first?.duration, 20 * 60)
    XCTAssertEqual(summary.devices.map(\.deviceID), ["phone"])
    XCTAssertEqual(summary.lastSyncedAt, t(90))
  }

  func testBlocksMergeShortGapsAndDropSlivers() {
    let blocks = DeviceUsageSummaryBuilder.blocks(
      sessions: [
        session("com.burbn.instagram", 0, 5),
        session("com.google.ios.youtube", 6, 12),  // 1 min gap: merged
        session("com.apple.camera", 30, 30.5),  // 30s on its own: too short to draw
        session("com.apple.mobilesafari", 50, 55),
      ],
      dayStart: t(0), dayEnd: t(120))

    XCTAssertEqual(blocks.count, 2)
    XCTAssertEqual(blocks.first?.duration, 12 * 60)
    XCTAssertEqual(blocks.first?.apps.first?.bundleID, "com.google.ios.youtube")
  }

  func testAppNamesUseKnownNamesThenTheMeaningfulBundleComponent() {
    XCTAssertEqual(DeviceAppNames.displayName(for: "com.burbn.instagram"), "Instagram")
    XCTAssertEqual(DeviceAppNames.displayName(for: "com.example.ios.client"), "Example")
    XCTAssertEqual(DeviceAppNames.displayName(for: "io.todoist"), "Todoist")
  }

  func testDeviceKindFromModel() {
    XCTAssertEqual(UsageDeviceKind(model: "iPhone17,1"), .iPhone)
    XCTAssertEqual(UsageDeviceKind(model: "iPad13,4"), .iPad)
    XCTAssertEqual(UsageDeviceKind(model: "Mac14,12"), .other)
    XCTAssertEqual(UsageDeviceKind(model: nil), .other)
  }
}
