import LogbookModel
import SwiftUI

/// The flights with violations, as a sortable, multi-select table.
struct ViolationsTable: View {
  let rows: [ViolationRow]
  let timeZone: TimeZone
  @Binding var selection: Set<RecordID>
  let showInspector: () -> Void

  @State private var sortOrder = [KeyPathComparator(\ViolationRow.date, order: .reverse)]
  @SceneStorage("ViolationsTableColumns.v3")
  private var columnCustomization = TableColumnCustomization<ViolationRow>()

  private var sortedRows: [ViolationRow] { rows.sorted(using: sortOrder) }

  var body: some View {
    Table(
      sortedRows,
      selection: $selection,
      sortOrder: $sortOrder,
      columnCustomization: $columnCustomization
    ) {
      TableColumn("Date", value: \.date) { row in
        Text(LogbookFormat.date(row.date, in: timeZone))
      }
      .width(min: 88, ideal: 96)
      .customizationID("date")

      TableColumn("Aircraft", value: \.registration)
        .width(min: 60, ideal: 72)
        .customizationID("aircraft")

      TableColumn("Type", value: \.aircraftType)
        .width(min: 44, ideal: 52)
        .customizationID("type")

      TableColumn("Route", value: \.route) { row in
        Text(row.route).lineLimit(1).truncationMode(.middle)
      }
      .width(min: 90, ideal: 120)
      .customizationID("route")

      TableColumn("Violations", value: \.ruleTitles)
        .width(min: 140, ideal: 240)
        .customizationID("violations")

      TableColumn("PIC", value: \.PICMinutes) { row in
        Text(LogbookFormat.duration(minutes: row.PICMinutes)).monospacedDigit()
      }
      .width(min: 50, ideal: 60)
      .alignment(.trailing)
      .customizationID("pic")
      .defaultVisibility(.hidden)

      TableColumn("Passengers", value: \.passengerCount) { row in
        Text(row.passengerCount, format: .number).monospacedDigit()
      }
      .width(min: 40, ideal: 70)
      .alignment(.trailing)
      .customizationID("passengers")
      .defaultVisibility(.hidden)

      TableColumn("Explanation", value: \.explanation) { row in
        Text(row.explanation).lineLimit(1).help(row.explanation)
      }
      .width(min: 160, ideal: 360)
      .customizationID("explanation")
      .defaultVisibility(.hidden)
    }
    .contextMenu(forSelectionType: RecordID.self) { _ in
      Button("Show in Inspector", action: showInspector)
    } primaryAction: { _ in
      showInspector()
    }
    .onKeyPress(.return) {
      showInspector()
      return .handled
    }
    .accessibilityIdentifier("violationsTable")
  }
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
  PageColumnPreview(session: session) {
    ViolationsTable(
      rows: PreviewHelper.violationRows(in: session),
      timeZone: session.settings.pilot.homeTimeZone,
      selection: .constant([PreviewHelper.flight.id]),
      showInspector: {}
    )
  }
}
