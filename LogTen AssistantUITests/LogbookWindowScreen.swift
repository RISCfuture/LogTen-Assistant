import XCTest
import XCUITestKit

/// A logbook window showing the built-in sample logbook.
@MainActor
struct LogbookWindowScreen {
  let app: XCUIApplication

  private var violationsTable: XCUIElement { app.outlines["violationsTable"] }

  private var inspector: XCUIElement { app.descendant(id: "violationInspector") }

  /**
   Launches the app with the sample logbook, which never touches LogTen's files, and waits for
   the audit to finish and select Logbook Consistency, the sample's first queue with a finding
   to review.

   - Parameter stubsFlySto: Whether FlySto syncs are answered by the app's built-in stub, which
     returns one log of the sample logbook's Monterey flight.
   */
  static func launchWithSampleLogbook(stubsFlySto: Bool = false) -> Self {
    let app = XCUIApplication()
    app.launchArguments += ["-ApplePersistenceIgnoreState", "YES", "-UITestFixture", "sample"]
    if stubsFlySto { app.launchArguments += ["-UITestStubs", "flysto"] }
    app.launchAndWaitUntilReady { $0.outlines["findingsTable.logbook_consistency"] }
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
    return DataSourcesScreen(app: app)
  }

  /// Shows a review queue, by its identifier, such as `aircraft_comparisons`.
  func showQueue(_ queue: String) -> ReviewQueueScreen {
    app.descendant(id: "sidebar.audit.\(queue)").assertExists().click()
    return ReviewQueueScreen(app: app, table: app.outlines["findingsTable.\(queue)"])
  }

  /// Shows the logbook-consistency findings of a category of checks, by its identifier, such as
  /// `times`.
  func showChecks(_ category: String) -> ReviewQueueScreen {
    app.descendant(id: "sidebar.checks.\(category)").assertExists().click()
    return ReviewQueueScreen(app: app, table: app.outlines["findingsTable.checks.\(category)"])
  }

  /// Shows Audit & Fix ▸ Approved.
  func showApproved() -> ApprovedScreen {
    app.descendant(id: "sidebar.audit.approved").assertExists().click()
    return ApprovedScreen(app: app)
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
    let rows = violationsTable.outlineRows.count
    if rows != count {
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

/// The Logbook Settings sheet.
@MainActor
struct LogbookSettingsScreen {
  let app: XCUIApplication

  /// Fails the test unless the sheet shows the Custom Fields picker for a role, by the role's
  /// identifier, such as `night_takeoffs`.
  func assertShowsFieldPicker(
    for role: String,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    app.descendant(id: "customFields.role.\(role)").assertExists(file: file, line: line)
  }
}
