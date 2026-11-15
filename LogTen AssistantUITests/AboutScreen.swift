import XCTest
import XCUITestKit

/// The About window and its Acknowledgements sheet.
@MainActor
struct AboutScreen {
  let app: XCUIApplication

  private var window: XCUIElement { app.windows["About LogTen Assistant"] }

  /// Fails the test unless the window shows the version and links to the website and the issue
  /// tracker.
  func assertShowsIdentityAndLinks(file: StaticString = #filePath, line: UInt = #line) {
    window.assertExists(file: file, line: line)
    window.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", "Version "))
      .firstMatch.assertExists(file: file, line: line)
    app.descendant(id: "about.website").assertExists(file: file, line: line)
    app.descendant(id: "about.reportIssue").assertExists(file: file, line: line)
  }

  /// Opens the Acknowledgements sheet.
  func openAcknowledgements() {
    app.descendant(id: "about.acknowledgements").assertExists().click()
    app.descendant(id: "about.acknowledgements.done").assertExists()
  }

  /// Fails the test unless the Acknowledgements sheet lists its two sections.
  func assertAcknowledgementsSections(file: StaticString = #filePath, line: UInt = #line) {
    app.staticTexts["Swift Packages"].assertExists(file: file, line: line)
    app.staticTexts["Data Sources"].assertExists(file: file, line: line)
  }
}
