import XCTest

/// Data Sources, the Approved page and the Apply sheet on the sample logbook.
final class ApplyFlowTests: XCTestCase {
  private static let seatTime = 1

  /// Approves the sample's Seat Time finding with its first correction.
  @MainActor
  private func approveSeatTime(in window: LogbookWindowScreen) {
    let queue = window.showQueue("logbook_consistency").selectRow(Self.seatTime)
    queue.chooseCorrection(0)
    queue.markForCorrection()
  }

  @MainActor
  func testApplyIsGatedOnBothBackupsAndCancelAppliesNothing() {
    let window = LogbookWindowScreen.launchWithSampleLogbook()
    let approved = window.showApproved()
    approved.assertNothingApproved()
    approved.assertToolbarApply(isEnabled: false)

    approveSeatTime(in: window)
    let sheet = window.showApproved().applyApprovedFixesFromToolbar()
    sheet.assertApply(isEnabled: false)
    sheet.backUp()
    sheet.assertApply(isEnabled: false)
    sheet.confirmLogTenBackup()
    sheet.assertApply(isEnabled: true)
    XCTAssertEqual(sheet.applyTitle, "Record 1 Package")
    sheet.cancel()

    let history = window.showAppliedHistory()
    history.assertNothingApplied()
    XCTAssertEqual(history.summary, "Nothing applied")
    _ = window.showApproved().assertToolbarApply(isEnabled: true)
  }

  @MainActor
  func testWithdrawingAnApprovalReturnsTheFindingToUnreviewed() {
    let window = LogbookWindowScreen.launchWithSampleLogbook()
    approveSeatTime(in: window)

    let approved = window.showApproved()
    approved.withdrawApproval(ofRow: 0)
    approved.assertNothingApproved()
    XCTAssertEqual(window.summary, "No fixes approved")
    approved.assertToolbarApply(isEnabled: false)

    let queue = window.showQueue("logbook_consistency")
    queue.assertDecisionBadge(ofRow: Self.seatTime, is: "Unreviewed")
  }

  @MainActor
  func testBackUpLogbookFromTheApplyMenu() {
    let window = LogbookWindowScreen.launchWithSampleLogbook()
    window.backUpFromMenu()
    window.assertMenuItem("Show Backups in Finder", in: "Apply", enabled: true)
  }
}
