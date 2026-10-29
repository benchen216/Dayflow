import XCTest

@testable import Dayflow

final class VoiceNotesTests: XCTestCase {
  // MARK: - Voice mood

  private func warmBaseline() -> VoiceBaseline {
    let typical = VoiceFeatures(loudnessDB: -30, pitchHz: 150, pitchVariation: 0.15, voicedRatio: 0.8)
    return (0..<VoiceBaseline.warmupWindows).reduce(VoiceBaseline()) { baseline, _ in
      baseline.adding(typical)
    }
  }

  func testVoiceEstimateSkipsSilenceAndColdBaseline() {
    let speech = VoiceFeatures(loudnessDB: -30, pitchHz: 150, pitchVariation: 0.15, voicedRatio: 0.8)
    XCTAssertNil(VoiceEmotionEstimator.estimate(speech, baseline: VoiceBaseline()))

    let silence = VoiceFeatures(loudnessDB: -70, pitchHz: 0, pitchVariation: 0, voicedRatio: 0.05)
    XCTAssertNil(VoiceEmotionEstimator.estimate(silence, baseline: warmBaseline()))
  }

  func testVoiceAtBaselineIsNeutral() {
    let speech = VoiceFeatures(loudnessDB: -30, pitchHz: 150, pitchVariation: 0.15, voicedRatio: 0.8)
    XCTAssertEqual(VoiceEmotionEstimator.estimate(speech, baseline: warmBaseline())?.label, .neutral)
  }

  func testLouderAndHigherVoiceIsEnergizedWhenLivelyAndTenseWhenFlat() {
    let lively = VoiceFeatures(loudnessDB: -22, pitchHz: 175, pitchVariation: 0.25, voicedRatio: 0.9)
    XCTAssertEqual(VoiceEmotionEstimator.estimate(lively, baseline: warmBaseline())?.label, .energized)

    let flat = VoiceFeatures(loudnessDB: -22, pitchHz: 175, pitchVariation: 0.08, voicedRatio: 0.9)
    XCTAssertEqual(VoiceEmotionEstimator.estimate(flat, baseline: warmBaseline())?.label, .tense)
  }

  func testQuieterVoiceIsLowWhenMonotoneAndCalmOtherwise() {
    let monotone = VoiceFeatures(loudnessDB: -40, pitchHz: 130, pitchVariation: 0.05, voicedRatio: 0.6)
    XCTAssertEqual(VoiceEmotionEstimator.estimate(monotone, baseline: warmBaseline())?.label, .low)

    let soft = VoiceFeatures(loudnessDB: -40, pitchHz: 130, pitchVariation: 0.15, voicedRatio: 0.6)
    XCTAssertEqual(VoiceEmotionEstimator.estimate(soft, baseline: warmBaseline())?.label, .calm)
  }

  func testVoiceConfidenceStaysInRange() {
    let extreme = VoiceFeatures(loudnessDB: 0, pitchHz: 400, pitchVariation: 1, voicedRatio: 1)
    let confidence = VoiceEmotionEstimator.estimate(extreme, baseline: warmBaseline())?.confidence
    XCTAssertEqual(confidence, 1)
  }

  // MARK: - Face mood

  private let restingFace = FaceMetrics(
    mouthCornerLift: 0, mouthOpenness: 0.01, eyeOpenness: 0.3, browRaise: 0.1)

  private func warmFaceBaseline() -> FaceBaseline {
    (0..<FaceBaseline.warmupFrames).reduce(FaceBaseline()) { baseline, _ in
      baseline.adding(restingFace)
    }
  }

  func testFaceEstimateNeedsWarmBaseline() {
    XCTAssertNil(FaceEmotionEstimator.estimate(restingFace, baseline: FaceBaseline()))
    XCTAssertEqual(FaceEmotionEstimator.estimate(restingFace, baseline: warmFaceBaseline())?.label, .calm)
  }

