import XCTest
import XCUITestKit

/// The Logbook Settings sheet.
@MainActor
struct LogbookSettingsScreen {
  /// How far left of a category's title its chevron is drawn. The disclosure triangle the
  /// accessibility tree reports for a category lies at the row's trailing edge and ignores
  /// clicks, so the chevron is found relative to the title instead.
  private static let chevronGap: CGFloat = 9

  let app: XCUIApplication

  private var sheet: XCUIElement { app.sheets.firstMatch }

  /// The title of the selected page, such as "Rules".
  var page: String? {
    let segments = app.descendant(id: "logbookSettings.page").radioButtons
    return segments.allElementsBoundByIndex.first(where: \.isOn)?.label
  }

  /// Fails the test unless the sheet is showing.
  func assertShown(file: StaticString = #filePath, line: UInt = #line) {
    sheet.assertExists(file: file, line: line)
  }

  /// Fails the test unless the sheet has closed.
  func assertClosed(file: StaticString = #filePath, line: UInt = #line) {
    sheet.assertHidden(file: file, line: line)
  }

  /// Fails the test unless the sheet shows the Custom Fields picker for a role, by the role's
  /// identifier, such as `night_takeoffs`.
  func assertShowsFieldPicker(
    for role: String,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    app.descendant(id: "customFields.role.\(role)").assertExists(file: file, line: line)
  }

  /// Shows a page by its title, such as "Rules".
  @discardableResult
  func choosePage(_ title: String) -> Self {
    app.descendant(id: "logbookSettings.page").radioButtons[title].assertExists().click()
    return self
  }

  /// Chooses a field for a role, by the role's identifier and the field's title.
  @discardableResult
  func mapField(role: String, to field: String) -> Self {
    app.descendant(id: "customFields.role.\(role)").assertExists().click()
    app.menuItems[field].assertExists().click()
    return self
  }

  /// Expands a category of consistency checks, by the category's identifier, such as `times`.
  @discardableResult
  func expandChecks(_ category: String) -> Self {
    let group = reveal(app.descendant(id: "rulesSettings.category.\(category)")).assertExists()
    let title = group.staticTexts.firstMatch.assertExists()
    let chevron = title.coordinate(withNormalizedOffset: .zero)
      .withOffset(CGVector(dx: -Self.chevronGap, dy: title.frame.height / 2))
    chevron.click()
    return self
  }

  /// Switches a rule or check on or off, by its identifier, such as `no_proficiency_check`.
  @discardableResult
  func setRule(_ rule: String, on isOn: Bool) -> Self {
    setCheckbox(id: "rulesSettings.rule.\(rule)", on: isOn)
  }

  /// Switches the airplane instrument rating on or off.
  @discardableResult
  func setAirplaneInstrumentRating(on isOn: Bool) -> Self {
    setCheckbox(id: "pilot.instrument.airplane", on: isOn)
  }

  /// Fails the test unless a rule's switch is in a state.
  func assertRule(
    _ rule: String,
    isOn: Bool,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let toggle = app.descendant(id: "rulesSettings.rule.\(rule)").assertExists(
      file: file,
      line: line
    )
    XCTAssertEqual(toggle.isOn, isOn, file: file, line: line)
  }

  /// Saves the settings and closes the sheet.
  func done() {
    app.buttons["logbookSettings.done"].assertExists().click()
    assertClosed()
  }

  /// Discards the settings and closes the sheet.
  func cancel() {
    app.buttons["logbookSettings.cancel"].assertExists().click()
    assertClosed()
  }

  private func setCheckbox(id: String, on isOn: Bool) -> Self {
    let checkbox = reveal(app.descendant(id: id)).assertExists()
    if checkbox.isOn != isOn { checkbox.click() }
    return self
  }

  /// Scrolls the page until the element exists and lies within it.
  private func reveal(_ element: XCUIElement) -> XCUIElement {
    let page = sheet.scrollViews.firstMatch
    for _ in 0..<10 where !(element.exists && page.frame.contains(element.frame)) {
      page.scroll(byDeltaX: 0, deltaY: -300)
    }
    return element
  }
}
