import XCTest
import XCUITestKit

/// Audit & Fix ▸ Data Sources.
@MainActor
struct DataSourcesScreen {
  let app: XCUIApplication

  /// The status line the last data task left.
  var status: String {
    app.descendant(id: "dataSources.status").assertExists().text
  }

  /// Syncs FlySto with the Sync Now button on the page and waits for the sync, and the audit
  /// after it, to finish.
  @discardableResult
  func syncFlyStoFromPage(file: StaticString = #filePath, line: UInt = #line) -> Self {
    app.buttons["dataSources.syncFlySto"].assertExists(file: file, line: line).click()
    assertStatus(beginsWith: "Synced", file: file, line: line)
    app.descendant(id: "toolbar.activity").assertHidden(file: file, line: line)
    return self
  }

  /// Fails the test unless the status line comes to begin with some text.
  func assertStatus(
    beginsWith prefix: String,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let status = app.descendant(id: "dataSources.status").assertExists(file: file, line: line)
    let matches = NSPredicate(format: "value BEGINSWITH %@ OR label BEGINSWITH %@", prefix, prefix)
    if !status.waitFor(matches, timeout: ScaledTimeouts.slowElement) {
      XCTFail(
        "Expected a status beginning “\(prefix)”, found “\(self.status)”",
        file: file,
        line: line
      )
    }
  }

  /// Fails the test unless the page is showing.
  func assertShown(file: StaticString = #filePath, line: UInt = #line) {
    app.descendant(id: "dataSources").assertExists(file: file, line: line)
  }
}

/// A review queue's table of findings and the finding inspector.
@MainActor
struct ReviewQueueScreen {
  let app: XCUIApplication
  let table: XCUIElement

  /// The queue's finding rows, in table order.
  private var rows: XCUIElementQuery { table.outlineRows }

  /// The number of findings the table lists.
  var rowCount: Int { rows.count }

  /// The position of the selected row, if one is.
  var selectedRowIndex: Int? {
    (0..<rows.count).first { rows.element(boundBy: $0).isSelected }
  }

  /// The inspector's statement of the decision.
  var decisionText: String {
    app.descendant(id: "findingInspector.decision").assertExists().text
  }

  /// The title the reason pop-up shows.
  var reason: String {
    app.popUpButtons["findingInspector.reason"].assertExists().value as? String ?? ""
  }

  /// The text the note field holds.
  var note: String {
    app.textFields["findingInspector.note"].assertExists().value as? String ?? ""
  }

  /// Selects the finding on an aircraft's flight.
  func selectFinding(onAircraft registration: String) -> Self {
    let cell = table.staticTexts.matching(NSPredicate(format: "value == %@", registration))
      .firstMatch
    cell.assertExists().click()
    return self
  }

  /// Chooses one of the selected finding's correction options from the inspector's pop-up
  /// menu, by its position.
  @discardableResult
  func chooseCorrection(_ index: Int) -> Self {
    app.popUpButtons["findingInspector.correctionOptions"].assertExists().click()
    app.menuItems["findingInspector.correctionOption.\(index)"].assertExists().click()
    return self
  }

  /// Marks the selected finding for correction from the inspector.
  @discardableResult
  func markForCorrection() -> Self {
    app.buttons["decide.correction"].assertExists().click()
    return self
  }

  /// Selects a finding by its position in the table.
  @discardableResult
  func selectRow(_ index: Int) -> Self {
    rows.element(boundBy: index).staticTexts.firstMatch.assertExists().click()
    return self
  }

  /// Adds a row to the selection, or removes it, with a Command-click.
  @discardableResult
  func toggleRow(_ index: Int) -> Self {
    XCUIElement.perform(withKeyModifiers: .command) {
      rows.element(boundBy: index).staticTexts.firstMatch.assertExists().click()
    }
    return self
  }

  /// Fails the test unless the decision badge on the row at a position comes to read a name,
  /// such as "Kept as Logged".
  func assertDecisionBadge(
    ofRow index: Int,
    is name: String,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let row = rows.element(boundBy: index)
    let badge = row.images["findingsTable.decision"].assertExists(file: file, line: line)
    if !badge.waitFor(NSPredicate(format: "label == %@", name)) {
      XCTFail(
        "Expected row \(index) to read “\(name)”, found “\(badge.label)”",
        file: file,
        line: line
      )
    }
  }

  /// Fails the test unless the table is on screen.
  func assertShowsTable(file: StaticString = #filePath, line: UInt = #line) {
    table.assertExists(file: file, line: line)
  }

  /// Fails the test unless the table has been replaced by an empty state.
  func assertShowsNoTable(file: StaticString = #filePath, line: UInt = #line) {
    table.assertHidden(file: file, line: line)
  }

  /// Clicks Show Data Sources on the empty state a comparison queue without evidence shows.
  func showDataSourcesFromEmptyState() -> DataSourcesScreen {
    app.buttons["emptyQueue.dataSources"].assertExists().click()
    return DataSourcesScreen(app: app)
  }

