import AuditWorkflow
import FlightSources
import Foundation
import LogbookModel
import References

/// A data-source task a logbook session is running.
struct Activity {
  /// What the task is doing, such as “Syncing FlySto…”.
  var title: String

  /// The task's progress, when it can be measured.
  var progress: ProgressReporter?

  /// Whether the task is a FlySto sync, which the toolbar's Sync FlySto button shows in its
  /// place, through the audit that follows it.
  var isFlyStoSync = false
}

extension LogbookSession {
  /// Whether a data-source task can start: the logbook is loaded and nothing else is running.
  var canStartDataTask: Bool { canRunAudit && workspace != nil }

  /// Whether a data-source task or the ADS-B download is running that Stop can cancel.
  var canStopDataTask: Bool { dataTask != nil || adsbDownload.isActive }

  /// Whether an ADS-B download can be set up: a data-source task could start and no download
  /// is running.
  var canFetchADSB: Bool { canStartDataTask && !adsbDownload.isActive }

  nonisolated private static func syncStatus(_ summary: FlyStoSyncSummary) -> String {
    if summary.unreadableCount == 0 {
      String(localized: "Synced \(summary.saved, format: .number) FlySto logs.")
    } else {
      String(
        localized:
          "Synced \(summary.saved, format: .number) FlySto logs; \(summary.unreadableCount, format: .number) couldn’t be read."
      )
    }
  }

  /// Fetches the FlySto logs added since the last sync, then audits again.
  ///
  /// - Returns: Whether the sync finished without being stopped or failing.
  @discardableResult
  func syncFlySto() async -> Bool {
    guard canStartDataTask, let workspace else { return false }
    return await perform(String(localized: "Syncing FlySto…"), isFlyStoSync: true) { [services] in
      let summary = try await EvidenceLibrary(workspace: workspace)
        .syncFlySto(with: services.flySto())
      return Self.syncStatus(summary)
    }
  }

  /**
   Imports FlySto CSV exports and their web archives, then audits again.

   - Parameter files: Files the user chose or dropped; any that aren't exports or archives are
     ignored.
   */
  func importFlyStoExport(_ files: [URL]) async {
    let importable = files.filter(EvidenceLibrary.isImportable)
    guard canStartDataTask, let workspace, !importable.isEmpty else { return }
    _ = await perform(String(localized: "Importing FlySto export…")) {
      let accessing = importable.filter { $0.startAccessingSecurityScopedResource() }
      defer { for file in accessing { file.stopAccessingSecurityScopedResource() } }
      let export = try await EvidenceLibrary(workspace: workspace).importFlyStoExport(importable)
      return String(
        localized:
          "Imported \(export.records.count, format: .number) FlySto records from \(export.rowCount, format: .number) rows."
      )
    }
  }

  /// Downloads the NASR cycle in effect today, if it isn't saved yet, then audits again.
  ///
  /// - Returns: Whether the download finished without being stopped or failing.
  @discardableResult
  func updateNASR() async -> Bool {
    guard canStartDataTask else { return false }
    let progress = ProgressManager(totalCount: 1)
    return await perform(String(localized: "Updating NASR data…"), progress: progress.reporter) {
      [services] in
      let index = try await services.nasr.index(
        covering: .now,
        progress: progress.subprogress(assigningCount: 1)
      )
      return String(
        localized:
          "Airport data is from the cycle effective \(index.effectiveDate, format: LogbookFormat.cycleDate)."
      )
    }
  }

  /// Downloads the CIFP cycle in effect today, if it isn't saved yet, then audits again.
  ///
  /// - Returns: Whether the download finished without being stopped or failing.
  @discardableResult
  func updateApproachData() async -> Bool {
    guard canStartDataTask else { return false }
    let finished = await perform(String(localized: "Updating approach data…")) { [services] in
      let cycle = try await services.cifp.download(covering: .now)
      return String(
        localized:
          "Approach data is from the cycle effective \(cycle, format: LogbookFormat.cycleDate)."
      )
    }
    approachLibrary = nil
    return finished
  }

