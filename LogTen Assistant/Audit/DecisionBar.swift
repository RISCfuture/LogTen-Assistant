import AuditWorkflow
import LogbookModel
import Review
import SwiftUI

/**
 The review decision for the selected findings, kept in view below the finding inspector.

 It states the decision plainly, takes the reason and note that go with it, offers Mark for
 Correction as the one prominent action when a correction is on offer with Keep as Logged beside
 it, and keeps the rarer decisions in a menu. The Review menu has every decision with its
 shortcut.
 */
struct DecisionBar: View {
  let session: LogbookSession
  let status: DecisionStatus

  /// Whether Mark for Correction records a correction.
  let offersCorrection: Bool

  /// The finding whose reason and note the bar edits, or nil when it decides several at once.
  var draftFindingID: FindingID?

  /// Whether any of the several selected findings has a reason or note that a decision for all of
  /// them won't record.
  var hasDrafts = false

  var body: some View {
    VStack(alignment: .leading) {
      HStack(alignment: .firstTextBaseline) {
        DecisionStatusLabel(status: status)
        Spacer()
        MoreDecisionsMenu(session: session)
      }
      if let draftFindingID {
        DecisionInputs(session: session, findingID: draftFindingID)
      } else if hasDrafts {
        Text("Reasons and notes aren’t recorded for several findings at once.")
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("findingInspector.draftsNotice")
      }
      HStack {
        DecisionButton(session: session, decision: .falsePositive)
        MarkForCorrectionButton(
          session: session,
          offersCorrection: offersCorrection,
          correction: status.correctionTitle
        )
      }
      .controlSize(.regular)
    }
    .inspectorTextSize()
    .padding()
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.windowBackground)
    .overlay(alignment: .top) { Divider() }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("findingInspector.decisionButtons")
  }
}

/// What the decision bar reports about the selection.
enum DecisionStatus {
  /// One finding's decision, with the title of the correction it records or would record.
  case finding(ReviewDecision, correction: String?)

  /// Several findings, with how many of them Mark for Correction can approve and how many are
  /// already marked for correction.
  case several(count: Int, approvable: Int, marked: Int)

  /// The title of the correction a single finding would record.
  fileprivate var correctionTitle: String? {
    if case let .finding(_, correction) = self { correction } else { nil }
  }
}

/// The selection's decision, stated plainly.
private struct DecisionStatusLabel: View {
  let status: DecisionStatus

  var body: some View {
    switch status {
      case let .finding(decision, correction):
        Label {
          VStack(alignment: .leading) {
            Text(decision.statusTitle)
            if let correction, decision == .correction {
              Text("Correction: \(correction)").foregroundStyle(.secondary)
            }
          }
        } icon: {
          Image(systemName: decision.systemImage).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("findingInspector.decision")
      case let .several(count, approvable, marked):
        SeveralStatusText(count: count, approvable: approvable, marked: marked)
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("findingInspector.decision")
    }
  }
}

/// How many of several findings are marked for correction, or can be.
private struct SeveralStatusText: View {
  let count: Int
  let approvable: Int
  let marked: Int

  var body: some View {
    if marked == count {
      Text("All \(count, format: .number) marked for correction")
    } else if marked > 0 {
      Text("\(marked, format: .number) of \(count, format: .number) marked for correction")
    } else {
      Text(
        "\(approvable, format: .number) of \(count, format: .number) can be marked for correction"
      )
    }
  }
}

/// The reason and note of one finding's decision, bound to the session so an unreviewed
/// finding's draft survives a change of selection and a decided finding's record updates in place.
private struct DecisionInputs: View {
  let session: LogbookSession
  let findingID: FindingID

  @FocusState private var isNoteFocused: Bool

  private var draft: Binding<DecisionDraft> {
    Binding {
      session.decisionDraft(for: findingID)
    } set: {
      session.setDecisionDraft($0, for: findingID)
    }
  }

  var body: some View {
    VStack(alignment: .leading) {
      Picker("Reason", selection: draft.reason) {
        Text("No Reason").tag(ReviewReason?.none)
        ForEach(ReviewReason.allCases, id: \.self) { reason in
          Text(reason.title).tag(Optional(reason))
        }
      }
      .labelsHidden()
      .fixedSize()
      .accessibilityIdentifier("findingInspector.reason")
      TextField("Note", text: draft.note, prompt: Text("Note"), axis: .vertical)
        .labelsHidden()
        .lineLimit(1...3)
        .frame(maxWidth: .infinity)
        .focused($isNoteFocused)
        .onChange(of: isNoteFocused) {
          session.isEditingText = isNoteFocused
          if !isNoteFocused { session.commitDecisionEdit() }
        }
        .onSubmit {
          session.commitDecisionEdit()
          session.focusTable()
        }
        .onDisappear {
          if isNoteFocused { session.isEditingText = false }
          session.commitDecisionEdit()
        }
        .help("Press ⌘↩ to mark for correction with this note.")
        .accessibilityIdentifier("findingInspector.note")
    }
  }
}

/// The decisions made less often: Needs More Evidence and Reset Decision.
private struct MoreDecisionsMenu: View {
  let session: LogbookSession

