import XCTest

final class ViolationsTests: XCTestCase {
  private static let flightsWithViolations = 4
  private static let uncheckedRules = 2

  @MainActor
  func testShowsTheSampleLogbooksViolations() {
    let window = LogbookWindowScreen.launchWithSampleLogbook()
    window.showViolations()
    window.assertShowsViolations(onFlights: Self.flightsWithViolations)

    window.selectFlight(withRegistration: "N529SF")
    window.assertInspectorCites("14 CFR 61.58(a)(1)")

    window.showRule("no_proficiency_check")
    window.assertShowsViolations(onFlights: 1)
    XCTAssertTrue(window.summary.contains("14 CFR 61.58"), window.summary)
  }

  @MainActor
  func testMappingTheMissingFieldChecksTheRuleThatDidntRun() {
    let window = LogbookWindowScreen.launchWithSampleLogbook()
    window.showViolations()
    window.assertUncheckedRules(count: Self.uncheckedRules)

    let settings = window.openSettingsForUncheckedRuleInPageBar("no_nVGCurrency")
    XCTAssertEqual(settings.page, "Custom Fields")
    settings.assertShowsFieldPicker(for: "night_vision_goggle_proficiency_check")
    settings.mapField(role: "night_vision_goggle_proficiency_check", to: "Checkride").done()

    window.assertUncheckedRules(count: 0)
  }

  @MainActor
  func testSearchNarrowsViolationsToMatchingFlights() {
    let window = LogbookWindowScreen.launchWithSampleLogbook()
    window.showViolations()

    window.search("N529SF")
    window.assertShowsViolations(onFlights: 1)
    XCTAssertTrue(window.summary.hasSuffix("on 1 flight"), window.summary)

    window.search("ZZZZ")
    window.assertShowsNoMatches()
    XCTAssertEqual(window.summary, "No matches")
  }
}
