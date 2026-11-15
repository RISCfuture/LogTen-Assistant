import XCTest

final class LaunchTests: XCTestCase {
  @MainActor
  func testLaunchesToTheOpenLogbookWindow() {
    let screen = OpenLogbookScreen.launch()
    screen.assertOffersDefaultLogbook()
  }

  @MainActor
  func testAboutWindowOpensItsAcknowledgements() {
    let about = OpenLogbookScreen.launch().openAbout()
    about.assertShowsIdentityAndLinks()

    about.openAcknowledgements()
    about.assertAcknowledgementsSections()
  }
}
