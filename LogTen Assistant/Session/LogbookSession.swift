import AuditWorkflow
import Corrections
import FlightSources
import Foundation
import LogbookModel
import LogbookStore
import Observation
import References
import Regulations
import Review
import Workspace

/// The state of one logbook window: the logbook's records, its settings, the results of
/// checking it and reviewing its findings, plus what the window is showing.
///
/// Each logbook window owns a session. Menu commands reach the key window's session through
/// `FocusedValues.logbookSession`.
@Observable
final class LogbookSession {
  /// The logbook the window shows.
  private(set) var reference: LogbookReference

  /// Where opening or refreshing the logbook is.
  var phase = Phase.idle {
    didSet { loadFraction = nil }
  }

  /// How much of the current step is done, from 0 to 1, or `nil` if the step has no known size.
  var loadFraction: Double?

  /// The logbook's records, once read.
  private(set) var logbook: Logbook?

  /// The logbook's settings.
  private(set) var settings = LogbookSettings()

  /// The result of checking the logbook against the regulations.
  private(set) var regulationReport: RegulationReport?

  /// The snapshot the records were read from.
  private(set) var snapshot: LogbookSnapshot?

  /// The logbook's workspace, which keeps its settings, evidence, decisions and journal.
  private(set) var workspace: Workspace?

  /// An error from an action the user took, to show in an alert.
  var actionError: (any Error)?

  // MARK: Audit & Fix

  /// The latest Audit & Fix run.
  var auditRun: AuditRun?

  /// The run's identity and record fingerprints, which decisions are made against.
  var reviewedAudit: ReviewedAudit?

  /// The user's decisions about the run's findings.
  var reviewBook = ReviewBook()

  /// What happened to the previous run's decisions when they were carried to this one.
  var carryForward: CarryForwardResult?

  /// Where FlySto syncing and importing stand.
  var flyStoState = FlyStoSyncState()

  /// How many FlySto records are saved for the logbook.
  var flyStoRecordCount = 0

  /// The ADS-B traces downloaded for the logbook's aircraft.
  var adsbTraces = [ADSBProvenance]()

  /// The effective date of the newest downloaded NASR cycle.
  var airportCycle: Date?

  /// Whether the FAA's CIFP approach data has been downloaded.
  var hasApproachData = false

  /// The effective date of the downloaded CIFP cycle, or `nil` if none was downloaded.
  var approachCycle: Date?

  /// The data-source task running, if any.
  var activity: Activity?

  /// What the last data-source task did, for the Data Sources page.
  var dataSourceStatus: String?

  /// The data-source task running, so Stop can cancel it.
  var dataTask: Task<String, any Error>?

  /// The ADS-B download, which runs alongside the other data-source tasks.
  @ObservationIgnored let adsbDownload: ADSBDownloadJob

  /// Whether evidence was saved while another task was running, so the evidence is reread and
  /// audited again once it finishes.
  @ObservationIgnored var needsEvidenceReload = false

  /// Whether the Keychain holds a FlySto API token.
  var hasFlyStoToken = false

  /// The out-of-date data sources the window offers to update, or `nil` when it isn't offering.
  var staleDataSources: StaleDataSources?

  /// Whether the window has checked for out-of-date data sources, which it does once.
  @ObservationIgnored var hasCheckedDataSources = false

  /// The batches delivered to the logbook.
  var journal: ApplyJournal?

  // MARK: Window state

  /// What the sidebar has selected. Changing to another page deselects every finding, so the
  /// new page starts with nothing selected. Until the user or the restored window state picks
  /// a page, the first audit picks one with ``selectInitialPageIfNeeded()``.
  var sidebarSelection: SidebarItem? {
    didSet {
      if sidebarSelection != oldValue { selectedFindingIDs.removeAll() }
    }
  }

  /// The flights selected in the Violations table.
  var selectedFlightIDs = Set<RecordID>()

  /// The findings selected in a review table.
  var selectedFindingIDs = Set<FindingID>()

