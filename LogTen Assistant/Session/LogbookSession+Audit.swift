import AuditWorkflow
import Corrections
import FlightSources
import Foundation
import LogbookModel
import LogbookStore
import References
import Review
import Tracks
import Workspace

// MARK: - Running the audit

extension LogbookSession {
  /// Reads what the workspace and the reference-data folders hold: FlySto state, downloaded
  /// traces and NASR cycles, CIFP data and the apply journal.
  func loadWorkflowState() async {
    guard let workspace else { return }
    do {
      let library = EvidenceLibrary(workspace: workspace)
      flyStoState = try await library.syncState()
      flyStoRecordCount = try await library.flyStoRecords().count
      journal = try await JournalDocument.load(from: workspace)
    } catch {
      actionError = error
    }
    let registrations = Set(registrations.map { $0.uppercased() })
    adsbTraces = ((try? services.adsbCache.traces()) ?? [])
      .map(\.provenance)
      .filter { registrations.contains($0.registration?.uppercased() ?? "") }
    airportCycle = await services.nasr.savedCycles().max()
    hasApproachData = services.cifp.hasFile
    approachCycle = services.cifp.savedCycle
    refreshFlyStoAccount()
  }

  /**
   Runs the Audit & Fix checks over the loaded snapshot with the saved evidence, then carries
   the previous run's decisions forward to the new findings. Once it finishes, the sidebar
   selects a page if nothing has picked one yet.
   */
  func runWorkflowAudit() async {
    defer { selectInitialPageIfNeeded() }
    guard let logbook, let workspace else { return }
    commitDecisionEdit()
    phase = .working(.auditing)
    let preparation = AuditPreparation(
      services: services,
      workspace: workspace,
      logbook: logbook,
      settings: settings,
      snapshot: snapshot,
      approachLibrary: approachLibrary,
      loadsApproachData: hasApproachData
    )
    do {
      let (run, library) = try await withFractionReports(
        deliveredTo: { [weak self] in self?.loadFraction = $0 },
        body: { try await preparation.run(progress: $0) }
      )
      approachLibrary = library
      try await install(run, logbook: logbook, workspace: workspace)
    } catch is CancellationError {
      // The window closed; there's nothing to show.
    } catch {
      actionError = error
    }
    phase = .loaded
  }

  private func install(_ run: AuditRun, logbook: Logbook, workspace: Workspace) async throws {
    let reviewed = ReviewedAudit(findings: run.findings, logbook: logbook, settings: settings)
    await pendingReviewSave?.value
    let saved = try await ReviewState.load(from: workspace)
    let (book, result) = ReviewBook.carriedForward(from: saved, to: reviewed)
    auditRun = run
    reviewedAudit = reviewed
    reviewBook = book
    carryForward = result
    findingsByID = Dictionary(run.findings.map { ($0.id, $0) }) { first, _ in first }
    selectedFindingIDs.formIntersection(findingsByID.keys)
    saveReview()
  }
}

