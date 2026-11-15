import Audit
import AuditWorkflow
import Regulations
import SwiftUI

/// The logbook window's sidebar: the Audit & Fix pages, with the logbook-consistency findings
/// by category of check nested under Logbook Consistency, then the violations of each rule.
/// Rows are text with counts, and rows with nothing to show are gray; no symbol would tell
/// apart rules such as passenger and night passenger currency, so none have one.
struct LogbookSidebar: View {
  @Bindable var session: LogbookSession

  @SceneStorage("SidebarShowsCategories")
  private var showsCategories = true
  @SceneStorage("SidebarShowsViolations")
  private var showsViolations = true

  var body: some View {
    List(selection: $session.sidebarSelection) {
      Section("Audit & Fix") {
        ForEach(AuditPage.allCases, id: \.self) { page in
          if page == .logbookConsistency {
            DisclosureGroup(isExpanded: $showsCategories) {
              ForEach(ConsistencyCategory.allCases, id: \.self) { category in
                CheckCategorySidebarRow(category: category, session: session)
                  .tag(SidebarItem.checks(category))
              }
            } label: {
              AuditSidebarRow(page: page, session: session, showsBadge: !showsCategories)
                .tag(SidebarItem.audit(page))
            }
          } else {
            AuditSidebarRow(page: page, session: session)
              .tag(SidebarItem.audit(page))
          }
        }
      }
      Section("Violations", isExpanded: $showsViolations) {
        let violationCount = session.regulationReport?.violations.count ?? 0
        Text("All Violations")
          .badge(violationCount)
          .foregroundStyle(violationCount == 0 ? .secondary : .primary)
          .tag(SidebarItem.violations(nil))
          .accessibilityIdentifier("sidebar.violations")
        ForEach(RegulationRule.allCases, id: \.self) { rule in
          RuleSidebarRow(rule: rule, session: session)
            .tag(SidebarItem.violations(rule))
        }
      }
    }
    .listStyle(.sidebar)
    .accessibilityIdentifier("sidebar")
    .onChange(of: session.sidebarSelection) { revealSelection() }
  }

  private func revealSelection() {
    switch session.sidebarSelection {
      case .checks: showsCategories = true
      case .violations: showsViolations = true
      case .audit, nil: break
    }
  }
}

/// An Audit & Fix page in the sidebar, with the number of findings it holds to review, gray
/// when a page of findings has none.
private struct AuditSidebarRow: View {
  let page: AuditPage
  let session: LogbookSession

  /// Whether the count shows. A page that has rows nested under it hides its count while they
  /// are showing theirs.
  var showsBadge = true

  private var count: Int {
    if let queue = page.queue { return session.unreviewedCount(in: FindingList(queue: queue)) }
    return page == .approved ? session.approvedCorrections.count : 0
  }

  private var isEmpty: Bool {
    if let queue = page.queue { return !session.hasFindings(in: FindingList(queue: queue)) }
    return page == .approved && session.approvedCorrections.isEmpty
  }

  var body: some View {
    Text(page.title)
      .badge(showsBadge ? count : 0)
      .foregroundStyle(isEmpty ? .secondary : .primary)
      .help(page.summary)
      .accessibilityIdentifier("sidebar.audit.\(page.rawValue)")
  }
}

/// A category of consistency checks in the sidebar, with the number of its findings to review,
/// gray when it has none.
private struct CheckCategorySidebarRow: View {
  let category: ConsistencyCategory
  let session: LogbookSession

  private var list: FindingList { FindingList(queue: .logbookConsistency, category: category) }

  var body: some View {
    Text(category.title)
      .badge(session.unreviewedCount(in: list))
      .foregroundStyle(session.hasFindings(in: list) ? .primary : .secondary)
      .accessibilityIdentifier("sidebar.checks.\(category.rawValue)")
  }
}

/// A rule in the sidebar with its violation count: gray when it found none, and lighter still
/// when it didn't run, with the reason and what the rule can't see in its help tag and the
/// setting that lets it run in its context menu.
private struct RuleSidebarRow: View {
  let rule: RegulationRule
  let session: LogbookSession

  private var report: RegulationReport? { session.regulationReport }

  private var status: RuleStatus? { report?.statuses[rule] }

  private var violations: [Violation] {
    status?.isEvaluated == true ? report?.violations(of: rule) ?? [] : []
  }

  private var style: HierarchicalShapeStyle {
    if status?.isEvaluated == false { return .tertiary }
    return violations.isEmpty ? .secondary : .primary
  }

  var body: some View {
    Text(rule.title)
      .badge(violations.count)
      .foregroundStyle(style)
      .help(
        [status?.explanation ?? rule.citation, rule.limitations]
          .compactMap(\.self).joined(separator: "\n\n")
      )
      .contextMenu {
        if let remedy = report?.remedy(for: rule) {
          Button(remedy.actionTitle) { session.showSettings(for: remedy) }
        }
      }
      .accessibilityIdentifier("sidebar.rule.\(rule.rawValue)")
  }
}

#Preview(
  "Review Page Selected",
  traits: .sampleSession { $0.sidebarSelection = .audit(.logbookConsistency) }
) {
  @Environment(LogbookSession.self)
  @Previewable var session
  SidebarColumnPreview { LogbookSidebar(session: session) }
}
