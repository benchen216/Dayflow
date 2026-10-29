import XCTest

@testable import Dayflow

final class GarminCredentialsTests: XCTestCase {
  func testCleanedStripsWhitespaceAndQuotes() {
    XCTAssertEqual(GarminCredentials.cleaned("  abc123\n"), "abc123")
    XCTAssertEqual(GarminCredentials.cleaned("\"abc123\""), "abc123")
    XCTAssertEqual(GarminCredentials.cleaned(" 'abc123' "), "abc123")
  }

  func testCleanedRejectsEmptyInput() {
    XCTAssertNil(GarminCredentials.cleaned(""))
    XCTAssertNil(GarminCredentials.cleaned("  \n"))
    XCTAssertNil(GarminCredentials.cleaned("\"\""))
  }
}
