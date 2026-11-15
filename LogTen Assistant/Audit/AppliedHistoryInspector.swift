import Corrections
import SwiftUI

/// The inspector for Applied History: the selected batch, its changes and its verification.
struct AppliedHistoryInspector: View {
  let session: LogbookSession

  private var entry: ApplyJournalEntry? {
    session.selectedJournalEntryID.flatMap { session.journal?.entry($0) }
  }

  var body: some View {
    Group {
      if let entry {
        JournalEntryDetail(entry: entry, session: session)
      } else {
        ContentUnavailableView("No Batch Selected", systemImage: "clock.arrow.circlepath")
      }
    }
    .accessibilityIdentifier("appliedHistoryInspector")
  }
}

#Preview("No Selection", traits: .sampleSession { $0.sidebarSelection = .audit(.appliedHistory) }) {
  @Environment(LogbookSession.self)
  @Previewable var session
  InspectorColumnPreview { AppliedHistoryInspector(session: session) }
}

#Preview(
  "Batch Selected",
  traits: .sampleSession(PreviewHelper.selectAppliedBatch)
) {
  @Environment(LogbookSession.self)
  @Previewable var session
  InspectorColumnPreview { AppliedHistoryInspector(session: session) }
}
