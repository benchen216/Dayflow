//
//  SpeechTranscribing.swift
//  Dayflow
//
//  What the recorder needs from a speech engine, so Apple's recognizer and the local
//  SenseVoice model can be swapped without the capture code knowing which is running.
//

import AVFoundation

protocol SpeechTranscribing: AnyObject {
  /// Live text for the utterance in progress. Engines that only work on whole
  /// utterances never call it.
  var onPartial: ((String) -> Void)? { get set }
  var onSegment: ((TranscriptSegment) -> Void)? { get set }
  var onError: ((String) -> Void)? { get set }
  /// The emotion the engine heard in an utterance, for engines that can tell.
  var onVoiceEmotion: ((EmotionSample) -> Void)? { get set }

  func start()
  /// Called from the audio thread with 16 kHz mono buffers.
  func append(_ buffer: AVAudioPCMBuffer, isSilent: Bool)
  /// Ends the session. The last result arrives through `onSegment`; `finish` waits for it.
  func stop()
  func finish() async
}

enum SpeechEngine: String {
  case apple
  case senseVoice

  static let preferenceKey = "voiceNotesSpeechEngine"

  static var selected: SpeechEngine {
    SpeechEngine(rawValue: UserDefaults.standard.string(forKey: preferenceKey) ?? "") ?? .apple
  }
}
