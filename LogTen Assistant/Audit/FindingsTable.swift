import AuditWorkflow
import LogbookModel
import Review
import SwiftUI

/// Findings as a sortable, multi-select table, with the review commands in its context menu.
///
/// Return or a double-click shows the inspector; Space approves the selection for correction,
/// or clears its approval.
struct FindingsTable: View {
  let rows: [FindingRow]
  let timeZone: TimeZone
  @Binding var selection: Set<FindingID>
  @Bindable var session: LogbookSession

  /// Which table this is, for its accessibility identifier.
  let kind: String

  /// When fixes were recorded rather than sent to LogTen, by finding, for the Approved table.
  var recordedDates = [FindingID: Date]()

  @SceneStorage("FindingsTableColumns.v3")
  private var columnCustomization = TableColumnCustomization<FindingRow>()

  private var sortedRows: [FindingRow] { rows.sorted(using: session.findingSortOrder) }

  var body: some View {
    Table(
      sortedRows,
      selection: $selection,
      sortOrder: $session.findingSortOrder,
      columnCustomization: $columnCustomization
    ) {
      TableColumn("Decision", value: \.decisionTitle) { row in
        HStack(spacing: 4) {
          DecisionBadge(decision: row.decision)
          if let recordedAt = recordedDates[row.id] {
            RecordedBadge(recordedAt: recordedAt)
          }
        }
      }
      .width(min: 64, ideal: 70, max: 90)
      .customizationID("decision")

      TableColumn("Date", value: \.date) { row in
        Text(row.occurredAt.map { LogbookFormat.date($0, in: timeZone) } ?? "")
      }
      .width(min: 88, ideal: 96)
      .customizationID("date")

      TableColumn("Aircraft", value: \.registration)
        .width(min: 60, ideal: 72)
        .customizationID("aircraft")

      TableColumn("Severity", value: \.severityRank) { row in
        SeverityBadge(severity: row.severity)
      }
      .width(min: 120, ideal: 130)
      .customizationID("severity")

      TableColumn("Finding", value: \.ruleTitle) { row in
        Text(row.ruleTitle).lineLimit(1).help(row.message)
      }
      .width(min: 120, ideal: 200)
      .customizationID("rule")

      TableColumn("Route", value: \.route) { row in
        Text(row.route).lineLimit(1).truncationMode(.middle)
      }
      .width(min: 80, ideal: 110)
      .customizationID("route")
      .defaultVisibility(.hidden)

      TableColumn("Details", value: \.message) { row in
        Text(row.message).lineLimit(1).help(row.message)
      }
      .width(min: 160, ideal: 320)
      .customizationID("message")
      .defaultVisibility(.hidden)

      TableColumn("Proposed Change", value: \.changeSummary) { row in
        Text(row.changeSummary).lineLimit(1).help(row.changeSummary)
      }
      .width(min: 120, ideal: 240)
      .customizationID("change")
      .defaultVisibility(.hidden)
    }
    .contextMenu(forSelectionType: FindingID.self) { ids in
      FindingContextMenu(session: session, ids: ids)
    } primaryAction: { _ in
      session.isInspectorPresented = true
    }
    .modifier(ReviewTableCommands(session: session, selection: selection))
    .accessibilityIdentifier("findingsTable.\(kind)")
  }
}

/// The keyboard and context-menu commands shared by the findings tables: Return shows the
/// inspector, Space approves or clears the selection, and the table takes focus on request.
struct ReviewTableCommands: ViewModifier {
  let session: LogbookSession
  let selection: Set<FindingID>

  @FocusState private var isFocused: Bool

  func body(content: Content) -> some View {
    content
      .focused($isFocused)
      .onChange(of: session.tableFocusRequests) { isFocused = true }
      .onKeyPress(.return) {
        session.isInspectorPresented = true
        return .handled
      }
      .onKeyPress(.space) {
        guard !selection.isEmpty else { return .ignored }
        session.toggleApproval()
        return .handled
      }
  }
}

