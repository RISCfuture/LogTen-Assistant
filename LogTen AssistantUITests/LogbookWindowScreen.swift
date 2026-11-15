import XCTest
import XCUITestKit

/// A logbook window showing the built-in sample logbook.
@MainActor
struct LogbookWindowScreen {
  let app: XCUIApplication

  private var violationsTable: XCUIElement { app.outlines["violationsTable"] }

  private var inspector: XCUIElement { app.descendant(id: "violationInspector") }

  /// The Data Sources page, whether or not it is showing.
  var dataSources: DataSourcesScreen { DataSourcesScreen(app: app) }

  /// The page bar's summary, such as "12 of 40 to review".
  var summary: String {
    app.descendant(id: "pageBar.summary").assertExists().text
  }

  /**
   Launches the app with the sample logbook, which never touches LogTen's files, waits for the
   audit to finish and select Logbook Consistency, the sample's first queue with a finding to
   review, and fills the screen with the window so the inspector is on screen.

   - Parameters:
     - stubsFlySto: Whether FlySto syncs are answered by the app's built-in stub, which returns
       one log of the sample logbook's Monterey flight.
     - slowAudit: Whether each audit takes three seconds longer, so a test can see it run.
   */
  static func launchWithSampleLogbook(stubsFlySto: Bool = false, slowAudit: Bool = false) -> Self {
    let app = XCUIApplication()
    app.launchArguments += ["-ApplePersistenceIgnoreState", "YES", "-UITestFixture", "sample"]
    if stubsFlySto { app.launchArguments += ["-UITestStubs", "flysto"] }
    if slowAudit { app.launchArguments += ["-UITestLoadDelay", "3"] }
    app.launchAndWaitUntilReady { $0.outlines["findingsTable.logbook_consistency"] }
    app.clickMenuItem("Fill", in: "Window")
    return Self(app: app)
  }

  /// Shows Violations ▸ All Violations.
  func showViolations() {
    app.descendant(id: "sidebar.violations").assertExists().click()
    violationsTable.assertExists()
  }

  /// Shows Audit & Fix ▸ Data Sources.
  func showDataSources() -> DataSourcesScreen {
    app.descendant(id: "sidebar.audit.data_sources").assertExists().click()
    return dataSources
  }

  /// Shows a review queue, by its identifier, such as `aircraft_comparisons`.
  func showQueue(_ queue: String) -> ReviewQueueScreen {
    app.descendant(id: "sidebar.audit.\(queue)").assertExists().click()
    return reviewQueue(queue)
  }

  /// A review queue, by its identifier, whether or not it is showing.
  func reviewQueue(_ queue: String) -> ReviewQueueScreen {
    ReviewQueueScreen(app: app, table: app.outlines["findingsTable.\(queue)"])
  }

  /// Shows the logbook-consistency findings of a category of checks, by its identifier, such as
  /// `times`.
  func showChecks(_ category: String) -> ReviewQueueScreen {
    app.descendant(id: "sidebar.checks.\(category)").assertExists().click()
    return ReviewQueueScreen(app: app, table: app.outlines["findingsTable.checks.\(category)"])
  }

  /// Types into the toolbar search field after focusing it with Find.
  func search(_ text: String) {
    app.typeKey("f", modifierFlags: .command)
    let field = app.searchFields.firstMatch.assertExists()
    field.typeKey("a", modifierFlags: .command)
    field.typeText(text)
  }

  /// Empties the toolbar search field.
  func clearSearch() {
    let field = app.searchFields.firstMatch.assertExists()
    field.click()
    field.typeKey("a", modifierFlags: .command)
    field.typeKey(.delete, modifierFlags: [])
  }

  /// Chooses a segment of the page bar's scope control, such as "Last 90 Days".
  func chooseScope(_ segment: String) {
    app.descendant(id: "pageBar.scope").assertExists().radioButtons[segment].assertExists().click()
  }

  /// Fails the test unless a segment of the scope control is selected.
  func assertScopeSelected(
    _ segment: String,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let selected = app.descendant(id: "pageBar.scope").radioButtons[segment].value as? Int
    XCTAssertEqual(selected, 1, file: file, line: line)
  }

