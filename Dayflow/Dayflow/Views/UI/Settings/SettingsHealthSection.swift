//
//  SettingsHealthSection.swift
//  Dayflow
//
//  Where the Garmin Connect developer key is entered. It is kept in the Keychain.
//

import SwiftUI

struct SettingsHealthSection: View {
  @State private var keyInput = ""
  @State private var hasKey = GarminCredentials.hasKey
  @State private var failedToSave = false

  var body: some View {
    SettingsSection(
      title: "Garmin HRV",
      subtitle:
        "Heart rate variability from your Garmin watch, shown next to your mood. The key is stored in this Mac's Keychain and is never written to a file."
    ) {
      VStack(alignment: .leading, spacing: 0) {
        SettingsRow(
          label: hasKey ? "Key saved" : "No key yet",
          subtitle: statusText,
          showsDivider: true
        ) {
          if hasKey {
            SettingsSecondaryButton(title: "Remove") {
              if GarminCredentials.remove() { hasKey = false }
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
    return hasKey
      ? "Saved. Syncing HRV isn't turned on yet."
      : "Without a key, no Garmin data is read."
  }

  private func save() {
    guard GarminCredentials.cleaned(keyInput) != nil else { return }
    if GarminCredentials.save(keyInput) {
      keyInput = ""
      hasKey = true
      failedToSave = false
    } else {
      failedToSave = true
    }
  }
}
