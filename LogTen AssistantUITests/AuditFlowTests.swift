import XCTest

final class AuditFlowTests: XCTestCase {
  /// The entity the package should carry: the Monterey flight's block-in moved to FlySto's
  /// 20:40Z, as Unix-epoch seconds.
  private static let expectedFlyStoEntity =
    #"{"entity_name":"Flight","flight_key":"KEY-002","flight_actualArrivalTime":1772397600.0}"#

  /// The entity the package should carry for the PA-28 flight logged as both PIC and SIC, with
  /// its second correction, “Clear PIC”, chosen over the first, “Clear SIC”.
  private static let expectedSeatTimeEntity =
    #"{"entity_name":"Flight","flight_key":"KEY-006","flight_pic":"0:00"}"#

  @MainActor
  func testRecordsTheApprovedCorrections() {
    let window = LogbookWindowScreen.launchWithSampleLogbook(stubsFlySto: true)
    let emptyQueue = window.showQueue("aircraft_comparisons")
    emptyQueue.assertShowsNoTable()
    let dataSources = emptyQueue.showDataSourcesFromEmptyState().syncFlyStoFromPage()
    XCTAssertEqual(dataSources.status, "Synced 1 FlySto log.")

    let comparisons = window.showQueue("aircraft_comparisons").selectFinding(onAircraft: "N4321K")
    comparisons.assertProposesChange(to: "flight_actualArrivalTime")
    comparisons.markForCorrection()

    let times = window.showChecks("times").selectFinding(onAircraft: "N2468P")
    times.assertProposesChange(to: "flight_sic")
    times.chooseCorrection(1)
    times.assertProposesChange(to: "flight_pic")
    times.markForCorrection()

    let history = window.showApproved().applyApprovedFixes().backUpAndApply().showAppliedHistory()
    history.assertRecordedPackages(contain: Self.expectedFlyStoEntity)
    history.assertRecordedPackages(contain: Self.expectedSeatTimeEntity)

    let approved = window.showApproved()
    approved.assertNotesRecordedFixes()
    approved.assertRowsMarkedRecorded()
    let sheet = approved.applyApprovedFixes()
    sheet.assertShowsRecordedBefore()
    sheet.cancel()
    XCTAssertEqual(window.showAppliedHistory().summary, "2 batches recorded, not sent to LogTen")
  }
}
