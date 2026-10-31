//
//  SenseVoiceRuntime.swift
//  Dayflow
//
//  Runs the SenseVoice speech model on this Mac through FluidAudio's Core ML port, on the
//  Neural Engine. It recognizes Mandarin, Cantonese, English, Japanese and Korean, and
//  also reports the emotion it heard in each utterance, with a probability.
//
//  The model is downloaded once from Hugging Face into FluidAudio's cache when the user
//  asks for it in Voice notes (about 230 MB on Apple Silicon). Starting a recording never
//  downloads it; without the model, Voice notes falls back to Apple speech recognition.
//

import FluidAudio
import Foundation

struct SenseVoiceRecognition: Equatable, Sendable {
  let text: String
  /// Every emotion tag with its probability, most likely first.
  let emotionScores: [SenseVoiceTagScore]
}

final class SenseVoiceRuntime: Sendable {
  enum Model {
    /// int8 runs on the Neural Engine at half the size of fp16 with the same accuracy.
    /// Intel Macs have no Neural Engine, so they get the much larger fp32 model.
    static var precision: SenseVoiceEncoderPrecision {
      #if arch(arm64)
        .int8
      #else
        .fp32
      #endif
    }

    static var downloadMegabytes: Int {
      #if arch(arm64)
        230
      #else
        900
      #endif
    }

    /// FluidAudio's cache folder for SenseVoice. FluidAudio keeps the path private, so
    /// this mirrors it; `isInstalled` reports false if it ever moves, and the download
    /// button shows again.
    static var directory: URL {
      FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("FluidAudio", isDirectory: true)
        .appendingPathComponent("Models", isDirectory: true)
        .appendingPathComponent("sensevoice-small", isDirectory: true)
    }

    static func isInstalled(at directory: URL = directory) -> Bool {
      SenseVoiceModels.modelsExist(at: directory, precision: precision)
    }

    /// Downloads the model into FluidAudio's cache. `progress` gets 0...1.
    static func download(progress: @escaping @Sendable (Double) -> Void) async throws {
      _ = try await SenseVoiceModels.download(precision: precision) { update in
        progress(update.fractionCompleted)
      }
    }
  }

  private let manager: SenseVoiceManager

  /// Loads the downloaded model. Throws `notDownloaded` instead of fetching it.
  init(language: String, directory: URL = Model.directory) throws {
    guard Model.isInstalled(at: directory) else { throw SenseVoiceError.notDownloaded }
    let models = try SenseVoiceModels.load(from: directory, precision: Model.precision)
    manager = SenseVoiceManager(
      models: models,
      language: SenseVoiceOutput.languageIndex(for: language),
      textNorm: SenseVoiceOutput.withInverseTextNormalization)
  }

  /// Recognizes one utterance of 16 kHz mono samples (up to 30 seconds).
  func recognize(samples: [Float]) async throws -> SenseVoiceRecognition {
    let result = try await manager.transcribeDetailed(audio: samples)
    return SenseVoiceRecognition(text: result.text, emotionScores: result.scores.emotion)
  }
}

enum SenseVoiceError: LocalizedError, Equatable {
  case notDownloaded

  var errorDescription: String? {
    switch self {
    case .notDownloaded: return "The SenseVoice model hasn't been downloaded yet."
    }
  }
}

// MARK: - Mapping the model's output to the app's labels

enum SenseVoiceOutput {
  /// Maps SenseVoice's emotion tag to the six shared labels. Nil for tags it doesn't know.
  static func emotionLabel(from raw: String?) -> EmotionLabel? {
    guard let raw else { return nil }
    let tag = raw.trimmingCharacters(in: CharacterSet(charactersIn: "<|> ")).uppercased()
    switch tag {
    case "HAPPY": return .happy
    case "SURPRISED": return .energized
    case "ANGRY", "FEARFUL", "DISGUSTED": return .tense
    case "SAD": return .low
    case "NEUTRAL": return .neutral
    default: return nil
    }
  }

  /// The emotion heard in an utterance. The label comes from the most likely tag; its
  /// confidence adds up every tag that maps to the same label (ANGRY, FEARFUL and
  /// DISGUSTED all count toward tense). Nil when the most likely tag has no label.
  static func voiceEmotion(from scores: [SenseVoiceTagScore]) -> (
    label: EmotionLabel, confidence: Double
  )? {
    guard let top = scores.max(by: { $0.probability < $1.probability }),
      let label = emotionLabel(from: top.tag)
    else { return nil }
    let confidence = scores
      .filter { emotionLabel(from: $0.tag) == label }
      .reduce(0) { $0 + Double($1.probability) }
    return (label, min(confidence, 1))
  }

  /// SenseVoice's text-norm query token: 14 asks for written-out numbers and punctuation
  /// ("9點" rather than "九點"), 15 for spoken form.
  static let withInverseTextNormalization: Int32 = 14

  /// The model's language query token for a SenseVoice language code (FunASR's
  /// `lid_dict`). Anything else lets the model detect the language.
  static func languageIndex(for code: String) -> Int32 {
    switch code {
    case "zh": return 3
    case "en": return 4
    case "yue": return 7
    case "ja": return 11
    case "ko": return 12
    default: return 0
    }
  }

  /// SenseVoice writes Chinese in Simplified characters.
  static func traditional(_ text: String) -> String {
    text.applyingTransform(StringTransform("Hans-Hant"), reverse: false) ?? text
  }

  /// SenseVoice language code for a recognition locale. "auto" lets the model decide.
  static func languageCode(for locale: Locale) -> String {
    let tag = locale.identifier(.bcp47).lowercased()
    if tag.hasPrefix("zh-hk") || tag.hasPrefix("yue") { return "yue" }
    if tag.hasPrefix("zh") { return "zh" }
    for code in ["en", "ja", "ko"] where tag.hasPrefix(code) { return code }
    return "auto"
  }

  static func usesTraditionalChinese(_ locale: Locale) -> Bool {
    let tag = locale.identifier(.bcp47).lowercased()
    return tag.hasPrefix("zh-tw") || tag.hasPrefix("zh-hant") || tag.hasPrefix("zh-hk")
      || tag.hasPrefix("zh-mo") || tag.hasPrefix("yue")
  }
}
