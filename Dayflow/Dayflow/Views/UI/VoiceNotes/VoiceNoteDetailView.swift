import AppKit
import SwiftUI

/// One saved recording: playback, mood over time, meeting notes, and transcript.
struct VoiceNoteDetailView: View {
  private enum Tab: Hashable {
    case notes
    case transcript
  }

  @Environment(\.dayflowTheme) private var theme
  @ObservedObject private var store = VoiceNoteStore.shared
  @StateObject private var player = VoiceNotePlayer()
  @State private var tab: Tab
  @State private var titleDraft: String
  @State private var confirmingDelete = false
  @State private var actionError: String?
  @AppStorage("voiceNotesSkipSilence") private var skipsSilence = true

  let note: VoiceNote
  let onDelete: () -> Void

  init(note: VoiceNote, onDelete: @escaping () -> Void) {
    self.note = note
    self.onDelete = onDelete
    _tab = State(initialValue: note.notes == nil ? .transcript : .notes)
    _titleDraft = State(initialValue: note.title)
  }

  private var isGenerating: Bool {
    store.notesState == .generating(note.id)
  }

  private var generationError: String? {
    if case .failed(note.id, let message) = store.notesState { return message }
    return nil
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      header
      playerBar
      if !note.emotions.isEmpty { moodSection }
      tabPicker
      ScrollView {
        Group {
          switch tab {
          case .notes: notesContent
          case .transcript: transcriptContent
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 24)
      }
    }
    .padding(24)
    .onAppear {
      player.load(store.audioURL(for: note.id))
      player.speechRanges = note.speechRanges ?? []
      player.skipsSilence = skipsSilence
    }
    .onChange(of: skipsSilence) { _, newValue in player.skipsSilence = newValue }
    .onDisappear { player.stop() }
    // Generated notes can rename the recording.
    .onChange(of: note.title) { _, newTitle in titleDraft = newTitle }
    .confirmationDialog(
      String(localized: "voiceNotes.deleteConfirm", defaultValue: "Delete this recording?"),
      isPresented: $confirmingDelete
    ) {
      Button(String(localized: "voiceNotes.delete", defaultValue: "Delete"), role: .destructive) {
        delete()
      }
    } message: {
      Text(
        String(
          localized: "voiceNotes.deleteMessage",
          defaultValue: "The audio, transcript, and notes are removed from this Mac."))
    }
  }

  // MARK: - Header

