import AppKit
import Audit
import AuditWorkflow
import Corrections
import LogbookStore
import Review
import SwiftUI
import Workspace

/// The app's menus, the primary way to reach its commands. Logbook commands act on the key
/// logbook window's session, and are disabled rather than hidden when they don't apply.
struct LogbookCommands: Commands {
  let library: LogbookLibrary

  @FocusedValue(\.logbookSession)
  private var session
  @Environment(\.openWindow)
  private var openWindow
  @Environment(\.dismissWindow)
  private var dismissWindow

  private var opener: LogbookOpener {
    LogbookOpener(library: library, openWindow: openWindow, dismissWindow: dismissWindow)
  }

  var body: some Commands {
    CommandGroup(replacing: .newItem) {
      FileOpenCommands(library: library, opener: opener)
    }
    CommandGroup(replacing: .importExport) {
      FileTransferCommands(session: session)
    }
    CommandGroup(after: .textEditing) {
      Button("Find…") { session?.focusSearch() }
        .keyboardShortcut("f")
        .disabled(session?.isPresentingModal != false)
    }
    SidebarCommands()
    ToolbarCommands()
    CommandGroup(after: .sidebar) {
      ViewCommands(session: session)
    }
    CommandMenu("Audit") {
      AuditCommands(session: session)
    }
    CommandMenu("Review") {
      ReviewCommands(session: session)
    }
    CommandMenu("Apply") {
      ApplyCommands(session: session)
    }
  }
}

/// File ▸ Open commands and Open Recent.
private struct FileOpenCommands: View {
  let library: LogbookLibrary
  let opener: LogbookOpener

  var body: some View {
    Button("Open Logbook…") { opener(.chooseFolder(startingAt: nil)) }
      .keyboardShortcut("o")
    Button("Open Default LogTen Logbook…") {
      opener(.chooseFolder(startingAt: LogbookLocation.defaultGroupContainerURL))
    }
    .keyboardShortcut("o", modifiers: [.command, .shift])
    Menu("Open Recent") {
      ForEach(library.recents) { reference in
        Button(reference.title) { opener(.reference(reference)) }
      }
      Divider()
      Button("Clear Menu") { library.clearRecents() }
        .disabled(library.recents.isEmpty)
    }
  }
}

/// File ▸ import and export commands.
private struct FileTransferCommands: View {
  let session: LogbookSession?

  var body: some View {
    Button("Import FlySto Export…") {
      guard let session else { return }
      let files = FilePanels.chooseFlyStoExports()
      Task { await session.importFlyStoExport(files) }
    }
    .disabled(session?.canStartCommand != true)
    Divider()
    Menu("Export Findings") {
      ForEach(FindingExportFormat.allCases, id: \.self) { format in
        Button("\(format.title)…") { session?.exportFindings(as: format) }
      }
    }
    .disabled(session?.canExportCommand != true)
    Button("Export Review Decisions…") { session?.exportReviewDecisions() }
      .disabled(session?.canExportCommand != true)
  }
}

/// View menu commands for the logbook window, which don't apply while it shows a sheet.
private struct ViewCommands: View {
  let session: LogbookSession?

  private var isWindowAvailable: Bool { session?.isPresentingModal == false }

  private var scope: Binding<AuditScope> {
    Binding {
      session?.auditScope ?? .all
    } set: { scope in
      session?.auditScope = scope
    }
  }

  var body: some View {
    Button(session?.isInspectorPresented == true ? "Hide Inspector" : "Show Inspector") {
      session?.isInspectorPresented.toggle()
    }
    .keyboardShortcut("i", modifiers: [.command, .option])
    .disabled(!isWindowAvailable || session?.pageHasInspector != true)
    Divider()
    ForEach(Array(SidebarItem.pages.enumerated()), id: \.element) { index, item in
      Button(item.menuTitle) { session?.sidebarSelection = item }
        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))))
        .disabled(!isWindowAvailable)
    }
    Divider()
    Menu("Scope") {
      Picker("Scope", selection: scope) {
        ForEach(AuditScope.allCases, id: \.self) { Text($0.title).tag($0) }
      }
      .pickerStyle(.inline)
      .labelsHidden()
    }
    .disabled(!isWindowAvailable || session?.selectedList == nil)
  }
}

/// The Audit menu.
private struct AuditCommands: View {
  let session: LogbookSession?

  private var canStart: Bool { session?.canStartCommand == true }

