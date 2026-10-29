//
//  VoiceActivityDetector.swift
//  Dayflow
//
//  Decides frame by frame whether someone is speaking. A frame counts as speech
//  when it is clearly louder than the tracked background noise and has a pitch,
//  which keeps typing, fans, and clicks out. Short onsets are ignored and a short
//  hangover keeps word endings, so regions don't flicker.
//

import Foundation

struct VoiceActivityDetector: Equatable, Sendable {
  struct Configuration: Equatable, Sendable {
    /// Seconds per analyzed frame.
    var frameDuration: TimeInterval = 1024 / 16_000
    /// How far above the noise floor speech must be, in dB.
    var marginDB: Double = 10
    /// The noise floor never drops below this, so digital silence doesn't make every breath speech.
    var minimumFloorDB: Double = -65
    /// Consecutive speech-like frames before speech starts (~0.2 s).
    var onsetFrames = 3
    /// Frames speech continues after the last speech-like frame (~0.5 s).
    var hangoverFrames = 8
  }

  let configuration: Configuration
  private(set) var noiseFloorDB: Double
  private(set) var isSpeaking = false
  private var candidateFrames = 0
  private var hangoverLeft = 0

  init(configuration: Configuration = Configuration()) {
    self.configuration = configuration
    noiseFloorDB = configuration.minimumFloorDB
  }

  /// Feeds one frame and returns whether it is part of speech.
  mutating func process(levelDB: Double, hasPitch: Bool) -> Bool {
    let threshold = noiseFloorDB + configuration.marginDB
    let speechLike = hasPitch && levelDB > threshold

    if speechLike {
      candidateFrames += 1
      if candidateFrames >= configuration.onsetFrames {
        isSpeaking = true
        hangoverLeft = configuration.hangoverFrames
      }
    } else {
      candidateFrames = 0
      if hangoverLeft > 0 {
        hangoverLeft -= 1
      } else {
        isSpeaking = false
      }
      updateNoiseFloor(levelDB)
    }
    return isSpeaking
  }

  /// Falls quickly to quieter rooms and rises slowly, so speech doesn't drag it up.
  private mutating func updateNoiseFloor(_ levelDB: Double) {
    let rate = levelDB < noiseFloorDB ? 0.3 : 0.02
    noiseFloorDB = max(noiseFloorDB + (levelDB - noiseFloorDB) * rate, configuration.minimumFloorDB)
  }
}

/// A stretch of the recording where someone was speaking, in seconds.
struct SpeechRange: Codable, Equatable, Sendable {
  let start: TimeInterval
  let end: TimeInterval

  var duration: TimeInterval { end - start }
}

/// Collects per-frame speech decisions into ranges.
struct SpeechRangeBuilder: Equatable, Sendable {
  let frameDuration: TimeInterval
  private(set) var ranges: [SpeechRange] = []
  private var openStart: TimeInterval?
  private var frameIndex = 0

  init(frameDuration: TimeInterval) {
    self.frameDuration = frameDuration
  }

  mutating func add(isSpeech: Bool) {
    let time = Double(frameIndex) * frameDuration
    frameIndex += 1
    if isSpeech, openStart == nil {
      // Speech is confirmed a few frames late; start the range where it began.
      openStart = time
    } else if !isSpeech, let start = openStart {
      ranges.append(SpeechRange(start: start, end: time))
      openStart = nil
    }
  }

  /// Closes any open range at the current position.
  func finished(onsetFrames: Int) -> [SpeechRange] {
    let lead = Double(max(onsetFrames - 1, 0)) * frameDuration
    var all = ranges
    if let start = openStart {
      all.append(SpeechRange(start: start, end: Double(frameIndex) * frameDuration))
    }
    return all.map { SpeechRange(start: max($0.start - lead, 0), end: $0.end) }
  }
}

enum SilenceSkipper {
  /// Silences shorter than this are kept; they're natural pauses.
  static let minimumGap: TimeInterval = 1.5
  /// Lands a little before speech so the first syllable isn't clipped.
  static let leadIn: TimeInterval = 0.2

  /// Where to jump when `time` sits inside a long silence, or nil to keep playing.
  static func skipTarget(
    at time: TimeInterval, ranges: [SpeechRange], duration: TimeInterval,
    minimumGap: TimeInterval = minimumGap
  ) -> TimeInterval? {
    guard !ranges.isEmpty else { return nil }
    if ranges.contains(where: { time >= $0.start - leadIn && time < $0.end }) { return nil }

    let previousEnd = ranges.last { $0.end <= time }?.end ?? 0
    let next = ranges.first { $0.start - leadIn > time }
    let gapEnd = next?.start ?? duration
    guard gapEnd - previousEnd >= minimumGap else { return nil }
    return next.map { max($0.start - leadIn, time) } ?? duration
  }

  /// Total seconds that skipping would save.
  static func skippableSeconds(ranges: [SpeechRange], duration: TimeInterval) -> TimeInterval {
    guard !ranges.isEmpty else { return 0 }
    var bounds = [0.0]
    for range in ranges { bounds.append(contentsOf: [range.start, range.end]) }
    bounds.append(duration)
    return stride(from: 0, to: bounds.count - 1, by: 2)
      .map { max(bounds[$0 + 1] - bounds[$0], 0) }
      .filter { $0 >= minimumGap }
      .reduce(0, +)
  }
}
