//
//  VoiceNoteStore.swift
//  Dayflow
//
//  Keeps voice notes on disk and generates their meeting notes.
//
//  Files live in the voice_notes folder under the storage location (by default
//  ~/Library/Application Support/DayflowPlus/voice_notes/):
//    <id>/note.json   transcript, mood samples, and meeting notes
//    <id>/audio.m4a   the recording
//

import Foundation

@MainActor
final class VoiceNoteStore: ObservableObject {
  static let shared = VoiceNoteStore()

  enum NotesState: Equatable {
    case idle
    case generating(UUID)
    case failed(UUID, String)
  }

  @Published private(set) var notes: [VoiceNote] = []
  @Published private(set) var notesState: NotesState = .idle
  @Published private(set) var loadError: String?

  private let rootDirectory: URL
  private let generateText: (String) async throws -> String

  init(
    rootDirectory: URL = VoiceNoteStore.defaultRootDirectory(),
    generateText: @escaping (String) async throws -> String = {
      try await LLMService.shared.generateText(prompt: $0)
    }
  ) {
    self.rootDirectory = rootDirectory
    self.generateText = generateText
    if rootDirectory.standardizedFileURL == Self.defaultRootDirectory().standardizedFileURL {
      Self.moveNotes(from: Self.legacyRootDirectories(), into: rootDirectory)
    }
    reload()
  }

  // MARK: - Files

  nonisolated static func defaultRootDirectory() -> URL {
    StorageLocation.directory("voice_notes")
  }

  /// Earlier places notes were saved: the pre-rename Dayflow folder, and the default
  /// folder from before the user picked another storage location.
  private nonisolated static func legacyRootDirectories() -> [URL] {
    [
      URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library/Application Support/Dayflow/voice_notes", isDirectory: true),
      StorageLocation.defaultBase.appendingPathComponent("voice_notes", isDirectory: true),
    ]
  }

  /// Moves each note folder that isn't already in `destination`, then drops empty sources.
  nonisolated static func moveNotes(from sources: [URL], into destination: URL) {
    let fileManager = FileManager.default
    for source in sources where source.standardizedFileURL != destination.standardizedFileURL {
      guard
        let items = try? fileManager.contentsOfDirectory(
          at: source, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
      else { continue }
      try? fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
      for item in items {
        let target = destination.appendingPathComponent(item.lastPathComponent)
        guard !fileManager.fileExists(atPath: target.path) else { continue }
        do {
          try fileManager.moveItem(at: item, to: target)
        } catch {
          print("[VoiceNotes] Couldn't move \(item.lastPathComponent): \(error)")
        }
      }
      // Anything that couldn't move stays put, so only an empty folder is removed.
      try? fileManager.removeItem(at: source.appendingPathComponent(".DS_Store"))
      if (try? fileManager.contentsOfDirectory(atPath: source.path))?.isEmpty == true {
        try? fileManager.removeItem(at: source)
      }
    }
  }

  func directory(for id: UUID) -> URL {
    rootDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
  }

  func audioURL(for id: UUID) -> URL {
    directory(for: id).appendingPathComponent(VoiceNote.audioFileName)
  }

  private func metadataURL(for id: UUID) -> URL {
    directory(for: id).appendingPathComponent("note.json")
  }

  /// Creates the folder a new recording writes its audio into.
  func prepareDirectory(for id: UUID) throws -> URL {
    let url = directory(for: id)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  // MARK: - Loading and saving

  func reload() {
    let fileManager = FileManager.default
    guard
      let folders = try? fileManager.contentsOfDirectory(
        at: rootDirectory, includingPropertiesForKeys: nil)
    else {
      notes = []
      return
    }
    let decoder = Self.makeDecoder()
    var loaded: [VoiceNote] = []
    var failures = 0
    for folder in folders where folder.hasDirectoryPath {
      let url = folder.appendingPathComponent("note.json")
      guard fileManager.fileExists(atPath: url.path) else { continue }
      do {
        loaded.append(try decoder.decode(VoiceNote.self, from: Data(contentsOf: url)))
      } catch {
        failures += 1
        print("[VoiceNotes] Could not read \(url.lastPathComponent) in \(folder.lastPathComponent): \(error)")
      }
    }
    notes = loaded.sorted { $0.createdAt > $1.createdAt }
    loadError =
      failures > 0
      ? String(
        localized: "voiceNotes.loadError",
        defaultValue: "Some recordings could not be read.")
      : nil
  }

  func save(_ note: VoiceNote) throws {
    _ = try prepareDirectory(for: note.id)
    let data = try Self.makeEncoder().encode(note)
    try data.write(to: metadataURL(for: note.id), options: .atomic)
    var updated = notes.filter { $0.id != note.id }
    updated.append(note)
    notes = updated.sorted { $0.createdAt > $1.createdAt }
  }

  func delete(_ id: UUID) throws {
    let url = directory(for: id)
    if FileManager.default.fileExists(atPath: url.path) {
      try FileManager.default.removeItem(at: url)
    }
    notes = notes.filter { $0.id != id }
    if case .failed(id, _) = notesState { notesState = .idle }
  }

  func note(with id: UUID) -> VoiceNote? {
    notes.first { $0.id == id }
  }

  // MARK: - Meeting notes

  func generateMeetingNotes(for id: UUID) async {
    guard let note = note(with: id) else { return }
    guard !note.transcript.isEmpty else {
      notesState = .failed(
        id,
        String(
          localized: "voiceNotes.noTranscript",
          defaultValue: "There is no transcript to summarize yet."))
      return
    }
    notesState = .generating(id)
    let prompt = MeetingNotesPrompt.build(
      note: note,
      languageInstruction: LLMOutputLanguagePreferences.languageInstruction(forJSON: false))
    do {
      let reply = try await generateText(prompt)
      let parsed = MeetingNotesPrompt.parse(reply)
      guard !parsed.body.isEmpty else {
        throw NSError(
          domain: "VoiceNotes", code: 1,
          userInfo: [NSLocalizedDescriptionKey: "The AI provider returned an empty reply."])
      }
      // The note may have been renamed or deleted while the provider was working.
      guard let current = self.note(with: id) else {
        notesState = .idle
        return
      }
      try save(current.withNotes(parsed.body, title: parsed.title, at: Date()))
      notesState = .idle
      AnalyticsService.shared.capture("voice_note_notes_generated", ["seconds": Int(note.duration)])
    } catch {
      notesState = .failed(id, error.localizedDescription)
    }
  }

  // MARK: - Coding

  private static func makeEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }

  private static func makeDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }
}
