import XCTest

final class WindowTests: XCTestCase {
  @MainActor
  func testViewMenuShortcutsMoveBetweenPagesAndTheInspectorFollows() {
    let window = LogbookWindowScreen.launchWithSampleLogbook()

    window.pressPageShortcut("1")
    DataSourcesScreen(app: window.app).assertShown()
    window.assertInspectorButton(enabled: false)
    window.assertMenuItem("Hide Inspector", in: "View", enabled: false)

    window.pressPageShortcut("2")
    window.assertShowsQueue("logbook_consistency")
    let queue = window.reviewQueue("logbook_consistency")
    queue.assertInspector(isShown: true)

    window.pressPageShortcut("8")
    window.assertShowsViolationsTable()

    window.pressPageShortcut("2")
    window.toggleInspector()
    queue.assertInspector(isShown: false)
    window.assertMenuItem("Show Inspector", in: "View", enabled: true)

    window.toggleInspectorWithShortcut()
    queue.assertInspector(isShown: true)
    window.assertMenuItem("Hide Inspector", in: "View", enabled: true)
  }

  @MainActor
  func testWindowCommandsAreDisabledWhileASheetIsUp() {
    let window = LogbookWindowScreen.launchWithSampleLogbook()

    let settings = window.openLogbookSettings()
    window.assertMenuItem("Run Audit", in: "Audit", enabled: false)
    window.assertMenuItem("Logbook Settings…", in: "Audit", enabled: false)
    window.assertMenuItem("Data Sources", in: "View", enabled: false)
    window.assertMenuItem("Find…", in: "Edit", enabled: false)

    settings.cancel()
    window.assertMenuItem("Run Audit", in: "Audit", enabled: true)
    window.assertMenuItem("Logbook Settings…", in: "Audit", enabled: true)
    window.assertMenuItem("Data Sources", in: "View", enabled: true)
    window.assertMenuItem("Find…", in: "Edit", enabled: true)
  }
}
