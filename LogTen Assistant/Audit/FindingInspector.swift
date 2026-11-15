import Audit
import AuditWorkflow
import LogbookModel
import Review
import SwiftUI

/// The inspector for a review table, laid out like LogTen's: the selected finding's Checks
/// section first, then its evidence and its flight's details, with any correction's changes
/// shown in place and the details its sources disagree with marked. The decision bar stays in
/// view below.
struct FindingInspector: View {
  let session: LogbookSession

  private var selectedFinding: Finding? {
    guard session.selectedFindingIDs.count == 1, let id = session.selectedFindingIDs.first else {
      return nil
    }
    return session.finding(id)
  }

  var body: some View {
    Group {
      if let finding = selectedFinding {
        FindingDetail(session: session, finding: finding)
          .id(finding.id)
      } else if session.selectedFindingIDs.isEmpty {
        ContentUnavailableView(
          "No Finding Selected",
          systemImage: "checklist",
          description: Text("Select a finding to see its evidence and decide it.")
        )
      } else {
        SeveralFindingsView(session: session)
      }
    }
    .accessibilityIdentifier("findingInspector")
  }
}

/// Several selected findings, decided together.
private struct SeveralFindingsView: View {
  let session: LogbookSession

  private var approvableCount: Int {
    session.selectedFindingIDs.compactMap(session.finding).count {
      session.canApprove($0, amongSeveral: true)
    }
  }

  private var markedCount: Int {
    session.selectedFindingIDs.count { session.reviewBook.decision(for: $0) == .correction }
  }

  private var hasDrafts: Bool {
    session.selectedFindingIDs.contains { session.decisionDraft(for: $0) != DecisionDraft() }
  }

  var body: some View {
    ContentUnavailableView {
      Label(
        "\(session.selectedFindingIDs.count, format: .number) Findings Selected",
        systemImage: "checklist"
      )
    } description: {
      if approvableCount < session.selectedFindingIDs.count {
        Text(
          "Findings with no correction, or with several to choose from, aren’t marked for correction together."
        )
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .safeAreaBar(edge: .bottom) {
      DecisionBar(
        session: session,
        status: .several(
          count: session.selectedFindingIDs.count,
          approvable: approvableCount,
          marked: markedCount
        ),
        offersCorrection: approvableCount > 0,
        hasDrafts: hasDrafts
      )
    }
  }
}

/// One finding in full, with the decision bar below.
private struct FindingDetail: View {
  let session: LogbookSession
  let finding: Finding

  private var flight: Flight? { finding.recordIDs.lazy.compactMap(session.flight).first }

  private var shownCorrection: CorrectionOption? { session.shownCorrection(of: finding) }

  var body: some View {
    InspectorPage {
      InspectorSection(String(localized: "Checks")) {
        FindingChecks(session: session, finding: finding)
      }
      FindingEvidenceSections(session: session, finding: finding, flight: flight)
      if let flight {
        FlightDetailsSections(
          details: FlightDetails(
            flight: flight,
            customFields: session.logbook?.customFields ?? [],
            timeZone: session.settings.pilot.homeTimeZone,
            changes: shownCorrection?.changes ?? [],
            discrepancies: discrepancies(on: flight)
          )
        )
      }
    }
    .safeAreaBar(edge: .bottom) {
      DecisionBar(
        session: session,
        status: .finding(
          session.reviewBook.decision(for: finding.id),
          correction: shownCorrection?.title
        ),
        offersCorrection: session.canApprove(finding, amongSeveral: false),
        draftFindingID: finding.id
      )
    }
  }

  private func discrepancies(on flight: Flight) -> [SourceDiscrepancy] {
    (session.auditRun?.sourceChoices[flight.id] ?? []).compactMap {
      SourceDiscrepancy($0, flight: flight)
    }
  }
}

#Preview("Selected Finding", traits: .sampleSession { PreviewHelper.selectFinding(in: $0) }) {
  @Environment(LogbookSession.self)
  @Previewable var session
  InspectorColumnPreview { FindingInspector(session: session) }
}

#Preview(
  "Scrolled to a Pinned Section Bar",
  traits: .sampleSession { PreviewHelper.selectFinding(in: $0) }
) {
  @Environment(LogbookSession.self)
  @Previewable var session
  InspectorColumnPreview {
    FindingInspector(session: session)
      .defaultScrollAnchor(.center)
  }
}

#Preview(
  "Several Corrections",
  traits: .sampleSession { session in
    PreviewHelper.selectFinding(in: session) { $0.corrections.count > 1 }
  }
) {
  @Environment(LogbookSession.self)
  @Previewable var session
  InspectorColumnPreview { FindingInspector(session: session) }
}

#Preview(
  "Several Selected",
  traits: .sampleSession { session in
    session.sidebarSelection = .audit(.logbookConsistency)
    let findings = session.findings(in: FindingList(queue: .logbookConsistency))
    session.selectedFindingIDs = Set(findings.prefix(3).map(\.id))
  }
) {
  @Environment(LogbookSession.self)
  @Previewable var session
  InspectorColumnPreview { FindingInspector(session: session) }
}

#Preview(
  "No Selection",
  traits: .sampleSession { $0.sidebarSelection = .audit(.logbookConsistency) }
) {
  @Environment(LogbookSession.self)
  @Previewable var session
  InspectorColumnPreview { FindingInspector(session: session) }
}
