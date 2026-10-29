//
//  VoiceNoteModels.swift
//  Dayflow
//
//  A voice note is one recording session: the audio file, what was said, how the
//  speaker seemed to feel along the way, and the AI meeting notes made from it.
//

import Foundation

/// A coarse mood estimate. Voice and face both map onto the same small set so
/// the timeline can show them side by side.
enum EmotionLabel: String, Codable, CaseIterable, Sendable {
  case happy
  case energized
  case calm
  case neutral
  case tense
  case low

  var displayName: String {
    switch self {
    case .happy:
      return String(localized: "emotion.happy", defaultValue: "Happy")
    case .energized:
      return String(localized: "emotion.energized", defaultValue: "Energized")
    case .calm:
      return String(localized: "emotion.calm", defaultValue: "Calm")
    case .neutral:
      return String(localized: "emotion.neutral", defaultValue: "Neutral")
    case .tense:
      return String(localized: "emotion.tense", defaultValue: "Tense")
    case .low:
      return String(localized: "emotion.low", defaultValue: "Low")
    }
  }
}

enum EmotionSource: String, Codable, Sendable {
  case voice
  case face
  /// Sentiment of what was said, from the transcript.
  case words
}

struct EmotionSample: Codable, Equatable, Sendable {
  /// Seconds from the start of the recording.
  let offset: TimeInterval
  let source: EmotionSource
  let label: EmotionLabel
  /// 0...1, how far the measurements were from the speaker's own baseline.
  let confidence: Double
}

struct TranscriptSegment: Codable, Equatable, Identifiable, Sendable {
  let id: UUID
  /// Seconds from the start of the recording.
  let offset: TimeInterval
  let duration: TimeInterval
  let text: String

  init(id: UUID = UUID(), offset: TimeInterval, duration: TimeInterval, text: String) {
    self.id = id
    self.offset = offset
    self.duration = duration
    self.text = text
  }
}

struct VoiceNote: Codable, Equatable, Identifiable, Sendable {
  static let audioFileName = "audio.m4a"

  let id: UUID
  var title: String
  let createdAt: Date
  var duration: TimeInterval
  var transcript: [TranscriptSegment]
  var emotions: [EmotionSample]
  var usedCamera: Bool
  /// Where someone was speaking, from voice activity detection. Nil for notes
  /// recorded before detection existed.
  var speechRanges: [SpeechRange]?
  /// Markdown meeting notes, nil until generated.
  var notes: String?
  var notesGeneratedAt: Date?

  var fullTranscript: String {
    transcript.map(\.text).joined(separator: " ")
  }

  var emotionSummary: EmotionSummary {
    EmotionSummary(samples: emotions)
  }

  func withNotes(_ notes: String, title: String?, at date: Date) -> VoiceNote {
    var copy = self
    copy.notes = notes
    copy.notesGeneratedAt = date
    if let title, !title.isEmpty { copy.title = title }
    return copy
  }

  func withTitle(_ title: String) -> VoiceNote {
    var copy = self
    copy.title = title
    return copy
  }
}

/// How often each mood showed up, per source.
struct EmotionSummary: Equatable, Sendable {
  let voiceShares: [EmotionLabel: Double]
  let faceShares: [EmotionLabel: Double]
  let wordShares: [EmotionLabel: Double]

  init(samples: [EmotionSample]) {
    voiceShares = Self.shares(samples.filter { $0.source == .voice })
    faceShares = Self.shares(samples.filter { $0.source == .face })
    wordShares = Self.shares(samples.filter { $0.source == .words })
  }

  var isEmpty: Bool { voiceShares.isEmpty && faceShares.isEmpty && wordShares.isEmpty }

  var dominantVoice: EmotionLabel? { Self.dominant(voiceShares) }
  var dominantFace: EmotionLabel? { Self.dominant(faceShares) }

  var dominantWords: EmotionLabel? { Self.dominant(wordShares) }

  /// Every source that has samples, weighted equally.
  var combinedShares: [EmotionLabel: Double] {
    var combined: [EmotionLabel: Double] = [:]
    let sources = [voiceShares, faceShares, wordShares].filter { !$0.isEmpty }
    for shares in sources {
      for (label, share) in shares {
        combined[label, default: 0] += share / Double(sources.count)
      }
    }
    return combined
  }

  /// The most common mood across all sources.
  var dominant: EmotionLabel? { Self.dominant(combinedShares) }

  private static func shares(_ samples: [EmotionSample]) -> [EmotionLabel: Double] {
    guard !samples.isEmpty else { return [:] }
    var weights: [EmotionLabel: Double] = [:]
    for sample in samples {
      weights[sample.label, default: 0] += max(sample.confidence, 0.05)
    }
    let total = weights.values.reduce(0, +)
    return weights.mapValues { $0 / total }
  }

  private static func dominant(_ shares: [EmotionLabel: Double]) -> EmotionLabel? {
    // Ties break by declaration order so the result is stable.
    EmotionLabel.allCases
      .filter { shares[$0] != nil }
      .max { (shares[$0] ?? 0) < (shares[$1] ?? 0) }
  }
}
