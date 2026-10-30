//
//  DayGarminSection.swift
//  Dayflow
//
//  Garmin stress, Body Battery and HRV for the Day Summary right rail.
//

import SwiftUI

struct DayGarminData: Equatable {
  var day: GarminDay?
  var bodyBattery: [GarminSample] = []
  var hrvReadings: [GarminSample] = []
  var rangeStart = Date()
  var rangeEnd = Date()

  static let empty = DayGarminData()
}

struct DayGarminSection: View {
  @Environment(\.dayflowTheme) private var theme

  let data: DayGarminData
  let lastSyncedAt: Date?
  let outcome: GarminSyncOutcome?

  private enum Design {
    static let sectionSpacing: CGFloat = 14
    static let blockSpacing: CGFloat = 6
    static let barHeight: CGFloat = 8
    static let sparkHeight: CGFloat = 34
    static let batteryColor = Color(hex: "3FA796")
    static let hrvColor = Color(hex: "8A6FDF")
    static let stressColors = [
      Color(hex: "5B8DEF"), Color(hex: "F2C14E"), Color(hex: "F08A4B"), Color(hex: "D9534F"),
    ]
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Design.sectionSpacing) {
      Text(verbatim: "Your body")
        .font(.custom("InstrumentSerif-Regular", size: 22))
        .foregroundColor(theme.textPrimary)

      if outcome == .keyRejected {
        note("Garmin turned down the key. It may have expired; paste a new one in Settings.")
      } else if let day = data.day, day.hasData {
        if day.stressLevel != nil { stress(day) }
        if day.bodyBatteryCharged != nil || !data.bodyBattery.isEmpty { bodyBattery(day) }
        if day.hrvLastNight != nil { hrv(day) }
      } else {
        note("No Garmin data for this day yet.")
      }

      if let lastSyncedAt {
        let relative = RelativeDateTimeFormatter().localizedString(
          for: lastSyncedAt, relativeTo: Date())
        Text(verbatim: "Garmin · last synced \(relative)")
          .font(.custom("Figtree", size: 11))
          .foregroundColor(theme.textTertiary)
      }
    }
  }

  // MARK: - Stress

  private func stress(_ day: GarminDay) -> some View {
    let parts = [
      day.restStressSeconds, day.lowStressSeconds, day.mediumStressSeconds, day.highStressSeconds,
    ].map { Double($0 ?? 0) }
    let total = parts.reduce(0, +)
    return VStack(alignment: .leading, spacing: Design.blockSpacing) {
      headline(value: "\(day.stressLevel ?? 0)", label: "stress", detail: stressWord(day.stressLevel))
      if total > 0 {
        GeometryReader { geo in
          HStack(spacing: 2) {
            ForEach(parts.indices, id: \.self) { index in
              Capsule()
                .fill(Design.stressColors[index])
                .frame(width: max(0, geo.size.width * parts[index] / total - 2))
            }
          }
        }
        .frame(height: Design.barHeight)
        Text(
          verbatim:
            "Rest \(hours(parts[0])) · Low \(hours(parts[1])) · Medium \(hours(parts[2])) · High \(hours(parts[3]))"
        )
        .font(.custom("Figtree", size: 11))
        .foregroundColor(theme.textSecondary)
      }
    }
  }

  /// Garmin's own bands: 0–25 rest, 26–50 low, 51–75 medium, 76–100 high.
  private func stressWord(_ level: Int?) -> String {
    switch level ?? 0 {
    case ..<26: return "resting"
    case ..<51: return "low"
    case ..<76: return "medium"
    default: return "high"
    }
  }

  // MARK: - Body Battery

  private func bodyBattery(_ day: GarminDay) -> some View {
    VStack(alignment: .leading, spacing: Design.blockSpacing) {
      headline(
        value: "+\(day.bodyBatteryCharged ?? 0) / −\(day.bodyBatteryDrained ?? 0)",
        label: "Body Battery", detail: data.bodyBattery.last.map { "last \($0.value)" })
      if data.bodyBattery.count > 1 {
        Sparkline(
          samples: data.bodyBattery, start: data.rangeStart, end: data.rangeEnd,
          range: 0...100, color: Design.batteryColor
        )
        .frame(height: Design.sparkHeight)
        Text(verbatim: "Garmin reports only a few Body Battery points a day.")
          .font(.custom("Figtree", size: 10))
          .foregroundColor(theme.textTertiary)
      }
    }
  }

  // MARK: - HRV

  private func hrv(_ day: GarminDay) -> some View {
    VStack(alignment: .leading, spacing: Design.blockSpacing) {
      headline(
        value: "\(day.hrvLastNight ?? 0) ms", label: "HRV last night",
        detail: day.hrvStatus.map(Self.statusText))
      if let weekly = day.hrvWeeklyAverage {
        let baseline =
          day.hrvBaselineLow.flatMap { low in
            day.hrvBaselineHigh.map { " · usual \(low)–\($0) ms" }
          } ?? ""
        Text(verbatim: "7-day average \(weekly) ms\(baseline)")
          .font(.custom("Figtree", size: 11))
          .foregroundColor(theme.textSecondary)
      }
      if data.hrvReadings.count > 1, let first = data.hrvReadings.first,
        let last = data.hrvReadings.last
      {
        let values = data.hrvReadings.map(\.value)
        Sparkline(
          samples: data.hrvReadings, start: first.timestamp, end: last.timestamp,
          range: (values.min() ?? 0)...max((values.max() ?? 1), (values.min() ?? 0) + 1),
          color: Design.hrvColor
        )
        .frame(height: Design.sparkHeight)
      }
    }
  }

  nonisolated static func statusText(_ status: String) -> String {
    switch status {
    case "BALANCED": return "balanced"
    case "UNBALANCED": return "unbalanced"
    case "LOW": return "low"
    case "POOR": return "poor"
    default: return status.lowercased().replacingOccurrences(of: "_", with: " ")
    }
  }

  // MARK: - Pieces

  private func headline(value: String, label: String, detail: String?) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text(verbatim: value)
        .font(.custom("InstrumentSerif-Regular", size: 26))
        .foregroundColor(theme.summaryValue)
      Text(verbatim: detail.map { "\(label) · \($0)" } ?? label)
        .font(.custom("Figtree", size: 12))
        .foregroundColor(theme.textSecondary)
    }
  }

  private func hours(_ seconds: Double) -> String {
    LocalizedDuration.string(seconds)
  }

  private func note(_ text: String) -> some View {
    Text(verbatim: text)
      .font(.custom("Figtree", size: 11))
      .foregroundColor(theme.textSecondary)
      .fixedSize(horizontal: false, vertical: true)
  }
}

/// A line through timestamped samples, placed by time across [start, end].
private struct Sparkline: View {
  let samples: [GarminSample]
  let start: Date
  let end: Date
  let range: ClosedRange<Int>
  let color: Color

  var body: some View {
    GeometryReader { geo in
      let span = max(end.timeIntervalSince(start), 1)
      let height = Double(max(range.upperBound - range.lowerBound, 1))
      let points = samples.map { sample in
        CGPoint(
          x: geo.size.width * min(max(sample.timestamp.timeIntervalSince(start) / span, 0), 1),
          y: geo.size.height * (1 - Double(sample.value - range.lowerBound) / height))
      }
      ZStack {
        Path { path in
          guard let first = points.first else { return }
          path.move(to: first)
          points.dropFirst().forEach { path.addLine(to: $0) }
        }
        .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        ForEach(points.indices, id: \.self) { index in
          Circle().fill(color).frame(width: 4, height: 4).position(points[index])
        }
      }
    }
  }
}
