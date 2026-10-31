//
//  FaceEmotionModel.swift
//  Dayflow
//
//  Reads a facial expression with a Core ML model (EmotiEffLib / HSEmotion EfficientNet-B0,
//  converted to Core ML). It runs on this Mac and the frame is dropped afterwards.
//
//  The model isn't bundled with the app. Put the compiled model here and the feature turns on:
//
//    ~/Library/Application Support/DayflowPlus/models/emotion/EmotiEffNetB0.mlmodelc
//
//  Without it the app keeps using the geometry-based estimate.
//

import CoreML
import Foundation
import Vision

struct FaceEmotionReading: Equatable, Sendable {
  /// The square the model was shown, normalized with the origin at the bottom left (Vision space).
  let cropRect: CGRect
  /// Softmax probabilities in `FaceEmotionOutput.classNames` order.
  let probabilities: [Double]

  var topIndex: Int {
    probabilities.indices.max { probabilities[$0] < probabilities[$1] } ?? 0
  }
  var className: String { FaceEmotionOutput.classNames[topIndex] }
  var label: EmotionLabel { FaceEmotionOutput.label(forClass: topIndex) }
  var confidence: Double { probabilities.isEmpty ? 0 : probabilities[topIndex] }
}

final class FaceEmotionModel: @unchecked Sendable {
  static var modelURL: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent(AppDataDirectory.name, isDirectory: true)
      .appendingPathComponent("models", isDirectory: true)
      .appendingPathComponent("emotion", isDirectory: true)
      .appendingPathComponent("EmotiEffNetB0.mlmodelc", isDirectory: true)
  }

  static func isInstalled(at url: URL = modelURL) -> Bool {
    FileManager.default.fileExists(atPath: url.path)
  }

  private let model: VNCoreMLModel

  init(url: URL = FaceEmotionModel.modelURL) throws {
    let configuration = MLModelConfiguration()
    configuration.computeUnits = .all
    model = try VNCoreMLModel(for: MLModel(contentsOf: url, configuration: configuration))
  }

  /// Classifies the face inside `faceBox` (Vision's normalized box) of a camera frame.
  func read(pixelBuffer: CVPixelBuffer, faceBox: CGRect) -> FaceEmotionReading? {
    let size = CGSize(
      width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
    let crop = FaceEmotionOutput.squareCrop(around: faceBox, imageSize: size)

    let request = VNCoreMLRequest(model: model)
    request.imageCropAndScaleOption = .scaleFill
    request.regionOfInterest = crop
    do {
      try VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up).perform([request])
    } catch {
      print("[VoiceNotes] Face emotion model failed: \(error)")
      return nil
    }
    guard let logits = (request.results?.first as? VNCoreMLFeatureValueObservation)?
        .featureValue.multiArrayValue,
      logits.count == FaceEmotionOutput.classNames.count
    else { return nil }
    let values = (0..<logits.count).map { logits[$0].doubleValue }
    return FaceEmotionReading(cropRect: crop, probabilities: FaceEmotionOutput.softmax(values))
  }
}

enum FaceEmotionOutput {
  /// Output order of the 8-class AffectNet model.
  static let classNames = [
    "Anger", "Contempt", "Disgust", "Fear", "Happiness", "Neutral", "Sadness", "Surprise",
  ]

  /// Maps the model's classes onto the app's six labels.
  static func label(forClass index: Int) -> EmotionLabel {
    switch classNames[index] {
    case "Happiness": return .happy
    case "Surprise": return .energized
    case "Sadness": return .low
    case "Neutral": return .neutral
    default: return .tense  // Anger, Contempt, Disgust, Fear
    }
  }

  static func softmax(_ logits: [Double]) -> [Double] {
    guard let top = logits.max() else { return [] }
    let exps = logits.map { exp($0 - top) }
    let total = exps.reduce(0, +)
    return exps.map { $0 / total }
  }

  /// Vision's face box is tight, so widen it to a square with some margin around the head.
  /// Works in pixels so the crop is square on screen, then returns it normalized and kept
  /// inside the frame.
  static func squareCrop(
    around box: CGRect, imageSize: CGSize, margin: CGFloat = 0.25
  ) -> CGRect {
    let width = box.width * imageSize.width
    let height = box.height * imageSize.height
    let side = min(max(width, height) * (1 + margin), min(imageSize.width, imageSize.height))
    var x = box.midX * imageSize.width - side / 2
    var y = box.midY * imageSize.height - side / 2
    x = min(max(x, 0), imageSize.width - side)
    y = min(max(y, 0), imageSize.height - side)
    return CGRect(
      x: x / imageSize.width, y: y / imageSize.height,
      width: side / imageSize.width, height: side / imageSize.height)
  }
}
