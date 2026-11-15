public import Corrections
public import Foundation
public import LogbookModel

/// What applying the approved findings would do: the proposal, the preflight against a fresh
/// snapshot, and the batches to deliver.
public struct ApplyPlan: Hashable, Sendable {
  /// The longest `logten://` URL a batch is allowed to produce, in characters.
  public static let defaultMaximumURLLength = 8_000

  /// The approved changes, with each record's state when it was approved.
  public var proposal: CorrectionProposal

  /// Which operations are ready and which are excluded, with the manual checklist.
  public var preflight: PreflightResult

  /// The batches of ready changes, pilot batch first.
  public var batches: [CorrectionBatch]

  /// The number of flights the batches change.
  public var flightCount: Int { Set(batches.flatMap(\.recordIDs)).count }

  /**
   Plans the application of approved findings.

   - Parameters:
     - approvals: The approved findings and their chosen options, in order.
     - notes: The reviewer's notes, by finding.
     - audited: The snapshot the findings were computed from.
     - current: A snapshot taken just now, which preflight checks against.
     - metadata: The metadata the packages will carry.
     - maximumURLLength: The longest import URL a batch may produce.
   - Throws: `CorrectionError` if nothing is approved or a ready change can't be packaged.
   */
  public init(
    approving approvals: [ApprovedCorrection],
    notes: [FindingID: String] = [:],
    audited: Logbook,
    current: Logbook,
    metadata: ImportPackageMetadata,
    maximumURLLength: Int = defaultMaximumURLLength
  ) throws(CorrectionError) {
    proposal = try CorrectionProposal(approving: approvals, notes: notes, logbook: audited)
    preflight = Preflight.check(proposal, against: current)
    batches = try CorrectionBatch.plan(
      preflight.readyChanges,
      maximumURLLength: maximumURLLength,
      metadata: metadata
    )
  }
}

/**
 Delivers batches to LogTen through a writer, journals each one, and verifies it.

 A batch a recording writer saved to disk was never sent to LogTen, so it is journaled without
 verification. A sent batch is verified by polling fresh snapshots until its changes appear or
 the verifier gives up.
 */
public struct BatchDelivery: Sendable {
  /// The writer packages go through.
  public var writer: any CorrectionWriter

  /// Waits for and checks each sent batch.
  public var verifier: BatchVerifier

  /// The metadata every package carries.
  public var metadata: ImportPackageMetadata

  /// Creates a delivery.
  public init(
    writer: any CorrectionWriter,
    verifier: BatchVerifier = .init(),
    metadata: ImportPackageMetadata
  ) {
    self.writer = writer
    self.verifier = verifier
    self.metadata = metadata
  }

  /**
   The batch that reverts a journaled batch, checked against a fresh snapshot.

   - Parameters:
     - entryID: The journal entry to revert.
     - journal: The journal.
     - current: A snapshot taken just now.
   - Throws: ``RevertError`` if the entry can't be reverted or a flight changed since.
   */
  public static func revertBatch(
    for entryID: UUID,
    in journal: ApplyJournal,
    current: Logbook
  ) throws(RevertError) -> CorrectionBatch {
    guard let batch = journal.revertBatch(for: entryID) else { throw .notApplied }
    let issues = Preflight.check(batch.changes, against: current)
    let blocked = zip(batch.changes, issues).filter { !$0.1.isEmpty }
    guard blocked.isEmpty else {
      throw .blocked(blocked.map { BlockedChange(change: $0.0, issues: $0.1) })
    }
    return batch
  }
  /**
   Delivers one batch and journals it.

   - Parameters:
     - batch: The batch.
     - revertedEntryID: The journal entry the batch reverts, if it is a compensating batch.
     - journal: The journal to record the delivery and verification in.
     - applied: Batches of this apply already delivered and verified since `before`.
     - before: The snapshot taken before the first batch of this apply.
     - snapshot: Takes and reads a fresh snapshot.
   - Returns: The journal entry, with its verification if the batch was sent.
   */
  public func deliver(
    _ batch: CorrectionBatch,
    reverting revertedEntryID: UUID? = nil,
    into journal: inout ApplyJournal,
    after applied: [CorrectionBatch] = [],
    before: Logbook,
    snapshot: () async throws -> Logbook
  ) async throws -> ApplyJournalEntry {
    let package = try ImportPackage(batch: batch, metadata: metadata)
    let receipt = try await writer.write(package, for: batch)
    let entryID = journal.recordDelivery(
      of: batch,
      package: package,
      receipt: receipt,
      reverting: revertedEntryID
    )
    if receipt.recordedFile == nil {
      let verification = try await verifier.waitAndVerify(
        batch,
        after: applied,
        before: before,
        snapshot: snapshot
      )
      journal.recordVerification(verification, for: entryID)
    }
    guard let entry = journal.entry(entryID) else {
      preconditionFailure("The journal lost the entry it just recorded")
    }
    return entry
  }
}

/// A compensating change that can't be applied as it stands.
public struct BlockedChange: Hashable, Sendable {
  /// The change.
  public var change: FieldChange

  /// Why it can't be applied.
  public var issues: [PreflightIssue]
}

/// Why a batch can't be reverted.
public enum RevertError: Error, Hashable, Sendable {
  /// The batch isn't applied and in effect.
  case notApplied
  /// Some flights changed since the batch was applied.
  case blocked([BlockedChange])
}

extension RevertError: LocalizedError {
  public var errorDescription: String? {
    String(localized: "The batch can’t be reverted.", bundle: .module)
  }

  public var failureReason: String? {
    switch self {
      case .notApplied:
        String(
          localized: "The batch isn’t applied, or another batch already reverted it.",
          bundle: .module
        )
      case .blocked(let changes):
        changes.flatMap(\.issues).map(\.explanation).uniqued().joined(separator: " ")
    }
  }

  public var recoverySuggestion: String? {
    switch self {
      case .notApplied: nil
      case .blocked:
        String(localized: "Restore the affected entries by hand in LogTen.", bundle: .module)
    }
  }
}

extension Array where Element: Hashable {
  fileprivate func uniqued() -> Self {
    var seen = Set<Element>()
    return filter { seen.insert($0).inserted }
  }
}
