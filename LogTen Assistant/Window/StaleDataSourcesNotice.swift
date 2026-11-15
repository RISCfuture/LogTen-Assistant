import AuditWorkflow
import SwiftUI

/// The page bar's row naming the data sources that are out of date, with buttons to update them
/// or to stop offering.
struct StaleDataSourcesNotice: View {
  let stale: StaleDataSources
  let update: () -> Void
  let dismiss: () -> Void

  var body: some View {
    HStack {
      Label(StaleDataSourcesMessage(stale: stale).text, systemImage: "clock.arrow.circlepath")
        .accessibilityIdentifier("staleDataSources.message")
      Spacer()
      Button("Not Now", action: dismiss)
        .accessibilityIdentifier("staleDataSources.notNow")
      Button("Update", action: update)
        .buttonStyle(.borderedProminent)
        .accessibilityIdentifier("staleDataSources.update")
    }
    .controlSize(.small)
    .padding(.horizontal)
    .padding(.vertical, 6)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("staleDataSources")
  }
}

/// The sentences naming what is out of date, such as “NASR data is out of date. FlySto hasn’t
/// synced since Nov 6.”
private struct StaleDataSourcesMessage {
  let stale: StaleDataSources

  var text: String {
    [referenceSentence, flyStoSentence].compactMap(\.self).joined(separator: " ")
  }

  private var referenceSentence: String? {
    switch (stale.isAirportDataStale, stale.isApproachDataStale) {
      case (true, true): String(localized: "NASR and approach data are out of date.")
      case (true, false): String(localized: "NASR data is out of date.")
      case (false, true): String(localized: "Approach data is out of date.")
      case (false, false): nil
    }
  }

  private var flyStoSentence: String? {
    guard stale.isFlyStoStale else { return nil }
    guard let lastSynced = stale.flyStoLastSynced else {
      return String(localized: "FlySto hasn’t synced yet.")
    }
    return String(
      localized:
        "FlySto hasn’t synced since \(lastSynced, format: .dateTime.month(.abbreviated).day())."
    )
  }
}

#Preview(
  "Everything",
  traits: .sampleSession { session in
    session.sidebarSelection = .audit(.logbookConsistency)
    session.staleDataSources = StaleDataSources(
      isAirportDataStale: true,
      isApproachDataStale: true,
      isFlyStoStale: true,
      flyStoLastSynced: .now.addingTimeInterval(-3 * 86_400)
    )
  }
) {
  @Environment(LogbookSession.self)
  @Previewable var session
  PageColumnPreview(session: session)
}

#Preview(
  "Approach Data",
  traits: .sampleSession { session in
    session.sidebarSelection = .audit(.logbookConsistency)
    session.staleDataSources = StaleDataSources(isApproachDataStale: true)
  }
) {
  @Environment(LogbookSession.self)
  @Previewable var session
  PageColumnPreview(session: session)
}

#Preview(
  "FlySto Never Synced",
  traits: .sampleSession { session in
    session.sidebarSelection = .audit(.logbookConsistency)
    session.staleDataSources = StaleDataSources(isFlyStoStale: true)
  }
) {
  @Environment(LogbookSession.self)
  @Previewable var session
  PageColumnPreview(session: session)
}
