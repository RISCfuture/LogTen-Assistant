public import LogbookModel

/**
 The changes the reviewer approved, one operation per approved finding, with the state of each
 record when the finding was approved.

 A proposal is built from an explicit selection: an empty selection is an error, never “all
 findings”. Before anything is sent to LogTen, ``Preflight`` checks every operation against a
 fresh snapshot.
 */
public struct CorrectionProposal: Hashable, Codable, Sendable {
  /// The operations, in selection order.
  public var operations: [CorrectionOperation]

  /// Every change, in operation order.
  public var changes: [FieldChange] { operations.flatMap(\.changes) }

  /// Creates a proposal from operations.
  public init(operations: [CorrectionOperation]) {
    self.operations = operations
  }

  /**
   Proposes the changes of approved findings, each through the option the reviewer chose.

   - Parameters:
     - approvals: The findings approved for correction, in order; a finding approved twice is
       proposed once.
     - notes: The reviewer's notes, by finding.
     - logbook: The snapshot the findings were computed from, whose record fingerprints the
       operations keep.
   - Throws: ``CorrectionError/emptySelection`` if nothing is approved.
   */
  public init(
    approving approvals: [ApprovedCorrection],
    notes: [FindingID: String] = [:],
    logbook: Logbook
  ) throws(CorrectionError) {
    guard !approvals.isEmpty else { throw .emptySelection }
    var seen = Set<FindingID>()
    operations = approvals.filter { seen.insert($0.finding.id).inserted }.map { approval in
      CorrectionOperation(
        approval: approval,
        note: notes[approval.finding.id] ?? "",
        logbook: logbook
      )
    }
  }
}

/// A finding approved for correction, with the option the reviewer chose to resolve it.
public struct ApprovedCorrection: Hashable, Sendable {
  /// The finding.
  public let finding: Finding

  /// The chosen option, one of the finding's corrections.
  public let option: CorrectionOption

  /// Pairs a finding with one of its correction options.
  public init(finding: Finding, option: CorrectionOption) {
    precondition(finding.corrections.contains(option), "The option must be the finding's own")
    self.finding = finding
    self.option = option
  }
}

/// The changes one approved finding proposes.
public struct CorrectionOperation: Identifiable, Hashable, Codable, Sendable {
  private static let identifierLength = 20

  /// The operation's content-addressed identifier: the first 20 hexadecimal digits of the
  /// SHA-256 digest of its finding and the chosen option's changes.
  public let id: String

  /// The finding approved.
  public let findingID: FindingID

  /// The finding's rule.
  public let rule: RuleID

  /// The finding's description.
  public let message: String

  /// The records the finding involves.
  public let recordIDs: [RecordID]

  /// The reviewer's note.
  public let note: String

  /// The correction option chosen.
  public let optionID: CorrectionOptionID

  /// The chosen option's title.
  public let optionTitle: String

  /// The changes to make.
  public let changes: [FieldChange]

  /// The fingerprint of each involved record when the finding was approved.
  public let recordFingerprints: [RecordID: RecordFingerprint]

  /// Creates the operation for an approved finding and its chosen option.
  public init(approval: ApprovedCorrection, note: String = "", logbook: Logbook) {
    let finding = approval.finding
    id = String(
      CanonicalJSON.sha256(of: [
        .string(finding.id.rawValue), .array(approval.option.changes.map(\.canonicalJSON))
      ])
      .prefix(Self.identifierLength)
    )
    findingID = finding.id
    rule = finding.rule
    message = finding.message
    recordIDs = finding.recordIDs
    self.note = note
    optionID = approval.option.id
    optionTitle = approval.option.title
    changes = approval.option.changes
    recordFingerprints = logbook.fingerprints.filter { finding.recordIDs.contains($0.key) }
  }
}