  func testSmileIsHappyAndLoweredBrowIsTense() {
    let smile = FaceMetrics(mouthCornerLift: 0.05, mouthOpenness: 0.01, eyeOpenness: 0.3, browRaise: 0.1)
    XCTAssertEqual(FaceEmotionEstimator.estimate(smile, baseline: warmFaceBaseline())?.label, .happy)

    let frown = FaceMetrics(mouthCornerLift: -0.01, mouthOpenness: 0.01, eyeOpenness: 0.3, browRaise: 0.07)
    XCTAssertEqual(FaceEmotionEstimator.estimate(frown, baseline: warmFaceBaseline())?.label, .tense)
  }

  func testDroopingEyesAreLow() {
    let tired = FaceMetrics(mouthCornerLift: 0, mouthOpenness: 0.01, eyeOpenness: 0.18, browRaise: 0.1)
    XCTAssertEqual(FaceEmotionEstimator.estimate(tired, baseline: warmFaceBaseline())?.label, .low)
  }

  // MARK: - Signal

  func testLoudnessOfFullScaleSineIsAboutMinusThreeDB() {
    let samples = (0..<1600).map { Float(sin(Double($0) * 2 * .pi * 200 / 16_000)) }
    XCTAssertEqual(VoiceSignal.loudnessDB(samples), -3.01, accuracy: 0.05)
    XCTAssertEqual(VoiceSignal.loudnessDB([]), -160)
  }

  func testPitchDetectsSpeechRangeSineAndRejectsSilence() throws {
    let samples = (0..<1024).map { Float(0.5 * sin(Double($0) * 2 * .pi * 200 / 16_000)) }
    let pitch = try XCTUnwrap(VoiceSignal.pitchHz(samples, sampleRate: 16_000))
    XCTAssertEqual(pitch, 200, accuracy: 5)
    XCTAssertNil(VoiceSignal.pitchHz([Float](repeating: 0, count: 1024), sampleRate: 16_000))
  }

  func testFeaturesIgnoreSilentFrames() throws {
    let features = try XCTUnwrap(
      VoiceSignal.features(
        loudness: [-30, -30, -80, -25], pitches: [100, 200, nil, 300],
        speech: [true, true, false, false]))
    XCTAssertEqual(features.voicedRatio, 0.5)
    XCTAssertEqual(features.pitchHz, 150)
    XCTAssertEqual(features.loudnessDB, -30)
    XCTAssertEqual(features.pitchVariation, 50.0 / 150.0, accuracy: 0.0001)
    XCTAssertNil(VoiceSignal.features(loudness: [], pitches: [], speech: []))
  }

  // MARK: - Transcript sentiment

  func testSentimentMapsPositiveNegativeAndNeutral() {
    XCTAssertEqual(TranscriptSentiment.estimate(score: 0.8, voice: nil).label, .happy)
    XCTAssertEqual(TranscriptSentiment.estimate(score: -0.8, voice: .energized).label, .tense)
    XCTAssertEqual(TranscriptSentiment.estimate(score: -0.8, voice: .calm).label, .low)
    XCTAssertEqual(TranscriptSentiment.estimate(score: -0.8, voice: nil).label, .low)
    XCTAssertEqual(TranscriptSentiment.estimate(score: 0.1, voice: nil).label, .neutral)
    XCTAssertEqual(TranscriptSentiment.estimate(score: -1.5, voice: nil).confidence, 1)
  }

  func testSentimentSamplesUseVoiceDuringEachSegment() {
    let segments = [
      TranscriptSegment(offset: 0, duration: 10, text: "this is going badly"),
      TranscriptSegment(offset: 10, duration: 10, text: "unsupported language"),
      TranscriptSegment(offset: 20, duration: 10, text: "this is also going badly"),
    ]
    let voice = [
      EmotionSample(offset: 4, source: .voice, label: .tense, confidence: 0.9),
      EmotionSample(offset: 24, source: .voice, label: .calm, confidence: 0.9),
      EmotionSample(offset: 25, source: .face, label: .energized, confidence: 0.9),
    ]
    let samples = TranscriptSentiment.samples(
      for: segments, voiceSamples: voice,
      score: { $0.contains("badly") ? -0.7 : nil })
    XCTAssertEqual(samples.map(\.offset), [0, 20])
    XCTAssertEqual(samples.map(\.label), [.tense, .low])
    XCTAssertTrue(samples.allSatisfy { $0.source == .words })
  }

