import XCTest

/// Edits to the sample logbook's settings and the audit they trigger.
final class LogbookSettingsTests: XCTestCase {
  private static let proficiencyCheck = "no_proficiency_check"
  private static let flightsWithViolations = 4
  private static let allViolationsSummary = "8 violations on 4 flights"
  private static let withoutProficiencySummary = "7 violations on 4 flights"

  @MainActor
  func testTurningARuleOffThenBackOnThroughItsRemedy() {
    let window = LogbookWindowScreen.launchWithSampleLogbook()
    window.showViolations()
    window.assertShowsViolations(onFlights: Self.flightsWithViolations)
    window.assertSummary(Self.allViolationsSummary)

    let rules = window.openLogbookSettings().choosePage("Rules")
    rules.setRule(Self.proficiencyCheck, on: false).done()
    window.showRule(Self.proficiencyCheck)
    window.assertRuleNotChecked(offering: "Turn On Rule…")
    window.showViolations()
    window.assertSummary(Self.withoutProficiencySummary)

    window.showRule(Self.proficiencyCheck)
    let settings = window.openSettingsForUncheckedRule()
    XCTAssertEqual(settings.page, "Rules")
    settings.assertRule(Self.proficiencyCheck, isOn: false)
    settings.setRule(Self.proficiencyCheck, on: true).done()

    window.assertShowsViolations(onFlights: 1)
    window.assertRuleChecked()
    window.showViolations()
    window.assertShowsViolations(onFlights: Self.flightsWithViolations)
    window.assertSummary(Self.allViolationsSummary)
  }

  @MainActor
  func testCancelDiscardsEdits() {
    let window = LogbookWindowScreen.launchWithSampleLogbook()
    let rules = window.openLogbookSettings().choosePage("Rules")
    rules.setRule(Self.proficiencyCheck, on: false).cancel()

    let reopened = window.openLogbookSettings().choosePage("Rules")
    reopened.assertRule(Self.proficiencyCheck, isOn: true)
  }

  @MainActor
  func testRemovingTheInstrumentRatingSendsIFRCurrencyToThePilotProfile() {
    let window = LogbookWindowScreen.launchWithSampleLogbook()
    window.showRule("no_iFRCurrency")
    window.assertShowsLimitations()

    let pilot = window.openLogbookSettings()
    pilot.setAirplaneInstrumentRating(on: false).done()
    window.assertRuleNotChecked(offering: "Edit Pilot Profile…")
    XCTAssertEqual(window.openSettingsForUncheckedRule().page, "Pilot")
  }

  @MainActor
  func testSwitchingOffAConsistencyCheckRemovesItsFindings() {
    let window = LogbookWindowScreen.launchWithSampleLogbook()
    let times = window.showChecks("times")
    XCTAssertEqual(times.rowCount, 1)
    window.assertSummary("1 of 1 to review")

    let rules = window.openLogbookSettings().choosePage("Rules")
    let settings = rules.expandChecks("times")
    settings.setRule("seat_time", on: false).done()

    times.assertShowsNoTable()
    window.assertSummary("No findings")
  }
}
