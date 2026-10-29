import CoreVideo
import XCTest

@testable import Dayflow

final class FaceEmotionTests: XCTestCase {
  func testSoftmaxSumsToOneAndKeepsOrder() {
    let probabilities = FaceEmotionOutput.softmax([1, 2, 3, 0, -1, 0.5, 0, 0])
    XCTAssertEqual(probabilities.reduce(0, +), 1, accuracy: 1e-9)
    XCTAssertEqual(probabilities.firstIndex(of: probabilities.max()!), 2)
    XCTAssertEqual(FaceEmotionOutput.softmax([]), [])
  }

  func testClassesMapToTheSixLabels() {
    func label(_ name: String) -> EmotionLabel {
      FaceEmotionOutput.label(forClass: FaceEmotionOutput.classNames.firstIndex(of: name)!)
    }
    XCTAssertEqual(label("Happiness"), .happy)
    XCTAssertEqual(label("Surprise"), .energized)
    XCTAssertEqual(label("Sadness"), .low)
    XCTAssertEqual(label("Neutral"), .neutral)
    for name in ["Anger", "Contempt", "Disgust", "Fear"] {
      XCTAssertEqual(label(name), .tense, name)
    }
  }

  func testReadingReportsTheTopClass() {
    var probabilities = [Double](repeating: 0.01, count: 8)
    probabilities[4] = 0.93
    let reading = FaceEmotionReading(cropRect: .zero, probabilities: probabilities)
    XCTAssertEqual(reading.className, "Happiness")
    XCTAssertEqual(reading.label, .happy)
    XCTAssertEqual(reading.confidence, 0.93, accuracy: 1e-9)
  }

  func testCropIsSquareOnScreenAndStaysInsideTheFrame() {
    let size = CGSize(width: 640, height: 480)
    // A face near the top-right corner, wider than the frame allows once widened.
    let box = CGRect(x: 0.8, y: 0.7, width: 0.2, height: 0.3)
    let crop = FaceEmotionOutput.squareCrop(around: box, imageSize: size)
    XCTAssertEqual(crop.width * size.width, crop.height * size.height, accuracy: 1e-6)
    XCTAssertGreaterThanOrEqual(crop.minX, 0)
    XCTAssertGreaterThanOrEqual(crop.minY, 0)
    XCTAssertLessThanOrEqual(crop.maxX, 1 + 1e-9)
    XCTAssertLessThanOrEqual(crop.maxY, 1 + 1e-9)
    // Wider than the face itself, so the forehead and chin are included.
    XCTAssertGreaterThan(crop.height * size.height, box.height * size.height)
  }

  func testCropNeverExceedsTheShorterSide() {
    let size = CGSize(width: 640, height: 480)
    let crop = FaceEmotionOutput.squareCrop(
      around: CGRect(x: 0, y: 0, width: 1, height: 1), imageSize: size)
    XCTAssertEqual(crop.height, 1, accuracy: 1e-9)
    XCTAssertEqual(crop.width * size.width, 480, accuracy: 1e-6)
  }

  // MARK: - With the real model (skipped when it isn't installed)

  func testRealModelReturnsEightProbabilities() throws {
    try XCTSkipUnless(FaceEmotionModel.isInstalled(), "Face emotion model isn't installed")
    let model = try FaceEmotionModel()

    var buffer: CVPixelBuffer?
    CVPixelBufferCreate(
      kCFAllocatorDefault, 640, 480, kCVPixelFormatType_32BGRA, nil, &buffer)
    let pixels = try XCTUnwrap(buffer)
    CVPixelBufferLockBaseAddress(pixels, [])
    memset(CVPixelBufferGetBaseAddress(pixels), 128, CVPixelBufferGetDataSize(pixels))
    CVPixelBufferUnlockBaseAddress(pixels, [])

    let reading = try XCTUnwrap(
      model.read(pixelBuffer: pixels, faceBox: CGRect(x: 0.3, y: 0.3, width: 0.3, height: 0.4)))
    XCTAssertEqual(reading.probabilities.count, 8)
    XCTAssertEqual(reading.probabilities.reduce(0, +), 1, accuracy: 1e-6)
    XCTAssertTrue(reading.probabilities.allSatisfy { $0 >= 0 })
  }
}
