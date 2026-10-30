import XCTest

@testable import Dayflow

/// Shapes copied from real Personal API responses, with made-up numbers.
final class GarminSyncTests: XCTestCase {
  private static let stress = """
    [{"calendarDate":"2026-10-29","values":{"highStressDuration":3780,"lowStressDuration":11940,
    "overallStressLevel":43,"restStressDuration":10920,"mediumStressDuration":10800}}]
    """

  private static let bodyBattery = """
    [{"date":"2026-10-29","charged":30,"drained":60,
      "bodyBatteryValueDescriptorDTOList":[
        {"bodyBatteryValueDescriptorIndex":1,"bodyBatteryValueDescriptorKey":"bodyBatteryLevel"},
        {"bodyBatteryValueDescriptorIndex":0,"bodyBatteryValueDescriptorKey":"timestamp"}],
      "bodyBatteryValuesArray":[[1793206980000,11],[1793222100000,null],[1793259000000,8]]}]
    """

  private static let hrvDaily = """
    {"hrvSummaries":[{"calendarDate":"2026-10-29","weeklyAvg":67,"lastNightAvg":51,
    "lastNight5MinHigh":82,"baseline":{"lowUpper":55,"balancedLow":59,"balancedUpper":74},
    "status":"BALANCED"}],"userProfilePk":1}
    """

  private static let hrvDay = """
    {"hrvSummary":{"calendarDate":"2026-10-29"},"hrvReadings":[
      {"hrvValue":41,"readingTimeGMT":"2026-10-28T17:52:08.0"},
      {"hrvValue":55,"readingTimeGMT":"2026-10-28T17:57:08.0"}]}
    """

  // MARK: - Decoding

  func testStressDays() throws {
    let days = try GarminDecoding.stressDays(from: Data(Self.stress.utf8))
    XCTAssertEqual(days.count, 1)
    XCTAssertEqual(days[0].calendarDate, "2026-10-29")
    XCTAssertEqual(days[0].stressLevel, 43)
    XCTAssertEqual(days[0].highStressSeconds, 3780)
  }

  func testBodyBatteryFollowsDescriptorOrderAndSkipsGaps() throws {
    let result = try GarminDecoding.bodyBattery(from: Data(Self.bodyBattery.utf8))
    XCTAssertEqual(result.days.first?.bodyBatteryCharged, 30)
    XCTAssertEqual(result.days.first?.bodyBatteryDrained, 60)
    XCTAssertEqual(result.samples.map(\.value), [11, 8])
    // Epoch milliseconds in UTC: 01:03 in Taiwan on the 29th.
    XCTAssertEqual(
      result.samples.first?.timestamp, ISO8601DateFormatter().date(from: "2026-10-28T17:03:00Z"))
  }

  func testHRVSummaryAndReadings() throws {
    let day = try XCTUnwrap(GarminDecoding.hrvDays(from: Data(Self.hrvDaily.utf8)).first)
    XCTAssertEqual(day.hrvLastNight, 51)
    XCTAssertEqual(day.hrvWeeklyAverage, 67)
    XCTAssertEqual(day.hrvStatus, "BALANCED")
    XCTAssertEqual(day.hrvBaselineLow, 59)
    XCTAssertEqual(day.hrvBaselineHigh, 74)

    let readings = try GarminDecoding.hrvReadings(from: Data(Self.hrvDay.utf8))
    XCTAssertEqual(readings.map(\.value), [41, 55])
    XCTAssertEqual(
      readings.first?.timestamp, ISO8601DateFormatter().date(from: "2026-10-28T17:52:08Z"))
  }

  func testNullAndEmptyBodiesMeanNoData() throws {
    XCTAssertEqual(try GarminDecoding.hrvDays(from: Data("null".utf8)), [])
    XCTAssertEqual(try GarminDecoding.hrvReadings(from: Data()), [])
    XCTAssertEqual(try GarminDecoding.stressDays(from: Data("[]".utf8)), [])
    let unmeasured = #"[{"calendarDate":"2026-10-30","values":{"overallStressLevel":-1}}]"#
    XCTAssertNil(try GarminDecoding.stressDays(from: Data(unmeasured.utf8)).first?.stressLevel)
  }

