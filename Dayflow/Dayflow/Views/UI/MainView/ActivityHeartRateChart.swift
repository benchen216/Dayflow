//
//  ActivityHeartRateChart.swift
//  Dayflow
//
//  Garmin heart rate across one timeline card, shown under the card's summary in the detail
//  panel. Hidden when no samples fall inside the card.
//

import Charts
import SwiftUI

struct HeartRateStats: Equatable, Sendable {
  let average: Int
  let minimum: Int
  let maximum: Int

  /// Nil without samples.
  init?(_ samples: [GarminSample]) {
    guard let average = GarminSample.average(samples),
      let minimum = samples.map(\.value).min(),
      let maximum = samples.map(\.value).max()
    else { return nil }
    self.average = average
    self.minimum = minimum
    self.maximum = maximum
  }
}

struct ActivityHeartRateChart: View {
  @Environment(\.dayflowTheme) private var theme
  @Environment(\.stylePreviewAfter) private var stylePreviewAfter
  @State private var samples: [GarminSample] = []

  let start: Date
  let end: Date

  private static let lineColor = Color(hex: "FF5950")

  private struct LoadKey: Equatable {
    let start: Date
    let end: Date
  }

  var body: some View {
    Group {
      if let stats = HeartRateStats(samples) {
        content(stats)
      }
    }
    .task(id: LoadKey(start: start, end: end)) {
      let start = start
      let end = end
      let loaded = await Task.detached(priority: .utility) {
        StorageManager.shared.fetchGarminSamples(.heartRate, from: start, to: end)
      }.value
      guard !Task.isCancelled else { return }
      samples = loaded
    }
  }

  private func content(_ stats: HeartRateStats) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(String(localized: "timeline.detail.heartRate", defaultValue: "HEART RATE"))
          .font(Font.custom("Figtree", size: 12).weight(.semibold))
          .foregroundColor(Color(red: 0.55, green: 0.55, blue: 0.55))
        Text(
          String(
            format: String(
              localized: "timeline.detail.heartRateStats",
              defaultValue: "Avg %1$lld · %2$lld–%3$lld bpm"),
            stats.average, stats.minimum, stats.maximum)
        )
        .font(Font.custom("Figtree", size: 12).monospacedDigit())
        .foregroundColor(stylePreviewAfter && theme.isDark ? .white : .black)
      }

      if samples.count > 1 {
        chart(stats)
          .frame(height: 72)
      }
    }
  }

  private func chart(_ stats: HeartRateStats) -> some View {
    Chart {
      RuleMark(y: .value("Average", stats.average))
        .foregroundStyle(Self.lineColor.opacity(0.35))
        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
      ForEach(samples, id: \.timestamp) { sample in
        LineMark(
          x: .value("Time", sample.timestamp),
          y: .value("bpm", sample.value)
        )
        .interpolationMethod(.monotone)
        .foregroundStyle(Self.lineColor)
        .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round))
      }
    }
    .chartXScale(domain: start...end)
    .chartYScale(domain: (stats.minimum - 5)...(stats.maximum + 5))
    .chartXAxis {
      AxisMarks(values: .automatic(desiredCount: 4)) { _ in
        AxisValueLabel(format: .dateTime.hour().minute())
          .font(Font.custom("Figtree", size: 10))
      }
    }
    .chartYAxis {
      AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
        AxisValueLabel()
          .font(Font.custom("Figtree", size: 10))
      }
    }
  }
}