  /// How far back the review pages reach, by the dates of the findings' flights. Narrowing it
  /// deselects the findings it hides.
  var auditScope = AuditScope.all {
    didSet { deselectUnlistedFindings() }
  }

  /// The correction option picked in the inspector for each finding with several, until a
  /// decision records one.
  var pickedCorrections = [FindingID: CorrectionOptionID]()

  /// The reason and note typed for each unreviewed finding, until a decision records them.
  var decisionDrafts = [FindingID: DecisionDraft]()

  /// The order the review tables sort findings in, which Next Unreviewed and deciding walk.
  var findingSortOrder = [KeyPathComparator(\FindingRow.date, order: .reverse)]

  /// The Applied History entry selected.
  var selectedJournalEntryID: ApplyJournalEntry.ID?

  /// The Applied History entry the user asked to revert, while the confirmation shows.
  var revertingEntryID: ApplyJournalEntry.ID?

  /// Whether the inspector is showing.
  var isInspectorPresented = true

  /// The page the Logbook Settings sheet opens on, or `nil` when the sheet isn't showing.
  var logbookSettingsPage: LogbookSettingsPage? {
    didSet { if logbookSettingsPage == nil { spotlitSettings = [] } }
  }

  /// The settings the Logbook Settings sheet points out when it opens, because changing them
  /// lets a rule the user asked about run.
  var spotlitSettings = [SettingsTarget]()

  /// The sheet the window is showing for a data-source or apply task.
  var presentedSheet: SessionSheet?

  /// The text in the window's search field. Typing deselects the findings it hides.
  var searchText = "" {
    didSet { deselectUnlistedFindings() }
  }

  /// Incremented to ask the window to focus its search field.
  private(set) var searchFocusRequests = 0

  /// Incremented to ask the page's findings table to take focus.
  private(set) var tableFocusRequests = 0

  /// The window's undo manager, which review decisions register with.
  @ObservationIgnored weak var undoManager: UndoManager?

  /// The services data-source tasks go through.
  @ObservationIgnored let services: SessionServices

  @ObservationIgnored let loader: LogbookLoader
  @ObservationIgnored private var flightsByID = [RecordID: Flight]()
  @ObservationIgnored var findingsByID = [FindingID: Finding]()
  @ObservationIgnored var approachLibrary: CIFPApproachLibrary?
  @ObservationIgnored var pendingReviewSave: Task<Void, Never>?
  @ObservationIgnored var editedNoteOrigins = [FindingID: ReviewRecord]()

  /// Whether a text field has keyboard focus, so menu shortcuts that text editing also uses
  /// (such as ⌘⌫) leave the key press to the field.
  var isEditingText = false

  /// Whether the Apply sheet is delivering batches, during which the logbook must not reload.
  var isApplying = false

  /// Whether Run Audit is snapshotting, checking and auditing the logbook.
  var isRunningAudit = false

  /// Whether results are being computed, so pages show progress instead of an empty state.
  var isAuditing: Bool {
    if isRunningAudit { return true }
    if case .working = phase { return true }
    return false
  }

  /// Whether a refresh can start: the logbook is loaded and nothing else is running.
  var canRunAudit: Bool {
    guard activity == nil, !isApplying, case .loaded = phase else { return false }
    return true
  }

  /// Whether the session shows the built-in sample logbook rather than one read from disk.
  var isFixture: Bool { !reference.isBookmarked }

  /// Whether the window is showing a sheet or a confirmation, during which the logbook
  /// commands don't apply.
  var isPresentingModal: Bool {
    presentedSheet != nil || logbookSettingsPage != nil || revertingEntryID != nil
  }

  /// Whether the sidebar's page has an inspector to show.
  var pageHasInspector: Bool { sidebarSelection != .audit(.dataSources) }

  /// Creates a session for a logbook; call ``load()`` to read it.
  init(
    reference: LogbookReference,
    loader: LogbookLoader = .init(),
    services: SessionServices = .current
  ) {
    self.reference = reference
    self.loader = loader
    self.services = services
    adsbDownload = ADSBDownloadJob(client: services.adsb, cache: services.adsbCache)
    adsbDownload.tracesDidSave = { [weak self] in await self?.reloadEvidenceWhenIdle() }
  }