  /// Fails the test unless the empty state offering Data Sources is showing.
  func assertOffersDataSources(file: StaticString = #filePath, line: UInt = #line) {
    app.buttons["emptyQueue.dataSources"].assertExists(file: file, line: line)
  }

  /// Clicks Show All Flights on the empty state a recent scope leaves.
  func showAllFlights() {
    app.buttons["emptyQueue.showAllFlights"].assertExists().click()
  }

  /// Records a decision with one of the decision bar's buttons, by its identifier suffix, such
  /// as `false_positive`.
  @discardableResult
  func decide(_ decision: String) -> Self {
    app.buttons["decide.\(decision)"].assertExists().click()
    return self
  }

  /// Records a decision from the More Decisions menu, such as `needs_evidence`.
  @discardableResult
  func decideFromMoreMenu(_ decision: String) -> Self {
    app.descendant(id: "findingInspector.moreDecisions").assertExists().click()
    app.menuItems["decide.\(decision)"].assertExists().click()
    return self
  }

  /// Chooses a reason in the inspector's pop-up, by its title.
  @discardableResult
  func chooseReason(_ title: String) -> Self {
    app.popUpButtons["findingInspector.reason"].assertExists().click()
    app.menuItems[title].assertExists().click()
    return self
  }

  /// Types a note into the inspector and commits it.
  @discardableResult
  func typeNote(_ text: String) -> Self {
    let note = app.textFields["findingInspector.note"].assertExists()
    note.click()
    note.typeText(text)
    note.typeKey(.return, modifierFlags: [])
    return self
  }

  /// Selects the next unreviewed finding with the Review menu's shortcut.
  @discardableResult
  func nextUnreviewed() -> Self {
    app.typeKey("]", modifierFlags: .command)
    return self
  }

  /// Selects the previous unreviewed finding with the Review menu's shortcut.
  @discardableResult
  func previousUnreviewed() -> Self {
    app.typeKey("[", modifierFlags: .command)
    return self
  }

  /// Approves the selection for correction, or clears its approval, with Space.
  @discardableResult
  func toggleApprovalWithSpace(file: StaticString = #filePath, line: UInt = #line) -> Self {
    awaitKeyboardFocus(file: file, line: line)
    app.typeKey(" ", modifierFlags: [])
    return self
  }

  /// Shows the inspector with Return.
  @discardableResult
  func showInspectorWithReturn(file: StaticString = #filePath, line: UInt = #line) -> Self {
    awaitKeyboardFocus(file: file, line: line)
    app.typeKey(.return, modifierFlags: [])
    return self
  }

  /// Waits for the table to take keyboard focus, which the table's key handlers need.
  private func awaitKeyboardFocus(file: StaticString, line: UInt) {
    if !table.waitFor(NSPredicate(format: "hasKeyboardFocus == true")) {
      XCTFail("The findings table never took keyboard focus", file: file, line: line)
    }
  }

  /// Fails the test unless the finding inspector is on screen or hidden.
  func assertInspector(
    isShown: Bool,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let inspector = app.descendant(id: "findingInspector")
    if isShown {
      inspector.assertExists(file: file, line: line)
    } else {
      inspector.assertHidden(file: file, line: line)
    }
  }

  /// Fails the test unless the inspector proposes changing a field.
  func assertProposesChange(
    to field: String,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    app.descendant(id: "proposedChange.\(field)").assertExists(file: file, line: line)
  }
}

/// Audit & Fix ▸ Approved.
@MainActor
struct ApprovedScreen {
  let app: XCUIApplication

  /// Opens the Apply sheet and waits for its plan.
  func applyApprovedFixes() -> ApplySheetScreen {
    app.buttons["approved.apply"].assertExists().click()
    app.buttons["apply.backUp"].assertExists()
    return ApplySheetScreen(app: app)
  }

  /// Opens the Apply sheet with the toolbar button and waits for its plan.
  func applyApprovedFixesFromToolbar() -> ApplySheetScreen {
    app.buttons["toolbar.applyApproved"].assertExists().click()
    app.buttons["apply.backUp"].assertExists()
    return ApplySheetScreen(app: app)
  }

  /// Fails the test unless the page is the empty state with no way to apply.
  func assertNothingApproved(file: StaticString = #filePath, line: UInt = #line) {
    app.staticTexts["No Approved Fixes"].assertExists(file: file, line: line)
    app.buttons["approved.apply"].assertHidden(file: file, line: line)
  }

  /// Fails the test unless the toolbar's Apply Fixes button is enabled or disabled.
  func assertToolbarApply(
    isEnabled: Bool,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let button = app.buttons["toolbar.applyApproved"].assertExists(file: file, line: line)
    XCTAssertEqual(button.isEnabled, isEnabled, file: file, line: line)
  }

