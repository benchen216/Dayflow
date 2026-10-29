//
//  SenseVoiceRuntime.swift
//  Dayflow
//
//  Runs the SenseVoice speech model on this Mac through sherpa-onnx. It recognizes
//  Mandarin, Cantonese, English, Japanese and Korean, and also reports the emotion it
//  heard in each utterance.
//
//  The sherpa-onnx library is loaded with dlopen from the models folder instead of
//  being linked, so the app builds and runs without it and the feature simply stays
//  off until the files are there:
//
//    ~/Library/Application Support/DayflowPlus/models/
//      lib/libsherpa-onnx-c-api.dylib, libonnxruntime.dylib
//      sensevoice/model.int8.onnx, tokens.txt
//
//  `recognize` must be called from one thread at a time.
//

import Foundation

final class SenseVoiceRuntime: @unchecked Sendable {
  struct Files {
    var modelsDirectory: URL

    var libraryDirectory: URL { modelsDirectory.appendingPathComponent("lib", isDirectory: true) }
    var cAPILibrary: URL { libraryDirectory.appendingPathComponent("libsherpa-onnx-c-api.dylib") }
    var onnxRuntimeLibrary: URL { libraryDirectory.appendingPathComponent("libonnxruntime.dylib") }
    var model: URL {
      modelsDirectory.appendingPathComponent("sensevoice", isDirectory: true)
        .appendingPathComponent("model.int8.onnx")
    }
    var tokens: URL {
      modelsDirectory.appendingPathComponent("sensevoice", isDirectory: true)
        .appendingPathComponent("tokens.txt")
    }

    /// Models stay in Application Support even when media is stored elsewhere.
    static var `default`: Files {
      Files(
        modelsDirectory: FileManager.default
          .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
          .appendingPathComponent(AppDataDirectory.name, isDirectory: true)
          .appendingPathComponent("models", isDirectory: true))
    }

    var missing: [URL] {
      [cAPILibrary, onnxRuntimeLibrary, model, tokens].filter {
        !FileManager.default.fileExists(atPath: $0.path)
      }
    }
  }

  struct Recognition: Equatable, Sendable {
    let text: String
    /// Raw emotion tag, for example "<|HAPPY|>". Nil when the model gave none.
    let emotion: String?
  }

  static func isInstalled(_ files: Files = .default) -> Bool { files.missing.isEmpty }

  // C signatures from sherpa-onnx's c-api.h.
  private typealias CreateRecognizer =
    @convention(c) (UnsafePointer<SherpaOnnxOfflineRecognizerConfig>?) -> OpaquePointer?
  private typealias DestroyRecognizer = @convention(c) (OpaquePointer?) -> Void
  private typealias CreateStream = @convention(c) (OpaquePointer?) -> OpaquePointer?
  private typealias DestroyStream = @convention(c) (OpaquePointer?) -> Void
  private typealias AcceptWaveform =
    @convention(c) (OpaquePointer?, Int32, UnsafePointer<Float>?, Int32) -> Void
  private typealias Decode = @convention(c) (OpaquePointer?, OpaquePointer?) -> Void
  private typealias GetResult =
    @convention(c) (OpaquePointer?) -> UnsafePointer<SherpaOnnxOfflineRecognizerResult>?
  private typealias DestroyResult =
    @convention(c) (UnsafePointer<SherpaOnnxOfflineRecognizerResult>?) -> Void

  private let recognizer: OpaquePointer
  private let destroyRecognizer: DestroyRecognizer
  private let createStream: CreateStream
  private let destroyStream: DestroyStream
  private let acceptWaveform: AcceptWaveform
  private let decode: Decode
  private let getResult: GetResult
  private let destroyResult: DestroyResult

