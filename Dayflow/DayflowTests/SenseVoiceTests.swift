import AVFoundation
import FluidAudio
import XCTest

@testable import Dayflow

final class SenseVoiceTests: XCTestCase {
  // MARK: - Mapping

  func testEmotionTagsMapToSharedLabels() {
    XCTAssertEqual(SenseVoiceOutput.emotionLabel(from: "<|HAPPY|>"), .happy)
    XCTAssertEqual(SenseVoiceOutput.emotionLabel(from: "HAPPY"), .happy)
    XCTAssertEqual(SenseVoiceOutput.emotionLabel(from: "<|SURPRISED|>"), .energized)
    XCTAssertEqual(SenseVoiceOutput.emotionLabel(from: "<|ANGRY|>"), .tense)
    XCTAssertEqual(SenseVoiceOutput.emotionLabel(from: "<|FEARFUL|>"), .tense)
    XCTAssertEqual(SenseVoiceOutput.emotionLabel(from: "<|DISGUSTED|>"), .tense)
    XCTAssertEqual(SenseVoiceOutput.emotionLabel(from: "<|SAD|>"), .low)
    XCTAssertEqual(SenseVoiceOutput.emotionLabel(from: "<|NEUTRAL|>"), .neutral)
  }

  func testUnknownEmotionTagsAreIgnored() {
    XCTAssertNil(SenseVoiceOutput.emotionLabel(from: nil))
    XCTAssertNil(SenseVoiceOutput.emotionLabel(from: ""))
    XCTAssertNil(SenseVoiceOutput.emotionLabel(from: "<|EMO_UNKNOWN|>"))
  }

  func testSimplifiedChineseBecomesTraditional() {
    XCTAssertEqual(SenseVoiceOutput.traditional("开会讨论预算"), "開會討論預算")
    XCTAssertEqual(SenseVoiceOutput.traditional("hello 123"), "hello 123")
  }

  func testLanguageCodesFollowTheSpeechLanguage() {
    XCTAssertEqual(SenseVoiceOutput.languageCode(for: Locale(identifier: "zh-TW")), "zh")
    XCTAssertEqual(SenseVoiceOutput.languageCode(for: Locale(identifier: "zh-CN")), "zh")
    XCTAssertEqual(SenseVoiceOutput.languageCode(for: Locale(identifier: "zh-HK")), "yue")
    XCTAssertEqual(SenseVoiceOutput.languageCode(for: Locale(identifier: "en-US")), "en")
    XCTAssertEqual(SenseVoiceOutput.languageCode(for: Locale(identifier: "ja-JP")), "ja")
    XCTAssertEqual(SenseVoiceOutput.languageCode(for: Locale(identifier: "ko-KR")), "ko")
    // The model doesn't know these, so it is left to guess.
    XCTAssertEqual(SenseVoiceOutput.languageCode(for: Locale(identifier: "de-DE")), "auto")
  }

  func testOnlyTraditionalLocalesGetTraditionalText() {
    XCTAssertTrue(SenseVoiceOutput.usesTraditionalChinese(Locale(identifier: "zh-TW")))
    XCTAssertTrue(SenseVoiceOutput.usesTraditionalChinese(Locale(identifier: "zh-Hant")))
    XCTAssertFalse(SenseVoiceOutput.usesTraditionalChinese(Locale(identifier: "zh-CN")))
    XCTAssertFalse(SenseVoiceOutput.usesTraditionalChinese(Locale(identifier: "en-US")))
  }

  func testVoiceEmotionAddsUpTagsWithTheSameLabel() throws {
    let scores = [
      SenseVoiceTagScore(tag: "ANGRY", probability: 0.4),
      SenseVoiceTagScore(tag: "NEUTRAL", probability: 0.35),
      SenseVoiceTagScore(tag: "FEARFUL", probability: 0.15),
      SenseVoiceTagScore(tag: "DISGUSTED", probability: 0.1),
    ]
    let emotion = try XCTUnwrap(SenseVoiceOutput.voiceEmotion(from: scores))
    XCTAssertEqual(emotion.label, .tense)
    XCTAssertEqual(emotion.confidence, 0.65, accuracy: 1e-5)
  }

  func testVoiceEmotionUsesTheMostLikelyTagEvenWhenUnsorted() throws {
    let scores = [
      SenseVoiceTagScore(tag: "NEUTRAL", probability: 0.25),
      SenseVoiceTagScore(tag: "SAD", probability: 0.7),
      SenseVoiceTagScore(tag: "HAPPY", probability: 0.05),
    ]
    let emotion = try XCTUnwrap(SenseVoiceOutput.voiceEmotion(from: scores))
    XCTAssertEqual(emotion.label, .low)
    XCTAssertEqual(emotion.confidence, 0.7, accuracy: 1e-5)
  }

  func testVoiceEmotionIsSkippedWhenTheModelIsUnsure() {
    XCTAssertNil(SenseVoiceOutput.voiceEmotion(from: []))
    XCTAssertNil(
      SenseVoiceOutput.voiceEmotion(from: [
        SenseVoiceTagScore(tag: "EMO_UNKNOWN", probability: 0.6),
        SenseVoiceTagScore(tag: "HAPPY", probability: 0.4),
      ]))
  }

