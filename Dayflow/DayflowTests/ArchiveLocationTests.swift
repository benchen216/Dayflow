import XCTest

@testable import Dayflow

final class ArchiveLocationTests: XCTestCase {
  private var scratch: URL!

  override func setUpWithError() throws {
    scratch = FileManager.default.temporaryDirectory
      .appendingPathComponent("archive-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: scratch)
  }

  private func makeFile(_ name: String, bytes: Int = 1_000, in folder: URL? = nil) throws -> URL {
    let directory = folder ?? scratch.appendingPathComponent("local", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent(name)
    try Data(repeating: 7, count: bytes).write(to: url)
    return url
  }

  private var archive: URL { scratch.appendingPathComponent("archive", isDirectory: true) }

  func testMoveCopiesTheFileThenRemovesTheOriginal() throws {
    let source = try makeFile("a.mp4", bytes: 2_048)
    let moved = try ArchiveLocation.move(source, into: archive)

    XCTAssertEqual(moved.deletingLastPathComponent().path, archive.path)
    XCTAssertEqual(try Data(contentsOf: moved).count, 2_048)
    XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
  }

  func testMoveNeverOverwritesAnExistingArchivedFile() throws {
    let first = try makeFile("a.mp4", bytes: 10)
    let firstMoved = try ArchiveLocation.move(first, into: archive)
    let second = try makeFile("a.mp4", bytes: 20)
    let secondMoved = try ArchiveLocation.move(second, into: archive)

    XCTAssertNotEqual(firstMoved, secondMoved)
    XCTAssertEqual(secondMoved.lastPathComponent, "a-2.mp4")
    XCTAssertEqual(try Data(contentsOf: firstMoved).count, 10)
    XCTAssertEqual(try Data(contentsOf: secondMoved).count, 20)
  }

  func testOriginalStaysWhenTheRecordUpdateFails() throws {
    struct DatabaseDown: Error {}
    let source = try makeFile("a.mp4")

    XCTAssertThrowsError(
      try ArchiveLocation.move(source, into: archive) { _ in throw DatabaseDown() })

    XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: archive.path)) ?? []
    XCTAssertTrue(leftovers.isEmpty, "The half-done copy should be removed: \(leftovers)")
  }

  func testRecordUpdateSeesTheFinalPathBeforeTheOriginalIsRemoved() throws {
    let source = try makeFile("a.mp4")
    var originalExistedDuringUpdate = false
    var updatedPath: String?

    let moved = try ArchiveLocation.move(source, into: archive) { destination in
      originalExistedDuringUpdate = FileManager.default.fileExists(atPath: source.path)
      updatedPath = destination.path
    }

    XCTAssertTrue(originalExistedDuringUpdate)
    XCTAssertEqual(updatedPath, moved.path)
  }

  func testArchiveInsideOrAroundTheStorageFolderIsRejected() throws {
    let storage = scratch.appendingPathComponent("storage", isDirectory: true)
    let inside = storage.appendingPathComponent("archive", isDirectory: true)
    try FileManager.default.createDirectory(at: inside, withIntermediateDirectories: true)

    XCTAssertThrowsError(try ArchiveLocation.validate(storage, storageBase: storage))
    XCTAssertThrowsError(try ArchiveLocation.validate(inside, storageBase: storage))
    XCTAssertThrowsError(try ArchiveLocation.validate(scratch, storageBase: storage))

    let elsewhere = scratch.appendingPathComponent("nas", isDirectory: true)
    try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
    XCTAssertNoThrow(try ArchiveLocation.validate(elsewhere, storageBase: storage))
  }
}
