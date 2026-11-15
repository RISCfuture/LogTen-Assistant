import LogbookModel
import Regulations
import SwiftUI

/// The Violations content for a sidebar entry: the table of flights, or why there's nothing to
/// show.
struct ViolationsView: View {
  @Bindable var session: LogbookSession

  /// The rule to show, or `nil` for every rule.
  let rule: RegulationRule?

  private var remedy: RuleRemedy? {
    rule.flatMap { session.regulationReport?.remedy(for: $0) }
  }

  private var rows: [ViolationRow] {
    guard let report = session.regulationReport else { return [] }
    return ViolationRow.rows(
      in: report,
      for: rule,
      flight: session.flight,
      matching: session.searchText,
      in: session.settings.pilot.homeTimeZone
    )
  }

  var body: some View {
    if let remedy {
      RuleNotCheckedView(remedy: remedy) { session.showSettings(for: remedy) }
    } else {
      ViolationsList(session: session, rows: rows)
    }
  }
}

/// Why a rule found nothing because it didn't run, with the button that opens the setting that
/// lets it run.
private struct RuleNotCheckedView: View {
  let remedy: RuleRemedy
  let showSettings: () -> Void

  var body: some View {
    ContentUnavailableView {
      Label("Not Checked", systemImage: "exclamationmark.magnifyingglass")
    } description: {
      Text(remedy.description)
    } actions: {
      Button(remedy.actionTitle, action: showSettings)
        .accessibilityIdentifier("ruleNotRunSettingsButton")
    }
  }
}

/// The violations' table, or in its place a note that there are none.
private struct ViolationsList: View {
  @Bindable var session: LogbookSession
  let rows: [ViolationRow]

  var body: some View {
    if rows.isEmpty, session.isAuditing {
      AuditProgressView(phase: session.phase, fraction: session.loadFraction)
    } else if rows.isEmpty {
      NoViolationsView(isSearching: !session.searchText.isEmpty)
    } else {
      ViolationsTable(
        rows: rows,
        timeZone: session.settings.pilot.homeTimeZone,
        selection: $session.selectedFlightIDs
      ) {
        session.isInspectorPresented = true
      }
    }
  }
}

/// Shown in place of an empty table.
private struct NoViolationsView: View {
  let isSearching: Bool

  var body: some View {
    if isSearching {
      ContentUnavailableView.search
    } else {
      ContentUnavailableView(
        "No Violations",
        systemImage: "checkmark.seal",
        description: Text("No flight appears to break the regulations checked.")
      )
    }
  }
}

#Preview("All Violations", traits: .sampleSession { $0.sidebarSelection = .violations(nil) }) {
  @Environment(LogbookSession.self)
  @Previewable var session
  PageColumnPreview(session: session)
}

#Preview(
  "No Violations",
  traits: .sampleSession { session in
    let report = session.regulationReport
    session.sidebarSelection = .violations(
      RegulationRule.allCases.first { rule in
        report?.statuses[rule]?.isEvaluated == true && report?.violations(of: rule).isEmpty == true
      }
    )
  }
) {
  @Environment(LogbookSession.self)
  @Previewable var session
  PageColumnPreview(session: session)
}

#Preview(
  "No Matches",
  traits: .sampleSession { session in
    session.sidebarSelection = .violations(nil)
    session.searchText = "ZZZZ"
  }
) {
  @Environment(LogbookSession.self)
  @Previewable var session
  PageColumnPreview(session: session)
}

#Preview(
  "Missing Fields",
  traits: .sampleSession { $0.sidebarSelection = .violations(.noNVGCurrency) }
) {
  @Environment(LogbookSession.self)
  @Previewable var session
  PageColumnPreview(session: session)
}

#Preview(
  "Pilot Profile",
  traits: .sampleSession { $0.sidebarSelection = .violations(.noIFRCurrency) }
) {
  @Environment(LogbookSession.self)
  @Previewable var session
  PageColumnPreview(session: session) {
    if let remedy = RuleRemedy(rule: .noIFRCurrency, status: .skipped(.noInstrumentRating)) {
      RuleNotCheckedView(remedy: remedy) {}
    }
  }
}

#Preview("Turned Off", traits: .sampleSession { $0.sidebarSelection = .violations(.noSICCurrency) })
{
  @Environment(LogbookSession.self)
  @Previewable var session
  PageColumnPreview(session: session) {
    if let remedy = RuleRemedy(rule: .noSICCurrency, status: .skipped(.disabled)) {
      RuleNotCheckedView(remedy: remedy) {}
    }
  }
}
