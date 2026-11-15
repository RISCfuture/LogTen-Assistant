import Foundation
import LogbookModel
import Review
import Testing

/// Audit runs over a two-flight logbook whose records and findings tests change between runs.
private struct Runs {
  static let storeUUID = UUID()
  static let first = RecordID(rawValue: "F1")
  static let second = RecordID(rawValue: "F2")

  var fingerprints: [RecordID: RecordFingerprint] = [
    first: RecordFingerprint(rawValue: "a"), second: RecordFingerprint(rawValue: "b")
  ]

  static func finding(_ id: RecordID, night: Int, rule: RuleID = "time_subset") -> Finding {
    Finding(rule: rule, recordIDs: [id], message: "", evidence: ["night": .integer(night)])
  }

  func audit(_ findings: [Finding]) -> ReviewedAudit {
    ReviewedAudit(
      identity: AuditIdentity(
        storeUUID: Self.storeUUID,
        logbookFingerprint: fingerprints.values.map(\.rawValue).sorted().joined(),
        settingsFingerprint: "",
        asOf: nil,
        findingIDs: findings.map(\.id)
      ),
      findings: findings,
      recordFingerprints: fingerprints
    )
  }
}

private func decide(_ finding: Finding, _ decision: ReviewDecision = .falsePositive)
  -> ReviewRecord
{
  ReviewRecord(findingID: finding.id, decision: decision, reason: .logbookCorrect, decidedAt: .now)
}

@Suite
struct `Carrying decisions forward` {
  @Test
  func `keeps a decision when its records and evidence are unchanged`() {
    let runs = Runs()
    let finding = Runs.finding(Runs.first, night: 90)
    let decision = decide(finding)

    let result = DecisionCarryForward.carry(
      [decision],
      from: runs.audit([finding]),
      to: runs.audit([finding, Runs.finding(Runs.second, night: 70)])
    )
    #expect(result.decisions == [finding.id: decision])
    #expect(result.history.map(\.outcome) == [.carried])
    #expect(result.counts == [.falsePositive: 1])
  }

  @Test
  func `keeps a decision made against a saved run whose evidence has whole-number doubles`()
    throws
  {
    let runs = Runs()
    let finding = Finding(
      rule: "telemetry_time",
      recordIDs: [Runs.first],
      message: "",
      evidence: ["observed": .double(66)]
    )
    let saved = try JSONDecoder().decode(
      ReviewedAudit.self,
      from: JSONEncoder().encode(runs.audit([finding]))
    )

    let result = DecisionCarryForward.carry(
      [decide(finding)],
      from: saved,
      to: runs.audit([finding])
    )
    #expect(result.history.map(\.outcome) == [.carried])
  }

  @Test
  func `carries an approved correction only while the finding still offers its option`() {
    let runs = Runs()
    let change = FieldChange(
      flightKey: "key",
      recordID: Runs.first,
      field: .flightNight,
      old: .integer(90),
      new: .integer(60)
    )
    var finding = Runs.finding(Runs.first, night: 90)
    finding.corrections = [CorrectionOption(title: "Correct Night", changes: [change])]
    let decision = ReviewRecord(
      findingID: finding.id,
      decision: .correction,
      correctionOptionID: finding.corrections[0].id,
      decidedAt: .now
    )
    var withdrawn = finding
    withdrawn.corrections = []

    let kept = DecisionCarryForward.carry(
      [decision],
      from: runs.audit([finding]),
      to: runs.audit([finding])
    )
    let dropped = DecisionCarryForward.carry(
      [decision],
      from: runs.audit([finding]),
      to: runs.audit([withdrawn])
    )

    #expect(kept.decisions[finding.id] == decision)
    #expect(dropped.decisions[finding.id] == nil)
    #expect(dropped.history.map(\.outcome) == [.correctionNoLongerOffered])
  }

  @Test
  func `drops a decision when a record it involves changed`() {
    var runs = Runs()
    let finding = Runs.finding(Runs.first, night: 90)
    let previous = runs.audit([finding])
    runs.fingerprints[Runs.first] = RecordFingerprint(rawValue: "changed")

    let result = DecisionCarryForward.carry(
      [decide(finding)],
      from: previous,
      to: runs.audit([finding])
    )
    #expect(result.decisions.isEmpty)
    #expect(result.history.map(\.outcome) == [.recordsOrEvidenceChanged])
  }

  @Test
  func `drops a decision when new evidence replaces the finding`() {
    let runs = Runs()
    let finding = Runs.finding(Runs.first, night: 90)
    let replacement = Runs.finding(Runs.first, night: 95)

    let result = DecisionCarryForward.carry(
      [decide(finding)],
      from: runs.audit([finding]),
      to: runs.audit([replacement])
    )
    #expect(result.decisions.isEmpty && result.retired.isEmpty)
    #expect(result.history.map(\.outcome) == [.recordsOrEvidenceChanged])
  }

