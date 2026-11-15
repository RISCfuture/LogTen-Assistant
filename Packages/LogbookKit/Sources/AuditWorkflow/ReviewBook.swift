public import Corrections
public import Foundation
public import LogbookModel
public import Review

/**
 The user's decisions about one run's findings.

 A finding without a record is unreviewed; deciding a finding “unreviewed” removes its record.
 Decisions are made against a `ReviewedAudit` and carried to the next run with
 ``carriedForward(from:to:)``, which keeps a decision only while its records and evidence are
 unchanged.
 */
public struct ReviewBook: Hashable, Sendable {
  /// The decisions, by finding.
  public private(set) var records: [FindingID: ReviewRecord]

  /// The decisions as a list, ordered by finding, for saving and exporting.
  public var orderedRecords: [ReviewRecord] {
    records.values.sorted { $0.findingID < $1.findingID }
  }

  /// Creates a book of decisions.
  public init(records: [FindingID: ReviewRecord] = [:]) {
    self.records = records
  }

  /**
   The decisions that still apply to a new run.

   - Parameters:
     - state: The decisions saved for the previous run, if any.
     - audit: The new run.
   - Returns: The decisions that carry over, and what happened to each saved one; the result
     is `nil` when nothing was saved.
   */
  public static func carriedForward(from state: ReviewState?, to audit: ReviewedAudit) -> (
    book: Self, result: CarryForwardResult?
  ) {
    guard let state else { return (Self(), nil) }
    let result = DecisionCarryForward.carry(state.decisions, from: state.audit, to: audit)
    return (Self(records: result.decisions), result)
  }

  private static func chosenOption(_ id: CorrectionOptionID?, of finding: Finding)
    -> CorrectionOption?
  {
    finding.correction(id) ?? (finding.corrections.count == 1 ? finding.corrections.first : nil)
  }

  /// What the user decided about a finding.
  public func decision(for id: FindingID) -> ReviewDecision {
    records[id]?.decision ?? .unreviewed
  }

  /**
   Sets or clears the record for a finding.

   - Parameters:
     - record: The new record; `nil`, or a record whose decision is unreviewed, clears it.
     - id: The finding.
   - Returns: The record it replaced, so the change can be undone.
   */
  @discardableResult
  public mutating func set(_ record: ReviewRecord?, for id: FindingID) -> ReviewRecord? {
    let previous = records[id]
    if let record, record.decision != .unreviewed {
      records[id] = record
    } else {
      records[id] = nil
    }
    return previous
  }

  /**
   Records the same decision for several findings.

   A correction decision records the chosen option: `option` for a finding that offers it,
   otherwise a finding's only option, otherwise none, leaving the choice to be made.

   - Parameters:
     - decision: The decision.
     - findings: The findings decided.
     - option: The correction option chosen, for a correction decision.
     - reason: Why the reviewer decided as they did.
     - note: The reviewer's note.
     - date: When the decision was made.
   - Returns: Each finding's previous record, for undoing the change.
   */
  @discardableResult
  public mutating func decide(
    _ decision: ReviewDecision,
    for findings: some Sequence<Finding>,
    choosing option: CorrectionOptionID? = nil,
    reason: ReviewReason? = nil,
    note: String = "",
    at date: Date = .now
  ) -> [FindingID: ReviewRecord?] {
    var previous = [FindingID: ReviewRecord?]()
    for finding in findings {
      let record = ReviewRecord(
        findingID: finding.id,
        decision: decision,
        correctionOptionID: decision == .correction
          ? Self.chosenOption(option, of: finding)?.id : nil,
        reason: reason,
        note: note,
        decidedAt: date
      )
      previous[finding.id] = set(record, for: finding.id)
    }
    return previous
  }

  /// The findings approved for correction whose chosen option is still offered, or that offer
  /// only one, each with that option, in the order given.
  public func approved(in findings: [Finding]) -> [ApprovedCorrection] {
    findings.compactMap { finding in
      guard let record = records[finding.id], record.decision == .correction,
        let option = Self.chosenOption(record.correctionOptionID, of: finding)
      else { return nil }
      return ApprovedCorrection(finding: finding, option: option)
    }
  }

  /**
   The next unreviewed finding in a list, wrapping around.

   - Parameters:
     - current: Where to start; the search begins after it, or at the start of the list.
     - ordered: The findings in display order.
     - forward: Whether to search forward or backward.
   - Returns: The next unreviewed finding, or `nil` if every other finding is reviewed.
   */
  public func nextUnreviewed(
    after current: FindingID?,
    in ordered: [FindingID],
    forward: Bool = true
  ) -> FindingID? {
    let list = forward ? ordered : ordered.reversed()
    let start = current.flatMap { list.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
    let rotated = list[start...] + list[..<start]
    return rotated.first { $0 != current && decision(for: $0) == .unreviewed }
  }
}