/// The work of an Audit & Fix run done off the main actor: gathering the saved evidence and
/// reference data, then running every check.
nonisolated private struct AuditPreparation: Sendable {
  /// The share of the audit's progress bar each preparation step fills, the checks taking
  /// the rest.
  private static let approachDataShare = 0.1
  private static let flyStoShare = 0.05
  private static let airportDataShare = 0.15

  let services: SessionServices
  let workspace: Workspace
  let logbook: Logbook
  let settings: LogbookSettings
  let snapshot: LogbookSnapshot?
  let approachLibrary: CIFPApproachLibrary?
  let loadsApproachData: Bool

  @concurrent
  func run(progress: @escaping ProgressTally.Report) async throws -> (
    AuditRun, CIFPApproachLibrary?
  ) {
    var finished = 0.0
    func complete(_ share: Double) {
      finished += share
      progress(finished)
    }

    progress(finished)
    let library = try await approaches()
    complete(Self.approachDataShare)
    let flyStoRecords = try await EvidenceLibrary(workspace: workspace).flyStoRecords()
    complete(Self.flyStoShare)
    let airportIndex = try await airportIndex()
    complete(Self.airportDataShare)
    let inputs = AuditInputs(
      logbook: logbook,
      settings: settings,
      flyStoRecords: flyStoRecords,
      tracks: tracks(),
      trackDetection: SessionServices.trackDetection,
      airportIndex: airportIndex,
      approachLookup: library,
      groupResolver: try snapshot.map { try LogbookReader(snapshot: $0, model: LogTenModel()) }
    )
    let prepared = finished
    let run = try await AuditRunner().run(inputs) { progress(prepared + (1 - prepared) * $0) }
    return (run, library)
  }

  /// The downloaded tracks of the logbook's aircraft, under any of their registrations.
  private func tracks() -> [Track] {
    var names = Set(logbook.aircraft.map { $0.registration.uppercased() })
    for (registration, aircraft) in settings.aircraft {
      names.insert(registration.uppercased())
      names.formUnion(aircraft.aliases.map { $0.uppercased() })
    }
    let traces = (try? services.adsbCache.traces()) ?? []
    return traces.map(\.track).filter { names.contains($0.registration.uppercased()) }
  }

  private func airportIndex() async throws -> AirportIndex? {
    guard let newest = await services.nasr.savedCycles().max() else { return nil }
    return try await services.nasr.savedIndex(covering: newest)
  }

  private func approaches() async throws -> CIFPApproachLibrary? {
    guard loadsApproachData else { return nil }
    if let approachLibrary { return approachLibrary }
    return try await CIFPApproachLibrary(contentsOf: services.cifp.fileURL)
  }
}

// MARK: - Default page

extension LogbookSession {
  /// The page a window opens on: the first review queue with a finding left to review,
  /// otherwise Data Sources.
  var initialSidebarSelection: SidebarItem {
    let page = AuditPage.allCases.first { page in
      page.queue.map { unreviewedCount(in: FindingList(queue: $0)) > 0 } ?? false
    }
    return .audit(page ?? .dataSources)
  }

  /// Selects ``initialSidebarSelection`` unless the user or the restored window state has
  /// already picked a page.
  func selectInitialPageIfNeeded() {
    guard sidebarSelection == nil else { return }
    sidebarSelection = initialSidebarSelection
  }
}

// MARK: - Findings

extension LogbookSession {
  /// The findings approved for correction, with their chosen options, in rule order.
  var approvedCorrections: [ApprovedCorrection] {
    reviewBook.approved(in: auditRun?.findings ?? [])
  }

  /// Whether the search field has text to match.
  var isSearching: Bool { !searchText.trimmingCharacters(in: .whitespaces).isEmpty }

  /// The findings the sidebar's page lists for review, if it lists any.
  var selectedList: FindingList? { sidebarSelection?.findingList }

  /// The findings the sidebar's page lists: a review page's, or the approved ones.
  var listedFindingIDs: Set<FindingID> {
    if let selectedList {
      Set(findings(in: selectedList).map(\.id))
    } else if sidebarSelection == .audit(.approved) {
      Set(approvedCorrections.map(\.finding.id))
    } else {
      []
    }
  }

  /// The findings of a list that are in scope and match the search field.
  func findings(in list: FindingList) -> [Finding] {
    scopedFindings(in: list).filter(matchesSearch)
  }

  /// A list's findings in the order the review table shows them, sorted by
  /// ``findingSortOrder``.
  func orderedFindings(in list: FindingList) -> [Finding] {
    FindingRow.rows(
      for: findings(in: list),
      book: reviewBook,
      picked: pickedCorrections,
      customFields: logbook?.customFields ?? [],
      flight: flight,
      segment: { self.auditRun?.segment(for: $0) }
    )
    .sorted(using: findingSortOrder)
    .map(\.finding)
  }

  /// Deselects the findings the sidebar's page doesn't list.
  func deselectUnlistedFindings() {
    selectedFindingIDs.formIntersection(listedFindingIDs)
  }

