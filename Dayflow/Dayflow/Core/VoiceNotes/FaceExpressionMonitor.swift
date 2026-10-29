//
//  FaceExpressionMonitor.swift
//  Dayflow
//
//  Samples the camera every few seconds and measures facial geometry with Vision.
//  Frames are analyzed in memory and dropped; nothing from the camera is saved
//  or sent anywhere.
//

import AVFoundation
import Vision

final class FaceExpressionMonitor: NSObject, @unchecked Sendable {
  static let sampleInterval: TimeInterval = 2

  /// Face measurements and when they were taken, called on the main queue.
  var onMetrics: ((FaceMetrics, Date) -> Void)?

  private let session = AVCaptureSession()
  private let queue = DispatchQueue(label: "com.dayflow.voice.face")
  private var lastSample = Date.distantPast

  static func requestCameraAccess() async -> Bool {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized: return true
    case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
    default: return false
    }
  }

  func start() throws {
    guard let device = AVCaptureDevice.default(for: .video) else {
      throw FaceMonitorError.noCamera
    }
    let input = try AVCaptureDeviceInput(device: device)
    let output = AVCaptureVideoDataOutput()
    output.alwaysDiscardsLateVideoFrames = true
    output.setSampleBufferDelegate(self, queue: queue)

    session.beginConfiguration()
    session.sessionPreset = .low
    guard session.canAddInput(input), session.canAddOutput(output) else {
      session.commitConfiguration()
      throw FaceMonitorError.noCamera
    }
    session.addInput(input)
    session.addOutput(output)
    session.commitConfiguration()
    queue.async { [session] in session.startRunning() }
  }

  func stop() {
    queue.sync {
      session.stopRunning()
      session.inputs.forEach(session.removeInput)
      session.outputs.forEach(session.removeOutput)
    }
  }

  /// Measures the largest face in the frame. Nil when no usable face is found.
  static func metrics(from face: VNFaceObservation) -> FaceMetrics? {
    guard let landmarks = face.landmarks,
      let outerLips = landmarks.outerLips?.normalizedPoints, outerLips.count >= 6,
      let innerLips = landmarks.innerLips?.normalizedPoints, !innerLips.isEmpty,
      let leftEye = landmarks.leftEye?.normalizedPoints, !leftEye.isEmpty,
      let rightEye = landmarks.rightEye?.normalizedPoints, !rightEye.isEmpty,
      let leftBrow = landmarks.leftEyebrow?.normalizedPoints, !leftBrow.isEmpty,
      let rightBrow = landmarks.rightEyebrow?.normalizedPoints, !rightBrow.isEmpty
    else { return nil }

    // Landmark points are normalized to the face box with y pointing up.
    let leftCorner = outerLips.min { $0.x < $1.x }!
    let rightCorner = outerLips.max { $0.x < $1.x }!
    let lipCenterY = outerLips.map(\.y).reduce(0, +) / CGFloat(outerLips.count)
    let cornerLift = (leftCorner.y + rightCorner.y) / 2 - lipCenterY

    let innerYs = innerLips.map(\.y)
    let mouthOpen = (innerYs.max()! - innerYs.min()!)

    func openness(_ points: [CGPoint]) -> CGFloat {
      let xs = points.map(\.x)
      let ys = points.map(\.y)
      let width = xs.max()! - xs.min()!
      return width > 0 ? (ys.max()! - ys.min()!) / width : 0
    }
    func meanY(_ points: [CGPoint]) -> CGFloat {
      points.map(\.y).reduce(0, +) / CGFloat(points.count)
    }
    let browGap =
      ((meanY(leftBrow) - meanY(leftEye)) + (meanY(rightBrow) - meanY(rightEye))) / 2

    return FaceMetrics(
      mouthCornerLift: Double(cornerLift),
      mouthOpenness: Double(mouthOpen),
      eyeOpenness: Double((openness(leftEye) + openness(rightEye)) / 2),
      browRaise: Double(browGap)
    )
  }
}

extension FaceExpressionMonitor: AVCaptureVideoDataOutputSampleBufferDelegate {
  func captureOutput(
    _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    let now = Date()
    guard now.timeIntervalSince(lastSample) >= Self.sampleInterval,
      let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
    else { return }
    lastSample = now

    let request = VNDetectFaceLandmarksRequest()
    let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
    do {
      try handler.perform([request])
    } catch {
      print("[VoiceNotes] Face analysis failed: \(error)")
      return
    }
    let largest = request.results?.max {
      $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height
    }
    guard let face = largest, let metrics = Self.metrics(from: face) else { return }
    DispatchQueue.main.async { [weak self] in self?.onMetrics?(metrics, now) }
  }
}

enum FaceMonitorError: LocalizedError {
  case noCamera

  var errorDescription: String? {
    String(localized: "voiceNotes.error.noCamera", defaultValue: "No camera is available.")
  }
}
