//
//  MeetingNotesPrompt.swift
//  Dayflow
//
//  Builds the prompt that turns a voice note's transcript into meeting notes,
//  and reads the title back out of the reply.
//

import Foundation

enum MeetingNotesPrompt {
  /// Keeps very long recordings inside every provider's context window.
  static let maxTranscriptCharacters = 60_000
  static let titlePrefix = "TITLE:"

  static func build(note: VoiceNote, languageInstruction: String?) -> String {
    let moodBlock = moodSection(note.emotionSummary)
    let languageBlock = languageInstruction.map { "\n\n\($0)" } ?? ""
    return """
      You are writing meeting notes from a voice recording the user made on their Mac.
      The transcript comes from on-device speech recognition, so expect missing punctuation \
      and a few misheard words. Fix obvious recognition mistakes silently; never invent facts \
      that are not in the transcript.

      Recording length: \(formatTimestamp(note.duration))

      ## Transcript
      \(transcriptBlock(note.transcript))
      \(moodBlock)
      ## Output format
      The first line must be `\(titlePrefix) <a short title, at most 8 words>`.
      Then write Markdown with these sections, skipping any that would be empty:
      ## Summary
      Two to four sentences on what this was about.
      ## Key points
      Bullets. Add the transcript timestamp like (12:34) when it helps find the moment.
      ## Decisions
      Bullets.
      ## Action items
      A checklist (`- [ ] `) with an owner when one is named.
      ## Open questions
      Bullets.
      \(moodBlock.isEmpty ? "" : "## Mood\nOne or two sentences on how the speaker seemed to feel and where it shifted. Treat the mood estimate as a rough signal, not a fact.")
      \(languageBlock)
      """
  }

  /// Splits the model reply into a title and the Markdown body.
  static func parse(_ response: String) -> (title: String?, body: String) {
    let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
    let lines = trimmed.components(separatedBy: .newlines)
    guard let first = lines.first,
      first.uppercased().hasPrefix(titlePrefix)
    else {
      return (nil, trimmed)
    }
    let title = first.dropFirst(titlePrefix.count)
      .trimmingCharacters(in: .whitespaces)
      .trimmingCharacters(in: CharacterSet(charactersIn: "\"*`"))
    let body = lines.dropFirst().joined(separator: "\n")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return (title.isEmpty ? nil : title, body)
  }

  static func transcriptBlock(_ segments: [TranscriptSegment]) -> String {
    let lines = segments.map { "[\(formatTimestamp($0.offset))] \($0.text)" }
    let full = lines.joined(separator: "\n")
    guard full.count > maxTranscriptCharacters else { return full }
    // Keep the opening and the end; the middle of a long talk is usually the most repetitive.
    let half = maxTranscriptCharacters / 2
    return "\(full.prefix(half))\n[… transcript trimmed …]\n\(full.suffix(half))"
  }

  static func moodSection(_ summary: EmotionSummary) -> String {
    guard !summary.isEmpty else { return "" }
    func describe(_ shares: [EmotionLabel: Double]) -> String {
      shares.sorted { $0.value > $1.value }
        .map { "\($0.key.rawValue) \(Int(($0.value * 100).rounded()))%" }
        .joined(separator: ", ")
    }
    var lines = ["", "## Estimated mood (on-device heuristic, low precision)"]
    if !summary.voiceShares.isEmpty { lines.append("Voice tone: \(describe(summary.voiceShares))") }
    if !summary.faceShares.isEmpty { lines.append("Facial expression: \(describe(summary.faceShares))") }
    if !summary.wordShares.isEmpty { lines.append("Transcript sentiment: \(describe(summary.wordShares))") }
    lines.append("")
    return lines.joined(separator: "\n")
  }

  static func formatTimestamp(_ seconds: TimeInterval) -> String {
    let total = max(Int(seconds.rounded(.down)), 0)
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let secs = total % 60
    return hours > 0
      ? String(format: "%d:%02d:%02d", hours, minutes, secs)
      : String(format: "%02d:%02d", minutes, secs)
  }
}
