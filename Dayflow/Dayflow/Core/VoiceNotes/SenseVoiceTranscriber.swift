//
//  SenseVoiceTranscriber.swift
//  Dayflow
//
//  Feeds the microphone to the local SenseVoice model. The model works on whole
//  utterances, so audio is collected while the voice activity detector hears speech,
//  and each utterance is recognized when the speaker pauses. Text and the emotion the
//  model heard arrive together, one utterance at a time.
//

import AVFoundation

final class SenseVoiceTranscriber: SpeechTranscribing, @unchecked Sendable {
  /// Silence after speech that closes an utterance.
  static let utterancePauseSeconds: TimeInterval = 0.8
  /// Longest stretch recognized at once, cut at this length if the speaker never pauses.
  static let maxUtteranceSeconds: TimeInterval = 30
  /// Audio kept from before the detector noticed speech, so first syllables aren't clipped.
  static let preRollSeconds: TimeInterval = 0.4
  /// Anything shorter is a click or a breath.
  static let minUtteranceSeconds: TimeInterval = 0.3

  var onPartial: ((String) -> Void)?
  var onSegment: ((TranscriptSegment) -> Void)?
  var onError: ((String) -> Void)?
  var onVoiceEmotion: ((EmotionSample) -> Void)?

  private let runtime: SenseVoiceRuntime
  private let sampleRate: Double
  private let writesTraditional: Bool
  private let lock = NSLock()
  /// Recognition is slow next to the audio thread, so it runs here, one at a time.
  private let decodeQueue = DispatchQueue(label: "com.dayflow.sensevoice.decode", qos: .userInitiated)

  private var framesWritten = 0
  private var preRoll: [Float] = []
  private var utterance: [Float] = []
  private var utteranceStartFrame = 0
  private var inSpeech = false
  private var silentSeconds: TimeInterval = 0
  private var isStopped = false

  init(runtime: SenseVoiceRuntime, sampleRate: Double, locale: Locale) {
    self.runtime = runtime
    self.sampleRate = sampleRate
    writesTraditional = SenseVoiceOutput.usesTraditionalChinese(locale)
  }

  /// Loads the model off the calling thread. Throws when the files are missing or won't load.
  static func make(sampleRate: Double, locale: Locale) async throws -> SenseVoiceTranscriber {
    let language = SenseVoiceOutput.languageCode(for: locale)
    let runtime = try await Task.detached(priority: .userInitiated) {
      try SenseVoiceRuntime(language: language)
    }.value
    return SenseVoiceTranscriber(runtime: runtime, sampleRate: sampleRate, locale: locale)
  }

  func start() {
    lock.lock()
    defer { lock.unlock() }
    isStopped = false
  }

  func append(_ buffer: AVAudioPCMBuffer, isSilent: Bool) {
    guard let channel = buffer.floatChannelData?[0] else { return }
    let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))

    lock.lock()
    defer { lock.unlock() }
    guard !isStopped else { return }
    let bufferStart = framesWritten
    framesWritten += samples.count
    let seconds = Double(samples.count) / sampleRate

    if isSilent {
      silentSeconds += seconds
      if inSpeech {
        utterance.append(contentsOf: samples)
        if silentSeconds >= Self.utterancePauseSeconds { closeUtteranceLocked() }
      } else {
        preRoll.append(contentsOf: samples)
        let keep = Int(Self.preRollSeconds * sampleRate)
        if preRoll.count > keep { preRoll.removeFirst(preRoll.count - keep) }
      }
      return
    }

    silentSeconds = 0
    if !inSpeech {
      inSpeech = true
      utterance = preRoll
      utteranceStartFrame = bufferStart - preRoll.count
      preRoll = []
    }
    utterance.append(contentsOf: samples)
    if Double(utterance.count) / sampleRate >= Self.maxUtteranceSeconds { closeUtteranceLocked() }
  }

  func stop() {
    lock.lock()
    defer { lock.unlock() }
    if inSpeech { closeUtteranceLocked() }
    isStopped = true
  }

  /// Waits for every queued utterance to be recognized.
  func finish() async {
    await withCheckedContinuation { continuation in
      decodeQueue.async { continuation.resume() }
    }
  }

  // MARK: - Utterances

  private func closeUtteranceLocked() {
    let samples = utterance
    let startFrame = utteranceStartFrame
    utterance = []
    preRoll = []
    inSpeech = false
    silentSeconds = 0
    guard Double(samples.count) / sampleRate >= Self.minUtteranceSeconds else { return }

    let offset = Double(startFrame) / sampleRate
    let duration = Double(samples.count) / sampleRate
    decodeQueue.async { [weak self] in
      self?.recognize(samples, offset: offset, duration: duration)
    }
  }

  private func recognize(_ samples: [Float], offset: TimeInterval, duration: TimeInterval) {
    guard let result = runtime.recognize(samples: samples) else {
      onError?("SenseVoice returned no result")
      return
    }
    var text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    if writesTraditional { text = SenseVoiceOutput.traditional(text) }
    // Music or noise comes back with an event tag and no words.
    guard !text.isEmpty else { return }

    onSegment?(TranscriptSegment(offset: offset, duration: duration, text: text))
    if let label = SenseVoiceOutput.emotionLabel(from: result.emotion) {
      onVoiceEmotion?(
        EmotionSample(
          offset: offset, source: .voice, label: label,
          confidence: SenseVoiceOutput.confidence(for: label)))
    }
  }
}
