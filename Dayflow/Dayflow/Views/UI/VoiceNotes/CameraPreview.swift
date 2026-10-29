//
//  CameraPreview.swift
//  Dayflow
//
//  A live look at what the face check sees: the camera picture, a box around the face Vision
//  found, a second box around the square the emotion model was shown, and the model's
//  probabilities. For checking that the face check works. Nothing is saved.
//

import AVFoundation
import AppKit
import SwiftUI

struct CameraPreview: NSViewRepresentable {
  let session: AVCaptureSession
  let frame: FaceFrame?

  func makeNSView(context: Context) -> PreviewView {
    PreviewView(session: session)
  }

  func updateNSView(_ view: PreviewView, context: Context) {
    view.show(frame)
  }

  final class PreviewView: NSView {
    private let previewLayer: AVCaptureVideoPreviewLayer
    private let faceBoxLayer = PreviewView.boxLayer(color: .systemGreen)
    private let cropBoxLayer = PreviewView.boxLayer(color: .systemYellow)

    init(session: AVCaptureSession) {
      previewLayer = AVCaptureVideoPreviewLayer(session: session)
      super.init(frame: .zero)
      wantsLayer = true
      layer?.backgroundColor = NSColor.black.cgColor
      previewLayer.videoGravity = .resizeAspect
      layer?.addSublayer(previewLayer)
      layer?.addSublayer(cropBoxLayer)
      layer?.addSublayer(faceBoxLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private var lastFrame: FaceFrame?

    override func layout() {
      super.layout()
      previewLayer.frame = bounds
      show(lastFrame)
    }

    func show(_ frame: FaceFrame?) {
      lastFrame = frame
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      place(faceBoxLayer, visionRect: frame?.faceBox)
      place(cropBoxLayer, visionRect: frame?.emotion?.cropRect)
      CATransaction.commit()
    }

    /// Vision's origin is the bottom left; the preview layer wants the top left.
    private func place(_ box: CALayer, visionRect: CGRect?) {
      guard let rect = visionRect else {
        box.isHidden = true
        return
      }
      let metadata = CGRect(x: rect.minX, y: 1 - rect.maxY, width: rect.width, height: rect.height)
      box.frame = previewLayer.layerRectConverted(fromMetadataOutputRect: metadata)
      box.isHidden = false
    }

    private static func boxLayer(color: NSColor) -> CALayer {
      let layer = CALayer()
      layer.borderColor = color.cgColor
      layer.borderWidth = 2
      layer.isHidden = true
      return layer
    }
  }
}

/// The camera, the boxes, and what the model thinks. Shown while testing the camera or recording
/// with it on.
struct CameraDebugPanel: View {
  @Environment(\.dayflowTheme) private var theme
  @ObservedObject var recorder: VoiceNoteRecorder

  var body: some View {
    if let session = recorder.cameraSession {
      VStack(alignment: .leading, spacing: 10) {
        CameraPreview(session: session, frame: recorder.faceFrame)
          .aspectRatio(4 / 3, contentMode: .fit)
          .frame(maxWidth: 420)
          .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        legend
        readout
      }
    }
  }

  private var legend: some View {
    HStack(spacing: 12) {
      swatch(.green, "Face Vision found")
      swatch(.yellow, "What the model saw")
    }
    .font(.custom("Figtree", size: 11))
    .foregroundColor(theme.textSecondary)
  }

  private func swatch(_ color: Color, _ text: String) -> some View {
    HStack(spacing: 5) {
      RoundedRectangle(cornerRadius: 2).stroke(color, lineWidth: 2).frame(width: 12, height: 9)
      Text(verbatim: text)
    }
  }

  @ViewBuilder
  private var readout: some View {
    if let frame = recorder.faceFrame {
      if frame.faceBox == nil {
        note("No face found in this frame.")
      } else if let emotion = frame.emotion {
        VStack(alignment: .leading, spacing: 4) {
          Text(verbatim: "\(emotion.className)  \(percent(emotion.confidence))  →  \(emotion.label.displayName)")
            .font(.custom("Figtree", size: 13).weight(.semibold))
            .foregroundColor(theme.textPrimary)
          ForEach(ranked(emotion), id: \.index) { row in
            probabilityRow(name: FaceEmotionOutput.classNames[row.index], value: row.value)
          }
        }
      } else {
        note(
          FaceEmotionModel.isInstalled()
            ? "The emotion model could not read this frame."
            : "The emotion model isn't installed, so mood comes from face geometry.")
      }
    } else {
      note("Waiting for the camera…")
    }
  }

  private func note(_ text: String) -> some View {
    Text(verbatim: text)
      .font(.custom("Figtree", size: 12))
      .foregroundColor(theme.textMuted)
  }

  private func probabilityRow(name: String, value: Double) -> some View {
    HStack(spacing: 8) {
      Text(verbatim: name)
        .font(.custom("Figtree", size: 11))
        .foregroundColor(theme.textSecondary)
        .frame(width: 70, alignment: .leading)
      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          Capsule().fill(theme.cardBorder)
          Capsule().fill(Color.accentColor).frame(width: max(2, proxy.size.width * value))
        }
      }
      .frame(width: 160, height: 6)
      Text(verbatim: percent(value))
        .font(.custom("Figtree", size: 11).monospacedDigit())
        .foregroundColor(theme.textMuted)
    }
  }

  private func ranked(_ emotion: FaceEmotionReading) -> [(index: Int, value: Double)] {
    emotion.probabilities.enumerated().map { (index: $0.offset, value: $0.element) }
      .sorted { $0.value > $1.value }
  }

  private func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }
}