  var body: some View {
    Menu {
      DecisionButton(session: session, decision: .needsEvidence)
      Divider()
      DecisionButton(session: session, decision: .unreviewed)
    } label: {
      Label("More Decisions", systemImage: "ellipsis.circle")
        .labelStyle(.iconOnly)
    }
    .menuStyle(.button)
    .buttonStyle(.borderless)
    .menuIndicator(.hidden)
    .fixedSize()
    .help("More Decisions")
    .accessibilityIdentifier("findingInspector.moreDecisions")
  }
}

/// A button that records one decision for the selected findings. Reset Decision stays where it
/// is; the others move on to the next unreviewed finding.
private struct DecisionButton: View {
  let session: LogbookSession
  let decision: ReviewDecision

  var body: some View {
    Button {
      if decision == .unreviewed {
        session.decide(decision)
      } else {
        session.decideAndAdvance(decision)
      }
    } label: {
      Text(decision.actionName).frame(maxWidth: .infinity)
    }
    .accessibilityIdentifier("decide.\(decision.rawValue)")
  }
}

/// The button that approves the shown correction, prominent only while there is one to approve.
private struct MarkForCorrectionButton: View {
  let session: LogbookSession
  let offersCorrection: Bool
  let correction: String?

  private var help: String {
    correction.map { String(localized: "Mark for Correction: \($0)") }
      ?? String(localized: "Mark for Correction")
  }

  var body: some View {
    if offersCorrection {
      DecisionButton(session: session, decision: .correction)
        .buttonStyle(.borderedProminent)
        .help(help)
    } else {
      DecisionButton(session: session, decision: .correction)
        .buttonStyle(.bordered)
        .disabled(true)
    }
  }
}

#Preview(
  "Unreviewed with a Draft",
  traits: .sampleSession { session in
    PreviewHelper.selectFinding(in: session) { session.canApprove($0, amongSeveral: false) }
    if let id = session.selectedFindingIDs.first {
      session.setDecisionDraft(
        DecisionDraft(reason: .evidenceConfirms, note: "Checked against the Hobbs meter."),
        for: id
      )
    }
  }
) {
  @Environment(LogbookSession.self)
  @Previewable var session
  InspectorColumnPreview { FindingInspector(session: session) }
}

#Preview(
  "No Correction Offered",
  traits: .sampleSession { session in
    PreviewHelper.selectFinding(in: session) { !session.canApprove($0, amongSeveral: false) }
  }
) {
  @Environment(LogbookSession.self)
  @Previewable var session
  InspectorColumnPreview { FindingInspector(session: session) }
}

#Preview(
  "Marked for Correction",
  traits: .sampleSession { session in
    PreviewHelper.selectFinding(in: session) { session.canApprove($0, amongSeveral: false) }
    session.decide(.correction)
    if let id = session.selectedFindingIDs.first {
      session.setDecisionDraft(DecisionDraft(note: "Signed by the instructor."), for: id)
    }
  }
) {
  @Environment(LogbookSession.self)
  @Previewable var session
  InspectorColumnPreview { FindingInspector(session: session) }
}

#Preview(
  "Several, One Marked",
  traits: .sampleSession { session in
    session.sidebarSelection = .audit(.logbookConsistency)
    _ = PreviewHelper.approvableFindings(in: session)
    session.selectedFindingIDs = session.listedFindingIDs
    session.decide(.correction)
  }
) {
  @Environment(LogbookSession.self)
  @Previewable var session
  InspectorColumnPreview { FindingInspector(session: session) }
}

#Preview(
  "Several with Drafts",
  traits: .sampleSession { session in
    session.sidebarSelection = .audit(.logbookConsistency)
    let listed = session.listedFindingIDs
    let approvable = PreviewHelper.approvableFindings(in: session).filter { listed.contains($0.id) }
    let findings = session.findings(in: FindingList(queue: .logbookConsistency))
    let other = findings.first { !session.canApprove($0, amongSeveral: true) }
    let selected = approvable.prefix(2).map(\.id) + [other?.id].compactMap(\.self)
    session.selectedFindingIDs = Set(selected)
    if let id = selected.first {
      session.setDecisionDraft(DecisionDraft(note: "Checked against the Hobbs meter."), for: id)
    }
  }
) {
  @Environment(LogbookSession.self)
  @Previewable var session
  InspectorColumnPreview { FindingInspector(session: session) }
}
