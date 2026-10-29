//
//  EmotionEstimator.swift
//  Dayflow
//
//  Turns measurements into a mood estimate. macOS has no built-in emotion API, so
//  these are transparent heuristics that compare each moment against the
//  speaker's own baseline for this recording. Everything runs on the Mac; no
//  audio or camera frames leave it for this.
//

import Foundation

// MARK: - Voice

/// Acoustic features for a few seconds of speech.
struct VoiceFeatures: Equatable, Sendable {
  /// Mean loudness of voiced frames, in dBFS (negative, louder is closer to 0).
  let loudnessDB: Double
  /// Mean fundamental frequency of voiced frames, in Hz.
  let pitchHz: Double
  /// Standard deviation of pitch divided by its mean. Lively speech varies more.
  let pitchVariation: Double
  /// Share of frames that contained speech, 0...1.
  let voicedRatio: Double
}

/// Running averages of the speaker's own voice, so "loud" means loud for them.
struct VoiceBaseline: Equatable, Sendable {
  private(set) var loudnessDB: Double = 0
  private(set) var pitchHz: Double = 0
  private(set) var pitchVariation: Double = 0
  private(set) var count: Int = 0

  /// Windows needed before estimates are trusted.
  static let warmupWindows = 3

  var isWarm: Bool { count >= Self.warmupWindows }

  func adding(_ features: VoiceFeatures) -> VoiceBaseline {
    var next = self
    next.count += 1
    let weight = 1 / Double(min(next.count, 20))
    next.loudnessDB += (features.loudnessDB - loudnessDB) * weight
    next.pitchHz += (features.pitchHz - pitchHz) * weight
    next.pitchVariation += (features.pitchVariation - pitchVariation) * weight
    return next
  }
}

enum VoiceEmotionEstimator {
  static let minimumVoicedRatio = 0.2

  /// Returns nil for silence or before the baseline has warmed up.
  static func estimate(_ features: VoiceFeatures, baseline: VoiceBaseline) -> (
    label: EmotionLabel, confidence: Double
  )? {
    guard features.voicedRatio >= minimumVoicedRatio, baseline.isWarm else { return nil }

    // About 6 dB is a clearly louder or softer delivery.
    let energy = (features.loudnessDB - baseline.loudnessDB) / 6
    let pitchShift = baseline.pitchHz > 0 ? (features.pitchHz - baseline.pitchHz) / baseline.pitchHz / 0.15 : 0
    let liveliness =
      baseline.pitchVariation > 0
      ? (features.pitchVariation - baseline.pitchVariation) / max(baseline.pitchVariation, 0.05)
      : 0
    let arousal = 0.6 * energy + 0.4 * pitchShift

    let label: EmotionLabel
    let strength: Double
    if arousal > 0.6 {
      // Raised and animated reads as energized; raised but flat reads as strained.
      label = liveliness >= 0 ? .energized : .tense
      strength = arousal
    } else if arousal < -0.6 {
      label = liveliness < -0.2 ? .low : .calm
      strength = -arousal
    } else if liveliness > 0.5 {
      label = .happy
      strength = liveliness
    } else {
      label = .neutral
      strength = 1 - abs(arousal)
    }
    return (label, clamp(strength / 2))
  }
}

// MARK: - Face

/// Facial geometry from Vision landmarks, normalized to the face box.
struct FaceMetrics: Equatable, Sendable {
  /// How far the mouth corners sit above the lip center (positive is a smile).
  let mouthCornerLift: Double
  /// Inner lip gap relative to face height.
  let mouthOpenness: Double
  /// Average eye height divided by eye width.
  let eyeOpenness: Double
  /// Gap between eyebrows and eyes relative to face height.
  let browRaise: Double
}

struct FaceBaseline: Equatable, Sendable {
  private(set) var mouthCornerLift: Double = 0
  private(set) var mouthOpenness: Double = 0
  private(set) var eyeOpenness: Double = 0
  private(set) var browRaise: Double = 0
  private(set) var count: Int = 0

  static let warmupFrames = 3

  var isWarm: Bool { count >= Self.warmupFrames }

  func adding(_ metrics: FaceMetrics) -> FaceBaseline {
    var next = self
    next.count += 1
    let weight = 1 / Double(min(next.count, 30))
    next.mouthCornerLift += (metrics.mouthCornerLift - mouthCornerLift) * weight
    next.mouthOpenness += (metrics.mouthOpenness - mouthOpenness) * weight
    next.eyeOpenness += (metrics.eyeOpenness - eyeOpenness) * weight
    next.browRaise += (metrics.browRaise - browRaise) * weight
    return next
  }
}

