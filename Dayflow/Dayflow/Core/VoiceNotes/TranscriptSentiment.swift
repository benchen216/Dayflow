//
//  TranscriptSentiment.swift
//  Dayflow
//
//  Scores what was said with Apple's on-device NaturalLanguage sentiment model
//  and turns each transcript segment into a mood sample. Negative words read as
//  tense when the voice was raised and low when it was subdued.
//

import Foundation
import NaturalLanguage

enum TranscriptSentiment {
  /// Scores at or beyond this, either way, count as clearly positive or negative.
  static let threshold = 0.3

  /// Apple lists Simplified Chinese as supported, but it scored plainly happy and
  /// neutral sentences as negative, and Traditional Chinese isn't supported at all.
  /// Skip both rather than add misleading samples.
  static let unreliableLanguages: Set<NLLanguage> = [.simplifiedChinese, .traditionalChinese]

  /// Apple's sentiment score for `text`, -1...1, or nil when its language isn't supported.
  static func score(_ text: String) -> Double? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty,
      let language = NLLanguageRecognizer.dominantLanguage(for: trimmed),
      !unreliableLanguages.contains(language),
      NLTagger.availableTagSchemes(for: .paragraph, language: language).contains(.sentimentScore)
    else { return nil }

    let tagger = NLTagger(tagSchemes: [.sentimentScore])
    tagger.string = trimmed
    tagger.setLanguage(language, range: trimmed.startIndex..<trimmed.endIndex)
    var total = 0.0
    var count = 0
    // Scoring per paragraph and averaging keeps one long segment from washing out.
    tagger.enumerateTags(
      in: trimmed.startIndex..<trimmed.endIndex, unit: .paragraph, scheme: .sentimentScore
    ) { tag, _ in
      if let value = tag.flatMap({ Double($0.rawValue) }) {
        total += value
        count += 1
      }
      return true
    }
    return count > 0 ? total / Double(count) : nil
  }

  static func estimate(score: Double, voice: EmotionLabel?) -> (
    label: EmotionLabel, confidence: Double
  ) {
    let strength = min(abs(score), 1)
    if score >= threshold { return (.happy, strength) }
    if score <= -threshold {
      let raised = voice == .energized || voice == .tense
      return (raised ? .tense : .low, strength)
    }
    return (.neutral, 1 - strength / threshold * 0.5)
  }

  /// One sample per segment that has a score, at the segment's start.
  static func samples(
    for segments: [TranscriptSegment], voiceSamples: [EmotionSample],
    score: (String) -> Double? = score
  ) -> [EmotionSample] {
    segments.compactMap { segment in
      guard let value = score(segment.text) else { return nil }
      let estimate = estimate(score: value, voice: voiceLabel(during: segment, in: voiceSamples))
      return EmotionSample(
        offset: segment.offset, source: .words, label: estimate.label,
        confidence: estimate.confidence)
    }
  }

  /// The most common voice mood while the segment was spoken.
  static func voiceLabel(during segment: TranscriptSegment, in samples: [EmotionSample])
    -> EmotionLabel?
  {
    let end = segment.offset + max(segment.duration, 1)
    let overlapping = samples.filter {
      $0.source == .voice && $0.offset >= segment.offset && $0.offset < end
    }
    return EmotionSummary(samples: overlapping).dominantVoice
  }
}
