//
//  VoiceNoteRecorder.swift
//  Dayflow
//
//  Runs one recording session: microphone, live transcript, voice mood, and the
//  optional camera mood. Saves a VoiceNote when it stops.
//

import AVFoundation
import Foundation

@MainActor
final class VoiceNoteRecorder: ObservableObject {
  static let shared = VoiceNoteRecorder()
  static let cameraPreferenceKey = "voiceNotesUseCameraForMood"

  enum State: Equatable {
    case idle
    case starting
    case recording(startedAt: Date)
    case failed(String)
  }

  @Published private(set) var state: State = .idle
  @Published private(set) var committedTranscript: [TranscriptSegment] = []
  @Published private(set) var partialTranscript = ""
  @Published private(set) var level: Double = -160
  @Published private(set) var voiceMood: EmotionLabel?
  @Published private(set) var faceMood: EmotionLabel?
  @Published private(set) var transcriptionNotice: String?

  var isRecording: Bool {
    if case .recording = state { return true }
    return false
  }

  private let store: VoiceNoteStore
  private var noteID: UUID?
  private var startedAt: Date?
  private var usedCamera = false
  private var emotions: [EmotionSample] = []
  private var voiceBaseline = VoiceBaseline()
  private var faceBaseline = FaceBaseline()
  private var captureEngine: VoiceCaptureEngine?
  private var transcriber: LiveTranscriber?
  private var faceMonitor: FaceExpressionMonitor?

  init(store: VoiceNoteStore = .shared) {
    self.store = store
  }

  // MARK: - Session

  func start(useCamera: Bool) async {
    guard state == .idle || isFailed else { return }
    state = .starting
    resetSession()

    guard await VoiceCaptureEngine.requestMicrophoneAccess() else {
      state = .failed(
        String(
          localized: "voiceNotes.error.micDenied",
          defaultValue: "Dayflow needs microphone access. Turn it on in System Settings → Privacy & Security → Microphone."
        ))
      return
    }

    let transcriber = await makeTranscriber()
    let id = UUID()
    do {
      let directory = try store.prepareDirectory(for: id)
      let engine = VoiceCaptureEngine(transcriber: transcriber)
      engine.onLevel = { [weak self] in self?.level = $0 }
      engine.onFeatures = { [weak self] features, offset in
        self?.handleVoice(features, offset: offset)
      }
      try engine.start(writingTo: directory.appendingPathComponent(VoiceNote.audioFileName))
      captureEngine = engine
      self.transcriber = transcriber
      noteID = id
    } catch {
      try? store.delete(id)
      state = .failed(error.localizedDescription)
      return
    }

    let now = Date()
    startedAt = now
    state = .recording(startedAt: now)
    if useCamera { await startCamera() }
    AnalyticsService.shared.capture("voice_note_started", ["camera": usedCamera])
  }

  /// Stops recording and saves the note. Returns its id so the UI can open it.
  @discardableResult
  func stop() async -> UUID? {
    guard isRecording, let id = noteID, let engine = captureEngine else { return nil }
    faceMonitor?.stop()
    faceMonitor = nil
    let result = engine.stop()
    let duration = result.duration
    captureEngine = nil

    // The last segment's final result arrives shortly after the request ends.
    try? await Task.sleep(nanoseconds: 1_200_000_000)
    transcriber = nil

    var segments = committedTranscript
    let leftover = partialTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
    if !leftover.isEmpty {
      let lastEnd = segments.last.map { $0.offset + $0.duration } ?? 0
      segments.append(
        TranscriptSegment(offset: lastEnd, duration: max(duration - lastEnd, 0), text: leftover))
    }

    let note = VoiceNote(
      id: id,
      title: defaultTitle(for: startedAt ?? Date()),
      createdAt: startedAt ?? Date(),
      duration: duration,
      transcript: segments,
      emotions: (emotions + TranscriptSentiment.samples(for: segments, voiceSamples: emotions))
        .sorted { $0.offset < $1.offset },
      usedCamera: usedCamera,
      speechRanges: result.speechRanges,
      notes: nil,
      notesGeneratedAt: nil
    )
    do {
      try store.save(note)
      state = .idle
    } catch {
      state = .failed(error.localizedDescription)
    }
    AnalyticsService.shared.capture(
      "voice_note_saved", ["seconds": Int(duration), "segments": segments.count])
    resetSession()
    return state == .idle ? id : nil
  }

