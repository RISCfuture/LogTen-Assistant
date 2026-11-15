public import Foundation
public import LogbookModel

/// The findings of one audit run over one snapshot.
public struct AuditReport: Hashable, Codable, Sendable {
  /// The logbook audited.
  public var identity: LogbookIdentity

  /// When the audit ran.
  public var generatedAt: Date

  /// The findings, ordered by rule and then identifier.
  public var findings: [Finding]

  /// Rules that were skipped, with the reason each was skipped.
  public var skippedRules: [RuleID: String]

  /// Creates a report, ordering its findings.
  public init(
    identity: LogbookIdentity,
    generatedAt: Date,
    findings: [Finding],
    skippedRules: [RuleID: String] = [:]
  ) {
    self.identity = identity
    self.generatedAt = generatedAt
    self.findings = findings.sorted { ($0.rule, $0.id) < ($1.rule, $1.id) }
    self.skippedRules = skippedRules
  }

  /// The findings that involve a record.
  public func findings(involving recordID: RecordID) -> [Finding] {
    findings.filter { $0.recordIDs.contains(recordID) }
  }
}