  /// `language` is one of auto, zh, en, ja, ko, yue.
  init(files: Files = .default, language: String = "auto", threads: Int32 = 2) throws {
    if let first = files.missing.first { throw SenseVoiceError.missingFile(first.lastPathComponent) }

    // The C API library finds onnxruntime next to itself, so load that one first.
    guard dlopen(files.onnxRuntimeLibrary.path, RTLD_NOW | RTLD_LOCAL) != nil,
      let handle = dlopen(files.cAPILibrary.path, RTLD_NOW | RTLD_LOCAL)
    else {
      throw SenseVoiceError.cannotLoadLibrary(dlerror().map { String(cString: $0) } ?? "unknown error")
    }

    func symbol<T>(_ name: String, as type: T.Type) throws -> T {
      guard let pointer = dlsym(handle, name) else { throw SenseVoiceError.missingSymbol(name) }
      return unsafeBitCast(pointer, to: T.self)
    }
    let create = try symbol("SherpaOnnxCreateOfflineRecognizer", as: CreateRecognizer.self)
    destroyRecognizer = try symbol("SherpaOnnxDestroyOfflineRecognizer", as: DestroyRecognizer.self)
    createStream = try symbol("SherpaOnnxCreateOfflineStream", as: CreateStream.self)
    destroyStream = try symbol("SherpaOnnxDestroyOfflineStream", as: DestroyStream.self)
    acceptWaveform = try symbol("SherpaOnnxAcceptWaveformOffline", as: AcceptWaveform.self)
    decode = try symbol("SherpaOnnxDecodeOfflineStream", as: Decode.self)
    getResult = try symbol("SherpaOnnxGetOfflineStreamResult", as: GetResult.self)
    destroyResult = try symbol("SherpaOnnxDestroyOfflineRecognizerResult", as: DestroyResult.self)

    // The config holds C string pointers, so keep copies alive until it's been used.
    var owned: [UnsafeMutablePointer<CChar>] = []
    func cString(_ value: String) -> UnsafePointer<CChar> {
      let copy = strdup(value)!
      owned.append(copy)
      return UnsafePointer(copy)
    }
    defer { owned.forEach { free($0) } }

    var config = SherpaOnnxOfflineRecognizerConfig()
    config.feat_config.sample_rate = 16_000
    config.feat_config.feature_dim = 80
    config.model_config.sense_voice.model = cString(files.model.path)
    config.model_config.sense_voice.language = cString(language)
    config.model_config.sense_voice.use_itn = 1
    config.model_config.tokens = cString(files.tokens.path)
    config.model_config.num_threads = threads
    config.model_config.provider = cString("cpu")
    config.decoding_method = cString("greedy_search")

    guard let recognizer = create(&config) else { throw SenseVoiceError.cannotCreateRecognizer }
    self.recognizer = recognizer
  }

  deinit {
    destroyRecognizer(recognizer)
  }

  /// Recognizes one utterance of 16 kHz mono samples.
  func recognize(samples: [Float], sampleRate: Int32 = 16_000) -> Recognition? {
    guard !samples.isEmpty, let stream = createStream(recognizer) else { return nil }
    defer { destroyStream(stream) }
    samples.withUnsafeBufferPointer { buffer in
      acceptWaveform(stream, sampleRate, buffer.baseAddress, Int32(buffer.count))
    }
    decode(recognizer, stream)
    guard let result = getResult(stream) else { return nil }
    defer { destroyResult(result) }

    let text = result.pointee.text.map { String(cString: $0) } ?? ""
    let emotion = result.pointee.emotion.map { String(cString: $0) }
    return Recognition(text: text, emotion: emotion?.isEmpty == true ? nil : emotion)
  }
}

enum SenseVoiceError: LocalizedError {
  case missingFile(String)
  case cannotLoadLibrary(String)
  case missingSymbol(String)
  case cannotCreateRecognizer

  var errorDescription: String? {
    switch self {
    case .missingFile(let name): return "SenseVoice file not found: \(name)"
    case .cannotLoadLibrary(let reason): return "Couldn't load the sherpa-onnx library: \(reason)"
    case .missingSymbol(let name): return "The sherpa-onnx library has no \(name)"
    case .cannotCreateRecognizer: return "SenseVoice couldn't start. Check the model files."
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

  /// SenseVoice has no confidence score, so a non-neutral label gets a fixed, modest one.
  static func confidence(for label: EmotionLabel) -> Double {
    label == .neutral ? 0.5 : 0.7
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
