//
//  SettingsDeviceUsageSection.swift
//  Dayflow
//
//  Opt-in for importing iPhone/iPad Screen Time, with the Full Disk Access
//  and Screen Time sharing steps it depends on.
//

import AppKit
import SwiftUI

struct SettingsDeviceUsageSection: View {
  @ObservedObject private var service = DeviceUsageSyncService.shared
  @State private var isEnabled = DeviceUsagePreferences.isEnabled
  @State private var devices: [UsageDevice] = []

  private static let fullDiskAccessURL = URL(
    string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!

  var body: some View {
    SettingsSection(
      title: String(localized: "iPhone Screen Time"),
      subtitle:
        String(
          localized:
            "Show time on your iPhone and iPad next to your Mac timeline. Dayflow reads the Screen Time data macOS already syncs from your devices through iCloud. It stays on this Mac, and AI tools connected to Dayflow can read it too. Turning import off deletes what was imported."
        )
    ) {
      VStack(alignment: .leading, spacing: 0) {
        SettingsRow(
          label: isEnabled ? String(localized: "Import is on") : String(localized: "Import is off"),
          subtitle: statusText,
          showsDivider: isEnabled
        ) {
          SettingsToggle(isOn: $isEnabled)
        }

        if isEnabled {
          if service.access == .needsFullDiskAccess {
            SettingsRow(
              label: String(localized: "Full Disk Access"),
              subtitle: String(
                localized:
                  "macOS keeps Screen Time behind Full Disk Access. Turn on Dayflow in the list, then come back."
              ),
              showsDivider: true
            ) {
              SettingsSecondaryButton(title: String(localized: "Open Settings")) {
                NSWorkspace.shared.open(Self.fullDiskAccessURL)
              }
            }
          } else if service.access == .noSyncedDevices {
            SettingsRow(
              label: String(localized: "No devices found"),
              subtitle: String(
                localized:
                  "On your iPhone, open Settings → Screen Time and turn on Share Across Devices, signed in to the same Apple Account as this Mac."
              ),
              showsDivider: true
            ) {
              EmptyView()
            }
          }

          SettingsRow(
            label: String(localized: "Sync now"),
            subtitle: String(
              localized: "Dayflow checks every 15 minutes. iCloud itself can lag by a few hours."),
            showsDivider: false
          ) {
            SettingsSecondaryButton(
              title: service.isSyncing ? String(localized: "Syncing…") : String(localized: "Sync"),
              systemImage: "arrow.clockwise",
              isDisabled: service.isSyncing
            ) {
              service.syncNow()
            }
          }
        }
      }
    }
    .onAppear {
      service.refreshAccess()
      reloadDevices()
    }
    .onChange(of: isEnabled) { _, enabled in
      service.setEnabled(enabled)
    }
    .onReceive(NotificationCenter.default.publisher(for: .deviceUsageDataUpdated)) { _ in
      reloadDevices()
    }
    .onChange(of: service.isSyncing) { _, syncing in
      if !syncing { reloadDevices() }
    }
  }

  private var statusText: String? {
    guard isEnabled else { return nil }
    let named = devices.filter { $0.kind != .other }
    guard !named.isEmpty else { return nil }
    return named.map { device in
      guard let last = device.lastEventAt else { return device.kind.displayName }
      let relative = RelativeDateTimeFormatter().localizedString(for: last, relativeTo: Date())
      return String(localized: "\(device.kind.displayName): last synced \(relative)")
    }.joined(separator: "\n")
  }

  private func reloadDevices() {
    Task.detached(priority: .utility) {
      let devices = StorageManager.shared.fetchUsageDevices()
      await MainActor.run { self.devices = devices }
    }
  }
}
