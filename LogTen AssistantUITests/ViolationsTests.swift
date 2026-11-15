import XCTest

final class ViolationsTests: XCTestCase {
  private static let flightsWithViolations = 4

  @MainActor
  func testShowsTheSampleLogbooksViolations() {
    let window = LogbookWindowScreen.launchWithSampleLogbook()
    window.showViolations()
    window.assertShowsViolations(onFlights: Self.flightsWithViolations)

    window.selectFlight(withRegistration: "N529SF")
    window.assertInspectorCites("14 CFR 61.58(a)(1)")
  }

  @MainActor
  func testOffersToMapTheFieldsOfARuleThatDidntRun() {
    let window = LogbookWindowScreen.launchWithSampleLogbook()
    window.showRule("no_nVGCurrency")
    let settings = window.openSettingsForUncheckedRule()
    settings.assertShowsFieldPicker(for: "night_vision_goggle_proficiency_check")
  }
}
