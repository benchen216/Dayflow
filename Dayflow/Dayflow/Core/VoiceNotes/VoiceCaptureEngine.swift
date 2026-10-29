//
//  VoiceCaptureEngine.swift
//  Dayflow
//
//  Captures the microphone, converts it to 16 kHz mono, and fans each buffer out
//  to the audio file, the live transcriber, and the voice mood analysis.
//

import AVFoundation

final class VoiceCaptureEngine: @unchecked Sendable {
  static let sampleRate: Double = 16_000
  /// Seconds of audio per voice mood estimate.
  static let analysisWindowSeconds: TimeInterval = 4
  /// Samples per analysis frame.
  static let frameLength = 1024

  /// Loudness in dBFS for the level meter, called on the main queue.
  var onLevel: ((Double) -> Void)?
  /// Voice features for each analysis window and its start offset, called on the main queue.
  var onFeatures: ((VoiceFeatures, TimeInterval) -> Void)?

  private let engine = AVAudioEngine()
  private let outputFormat: AVAudioFormat
  private let transcriber: LiveTranscriber?
  private let analysisQueue = DispatchQueue(label: "com.dayflow.voice.analysis")
  private var converter: AVAudioConverter?
  private var file: AVAudioFile?

  // Owned by analysisQueue.
  private var windowLoudness: [Double] = []
  private var windowPitches: [Double?] = []
  private var windowSpeech: [Bool] = []
  private var pendingSamples: [Float] = []
  private var vad = VoiceActivityDetector(
    configuration: .init(frameDuration: Double(VoiceCaptureEngine.frameLength) / VoiceCaptureEngine.sampleRate))
  private var speechRanges = SpeechRangeBuilder(frameDuration: Double(VoiceCaptureEngine.frameLength) / VoiceCaptureEngine.sampleRate)
  private var windowStartFrame: AVAudioFramePosition = 0
  private var analyzedFrames: AVAudioFramePosition = 0

  // Written on analysisQueue, read on the audio thread. One buffer of lag is fine.
  private let speechLock = NSLock()
  private var speechActive = false

  init(transcriber: LiveTranscriber?) {
    self.transcriber = transcriber
    outputFormat = AVAudioFormat(
      commonFormat: .pcmFormatFloat32, sampleRate: Self.sampleRate, channels: 1,
      interleaved: false)!
  }

  static func requestMicrophoneAccess() async -> Bool {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized: return true
    case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
    default: return false
    }
  }

  func start(writingTo url: URL) throws {
    let input = engine.inputNode
    let inputFormat = input.outputFormat(forBus: 0)
    guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
      throw VoiceCaptureError.noInputDevice
    }
    guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
      throw VoiceCaptureError.unsupportedFormat
    }
    self.converter = converter

    let settings: [String: Any] = [
      AVFormatIDKey: kAudioFormatMPEG4AAC,
      AVSampleRateKey: Self.sampleRate,
      AVNumberOfChannelsKey: 1,
      AVEncoderBitRateKey: 32_000,
    ]
    file = try AVAudioFile(
      forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)

    input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
      self?.process(buffer)
    }
    transcriber?.start()
    engine.prepare()
    do {
      try engine.start()
    } catch {
      input.removeTap(onBus: 0)
      file = nil
      throw error
    }
  }

  /// Stops capture and closes the file.
  func stop() -> VoiceCaptureResult {
    engine.inputNode.removeTap(onBus: 0)
    engine.stop()
    transcriber?.stop()
    let duration = file.map { Double($0.length) / Self.sampleRate } ?? 0
    // Releasing the file finalizes the AAC container.
    file = nil
    let ranges = analysisQueue.sync { () -> [SpeechRange] in
      flushWindow()
      return speechRanges.finished(onsetFrames: vad.configuration.onsetFrames)
    }
    return VoiceCaptureResult(duration: duration, speechRanges: ranges)
  }

  // MARK: - Audio thread

  private func process(_ buffer: AVAudioPCMBuffer) {
    guard let converted = convert(buffer) else { return }
    do {
      try file?.write(from: converted)
    } catch {
      print("[VoiceNotes] Failed to write audio: \(error)")
    }

    let samples = Array(
      UnsafeBufferPointer(start: converted.floatChannelData?[0], count: Int(converted.frameLength)))
    let loudness = VoiceSignal.loudnessDB(samples)
    speechLock.lock()
    let isSpeaking = speechActive
    speechLock.unlock()
    transcriber?.append(converted, isSilent: !isSpeaking)
    analysisQueue.async { [weak self] in self?.analyze(samples, loudness: loudness) }
  }

  private func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
    guard let converter else { return nil }
    let ratio = outputFormat.sampleRate / buffer.format.sampleRate
    let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
    guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
      return nil
    }
    var consumed = false
    var error: NSError?
    let status = converter.convert(to: output, error: &error) { _, inputStatus in
      if consumed {
        inputStatus.pointee = .noDataNow
        return nil
      }
      consumed = true
      inputStatus.pointee = .haveData
      return buffer
    }
    guard status != .error, output.frameLength > 0 else { return nil }
    return output
  }

  // MARK: - Analysis queue

  private func analyze(_ samples: [Float], loudness: Double) {
    // ~64 ms frames give stable pitch estimates for speech. Buffers rarely divide
    // evenly, so the remainder waits for the next buffer to keep frame times exact.
    let frameLength = Self.frameLength
    pendingSamples.append(contentsOf: samples)
    var start = 0
    while start + frameLength <= pendingSamples.count {
      let frame = Array(pendingSamples[start..<(start + frameLength)])
      let level = VoiceSignal.loudnessDB(frame)
      let pitch =
        level > VoiceSignal.silenceThresholdDB
        ? VoiceSignal.pitchHz(frame, sampleRate: Self.sampleRate) : nil
      let isSpeech = vad.process(levelDB: level, hasPitch: pitch != nil)
      speechRanges.add(isSpeech: isSpeech)
      windowLoudness.append(level)
      windowPitches.append(pitch)
      windowSpeech.append(isSpeech)
      start += frameLength
    }
    pendingSamples.removeFirst(start)
    speechLock.lock()
    speechActive = vad.isSpeaking
    speechLock.unlock()
    analyzedFrames += AVAudioFramePosition(samples.count)

    DispatchQueue.main.async { [weak self] in self?.onLevel?(loudness) }

    let windowFrames = AVAudioFramePosition(Self.analysisWindowSeconds * Self.sampleRate)
    if analyzedFrames - windowStartFrame >= windowFrames {
      flushWindow()
    }
  }

  private func flushWindow() {
    let offset = Double(windowStartFrame) / Self.sampleRate
    let features = VoiceSignal.features(
      loudness: windowLoudness, pitches: windowPitches, speech: windowSpeech)
    windowLoudness = []
    windowPitches = []
    windowSpeech = []
    windowStartFrame = analyzedFrames
    guard let features else { return }
    DispatchQueue.main.async { [weak self] in self?.onFeatures?(features, offset) }
  }
}

struct VoiceCaptureResult {
  let duration: TimeInterval
  let speechRanges: [SpeechRange]
}

enum VoiceCaptureError: LocalizedError {
  case noInputDevice
  case unsupportedFormat

  var errorDescription: String? {
    switch self {
    case .noInputDevice:
      return String(
        localized: "voiceNotes.error.noMic", defaultValue: "No microphone is available.")
    case .unsupportedFormat:
      return String(
        localized: "voiceNotes.error.format",
        defaultValue: "The microphone's audio format isn't supported.")
    }
  }
}