  /// Runs the audit from the toolbar and waits for it to start and finish.
  func runAudit(file: StaticString = #filePath, line: UInt = #line) {
    app.buttons["toolbar.runAudit"].assertExists(file: file, line: line).click()
    let activity = app.descendant(id: "toolbar.activity")
    activity.assertExists("The audit never started", file: file, line: line)
    activity.assertHidden("The audit never finished", file: file, line: line)
    app.buttons["toolbar.runAudit"].assertExists(file: file, line: line)
  }

  /// Fails the test unless the page bar's summary reads `expected` once the audit is done.
  func assertSummary(
    _ expected: String,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let summary = app.descendant(id: "pageBar.summary").assertExists(file: file, line: line)
    let matches = NSPredicate(format: "value == %@ OR label == %@", expected, expected)
    if !summary.waitFor(matches, timeout: ScaledTimeouts.slowElement) {
      XCTFail("Expected the summary “\(expected)”, found “\(self.summary)”", file: file, line: line)
    }
  }

  /// Fails the test unless the page bar says a number of rules didn't run, or says nothing when
  /// the number is 0.
  func assertUncheckedRules(
    count: Int,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let button = app.descendant(id: "pageBar.uncheckedRules")
    guard count > 0 else {
      button.assertHidden(timeout: ScaledTimeouts.slowElement, file: file, line: line)
      button.assertNeverAppears(file: file, line: line)
      return
    }
    button.assertExists(timeout: ScaledTimeouts.slowElement, file: file, line: line)
    if !button.waitFor(NSPredicate(format: "label BEGINSWITH %@", "\(count) ")) {
      XCTFail("Expected \(count) unchecked rules, found “\(button.text)”", file: file, line: line)
    }
  }

  /// Undoes the last edit with the Edit menu's Undo item, which must name the action.
  func undo(_ action: String, file: StaticString = #filePath, line: UInt = #line) {
    app.clickMenuItem("Undo \(action)", in: "Edit", file: file, line: line)
  }

  /// Shows or hides the inspector with the toolbar button.
  func toggleInspector() {
    app.buttons["toolbar.inspector"].assertExists().click()
  }

  /// Presses a View menu page shortcut, such as `1` for Data Sources.
  func pressPageShortcut(_ key: String) {
    app.typeKey(key, modifierFlags: .command)
  }

  /// Shows or hides the inspector with its menu shortcut.
  func toggleInspectorWithShortcut() {
    app.typeKey("i", modifierFlags: [.command, .option])
  }

  /// Fails the test unless a review queue's table is showing, by the queue's identifier.
  func assertShowsQueue(
    _ queue: String,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    app.outlines["findingsTable.\(queue)"].assertExists(file: file, line: line)
  }

  /// Fails the test unless the Violations table is showing.
  func assertShowsViolationsTable(file: StaticString = #filePath, line: UInt = #line) {
    violationsTable.assertExists(file: file, line: line)
  }

  /// Fails the test unless the toolbar's inspector button is enabled or disabled.
  func assertInspectorButton(
    enabled: Bool,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let button = app.buttons["toolbar.inspector"].assertExists(file: file, line: line)
    XCTAssertEqual(button.isEnabled, enabled, file: file, line: line)
  }

  /// Fails the test unless a menu item of the menu bar is enabled or disabled.
  func assertMenuItem(
    _ title: String,
    in menu: String,
    enabled: Bool,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let bar = app.menuBars.firstMatch
    bar.menuBarItems[menu].click()
    let item = bar.menuItems[title].assertExists(file: file, line: line)
    XCTAssertEqual(item.isEnabled, enabled, "\(menu) ▸ \(title)", file: file, line: line)
    app.typeKey(.escape, modifierFlags: [])
  }

  /// Shows Audit & Fix ▸ Approved.
  func showApproved() -> ApprovedScreen {
    app.descendant(id: "sidebar.audit.approved").assertExists().click()
    return ApprovedScreen(app: app)
  }

  /// Shows Audit & Fix ▸ Applied History.
  func showAppliedHistory() -> AppliedHistoryScreen {
    app.descendant(id: "sidebar.audit.applied_history").assertExists().click()
    return AppliedHistoryScreen(app: app)
  }

