import SwiftUI

extension EmotionLabel {
  /// Warm for pleasant, cool for subdued, red-orange for strain.
  var color: Color {
    switch self {
    case .happy: return Color(red: 0.96, green: 0.70, blue: 0.20)
    case .energized: return Color(red: 0.98, green: 0.45, blue: 0.25)
    case .calm: return Color(red: 0.36, green: 0.68, blue: 0.62)
    case .neutral: return Color(red: 0.62, green: 0.62, blue: 0.66)
    case .tense: return Color(red: 0.84, green: 0.24, blue: 0.30)
    case .low: return Color(red: 0.38, green: 0.48, blue: 0.80)
    }
  }
}

/// A rounded capsule button used across the voice notes screens.
struct VoicePillButtonStyle: ButtonStyle {
  @Environment(\.dayflowTheme) private var theme
  var prominent = false
  var tint: Color?

  func makeBody(configuration: Configuration) -> some View {
    let fill = tint ?? theme.accent
    configuration.label
      .font(.custom("Figtree", size: 12).weight(.semibold))
      .padding(.horizontal, 12)
      .padding(.vertical, 7)
      .foregroundColor(prominent ? .white : theme.controlText)
      .background(
        Capsule().fill(prominent ? AnyShapeStyle(fill) : AnyShapeStyle(theme.controlFill))
      )
      .overlay(Capsule().strokeBorder(prominent ? Color.clear : theme.controlBorder, lineWidth: 0.6))
      .scaleEffect(configuration.isPressed ? 0.97 : 1)
      .opacity(configuration.isPressed ? 0.85 : 1)
      .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
  }
}

struct EmotionChip: View {
  @Environment(\.dayflowTheme) private var theme
  let caption: String
  let label: EmotionLabel?

  var body: some View {
    HStack(spacing: 6) {
      Circle()
        .fill(label?.color ?? theme.textMuted)
        .frame(width: 8, height: 8)
      Text(caption)
        .foregroundColor(theme.textSecondary)
      Text(label?.displayName ?? "—")
        .foregroundColor(theme.textPrimary)
        .fontWeight(.semibold)
    }
    .font(.custom("Figtree", size: 12))
    .padding(.horizontal, 10)
    .padding(.vertical, 5)
    .background(Capsule().fill(theme.chipFill))
    .overlay(Capsule().strokeBorder(theme.chipBorder, lineWidth: 0.6))
    .accessibilityElement(children: .combine)
  }
}

/// Live input level, mapped from dBFS to a bar.
struct VoiceLevelMeter: View {
  @Environment(\.dayflowTheme) private var theme
  let levelDB: Double

  private var fraction: CGFloat {
    CGFloat(min(max((levelDB + 60) / 60, 0), 1))
  }

  var body: some View {
    GeometryReader { geo in
      ZStack(alignment: .leading) {
        Capsule().fill(theme.segmentTrackFill)
        Capsule()
          .fill(theme.accent)
          .frame(width: max(geo.size.width * fraction, 4))
          .animation(.linear(duration: 0.1), value: fraction)
      }
    }
    .frame(height: 6)
    .accessibilityLabel(
      Text(String(localized: "voiceNotes.level", defaultValue: "Microphone level")))
  }
}

/// Two rows of colored blocks, voice on top and face below, across the recording.
struct EmotionTimelineStrip: View {
  @Environment(\.dayflowTheme) private var theme
  let samples: [EmotionSample]
  let duration: TimeInterval
  var playhead: TimeInterval?
  var onSeek: ((TimeInterval) -> Void)?

  private var sources: [EmotionSource] {
    [EmotionSource.voice, .face, .words].filter { source in samples.contains { $0.source == source } }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      ForEach(sources, id: \.self) { source in
        HStack(spacing: 8) {
          Text(sourceName(source))
            .font(.custom("Figtree", size: 11))
            .foregroundColor(theme.textSecondary)
            .frame(width: 44, alignment: .leading)
          row(for: source)
        }
      }
    }
  }

  private func row(for source: EmotionSource) -> some View {
    let rowSamples = samples.filter { $0.source == source }.sorted { $0.offset < $1.offset }
    return GeometryReader { geo in
      let width = geo.size.width
      ZStack(alignment: .leading) {
        RoundedRectangle(cornerRadius: 3).fill(theme.segmentTrackFill)
        ForEach(Array(rowSamples.enumerated()), id: \.offset) { index, sample in
          let end = index + 1 < rowSamples.count ? rowSamples[index + 1].offset : duration
          let start = position(sample.offset, width: width)
          RoundedRectangle(cornerRadius: 2)
            .fill(sample.label.color.opacity(0.35 + 0.65 * sample.confidence))
            .frame(width: max(position(end, width: width) - start, 2))
            .offset(x: start)
            .help("\(MeetingNotesPrompt.formatTimestamp(sample.offset)) · \(sample.label.displayName)")
        }
        if let playhead {
          Rectangle()
            .fill(theme.textPrimary)
            .frame(width: 1.5)
            .offset(x: position(playhead, width: width))
        }
      }
      .contentShape(Rectangle())
      .onTapGesture { location in
        guard width > 0 else { return }
        onSeek?(Double(location.x / width) * duration)
      }
    }
    .frame(height: 12)
  }

  private func position(_ time: TimeInterval, width: CGFloat) -> CGFloat {
    guard duration > 0 else { return 0 }
    return CGFloat(min(max(time / duration, 0), 1)) * width
  }

  private func sourceName(_ source: EmotionSource) -> String {
    switch source {
    case .voice: return String(localized: "voiceNotes.source.voice", defaultValue: "Voice")
    case .face: return String(localized: "voiceNotes.source.face", defaultValue: "Face")
    case .words: return String(localized: "voiceNotes.source.words", defaultValue: "Words")
    }
  }
}

/// Share of each mood, largest first.
struct EmotionShareLegend: View {
  @Environment(\.dayflowTheme) private var theme
  let shares: [EmotionLabel: Double]

  var body: some View {
    // At most six moods, so a single line fits the detail column.
    HStack(spacing: 10) {
      ForEach(shares.sorted { $0.value > $1.value }, id: \.key) { label, share in
        HStack(spacing: 5) {
          Circle().fill(label.color).frame(width: 7, height: 7)
          Text("\(label.displayName) \(Int((share * 100).rounded()))%")
            .font(.custom("Figtree", size: 11))
            .foregroundColor(theme.textSecondary)
        }
      }
    }
  }
}