/// A decision as a small symbol, with its name for VoiceOver and as a tooltip.
struct DecisionBadge: View {
  let decision: ReviewDecision

  var body: some View {
    Image(systemName: decision.systemImage)
      .foregroundStyle(decision == .unreviewed ? .tertiary : .secondary)
      .help(decision.title)
      .accessibilityLabel(decision.title)
      .accessibilityIdentifier("findingsTable.decision")
  }
}

/// Marks a fix recorded to disk but not sent to LogTen, with when as its tooltip.
struct RecordedBadge: View {
  let recordedAt: Date

  private var note: String { RecordedFixText.note(recordedAt: recordedAt) }

  var body: some View {
    Image(systemName: "tray.and.arrow.down")
      .foregroundStyle(.secondary)
      .help(note)
      .accessibilityLabel(note)
      .accessibilityIdentifier("findingsTable.recorded")
  }
}

/// A severity tier as its symbol and name. Only discrepancies and questionable entries are tinted.
struct SeverityBadge: View {
  let severity: Severity

  private var tint: AnyShapeStyle {
    switch severity {
      case .discrepancy: AnyShapeStyle(.red)
      case .questionable: AnyShapeStyle(.orange)
      case .suggestion: AnyShapeStyle(.secondary)
    }
  }

  var body: some View {
    Label {
      Text(severity.title)
    } icon: {
      Image(systemName: severity.systemImage).foregroundStyle(tint)
    }
    .labelStyle(.tight)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(severity.title)
  }
}

/// A label with its icon set close to its title.
struct TightLabelStyle: LabelStyle {
  private static let spacing = 3.0

  func makeBody(configuration: Configuration) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: Self.spacing) {
      configuration.icon
      configuration.title
    }
  }
}

extension LabelStyle where Self == TightLabelStyle {
  /// A label with its icon set close to its title.
  static var tight: Self { .init() }
}

/// The review commands for findings, as a context menu that mirrors the Review menu.
struct FindingContextMenu: View {
  let session: LogbookSession
  let ids: Set<FindingID>

  private var canMarkForCorrection: Bool {
    ids.compactMap(session.finding).contains {
      session.canApprove($0, amongSeveral: ids.count > 1)
    }
  }

  var body: some View {
    Group {
      ContextDecisionButton(session: session, ids: ids, decision: .correction)
        .disabled(!canMarkForCorrection)
      ContextDecisionButton(session: session, ids: ids, decision: .falsePositive)
      Divider()
      ContextDecisionButton(session: session, ids: ids, decision: .needsEvidence)
      ContextDecisionButton(session: session, ids: ids, decision: .unreviewed)
    }
    .disabled(ids.isEmpty)
    Divider()
    Button("Show in Inspector") { session.isInspectorPresented = true }
  }
}

/// A context-menu item that records one decision for the clicked findings.
private struct ContextDecisionButton: View {
  let session: LogbookSession
  let ids: Set<FindingID>
  let decision: ReviewDecision

  var body: some View {
    Button(decision.actionName) { session.decide(decision, for: ids) }
  }
}

#Preview("Severity Badges") {
  VStack(alignment: .leading) {
    ForEach(Severity.allCases, id: \.self) { SeverityBadge(severity: $0) }
  }
  .padding()
  .frame(width: LogbookSplitView.sidebarIdealWidth, alignment: .leading)
}

#Preview("Findings", traits: .sampleSession { $0.sidebarSelection = .audit(.logbookConsistency) }) {
  @Environment(LogbookSession.self)
  @Previewable var session
  PageColumnPreview(session: session) {
    FindingsTable(
      rows: PreviewHelper.findingRows(of: .logbookConsistency, in: session),
      timeZone: session.settings.pilot.homeTimeZone,
      selection: .constant([]),
      session: session,
      kind: "preview"
    )
  }
}