  /**
   Creates a session showing what another session loaded, with its own window state: nothing
   selected, no sheet presented and no task running. It shares the other session's workspace.

   SwiftUI previews use it to give each preview its own copy of a logbook loaded once.
   */
  convenience init(copying loaded: LogbookSession) {
    self.init(reference: loaded.reference, loader: loaded.loader, services: loaded.services)
    phase = loaded.phase
    logbook = loaded.logbook
    flightsByID = loaded.flightsByID
    settings = loaded.settings
    regulationReport = loaded.regulationReport
    snapshot = loaded.snapshot
    workspace = loaded.workspace
    auditRun = loaded.auditRun
    reviewedAudit = loaded.reviewedAudit
    reviewBook = loaded.reviewBook
    carryForward = loaded.carryForward
    findingsByID = loaded.findingsByID
    approachLibrary = loaded.approachLibrary
    flyStoState = loaded.flyStoState
    flyStoRecordCount = loaded.flyStoRecordCount
    adsbTraces = loaded.adsbTraces
    airportCycle = loaded.airportCycle
    hasApproachData = loaded.hasApproachData
    approachCycle = loaded.approachCycle
    hasFlyStoToken = loaded.hasFlyStoToken
    staleDataSources = loaded.staleDataSources
    hasCheckedDataSources = loaded.hasCheckedDataSources
    journal = loaded.journal
    sidebarSelection = loaded.sidebarSelection
  }

  /// The flight with an identifier, if it is in the logbook.
  func flight(_ id: RecordID) -> Flight? { flightsByID[id] }

  /// The finding with an identifier, if the latest run produced it.
  func finding(_ id: FindingID) -> Finding? { findingsByID[id] }

  /// Asks the window to focus its search field.
  func focusSearch() { searchFocusRequests += 1 }

  /// Asks the page's findings table to take focus.
  func focusTable() { tableFocusRequests += 1 }

  isolated deinit {
    adsbDownload.stop()
  }

  /// Where opening or refreshing a logbook is.
  enum Phase {
    /// Nothing has been read yet.
    case idle
    /// The logbook is being read or checked.
    case working(LoadStep)
    /// The logbook is read and checked.
    case loaded
    /// Opening the logbook failed.
    case failed(any Error)
  }
}

/// A sheet a logbook window shows for a longer task.
enum SessionSheet: String, Identifiable {
  /// Applying approved fixes.
  case apply
  /// Downloading ADS-B traces.
  case fetchADSB
  /// Uploading data logs to FlySto.
  case uploadLogs

  var id: String { rawValue }
}

// MARK: - Loading

extension LogbookSession {
  private static let fixtureWorkspaceFolder = "LogTenAssistantFixtures"

  /// Settings for a logbook that has none saved: custom fields mapped by their titles and the
  /// owner taken from LogTen's “me” person.
  private static func suggestedSettings(for logbook: Logbook) -> LogbookSettings {
    var settings = LogbookSettings(fieldMapping: .suggested(for: logbook.customFields))
    settings.pilot.ownerPersonID = logbook.people.first(where: \.isMe)?.id
    return settings
  }

  /// The name to show for a logbook: its owner's, from the settings or else LogTen's “me”
  /// person, otherwise a generic name.
  static func displayName(of logbook: Logbook, settings: LogbookSettings) -> String {
    let owner =
      settings.pilot.ownerPersonID.flatMap { id in logbook.people.first { $0.id == id } }
      ?? logbook.people.first(where: \.isMe)
    guard let owner else { return LogbookReference.genericName }
    return String(localized: "\(owner.name)’s Logbook")
  }

  /// Snapshots and reads the logbook, checks it against the regulations, and audits it. After the
  /// first load, notes which data sources are out of date.
  func load() async {
    phase = .working(.snapshotting)
    do {
      switch reference.source {
        case .bookmark: try await loadFromDisk()
        case .fixture(let name):
          try await Task.sleep(for: LaunchEnvironment.fixtureLoadDelay)
          try loadFixture(named: name)
      }
      await evaluateRegulations()
      await evidenceDidChange()
      checkDataSourcesOnce()
    } catch is CancellationError {
      phase = .idle
    } catch {
      phase = .failed(error)
    }
  }

