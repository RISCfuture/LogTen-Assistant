import Audit
import AuditWorkflow
import Corrections
import FlightSources
import Foundation
import LogbookModel
import Review
import Tracks

extension PreviewHelper {
  private static let previewBlockMinutes = 12
  private static let previewTakeoffDelaySeconds = 7.0 * 60

  /// A correction that moves a flight's block-in later and adds the minutes to its total time.
  static func correction(of flight: Flight) -> CorrectionOption {
    let arrival = flight.events.in ?? flight.date
    let changes = [
      FieldChange(
        flightKey: flight.flightKey,
        recordID: flight.id,
        field: .flightActualArrivalTime,
        old: flight.events.in.map(FieldValue.date) ?? .null,
        new: .date(arrival.addingTimeInterval(Double(previewBlockMinutes) * 60))
      ),
      FieldChange(
        flightKey: flight.flightKey,
        recordID: flight.id,
        field: .flightTotalTime,
        old: .integer(Int(flight.times.total)),
        new: .integer(Int(flight.times.total) + previewBlockMinutes)
      )
    ]
    return CorrectionOption(title: "Use FlySto’s Block-In", changes: changes)
  }

  /// A journal holding a delivered, verified batch of a flight's correction.
  static func journal(of flight: Flight) -> ApplyJournal {
    var journal = ApplyJournal(storeUUID: UUID())
    let batch = CorrectionBatch(changes: correction(of: flight).changes)
    if let package = try? ImportPackage(
      batch: batch,
      metadata: ImportPackageMetadata(version: "1.0")
    ) {
      journal.recordDelivery(
        of: batch,
        package: package,
        receipt: WriteReceipt(batchID: batch.id, deliveredAt: .now)
      )
    }
    if let entry = journal.entries.last {
      journal.recordVerification(BatchVerification(batchID: batch.id), for: entry.id)
    }
    return journal
  }

  /// A journal holding one batch of approved fixes, recorded to disk rather than sent to LogTen.
  static func recordedJournal(of corrections: [ApprovedCorrection]) -> ApplyJournal {
    var journal = ApplyJournal(storeUUID: UUID())
    let batch = CorrectionBatch(changes: corrections.flatMap(\.option.changes))
    if let package = try? ImportPackage(
      batch: batch,
      metadata: ImportPackageMetadata(version: "1.0")
    ) {
      journal.recordDelivery(
        of: batch,
        package: package,
        receipt: WriteReceipt(
          batchID: batch.id,
          deliveredAt: .now,
          recordedFile: URL.temporaryDirectory.appending(path: "\(batch.id).json")
        )
      )
    }
    return journal
  }

  /// A delivered, verified batch of a flight's correction.
  static func journalEntry(of flight: Flight) -> ApplyJournalEntry {
    let batch = CorrectionBatch(changes: correction(of: flight).changes)
    return ApplyJournalEntry(
      batch: batch,
      packageJSON: #"{"batch":"\#(batch.id)"}"#,
      receipt: WriteReceipt(batchID: batch.id, deliveredAt: .now),
      verification: BatchVerification(batchID: batch.id)
    )
  }

  /// Sources that disagree with a flight's takeoff time, where FlySto's own records conflict, and
  /// with its landings, of which FlySto saw one more and ADS-B has no usable count.
  static func discrepancies(of flight: Flight) -> [SourceDiscrepancy] {
    let takeoff = (flight.events.off ?? flight.date).addingTimeInterval(previewTakeoffDelaySeconds)
    return [
      SourceDiscrepancy(
        title: ObservedField.time(.takeoff).title,
        fields: [.flightTakeoffTime],
        logbookValue: SourceValue.logbook(flight, .time(.takeoff)),
        readings: [
          SourceDiscrepancy.Reading(
            source: EvidenceSource.flySto.title,
            value: LogbookFormat.zuluTime(takeoff),
            isPreferred: true,
            isUsable: true,
            hasConflict: true
          ),
          SourceDiscrepancy.Reading(
            source: EvidenceSource.adsbLol.title,
            value: LogbookFormat.zuluTime(takeoff),
            isPreferred: false,
            isUsable: true,
            hasConflict: false
          )
        ]
      ),
      SourceDiscrepancy(
        title: ObservedField.count(.landing).title,
        fields: [.flightDayLandings, .flightNightLandings],
        logbookValue: SourceValue.logbook(flight, .count(.landing)),
        readings: [
          SourceDiscrepancy.Reading(
            source: EvidenceSource.flySto.title,
            value: (flight.counts.landings + 1).formatted(.number),
            isPreferred: true,
            isUsable: true,
            hasConflict: false
          ),
          SourceDiscrepancy.Reading(
            source: EvidenceSource.adsbLol.title,
            value: SourceValue.text(of: nil),
            isPreferred: false,
            isUsable: false,
            hasConflict: false
          )
        ]
      )
    ]
  }

  /// Shows Applied History with a delivered batch selected.
  static func selectAppliedBatch(in session: LogbookSession) {
    session.sidebarSelection = .audit(.appliedHistory)
    session.journal = journal(of: flight)
    session.selectedJournalEntryID = session.journal?.entries.first?.id
  }

  /**
   Marks for correction the findings of a loaded session that offer a correction, each with
   the correction it shows, skipping any whose changes touch a field an earlier one changes so
   the fixes plan without conflicts.

   - Parameters:
     - limit: The most findings to mark.
     - session: A loaded session.
   */
  static func approveCorrections(_ limit: Int = .max, in session: LogbookSession) {
    var changedFields = [RecordID: Set<LogTenFieldKey>]()
    var approved = Set<FindingID>()
    for finding in approvableFindings(in: session) where approved.count < limit {
      let changes = session.shownCorrection(of: finding)?.changes ?? []
      guard changes.allSatisfy({ changedFields[$0.recordID]?.contains($0.field) != true }) else {
        continue
      }
      changes.forEach { changedFields[$0.recordID, default: []].insert($0.field) }
      approved.insert(finding.id)
    }
    session.decide(.correction, for: approved)
  }

  /// Approves a loaded session's first fixes and records them as applied in record mode.
  static func approveAndRecord(_ count: Int, in session: LogbookSession) {
    approveCorrections(count, in: session)
    session.journal = recordedJournal(of: session.approvedCorrections)
  }

  /// The findings of a loaded session that offer a correction, each with the correction it
  /// shows picked so that they can be marked for correction together.
  static func approvableFindings(in session: LogbookSession) -> [Finding] {
    var approvable = [Finding]()
    for finding in session.auditRun?.findings ?? [] {
      guard let option = session.shownCorrection(of: finding) else { continue }
      session.pickedCorrections[finding.id] = option.id
      approvable.append(finding)
    }
    return approvable
  }

  /**
   Shows a review page and selects the first of its findings that passes a test.

   - Parameters:
     - page: The review page to show.
     - session: A loaded session.
     - isIncluded: Whether to select a finding.
   */
  static func selectFinding(
    on page: AuditPage = .logbookConsistency,
    in session: LogbookSession,
    where isIncluded: (Finding) -> Bool = { _ in true }
  ) {
    session.sidebarSelection = .audit(page)
    let findings = page.queue.map { session.findings(in: FindingList(queue: $0)) } ?? []
    session.selectedFindingIDs = Set([findings.first(where: isIncluded)?.id].compactMap(\.self))
  }
}