  func testAppleSentimentScoresClearEnglish() throws {
    let positive = try XCTUnwrap(TranscriptSentiment.score("I love this, it's a wonderful result."))
    let negative = try XCTUnwrap(TranscriptSentiment.score("This is terrible and I hate how it went."))
    XCTAssertGreaterThan(positive, negative)
    XCTAssertNil(TranscriptSentiment.score("   "))
    XCTAssertNil(TranscriptSentiment.score("今天的會議很順利，大家都很開心"))
    XCTAssertNil(TranscriptSentiment.score("今天的会议很顺利，大家都很开心"))
  }

  func testSummaryIncludesWordsInCombinedShares() {
    let summary = EmotionSummary(samples: [
      EmotionSample(offset: 0, source: .voice, label: .calm, confidence: 1),
      EmotionSample(offset: 0, source: .words, label: .happy, confidence: 1),
    ])
    XCTAssertEqual(summary.dominantWords, .happy)
    XCTAssertEqual(summary.combinedShares[.happy] ?? 0, 0.5, accuracy: 0.0001)
    XCTAssertTrue(
      MeetingNotesPrompt.moodSection(summary).contains("Transcript sentiment: happy 100%"))
  }

  // MARK: - Voice activity

  private func run(
    _ detector: inout VoiceActivityDetector, frames: Int, level: Double, pitch: Bool
  ) -> [Bool] {
    (0..<frames).map { _ in detector.process(levelDB: level, hasPitch: pitch) }
  }

  func testSpeechStartsAfterOnsetAndHoldsThroughHangover() {
    var vad = VoiceActivityDetector()
    let config = vad.configuration
    let speech = run(&vad, frames: config.onsetFrames, level: -30, pitch: true)
    XCTAssertEqual(speech, Array(repeating: false, count: config.onsetFrames - 1) + [true])

    let tail = run(&vad, frames: config.hangoverFrames + 1, level: -70, pitch: false)
    XCTAssertEqual(tail, Array(repeating: true, count: config.hangoverFrames) + [false])
  }

  func testLoudSoundsWithoutPitchAreNotSpeech() {
    var vad = VoiceActivityDetector()
    XCTAssertFalse(run(&vad, frames: 20, level: -20, pitch: false).contains(true))
  }

  func testNoiseFloorAdaptsSoVoiceMustRiseAboveBackground() {
    var vad = VoiceActivityDetector()
    // A steady fan at -40 dB pulls the floor up to it.
    _ = run(&vad, frames: 400, level: -40, pitch: false)
    XCTAssertEqual(vad.noiseFloorDB, -40, accuracy: 1)
    // Pitched sound barely above the fan is still background.
    XCTAssertFalse(run(&vad, frames: 10, level: -35, pitch: true).contains(true))
    // Speech well above it counts.
    XCTAssertTrue(run(&vad, frames: 10, level: -20, pitch: true).contains(true))
  }

  func testRangeBuilderBacksStartUpToSpeechOnset() {
    var builder = SpeechRangeBuilder(frameDuration: 0.1)
    let decisions = [false, false, false, false, true, true, true, false, false, true, true]
    decisions.forEach { builder.add(isSpeech: $0) }
    let ranges = builder.finished(onsetFrames: 3)
    XCTAssertEqual(ranges.count, 2)
    XCTAssertEqual(ranges[0].start, 0.2, accuracy: 0.0001)
    XCTAssertEqual(ranges[0].end, 0.7, accuracy: 0.0001)
    XCTAssertEqual(ranges[1].start, 0.7, accuracy: 0.0001)
    XCTAssertEqual(ranges[1].end, 1.1, accuracy: 0.0001)
  }