  /// Fails the test unless every approved row carries the badge for a fix recorded before.
  func assertRowsMarkedRecorded(file: StaticString = #filePath, line: UInt = #line) {
    let table = app.outlines["findingsTable.approved"].assertExists(file: file, line: line)
    for index in 0..<table.outlineRows.count {
      let row = table.outlineRows.element(boundBy: index)
      row.images["findingsTable.recorded"].assertExists(file: file, line: line)
    }
  }

  /// Selects the approved row at a position and withdraws its approval from the inspector's
  /// More Decisions menu.
  func withdrawApproval(ofRow index: Int) {
    ReviewQueueScreen(app: app, table: app.outlines["findingsTable.approved"])
      .selectRow(index)
      .decideFromMoreMenu("unreviewed")
  }

  /// Fails the test unless the page notes that approved fixes were recorded but not sent.
  func assertNotesRecordedFixes(file: StaticString = #filePath, line: UInt = #line) {
    app.descendant(id: "approved.recordedNote").assertExists(file: file, line: line)
  }
}

/// The Apply sheet.
@MainActor
struct ApplySheetScreen {
  let app: XCUIApplication

  /// The title of the button that applies or records the batches.
  var applyTitle: String {
    app.buttons["apply.apply"].assertExists().label
  }

  /// Backs up the logbook, confirms a LogTen backup, and applies the batches.
  @discardableResult
  func backUpAndApply() -> Self {
    app.buttons["apply.backUp"].click()
    app.descendant(id: "apply.backupDone").assertExists()
    app.descendant(id: "apply.confirmsLogTenBackup").assertExists().click()
    app.buttons["apply.apply"].assertExists().click()
    return self
  }

  /// Backs up the logbook and waits for the backup to be listed.
  @discardableResult
  func backUp() -> Self {
    app.buttons["apply.backUp"].assertExists().click()
    app.descendant(id: "apply.backupDone").assertExists()
    return self
  }

  /// Switches on the acknowledgement of a backup made in LogTen.
  @discardableResult
  func confirmLogTenBackup() -> Self {
    app.descendant(id: "apply.confirmsLogTenBackup").assertExists().click()
    return self
  }

  /// Closes the sheet with Cancel.
  func cancel() {
    app.buttons["apply.close"].assertExists().click()
    app.buttons["apply.apply"].assertHidden()
  }

  /// Fails the test unless the apply button is enabled or disabled.
  func assertApply(isEnabled: Bool, file: StaticString = #filePath, line: UInt = #line) {
    let button = app.buttons["apply.apply"].assertExists(file: file, line: line)
    XCTAssertEqual(button.isEnabled, isEnabled, file: file, line: line)
  }

  /// Fails the test unless the plan notes fixes recorded before and shows when each operation
  /// was recorded.
  func assertShowsRecordedBefore(file: StaticString = #filePath, line: UInt = #line) {
    app.descendant(id: "apply.recordedNote").assertExists(file: file, line: line)
    app.descendant(id: "apply.operation.recorded").assertExists(file: file, line: line)
  }

  /// Closes the sheet on Applied History once applying has finished.
  func showAppliedHistory() -> AppliedHistoryScreen {
    app.buttons["apply.showHistory"].assertExists().click()
    return AppliedHistoryScreen(app: app)
  }
}

/// Audit & Fix ▸ Applied History and its inspector.
@MainActor
struct AppliedHistoryScreen {
  let app: XCUIApplication

  /// The page bar's summary, such as "Nothing applied".
  var summary: String {
    app.descendant(id: "pageBar.summary").assertExists().text
  }

  /// Fails the test unless the page is the empty state.
  func assertNothingApplied(file: StaticString = #filePath, line: UInt = #line) {
    app.staticTexts["Nothing Applied"].assertExists(file: file, line: line)
  }

  /// Fails the test unless a recorded batch's package contains some text. Selects each batch in
  /// turn and expands its package in the inspector.
  func assertRecordedPackages(
    contain text: String,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let table = app.outlines["appliedHistory"].assertExists(file: file, line: line)
    let rows = table.outlineRows
    var packages = [String]()
    for index in 0..<rows.count {
      packages.append(package(ofRow: rows.element(boundBy: index)))
    }
    if !packages.contains(where: { $0.contains(text) }) {
      XCTFail("No recorded package \(packages) contains \(text)", file: file, line: line)
    }
  }

  /// The package the inspector shows once a row is selected. The disclosure is collapsed and
  /// expanded again, so the text is read from an element created for this row's batch rather than
  /// one carried over from the previous selection.
  private func package(ofRow row: XCUIElement) -> String {
    row.staticTexts.firstMatch.assertExists().click()
    let toggle = app.descendant(id: "appliedHistory.packageToggle").assertExists()
    let package = app.descendant(id: "appliedHistory.package")
    if package.exists {
      toggle.click()
      package.waitForNonExistence(timeout: ScaledTimeouts.short)
    }
    toggle.click()
    return package.assertExists().value as? String ?? package.label
  }
}
