//
//  SpeechLanguage.swift
//  Dayflow
//
//  Which language speech recognition listens for. Apple's recognizer can't detect
//  the language on its own, so it follows a stored choice and otherwise the app's
//  language, not the system's first language.
//

import Foundation

enum SpeechLanguage {
  static let preferenceKey = "voiceNotesSpeechLanguage"
  /// Stored value meaning "use the app language".
  static let followApp = ""
  static let options = ["zh-TW", "zh-CN", "en-US", "ja-JP", "ko-KR", "de-DE", "fr-FR", "ru-RU"]
  static let fallback = "en-US"

  /// The recognizer locale for a stored preference.
  static func locale(
    for preference: String, appLanguage: AppLanguage = AppLanguagePreferences.selection(),
    preferredLanguages: [String] = Locale.preferredLanguages
  ) -> Locale {
    if options.contains(preference) { return Locale(identifier: preference) }
    return Locale(
      identifier: identifier(for: appLanguage, preferredLanguages: preferredLanguages))
  }

  static func identifier(for appLanguage: AppLanguage, preferredLanguages: [String]) -> String {
    switch appLanguage {
    case .traditionalChinese: return "zh-TW"
    case .simplifiedChinese: return "zh-CN"
    case .english: return "en-US"
    case .japanese: return "ja-JP"
    case .korean: return "ko-KR"
    case .german: return "de-DE"
    case .french: return "fr-FR"
    case .russian: return "ru-RU"
    case .system:
      for language in preferredLanguages {
        if let match = identifier(forLanguageTag: language) { return match }
      }
      return fallback
    }
  }

  /// Maps a BCP 47 tag such as "zh-Hant-TW" or "en-TW" onto one of `options`.
  static func identifier(forLanguageTag tag: String) -> String? {
    let locale = Locale(identifier: tag)
    guard let code = locale.language.languageCode?.identifier else { return nil }
    if code == "zh" {
      let script = locale.language.script?.identifier
      let region = locale.region?.identifier
      let traditional = script == "Hant" || (script == nil && ["TW", "HK", "MO"].contains(region))
      return traditional ? "zh-TW" : "zh-CN"
    }
    return options.first { $0.hasPrefix(code + "-") }
  }

  /// Native name, so it stays readable whatever the app language is.
  static func displayName(_ identifier: String) -> String {
    Locale(identifier: identifier).localizedString(forIdentifier: identifier) ?? identifier
  }
}