  // MARK: - Silence skipping

  private let ranges = [SpeechRange(start: 2, end: 5), SpeechRange(start: 10, end: 12)]

  func testSkipJumpsToJustBeforeNextSpeech() throws {
    let lead = SilenceSkipper.leadIn
    XCTAssertEqual(try XCTUnwrap(SilenceSkipper.skipTarget(at: 0.5, ranges: ranges, duration: 15)), 2 - lead, accuracy: 0.0001)
    XCTAssertEqual(try XCTUnwrap(SilenceSkipper.skipTarget(at: 6, ranges: ranges, duration: 15)), 10 - lead, accuracy: 0.0001)
    // Trailing silence runs to the end.
    XCTAssertEqual(SilenceSkipper.skipTarget(at: 13, ranges: ranges, duration: 15), 15)
  }

  func testSkipLeavesSpeechAndShortPausesAlone() {
    XCTAssertNil(SilenceSkipper.skipTarget(at: 3, ranges: ranges, duration: 15))
    XCTAssertNil(SilenceSkipper.skipTarget(at: 1.9, ranges: ranges, duration: 15))
    let close = [SpeechRange(start: 2, end: 5), SpeechRange(start: 6, end: 8)]
    XCTAssertNil(SilenceSkipper.skipTarget(at: 5.5, ranges: close, duration: 8))
    XCTAssertNil(SilenceSkipper.skipTarget(at: 5, ranges: [], duration: 8))
  }

  func testSkippableSecondsCountsOnlyLongGaps() {
    XCTAssertEqual(SilenceSkipper.skippableSeconds(ranges: ranges, duration: 15), 10, accuracy: 0.0001)
    let close = [SpeechRange(start: 1, end: 5), SpeechRange(start: 6, end: 8)]
    XCTAssertEqual(SilenceSkipper.skippableSeconds(ranges: close, duration: 8.5), 0)
  }

  // MARK: - Summary

  func testSummarySharesAndDominantLabels() {
    let samples = [
      EmotionSample(offset: 0, source: .voice, label: .calm, confidence: 1),
      EmotionSample(offset: 4, source: .voice, label: .calm, confidence: 1),
      EmotionSample(offset: 8, source: .voice, label: .tense, confidence: 1),
      EmotionSample(offset: 2, source: .face, label: .happy, confidence: 1),
    ]
    let summary = EmotionSummary(samples: samples)
    XCTAssertEqual(summary.voiceShares[.calm] ?? 0, 2.0 / 3.0, accuracy: 0.0001)
    XCTAssertEqual(summary.dominantVoice, .calm)
    XCTAssertEqual(summary.dominantFace, .happy)
    // Face is a single source at 100% happy, voice is 67% calm.
    XCTAssertEqual(summary.dominant, .happy)
    XCTAssertTrue(EmotionSummary(samples: []).isEmpty)
    XCTAssertNil(EmotionSummary(samples: []).dominant)
  }

  // MARK: - Prompt

  private func makeNote(
    transcript: [TranscriptSegment] = [
      TranscriptSegment(offset: 0, duration: 5, text: "Let's ship on Friday."),
      TranscriptSegment(offset: 65, duration: 4, text: "Ben will write the release notes."),
    ],
    emotions: [EmotionSample] = []
  ) -> VoiceNote {
    VoiceNote(
      id: UUID(), title: "Recording", createdAt: Date(timeIntervalSince1970: 1_800_000_000),
      duration: 70, transcript: transcript, emotions: emotions, usedCamera: false, notes: nil,
      notesGeneratedAt: nil)
  }

