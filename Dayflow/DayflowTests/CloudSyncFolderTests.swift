import XCTest

@testable import Dayflow

final class CloudSyncFolderTests: XCTestCase {
  private let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)

  private func kind(_ path: String?) -> StorageLocation.CloudSyncKind? {
    StorageLocation.cloudSyncKind(for: path.map { URL(fileURLWithPath: $0) }, home: home)
  }

  func testICloudDriveFoldersAreDetected() {
    XCTAssertEqual(
      kind("/Users/tester/Library/Mobile Documents/com~apple~CloudDocs/Dayflow"), .iCloudDrive)
    XCTAssertEqual(kind("/Users/tester/Library/Mobile Documents"), .iCloudDrive)
  }

  func testFileProviderFoldersAreDetected() {
    XCTAssertEqual(
      kind("/Users/tester/Library/CloudStorage/GoogleDrive-me@example.com/My Drive/Dayflow"),
      .fileProvider)
    XCTAssertEqual(kind("/Users/tester/Library/CloudStorage/Dropbox/Dayflow"), .fileProvider)
  }

  func testOrdinaryAndLookalikeFoldersAreNotFlagged() {
    XCTAssertNil(kind(nil))
    XCTAssertNil(kind("/Volumes/NAS/Dayflow"))
    XCTAssertNil(kind("/Users/tester/Movies/Dayflow"))
    XCTAssertNil(kind("/Users/tester/Library/CloudStorageBackup/Dayflow"))
    XCTAssertNil(kind("/Users/tester/Library/Mobile Documents Old/Dayflow"))
  }
}