  func testLanguageIndicesMatchTheModel() {
    XCTAssertEqual(SenseVoiceOutput.languageIndex(for: "auto"), 0)
    XCTAssertEqual(SenseVoiceOutput.languageIndex(for: "zh"), 3)
    XCTAssertEqual(SenseVoiceOutput.languageIndex(for: "en"), 4)
    XCTAssertEqual(SenseVoiceOutput.languageIndex(for: "yue"), 7)
    XCTAssertEqual(SenseVoiceOutput.languageIndex(for: "ja"), 11)
    XCTAssertEqual(SenseVoiceOutput.languageIndex(for: "ko"), 12)
    XCTAssertEqual(SenseVoiceOutput.languageIndex(for: "de"), 0)
  }

  func testMissingModelIsReportedWithoutDownloading() {
    let empty = FileManager.default.temporaryDirectory
      .appendingPathComponent("no-models-\(UUID().uuidString)")
    XCTAssertFalse(SenseVoiceRuntime.Model.isInstalled(at: empty))
    XCTAssertThrowsError(try SenseVoiceRuntime(language: "zh", directory: empty)) { error in
      XCTAssertEqual(error as? SenseVoiceError, .notDownloaded)
    }
    XCTAssertFalse(FileManager.default.fileExists(atPath: empty.path))
  }

  // MARK: - With the real model (skipped when the model files aren't on this Mac)

  private static let sampleDirectory = URL(
    fileURLWithPath:
      "/Users/ben/CodeProject/models/sensevoice-dl/x/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17/test_wavs"
  )

  private func requireModel() throws {
    try XCTSkipUnless(SenseVoiceRuntime.Model.isInstalled(), "The SenseVoice model isn't downloaded")
  }

  private func samples(named name: String) throws -> [Float] {
    let url = Self.sampleDirectory.appendingPathComponent(name)
    try XCTSkipUnless(FileManager.default.fileExists(atPath: url.path), "No sample \(name)")
    let file = try AVAudioFile(forReading: url)
    let format = AVAudioFormat(
      commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
    XCTAssertEqual(file.processingFormat.sampleRate, 16_000)
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length))!
    try file.read(into: buffer)
    return Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
  }

  func testRecognizesEnglishAndChineseWithTheRealModel() async throws {
    try requireModel()
    let english = try await SenseVoiceRuntime(language: "en")
      .recognize(samples: samples(named: "en.wav"))
    XCTAssertTrue(english.text.lowercased().contains("tribal"), "English: \(english.text)")

    // "9点" rather than "九点" shows the language and text-norm indices reach the model.
    let chinese = try await SenseVoiceRuntime(language: "zh")
      .recognize(samples: samples(named: "zh.wav"))
    XCTAssertTrue(chinese.text.contains("9点"), "Chinese: \(chinese.text)")
    let probabilities = chinese.emotionScores.map { Double($0.probability) }
    XCTAssertEqual(probabilities.reduce(0, +), 1, accuracy: 1e-3)
  }

  func testTranscriberEmitsASegmentAfterAPause() async throws {
    try requireModel()
    let speech = try samples(named: "zh.wav")
    let locale = Locale(identifier: "zh-TW")
    let transcriber = try await SenseVoiceTranscriber.make(sampleRate: 16_000, locale: locale)

    let lock = NSLock()
    var segments: [TranscriptSegment] = []
    transcriber.onSegment = { segment in
      lock.lock()
      segments.append(segment)
      lock.unlock()
    }
    transcriber.start()

    // Half a second of quiet, the sentence, then a pause long enough to close it.
    let quiet = [Float](repeating: 0, count: 8_000)
    let pause = [Float](repeating: 0, count: Int(16_000 * 1.5))
    for (chunk, isSilent) in Self.chunks(quiet + speech + pause, silentAbove: 0.01) {
      transcriber.append(chunk, isSilent: isSilent)
    }
    transcriber.stop()
    await transcriber.finish()

    lock.lock()
    let heard = segments
    lock.unlock()
    XCTAssertEqual(heard.count, 1, "Segments: \(heard.map(\.text))")
    let segment = try XCTUnwrap(heard.first)
    // Written in Traditional characters for a zh-TW listener.
    XCTAssertTrue(segment.text.contains("9點"), segment.text)
    // The utterance begins after the half second of quiet, give or take the pre-roll.
    XCTAssertEqual(segment.offset, 0.1, accuracy: 0.45)
  }

  /// 4096-sample buffers marked silent when their peak is below `silentAbove`.
  private static func chunks(_ samples: [Float], silentAbove threshold: Float)
    -> [(AVAudioPCMBuffer, Bool)]
  {
    let format = AVAudioFormat(
      commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
    var result: [(AVAudioPCMBuffer, Bool)] = []
    var start = 0
    while start < samples.count {
      let end = min(start + 4096, samples.count)
      let slice = Array(samples[start..<end])
      let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(slice.count))!
      buffer.frameLength = AVAudioFrameCount(slice.count)
      slice.withUnsafeBufferPointer {
        buffer.floatChannelData![0].update(from: $0.baseAddress!, count: slice.count)
      }
      let peak = slice.map(abs).max() ?? 0
      result.append((buffer, peak < threshold))
      start = end
    }
    return result
  }
}