  /// Whether a list has findings in scope, reviewed or not.
  func hasFindings(in list: FindingList) -> Bool {
    !scopedFindings(in: list).isEmpty
  }

  /// The number of a list's findings in scope not reviewed yet.
  func unreviewedCount(in list: FindingList) -> Int {
    scopedFindings(in: list).count { reviewBook.decision(for: $0.id) == .unreviewed }
  }

  /// The correction option a finding shows: the one its decision records, otherwise the one
  /// picked in the inspector, otherwise the first it offers.
  func shownCorrection(of finding: Finding) -> CorrectionOption? {
    reviewBook.shownCorrection(of: finding, picked: pickedCorrections[finding.id])
  }

  /**
   Whether approving a finding records a correction the reviewer can see. When several
   findings are decided together, a finding that offers several options is approved only if
   one was picked for it.
   */
  func canApprove(_ finding: Finding, amongSeveral: Bool) -> Bool {
    guard shownCorrection(of: finding) != nil else { return false }
    return !amongSeveral || finding.corrections.count == 1
      || finding.correction(pickedCorrections[finding.id]) != nil
  }

  private func scopedFindings(in list: FindingList) -> [Finding] {
    guard let auditRun, let logbook else { return [] }
    return auditScope.findings(
      auditRun.findings(in: list.queue).filter(list.contains),
      in: logbook,
      asOf: .now,
      timeZone: settings.pilot.homeTimeZone
    )
  }

  /// Whether a finding matches the search field, by its message, its rule, its severity, or
  /// the date, registration, route or remarks of its flights.
  func matchesSearch(_ finding: Finding) -> Bool {
    let flights = finding.recordIDs.compactMap(flight)
    let timeZone = settings.pilot.homeTimeZone
    return matchesSearch(
      [
        finding.message, finding.rule.rawValue, RuleDisplay.title(of: finding.rule),
        finding.severity.title
      ]
        + flights.flatMap {
          [
            LogbookFormat.date($0.date, in: timeZone), $0.aircraft?.registration,
            LogbookFormat.route(of: $0), $0.remarks
          ]
        }
        .compactMap(\.self)
    )
  }

  /// Whether an Applied History entry matches the search field, by the registration or route
  /// of its flights or the date it was delivered.
  func matchesSearch(_ entry: ApplyJournalEntry) -> Bool {
    let flights = entry.batch.recordIDs.compactMap(flight)
    return matchesSearch(
      [entry.receipt.deliveredAt.formatted(date: .abbreviated, time: .shortened)]
        + flights.flatMap { [$0.aircraft?.registration, LogbookFormat.route(of: $0)] }
        .compactMap(\.self)
    )
  }

  private func matchesSearch(_ fields: [String]) -> Bool {
    let query = searchText.trimmingCharacters(in: .whitespaces)
    return query.isEmpty || fields.contains { $0.localizedStandardContains(query) }
  }
}

// MARK: - Decisions

/// The reason and note the user gives for a decision.
nonisolated struct DecisionDraft: Equatable, Sendable {
  /// Why the user decided as they did, if they chose a reason.
  var reason: ReviewReason?

  /// The user's note.
  var note = ""
}

nonisolated private extension DecisionDraft {
  /// Whether the draft holds nothing.
  var isEmpty: Bool { self == Self() }

  /// A record's reason and note.
  init(_ record: ReviewRecord) {
    self.init(reason: record.reason, note: record.note)
  }
}

extension LogbookSession {
  /// Whether review commands apply: a review page or the approved list is showing with
  /// findings selected.
  var canDecide: Bool {
    guard selectedList != nil || sidebarSelection == .audit(.approved) else { return false }
    return !selectedFindingIDs.isEmpty
  }

  /// Whether Mark for Correction applies: at least one selected finding can be approved.
  var canMarkForCorrection: Bool {
    guard canDecide else { return false }
    let selected = selectedFindingIDs.compactMap(finding)
    return selected.contains { canApprove($0, amongSeveral: selected.count > 1) }
  }

