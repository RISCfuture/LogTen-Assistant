import Audit
import AuditWorkflow
import Corrections
import LogbookModel
import Review
import SwiftUI

/// The contents of a finding's Checks section: what it says and how serious it is, the
/// recommendation and the correction options.
struct FindingChecks: View {
  private static let groupSpacing = 12.0

  let session: LogbookSession
  let finding: Finding

  var body: some View {
    VStack(alignment: .leading, spacing: Self.groupSpacing) {
      FindingSummary(session: session, finding: finding)
      if let recommendation = finding.recommendation {
        VStack(alignment: .leading) {
          InspectorSubheading(String(localized: "Recommendation"))
          Text(recommendation)
            .accessibilityIdentifier("findingInspector.recommendation")
        }
      }
      CorrectionChoice(session: session, finding: finding)
    }
  }
}

/// What a finding says, how serious it is, and why it matters.
private struct FindingSummary: View {
  let session: LogbookSession
  let finding: Finding

  @AppStorage(AppSettingsKey.showsFindingIDs)
  private var showsFindingIDs = false

  private var analysis: FindingAnalysis? { session.auditRun?.analyses[finding.id] }
  private var followUp: AuditFollowUp? { session.auditRun?.followUps[finding.id] }

  private var notes: [String] {
    [analysis?.summary, followUp?.summary].compactMap(\.self)
      + (analysis?.notes ?? []) + (followUp?.notes ?? [])
  }

  var body: some View {
    VStack(alignment: .leading) {
      InspectorSubheading(RuleDisplay.title(of: finding.rule))
      SeverityBadge(severity: finding.severity)
        .accessibilityIdentifier("findingInspector.severity")
      Text(finding.message)
        .accessibilityIdentifier("findingInspector.message")
      if let explanation = finding.explanation {
        Text(explanation)
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("findingInspector.explanation")
      }
      if let citation = finding.citation {
        LabeledContent("Reference") {
          CitationText(citation: citation)
        }
      }
      ForEach(notes, id: \.self) { note in
        Text(note).foregroundStyle(.secondary)
      }
      if showsFindingIDs {
        LabeledContent("Finding ID") {
          Text(finding.id.rawValue).monospaced()
        }
      }
    }
  }
}

/// A citation, as a link when it is a web address.
private struct CitationText: View {
  let citation: String

  private var url: URL? {
    URL(string: citation)?.webLink
  }

  var body: some View {
    if let url {
      Link(url.host() ?? citation, destination: url)
    } else {
      Text(citation)
    }
  }
}

/// The finding's correction: a pop-up menu of its options when it offers several, then the shown
/// option's changes and what it does.
private struct CorrectionChoice: View {
  let session: LogbookSession
  let finding: Finding

  private var shown: CorrectionOption? { session.shownCorrection(of: finding) }

  private var selection: Binding<CorrectionOptionID?> {
    Binding {
      shown?.id
    } set: { option in
      if let option { session.pick(option, for: finding) }
    }
  }

  var body: some View {
    if finding.corrections.count > 1 {
      VStack(alignment: .leading) {
        InspectorSubheading(String(localized: "Corrections"))
        Picker("Correction", selection: selection) {
          if shown == nil {
            Text("Choose a Correction").tag(CorrectionOptionID?.none)
          }
          ForEach(Array(finding.corrections.enumerated()), id: \.element.id) { index, option in
            Text(option.title)
              .tag(Optional(option.id))
              .accessibilityIdentifier("findingInspector.correctionOption.\(index)")
          }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
        .accessibilityIdentifier("findingInspector.correctionOptions")
        if let shown {
          OptionDetail(option: shown, finding: finding, session: session)
        } else {
          Text("Choose the correction to apply.")
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("findingInspector.chooseCorrection")
        }
      }
    } else if let shown {
      VStack(alignment: .leading) {
        InspectorSubheading(String(localized: "Correction: \(shown.title)"))
        OptionDetail(option: shown, finding: finding, session: session)
      }
    }
  }
}

/// A correction option's changes and what it does, with why approving it adds the change to the
/// checklist when the flight is signed or locked or LogTen can't import it.
private struct OptionDetail: View {
  let option: CorrectionOption
  let finding: Finding
  let session: LogbookSession

  var body: some View {
    ProposedChanges(changes: option.changes, customFields: session.logbook?.customFields ?? [])
    if let detail = option.detail {
      Text(detail).foregroundStyle(.secondary)
    }
    if let restriction = finding.correctionRestriction {
      Text(restriction.explanation)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("findingInspector.restriction")
    } else if !option.isImportable {
      Text(
        "LogTen can’t import this change. Approving it adds it to the checklist of changes to make in LogTen yourself."
      )
      .foregroundStyle(.secondary)
      .accessibilityIdentifier("findingInspector.manualChange")
    }
  }
}

#Preview("Several Corrections", traits: .sampleSession()) {
  @Environment(LogbookSession.self)
  @Previewable var session
  InspectorColumnPreview {
    if let finding = session.auditRun?.findings.first(where: { $0.corrections.count > 1 }) {
      InspectorPage {
        InspectorSection("Checks") { FindingChecks(session: session, finding: finding) }
      }
    }
  }
}

#Preview("No Correction", traits: .sampleSession()) {
  @Environment(LogbookSession.self)
  @Previewable var session
  InspectorColumnPreview {
    if let finding = session.auditRun?.findings.first(where: \.corrections.isEmpty) {
      InspectorPage {
        InspectorSection("Checks") { FindingChecks(session: session, finding: finding) }
      }
    }
  }
}