  @Test
  func `retires a reviewed finding the new run no longer produces`() {
    let runs = Runs()
    let finding = Runs.finding(Runs.first, night: 90)
    let decision = decide(finding, .correction)

    let result = DecisionCarryForward.carry(
      [decision],
      from: runs.audit([finding]),
      to: runs.audit([Runs.finding(Runs.first, night: 90, rule: "block_duration")])
    )
    #expect(result.retired == [RetiredFinding(finding: finding, decision: decision)])
    #expect(result.history.first?.isCarried == true)
  }

  @Test
  func `reports a decision the previous run has no finding for and still counts it`() {
    let runs = Runs()
    let known = Runs.finding(Runs.first, night: 90)
    let stray = decide(Runs.finding(Runs.second, night: 70), .needsEvidence)

    let result = DecisionCarryForward.carry(
      [decide(known), stray],
      from: runs.audit([known]),
      to: runs.audit([known])
    )

    #expect(result.history.map(\.outcome) == [.carried, .findingUnknown])
    #expect(result.history[1].rule == nil)
    #expect(result.history[1].recordIDs.isEmpty)
    #expect(result.counts == [.falsePositive: 1, .needsEvidence: 1])
    #expect(result.decisions.keys.contains(stray.findingID) == false)
  }
}

@Suite
struct `Decision exports` {
  private let runs = Runs()
  private let findings = [Runs.finding(Runs.first, night: 90), Runs.finding(Runs.second, night: 70)]

  @Test
  func `round-trips decisions for the run they were made against`() throws {
    let audit = runs.audit(findings)
    let decisions = [decide(findings[0], .correction), decide(findings[1])]
    let export = ReviewExport(audit: audit, decisions: decisions)

    #expect(export.selectedFindingIDs == [findings[0].id])
    #expect(try export.validated(against: audit) == decisions)
  }

  @Test
  func `refuses decisions for another run, duplicates and inconsistent selections`() {
    let audit = runs.audit(findings)
    let other = runs.audit([findings[0]])

    #expect(throws: ReviewExportError.auditMismatch) {
      try ReviewExport(audit: other, decisions: []).validated(against: audit)
    }
    #expect(throws: ReviewExportError.duplicateDecision(findings[0].id)) {
      try ReviewExport(audit: audit, decisions: [decide(findings[0]), decide(findings[0])])
        .validated(against: audit)
    }
    var export = ReviewExport(audit: audit, decisions: [decide(findings[0], .correction)])
    export.selectedFindingIDs.append(findings[1].id)
    #expect(throws: ReviewExportError.selectionMismatch) { try export.validated(against: audit) }
    export.selectedFindingIDs = [findings[0].id, findings[0].id]
    #expect(throws: ReviewExportError.selectionMismatch) { try export.validated(against: audit) }
  }

  @Test
  func `refuses an unsupported format version and a decision about an unknown finding`() {
    let audit = runs.audit([findings[0]])
    var export = ReviewExport(audit: audit, decisions: [])
    let unsupported = ReviewExport.currentSchemaVersion + 1
    export.schemaVersion = unsupported
    #expect(throws: ReviewExportError.unsupportedSchemaVersion(unsupported)) {
      try export.validated(against: audit)
    }

    let stray = decide(findings[1])
    #expect(throws: ReviewExportError.unknownFinding(stray.findingID)) {
      try ReviewExport(audit: audit, decisions: [stray]).validated(against: audit)
    }
  }
}

@Suite
struct `Audit identity` {
  @Test
  func `doesn't depend on the order sets in the settings encode in`() {
    let logbook = Logbook(identity: LogbookIdentity(storeUUID: Runs.storeUUID))
    let rules = (0..<20).map { RuleID(rawValue: "rule_\($0)") }
    var first = LogbookSettings()
    first.rules.disabledRules = Set(rules)
    var second = LogbookSettings()
    for rule in rules.reversed() { second.rules.disabledRules.insert(rule) }
    var changed = first
    changed.rules.disabledRules.remove(rules[0])

    let identity = ReviewedAudit(findings: [], logbook: logbook, settings: first).identity
    #expect(identity == ReviewedAudit(findings: [], logbook: logbook, settings: second).identity)
    #expect(identity != ReviewedAudit(findings: [], logbook: logbook, settings: changed).identity)
  }

  @Test
  func `fingerprints a group by its definition and membership, not member order`() {
    let id = RecordID(rawValue: "G1")
    func fingerprint(members: [String]) -> RecordFingerprint? {
      let group = LogbookGroup(
        id: id,
        name: "Trip",
        memberFlightIDs: members.map { RecordID(rawValue: $0) }
      )
      let logbook = Logbook(
        identity: LogbookIdentity(storeUUID: Runs.storeUUID),
        groups: [group]
      )
      return ReviewedAudit.fingerprints(of: logbook)[id]
    }

    let original = fingerprint(members: ["F1", "F2"])
    #expect(original != nil)
    #expect(original == fingerprint(members: ["F2", "F1"]))
    #expect(original != fingerprint(members: ["F1", "F2", "F3"]))
  }
}