enum FaceEmotionEstimator {
  static func estimate(_ metrics: FaceMetrics, baseline: FaceBaseline) -> (
    label: EmotionLabel, confidence: Double
  )? {
    guard baseline.isWarm else { return nil }

    let smile = (metrics.mouthCornerLift - baseline.mouthCornerLift) / 0.02
    let brow = (metrics.browRaise - baseline.browRaise) / 0.015
    let eyes = baseline.eyeOpenness > 0 ? (metrics.eyeOpenness - baseline.eyeOpenness) / baseline.eyeOpenness / 0.25 : 0
    let mouth = (metrics.mouthOpenness - baseline.mouthOpenness) / 0.03

    if smile > 1 {
      return (.happy, clamp(smile / 3))
    }
    if brow > 1 && (eyes > 0.5 || mouth > 1) {
      return (.energized, clamp((brow + max(eyes, mouth)) / 5))
    }
    if brow < -1 && smile < 0 {
      return (.tense, clamp(-brow / 3))
    }
    if eyes < -1 {
      return (.low, clamp(-eyes / 3))
    }
    let stillness = max(abs(smile), abs(brow), abs(eyes))
    return stillness < 0.4 ? (.calm, clamp(1 - stillness)) : (.neutral, 0.4)
  }
}

private func clamp(_ value: Double) -> Double {
  min(max(value, 0), 1)
}

// MARK: - Signal processing

enum VoiceSignal {
  /// Frames quieter than this are not worth a pitch search.
  static let silenceThresholdDB = -60.0

  static func loudnessDB(_ samples: [Float]) -> Double {
    guard !samples.isEmpty else { return -160 }
    let sumSquares = samples.reduce(Float(0)) { $0 + $1 * $1 }
    let rms = sqrt(Double(sumSquares) / Double(samples.count))
    return rms > 0 ? 20 * log10(rms) : -160
  }

  /// Autocorrelation pitch estimate for speech (70–400 Hz). Nil when unvoiced.
  static func pitchHz(_ samples: [Float], sampleRate: Double) -> Double? {
    let minLag = Int(sampleRate / 400)
    let maxLag = Int(sampleRate / 70)
    guard samples.count > maxLag * 2, minLag > 0 else { return nil }

    var energy: Float = 0
    for sample in samples { energy += sample * sample }
    guard energy > 0 else { return nil }

    var bestLag = 0
    var bestCorrelation: Float = 0
    let count = samples.count
    for lag in minLag...maxLag {
      var correlation: Float = 0
      for index in 0..<(count - lag) {
        correlation += samples[index] * samples[index + lag]
      }
      if correlation > bestCorrelation {
        bestCorrelation = correlation
        bestLag = lag
      }
    }
    // A weak peak means noise rather than a voiced sound.
    guard bestLag > 0, bestCorrelation / energy > 0.3 else { return nil }
    return sampleRate / Double(bestLag)
  }

  /// Summarizes per-frame measurements for one analysis window. `speech` holds the
  /// voice activity decision for each frame.
  static func features(loudness: [Double], pitches: [Double?], speech: [Bool]) -> VoiceFeatures? {
    guard !loudness.isEmpty else { return nil }
    let voiced = zip(zip(loudness, pitches), speech).compactMap { frame, isSpeech -> (Double, Double)? in
      guard isSpeech, let pitch = frame.1 else { return nil }
      return (frame.0, pitch)
    }
    let voicedRatio = Double(voiced.count) / Double(loudness.count)
    guard !voiced.isEmpty else {
      return VoiceFeatures(loudnessDB: -160, pitchHz: 0, pitchVariation: 0, voicedRatio: 0)
    }
    let meanLoudness = voiced.map(\.0).reduce(0, +) / Double(voiced.count)
    let pitchValues = voiced.map(\.1)
    let meanPitch = pitchValues.reduce(0, +) / Double(pitchValues.count)
    let variance =
      pitchValues.map { ($0 - meanPitch) * ($0 - meanPitch) }.reduce(0, +) / Double(pitchValues.count)
    return VoiceFeatures(
      loudnessDB: meanLoudness,
      pitchHz: meanPitch,
      pitchVariation: meanPitch > 0 ? sqrt(variance) / meanPitch : 0,
      voicedRatio: voicedRatio
    )
  }
}
