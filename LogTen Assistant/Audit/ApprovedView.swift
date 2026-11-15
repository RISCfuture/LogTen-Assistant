import Corrections
import LogbookModel
import Review
import SwiftUI

/// Audit & Fix ▸ Approved: the fixes marked for correction, ready to back up and apply.
struct ApprovedView: View {
  @Bindable var session: LogbookSession

  private var rows: [FindingRow] {
    FindingRow.rows(
      for: session.approvedCorrections.map(\.finding).filter(session.matchesSearch),
      book: session.reviewBook,
      picked: session.pickedCorrections,
      customFields: session.logbook?.customFields ?? [],
      flight: session.flight
    )
  }

  private var retiredCount: Int { session.carryForward?.retired.count ?? 0 }

  private var showsBar: Bool { !session.approvedCorrections.isEmpty || retiredCount > 0 }

  var body: some View {
    let rows = rows
    Group {
      if !rows.isEmpty {
        FindingsTable(
          rows: rows,
          timeZone: session.settings.pilot.homeTimeZone,
          selection: $session.selectedFindingIDs,
          session: session,
          kind: "approved",
          recordedDates: session.recordedFixDates
        )
      } else if session.approvedCorrections.isEmpty {
        ContentUnavailableView(
          "No Approved Fixes",
          systemImage: "tray",
          description: Text("Mark findings for correction in a review page to apply them here.")
        )
      } else {
        ContentUnavailableView.search
      }
    }
    .scrollEdgeEffectStyle(.hard, for: .bottom)
    .safeAreaBar(edge: .bottom) {
      if showsBar {
        ApprovedBar(session: session, fixCount: session.approvedCorrections.count)
      }
    }
  }
}

/// Counts every approved fix, whatever the search shows, with the Apply button.
private struct ApprovedBar: View {
  let session: LogbookSession
  let fixCount: Int

  private var retired: Int { session.carryForward?.retired.count ?? 0 }

  private var recordedDates: [Date] { Array(session.recordedFixDates.values) }

  var body: some View {
    HStack {
      VStack(alignment: .leading) {
        Text("\(fixCount) fixes approved")
        if let latest = recordedDates.max() {
          RecordedFixesNote(count: recordedDates.count, latest: latest)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("approved.recordedNote")
        }
        if retired > 0 {
          Text(
            "\(retired) earlier decisions no longer apply because their findings are gone."
          )
          .foregroundStyle(.secondary)
        }
      }
      Spacer()
      Button("Apply Fixes…") { session.presentedSheet = .apply }
        .disabled(fixCount == 0 || !session.canStartDataTask)
        .accessibilityIdentifier("approved.apply")
    }
    .padding()
  }
}

/// How many approved fixes were recorded but not sent to LogTen, and when the latest was:
/// “3 fixes recorded Nov 9 — not sent to LogTen”.
struct RecordedFixesNote: View {
  let count: Int
  let latest: Date

  var body: some View {
    Text(
      "\(count) fixes recorded \(latest, format: .dateTime.month().day()) — not sent to LogTen"
    )
  }
}

#Preview(
  "Approved Fixes",
  traits: .sampleSession { session in
    PreviewHelper.approveCorrections(in: session)
    session.sidebarSelection = .audit(.approved)
  }
) {
  @Environment(LogbookSession.self)
  @Previewable var session
  PageColumnPreview(session: session)
}

#Preview(
  "Recorded Before",
  traits: .sampleSession { session in
    PreviewHelper.approveAndRecord(3, in: session)
    session.sidebarSelection = .audit(.approved)
  }
) {
  @Environment(LogbookSession.self)
  @Previewable var session
  PageColumnPreview(session: session)
}

#Preview("No Approved Fixes", traits: .sampleSession { $0.sidebarSelection = .audit(.approved) }) {
  @Environment(LogbookSession.self)
  @Previewable var session
  PageColumnPreview(session: session)
}
