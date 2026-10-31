import XCTest

@testable import Dayflow

final class TaskHeartRateTests: XCTestCase {
  private let midnight = Date(timeIntervalSince1970: 1_800_000_000)

  private func heartRate(atMinute minute: Double, _ value: Int) -> GarminSample {
    GarminSample(kind: .heartRate, timestamp: midnight.addingTimeInterval(minute * 60), value: value)
  }

  private func card(_ start: String, _ end: String, title: String) -> TimelineCard {
    TimelineCard(
      recordId: nil, batchId: nil, startTimestamp: start, endTimestamp: end, category: "Work",
      subcategory: "Work", title: title, summary: "", detailedSummary: "", day: "2027-01-15",
      distractions: nil, videoSummaryURL: nil, otherVideoSummaryURLs: nil, appSites: nil)
  }

  // MARK: - Average

  func testAverageCountsOnlySamplesInsideTheRangeAndRoundsDown() {
    let samples = [
      heartRate(atMinute: 59, 200),
      heartRate(atMinute: 60, 70),
      heartRate(atMinute: 62, 75),
      heartRate(atMinute: 90, 200),
    ]

    let average = GarminSample.average(
      of: samples, from: midnight.addingTimeInterval(60 * 60),
      to: midnight.addingTimeInterval(90 * 60))

    XCTAssertEqual(average, 72)
  }

  func testAverageIsNilWithoutSamplesInRange() {
    let samples = [heartRate(atMinute: 10, 80)]

    XCTAssertNil(GarminSample.average([]))
    XCTAssertNil(
      GarminSample.average(
        of: samples, from: midnight.addingTimeInterval(60 * 60),
        to: midnight.addingTimeInterval(90 * 60)))
  }

  // MARK: - Detail chart

  func testStatsGiveAverageMinimumAndMaximum() {
    let stats = HeartRateStats([
      heartRate(atMinute: 0, 70), heartRate(atMinute: 2, 95), heartRate(atMinute: 4, 61),
    ])

    XCTAssertEqual(stats?.average, 75)
    XCTAssertEqual(stats?.minimum, 61)
    XCTAssertEqual(stats?.maximum, 95)
  }

  func testStatsAreNilWithoutSamples() {
    XCTAssertNil(HeartRateStats([]))
  }

  // MARK: - Workflow grid

  func testWorkflowHeartRateReadsMinutesPastMidnight() {
    let lookup = workflowHeartRate(
      samples: [heartRate(atMinute: 1440 + 30, 64), heartRate(atMinute: 600, 90)],
      dayMidnight: midnight)

    XCTAssertEqual(lookup(1440, 1500), 64)
    XCTAssertEqual(lookup(600, 630), 90)
    XCTAssertNil(lookup(700, 730))
  }

  func testSlotCardInfoCarriesTheCardsHeartRate() {
    let cards = [
      card("09:00 AM", "09:30 AM", title: "Focus"),
      card("10:00 AM", "10:30 AM", title: "Meeting"),
    ]
    let samples = [heartRate(atMinute: 9 * 60 + 10, 66), heartRate(atMinute: 10 * 60 + 10, 88)]

    let result = computeDailyWorkflow(
      cards: cards, categories: [],
      heartRate: workflowHeartRate(samples: samples, dayMidnight: midnight))

    let infos = result.rows.flatMap(\.slotCardInfos).compactMap { $0 }
    XCTAssertEqual(infos.first { $0.title == "Focus" }?.heartRate, 66)
    XCTAssertEqual(infos.first { $0.title == "Meeting" }?.heartRate, 88)
  }

  func testSlotCardInfoHasNoHeartRateByDefault() {
    let result = computeDailyWorkflow(
      cards: [card("09:00 AM", "09:30 AM", title: "Focus")], categories: [])

    let infos = result.rows.flatMap(\.slotCardInfos).compactMap { $0 }
    XCTAssertFalse(infos.isEmpty)
    XCTAssertTrue(infos.allSatisfy { $0.heartRate == nil })
  }
}
