public import Audit
public import FlightSources
public import Foundation
public import LogbookModel
public import Tracks

/// The result of one Audit & Fix run over a snapshot: every finding, with the evidence and
/// analysis behind it.
public struct AuditRun: Sendable {
  /// When the run finished.
  public var generatedAt: Date

  /// The findings to review, ordered by rule and then identifier.
  public var findings: [Finding]

  /// Findings withheld by policy, such as activity while instructing.
  public var excluded: [ExcludedFinding]

  /// Diagnoses of consistency findings, such as likely date errors.
  public var analyses: [FindingID: FindingAnalysis]

  /// Follow-up detail for evidence findings: what to check and the events observed.
  public var followUps: [FindingID: AuditFollowUp]

  /// The external evidence for each entry that has some.
  public var contexts: [RecordID: EvidenceContext]

  /// How each compared field of each entry was decided between the sources.
  public var sourceChoices: [RecordID: [SourceChoice]]

  /// The FlySto records the run used.
  public var flyStoRecords: [FlyStoRecord]

  /// How each FlySto record was matched to an entry.
  public var flyStoMatches: [EvidenceMatch]

  /// Every track segment found, by identifier.
  public var segments: [String: TrackSegment]

  /// How each flight segment was matched to an entry.
  public var segmentMatches: [SegmentMatch]

  /// How each logbook group was evaluated.
  public var groupEvaluations: [SmartGroupEvaluation]

  /// Audits that couldn't run, and why.
  public var notes: [AuditNote]

  /// Creates a run from its parts.
  public init(
    generatedAt: Date,
    findings: [Finding],
    excluded: [ExcludedFinding] = [],
    analyses: [FindingID: FindingAnalysis] = [:],
    followUps: [FindingID: AuditFollowUp] = [:],
    contexts: [RecordID: EvidenceContext] = [:],
    sourceChoices: [RecordID: [SourceChoice]] = [:],
    flyStoRecords: [FlyStoRecord] = [],
    flyStoMatches: [EvidenceMatch] = [],
    segments: [String: TrackSegment] = [:],
    segmentMatches: [SegmentMatch] = [],
    groupEvaluations: [SmartGroupEvaluation] = [],
    notes: [AuditNote] = []
  ) {
    self.generatedAt = generatedAt
    self.findings = findings.sorted { ($0.rule, $0.id) < ($1.rule, $1.id) }
    self.excluded = excluded
    self.analyses = analyses
    self.followUps = followUps
    self.contexts = contexts
    self.sourceChoices = sourceChoices
    self.flyStoRecords = flyStoRecords
    self.flyStoMatches = flyStoMatches
    self.segments = segments
    self.segmentMatches = segmentMatches
    self.groupEvaluations = groupEvaluations
    self.notes = notes
  }
}

// MARK: - Lookup

extension AuditRun {
  private static let segmentEvidenceKey = "segment_id"

  /// The findings in a review queue.
  public func findings(in queue: ReviewQueue) -> [Finding] {
    findings.filter { ReviewQueue(rule: $0.rule) == queue }
  }

  /// The finding with an identifier, if the run produced it.
  public func finding(_ id: FindingID) -> Finding? {
    findings.first { $0.id == id }
  }

  /// The track segment a finding is about, for unmatched and ambiguous activity.
  public func segment(for finding: Finding) -> TrackSegment? {
    finding.evidence[Self.segmentEvidenceKey]?.stringValue.flatMap { segments[$0] }
  }

  /// The FlySto record matched to an entry, if exactly one was.
  public func flyStoRecord(for flightID: RecordID) -> FlyStoRecord? {
    guard
      let match = flyStoMatches.first(where: { $0.status == .matched && $0.flightID == flightID })
    else { return nil }
    return flyStoRecords.first { $0.id == match.sourceID }
  }
}

/// Why part of an audit didn't run.
public struct AuditNote: Hashable, Codable, Sendable {
  /// The part of the audit.
  public var subject: Subject

  /// A localized explanation.
  public var message: String

  /// Creates a note.
  public init(subject: Subject, message: String) {
    self.subject = subject
    self.message = message
  }

  /// The parts of an audit that can be skipped.
  public enum Subject: String, Codable, Sendable {
    /// Comparisons with FlySto records.
    case flySto = "fly_sto"
    /// Comparisons with ADS-B tracks.
    case adsb
    /// Checks against FAA airport data.
    case airportData = "airport_data"
    /// Approach naming from published procedures.
    case approachData = "approach_data"
    /// Smart-group evaluation.
    case smartGroups = "smart_groups"
    /// The instruction-activity policy.
    case instructionPolicy = "instruction_policy"
  }
}
