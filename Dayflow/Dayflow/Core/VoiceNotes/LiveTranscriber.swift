//
//  LiveTranscriber.swift
//  Dayflow
//
//  Streams microphone audio into Apple speech recognition and hands back
//  timestamped segments. A single recognition request has a length limit, so a
//  new one starts at the next pause after `preferredSegmentSeconds`, or forcibly
//  at `maxSegmentSeconds`.
//

import AVFoundation
import Speech

final class LiveTranscriber: @unchecked Sendable {
  static let preferredSegmentSeconds: TimeInterval = 20
  static let maxSegmentSeconds: TimeInterval = 50

  /// Live text for the segment in progress.
  var onPartial: ((String) -> Void)?
  var onSegment: ((TranscriptSegment) -> Void)?
  var onError: ((String) -> Void)?

  private let recognizer: SFSpeechRecognizer
  private let sampleRate: Double
  private let lock = NSLock()
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var task: SFSpeechRecognitionTask?
  private var framesWritten: AVAudioFramePosition = 0
  private var segmentStartFrame: AVAudioFramePosition = 0
  private var isStopped = false

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

    let segmentSeconds = Double(framesWritten - segmentStartFrame) / sampleRate
    if (isSilent && segmentSeconds >= Self.preferredSegmentSeconds)
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
    self.request = request

    var delivered = false
    task = recognizer.recognitionTask(with: request) { [weak self] result, error in
      guard let self, !delivered else { return }
      if let result {
        let text = result.bestTranscription.formattedString
        if result.isFinal {
          delivered = true
          self.deliver(text: text, offset: startOffset, transcription: result.bestTranscription)
        } else {
          self.onPartial?(text)
        }
      } else if let error {
        delivered = true
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
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    let lastSegment = transcription.segments.last
    let duration = lastSegment.map { $0.timestamp + $0.duration } ?? 0
    onSegment?(TranscriptSegment(offset: offset, duration: duration, text: trimmed))
  }
}