  /**
   Notes which data sources are out of date, so the window offers to update them. It checks
   once, after the logbook first loads, and never for the sample logbook.
   */
  func checkDataSourcesOnce() {
    guard !hasCheckedDataSources, !isFixture, case .loaded = phase else { return }
    hasCheckedDataSources = true
    recheckStaleDataSources()
  }

  /// Updates the out-of-date data sources one after another, stopping at the first that is
  /// stopped or fails, and stops offering to.
  func updateStaleDataSources() async {
    guard let staleDataSources, canStartDataTask else { return }
    self.staleDataSources = nil
    var updates = [() async -> Bool]()
    if staleDataSources.isAirportDataStale { updates.append(updateNASR) }
    if staleDataSources.isApproachDataStale { updates.append(updateApproachData) }
    if staleDataSources.isFlyStoStale { updates.append(syncFlySto) }
    for update in updates {
      guard await update() else { return }
    }
  }

  /// Stops the running data-source task at its next suspension point, or else the ADS-B
  /// download. What either saved before stopping is still audited.
  func stopDataTask() {
    if let dataTask { dataTask.cancel() } else { adsbDownload.stop() }
  }

  /// Checks again whether a FlySto API token is stored, after the user may have saved one in
  /// Settings.
  func refreshFlyStoAccount() { hasFlyStoToken = services.hasFlyStoToken() }

  /// Rereads the saved evidence and audits again, repeating if more evidence was saved
  /// meanwhile.
  func evidenceDidChange() async {
    repeat {
      needsEvidenceReload = false
      await loadWorkflowState()
      await runWorkflowAudit()
    } while needsEvidenceReload
  }

  /**
   Rereads the saved evidence and audits again after a background download saved some, or, if
   another task or audit is running, has it do so once it finishes.
   */
  func reloadEvidenceWhenIdle() async {
    guard canRunAudit else {
      needsEvidenceReload = true
      return
    }
    activity = Activity(title: String(localized: "Auditing…"))
    await evidenceDidChange()
    activity = nil
  }

  /**
   Runs a data-source task, shows its progress, then rereads the evidence and audits again.

   The activity lasts until the audit finishes, so the window shows the task as running until
   its results are counted. ``stopDataTask()`` cancels the task, and the audit still runs over
   what it saved.

   - Parameters:
     - title: What the task is doing.
     - progress: The task's progress, if it can be measured.
     - isFlyStoSync: Whether the task is a FlySto sync.
     - task: The task; returns a summary for the Data Sources page.
   - Returns: Whether the task finished without being stopped or failing.
   */
  private func perform(
    _ title: String,
    progress: ProgressReporter? = nil,
    isFlyStoSync: Bool = false,
    task: @escaping @Sendable () async throws -> String
  ) async -> Bool {
    activity = Activity(title: title, progress: progress, isFlyStoSync: isFlyStoSync)
    let work = Task { try await DataTask(work: task).run() }
    dataTask = work
    var finished = false
    do {
      dataSourceStatus = try await withTaskCancellationHandler {
        try await work.value
      } onCancel: {
        work.cancel()
      }
      finished = true
    } catch _ where work.isCancelled {
      dataSourceStatus = String(localized: "Stopped.")
    } catch {
      actionError = error
    }
    dataTask = nil
    activity = Activity(title: String(localized: "Auditing…"), isFlyStoSync: isFlyStoSync)
    await evidenceDidChange()
    activity = nil
    if staleDataSources != nil { recheckStaleDataSources() }
    return finished
  }

  private func recheckStaleDataSources() {
    let stale = StaleDataSources(
      airportCycle: airportCycle,
      approachCycle: approachCycle,
      hasFlyStoToken: hasFlyStoToken,
      flyStoLastSynced: flyStoState.lastSyncedAt,
      flightDates: logbook?.flights.map(\.date) ?? []
    )
    staleDataSources = stale.isEmpty ? nil : stale
  }
}

/// Runs a data-source task off the main actor.
nonisolated private struct DataTask: Sendable {
  let work: @Sendable () async throws -> String

  @concurrent
  func run() async throws -> String { try await work() }
}
