import XCTest

@testable import Dayflow

final class DailyMoodLogTests: XCTestCase {
  private let dayStart = Date(timeIntervalSince1970: 1_800_000_000)
  private var dayEnd: Date { dayStart.addingTimeInterval(24 * 60 * 60) }

  private func note(
    title: String, at offset: TimeInterval, duration: TimeInterval = 300,
    emotions: [EmotionSample]
  ) -> VoiceNote {
    VoiceNote(
      id: UUID(), title: title, createdAt: dayStart.addingTimeInterval(offset), duration: duration,
      transcript: [TranscriptSegment(offset: 0, duration: 5, text: "Private words")],
      emotions: emotions, usedCamera: true, notes: nil, notesGeneratedAt: nil)
  }

  private func sample(_ source: EmotionSource, _ label: EmotionLabel) -> EmotionSample {
    EmotionSample(offset: 0, source: source, label: label, confidence: 0.8)
  }

  private func noHeartRate(_: Date, _: Date) -> [GarminSample] { [] }

  // MARK: - Building the log

  func testKeepsOnlyTheDaysNotesWithMoodsOldestFirst() {
    let notes = [
      note(title: "Afternoon", at: 6 * 3600, emotions: [sample(.voice, .calm)]),
      note(title: "Morning", at: 3600, emotions: [sample(.voice, .tense)]),
      note(title: "No mood", at: 7200, emotions: []),
      note(title: "Day before", at: -3600, emotions: [sample(.voice, .happy)]),
      note(title: "Next day", at: 24 * 3600, emotions: [sample(.voice, .happy)]),
    ]

    let log = DailyMoodLog.make(notes: notes, from: dayStart, to: dayEnd, heartRate: noHeartRate)

    XCTAssertEqual(log.entries.map(\.title), ["Morning", "Afternoon"])
  }

  func testEntryHasDominantMoodPerSource() {
    let notes = [
      note(
        title: "Sync", at: 3600,
        emotions: [
          sample(.voice, .tense), sample(.voice, .tense), sample(.voice, .calm),
          sample(.face, .happy), sample(.words, .neutral),
        ])
    ]

    let entry = DailyMoodLog.make(
      notes: notes, from: dayStart, to: dayEnd, heartRate: noHeartRate
    ).entries.first

    XCTAssertEqual(entry?.voice, .tense)
    XCTAssertEqual(entry?.face, .happy)
    XCTAssertEqual(entry?.words, .neutral)
  }

  func testHeartRateIsTheAverageAroundTheRecordingAndNilWithoutSamples() {
    let recorded = note(title: "Sync", at: 3600, duration: 600, emotions: [sample(.voice, .calm)])
    var asked: (Date, Date)?
    let withData = DailyMoodLog.make(notes: [recorded], from: dayStart, to: dayEnd) { start, end in
      asked = (start, end)
      return [80, 90, 101].map { GarminSample(kind: .heartRate, timestamp: start, value: $0) }
    }

    XCTAssertEqual(withData.entries.first?.heartRate, 90)
    XCTAssertEqual(asked?.0, recorded.createdAt.addingTimeInterval(-DailyMoodLog.heartRateMargin))
    XCTAssertEqual(
      asked?.1, recorded.createdAt.addingTimeInterval(600 + DailyMoodLog.heartRateMargin))

    let withoutData = DailyMoodLog.make(
      notes: [recorded], from: dayStart, to: dayEnd, heartRate: noHeartRate)
    XCTAssertNil(withoutData.entries.first?.heartRate)
  }

  // MARK: - Prompt text

  func testPromptTextListsMoodsAndHeartRateButNoTranscript() {
    let notes = [
      note(title: "Planning", at: 3600, emotions: [sample(.voice, .tense), sample(.face, .calm)])
    ]
    let log = DailyMoodLog.make(notes: notes, from: dayStart, to: dayEnd) { start, _ in
      [GarminSample(kind: .heartRate, timestamp: start, value: 88)]
    }

    let text = log.promptText(day: "2027-01-15")

    XCTAssertTrue(text.contains("Mood log for 2027-01-15"))
    XCTAssertTrue(text.contains("\"Planning\": voice tense, face calm, heart rate 88 bpm"))
    XCTAssertTrue(text.contains("Whole day: calm 50%, tense 50%"))
    XCTAssertFalse(text.contains("Private words"))
  }

  func testEmptyLogHasNoPromptTextOrSummary() {
    let log = DailyMoodLog.make(notes: [], from: dayStart, to: dayEnd, heartRate: noHeartRate)

    XCTAssertTrue(log.isEmpty)
    XCTAssertEqual(log.promptText(day: "2027-01-15"), "")
    XCTAssertNil(log.summarySentence())
  }

  func testSummarySentenceNamesTheDominantMood() {
    let notes = [
      note(title: "A", at: 3600, emotions: [sample(.voice, .calm), sample(.voice, .calm)]),
      note(title: "B", at: 7200, emotions: [sample(.voice, .tense)]),
    ]
    let log = DailyMoodLog.make(notes: notes, from: dayStart, to: dayEnd, heartRate: noHeartRate)

    let sentence = log.summarySentence()

    XCTAssertNotNil(sentence)
    XCTAssertTrue(sentence?.localizedCaseInsensitiveContains(EmotionLabel.calm.displayName) == true)
    XCTAssertTrue(sentence?.contains("2") == true)
  }

  // MARK: - Recap prompt and draft

  func testRecapPromptIsUnchangedWithoutMood() {
    let plain = DailyRecapGenerator.makeLocalPrompt(day: "2027-01-15", cards: [])
    let empty = DailyRecapGenerator.makeLocalPrompt(day: "2027-01-15", cards: [], moodText: "")

    XCTAssertEqual(plain, empty)
    XCTAssertFalse(plain.contains("\"mood\""))
    XCTAssertFalse(plain.contains("## Mood"))
  }

  func testRecapPromptAsksForMoodWhenThereIsALog() {
    let prompt = DailyRecapGenerator.makeLocalPrompt(
      day: "2027-01-15", cards: [], provider: .claude, moodText: "Mood log for 2027-01-15")

    XCTAssertTrue(prompt.contains("## Mood\n\nMood log for 2027-01-15"))
    XCTAssertTrue(prompt.contains("\"next\": \"one sentence or null\",\n  \"mood\": \"one sentence or null\""))
    XCTAssertTrue(prompt.contains("Never mention mood in \"done\" or \"next\""))
  }

  func testDraftsSavedBeforeMoodStillDecode() throws {
    let json = """
      {"highlightsTitle":"H","highlights":[],"tasksTitle":"T","tasks":[],
       "blockersTitle":"B","blockersBody":""}
      """
    let draft = try JSONDecoder().decode(DailyStandupDraft.self, from: Data(json.utf8))
    XCTAssertNil(draft.mood)

    var withMood = draft
    withMood.mood = "A calm day."
    let roundTrip = try JSONDecoder().decode(
      DailyStandupDraft.self, from: Data(withMood.encodedJSONString()!.utf8))
    XCTAssertEqual(roundTrip.mood, "A calm day.")
  }
}
