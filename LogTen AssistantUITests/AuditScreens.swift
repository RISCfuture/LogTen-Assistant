import XCTest
import XCUITestKit

/// Audit & Fix ▸ Data Sources.
@MainActor
struct DataSourcesScreen {
  let app: XCUIApplication

  /// Syncs FlySto from the toolbar and waits for the sync and the audit after it to finish.
  @discardableResult
  func syncFlySto(file: StaticString = #filePath, line: UInt = #line) -> Self {
    app.buttons["toolbar.syncFlySto"].assertExists(file: file, line: line).click()
    app.descendant(id: "dataSources.status").assertExists(file: file, line: line)
    app.descendant(id: "toolbar.activity").assertHidden(file: file, line: line)
    return self
  }
}

/// A review queue's table of findings and the finding inspector.
@MainActor
struct ReviewQueueScreen {
  let app: XCUIApplication
  let table: XCUIElement

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

  /// Fails the test unless the page notes that approved fixes were recorded but not sent.
  func assertNotesRecordedFixes(file: StaticString = #filePath, line: UInt = #line) {
    app.descendant(id: "approved.recordedNote").assertExists(file: file, line: line)
  }
}

/// The Apply sheet.
@MainActor
struct ApplySheetScreen {
  let app: XCUIApplication

  /// Backs up the logbook, confirms a LogTen backup, and applies the batches.
  @discardableResult
  func backUpAndApply() -> Self {
    app.buttons["apply.backUp"].click()
    app.descendant(id: "apply.backupDone").assertExists()
    app.descendant(id: "apply.confirmsLogTenBackup").assertExists().click()
    app.buttons["apply.apply"].assertExists().click()
    return self
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
