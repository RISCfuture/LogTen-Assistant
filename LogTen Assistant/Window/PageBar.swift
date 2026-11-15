import AuditWorkflow
import Corrections
import LogbookModel
import Regulations
import Review
import SwiftUI

/**
 The slim bar above every page but Data Sources: a summary of the page with the scope control
 beside it, on a rule's page what the rule can't see, and below that the offer to update
 out-of-date data sources.

 The offer shows while the session is offering updates and no task or audit is running. Data
 Sources shows its own status, so it gets only the offer, and no bar without one.
 */
struct PageBar: View {
  let session: LogbookSession

  private var offeredUpdate: StaleDataSources? {
    session.canStartDataTask ? session.staleDataSources : nil
  }

  private var showsStatus: Bool { session.sidebarSelection != .audit(.dataSources) }

  var body: some View {
    if showsStatus || offeredUpdate != nil {
      PageBarContent(session: session, showsStatus: showsStatus)
    }
  }
}

private struct PageBarContent: View {
  let session: LogbookSession
  let showsStatus: Bool

  private var summary: PageSummary { PageSummary(session: session) }

  /// What the selected rule can't see, on a rule's Violations page.
  private var limitations: String? {
    guard case .violations(let rule?) = session.sidebarSelection else { return nil }
    return rule.limitations
  }

  private var offeredUpdate: StaleDataSources? {
    session.canStartDataTask ? session.staleDataSources : nil
  }

  var body: some View {
    VStack(spacing: 0) {
      if showsStatus {
        PageStatusRow(session: session, summary: summary.text)
      }
      if let limitations {
        RuleLimitationsNote(text: limitations)
      }
      if let offeredUpdate {
        if showsStatus { Divider() }
        StaleDataSourcesNotice(
          stale: offeredUpdate,
          update: { Task { await session.updateStaleDataSources() } },
          dismiss: { session.staleDataSources = nil }
        )
      }
    }
    .frame(maxWidth: .infinity)
    .background(.windowBackground)
    .overlay(alignment: .bottom) { Divider() }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("pageBar")
  }
}

/// A brief note of what a regulation check can't see in a logbook.
private struct RuleLimitationsNote: View {
  let text: String

  var body: some View {
    Label(text, systemImage: "info.circle")
      .font(.caption)
      .foregroundStyle(.secondary)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal)
      .padding(.bottom, 6)
      .accessibilityIdentifier("pageBar.limitations")
  }
}

/// The page's review progress or counts, and the scope control on pages that list findings. Other
/// pages keep the control's room so the row is the same height on every page. All Violations
/// also offers the rules that couldn't run for lack of mapped fields.
private struct PageStatusRow: View {
  let session: LogbookSession
  let summary: String?

  private var uncheckedRules: [RuleRemedy] {
    guard session.sidebarSelection == .violations(nil), !session.isAuditing,
      let report = session.regulationReport
    else { return [] }
    return report.unevaluatedRules.compactMap { report.remedy(for: $0) }
  }

  var body: some View {
    HStack {
      HStack(spacing: 3) {
        if let summary {
          Text(summary)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .accessibilityIdentifier("pageBar.summary")
        }
        if !uncheckedRules.isEmpty {
          Text(verbatim: "·").foregroundStyle(.secondary).accessibilityHidden(true)
          UncheckedRulesButton(session: session, remedies: uncheckedRules)
        }
      }
      Spacer()
      if session.selectedList != nil {
        ScopePicker(session: session)
      } else {
        ScopePicker(session: session).hidden().accessibilityHidden(true)
      }
    }
    .controlSize(.small)
    .padding(.horizontal)
    .padding(.vertical, 6)
  }
}

/// “2 rules not checked”, opening a list of the rules with what lets each run.
private struct UncheckedRulesButton: View {
  let session: LogbookSession
  let remedies: [RuleRemedy]

  @State private var isShowingRules = false

