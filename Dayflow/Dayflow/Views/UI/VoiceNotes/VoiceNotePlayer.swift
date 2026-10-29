import AVFoundation
import Combine

/// Plays a voice note's audio and publishes the playhead for the UI.
@MainActor
final class VoiceNotePlayer: NSObject, ObservableObject {
  @Published private(set) var isPlaying = false
  @Published private(set) var currentTime: TimeInterval = 0
  @Published private(set) var duration: TimeInterval = 0
  @Published private(set) var loadError: String?

  /// Speech regions used to jump over long silences.
  var speechRanges: [SpeechRange] = []
  var skipsSilence = false

  private var player: AVAudioPlayer?
  private var timer: AnyCancellable?
  private(set) var loadedURL: URL?

  func load(_ url: URL) {
    guard url != loadedURL else { return }
    stop()
    loadedURL = url
    do {
      let player = try AVAudioPlayer(contentsOf: url)
      player.delegate = self
      player.prepareToPlay()
      self.player = player
      duration = player.duration
      currentTime = 0
      loadError = nil
    } catch {
      player = nil
      duration = 0
      loadError = String(
        localized: "voiceNotes.player.missing", defaultValue: "The audio for this recording is missing.")
    }
  }

  func togglePlayback() {
    guard let player else { return }
    if player.isPlaying {
      player.pause()
      setPlaying(false)
    } else {
      player.play()
      setPlaying(true)
    }
  }

  func seek(to time: TimeInterval, play: Bool = false) {
    guard let player else { return }
    player.currentTime = min(max(time, 0), player.duration)
    currentTime = player.currentTime
    if play && !player.isPlaying {
      player.play()
      setPlaying(true)
    }
  }

  func stop() {
    player?.stop()
    setPlaying(false)
  }

  private func setPlaying(_ playing: Bool) {
    isPlaying = playing
    timer?.cancel()
    guard playing else { return }
    timer = Timer.publish(every: 0.1, on: .main, in: .common)
      .autoconnect()
      .sink { [weak self] _ in self?.tick() }
  }

  private func tick() {
    guard let player else { return }
    if skipsSilence,
      let target = SilenceSkipper.skipTarget(
        at: player.currentTime, ranges: speechRanges, duration: player.duration),
      target > player.currentTime + 0.05
    {
      if target >= player.duration - 0.05 {
        player.stop()
        player.currentTime = 0
        setPlaying(false)
      } else {
        player.currentTime = target
      }
    }
    currentTime = player.currentTime
  }
}

extension VoiceNotePlayer: AVAudioPlayerDelegate {
  nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    Task { @MainActor in
      self.setPlaying(false)
      self.currentTime = 0
    }
  }
}
