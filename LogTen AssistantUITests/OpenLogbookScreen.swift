import XCTest
import XCUITestKit

/// The Open Logbook window, shown at launch when no logbook window is restored.
@MainActor
struct OpenLogbookScreen {
  let app: XCUIApplication

  private var openDefaultButton: XCUIElement {
    app.buttons["openDefaultLogbookButton"]
  }

  /// Launches the app without restoring earlier windows and waits for the Open Logbook window.
  static func launch() -> Self {
    let app = XCUIApplication()
    app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
    app.launchAndWaitUntilReady { $0.buttons["openDefaultLogbookButton"] }
    return Self(app: app)
  }

  /// Fails the test unless the window offers to open LogTen's logbook.
  func assertOffersDefaultLogbook(file: StaticString = #filePath, line: UInt = #line) {
    openDefaultButton.assertExists(file: file, line: line)
  }
}
