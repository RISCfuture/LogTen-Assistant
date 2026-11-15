public import Foundation
public import LogbookModel

/// What the user decided about a finding.
public enum ReviewDecision: String, CaseIterable, Codable, CodingKeyRepresentable, Sendable {
  /// Not reviewed yet.
  case unreviewed
  /// The finding is right and its chosen correction should be applied.
  case correction
  /// The entry is to be kept as logged: the finding is wrong, or the record is intentional.
  case falsePositive = "false_positive"
  /// The finding can't be decided without more evidence.
  case needsEvidence = "needs_evidence"
}

/// Why a reviewer reached a decision, chosen from the reasons the review UI offers.
public enum ReviewReason: String, CaseIterable, Codable, Sendable {
  /// The evidence supports the finding.
  case evidenceConfirms = "evidence_confirms"
  /// The logged value is right; the evidence is wrong or incomplete.
  case logbookCorrect = "logbook_correct"
  /// The entry records another pilot's flight or partial credit, so the comparison doesn't
  /// apply.
  case attribution
  /// The source data is missing, ambiguous or unreliable for this flight.
  case evidenceUnreliable = "evidence_unreliable"
  /// None of the above; the note explains.
  case other
}

/// A decision about one finding, with the user's reason and note.
public struct ReviewRecord: Identifiable, Hashable, Codable, Sendable {
  /// The finding decided.
  public var findingID: FindingID

  /// The decision.
  public var decision: ReviewDecision

  /// The correction option chosen, for a ``ReviewDecision/correction`` decision.
  public var correctionOptionID: CorrectionOptionID?

  /// Why the user decided as they did, if they chose a reason.
  public var reason: ReviewReason?

  /// The user's own words about the decision.
  public var note: String

  /// When the decision was made.
  public var decidedAt: Date

  /// The record's identifier, which is its finding's.
  public var id: FindingID { findingID }

  /// Creates a review record.
  public init(
    findingID: FindingID,
    decision: ReviewDecision,
    correctionOptionID: CorrectionOptionID? = nil,
    reason: ReviewReason? = nil,
    note: String = "",
    decidedAt: Date
  ) {
    self.findingID = findingID
    self.decision = decision
    self.correctionOptionID = correctionOptionID
    self.reason = reason
    self.note = note
    self.decidedAt = decidedAt
  }
}