  var body: some View {
    Button("\(remedies.count) rules not checked") { isShowingRules = true }
      .buttonStyle(.link)
      .help("Show the rules that couldn’t run and how to check them")
      .popover(isPresented: $isShowingRules, arrowEdge: .bottom) {
        UncheckedRulesList(remedies: remedies) { remedy in
          isShowingRules = false
          session.showSettings(for: remedy)
        }
      }
      .accessibilityIdentifier("pageBar.uncheckedRules")
  }
}

/// Each rule that couldn't run, why, and the button that opens the setting that lets it run.
private struct UncheckedRulesList: View {
  let remedies: [RuleRemedy]
  let showSettings: (RuleRemedy) -> Void

  @ScaledMetric private var width = 320.0

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      ForEach(remedies, id: \.rule) { remedy in
        UncheckedRuleItem(remedy: remedy) { showSettings(remedy) }
      }
    }
    .padding()
    .frame(width: width)
  }
}

/// One rule in the list of rules that couldn't run.
private struct UncheckedRuleItem: View {
  let remedy: RuleRemedy
  let showSettings: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(remedy.rule.title)
        .font(.headline)
      Text(remedy.description)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      Button(remedy.actionTitle, action: showSettings)
        .controlSize(.small)
        .accessibilityIdentifier("pageBar.uncheckedRules.\(remedy.rule.rawValue)")
    }
  }
}

/// The segmented control that limits review pages to recent flights.
private struct ScopePicker: View {
  @Bindable var session: LogbookSession

  var body: some View {
    Picker("Scope", selection: $session.auditScope) {
      ForEach(AuditScope.allCases, id: \.self) { scope in
        Text(scope.shortTitle).tag(scope).accessibilityLabel(scope.title)
      }
    }
    .pickerStyle(.segmented)
    .labelsHidden()
    .fixedSize()
    .help("Show findings on flights from the last 90 days, this year or the whole logbook")
    .accessibilityIdentifier("pageBar.scope")
  }
}

/// A summary of the selected page, such as “12 of 40 to review”, or `nil` while the audit is
/// running. The counts of review, Approved and Violations pages are of what the search field
/// matches.
private struct PageSummary {
  private static let separator = " · "

  private static var noMatches: String { String(localized: "No matches") }

  let session: LogbookSession

  var text: String? {
    guard !session.isAuditing else { return nil }
    let parts = self.parts
    return parts.isEmpty ? nil : parts.joined(separator: Self.separator)
  }

  private var parts: [String] {
    switch session.sidebarSelection {
      case .audit(.appliedHistory): appliedParts
      case .audit(.approved): approvedParts
      case nil: []
      case .audit, .checks: session.selectedList.map(reviewParts) ?? []
      case .violations(nil): violationParts
      case .violations(let rule?): [rule.citation]
    }
  }

  private var appliedParts: [String] {
    let entries = session.journal?.entries ?? []
    guard !entries.isEmpty else { return [String(localized: "Nothing applied")] }
    if session.isSearching, !entries.contains(where: session.matchesSearch) {
      return [Self.noMatches]
    }
    let applied = session.journal?.appliedBatches.count ?? 0
    let recorded = entries.count { $0.isRecorded && $0.revertedEntryID == nil }
    var parts = [String]()
    if applied > 0 || recorded == 0 {
      parts.append(String(localized: "\(applied) batches applied"))
    }
    if recorded > 0 {
      parts.append(
        String(localized: "\(recorded) batches recorded, not sent to LogTen")
      )
    }
    return parts
  }

  private var approvedParts: [String] {
    let approved = session.approvedCorrections
    guard !approved.isEmpty else { return [String(localized: "No fixes approved")] }
    guard session.isSearching else {
      return [String(localized: "\(approved.count) fixes approved")]
    }
    let matching = approved.count { session.matchesSearch($0.finding) }
    guard matching > 0 else { return [Self.noMatches] }
    return [
      String(
        localized: "\(matching, format: .number) of \(approved.count) approved fixes"
      )
    ]
  }