  private var header: some View {
    HStack(alignment: .top, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        TextField("", text: $titleDraft)
          .textFieldStyle(.plain)
          .font(.custom("InstrumentSerif-Regular", size: 28))
          .foregroundColor(theme.textPrimary)
          .onSubmit(saveTitle)
        HStack(spacing: 6) {
          Text(note.createdAt, format: .dateTime.weekday().month().day().hour().minute())
          Text("·")
          Text(MeetingNotesPrompt.formatTimestamp(note.duration))
          if note.usedCamera {
            Text("·")
            Image(systemName: "camera.fill").font(.system(size: 9))
          }
        }
        .font(.custom("Figtree", size: 12))
        .foregroundColor(theme.textSecondary)
        if let actionError {
          Text(actionError)
            .font(.custom("Figtree", size: 11))
            .foregroundColor(EmotionLabel.tense.color)
        }
      }
      Spacer()
      Button {
        NSWorkspace.shared.activateFileViewerSelecting([store.audioURL(for: note.id)])
      } label: {
        Image(systemName: "folder")
      }
      .buttonStyle(VoicePillButtonStyle())
      .help(String(localized: "voiceNotes.reveal", defaultValue: "Show audio file in Finder"))
      Button {
        confirmingDelete = true
      } label: {
        Image(systemName: "trash")
      }
      .buttonStyle(VoicePillButtonStyle())
      .help(String(localized: "voiceNotes.delete", defaultValue: "Delete"))
    }
  }

  private var playerBar: some View {
    HStack(spacing: 12) {
      Button {
        player.togglePlayback()
      } label: {
        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
          .frame(width: 14)
      }
      .buttonStyle(VoicePillButtonStyle(prominent: true))
      .disabled(player.loadError != nil)

      Slider(
        value: Binding(
          get: { player.currentTime },
          set: { player.seek(to: $0) }),
        in: 0...max(player.duration, 0.1)
      )
      .controlSize(.small)
      .disabled(player.loadError != nil)

      Text(
        "\(MeetingNotesPrompt.formatTimestamp(player.currentTime)) / \(MeetingNotesPrompt.formatTimestamp(player.duration))"
      )
      .font(.custom("Figtree", size: 11).monospacedDigit())
      .foregroundColor(theme.textSecondary)

      if let ranges = note.speechRanges, !ranges.isEmpty {
        skipSilenceToggle(ranges: ranges)
      }
    }
    .overlay(alignment: .bottomLeading) {
      if let loadError = player.loadError {
        Text(loadError)
          .font(.custom("Figtree", size: 11))
          .foregroundColor(theme.textMuted)
          .offset(y: 16)
      }
    }
  }

  private func skipSilenceToggle(ranges: [SpeechRange]) -> some View {
    let saved = SilenceSkipper.skippableSeconds(
      ranges: ranges, duration: max(note.duration, player.duration))
    return Toggle(isOn: $skipsSilence) {
      Text(String(localized: "voiceNotes.skipSilence", defaultValue: "Skip silence"))
        .font(.custom("Figtree", size: 11))
        .foregroundColor(theme.textSecondary)
    }
    .toggleStyle(.switch)
    .controlSize(.mini)
    .help(
      String(
        localized: "voiceNotes.skipSilenceHelp",
        defaultValue: "Jumps over pauses longer than 1.5 seconds. Saves \(MeetingNotesPrompt.formatTimestamp(saved)) on this recording."
      ))
  }

  private var moodSection: some View {
    let summary = note.emotionSummary
    return VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(String(localized: "voiceNotes.mood", defaultValue: "Mood over time"))
          .font(.custom("Figtree", size: 12).weight(.semibold))
          .foregroundColor(theme.textPrimary)
        Text(String(localized: "voiceNotes.moodEstimate", defaultValue: "Estimated on your Mac"))
          .font(.custom("Figtree", size: 11))
          .foregroundColor(theme.textMuted)
          .help(
            String(
              localized: "voiceNotes.moodHelp",
              defaultValue: "A rough estimate from loudness and pitch compared with your usual voice, plus facial expression when the camera was on. Treat it as a hint, not a diagnosis."
            ))
        Spacer()
      }
      EmotionTimelineStrip(
        samples: note.emotions, duration: max(note.duration, player.duration),
        playhead: player.currentTime,
        onSeek: { player.seek(to: $0) })
      EmotionShareLegend(shares: summary.combinedShares)
    }
    .padding(12)
    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.cardFill))
  }

  private var tabPicker: some View {
    Picker("", selection: $tab) {
      Text(String(localized: "voiceNotes.tab.notes", defaultValue: "Meeting notes")).tag(Tab.notes)
      Text(String(localized: "voiceNotes.tab.transcript", defaultValue: "Transcript")).tag(
        Tab.transcript)
    }
    .pickerStyle(.segmented)
    .labelsHidden()
    .frame(maxWidth: 280)
  }

  // MARK: - Notes

  @ViewBuilder
  private var notesContent: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 8) {
        Button {
          Task { await store.generateMeetingNotes(for: note.id) }
        } label: {
          Label(
            note.notes == nil
              ? String(localized: "voiceNotes.generate", defaultValue: "Generate meeting notes")
              : String(localized: "voiceNotes.regenerate", defaultValue: "Regenerate"),
            systemImage: "sparkles")
        }
        .buttonStyle(VoicePillButtonStyle(prominent: note.notes == nil))
        .disabled(isGenerating || note.transcript.isEmpty)

        if let notes = note.notes {
          Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(notes, forType: .string)
          } label: {
            Label(String(localized: "voiceNotes.copy", defaultValue: "Copy"), systemImage: "doc.on.doc")
          }
          .buttonStyle(VoicePillButtonStyle())
        }
        if isGenerating {
          ProgressView().controlSize(.small)
        }
      }

      if let generationError {
        Text(generationError)
          .font(.custom("Figtree", size: 12))
          .foregroundColor(EmotionLabel.tense.color)
          .fixedSize(horizontal: false, vertical: true)
      }

      if let notes = note.notes {
        ChatMarkdownContentView(content: notes)
      } else if note.transcript.isEmpty {
        placeholder(
          String(
            localized: "voiceNotes.noTranscriptHint",
            defaultValue: "This recording has no transcript, so there's nothing to summarize. Check that Speech Recognition is allowed in System Settings."
          ))
      } else {
        placeholder(
          String(
            localized: "voiceNotes.generateHint",
            defaultValue: "Uses your AI provider from Settings to write a summary, decisions, and action items from the transcript."
          ))
      }
    }
  }

  // MARK: - Transcript

  @ViewBuilder
  private var transcriptContent: some View {
    if note.transcript.isEmpty {
      placeholder(
        String(localized: "voiceNotes.transcriptEmpty", defaultValue: "No speech was transcribed."))
    } else {
      VStack(alignment: .leading, spacing: 12) {
        ForEach(note.transcript) { segment in
          TranscriptLine(segment: segment, onTapTime: { player.seek(to: segment.offset, play: true) })
        }
      }
    }
  }

  private func placeholder(_ text: String) -> some View {
    Text(text)
      .font(.custom("Figtree", size: 13))
      .foregroundColor(theme.textMuted)
      .fixedSize(horizontal: false, vertical: true)
  }

  // MARK: - Actions

  private func saveTitle() {
    let trimmed = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed != note.title,
      let current = store.note(with: note.id)
    else {
      titleDraft = note.title
      return
    }
    do {
      try store.save(current.withTitle(trimmed))
      actionError = nil
    } catch {
      actionError = error.localizedDescription
    }
  }

  private func delete() {
    player.stop()
    do {
      try store.delete(note.id)
      onDelete()
    } catch {
      actionError = error.localizedDescription
    }
  }
}