  var body: some View {
    Button("Run Audit") {
      guard let session else { return }
      Task { await session.runAudit() }
    }
    .keyboardShortcut("r")
    .disabled(session?.canRunCommand != true)
    Button("Sync FlySto") {
      guard let session else { return }
      Task { await session.syncFlySto() }
    }
    .keyboardShortcut("r", modifiers: [.command, .shift])
    .disabled(!canStart)
    Button("Fetch ADS-B Data…") { session?.presentedSheet = .fetchADSB }
      .disabled(session?.canFetchADSBCommand != true)
    Button("Upload Data Logs to FlySto…") { session?.presentedSheet = .uploadLogs }
      .disabled(!canStart)
    Button("Update NASR Data") {
      guard let session else { return }
      Task { await session.updateNASR() }
    }
    .disabled(!canStart)
    Button("Update Approach Data") {
      guard let session else { return }
      Task { await session.updateApproachData() }
    }
    .disabled(!canStart)
    Button("Stop") { session?.stopDataTask() }
      .keyboardShortcut(".")
      .disabled(session?.canStopCommand != true)
    Divider()
    Button("Logbook Settings…") { session?.logbookSettingsPage = .pilot }
      .keyboardShortcut(",", modifiers: [.command, .option])
      .disabled(session?.logbook == nil || session?.isPresentingModal != false)
  }
}

/// The Review menu, for decisions on audit findings.
private struct ReviewCommands: View {
  let session: LogbookSession?

  private var canDecide: Bool { session?.canDecideCommand == true }
  private var canKeep: Bool { canDecide && session?.isEditingText != true }
  private var canMarkForCorrection: Bool {
    canDecide && session?.canMarkForCorrection == true
  }
  private var canNavigate: Bool {
    session?.selectedList != nil && session?.isPresentingModal == false
  }

  var body: some View {
    Button("Mark for Correction") { session?.decideAndAdvance(.correction) }
      .keyboardShortcut(.return)
      .disabled(!canMarkForCorrection)
    Button("Keep as Logged") { session?.decideAndAdvance(.falsePositive) }
      .keyboardShortcut(.delete)
      .disabled(!canKeep)
    Button("Needs More Evidence") { session?.decideAndAdvance(.needsEvidence) }
      .keyboardShortcut("e")
      .disabled(!canKeep)
    Button("Reset Decision") { session?.decideAndAdvance(.unreviewed) }
      .disabled(!canDecide)
    Divider()
    Button("Next Unreviewed") { session?.selectUnreviewed(forward: true) }
      .keyboardShortcut("]")
      .disabled(!canNavigate)
    Button("Previous Unreviewed") { session?.selectUnreviewed(forward: false) }
      .keyboardShortcut("[")
      .disabled(!canNavigate)
  }
}

/// The Apply menu, for backing up the logbook and applying approved fixes.
private struct ApplyCommands: View {
  let session: LogbookSession?

  private var canStart: Bool { session?.canStartCommand == true }

  private var backupsDirectory: URL? {
    guard session?.isPresentingModal == false,
      let directory = session?.workspace?.backupsDirectory,
      FileManager.default.fileExists(atPath: directory.path(percentEncoded: false))
    else { return nil }
    return directory
  }

  var body: some View {
    Button("Apply Fixes…") { session?.presentedSheet = .apply }
      .keyboardShortcut("a", modifiers: [.command, .shift])
      .disabled(!canStart || session?.approvedCorrections.isEmpty != false)
    Button("Back Up Logbook") {
      guard let session else { return }
      Task { await session.backUpLogbook() }
    }
    .disabled(!canStart)
    Divider()
    Button("Show Backups in Finder") {
      guard let backupsDirectory else { return }
      NSWorkspace.shared.activateFileViewerSelecting([backupsDirectory])
    }
    .disabled(backupsDirectory == nil)
    Button("Revert Batch…") { session?.revertingEntryID = session?.revertableEntryID }
      .disabled(session?.revertableEntryID == nil || session?.isPresentingModal != false)
  }
}

extension SidebarItem {
  /// The page's name in the View menu.
  fileprivate var menuTitle: String {
    switch self {
      case .audit(let page): page.title
      case .checks(let category): category.title
      case .violations: String(localized: "Violations")
    }
  }
}

extension LogbookSession {
  /// Whether a data-source task can start and no sheet is up.
  fileprivate var canStartCommand: Bool { canStartDataTask && !isPresentingModal }

  /// Whether a fresh audit can start and no sheet is up.
  fileprivate var canRunCommand: Bool { canRunAudit && !isPresentingModal }

  /// Whether an ADS-B download can be set up and no sheet is up.
  fileprivate var canFetchADSBCommand: Bool { canFetchADSB && !isPresentingModal }

  /// Whether a data-source task or the ADS-B download is running and no sheet is up.
  fileprivate var canStopCommand: Bool { canStopDataTask && !isPresentingModal }

  /// Whether findings can be exported and no sheet is up.
  fileprivate var canExportCommand: Bool { canExport && !isPresentingModal }

  /// Whether review commands apply and no sheet is up.
  fileprivate var canDecideCommand: Bool { canDecide && !isPresentingModal }

  /// The Applied History entry that is selected and can be reverted, if any.
  fileprivate var revertableEntryID: ApplyJournalEntry.ID? {
    guard sidebarSelection == .audit(.appliedHistory), let selectedJournalEntryID,
      let entry = journal?.entries.first(where: { $0.id == selectedJournalEntryID }),
      canRevert(entry)
    else { return nil }
    return entry.id
  }
}
