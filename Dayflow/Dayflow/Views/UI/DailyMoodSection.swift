//
//  DailyMoodSection.swift
//  Dayflow
//
//  The Daily page's mood card: the day's overall mood and one row per voice note with its
//  voice, face and wording mood and the heart rate while recording. It is only shown here and
//  is never copied with the standup. Hidden when the day has no voice notes with moods.
//

import SwiftUI

struct DailyMoodSection: View {
  @Environment(\.dayflowTheme) private var theme
  @ObservedObject private var store = VoiceNoteStore.shared
  @State private var log: DailyMoodLog?

  let day: DailyStandupDayInfo
  let scale: CGFloat

  private struct LoadKey: Equatable {
    let day: DailyStandupDayInfo
    let notes: [VoiceNote]
  }

  var body: some View {
    Group {
      if let log, !log.isEmpty { content(log) }
    }
    .task(id: LoadKey(day: day, notes: store.notes)) {
      let day = day
      let loaded = await Task.detached(priority: .utility) {
        await DailyMoodLog.load(from: day.startOfDay, to: day.endOfDay)
      }.value
      guard !Task.isCancelled else { return }
      log = loaded
    }
  }

  private func content(_ log: DailyMoodLog) -> some View {
    let cornerRadius = 12 * scale
    return VStack(alignment: .leading, spacing: 14 * scale) {
      HStack(alignment: .firstTextBaseline, spacing: 10 * scale) {
        Text(String(localized: "daily.mood.title", defaultValue: "Mood"))
          .font(.custom("InstrumentSerif-Regular", size: 24 * scale))
          .foregroundStyle(theme.isDark ? theme.textSecondary : StandupStyle.headingColor)
        Text(String(localized: "voiceNotes.moodEstimate", defaultValue: "Estimated on your Mac"))
          .font(.custom("Figtree-Regular", size: 12 * scale))
          .foregroundColor(theme.textMuted)
          .help(
            String(
              localized: "daily.mood.help",
              defaultValue: "From the voice notes recorded this day. Only you see this; it isn't copied with the standup."
            ))
        Spacer(minLength: 0)
      }

      EmotionShareLegend(shares: log.summary.combinedShares)

      VStack(alignment: .leading, spacing: 8 * scale) {
        ForEach(log.entries) { entry in
          row(entry)
        }
      }
    }
    .padding(22 * scale)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .fill(theme.standupCardGradient)
    )
    .overlay(
      RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .stroke(theme.isDark ? theme.standupCardBorder : StandupStyle.strokeColor, lineWidth: 0.75)
    )
  }

  private func row(_ entry: DailyMoodEntry) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 12 * scale) {
      Text(entry.createdAt.formatted(date: .omitted, time: .shortened))
        .font(.custom("Figtree-Regular", size: 13 * scale).monospacedDigit())
        .foregroundColor(theme.textMuted)
        .frame(width: 64 * scale, alignment: .leading)
      Text(verbatim: entry.title)
        .font(.custom("Figtree-Medium", size: 13 * scale))
        .foregroundColor(theme.textPrimary)
        .lineLimit(1)
        .truncationMode(.tail)
        .frame(maxWidth: 260 * scale, alignment: .leading)
      HStack(spacing: 10 * scale) {
        moodChip(
          String(localized: "voiceNotes.source.voice", defaultValue: "Voice"), entry.voice)
        moodChip(String(localized: "voiceNotes.source.face", defaultValue: "Face"), entry.face)
        moodChip(
          String(localized: "voiceNotes.source.words", defaultValue: "Words"), entry.words)
      }
      Spacer(minLength: 0)
      if let heartRate = entry.heartRate {
        Text(verbatim: "♥ \(heartRate) bpm")
          .font(.custom("Figtree-Regular", size: 12 * scale).monospacedDigit())
          .foregroundColor(theme.textSecondary)
          .help(
            String(
              localized: "daily.mood.heartRateHelp",
              defaultValue: "Average Garmin heart rate while recording"))
      }
    }
  }

  @ViewBuilder
  private func moodChip(_ source: String, _ label: EmotionLabel?) -> some View {
    if let label {
      HStack(spacing: 5 * scale) {
        Circle().fill(label.color).frame(width: 7 * scale, height: 7 * scale)
        Text(verbatim: "\(source) \(label.displayName)")
          .font(.custom("Figtree-Regular", size: 12 * scale))
          .foregroundColor(theme.textSecondary)
      }
    }
  }
}
