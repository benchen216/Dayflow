//
//  LiveTranscriber.swift
//  Dayflow
//
//  Streams microphone audio into Apple speech recognition and hands back
//  timestamped segments. A single recognition request has a length limit, so a
//  new one starts at every pause after speech, at the next pause after
//  `preferredSegmentSeconds`, or forcibly at `maxSegmentSeconds`.
//
//  Apple's recognizer can drop what it heard earlier in a request once the speaker
//  pauses and starts again, so each utterance gets its own request and
//  `UtteranceTracker` saves text the recognizer starts over on anyway.
//

import AVFoundation
import Speech

final class LiveTranscriber: SpeechTranscribing, @unchecked Sendable {
  static let preferredSegmentSeconds: TimeInterval = 20
  static let maxSegmentSeconds: TimeInterval = 50
  /// Silence after speech that closes the current utterance.
  static let utterancePauseSeconds: TimeInterval = 1.2

  /// Live text for the segment in progress.
  var onPartial: ((String) -> Void)?
  var onSegment: ((TranscriptSegment) -> Void)?
  var onError: ((String) -> Void)?
  /// Apple's recognizer doesn't report emotion.
  var onVoiceEmotion: ((EmotionSample) -> Void)?

  private let recognizer: SFSpeechRecognizer
  private let sampleRate: Double
  private let lock = NSLock()
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var task: SFSpeechRecognitionTask?
  private var framesWritten: AVAudioFramePosition = 0
  private var segmentStartFrame: AVAudioFramePosition = 0
  private var isStopped = false
  private var silentSeconds: TimeInterval = 0
  private var segmentHasSpeech = false

  /// Nil when speech recognition is unavailable for the current language.
  init?(sampleRate: Double, locale: Locale = .current) {
    guard let recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer(),
      recognizer.isAvailable
    else { return nil }
    self.recognizer = recognizer
    self.sampleRate = sampleRate
  }

  static func requestAuthorization() async -> Bool {
    await withCheckedContinuation { continuation in
      SFSpeechRecognizer.requestAuthorization { status in
        continuation.resume(returning: status == .authorized)
      }
    }
  }

  var isOnDevice: Bool { recognizer.supportsOnDeviceRecognition }

  func start() {
    lock.lock()
    defer { lock.unlock() }
    isStopped = false
    beginSegmentLocked()
  }

  /// Called from the audio thread with 16 kHz mono buffers.
  func append(_ buffer: AVAudioPCMBuffer, isSilent: Bool) {
    lock.lock()
    defer { lock.unlock() }
    guard !isStopped else { return }
    request?.append(buffer)
    framesWritten += AVAudioFramePosition(buffer.frameLength)

    if isSilent {
      silentSeconds += Double(buffer.frameLength) / sampleRate
    } else {
      silentSeconds = 0
      segmentHasSpeech = true
    }

    let segmentSeconds = Double(framesWritten - segmentStartFrame) / sampleRate
    let pausedAfterSpeech = segmentHasSpeech && silentSeconds >= Self.utterancePauseSeconds
    if pausedAfterSpeech
      || (isSilent && segmentSeconds >= Self.preferredSegmentSeconds)
      || segmentSeconds >= Self.maxSegmentSeconds
    {
      finishSegmentLocked()
      beginSegmentLocked()
    }
  }

  /// Ends the current request. Its final result still arrives through `onSegment`.
  func stop() {
    lock.lock()
    defer { lock.unlock() }
    isStopped = true
    finishSegmentLocked()
  }

  /// The last segment's final result arrives shortly after the request ends.
  func finish() async {
    try? await Task.sleep(nanoseconds: 1_200_000_000)
  }

  private func beginSegmentLocked() {
    let request = SFSpeechAudioBufferRecognitionRequest()
    request.shouldReportPartialResults = true
    request.addsPunctuation = true
    // Keep audio on the Mac whenever the language supports it.
    if recognizer.supportsOnDeviceRecognition {
      request.requiresOnDeviceRecognition = true
    }
    let startOffset = Double(framesWritten) / sampleRate
    segmentStartFrame = framesWritten
    segmentHasSpeech = false
    silentSeconds = 0
    self.request = request

    var delivered = false
    var tracker = UtteranceTracker()
    task = recognizer.recognitionTask(with: request) { [weak self] result, error in
      guard let self, !delivered else { return }
      if let result {
        let transcription = result.bestTranscription
        let text = transcription.formattedString
        if result.isFinal {
          delivered = true
          self.deliver(text: text, offset: startOffset, transcription: transcription)
        } else {
          let times = Self.times(of: transcription)
          if let finished = tracker.update(text: text, start: times.start, end: times.end) {
            self.emit(
              text: finished.text, offset: startOffset + finished.start,
              duration: finished.end - finished.start)
          }
          self.onPartial?(text)
        }
      } else if let error {
        delivered = true
        // Keep whatever was heard before the request failed.
        if let heard = tracker.pending {
          self.emit(
            text: heard.text, offset: startOffset + heard.start, duration: heard.end - heard.start)
        }
        let nsError = error as NSError
        // 1110 is "no speech detected", which is normal for a quiet stretch.
        if nsError.code != 1110 && nsError.code != 216 {
          self.onError?(error.localizedDescription)
        }
      }
    }
  }

  private func finishSegmentLocked() {
    request?.endAudio()
    request = nil
    task = nil
  }

  private func deliver(text: String, offset: TimeInterval, transcription: SFTranscription) {
    let times = Self.times(of: transcription)
    emit(text: text, offset: offset + times.start, duration: times.end - times.start)
  }

  private func emit(text: String, offset: TimeInterval, duration: TimeInterval) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    onSegment?(TranscriptSegment(offset: offset, duration: max(duration, 0), text: trimmed))
  }

  private static func times(of transcription: SFTranscription) -> (start: TimeInterval, end: TimeInterval) {
    guard let first = transcription.segments.first, let last = transcription.segments.last else {
      return (0, 0)
    }
    return (first.timestamp, last.timestamp + last.duration)
  }
}

/// Spots the recognizer starting a new utterance inside one request, so the text it
/// was holding can be saved before the next partial replaces it.
struct UtteranceTracker {
  struct Utterance: Equatable {
    var text: String
    var start: TimeInterval
    var end: TimeInterval
  }

  private var current: Utterance?

  /// The utterance in progress.
  var pending: Utterance? { current }

  /// Feed each partial result. Returns the previous utterance when this one is a restart.
  mutating func update(text: String, start: TimeInterval, end: TimeInterval) -> Utterance? {
    let next = Utterance(text: text, start: start, end: end)
    defer { if !text.trimmingCharacters(in: .whitespaces).isEmpty { current = next } }
    guard let previous = current, Self.isRestart(from: previous, to: next) else { return nil }
    return previous
  }

  static func isRestart(from previous: Utterance, to next: Utterance) -> Bool {
    guard !next.text.isEmpty, previous.text.count >= 2 else { return false }
    // Time running backwards means a fresh run of words.
    if next.end < previous.end - 0.5 { return true }
    // Revisions rewrite words but keep the opening; a much shorter text that
    // shares none of it is a new utterance.
    let shared = zip(previous.text, next.text).prefix { $0 == $1 }.count
    return next.text.count * 2 < previous.text.count && shared < 2
  }
}
