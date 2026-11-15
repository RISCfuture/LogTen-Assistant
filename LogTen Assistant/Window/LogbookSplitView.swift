import Audit
import AuditWorkflow
import LogbookModel
import LogbookStore
import SwiftUI

/// A loaded logbook: the sidebar, the selected page and the inspector.
struct LogbookSplitView: View {
  /// The narrowest the sidebar column gets.
  private static let sidebarMinWidth = 200.0

  /// The sidebar column's width in a new window.
  static let sidebarIdealWidth = 230.0

  /// The narrowest the inspector column gets.
  private static let inspectorMinWidth = 300.0

  /// The inspector column's width in a new window.
  static let inspectorIdealWidth = 300.0

  /// The size of a new logbook window.
  static let defaultWindowSize = CGSize(width: 1280, height: 800)

  /// The narrowest the page column gets.
  private static let detailMinWidth = 420.0

  /// The sum of the columns' minimum widths, the width the opening and error views hold a logbook
  /// window to.
  static let windowMinWidth = sidebarMinWidth + detailMinWidth + inspectorMinWidth

  /// The shortest a logbook window gets.
  static let windowMinHeight = 520.0

  @Bindable var session: LogbookSession

  @Environment(\.undoManager)
  private var undoManager
  @FocusState private var isSearchFocused: Bool

  private var isInspectorShown: Binding<Bool> {
    Binding {
      session.isInspectorPresented && session.pageHasInspector
    } set: { isPresented in
      if session.pageHasInspector { session.isInspectorPresented = isPresented }
    }
  }

  private var searchPrompt: LocalizedStringResource {
    switch session.sidebarSelection {
      case .violations: "Search Flights"
      case .audit(.appliedHistory): "Search Batches"
      case .audit(.dataSources): "Search"
      case .audit, .checks, nil: "Search Findings"
    }
  }

  var body: some View {
    NavigationSplitView {
      LogbookSidebar(session: session)
        .navigationSplitViewColumnWidth(min: Self.sidebarMinWidth, ideal: Self.sidebarIdealWidth)
    } detail: {
      LogbookDetail(session: session)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaBar(edge: .top) { PageBar(session: session) }
        .toolbar { LogbookToolbar(session: session) }
    }
    .frame(minHeight: Self.windowMinHeight)
    .inspector(isPresented: isInspectorShown) {
      LogbookInspector(session: session)
        .inspectorColumnWidth(min: Self.inspectorMinWidth, ideal: Self.inspectorIdealWidth)
    }
    .navigationSubtitle(ActivitySubtitle(session: session).text)
    .searchable(text: $session.searchText, placement: .toolbar, prompt: Text(searchPrompt))
    .searchFocused($isSearchFocused)
    .onChange(of: isSearchFocused) { session.isEditingText = isSearchFocused }
    .onChange(of: session.searchFocusRequests) { isSearchFocused = true }
    .dropDestination(for: URL.self) { files, _ in
      let exports = files.filter(EvidenceLibrary.isImportable)
      guard !exports.isEmpty, session.canStartDataTask else { return false }
      Task { await session.importFlyStoExport(exports) }
      return true
    }
    .sheet(item: $session.logbookSettingsPage, onDismiss: session.focusTable) { _ in
      LogbookSettingsSheet(session: session)
    }
    .sheet(item: $session.presentedSheet, onDismiss: session.focusTable) { sheet in
      SessionSheetView(session: session, sheet: sheet)
    }
    .alert(
      session.actionError?.localizedDescription ?? "",
      isPresented: .init(
        get: { session.actionError != nil },
        set: { if !$0 { session.actionError = nil } }
      )
    ) {
      Button("OK") { session.actionError = nil }
    } message: {
      Text((session.actionError as? NSError)?.localizedFailureReason ?? "")
    }
    .onAppear { session.undoManager = undoManager }
    .onChange(of: undoManager) { session.undoManager = undoManager }
  }
}

/// The window's subtitle: the task, audit or ADS-B download running, or nothing while idle.
private struct ActivitySubtitle {
  let session: LogbookSession

  var text: String {
    session.activity?.title ?? auditing ?? session.adsbDownload.subtitle ?? ""
  }

  private var auditing: String? {
    session.isAuditing ? String(localized: "Auditing…") : nil
  }
}

/// The page the sidebar selected.
struct LogbookDetail: View {
  let session: LogbookSession

  var body: some View {
    switch session.sidebarSelection {
      case .audit(let page):
        AuditPageView(session: session, page: page)
      case .checks(let category):
        ReviewQueueView(
          session: session,
          list: FindingList(queue: .logbookConsistency, category: category)
        )
      case .violations(let rule):
        ViolationsView(session: session, rule: rule)
      case nil:
        NoPageSelectedView(phase: session.phase, fraction: session.loadFraction)
    }
  }
}

/// Shown while no page is selected: the step the audit is on, or else a note that nothing is.
private struct NoPageSelectedView: View {
  let phase: LogbookSession.Phase
  let fraction: Double?

  var body: some View {
    if case .working = phase {
      AuditProgressView(phase: phase, fraction: fraction)
        .accessibilityIdentifier("detailProgress")
    } else {
      ContentUnavailableView("Nothing Selected", systemImage: "sidebar.left")
    }
  }
}

/// The inspector for the selected page, on an opaque background so the table doesn't show
/// through the column.
private struct LogbookInspector: View {
  let session: LogbookSession

  var body: some View {
    Group {
      switch session.sidebarSelection {
        case .violations:
          ViolationInspector(session: session)
        case .audit(.appliedHistory):
          AppliedHistoryInspector(session: session)
        case .audit(.dataSources), nil:
          Color.clear
        case .audit, .checks:
          FindingInspector(session: session)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.windowBackground)
  }
}

/// A sheet for a data-source or apply task.
private struct SessionSheetView: View {
  let session: LogbookSession
  let sheet: SessionSheet

  var body: some View {
    switch sheet {
      case .apply: ApplySheet(session: session)
      case .fetchADSB: FetchADSBSheet(session: session)
      case .uploadLogs: UploadLogsSheet(session: session)
    }
  }
}

#Preview(
  "Review",
  traits: .sampleSession { session in
    PreviewHelper.selectFinding(in: session)
  }
) {
  @Environment(LogbookSession.self)
  @Previewable var session
  WindowPreview { LogbookSplitView(session: session) }
}

#Preview(
  "Data Sources",
  traits: .sampleSession { session in
    session.sidebarSelection = .audit(.dataSources)
  }
) {
  @Environment(LogbookSession.self)
  @Previewable var session
  WindowPreview { LogbookSplitView(session: session) }
}

#Preview(
  "Applied History",
  traits: .sampleSession(PreviewHelper.selectAppliedBatch)
) {
  @Environment(LogbookSession.self)
  @Previewable var session
  WindowPreview { LogbookSplitView(session: session) }
}

#Preview(
  "Update Offer",
  traits: .sampleSession { session in
    session.sidebarSelection = .audit(.logbookConsistency)
    session.staleDataSources = StaleDataSources(isAirportDataStale: true, isFlyStoStale: true)
  }
) {
  @Environment(LogbookSession.self)
  @Previewable var session
  WindowPreview { LogbookSplitView(session: session) }
}

#Preview(
  "Violations",
  traits: .sampleSession { session in
    session.sidebarSelection = .violations(nil)
    session.selectedFlightIDs = [PreviewHelper.flight.id]
  }
) {
  @Environment(LogbookSession.self)
  @Previewable var session
  WindowPreview { LogbookSplitView(session: session) }
}
