import AuditWorkflow
import SwiftUI

/// The contents of a logbook window: opens the logbook, then shows it.
struct LogbookWindow: View {
  @Binding var reference: LogbookReference

  @Environment(LogbookLibrary.self)
  private var library
  @State private var session: LogbookSession
  @SceneStorage("SidebarSelection")
  private var storedSidebarSelection: SidebarItem?
  @SceneStorage("InspectorPresented")
  private var storedInspectorPresented = true
  @SceneStorage("AuditScope")
  private var storedAuditScope = AuditScope.all
  @Environment(\.appearsActive)
  private var appearsActive

  var body: some View {
    LogbookPhaseView(session: session)
      .navigationTitle(session.reference.title)
      .focusedSceneValue(\.logbookSession, session)
      .task {
        restoreWindowState()
        OpenLogbooks.shared.activate(session)
        await session.load()
        noteLoaded()
      }
      .onChange(of: appearsActive) {
        guard appearsActive else { return }
        OpenLogbooks.shared.activate(session)
        session.refreshFlyStoAccount()
      }
      .onDisappear { session.commitDecisionEdit() }
      .onChange(of: session.reference.displayName) { noteLoaded() }
      .onChange(of: session.sidebarSelection) { storedSidebarSelection = session.sidebarSelection }
      .onChange(of: session.isInspectorPresented) {
        storedInspectorPresented = session.isInspectorPresented
      }
      .onChange(of: session.auditScope) { storedAuditScope = session.auditScope }
  }

  /// Creates the window's contents for a logbook.
  init(reference: Binding<LogbookReference>) {
    _reference = reference
    _session = State(initialValue: LogbookSession(reference: reference.wrappedValue))
  }

  private func restoreWindowState() {
    session.sidebarSelection = storedSidebarSelection ?? session.sidebarSelection
    session.isInspectorPresented = storedInspectorPresented
    session.auditScope = storedAuditScope
  }

  private func noteLoaded() {
    guard session.logbook != nil else { return }
    reference = session.reference
    library.noteOpened(session.reference)
  }
}

/// Shows a logbook session according to how far opening it has got.
private struct LogbookPhaseView: View {
  let session: LogbookSession

  var body: some View {
    switch session.phase {
      case .failed(let error):
        LogbookErrorView(error: error) {
          Task { await session.load() }
        }
      case .idle,
        .working where session.logbook == nil:
        LogbookProgressView(phase: session.phase, fraction: session.loadFraction)
      default:
        LogbookSplitView(session: session)
    }
  }
}

/// Shown while a logbook is first being read.
private struct LogbookProgressView: View {
  let phase: LogbookSession.Phase
  var fraction: Double?

  var body: some View {
    AuditProgressView(
      phase: phase,
      fraction: fraction,
      fallbackTitle: String(localized: "Opening…")
    )
    .frame(
      minWidth: LogbookSplitView.windowMinWidth,
      maxWidth: .infinity,
      minHeight: LogbookSplitView.windowMinHeight,
      maxHeight: .infinity
    )
    .accessibilityIdentifier("logbookProgress")
  }
}

/// Shown when a logbook couldn't be opened.
private struct LogbookErrorView: View {
  let error: any Error
  let retry: () -> Void

  private var details: String {
    let error = error as NSError
    return [error.localizedFailureReason, error.localizedRecoverySuggestion]
      .compactMap(\.self).joined(separator: " ")
  }

  var body: some View {
    ContentUnavailableView {
      Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
    } description: {
      Text(details)
    } actions: {
      Button("Try Again", action: retry)
        .accessibilityIdentifier("retryOpenButton")
    }
    .frame(
      minWidth: LogbookSplitView.windowMinWidth,
      minHeight: LogbookSplitView.windowMinHeight
    )
  }
}

#Preview("Opening") {
  WindowPreview {
    LogbookProgressView(phase: .working(.snapshotting))
  }
}

#Preview("Failed") {
  WindowPreview {
    LogbookErrorView(error: LogbookOpeningError.unknownFixture("missing")) {}
  }
}
