import SwiftUI

/// An Audit & Fix page.
struct AuditPageView: View {
  let session: LogbookSession
  let page: AuditPage

  var body: some View {
    switch page {
      case .dataSources: DataSourcesView(session: session)
      case .approved: ApprovedView(session: session)
      case .appliedHistory: AppliedHistoryView(session: session)
      case .logbookConsistency, .aircraftComparisons, .unmatchedActivity, .groupsAndCurrency:
        if let queue = page.queue {
          ReviewQueueView(session: session, list: FindingList(queue: queue))
        }
    }
  }
}

#Preview(
  "Needs Evidence",
  traits: .sampleSession { $0.sidebarSelection = .audit(.aircraftComparisons) }
) {
  @Environment(LogbookSession.self)
  @Previewable var session
  PageColumnPreview(session: session) {
    AuditPageView(session: session, page: .aircraftComparisons)
  }
}
