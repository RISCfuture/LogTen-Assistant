import AuditWorkflow
import Corrections
import Foundation
import LogbookModel
import LogbookTestSupport
import Testing

@Suite
struct `Apply workflow` {
  private static let metadata = ImportPackageMetadata(version: "1.0")
  private static let arrival = utc("2026-10-12T15:25:00Z")

  private static func lateArrival(on flight: Flight) -> ApprovedCorrection {
    let option = CorrectionOption(
      title: "Use FlySto’s Time",
      changes: [
        FieldChange(
          flightKey: flight.flightKey,
          recordID: flight.id,
          field: .flightActualArrivalTime,
          old: flight[field: .flightActualArrivalTime],
          new: .date(arrival)
        )
      ]
    )
    let finding = Finding(
      rule: "telemetry_time",
      recordIDs: [flight.id],
      message: "In differs.",
      evidence: ["flight": .string(flight.id.rawValue)],
      corrections: [option]
    )
    return ApprovedCorrection(finding: finding, option: option)
  }

  /// The logbook with every change of some batches made, as LogTen would make them.
  private static func applying(_ batches: [CorrectionBatch], to logbook: Logbook) -> Logbook {
    var updated = logbook
    for change in batches.flatMap(\.changes) {
      guard let index = updated.flights.firstIndex(where: { $0.id == change.recordID }) else {
        continue
      }
      updated.flights[index][field: change.field] = change.new
    }
    return updated
  }

  @Test
  func `sends ready flights in a pilot batch and lists the rest for manual editing`() throws {
    let flights = [flight("A"), flight("B"), flight("C", isLocked: true)]
    let book = logbook(flights)
    let flightsByID = Dictionary(uniqueKeysWithValues: flights.map { ($0.id, $0) })
    let approvals = flights.map(Self.lateArrival).map { approval in
      ApprovedCorrection(
        finding: approval.finding.markingCorrectionRestriction(on: flightsByID),
        option: approval.option
      )
    }

    let plan = try ApplyPlan(
      approving: approvals,
      audited: book,
      current: book,
      metadata: Self.metadata
    )

    #expect(plan.batches.map(\.recordIDs) == [["A"], ["B"]])
    #expect(plan.preflight.excluded.map(\.operation.recordIDs) == [["C"]])
    #expect(plan.preflight.checklist.items.map(\.change.recordID) == ["C"])
    #expect(approvals[2].finding.correctionRestriction == .locked)
    #expect(plan.preflight.excluded.map(\.issues) == [[.locked("C")]])
    #expect(plan.flightCount == 2)
  }

  @Test
  func `journals a recorded batch without verifying it`() async throws {
    let directory = try TemporaryDirectory()
    let book = logbook([flight("A")])
    let plan = try ApplyPlan(
      approving: [Self.lateArrival(on: book.flights[0])],
      audited: book,
      current: book,
      metadata: Self.metadata
    )
    let delivery = BatchDelivery(
      writer: RecordingWriter(directory: directory.url),
      metadata: Self.metadata
    )
    var journal = ApplyJournal(storeUUID: book.identity.storeUUID)

    let entry = try await delivery.deliver(
      plan.batches[0],
      into: &journal,
      before: book
    ) {
      Issue.record("A recorded batch was verified"); return book
    }

    #expect(entry.status == .delivered)
    #expect(entry.receipt.recordedFile?.lastPathComponent == "\(plan.batches[0].id).json")
    #expect(journal.appliedBatches.isEmpty)
  }

  @Test
  func `verifies a sent batch and reverts it with its old values`() async throws {
    let book = logbook([flight("A")])
    let batch = CorrectionBatch(changes: Self.lateArrival(on: book.flights[0]).option.changes)
    let delivery = BatchDelivery(
      writer: SendingWriter(),
      verifier: BatchVerifier(timeout: .seconds(1), pollInterval: .milliseconds(10)),
      metadata: Self.metadata
    )
    var journal = ApplyJournal(storeUUID: book.identity.storeUUID)
    let applied = Self.applying([batch], to: book)

    let entry = try await delivery.deliver(batch, into: &journal, before: book) { applied }
    let revert = try BatchDelivery.revertBatch(for: entry.id, in: journal, current: applied)

    #expect(entry.status == .verified)
    #expect(revert == batch.compensating)
    #expect(revert.changes.first?.new == book.flights[0][field: .flightActualArrivalTime])
  }

  @Test
  func `refuses to revert a batch whose flight changed since`() throws {
    let book = logbook([flight("A")])
    let batch = CorrectionBatch(changes: Self.lateArrival(on: book.flights[0]).option.changes)
    var journal = ApplyJournal(storeUUID: book.identity.storeUUID)
    let id = journal.recordDelivery(
      of: batch,
      package: try ImportPackage(batch: batch, metadata: Self.metadata),
      receipt: WriteReceipt(batchID: batch.id, deliveredAt: .now)
    )
    let applied = Self.applying([batch], to: book)
    journal.recordVerification(
      BatchVerifier.verify(batch, before: book, current: applied),
      for: id
    )
    let edited = logbook([flight("A", in: "2026-10-12T16:00:00Z")])

    #expect {
      try BatchDelivery.revertBatch(for: id, in: journal, current: edited)
    } throws: { error in
      guard case .blocked(let changes) = error as? RevertError else { return false }
      return changes.map(\.change.recordID) == ["A"]
    }
  }
}

/// A writer that pretends to hand packages to LogTen, so deliveries are verified.
private struct SendingWriter: CorrectionWriter {
  func write(_: ImportPackage, for batch: CorrectionBatch) -> WriteReceipt {
    WriteReceipt(batchID: batch.id, deliveredAt: .now)
  }
}