  /**
   The reason and note a finding's decision bar shows: those its decision recorded, or for an
   unreviewed finding, those typed for it so far.
   */
  func decisionDraft(for id: FindingID) -> DecisionDraft {
    reviewBook.records[id].map(DecisionDraft.init) ?? decisionDrafts[id] ?? DecisionDraft()
  }

  /**
   Changes the reason and note a finding's decision bar shows.

   An unreviewed finding keeps them as a draft until a decision records them. A decided
   finding's record changes: a new reason is saved at once, undoably, and a new note is saved
   by ``commitDecisionEdit()``.
   */
  func setDecisionDraft(_ draft: DecisionDraft, for id: FindingID) {
    guard var record = reviewBook.records[id] else {
      decisionDrafts[id] = draft.isEmpty ? nil : draft
      return
    }
    if draft.reason != record.reason {
      commitDecisionEdit()
      let previous = record
      record.reason = draft.reason
      record.note = draft.note
      reviewBook.set(record, for: id)
      registerUndo(restoring: [id: previous], actionName: String(localized: "Change Reason"))
      saveReview()
    } else if draft.note != record.note {
      if editedNoteOrigins[id] == nil { editedNoteOrigins[id] = record }
      record.note = draft.note
      reviewBook.set(record, for: id)
    }
  }

  /// Saves the notes edited on decided findings since the last commit, as one undoable edit.
  func commitDecisionEdit() {
    let origins = editedNoteOrigins.filter { id, record in reviewBook.records[id] != record }
    editedNoteOrigins.removeAll()
    guard !origins.isEmpty else { return }
    registerUndo(
      restoring: origins.mapValues(Optional.some),
      actionName: String(localized: "Edit Note")
    )
    saveReview()
  }

  /**
   Records a decision for findings, undoably. A correction records the option each finding
   shows, and skips findings ``canApprove(_:amongSeveral:)`` rules out.

   A finding already decided keeps its reason and note. A single selected finding not yet
   reviewed records its draft; findings decided together, or named by `ids`, record none.
   Resetting a decision keeps its reason and note as the finding's draft.

   - Parameters:
     - decision: The decision.
     - ids: The findings, as from a context menu; the selection when `nil`.
   - Returns: Whether any finding's record changed.
   */
  @discardableResult
  func decide(_ decision: ReviewDecision, for ids: Set<FindingID>? = nil) -> Bool {
    let chosen = chosenFindings(ids)
    let draftID = ids == nil && chosen.count == 1 ? chosen.first?.id : nil
    let changed = record(decision, for: targets(of: decision, among: chosen)) { finding in
      if let record = reviewBook.records[finding.id] { return DecisionDraft(record) }
      return finding.id == draftID ? decisionDrafts[finding.id] ?? DecisionDraft() : DecisionDraft()
    }
    if let draftID, reviewBook.records[draftID] != nil { decisionDrafts[draftID] = nil }
    return changed
  }

  /**
   Records a decision for the selected findings, then selects the next unreviewed finding in
   the order the table shows. It moves on only after deciding one finding on a review page.
   */
  func decideAndAdvance(_ decision: ReviewDecision) {
    let ordered = selectedList.map { orderedFindings(in: $0).map(\.id) } ?? []
    let decided = selectedFindingIDs
    guard decide(decision), decision != .unreviewed, decided.count == 1 else { return }
    if let next = reviewBook.nextUnreviewed(after: decided.first, in: ordered) {
      selectedFindingIDs = [next]
    }
  }

  /**
   Picks a finding's correction option. A finding already approved for correction is approved
   again with the new option, undoably.
   */
  func pick(_ option: CorrectionOptionID, for finding: Finding) {
    pickedCorrections[finding.id] = option
    guard let record = reviewBook.records[finding.id], record.decision == .correction,
      record.correctionOptionID != option
    else { return }
    self.record(
      .correction,
      for: [finding],
      option: { _ in option },
      annotation: { _ in DecisionDraft(record) }
    )
  }

