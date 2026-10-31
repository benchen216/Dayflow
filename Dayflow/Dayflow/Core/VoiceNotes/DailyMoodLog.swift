//
//  DailyMoodLog.swift
//  Dayflow
//
//  The day's voice notes reduced to their moods, for the Daily page. Each note keeps its
//  dominant voice, face and wording mood plus the average Garmin heart rate while it was
//  recorded. The same log is written into the daily recap prompt so the AI can mention how
//  the day felt. Transcripts never leave the note; only titles and moods do.
//

import Foundation

struct DailyMoodEntry: Equatable, Identifiable, Sendable {
  let id: UUID
  let title: String
  let createdAt: Date
  let duration: TimeInterval
  let voice: EmotionLabel?
  let face: EmotionLabel?
  let words: EmotionLabel?
  /// Average bpm while recording, nil without Garmin samples.
  let heartRate: Int?
}

struct DailyMoodLog: Equatable, Sendable {
  let entries: [DailyMoodEntry]
  /// Every mood sample of the day, so longer notes weigh more.
  let summary: EmotionSummary

  var isEmpty: Bool { entries.isEmpty }

  /// Heart rate comes every two minutes, so short recordings are widened to catch a point.
  static let heartRateMargin: TimeInterval = 2 * 60

  /// Notes created in [start, end) that carry mood samples, oldest first.
  static func make(
    notes: [VoiceNote], from start: Date, to end: Date,
    heartRate: (Date, Date) -> [GarminSample]
  ) -> DailyMoodLog {
    let dayNotes =
      notes
      .filter { $0.createdAt >= start && $0.createdAt < end && !$0.emotions.isEmpty }
      .sorted { $0.createdAt < $1.createdAt }
    let entries = dayNotes.map { note in
      let summary = note.emotionSummary
      let samples = heartRate(
        note.createdAt.addingTimeInterval(-heartRateMargin),
        note.createdAt.addingTimeInterval(note.duration + heartRateMargin))
      return DailyMoodEntry(
        id: note.id, title: note.title, createdAt: note.createdAt, duration: note.duration,
        voice: summary.dominantVoice, face: summary.dominantFace, words: summary.dominantWords,
        heartRate: GarminSample.average(samples))
    }
    return DailyMoodLog(
      entries: entries, summary: EmotionSummary(samples: dayNotes.flatMap(\.emotions)))
  }

  /// Reads the saved voice notes and Garmin heart rate. The note list is taken on the main
  /// actor; the database reads run wherever the caller is.
  static func load(from start: Date, to end: Date) async -> DailyMoodLog {
    let notes = await MainActor.run { VoiceNoteStore.shared.notes }
    return make(notes: notes, from: start, to: end) {
      StorageManager.shared.fetchGarminSamples(.heartRate, from: $0, to: $1)
    }
  }

  /// The day's moods in English for the recap prompt; the prompt's language section decides
  /// the output language. Empty when there are no notes.
  func promptText(day: String) -> String {
    guard !isEmpty else { return "" }
    var lines = [
      "Mood log for \(day), from voice notes. Voice tone, facial expression and wording were each estimated on-device and are rough hints, not diagnoses:",
      "",
    ]
    for entry in entries {
      var parts: [String] = []
      if let voice = entry.voice { parts.append("voice \(voice.rawValue)") }
      if let face = entry.face { parts.append("face \(face.rawValue)") }
      if let words = entry.words { parts.append("words \(words.rawValue)") }
      if let heartRate = entry.heartRate { parts.append("heart rate \(heartRate) bpm") }
      let minutes = max(1, Int((entry.duration / 60).rounded()))
      let time = Self.clockTime(entry.createdAt)
      lines.append("- \(time), \(minutes) min, \"\(entry.title)\": \(parts.joined(separator: ", "))")
    }
    let overall = Self.rankedShares(summary.combinedShares)
      .map { "\($0.label.rawValue) \($0.percent)%" }
    if !overall.isEmpty {
      lines.append("")
      lines.append("Whole day: \(overall.joined(separator: ", "))")
    }
    return lines.joined(separator: "\n")
  }

  /// One plain sentence for recaps whose generator can't write about mood itself.
  func summarySentence() -> String? {
    guard let dominant = summary.dominant else { return nil }
    return String(
      format: String(
        localized: "daily.mood.summary", defaultValue: "Mostly %1$@ across %2$lld voice notes"),
      dominant.displayName.lowercased(with: .current), entries.count)
  }

  static func rankedShares(_ shares: [EmotionLabel: Double]) -> [(label: EmotionLabel, percent: Int)]
  {
    // Ties break by declaration order so the result is stable.
    let order = EmotionLabel.allCases
    let present: [EmotionLabel] = order.filter { shares[$0] != nil }
    let ranked = present.sorted { lhs, rhs in
      let left = shares[lhs] ?? 0
      let right = shares[rhs] ?? 0
      if left != right { return left > right }
      return (order.firstIndex(of: lhs) ?? 0) < (order.firstIndex(of: rhs) ?? 0)
    }
    return ranked.map { label in
      (label: label, percent: Int(((shares[label] ?? 0) * 100).rounded()))
    }
  }

  private static func clockTime(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "h:mm a"
    return formatter.string(from: date)
  }
}
