import XCTest
import XCUITestKit

/// The Open Logbook window, shown at launch when no logbook window is restored.
@MainActor
struct OpenLogbookScreen {
  let app: XCUIApplication

  private var openDefaultButton: XCUIElement {
    app.buttons["openDefaultLogbookButton"]
  }

  /// Launches the app without restoring earlier windows, with crash reporting and update checks
  /// off, and waits for the Open Logbook window.
  static func launch() -> Self {
    let app = XCUIApplication()
    app.launchArguments += ["-ApplePersistenceIgnoreState", "YES", "-UITestRun", "YES"]
    app.launchAndWaitUntilReady { $0.buttons["openDefaultLogbookButton"] }
    return Self(app: app)
  }

  /// Fails the test unless the window offers to open LogTen's logbook.
  func assertOffersDefaultLogbook(file: StaticString = #filePath, line: UInt = #line) {
    openDefaultButton.assertExists(file: file, line: line)
  }

  /// Chooses About LogTen Assistant from the app menu.
  func openAbout() -> AboutScreen {
    app.clickMenuItem("About LogTen Assistant", in: "LogTen Assistant")
    return AboutScreen(app: app)
  }
}
