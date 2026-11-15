public import Foundation
public import LogbookModel

/**
 The record of everything delivered to one logbook: each batch, its package, its verification,
 and the compensating batch that undoes it.

 The journal is the source of truth for what was applied. A batch counts as applied once it is
 verified; a failed or unverified batch stays in the journal so it is never retried blindly.
 Reverting a batch delivers its compensating batch, which is journaled like any other.
 */
public struct ApplyJournal: Hashable, Codable, Sendable {
  /// The logbook the journal belongs to.
  public var storeUUID: UUID

  /// The backup made before the first batch.
  public var backup: BackupManifest?

  /// The deliveries, in order.
  public private(set) var entries: [ApplyJournalEntry]

  /// The batches applied and verified, and not reverted, in order.
  public var appliedBatches: [CorrectionBatch] {
    let reverted = Set(entries.filter { $0.status == .verified }.compactMap(\.revertedEntryID))
    return entries.filter {
      $0.revertedEntryID == nil && $0.status == .verified && !reverted.contains($0.id)
    }
    .map(\.batch)
  }

  /// The flights whose applied changes are in effect.
  public var appliedRecordIDs: Set<RecordID> {
    appliedBatches.reduce(into: []) { $0.formUnion($1.recordIDs) }
  }

  /// Creates an empty journal.
  public init(storeUUID: UUID, backup: BackupManifest? = nil) {
    self.storeUUID = storeUUID
    self.backup = backup
    entries = []
  }

  /**
   Records that a batch was delivered.

   - Parameters:
     - batch: The batch.
     - package: The package delivered.
     - receipt: The writer's receipt.
     - revertedEntryID: The entry this batch reverts, if it is a compensating batch.
   - Returns: The new entry's identifier.
   */
  @discardableResult
  public mutating func recordDelivery(
    of batch: CorrectionBatch,
    package: ImportPackage,
    receipt: WriteReceipt,
    reverting revertedEntryID: UUID? = nil
  ) -> UUID {
    let entry = ApplyJournalEntry(
      batch: batch,
      packageJSON: package.json,
      receipt: receipt,
      revertedEntryID: revertedEntryID
    )
    entries.append(entry)
    return entry.id
  }

  /// Records a delivered batch's verification.
  public mutating func recordVerification(_ verification: BatchVerification, for entryID: UUID) {
    guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
    entries[index].verification = verification
  }

  /// The entry with an identifier.
  public func entry(_ id: UUID) -> ApplyJournalEntry? { entries.first { $0.id == id } }

  /**
   The batch that reverts an applied entry.

   - Returns: The entry's compensating batch, or `nil` if the entry isn't applied and in
     effect.
   */
  public func revertBatch(for entryID: UUID) -> CorrectionBatch? {
    guard let entry = entry(entryID), appliedBatches.contains(entry.batch) else { return nil }
    return entry.compensatingBatch
  }
}

/// One delivered batch.
public struct ApplyJournalEntry: Identifiable, Hashable, Codable, Sendable {
  /// The entry's identifier.
  public var id: UUID

  /// The batch delivered.
  public var batch: CorrectionBatch

  /// The exact package text delivered.
  public var packageJSON: String

  /// The writer's receipt.
  public var receipt: WriteReceipt

  /// The entry this one reverts, if it delivered a compensating batch.
  public var revertedEntryID: UUID?

  /// The verification, once the batch was verified.
  public var verification: BatchVerification?

  /// The batch that undoes this one.
  public var compensatingBatch: CorrectionBatch { batch.compensating }

  /// Whether the batch was verified, failed verification, or is awaiting it.
  public var status: Status {
    guard let verification else { return .delivered }
    return verification.isVerified ? .verified : .failed
  }

  /// Creates an entry.
  public init(
    id: UUID = UUID(),
    batch: CorrectionBatch,
    packageJSON: String,
    receipt: WriteReceipt,
    revertedEntryID: UUID? = nil,
    verification: BatchVerification? = nil
  ) {
    self.id = id
    self.batch = batch
    self.packageJSON = packageJSON
    self.receipt = receipt
    self.revertedEntryID = revertedEntryID
    self.verification = verification
  }

  /// Where a delivered batch stands.
  public enum Status: String, Codable, Sendable {
    /// Delivered, not yet verified.
    case delivered
    /// Verified as applied exactly.
    case verified
    /// Verification found discrepancies.
    case failed
  }
}