  /// Takes a fresh snapshot of the logbook and checks and audits it again. The previous results
  /// are cleared first, so no page shows stale findings while the audit runs.
  func runAudit() async {
    guard canRunAudit else { return }
    isRunningAudit = true
    defer { isRunningAudit = false }
    clearResults()
    await load()
  }

  /**
   Reads the logbook as it is now, from a fresh snapshot, without changing what the window
   shows.

   The sample logbook is returned as built, since nothing can change it.
   */
  func freshLogbook() async throws -> Logbook {
    switch reference.source {
      case .bookmark:
        return try await loader.load(reference, protecting: snapshot) { _, _ in }.logbook
      case .fixture(let name):
        guard let fixture = SampleLogbook(named: name) else {
          throw LogbookOpeningError.unknownFixture(name)
        }
        return fixture.logbook
    }
  }

  private func clearResults() {
    regulationReport = nil
    auditRun = nil
    reviewedAudit = nil
    findingsByID = [:]
  }

  private func loadFromDisk() async throws {
    let loaded = try await loader.load(reference) { [weak self] step, fraction in
      self?.phase = .working(step)
      self?.loadFraction = fraction
    }
    if let bookmark = loaded.refreshedBookmark {
      reference = reference.replacingBookmark(bookmark)
    }
    workspace = loaded.workspace
    snapshot = loaded.snapshot
    install(loaded.logbook, settings: loaded.settings)
  }

  private func loadFixture(named name: String) throws {
    guard let fixture = SampleLogbook(named: name) else {
      throw LogbookOpeningError.unknownFixture(name)
    }
    if workspace == nil {
      workspace = try Workspace(
        directory: FileManager.default.temporaryDirectory
          .appending(path: Self.fixtureWorkspaceFolder, directoryHint: .isDirectory)
          .appending(path: UUID().uuidString, directoryHint: .isDirectory)
      )
    }
    install(fixture.logbook, settings: fixture.settings)
  }

  private func install(_ logbook: Logbook, settings: LogbookSettings) {
    self.logbook = logbook
    flightsByID = Dictionary(logbook.flights.map { ($0.id, $0) }) { first, _ in first }
    self.settings = settings == LogbookSettings() ? Self.suggestedSettings(for: logbook) : settings
    selectedFlightIDs.formIntersection(flightsByID.keys)
    reference.displayName = Self.displayName(of: logbook, settings: self.settings)
    reference.storeUUID = logbook.identity.storeUUID
  }

  private func evaluateRegulations() async {
    guard let logbook else { return }
    phase = .working(.checkingRegulations)
    do {
      let engine = RegulationEngine(settings: settings)
      regulationReport = try await withFractionReports(
        deliveredTo: { [weak self] in self?.loadFraction = $0 },
        body: { try await engine.evaluate(logbook.flights, progress: $0) }
      )
      phase = .loaded
    } catch is CancellationError {
      phase = .loaded
    } catch {
      phase = .failed(error)
    }
  }
}

// MARK: - Settings

extension LogbookSession {
  /// The people in the logbook, sorted by name.
  var people: [Person] {
    (logbook?.people ?? []).sorted {
      $0.name.localizedStandardCompare($1.name) == .orderedAscending
    }
  }

  /// The registrations of the logbook's aircraft, sorted.
  var registrations: [String] {
    Set((logbook?.aircraft ?? []).map(\.registration)).sorted()
  }

  /// Saves new settings for the logbook, then checks and audits it again with them.
  func apply(_ newSettings: LogbookSettings) async {
    settings = newSettings
    if let logbook { reference.displayName = Self.displayName(of: logbook, settings: newSettings) }
    do {
      try await workspace?.save(newSettings)
    } catch {
      actionError = error
    }
    await evaluateRegulations()
    await runWorkflowAudit()
    if needsEvidenceReload { await evidenceDidChange() }
  }
}