  func testPromptIncludesTimestampedTranscriptAndLanguage() {
    let prompt = MeetingNotesPrompt.build(
      note: makeNote(), languageInstruction: "Respond in Traditional Chinese.")
    XCTAssertTrue(prompt.contains("[00:00] Let's ship on Friday."))
    XCTAssertTrue(prompt.contains("[01:05] Ben will write the release notes."))
    XCTAssertTrue(prompt.contains("Respond in Traditional Chinese."))
    XCTAssertTrue(prompt.contains(MeetingNotesPrompt.titlePrefix))
    XCTAssertFalse(prompt.contains("## Mood"))
  }

  func testPromptAddsMoodOnlyWhenSamplesExist() {
    let note = makeNote(emotions: [EmotionSample(offset: 0, source: .voice, label: .calm, confidence: 0.8)])
    let prompt = MeetingNotesPrompt.build(note: note, languageInstruction: nil)
    XCTAssertTrue(prompt.contains("Voice tone: calm 100%"))
    XCTAssertTrue(prompt.contains("## Mood"))
  }

  func testLongTranscriptIsTrimmedInTheMiddle() {
    let long = (0..<5_000).map {
      TranscriptSegment(offset: Double($0), duration: 1, text: "sentence number \($0)")
    }
    let block = MeetingNotesPrompt.transcriptBlock(long)
    XCTAssertLessThan(block.count, MeetingNotesPrompt.maxTranscriptCharacters + 100)
    XCTAssertTrue(block.contains("sentence number 0"))
    XCTAssertTrue(block.contains("sentence number 4999"))
    XCTAssertTrue(block.contains("transcript trimmed"))
  }

  func testParseExtractsTitleAndBody() {
    let parsed = MeetingNotesPrompt.parse("TITLE: \"Release planning\"\n\n## Summary\nShip Friday.")
    XCTAssertEqual(parsed.title, "Release planning")
    XCTAssertEqual(parsed.body, "## Summary\nShip Friday.")

    let untitled = MeetingNotesPrompt.parse("## Summary\nShip Friday.")
    XCTAssertNil(untitled.title)
    XCTAssertEqual(untitled.body, "## Summary\nShip Friday.")
  }

  func testTimestampFormatting() {
    XCTAssertEqual(MeetingNotesPrompt.formatTimestamp(0), "00:00")
    XCTAssertEqual(MeetingNotesPrompt.formatTimestamp(65.9), "01:05")
    XCTAssertEqual(MeetingNotesPrompt.formatTimestamp(3_725), "1:02:05")
    XCTAssertEqual(MeetingNotesPrompt.formatTimestamp(-4), "00:00")
  }

  // MARK: - Store

