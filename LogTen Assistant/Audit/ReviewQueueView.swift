import Audit
import AuditWorkflow
import LogbookModel
import SwiftUI

/// A review page: a queue's findings, or one category of its checks, in a table, with how
/// many are left to review.
struct ReviewQueueView: View {
  @Bindable var session: LogbookSession
  let list: FindingList

  private var rows: [FindingRow] {
    FindingRow.rows(
      for: session.findings(in: list),
      book: session.reviewBook,
      picked: session.pickedCorrections,
      customFields: session.logbook?.customFields ?? [],
      flight: session.flight,
      segment: { session.auditRun?.segment(for: $0) }
    )
  }

  var body: some View {
    let rows = rows
    if rows.isEmpty {
      EmptyQueueView(session: session, queue: list.queue)
    } else if list.queue == .groupsAndCurrency {
      GroupFindingsTable(
        rows: rows,
        selection: $session.selectedFindingIDs,
        session: session,
        kind: list.identifier
      )
    } else {
      FindingsTable(
        rows: rows,
        timeZone: session.settings.pilot.homeTimeZone,
        selection: $session.selectedFindingIDs,
        session: session,
        kind: list.identifier
      )
    }
  }
}

/// Shown in place of an empty queue: the audit running, a search with no matches, or why
/// there is nothing to review.
private struct EmptyQueueView: View {
  @Bindable var session: LogbookSession
  let queue: ReviewQueue

  private var needsEvidence: Bool {
    [.aircraftComparisons, .unmatchedActivity].contains(queue)
  }

  private var auditHasNotRun: Bool {
    if case .loaded = session.phase { session.auditRun == nil } else { false }
  }

  var body: some View {
    if session.isAuditing {
      AuditProgressView(phase: session.phase, fraction: session.loadFraction)
    } else if !session.searchText.isEmpty {
      ContentUnavailableView.search
    } else if auditHasNotRun {
      AuditNotRunView(session: session)
    } else if needsEvidence {
      NoEvidenceView(session: session)
    } else if session.auditScope != .all {
      ScopedQueueView(session: session)
    } else {
      ContentUnavailableView(
        "Nothing to Review",
        systemImage: "checkmark.seal",
        description: Text("Every check passed.")
      )
    }
  }
}

/// Offers to run the audit that hasn't run yet.
private struct AuditNotRunView: View {
  let session: LogbookSession

  var body: some View {
    ContentUnavailableView {
      Label("Audit Not Run", systemImage: "text.page.badge.magnifyingglass")
    } description: {
      Text("Run an audit to check this logbook.")
    } actions: {
      Button("Run Audit") { Task { await session.runAudit() } }
        .disabled(!session.canRunAudit)
        .accessibilityIdentifier("emptyQueue.runAudit")
    }
  }
}

/// Explains that a comparison queue needs evidence, and offers Data Sources.
private struct NoEvidenceView: View {
  let session: LogbookSession

  var body: some View {
    ContentUnavailableView {
      Label("Nothing to Review", systemImage: "checkmark.seal")
    } description: {
      Text(
        "Sync FlySto or fetch ADS-B data to compare entries with what the aircraft recorded."
      )
    } actions: {
      Button("Show Data Sources") { session.sidebarSelection = .audit(.dataSources) }
        .accessibilityIdentifier("emptyQueue.dataSources")
    }
  }
}

/// Explains that a recent scope has no findings, and offers all flights.
private struct ScopedQueueView: View {
  @Bindable var session: LogbookSession

  private var description: LocalizedStringKey {
    switch session.auditScope {
      case .last90Days: "No findings on flights from the last 90 days."
      case .thisYear: "No findings on flights from this year."
      case .all: "Every check passed."
    }
  }

  var body: some View {
    ContentUnavailableView {
      Label("Nothing to Review", systemImage: "checkmark.seal")
    } description: {
      Text(description)
    } actions: {
      Button("Show All Flights") { session.auditScope = .all }
        .accessibilityIdentifier("emptyQueue.showAllFlights")
    }
  }
}

#Preview(
  "Logbook Consistency",
  traits: .sampleSession { $0.sidebarSelection = .audit(.logbookConsistency) }
) {
  @Environment(LogbookSession.self)
  @Previewable var session
  PageColumnPreview(session: session)
}

#Preview(
  "Nothing to Review",
  traits: .sampleSession { $0.sidebarSelection = .audit(.groupsAndCurrency) }
) {
  @Environment(LogbookSession.self)
  @Previewable var session
  PageColumnPreview(session: session)
}

#Preview("Times Checks", traits: .sampleSession { $0.sidebarSelection = .checks(.times) }) {
  @Environment(LogbookSession.self)
  @Previewable var session
  PageColumnPreview(session: session)
}

#Preview(
  "No Matches",
  traits: .sampleSession { session in
    session.sidebarSelection = .audit(.logbookConsistency)
    session.searchText = "ZZZZ"
  }
) {
  @Environment(LogbookSession.self)
  @Previewable var session
  PageColumnPreview(session: session)
}
