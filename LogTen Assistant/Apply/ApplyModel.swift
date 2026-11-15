import AuditWorkflow
import Corrections
import Foundation
import LogbookModel
import Observation
import Review
import Workspace

/**
 Drives the Apply sheet: plans the approved fixes against a fresh snapshot, backs the logbook up,
 then delivers the pilot batch and the rest one at a time, verifying each.

 Applying can't start until a backup succeeds and the user confirms they made a LogTen backup
 too. Cancelling stops before the next batch; a batch already handed to LogTen is still
 verified.
 */
@Observable
final class ApplyModel {
  /// Where applying stands.
  private(set) var step = Step.preparing

  /// The plan, once prepared.
  private(set) var plan: ApplyPlan?

  /// The backup, once made.
  private(set) var backup: BackupManifest?

  /// Whether the backup is being made.
  private(set) var isBackingUp = false

  /// Whether the user confirms they made a backup in LogTen.
  var confirmsLogTenBackup = false

  /// Each batch's state, in delivery order.
  private(set) var batches = [BatchProgress]()

  /// Whether the user asked to stop after the batch under way.
  private(set) var isCancelled = false

  /// Whether packages go to LogTen rather than to disk.
  private(set) var sendsToLogTen = false

  /// When the planned fixes recorded by an earlier apply were recorded, by finding, as of
  /// preparing.
  private(set) var recordedBefore = [FindingID: Date]()

  @ObservationIgnored private let session: LogbookSession
  @ObservationIgnored private var writer: (any CorrectionWriter)?

  /// Whether the Apply button is enabled.
  var canApply: Bool {
    backup != nil && confirmsLogTenBackup && !(plan?.batches.isEmpty ?? true)
      && step == .ready
  }

  /// How many batches have been delivered.
  var deliveredCount: Int { batches.count { $0.entry != nil } }

  /// How many batches were left undelivered.
  var stoppedCount: Int { batches.count { $0.state == .stopped } }

  /// The journal entry of the last batch delivered, if any was.
  var lastDeliveredEntryID: ApplyJournalEntry.ID? { batches.last { $0.entry != nil }?.entry?.id }

  /// Creates the model for a session's approved findings.
  init(session: LogbookSession) {
    self.session = session
  }

  private static func storeUUID(of session: LogbookSession) -> UUID {
    session.logbook?.identity.storeUUID ?? UUID()
  }

  /// Why a batch can't be delivered against the logbook as it is now, if it can't.
  private static func problem(with batch: CorrectionBatch, in logbook: Logbook) -> String? {
    let issues = Preflight.check(batch.changes, against: logbook).flatMap(\.self)
    guard !issues.isEmpty else { return nil }
    let reasons = Set(issues.map(\.explanation)).sorted().joined(separator: " ")
    return String(localized: "The logbook changed since the plan was made. \(reasons)")
  }

  /// Takes a fresh snapshot and plans the approved fixes against it.
  func prepare() async {
    step = .preparing
    guard session.logbook != nil, session.workspace != nil else { return }
    do {
      plan(against: try await session.freshLogbook())
    } catch {
      step = .failed(error.localizedDescription)
    }
  }

  /// Plans the approved fixes against the logbook as it is now.
  func plan(against current: Logbook) {
    guard let audited = session.logbook, let workspace = session.workspace else { return }
    do {
      let plan = try ApplyPlan(
        approving: session.approvedCorrections,
        notes: session.reviewBook.records.compactMapValues { $0.note.isEmpty ? nil : $0.note },
        audited: audited,
        current: current,
        metadata: .app
      )
      self.plan = plan
      recordedBefore = session.recordedFixDates
      batches = plan.batches.map { BatchProgress(batch: $0) }
      let chosen = WriterPolicy.writer(for: workspace, isFixture: session.isFixture)
      writer = chosen.writer
      sendsToLogTen = chosen.sendsToLogTen
      step = .ready
    } catch {
      step = .failed(error.localizedDescription)
    }
  }

  /// Backs the logbook up into its workspace.
  func backUp() async {
    guard let workspace = session.workspace else { return }
    isBackingUp = true
    defer { isBackingUp = false }
    do {
      backup = try await LogbookBackupTask(reference: session.reference, workspace: workspace).run()
      var journal = session.journal ?? ApplyJournal(storeUUID: Self.storeUUID(of: session))
      journal.backup = backup
      try await session.saveJournal(journal)
    } catch {
      session.actionError = error
    }
  }

  /// Delivers the batches in order, stopping early if cancelled or a batch fails verification.
  /// Batches not reached are marked stopped.
  func apply() async {
    guard canApply else { return }
    step = .applying
    session.isApplying = true
    await deliverBatches()
    markUndeliveredBatchesStopped()
    session.isApplying = false
    step = .finished
    await session.runAudit()
  }

  private func deliverBatches() async {
    guard let writer else { return }
    let delivery = BatchDelivery(writer: writer, metadata: .app)
    var journal = session.journal ?? ApplyJournal(storeUUID: Self.storeUUID(of: session))
    var applied = [CorrectionBatch]()
    var baseline: Logbook?
    for index in batches.indices where !isCancelled {
      batches[index].state = sendsToLogTen ? .waitingForLogTen : .recording
      do {
        let current = try await session.freshLogbook()
        if let problem = Self.problem(with: batches[index].batch, in: current) {
          batches[index].state = .error(problem)
          break
        }
        let before = baseline ?? current
        baseline = before
        let entry = try await delivery.deliver(
          batches[index].batch,
          into: &journal,
          after: applied,
          before: before
        ) { [session] in try await session.freshLogbook() }
        try await session.saveJournal(journal)
        batches[index].entry = entry
        batches[index].state = .finished(entry.status)
        guard entry.status != .failed else { break }
        applied.append(batches[index].batch)
      } catch {
        batches[index].state = .error(error.localizedDescription)
        break
      }
    }
  }

