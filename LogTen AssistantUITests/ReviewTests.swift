import XCTest

/// Decisions on the sample logbook's two Logbook Consistency findings: row 0, Crew Seat, which
/// proposes no correction, and row 1, Seat Time, which offers several.
final class ReviewTests: XCTestCase {
  private static let crewSeat = 0
  private static let seatTime = 1

  @MainActor
  private func launchOnLogbookConsistency(
    slowAudit: Bool = false
  ) -> (LogbookWindowScreen, ReviewQueueScreen) {
    let window = LogbookWindowScreen.launchWithSampleLogbook(slowAudit: slowAudit)
    return (window, window.showQueue("logbook_consistency"))
  }

  @MainActor
  func testKeepAsLoggedAdvancesAndUndoRestores() {
    let (window, queue) = launchOnLogbookConsistency()
    XCTAssertEqual(window.summary, "2 of 2 to review")

    queue.selectRow(Self.crewSeat).decide("false_positive")
    queue.assertDecisionBadge(ofRow: Self.crewSeat, is: "Kept as Logged")
    XCTAssertEqual(queue.selectedRowIndex, Self.seatTime)
    XCTAssertEqual(queue.decisionText, "Not reviewed")
    XCTAssertEqual(window.summary, "1 of 2 to review")

    window.undo("Keep as Logged")
    XCTAssertEqual(queue.selectedRowIndex, Self.crewSeat)
    XCTAssertEqual(queue.decisionText, "Not reviewed")
    XCTAssertEqual(window.summary, "2 of 2 to review")
  }

  @MainActor
  func testNeedsMoreEvidenceThenResetDecision() {
    let (window, queue) = launchOnLogbookConsistency()

    queue.selectRow(Self.crewSeat).decideFromMoreMenu("needs_evidence")
    queue.selectRow(Self.crewSeat)
    XCTAssertEqual(queue.decisionText, "Needs more evidence")
    XCTAssertEqual(window.summary, "1 of 2 to review")

    queue.decideFromMoreMenu("unreviewed")
    XCTAssertEqual(queue.selectedRowIndex, Self.crewSeat)
    XCTAssertEqual(queue.decisionText, "Not reviewed")
    XCTAssertEqual(window.summary, "2 of 2 to review")
  }

  @MainActor
  func testReasonAndNoteDraftIsRecordedWithTheDecision() {
    let (_, queue) = launchOnLogbookConsistency()

    queue.selectRow(Self.crewSeat).chooseReason("The evidence confirms it")
    queue.typeNote("Checked the roster")
    queue.selectRow(Self.seatTime).selectRow(Self.crewSeat)
    XCTAssertEqual(queue.reason, "The evidence confirms it")
    XCTAssertEqual(queue.note, "Checked the roster")

    queue.decide("false_positive").selectRow(Self.crewSeat)
    XCTAssertEqual(queue.decisionText, "Kept as logged")
    XCTAssertEqual(queue.reason, "The evidence confirms it")
    XCTAssertEqual(queue.note, "Checked the roster")
  }

  @MainActor
  func testDecidingSeveralFindingsApprovesOnlyThoseWithOneChosenCorrection() {
    let (window, queue) = launchOnLogbookConsistency()

    queue.selectRow(Self.crewSeat).toggleRow(Self.seatTime)
    XCTAssertEqual(queue.decisionText, "0 of 2 can be marked for correction")

    queue.toggleRow(Self.crewSeat).chooseCorrection(0).toggleRow(Self.crewSeat)
    XCTAssertEqual(queue.decisionText, "1 of 2 can be marked for correction")
    queue.markForCorrection()
    XCTAssertEqual(queue.decisionText, "1 of 2 marked for correction")

    _ = window.showApproved()
    XCTAssertEqual(window.summary, "1 fix approved")
  }

  @MainActor
  func testNextAndPreviousUnreviewedStayPutWhenNoOtherFindingIsUnreviewed() {
    let (_, queue) = launchOnLogbookConsistency()

    queue.selectRow(Self.crewSeat).nextUnreviewed()
    XCTAssertEqual(queue.selectedRowIndex, Self.seatTime)
    queue.previousUnreviewed()
    XCTAssertEqual(queue.selectedRowIndex, Self.crewSeat)

    queue.selectRow(Self.seatTime).decide("false_positive")
    queue.selectRow(Self.crewSeat).nextUnreviewed()
    XCTAssertEqual(queue.selectedRowIndex, Self.crewSeat)
  }

  @MainActor
  func testSearchNarrowsTheTable() {
    let (window, queue) = launchOnLogbookConsistency()

    window.search("Crew Seat")
    XCTAssertEqual(queue.rowCount, 1)
    XCTAssertEqual(window.summary, "1 of 1 to review")

    window.search("ZZZZ")
    queue.assertShowsNoTable()
    XCTAssertEqual(window.summary, "No matches")

    window.clearSearch()
    XCTAssertEqual(queue.rowCount, 2)
    XCTAssertEqual(window.summary, "2 of 2 to review")
  }

  @MainActor
  func testEmptyScopeOffersAllFlights() {
    let (window, queue) = launchOnLogbookConsistency()

    window.chooseScope("Last 90 Days")
    queue.assertShowsNoTable()
    queue.showAllFlights()
    queue.assertShowsTable()
    window.assertScopeSelected("All Flights")
  }

  @MainActor
  func testRunAuditKeepsEarlierDecisions() {
    let (window, queue) = launchOnLogbookConsistency(slowAudit: true)
    queue.selectRow(Self.crewSeat).decide("false_positive")

    window.runAudit()
    queue.assertShowsTable()
    queue.selectRow(Self.crewSeat)
    queue.assertDecisionBadge(ofRow: Self.crewSeat, is: "Kept as Logged")
    XCTAssertEqual(queue.decisionText, "Kept as logged")
    XCTAssertEqual(window.summary, "1 of 2 to review")
  }

  @MainActor
  func testSpaceTogglesApprovalAndReturnShowsTheInspector() throws {
    let system = ProcessInfo.processInfo.operatingSystemVersion
    try XCTSkipIf(
      system.majorVersion == 27 && system.minorVersion == 0,
      "Clicking a row doesn’t give the findings table keyboard focus on macOS 27.0."
    )
    let (window, queue) = launchOnLogbookConsistency()

    queue.selectRow(Self.seatTime).toggleApprovalWithSpace()
    _ = window.showApproved()
    XCTAssertEqual(window.summary, "1 fix approved")
    window.showQueue("logbook_consistency")
      .assertDecisionBadge(ofRow: Self.seatTime, is: "Correction")

    queue.selectRow(Self.seatTime).toggleApprovalWithSpace()
    _ = window.showApproved()
    window.showQueue("logbook_consistency")
      .assertDecisionBadge(ofRow: Self.seatTime, is: "Unreviewed")

    window.toggleInspector()
    queue.assertInspector(isShown: false)
    queue.selectRow(Self.seatTime).showInspectorWithReturn().assertInspector(isShown: true)
  }
}
