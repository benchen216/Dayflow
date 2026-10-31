//
//  SenseVoiceModelStore.swift
//  Dayflow
//
//  Whether the SenseVoice model is on this Mac, and the one download the user can start
//  from Voice notes. The download only happens when the user asks for it.
//

import Foundation

@MainActor
final class SenseVoiceModelStore: ObservableObject {
  enum Status: Equatable {
    case notDownloaded
    case downloading(Double)
    /// Core ML compiles the model for the Neural Engine the first time it loads, which
    /// takes a minute or two; doing it here keeps the first recording from waiting on it.
    case preparing
    case ready
    case failed(String)
  }

  static let shared = SenseVoiceModelStore()

  @Published private(set) var status: Status

  private init() {
    status = SenseVoiceRuntime.Model.isInstalled() ? .ready : .notDownloaded
  }

  func download() {
    switch status {
    case .downloading, .preparing: return
    default: break
    }
    status = .downloading(0)
    Task {
      do {
        try await SenseVoiceRuntime.Model.download { fraction in
          Task { @MainActor [weak self] in
            guard let self, case .downloading = self.status else { return }
            self.status = .downloading(fraction)
          }
        }
        guard SenseVoiceRuntime.Model.isInstalled() else {
          status = .failed("")
          return
        }
        status = .preparing
        try await Task.detached(priority: .utility) {
          _ = try SenseVoiceRuntime(language: "auto")
        }.value
        status = .ready
      } catch {
        print("[VoiceNotes] SenseVoice model download failed: \(error)")
        status = .failed(error.localizedDescription)
      }
    }
  }
}
