import SwiftUI

/**
 The logbook window's frequent commands, each also in a menu.

 Every command is an icon with its title in the help tag and the customization palette. A task's
 button turns into a spinner while that task runs. Apply Fixes… is the one prominent item, and
 only once a fix is approved. The inspector toggle sits in a group of its own.

 Attach it to the detail column rather than the split view: items attached to the split view
 share one group and ignore the spacer between them.
 */
struct LogbookToolbar: ToolbarContent {
  @Bindable var session: LogbookSession

  var body: some ToolbarContent {
    ToolbarItemGroup(placement: .primaryAction) {
      RunAuditButton(session: session)
      SyncFlyStoButton(session: session)
      ApplyFixesButton(session: session)
    }
    ToolbarSpacer(.fixed, placement: .primaryAction)
    ToolbarItem(placement: .primaryAction) {
      InspectorToggle(session: session)
    }
    ToolbarSpacer(.fixed, placement: .primaryAction)
    ToolbarItem(placement: .primaryAction) {
      PageHelpLink(selection: session.sidebarSelection)
    }
  }
}

/// The help button for the page the sidebar selects.
private struct PageHelpLink: View {
  let selection: SidebarItem?

  private var anchor: HelpAnchor {
    switch selection {
      case .audit(.dataSources): .dataSources
      case .audit(.approved): .applyingFixes
      case .audit(.appliedHistory): .revertingABatch
      case .audit(.logbookConsistency), .audit(.aircraftComparisons), .audit(.unmatchedActivity),
        .audit(.groupsAndCurrency), .checks:
        .reviewingFindings
      case .violations: .violations
      case nil: .gettingStarted
    }
  }

  var body: some View {
    HelpTopicLink(anchor: anchor, accessibilityIdentifier: "toolbar.help")
  }
}

/// Runs the audit again, or a spinner while the logbook is being read and audited.
private struct RunAuditButton: View {
  let session: LogbookSession

  var body: some View {
    if session.isAuditing, session.activity == nil {
      TaskSpinner(title: String(localized: "Auditing…"))
    } else {
      Button {
        Task { await session.runAudit() }
      } label: {
        Label("Run Audit", systemImage: "text.page.badge.magnifyingglass")
      }
      .disabled(!session.canRunAudit)
      .help("Run Audit: take a fresh snapshot of the logbook and check it again")
      .accessibilityIdentifier("toolbar.runAudit")
    }
  }
}

/// Syncs FlySto, or a spinner while a sync and the audit after it run.
private struct SyncFlyStoButton: View {
  let session: LogbookSession

  var body: some View {
    if let activity = session.activity, activity.isFlyStoSync {
      TaskSpinner(title: activity.title)
    } else {
      Button {
        Task { await session.syncFlySto() }
      } label: {
        Label("Sync FlySto", image: "flysto.sync")
      }
      .disabled(!session.canStartDataTask)
      .help("Sync FlySto: fetch the FlySto logs added since the last sync")
      .accessibilityIdentifier("toolbar.syncFlySto")
    }
  }
}

/// A small spinner standing in for a toolbar button while its task runs.
private struct TaskSpinner: View {
  let title: String

  var body: some View {
    ProgressView()
      .controlSize(.small)
      .help(title)
      .accessibilityLabel(title)
      .accessibilityIdentifier("toolbar.activity")
  }
}

/// Opens the Apply sheet, prominent only while there are approved fixes to apply.
private struct ApplyFixesButton: View {
  let session: LogbookSession

  private var canApply: Bool {
    !session.approvedCorrections.isEmpty && session.canStartDataTask
  }

  private var button: some View {
    Button {
      session.presentedSheet = .apply
    } label: {
      Label("Apply Fixes…", image: "book.badge.checkmark")
    }
    .disabled(!canApply)
    .help("Apply Fixes: back up the logbook and apply the approved fixes through LogTen")
    .accessibilityIdentifier("toolbar.applyApproved")
  }

  var body: some View {
    if canApply {
      button.buttonStyle(.borderedProminent)
    } else {
      button
    }
  }
}

/// Shows or hides the inspector, unavailable on pages without one.
private struct InspectorToggle: View {
  let session: LogbookSession

  private var title: LocalizedStringResource {
    session.isInspectorPresented ? "Hide Inspector" : "Show Inspector"
  }

  var body: some View {
    Button {
      session.isInspectorPresented.toggle()
    } label: {
      Label(String(localized: title), systemImage: "sidebar.trailing")
    }
    .disabled(!session.pageHasInspector)
    .help(String(localized: title))
    .accessibilityIdentifier("toolbar.inspector")
  }
}
