//
//  DayPhoneUsageSection.swift
//  Dayflow
//
//  iPhone/iPad Screen Time section for the Day Summary right rail.
//

import SwiftUI

struct DayPhoneUsageSection: View {
  @Environment(\.dayflowTheme) private var theme

  let summary: DeviceUsageDaySummary
  /// Mac time captured the same day, for the phone-vs-Mac split.
  let macCapturedTime: TimeInterval
  let access: DeviceUsageAccess

  private enum Design {
    static let sectionSpacing: CGFloat = 14
    static let rowSpacing: CGFloat = 9
    static let barHeight: CGFloat = 6
    static let nameWidth: CGFloat = 110
    static let durationWidth: CGFloat = 52
    static let splitHeight: CGFloat = 8
    static let phoneColor = Color(hex: "5B8DEF")
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Design.sectionSpacing) {
      Text("On your phone")
        .font(.custom("InstrumentSerif-Regular", size: 22))
        .foregroundColor(theme.textPrimary)

      if access == .needsFullDiskAccess {
        note(String(localized: "Give Dayflow Full Disk Access to read iPhone Screen Time."))
      } else if summary.total <= 0 {
        note(emptyText)
      } else {
        totals
        if macCapturedTime > 0 {
          split
        }
        topApps
      }

      if let syncedText {
        Text(syncedText)
          .font(.custom("Figtree", size: 11))
          .foregroundColor(theme.textTertiary)
      }
    }
  }

  private var emptyText: String {
    summary.devices.isEmpty && summary.lastSyncedAt == nil
      ? String(localized: "No iPhone data for this day yet. iCloud can take a few hours to sync it.")
      : String(localized: "No phone use recorded for this day.")
  }

  private var totals: some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
      Text(LocalizedDuration.string(summary.total))
        .font(.custom("InstrumentSerif-Regular", size: 28))
        .foregroundColor(theme.summaryValue)
      Text("\(summary.pickups) pickups")
        .font(.custom("Figtree", size: 12))
        .foregroundColor(theme.textSecondary)
    }
  }

  /// One bar: Mac time on the left in the theme accent, phone on the right.
  private var split: some View {
    let total = summary.total + macCapturedTime
    let phoneShare = total > 0 ? summary.total / total : 0
    return VStack(alignment: .leading, spacing: 6) {
      GeometryReader { geo in
        HStack(spacing: 2) {
          Capsule()
            .fill(theme.accent.opacity(0.7))
            .frame(width: max(0, geo.size.width * (1 - phoneShare) - 1))
          Capsule()
            .fill(Design.phoneColor)
            .frame(width: max(0, geo.size.width * phoneShare - 1))
        }
      }
      .frame(height: Design.splitHeight)

      HStack {
        Text("Mac \(LocalizedDuration.string(macCapturedTime))")
        Spacer()
        Text("Phone \(Int((phoneShare * 100).rounded()))%")
      }
      .font(.custom("Figtree", size: 11))
      .foregroundColor(theme.textSecondary)
    }
  }

  private var topApps: some View {
    let longest = summary.topApps.first?.duration ?? 1
    return VStack(alignment: .leading, spacing: Design.rowSpacing) {
      ForEach(summary.topApps) { app in
        HStack(spacing: 8) {
          Text(app.displayName)
            .font(.custom("Figtree", size: 12))
            .foregroundColor(theme.textPrimary)
            .lineLimit(1)
            .frame(width: Design.nameWidth, alignment: .leading)

          GeometryReader { geo in
            ZStack(alignment: .leading) {
              Capsule().fill(theme.targetsTrackFill)
              Capsule()
                .fill(Design.phoneColor.opacity(0.85))
                .frame(width: max(Design.barHeight, geo.size.width * app.duration / longest))
            }
          }
          .frame(height: Design.barHeight)

          Text(LocalizedDuration.string(app.duration))
            .font(.custom("Figtree", size: 11))
            .foregroundColor(theme.textSecondary)
            .frame(width: Design.durationWidth, alignment: .trailing)
        }
        .help(app.bundleID)
      }
    }
  }

  private var syncedText: String? {
    guard let last = summary.lastSyncedAt else { return nil }
    let relative = RelativeDateTimeFormatter().localizedString(for: last, relativeTo: Date())
    let names = Set(summary.devices.map(\.kind.displayName)).sorted().joined(separator: " + ")
    return names.isEmpty
      ? String(localized: "Last synced \(relative)")
      : String(localized: "\(names) · last synced \(relative)")
  }

  private func note(_ text: String) -> some View {
    Text(text)
      .font(.custom("Figtree", size: 11))
      .foregroundColor(theme.textSecondary)
      .fixedSize(horizontal: false, vertical: true)
  }
}