  private func makeTempDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("VoiceNotesTests-\(UUID().uuidString)", isDirectory: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: url) }
    return url
  }

  @MainActor
  func testStoreSavesReloadsAndDeletes() throws {
    let root = try makeTempDirectory()
    let store = VoiceNoteStore(rootDirectory: root, generateText: { _ in "" })
    let note = makeNote(emotions: [EmotionSample(offset: 1, source: .face, label: .happy, confidence: 0.5)])
    try store.save(note)

    let reloaded = VoiceNoteStore(rootDirectory: root, generateText: { _ in "" })
    XCTAssertEqual(reloaded.notes, [note])

    try reloaded.delete(note.id)
    XCTAssertTrue(reloaded.notes.isEmpty)
    XCTAssertFalse(FileManager.default.fileExists(atPath: reloaded.directory(for: note.id).path))
  }

  @MainActor
  func testGenerateMeetingNotesSavesParsedTitleAndBody() async throws {
    let root = try makeTempDirectory()
    var receivedPrompt = ""
    let store = VoiceNoteStore(
      rootDirectory: root,
      generateText: { prompt in
        receivedPrompt = prompt
        return "TITLE: Release planning\n## Summary\nShip Friday."
      })
    let note = makeNote()
    try store.save(note)

    await store.generateMeetingNotes(for: note.id)

    let updated = try XCTUnwrap(store.note(with: note.id))
    XCTAssertEqual(updated.title, "Release planning")
    XCTAssertEqual(updated.notes, "## Summary\nShip Friday.")
    XCTAssertNotNil(updated.notesGeneratedAt)
    XCTAssertEqual(store.notesState, .idle)
    XCTAssertTrue(receivedPrompt.contains("Let's ship on Friday."))
  }

  @MainActor
  func testGenerateMeetingNotesReportsFailureAndEmptyTranscript() async throws {
    let root = try makeTempDirectory()
    let store = VoiceNoteStore(
      rootDirectory: root,
      generateText: { _ in
        throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "offline"])
      })
    let note = makeNote()
    let silent = makeNote(transcript: [])
    try store.save(note)
    try store.save(silent)

    await store.generateMeetingNotes(for: note.id)
    XCTAssertEqual(store.notesState, .failed(note.id, "offline"))
    XCTAssertNil(store.note(with: note.id)?.notes)

    await store.generateMeetingNotes(for: silent.id)
    guard case .failed(silent.id, _) = store.notesState else {
      return XCTFail("Expected a failure for a note without transcript")
    }
  }

  // MARK: - Speech language

  func testSpeechLanguageFollowsAppLanguageNotSystemOrder() {
    let system = ["en-TW", "zh-Hant-TW"]
    XCTAssertEqual(
      SpeechLanguage.locale(for: "", appLanguage: .traditionalChinese, preferredLanguages: system)
        .identifier(.bcp47), "zh-TW")
    XCTAssertEqual(
      SpeechLanguage.locale(for: "", appLanguage: .system, preferredLanguages: system)
        .identifier(.bcp47),
      "en-US")
  }

  func testSpeechLanguageStoredChoiceWins() {
    XCTAssertEqual(
      SpeechLanguage.locale(for: "ja-JP", appLanguage: .english, preferredLanguages: [])
        .identifier(.bcp47),
      "ja-JP")
  }

  func testSpeechLanguageMapsChineseScripts() {
    XCTAssertEqual(SpeechLanguage.identifier(forLanguageTag: "zh-Hant-TW"), "zh-TW")
    XCTAssertEqual(SpeechLanguage.identifier(forLanguageTag: "zh-TW"), "zh-TW")
    XCTAssertEqual(SpeechLanguage.identifier(forLanguageTag: "zh-Hans-CN"), "zh-CN")
    XCTAssertEqual(SpeechLanguage.identifier(forLanguageTag: "ko-KR"), "ko-KR")
    XCTAssertNil(SpeechLanguage.identifier(forLanguageTag: "sv-SE"))
  }

  // MARK: - Utterance tracking

  func testTrackerKeepsGrowingTextTogether() {
    var tracker = UtteranceTracker()
    XCTAssertNil(tracker.update(text: "今天", start: 0.2, end: 0.8))
    XCTAssertNil(tracker.update(text: "今天開會", start: 0.2, end: 1.4))
    XCTAssertNil(tracker.update(text: "今天開會討論預算", start: 0.2, end: 2.6))
  }

  func testTrackerAllowsRevisedWords() {
    var tracker = UtteranceTracker()
    _ = tracker.update(text: "hello wold", start: 0, end: 1)
    XCTAssertNil(tracker.update(text: "hello world and", start: 0, end: 1.6))
  }

  func testTrackerSavesTextWhenRecognizerStartsOver() {
    var tracker = UtteranceTracker()
    _ = tracker.update(text: "今天開會討論預算", start: 0.2, end: 2.6)
    let saved = tracker.update(text: "下週", start: 4.1, end: 4.6)
    XCTAssertEqual(saved?.text, "今天開會討論預算")
    XCTAssertEqual(saved?.start, 0.2)
    XCTAssertEqual(tracker.pending?.text, "下週")
  }

  func testTrackerSavesTextWhenTimestampsRestart() {
    var tracker = UtteranceTracker()
    _ = tracker.update(text: "first sentence here", start: 0.1, end: 5.0)
    let saved = tracker.update(text: "second sentence here", start: 0.1, end: 1.2)
    XCTAssertEqual(saved?.text, "first sentence here")
  }
}