  private var violationParts: [String] {
    guard let report = session.regulationReport else { return [] }
    guard session.isSearching else { return Self.violationParts(of: report) }
    let rows = ViolationRow.rows(
      in: report,
      for: nil,
      flight: session.flight,
      matching: session.searchText,
      in: session.settings.pilot.homeTimeZone
    )
    guard !rows.isEmpty else { return [Self.noMatches] }
    let matching = rows.reduce(0) { $0 + $1.violations.count }
    return [
      String(
        localized:
          "\(matching, format: .number) of \(report.violations.count) violations on \(rows.count) flights"
      )
    ]
  }

  private static func violationParts(of report: RegulationReport) -> [String] {
    let violations = report.violations.count
    let flights = report.flights.count
    return [
      String(
        localized: "\(violations) violations on \(flights) flights"
      )
    ]
  }

  private func reviewParts(_ list: FindingList) -> [String] {
    let findings = session.findings(in: list)
    let total = findings.count
    let unreviewed = findings.count { session.reviewBook.decision(for: $0.id) == .unreviewed }
    if total == 0 {
      return [session.isSearching ? Self.noMatches : String(localized: "No findings")]
    }
    if unreviewed == 0 { return [String(localized: "All \(total, format: .number) reviewed")] }
    return [
      String(localized: "\(unreviewed, format: .number) of \(total, format: .number) to review")
    ]
  }
}

nonisolated extension AuditScope {
  /// The scope's name in a segmented control: “90 Days”, “This Year” or “All”.
  fileprivate var shortTitle: String {
    switch self {
      case .last90Days: String(localized: "90 Days")
      case .thisYear: String(localized: "This Year")
      case .all: String(localized: "All", comment: "Audit scope: every flight")
    }
  }
}

#Preview(
  "Review",
  traits: .sampleSession { session in
    session.sidebarSelection = .audit(.logbookConsistency)
  }
) {
  @Environment(LogbookSession.self)
  @Previewable var session
  PageColumnPreview(session: session)
}

#Preview(
  "Rule with Limitations",
  traits: .sampleSession { session in
    session.sidebarSelection = .violations(.noIFRCurrency)
  }
) {
  @Environment(LogbookSession.self)
  @Previewable var session
  PageColumnPreview(session: session)
}

#Preview(
  "Violations",
  traits: .sampleSession { session in
    session.sidebarSelection = .violations(nil)
  }
) {
  @Environment(LogbookSession.self)
  @Previewable var session
  PageColumnPreview(session: session)
}

#Preview("Unchecked Rules Popover") {
  PopoverPreview {
    UncheckedRulesList(
      remedies: [
        RuleRemedy(
          rule: .noNVGCurrency,
          status: .notEvaluated(missingRoles: [.nightVisionGoggleProficiencyCheck])
        ),
        RuleRemedy(
          rule: .noNightPassengerCurrency,
          status: .notEvaluated(missingRoles: [.nightTakeoffs, .nightFullStops])
        )
      ].compactMap(\.self)
    ) { _ in }
  }
}

#Preview(
  "Review with Update Offer",
  traits: .sampleSession { session in
    session.sidebarSelection = .audit(.logbookConsistency)
    session.staleDataSources = StaleDataSources(isAirportDataStale: true, isFlyStoStale: true)
  }
) {
  @Environment(LogbookSession.self)
  @Previewable var session
  PageColumnPreview(session: session)
}

#Preview(
  "Data Sources with Update Offer",
  traits: .sampleSession { session in
    session.sidebarSelection = .audit(.dataSources)
    session.staleDataSources = StaleDataSources(isApproachDataStale: true)
  }
) {
  @Environment(LogbookSession.self)
  @Previewable var session
  PageColumnPreview(session: session)
}