  /// Marks the batches never started as stopped. Their fixes stay approved, so they can be applied
  /// later.
  private func markUndeliveredBatchesStopped() {
    for index in batches.indices where batches[index].state == .pending {
      batches[index].state = .stopped
    }
  }

  /// Stops applying after the batch under way.
  func cancel() { isCancelled = true }

  /// Moves to a step without doing its work, so a preview can show the sheet at that step.
  func showForPreview(_ step: Step) { self.step = step }

  /// Shows the first batch recorded and the rest not applied, as after stopping early.
  func showStoppedForPreview() {
    for index in batches.indices {
      batches[index].state = index == 0 ? .finished(.delivered) : .stopped
    }
    step = .finished
  }

  /// Where applying stands.
  enum Step: Equatable {
    /// The fresh snapshot is being taken and the plan made.
    case preparing
    /// The plan is ready for review and backup.
    case ready
    /// Batches are being delivered.
    case applying
    /// Every batch was delivered, or applying stopped.
    case finished
    /// Planning failed.
    case failed(String)
  }
}

/// One batch's progress through the Apply sheet.
struct BatchProgress: Identifiable {
  /// The batch.
  let batch: CorrectionBatch

  /// Where the batch stands.
  var state = State.pending

  /// The batch's journal entry, once delivered.
  var entry: ApplyJournalEntry?

  var id: String { batch.id }

  /// Where a batch stands.
  enum State: Equatable {
    /// Not delivered yet.
    case pending
    /// Not delivered because applying stopped first; its fixes stay approved.
    case stopped
    /// Being saved to disk.
    case recording
    /// Handed to LogTen; waiting for the user to confirm the import and for the change to show.
    case waitingForLogTen
    /// Delivered, with its journal status.
    case finished(ApplyJournalEntry.Status)
    /// Delivery failed.
    case error(String)
  }
}

extension LogbookSession {
  /// Whether packages go to LogTen rather than to disk.
  var sendsToLogTen: Bool {
    guard let workspace else { return false }
    return WriterPolicy.writer(for: workspace, isFixture: isFixture).sendsToLogTen
  }

  /// Saves the apply journal to the workspace and shows it.
  func saveJournal(_ journal: ApplyJournal) async throws {
    try await workspace?.save(JournalDocument(journal: journal))
    self.journal = journal
  }

  /**
   Reverts a delivered batch by delivering its compensating batch, after checking it against a
   fresh snapshot.

   A batch sent to LogTen is preceded by a fresh backup of the logbook; the caller has the
   user confirm a LogTen backup first.
   */
  func revert(_ entryID: UUID) async {
    guard canStartDataTask, let workspace, var journal else { return }
    activity = Activity(title: String(localized: "Reverting batch…"))
    do {
      let current = try await freshLogbook()
      let batch = try BatchDelivery.revertBatch(for: entryID, in: journal, current: current)
      let (writer, sendsToLogTen) = WriterPolicy.writer(for: workspace, isFixture: isFixture)
      if sendsToLogTen {
        journal.backup = try await LogbookBackupTask(reference: reference, workspace: workspace)
          .run()
      }
      let delivery = BatchDelivery(writer: writer, metadata: .app)
      let revertEntry = try await delivery.deliver(
        batch,
        reverting: entryID,
        into: &journal,
        before: current
      ) { [self] in try await freshLogbook() }
      try await saveJournal(journal)
      selectedJournalEntryID = revertEntry.id
    } catch {
      actionError = error
    }
    activity = nil
    await runAudit()
  }

  /// Whether a journal entry can be reverted now.
  func canRevert(_ entry: ApplyJournalEntry) -> Bool {
    journal?.revertBatch(for: entry.id) != nil && canStartDataTask
  }

  /// Backs up the logbook into its workspace, outside of applying.
  func backUpLogbook() async {
    guard let workspace, activity == nil else { return }
    activity = Activity(title: String(localized: "Backing up the logbook…"))
    do {
      let manifest = try await LogbookBackupTask(reference: reference, workspace: workspace).run()
      var journal = journal ?? ApplyJournal(storeUUID: logbook?.identity.storeUUID ?? UUID())
      journal.backup = manifest
      try await saveJournal(journal)
      dataSourceStatus = String(
        localized:
          "Backed up ^[\(manifest.files.count) file](inflect: true) to \(manifest.directory.lastPathComponent)."
      )
    } catch {
      actionError = error
    }
    activity = nil
    if needsEvidenceReload { await reloadEvidenceWhenIdle() }
  }
}

extension ImportPackageMetadata {
  private static let versionKey = "CFBundleShortVersionString"
  private static let unknownVersion = "1.0"

  /// The metadata the app's packages carry: its name and version.
  static var app: Self {
    Self(version: Bundle.main.object(forInfoDictionaryKey: versionKey) as? String ?? unknownVersion)
  }
}