  func dismissError() {
    if isFailed { state = .idle }
  }

  // MARK: - Setup

  private var isFailed: Bool {
    if case .failed = state { return true }
    return false
  }

  private func makeTranscriber() async -> LiveTranscriber? {
    guard await LiveTranscriber.requestAuthorization() else {
      transcriptionNotice = String(
        localized: "voiceNotes.notice.speechDenied",
        defaultValue: "Speech recognition is off, so this recording won't have a transcript. Turn it on in System Settings → Privacy & Security → Speech Recognition."
      )
      return nil
    }
    guard let transcriber = LiveTranscriber(sampleRate: VoiceCaptureEngine.sampleRate) else {
      transcriptionNotice = String(
        localized: "voiceNotes.notice.speechUnavailable",
        defaultValue: "Speech recognition isn't available for your language right now.")
      return nil
    }
    if !transcriber.isOnDevice {
      transcriptionNotice = String(
        localized: "voiceNotes.notice.serverSpeech",
        defaultValue: "Your language isn't supported for on-device recognition, so Apple's speech service transcribes this recording."
      )
    }
    transcriber.onPartial = { [weak self] text in
      DispatchQueue.main.async { self?.partialTranscript = text }
    }
    transcriber.onSegment = { [weak self] segment in
      DispatchQueue.main.async {
        guard let self else { return }
        self.committedTranscript.append(segment)
        self.partialTranscript = ""
      }
    }
    transcriber.onError = { message in
      print("[VoiceNotes] Speech recognition error: \(message)")
    }
    return transcriber
  }

  private func startCamera() async {
    guard await FaceExpressionMonitor.requestCameraAccess() else {
      transcriptionNotice = String(
        localized: "voiceNotes.notice.cameraDenied",
        defaultValue: "Camera access is off, so mood comes from your voice only.")
      return
    }
    let monitor = FaceExpressionMonitor()
    monitor.onMetrics = { [weak self] metrics, date in
      self?.handleFace(metrics, at: date)
    }
    do {
      try monitor.start()
      faceMonitor = monitor
      usedCamera = true
    } catch {
      transcriptionNotice = error.localizedDescription
    }
  }

  private func resetSession() {
    noteID = nil
    startedAt = nil
    usedCamera = false
    emotions = []
    voiceBaseline = VoiceBaseline()
    faceBaseline = FaceBaseline()
    committedTranscript = []
    partialTranscript = ""
    level = -160
    voiceMood = nil
    faceMood = nil
    transcriptionNotice = nil
  }

  // MARK: - Mood

  private func handleVoice(_ features: VoiceFeatures, offset: TimeInterval) {
    guard isRecording else { return }
    // Estimate against the baseline before this window joins it.
    if let estimate = VoiceEmotionEstimator.estimate(features, baseline: voiceBaseline) {
      emotions.append(
        EmotionSample(
          offset: offset, source: .voice, label: estimate.label, confidence: estimate.confidence))
      voiceMood = estimate.label
    }
    if features.voicedRatio >= VoiceEmotionEstimator.minimumVoicedRatio {
      voiceBaseline = voiceBaseline.adding(features)
    }
  }

  private func handleFace(_ metrics: FaceMetrics, at date: Date) {
    guard isRecording, let startedAt else { return }
    if let estimate = FaceEmotionEstimator.estimate(metrics, baseline: faceBaseline) {
      emotions.append(
        EmotionSample(
          offset: date.timeIntervalSince(startedAt), source: .face, label: estimate.label,
          confidence: estimate.confidence))
      faceMood = estimate.label
    }
    faceBaseline = faceBaseline.adding(metrics)
  }

  private func defaultTitle(for date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return String(
      localized: "voiceNotes.defaultTitle",
      defaultValue: "Recording \(formatter.string(from: date))")
  }
}