  func testMergeFoldsEndpointsIntoOneRowPerDay() throws {
    let merged = GarminDecoding.merge(
      try GarminDecoding.stressDays(from: Data(Self.stress.utf8)),
      try GarminDecoding.bodyBattery(from: Data(Self.bodyBattery.utf8)).days,
      try GarminDecoding.hrvDays(from: Data(Self.hrvDaily.utf8)))
    XCTAssertEqual(merged.count, 1)
    XCTAssertEqual(merged[0].stressLevel, 43)
    XCTAssertEqual(merged[0].bodyBatteryCharged, 30)
    XCTAssertEqual(merged[0].hrvLastNight, 51)
  }

  func testTokenIsTheBareResponseBody() {
    XCTAssertEqual(GarminAPI.tokenValue(from: Data("eyJ.abc.def\n".utf8)), "eyJ.abc.def")
    XCTAssertEqual(GarminAPI.tokenValue(from: Data("\"eyJ.abc\"".utf8)), "eyJ.abc")
    XCTAssertEqual(GarminAPI.tokenValue(from: Data(#"{"access_token":"t"}"#.utf8)), "t")
    XCTAssertNil(GarminAPI.tokenValue(from: Data()))
  }

  func testRecentDaysAreLocalCalendarDatesOldestFirst() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Taipei")!
    let date = ISO8601DateFormatter().date(from: "2026-10-29T17:00:00Z")!  // 01:00 on the 30th
    XCTAssertEqual(
      GarminSyncService.recentDays(3, endingAt: date, calendar: calendar),
      ["2026-10-28", "2026-10-29", "2026-10-30"])
  }

  // MARK: - Token handling

  func testExpiredTokenIsExchangedAgainOnce() async throws {
    let transport = StubTransport(routes: [
      "token": [(Data("t1".utf8), 200), (Data("t2".utf8), 200)],
      "stress": [(Data(), 401), (Data(Self.stress.utf8), 200)],
      "bodyBattery": [(Data("[]".utf8), 200)],
      "hrv/daily": [(Data("null".utf8), 200)],
    ])
    let api = GarminAPI(transport: transport, apiKey: { "key" })
    let result = try await api.fetch(days: ["2026-10-29"])
    XCTAssertEqual(result.days.first?.stressLevel, 43)
    let tokens = await transport.bearerTokens
    XCTAssertEqual(tokens, ["Bearer t1", "Bearer t2", "Bearer t2", "Bearer t2"])
  }

  func testRejectedKeyIsReported() async {
    let transport = StubTransport(routes: ["token": [(Data(), 401)]])
    let api = GarminAPI(transport: transport, apiKey: { "old-key" })
    do {
      _ = try await api.fetch(days: ["2026-10-29"])
      XCTFail("Expected keyRejected")
    } catch {
      XCTAssertEqual(error as? GarminAPIError, .keyRejected)
    }
  }

  func testMissingKeyIsReportedWithoutCallingGarmin() async {
    let transport = StubTransport(routes: [:])
    let api = GarminAPI(transport: transport, apiKey: { nil })
    do {
      _ = try await api.fetch(days: ["2026-10-29"])
      XCTFail("Expected keyRejected")
    } catch {
      XCTAssertEqual(error as? GarminAPIError, .keyRejected)
    }
    let calls = await transport.callCount
    XCTAssertEqual(calls, 0)
  }
}

/// Answers by matching a fragment of the path, in order, repeating the last answer.
private actor StubTransport: GarminTransport {
  private var routes: [String: [(Data, Int)]]
  private(set) var bearerTokens: [String] = []
  private(set) var callCount = 0

  init(routes: [String: [(Data, Int)]]) { self.routes = routes }

  nonisolated func send(_ request: URLRequest) async throws -> (Data, Int) {
    try await answer(request)
  }

  private func answer(_ request: URLRequest) throws -> (Data, Int) {
    callCount += 1
    let path = request.url?.path ?? ""
    let key: String
    if path.hasSuffix("/token") {
      key = "token"
    } else {
      if let auth = request.value(forHTTPHeaderField: "Authorization") { bearerTokens.append(auth) }
      key =
        path.contains("stress") ? "stress"
        : path.contains("bodyBattery") ? "bodyBattery"
        : path.contains("hrv/daily") ? "hrv/daily" : path
    }
    guard var answers = routes[key], let first = answers.first else {
      throw URLError(.unsupportedURL)
    }
    if answers.count > 1 { answers.removeFirst() }
    routes[key] = answers
    return first
  }
}
