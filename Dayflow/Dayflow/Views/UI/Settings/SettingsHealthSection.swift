//
//  SettingsHealthSection.swift
//  Dayflow
//
//  Where the Garmin Connect developer key is entered (kept in the Keychain), and how the
//  stress, Body Battery and HRV sync is doing.
//

import SwiftUI

struct SettingsHealthSection: View {
  @ObservedObject private var sync = GarminSyncService.shared
  @State private var keyInput = ""
  @State private var failedToSave = false

  private var hasKey: Bool { sync.hasKey }

  var body: some View {
    SettingsSection(
      title: "Garmin",
      subtitle:
        "Stress, Body Battery and HRV from your Garmin watch, shown next to your mood. The key is stored in this Mac's Keychain and is never written to a file."
    ) {
      VStack(alignment: .leading, spacing: 0) {
        SettingsRow(
          label: hasKey ? "Key saved" : "No key yet",
          subtitle: statusText,
          showsDivider: true
        ) {
          if hasKey {
            HStack(spacing: 8) {
              SettingsSecondaryButton(
                title: sync.isSyncing ? "Syncing…" : "Sync now", isDisabled: sync.isSyncing
              ) {
                sync.syncNow()
              }
              SettingsSecondaryButton(title: "Remove") {
                if GarminCredentials.remove() { sync.keyChanged() }
              }
            }
          }
        }

        SettingsRow(
          label: hasKey ? "Replace key" : "Garmin Connect API key",
          subtitle: "Paste the key from the Garmin developer portal.",
          showsDivider: false
        ) {
          HStack(spacing: 8) {
            SecureField("Paste key", text: $keyInput)
              .textFieldStyle(.roundedBorder)
              .font(.custom("SF Mono", size: 12))
              .frame(width: 220)
              .onSubmit(save)
            SettingsSecondaryButton(
              title: "Save", isDisabled: GarminCredentials.cleaned(keyInput) == nil, action: save)
          }
        }
      }
    }
  }

  private var statusText: String {
    if failedToSave { return "The Keychain refused to save the key. Try again." }
    guard hasKey else { return "Without a key, no Garmin data is read." }
    switch sync.lastOutcome {
    case .keyRejected:
      return "Garmin turned down the key. It may have expired or been deleted; paste a new one."
    case .failed(let reason):
      return "The last sync failed: \(reason)"
    case .synced, nil:
      guard let last = sync.lastSyncedAt else { return "Saved. The first sync starts shortly." }
      let relative = RelativeDateTimeFormatter().localizedString(for: last, relativeTo: Date())
      return "Last synced \(relative). Syncs every 6 hours while Dayflow is open."
    }
  }

  private func save() {
    guard GarminCredentials.cleaned(keyInput) != nil else { return }
    if GarminCredentials.save(keyInput) {
      keyInput = ""
      failedToSave = false
      sync.keyChanged()
    } else {
      failedToSave = true
    }
  }
}
