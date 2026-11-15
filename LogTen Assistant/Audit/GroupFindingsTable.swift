import AuditWorkflow
import LogbookModel
import Review
import SwiftUI

/// Smart-group findings as a sortable, multi-select table of the group, the check that flagged
/// it and the regulation it cites. It takes the same commands as ``FindingsTable``.
struct GroupFindingsTable: View {
  let rows: [FindingRow]
  @Binding var selection: Set<FindingID>
  @Bindable var session: LogbookSession

  /// Which table this is, for its accessibility identifier.
  let kind: String

  @SceneStorage("GroupFindingsTableColumns.v1")
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
        DecisionBadge(decision: row.decision)
      }
      .width(min: 64, ideal: 70, max: 90)
      .customizationID("decision")

      TableColumn("Group", value: \.groupName) { row in
        Text(row.groupName).lineLimit(1)
      }
      .width(min: 120, ideal: 200)
      .customizationID("group")

      TableColumn("Severity", value: \.severityRank) { row in
        SeverityBadge(severity: row.severity)
      }
      .width(min: 120, ideal: 130)
      .customizationID("severity")

      TableColumn("Check", value: \.ruleTitle) { row in
        Text(row.ruleTitle).lineLimit(1).help(row.message)
      }
      .width(min: 140, ideal: 220)
      .customizationID("check")

      TableColumn("Regulation", value: \.citation)
        .width(min: 80, ideal: 100)
        .customizationID("citation")

      TableColumn("Details", value: \.message) { row in
        Text(row.message).lineLimit(1).help(row.message)
      }
      .width(min: 160, ideal: 320)
      .customizationID("message")
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

#Preview(
  "Every Finding",
  traits: .sampleSession { $0.sidebarSelection = .audit(.groupsAndCurrency) }
) {
  @Environment(LogbookSession.self)
  @Previewable var session
  PageColumnPreview(session: session) {
    GroupFindingsTable(
      rows: PreviewHelper.findingRows(in: session),
      selection: .constant([]),
      session: session,
      kind: "preview"
    )
  }
}