  /// Chooses Apply ▸ Back Up Logbook from the menu bar and waits for the backup to be reported
  /// on Data Sources.
  func backUpFromMenu(file: StaticString = #filePath, line: UInt = #line) -> DataSourcesScreen {
    app.clickMenuItem("Back Up Logbook", in: "Apply")
    let dataSources = showDataSources()
    dataSources.assertStatus(beginsWith: "Backed up", file: file, line: line)
    return dataSources
  }

  /// Shows a rule's Violations page, by the rule's identifier, such as `no_nVGCurrency`.
  func showRule(_ rule: String) {
    app.descendant(id: "sidebar.rule.\(rule)").assertExists().click()
  }

  /// Clicks the button on the page of a rule that didn't run that opens the setting it needs.
  func openSettingsForUncheckedRule() -> LogbookSettingsScreen {
    app.descendant(id: "ruleNotRunSettingsButton").assertExists().click()
    return LogbookSettingsScreen(app: app)
  }

  /// Opens the page bar's list of rules that didn't run and clicks the button of one, by the
  /// rule's identifier.
  func openSettingsForUncheckedRuleInPageBar(_ rule: String) -> LogbookSettingsScreen {
    app.descendant(id: "pageBar.uncheckedRules").assertExists().click()
    app.descendant(id: "pageBar.uncheckedRules.\(rule)").assertExists().click()
    return LogbookSettingsScreen(app: app)
  }

  /// Opens Logbook Settings with Audit ▸ Logbook Settings…'s shortcut.
  func openLogbookSettings() -> LogbookSettingsScreen {
    app.typeKey(",", modifierFlags: [.command, .option])
    let sheet = LogbookSettingsScreen(app: app)
    sheet.assertShown()
    return sheet
  }

  /// Fails the test unless the page is the not-checked notice with a button titled `action`.
  func assertRuleNotChecked(
    offering action: String,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    app.descendant(id: "ruleNotRunSettingsButton").assertExists(file: file, line: line)
    app.staticTexts["Not Checked"].assertExists(file: file, line: line)
    app.buttons[action].assertExists(file: file, line: line)
  }

  /// Fails the test unless the rule's page lists flights and isn't the not-checked notice.
  func assertRuleChecked(file: StaticString = #filePath, line: UInt = #line) {
    violationsTable.assertExists(file: file, line: line)
    app.descendant(id: "ruleNotRunSettingsButton").assertHidden(file: file, line: line)
  }

  /// Fails the test unless the page bar notes what the rule can't see.
  func assertShowsLimitations(file: StaticString = #filePath, line: UInt = #line) {
    app.descendant(id: "pageBar.limitations").assertExists(file: file, line: line)
  }

  /// Fails the test unless a search that matches nothing replaced the Violations table.
  func assertShowsNoMatches(file: StaticString = #filePath, line: UInt = #line) {
    violationsTable.assertHidden(file: file, line: line)
    app.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", "No Results")).firstMatch
      .assertExists(file: file, line: line)
  }

  /// Selects the table row showing an aircraft registration.
  func selectFlight(withRegistration registration: String) {
    let cell = violationsTable.staticTexts.matching(
      NSPredicate(format: "value == %@", registration)
    ).firstMatch
    cell.assertExists()
    cell.click()
  }

  /// Fails the test unless the Violations table shows one row per flight for a number of
  /// flights.
  func assertShowsViolations(
    onFlights count: Int,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    violationsTable.assertExists(file: file, line: line)
    if !waitUntil(timeout: ScaledTimeouts.short, { violationsTable.outlineRows.count == count }) {
      let rows = violationsTable.outlineRows.count
      XCTFail("Expected \(count) flights with violations, found \(rows)", file: file, line: line)
    }
  }

  /// Fails the test unless the inspector links to a regulation.
  func assertInspectorCites(
    _ citation: String,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    inspector.links[citation].assertExists(file: file, line: line)
  }
}

/// Polls a condition on the main run loop until it holds or the timeout passes, and returns
/// whether it held.
@MainActor
private func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
  let deadline = Date.now.addingTimeInterval(timeout)
  while !condition() {
    if Date.now >= deadline { return false }
    RunLoop.current.run(until: .now.addingTimeInterval(0.2))
  }
  return true
}

extension XCUIElement {
  /// The element's value when it is text, else its label.
  var text: String {
    (value as? String).flatMap { $0.isEmpty ? nil : $0 } ?? label
  }
}