  /// Approves the selected findings for correction, or clears their approval if every one is
  /// already approved.
  func toggleApproval() {
    let approved = selectedFindingIDs.allSatisfy { reviewBook.decision(for: $0) == .correction }
    decide(approved ? .unreviewed : .correction)
  }

  /// Selects the next or previous unreviewed finding in the order the table shows.
  func selectUnreviewed(forward: Bool) {
    guard let list = selectedList else { return }
    let ordered = orderedFindings(in: list).map(\.id)
    let current =
      forward
      ? ordered.last(where: selectedFindingIDs.contains)
      : ordered.first(where: selectedFindingIDs.contains)
    guard let next = reviewBook.nextUnreviewed(after: current, in: ordered, forward: forward)
    else { return }
    selectedFindingIDs = [next]
  }

  /// Saves the decisions to the workspace, after any save already under way.
  func saveReview() {
    guard let workspace, let reviewedAudit else { return }
    let state = ReviewState(audit: reviewedAudit, decisions: reviewBook.orderedRecords)
    let previous = pendingReviewSave
    pendingReviewSave = Task { [weak self] in
      await previous?.value
      do {
        try await workspace.save(state)
      } catch {
        self?.actionError = error
      }
    }
  }

  private func chosenFindings(_ ids: Set<FindingID>?) -> [Finding] {
    (ids ?? selectedFindingIDs).sorted().compactMap { findingsByID[$0] }
  }

  private func targets(of decision: ReviewDecision, among chosen: [Finding]) -> [Finding] {
    guard decision == .correction else { return chosen }
    return chosen.filter { canApprove($0, amongSeveral: chosen.count > 1) }
  }

  /**
   Records a decision for findings, undoably.

   - Parameters:
     - decision: The decision.
     - findings: The findings.
     - option: The correction option to record for each finding; the one it shows by default.
     - annotation: The reason and note to record for each finding.
   - Returns: Whether any finding's record changed.
   */
  @discardableResult
  private func record(
    _ decision: ReviewDecision,
    for findings: [Finding],
    option: ((Finding) -> CorrectionOptionID?)? = nil,
    annotation: (Finding) -> DecisionDraft
  ) -> Bool {
    commitDecisionEdit()
    var previous = [FindingID: ReviewRecord?]()
    for finding in findings {
      let draft = annotation(finding)
      let changed = reviewBook.decide(
        decision,
        for: [finding],
        choosing: decision == .correction
          ? (option?(finding) ?? shownCorrection(of: finding)?.id) : nil,
        reason: draft.reason,
        note: draft.note
      )
      previous.merge(changed) { earlier, _ in earlier }
    }
    let changed = previous.filter { id, record in reviewBook.records[id] != record }
    guard !changed.isEmpty else { return false }
    keepDrafts(ofCleared: changed)
    registerUndo(restoring: changed, actionName: decision.actionName)
    saveReview()
    return true
  }

  /// Keeps the reason and note of records that were cleared as their findings' drafts, so
  /// nothing typed is lost when a finding returns to unreviewed.
  private func keepDrafts(ofCleared previous: [FindingID: ReviewRecord?]) {
    for case let (id, record?) in previous where reviewBook.records[id] == nil {
      let draft = DecisionDraft(record)
      if !draft.isEmpty { decisionDrafts[id] = draft }
    }
  }

  private func registerUndo(restoring previous: [FindingID: ReviewRecord?], actionName: String) {
    undoManager?.registerUndo(withTarget: self) { session in
      session.restore(previous, actionName: actionName)
    }
    undoManager?.setActionName(actionName)
  }

  /// Puts records back, undoably, and selects those of their findings the page lists.
  private func restore(_ records: [FindingID: ReviewRecord?], actionName: String) {
    var replaced = [FindingID: ReviewRecord?]()
    for (id, record) in records { replaced[id] = reviewBook.set(record, for: id) }
    keepDrafts(ofCleared: replaced)
    registerUndo(restoring: replaced, actionName: actionName)
    saveReview()
    let restored = listedFindingIDs.intersection(records.keys)
    if !restored.isEmpty { selectedFindingIDs = restored }
  }
}
