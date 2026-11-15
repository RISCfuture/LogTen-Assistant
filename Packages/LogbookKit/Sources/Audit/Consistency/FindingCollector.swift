import LogbookModel

/// Accumulates findings and their analyses as the rules run.
struct FindingCollector {
  private(set) var findings = [Finding]()
  private(set) var analyses = [FindingID: FindingAnalysis]()

  /// Adds a finding of any rule.
  @discardableResult
  mutating func emit(
    _ rule: RuleID,
    _ recordIDs: [RecordID],
    message: String,
    evidence: JSONValue,
    severity: Severity = .suggestion,
    explanation: String? = nil,
    recommendation: String? = nil,
    corrections: [CorrectionOption] = [],
    citation: String? = nil
  ) -> Finding {
    let finding = Finding(
      rule: rule,
      recordIDs: recordIDs,
      message: message,
      evidence: evidence,
      severity: severity,
      explanation: explanation,
      recommendation: recommendation,
      corrections: corrections,
      citation: citation
    )
    findings.append(finding)
    return finding
  }

  /// Adds a finding of a consistency rule.
  @discardableResult
  mutating func emit(
    _ rule: ConsistencyRule,
    _ recordIDs: [RecordID],
    message: String,
    evidence: JSONValue,
    severity: Severity = .suggestion,
    explanation: String? = nil,
    recommendation: String? = nil,
    corrections: [CorrectionOption] = []
  ) -> Finding {
    emit(
      rule.id,
      recordIDs,
      message: message,
      evidence: evidence,
      severity: severity,
      explanation: explanation,
      recommendation: recommendation,
      corrections: corrections
    )
  }

  mutating func attach(_ analysis: FindingAnalysis, to id: FindingID) {
    analyses[id] = analysis
  }

  func findings(of rule: ConsistencyRule, involving recordID: RecordID) -> [Finding] {
    findings.filter { $0.rule == rule.id && $0.recordIDs == [recordID] }
  }

  func analysis(of id: FindingID) -> FindingAnalysis? { analyses[id] }

  /// The findings of enabled rules, ordered by rule and identifier, with their analyses.
  func result(enabling isEnabled: (RuleID) -> Bool) -> ConsistencyAuditResult {
    let kept = findings.filter { isEnabled($0.rule) }
      .sorted { ($0.rule, $0.id) < ($1.rule, $1.id) }
    let ids = Set(kept.map(\.id))
    return ConsistencyAuditResult(
      findings: kept,
      analyses: analyses.filter { ids.contains($0.key) }
    )
  }
}
