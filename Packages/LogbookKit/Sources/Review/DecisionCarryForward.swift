public import LogbookModel

/**
 Carries review decisions from one audit run to the next, keeping a decision only while the
 data it was made about is unchanged.

 A decision carries forward when every record its finding involves has the same fingerprint in
 both runs and the new run produced a finding with the same identifier, which is derived from
 the rule, records and evidence. The identifier stands for the evidence because evidence decoded
 from a saved run can differ in representation from the same evidence computed afresh (a
 whole-number `Double` is saved as `66` and reads back as an integer). A reviewed finding the
 new run no longer produces, whose records are unchanged and which no other finding of the same rule and records replaces, is kept as a
 retired finding so the decision stays reachable without reappearing as a new alert. Any other
 decision is dropped, and the finding must be reviewed again.

 An approved correction carries forward only while the new finding still offers the option that
 was chosen; otherwise the finding must be reviewed again, so a different option is never
 applied in its place.
 */
public enum DecisionCarryForward {
  /**
   Carries decisions from a previous run to the current one.

   - Parameters:
     - decisions: The decisions made against `previous`.
     - previous: The run the decisions were made against.
     - current: The new run.
   - Returns: The decisions that still apply, retired findings, and what happened to each
     decision.
   */
  public static func carry(
    _ decisions: [ReviewRecord],
    from previous: ReviewedAudit,
    to current: ReviewedAudit
  ) -> CarryForwardResult {
    let old = Dictionary(previous.findings.map { ($0.id, $0) }) { first, _ in first }
    let new = Dictionary(current.findings.map { ($0.id, $0) }) { first, _ in first }
    var result = CarryForwardResult(sourceAuditID: previous.identity)

    for decision in decisions {
      result.counts[decision.decision, default: 0] += 1
      guard let finding = old[decision.findingID] else {
        result.history.append(
          .init(decision: decision, rule: nil, recordIDs: [], outcome: .findingUnknown)
        )
        continue
      }
      var outcome = outcome(of: finding, previous: previous, current: current, new: new)
      if outcome == .carried, !decision.isOffered(by: new[finding.id]?.corrections ?? []) {
        outcome = .correctionNoLongerOffered
      }
      switch outcome {
        case .carried: result.decisions[finding.id] = decision
        case .retired: result.retired.append(RetiredFinding(finding: finding, decision: decision))
        case .recordsOrEvidenceChanged, .correctionNoLongerOffered, .findingUnknown: break
      }
      result.history.append(
        .init(
          decision: decision,
          rule: finding.rule,
          recordIDs: finding.recordIDs,
          outcome: outcome
        )
      )
    }
    return result
  }

  private static func outcome(
    of finding: Finding,
    previous: ReviewedAudit,
    current: ReviewedAudit,
    new: [FindingID: Finding]
  ) -> CarryForwardEntry.Outcome {
    let unchanged = finding.recordIDs.allSatisfy { id in
      guard let before = previous.recordFingerprints[id], let after = current.recordFingerprints[id]
      else { return false }
      return before == after
    }
    guard unchanged else { return .recordsOrEvidenceChanged }
    guard new[finding.id] == nil else { return .carried }
    let superseded = new.values.contains {
      $0.rule == finding.rule && $0.recordIDs == finding.recordIDs
    }
    return superseded ? .recordsOrEvidenceChanged : .retired
  }
}

extension ReviewRecord {
  /// Whether the record's chosen correction option, if it has one, is among those offered.
  fileprivate func isOffered(by offered: [CorrectionOption]) -> Bool {
    guard let correctionOptionID else { return true }
    return offered.contains { $0.id == correctionOptionID }
  }
}

/// The decisions carried from one audit run to the next.
public struct CarryForwardResult: Hashable, Codable, Sendable {
  /// The run the decisions were made against.
  public var sourceAuditID: AuditIdentity

  /// The decisions that still apply, by finding in the current run.
  public var decisions: [FindingID: ReviewRecord]

  /// Reviewed findings the current run no longer produces, kept with their decisions.
  public var retired: [RetiredFinding]

  /// What happened to each decision, in the order given.
  public var history: [CarryForwardEntry]

  /// How many of the decisions had each status.
  public var counts: [ReviewDecision: Int]

  /// Creates an empty result.
  public init(sourceAuditID: AuditIdentity) {
    self.sourceAuditID = sourceAuditID
    decisions = [:]
    retired = []
    history = []
    counts = [:]
  }
}

/// A reviewed finding that a later run no longer produces although its records are unchanged.
public struct RetiredFinding: Hashable, Codable, Sendable {
  /// The finding as it was reviewed.
  public var finding: Finding

  /// The decision made about it.
  public var decision: ReviewRecord

  /// Creates a retired finding.
  public init(finding: Finding, decision: ReviewRecord) {
    self.finding = finding
    self.decision = decision
  }
}

/// What happened to one decision when it was carried forward.
public struct CarryForwardEntry: Hashable, Codable, Sendable {
  /// The decision.
  public var decision: ReviewRecord

  /// The rule of the finding decided, if the previous run had it.
  public var rule: RuleID?

  /// The records the finding involved.
  public var recordIDs: [RecordID]

  /// Whether the decision still applies.
  public var outcome: Outcome

  /// Whether the decision still applies, either to a current finding or to a retired one.
  public var isCarried: Bool { outcome == .carried || outcome == .retired }

  /// Creates an entry.
  public init(decision: ReviewRecord, rule: RuleID?, recordIDs: [RecordID], outcome: Outcome) {
    self.decision = decision
    self.rule = rule
    self.recordIDs = recordIDs
    self.outcome = outcome
  }

  /// What happened to a decision.
  public enum Outcome: String, Codable, Sendable {
    /// The current run produced the same finding over unchanged records.
    case carried
    /// The current run no longer produces the finding, and its records are unchanged.
    case retired
    /// A record or the finding's evidence changed, so the finding must be reviewed again.
    case recordsOrEvidenceChanged = "records_or_evidence_changed"
    /// The finding is unchanged but no longer offers the correction option that was approved.
    case correctionNoLongerOffered = "correction_no_longer_offered"
    /// The previous run had no such finding.
    case findingUnknown = "finding_unknown"
  }
}
