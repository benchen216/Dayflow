import SwiftUI

/// Voice notes tab: record on the left, review a recording on the right.
struct VoiceNotesView: View {
  @Environment(\.dayflowTheme) private var theme
  @ObservedObject private var store = VoiceNoteStore.shared
  @ObservedObject private var recorder = VoiceNoteRecorder.shared
  @AppStorage(VoiceNoteRecorder.cameraPreferenceKey) private var useCamera = false
  @AppStorage(SpeechLanguage.preferenceKey) private var speechLanguage = SpeechLanguage.followApp
  @AppStorage(SpeechEngine.preferenceKey) private var speechEngine = SpeechEngine.apple.rawValue
  @State private var selectedID: UUID?

  var body: some View {
    HStack(spacing: 0) {
      sidebar
        .frame(width: 280)
      Rectangle()
        .fill(theme.rightPanelDivider)
        .frame(width: 1)
      detail
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .onAppear {
      if selectedID == nil { selectedID = store.notes.first?.id }
    }
  }

  // MARK: - Left column

  private var sidebar: some View {
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 4) {
        Text(String(localized: "voiceNotes.title", defaultValue: "Voice notes"))
          .font(.custom("InstrumentSerif-Regular", size: 32))
          .foregroundColor(theme.textPrimary)
        Text(
          String(
            localized: "voiceNotes.subtitle",
            defaultValue: "Record a conversation, read it back, and get AI meeting notes."))
          .font(.custom("Figtree", size: 12))
          .foregroundColor(theme.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      recordCard

      if let loadError = store.loadError {
        Text(loadError)
          .font(.custom("Figtree", size: 11))
          .foregroundColor(theme.textSecondary)
      }

      ScrollView {
        LazyVStack(spacing: 6) {
          ForEach(store.notes) { note in
            VoiceNoteRow(note: note, isSelected: selectedID == note.id)
              .onTapGesture { selectedID = note.id }
          }
        }
      }
      .overlay {
        if store.notes.isEmpty && !recorder.isRecording {
          Text(
            String(
              localized: "voiceNotes.empty",
              defaultValue: "No recordings yet. Press Start recording to capture your first one."))
            .font(.custom("Figtree", size: 12))
            .foregroundColor(theme.textMuted)
            .multilineTextAlignment(.center)
            .padding()
        }
      }
    }
    .padding(20)
  }

  /// Only offered once the local model files are in place.
  private var enginePicker: some View {
    HStack(spacing: 8) {
      Text(String(localized: "voiceNotes.engine", defaultValue: "Speech engine"))
        .font(.custom("Figtree", size: 12))
        .foregroundColor(theme.textSecondary)
      Spacer(minLength: 0)
      Picker("", selection: $speechEngine) {
        Text(String(localized: "voiceNotes.engine.apple", defaultValue: "Apple"))
          .tag(SpeechEngine.apple.rawValue)
        Text(String(localized: "voiceNotes.engine.senseVoice", defaultValue: "SenseVoice (local)"))
          .tag(SpeechEngine.senseVoice.rawValue)
      }
      .labelsHidden()
      .controlSize(.small)
      .fixedSize()
    }
    .help(
      String(
        localized: "voiceNotes.engineHelp",
        defaultValue:
          "SenseVoice runs on this Mac and also hears emotion in your voice. It knows Chinese, Cantonese, English, Japanese and Korean."
      ))
  }

  private var languagePicker: some View {
    HStack(spacing: 8) {
      Text(String(localized: "voiceNotes.language", defaultValue: "Speech language"))
        .font(.custom("Figtree", size: 12))
        .foregroundColor(theme.textSecondary)
      Spacer(minLength: 0)
      Picker("", selection: $speechLanguage) {
        Text(
          String(
            localized: "voiceNotes.language.followApp", defaultValue: "Same as app language")
        ).tag(SpeechLanguage.followApp)
        ForEach(SpeechLanguage.options, id: \.self) { identifier in
          Text(SpeechLanguage.displayName(identifier)).tag(identifier)
        }
      }
      .labelsHidden()
      .controlSize(.small)
      .fixedSize()
    }
    .help(
      String(
        localized: "voiceNotes.languageHelp",
        defaultValue: "Speech recognition can't detect the language, so pick the one you'll speak."
      ))
  }

  private var recordCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      switch recorder.state {
      case .recording(let startedAt):
        TimelineView(.periodic(from: startedAt, by: 1)) { context in
          HStack(spacing: 8) {
            Circle().fill(Color.red).frame(width: 9, height: 9)
            Text(MeetingNotesPrompt.formatTimestamp(context.date.timeIntervalSince(startedAt)))
              .font(.custom("Figtree", size: 22).weight(.semibold).monospacedDigit())
              .foregroundColor(theme.textPrimary)
          }
        }
        VoiceLevelMeter(levelDB: recorder.level)
        Button {
          Task {
            if let id = await recorder.stop() { selectedID = id }
          }
        } label: {
          Label(
            String(localized: "voiceNotes.stop", defaultValue: "Stop and save"),
            systemImage: "stop.fill")
        }
        .buttonStyle(VoicePillButtonStyle(prominent: true, tint: .red))
      case .starting:
        ProgressView().controlSize(.small)
      case .idle, .failed:
        Button {
          Task { await recorder.start(useCamera: useCamera) }
        } label: {
          Label(
            String(localized: "voiceNotes.record", defaultValue: "Start recording"),
            systemImage: "mic.fill")
        }
        .buttonStyle(VoicePillButtonStyle(prominent: true))
        languagePicker
        if SenseVoiceRuntime.isInstalled() { enginePicker }
        Toggle(isOn: $useCamera) {
          Text(
            String(
              localized: "voiceNotes.cameraToggle",
              defaultValue: "Also read mood from the camera"))
            .font(.custom("Figtree", size: 12))
            .foregroundColor(theme.textSecondary)
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
        .help(
          String(
            localized: "voiceNotes.cameraHelp",
            defaultValue: "Frames are analyzed on your Mac every 2 seconds and never saved."))
        Button {
          if recorder.cameraSession == nil {
            Task { await recorder.startCameraTest() }
          } else {
            recorder.stopCameraTest()
          }
        } label: {
          Label(
            recorder.cameraSession == nil ? "Test the camera" : "Stop the camera test",
            systemImage: recorder.cameraSession == nil ? "camera" : "camera.fill")
        }
        .buttonStyle(.plain)
        .font(.custom("Figtree", size: 12))
        .foregroundColor(theme.textSecondary)
      }

      if case .failed(let message) = recorder.state {
        errorText(message)
      }
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.cardFill))
    .overlay(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .strokeBorder(theme.cardBorder, lineWidth: 0.6))
  }

  private func errorText(_ message: String) -> some View {
    Text(message)
      .font(.custom("Figtree", size: 11))
      .foregroundColor(EmotionLabel.tense.color)
      .fixedSize(horizontal: false, vertical: true)
  }

  // MARK: - Right column

  @ViewBuilder
  private var detail: some View {
    if recorder.isRecording {
      LiveRecordingView(recorder: recorder)
    } else if recorder.cameraSession != nil {
      ScrollView { CameraDebugPanel(recorder: recorder).padding(20) }
    } else if let id = selectedID, let note = store.note(with: id) {
      VoiceNoteDetailView(note: note, onDelete: { selectedID = store.notes.first?.id })
        .id(note.id)
    } else {
      VStack(spacing: 8) {
        Image(systemName: "waveform")
          .font(.system(size: 28))
          .foregroundColor(theme.textMuted)
        Text(String(localized: "voiceNotes.pick", defaultValue: "Pick a recording to review it."))
          .font(.custom("Figtree", size: 13))
          .foregroundColor(theme.textMuted)
      }
    }
  }
}

