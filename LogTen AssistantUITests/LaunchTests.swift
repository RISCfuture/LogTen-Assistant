import XCTest

final class LaunchTests: XCTestCase {
  @MainActor
  func testLaunchesToTheOpenLogbookWindow() {
    let screen = OpenLogbookScreen.launch()
    screen.assertOffersDefaultLogbook()
  }
}
