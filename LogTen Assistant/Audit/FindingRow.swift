import AuditWorkflow
import Foundation
import LogbookModel
import Review
import Tracks

/// One finding in a review table, with what the table shows of its flight and decision.
nonisolated struct FindingRow: Identifiable, Hashable {
  /// The finding.
  let finding: Finding

  /// The first flight the finding involves, if it involves one.
  let flight: Flight?

  /// The aircraft track the finding is about, for activity that matches no flight.
  let segment: TrackSegment?

  /// The user's decision.
  let decision: ReviewDecision

  /// The correction option the row shows: the one chosen or picked, otherwise the first
  /// offered.
  let correction: CorrectionOption?

  /// The logbook's custom fields, for naming changed fields.
  let customFields: [CustomFieldDefinition]

  var id: FindingID { finding.id }

  /// When the flight happened, or the track began, if the finding involves either.
  var occurredAt: Date? { flight?.date ?? segment?.start }

  var date: Date { occurredAt ?? .distantPast }

  var registration: String { flight?.aircraft?.registration ?? segment?.registration ?? "" }

  var route: String { flight.flatMap(LogbookFormat.route(of:)) ?? "" }

  var ruleTitle: String { RuleDisplay.title(of: finding.rule) }

  var message: String { finding.message }

  /// The smart group a group finding is about, or an empty string for other findings.
  var groupName: String { finding.evidence["group"]?.stringValue ?? "" }

  /// The regulation the finding cites, or an empty string.
  var citation: String { finding.citation ?? "" }

  var severity: Severity { finding.severity }

  var severityRank: Int { Severity.allCases.firstIndex(of: finding.severity) ?? 0 }

  var decisionTitle: String { decision.title }

  /// The shown correction's changes, as “Field: old → new”.
  var changeSummary: String {
    (correction?.changes ?? []).map { change in
      let title = LogbookFormat.fieldTitle(change.field, customFields: customFields)
      let old = LogbookFormat.auditValue(change.old, of: change.field)
      let new = LogbookFormat.auditValue(change.new, of: change.field)
      return String(localized: "\(title): \(old) → \(new)")
    }
    .joined(separator: "; ")
  }

  /**
   Builds rows for findings.

   - Parameters:
     - findings: The findings.
     - book: The user's decisions.
     - picked: The correction options picked in the inspector, by finding.
     - customFields: The logbook's custom fields.
     - flight: Looks up a flight by identifier.
     - segment: Finds the track a finding is about; by default none.
   */
  static func rows(
    for findings: [Finding],
    book: ReviewBook,
    picked: [FindingID: CorrectionOptionID],
    customFields: [CustomFieldDefinition],
    flight: (RecordID) -> Flight?,
    segment: (Finding) -> TrackSegment? = { _ in nil }
  ) -> [Self] {
    findings.map { finding in
      Self(
        finding: finding,
        flight: finding.recordIDs.lazy.compactMap(flight).first,
        segment: segment(finding),
        decision: book.decision(for: finding.id),
        correction: book.shownCorrection(of: finding, picked: picked[finding.id]),
        customFields: customFields
      )
    }
  }
}

nonisolated extension ReviewBook {
  /// The correction option to show for a finding: the one its decision records, otherwise the
  /// one picked, otherwise the first it offers. A finding approved for correction without an
  /// option, which offers several, shows none, since the choice is still to be made.
  func shownCorrection(
    of finding: Finding,
    picked: CorrectionOptionID?
  ) -> CorrectionOption? {
    let record = records[finding.id]
    if let option = finding.correction(record?.correctionOptionID) ?? finding.correction(picked) {
      return option
    }
    let awaitsChoice = record?.decision == .correction && finding.corrections.count > 1
    return awaitsChoice ? nil : finding.corrections.first
  }
}