private struct VoiceNoteRow: View {
  @Environment(\.dayflowTheme) private var theme
  let note: VoiceNote
  let isSelected: Bool

  var body: some View {
    HStack(spacing: 10) {
      Circle()
        .fill(note.emotionSummary.dominant?.color ?? theme.textMuted.opacity(0.4))
        .frame(width: 8, height: 8)
      VStack(alignment: .leading, spacing: 2) {
        Text(note.title)
          .font(.custom("Figtree", size: 13).weight(.semibold))
          .foregroundColor(theme.textPrimary)
          .lineLimit(1)
        HStack(spacing: 6) {
          Text(note.createdAt, format: .dateTime.month().day().hour().minute())
          Text("·")
          Text(MeetingNotesPrompt.formatTimestamp(note.duration))
          if note.notes != nil {
            Image(systemName: "sparkles").font(.system(size: 9))
          }
        }
        .font(.custom("Figtree", size: 11))
        .foregroundColor(theme.textSecondary)
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .background(
      RoundedRectangle(cornerRadius: 9, style: .continuous)
        .fill(isSelected ? theme.chipFill : Color.clear)
    )
    .contentShape(Rectangle())
    .pointingHandCursor()
  }
}

private struct LiveRecordingView: View {
  @Environment(\.dayflowTheme) private var theme
  @ObservedObject var recorder: VoiceNoteRecorder

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(spacing: 8) {
        EmotionChip(
          caption: String(localized: "voiceNotes.source.voice", defaultValue: "Voice"),
          label: recorder.voiceMood)
        if recorder.faceMood != nil {
          EmotionChip(
            caption: String(localized: "voiceNotes.source.face", defaultValue: "Face"),
            label: recorder.faceMood)
        }
        Spacer()
      }
      if let notice = recorder.transcriptionNotice {
        Text(notice)
          .font(.custom("Figtree", size: 11))
          .foregroundColor(theme.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      CameraDebugPanel(recorder: recorder)

      ScrollViewReader { proxy in
        ScrollView {
          VStack(alignment: .leading, spacing: 10) {
            ForEach(recorder.committedTranscript) { segment in
              TranscriptLine(segment: segment)
            }
            if !recorder.partialTranscript.isEmpty {
              Text(recorder.partialTranscript)
                .font(.custom("Figtree", size: 14))
                .foregroundColor(theme.textSecondary)
            }
            Color.clear.frame(height: 1).id("bottom")
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: recorder.partialTranscript) { _, _ in
          proxy.scrollTo("bottom", anchor: .bottom)
        }
      }
      .overlay {
        if recorder.committedTranscript.isEmpty && recorder.partialTranscript.isEmpty {
          Text(String(localized: "voiceNotes.listening", defaultValue: "Listening…"))
            .font(.custom("Figtree", size: 13))
            .foregroundColor(theme.textMuted)
        }
      }
    }
    .padding(24)
  }
}

struct TranscriptLine: View {
  @Environment(\.dayflowTheme) private var theme
  let segment: TranscriptSegment
  var onTapTime: (() -> Void)?

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
      Button {
        onTapTime?()
      } label: {
        Text(MeetingNotesPrompt.formatTimestamp(segment.offset))
          .font(.custom("Figtree", size: 11).monospacedDigit())
          .foregroundColor(onTapTime == nil ? theme.textMuted : theme.accentText)
      }
      .buttonStyle(.plain)
      .disabled(onTapTime == nil)
      Text(segment.text)
        .font(.custom("Figtree", size: 14))
        .foregroundColor(theme.textPrimary)
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}
