import Corrections
import LogbookModel
import SwiftUI

/// A batch’s details in the inspector: what it did, its changes, verification and package.
struct JournalEntryDetail: View {
  let entry: ApplyJournalEntry
  let session: LogbookSession

  var body: some View {
    InspectorPage {
      InspectorSection(String(localized: "Batch")) {
        LabeledContent("Applied") {
          Text(entry.receipt.deliveredAt.formatted(date: .abbreviated, time: .shortened))
        }
        LabeledContent("Action") { Text(entry.actionTitle) }
        LabeledContent("Flights") {
          Text(entry.batch.recordIDs.count, format: .number).monospacedDigit()
        }
        LabeledContent("Changes") {
          Text(entry.batch.changes.count, format: .number).monospacedDigit()
        }
        LabeledContent("Status") { Text(entry.displayStatus) }
        Button("Revert Batch…") { session.revertingEntryID = entry.id }
          .disabled(!session.canRevert(entry))
          .accessibilityIdentifier("appliedHistory.revert")
      }
      InspectorSection(String(localized: "Changes")) {
        ProposedChanges(
          changes: entry.batch.changes,
          customFields: session.logbook?.customFields ?? []
        )
      }
      if let verification = entry.verification {
        InspectorSection(String(localized: "Verification")) {
          if verification.isVerified {
            Text("Every change appears in the logbook, and nothing else changed.")
          }
          ForEach(Array(verification.issues.enumerated()), id: \.offset) { _, issue in
            Text(issue.explanation).foregroundStyle(.secondary)
          }
        }
      }
      InspectorSection(String(localized: "Package")) {
        PackageDisclosure(json: entry.packageJSON)
      }
    }
  }
}

/// The package JSON behind a disclosure whose whole label toggles it.
private struct PackageDisclosure: View {
  let json: String

  @State private var isExpanded = false

  var body: some View {
    VStack(alignment: .leading) {
      Button {
        isExpanded.toggle()
      } label: {
        Label("Package JSON", systemImage: "chevron.right")
          .labelStyle(DisclosureLabelStyle(isExpanded: isExpanded))
          .contentShape(.rect)
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("appliedHistory.packageToggle")
      if isExpanded {
        Text(json)
          .monospaced()
          .textSelection(.enabled)
          .accessibilityIdentifier("appliedHistory.package")
      }
    }
  }
}

/// A label with a chevron that turns down when expanded, in the style of a disclosure triangle.
private struct DisclosureLabelStyle: LabelStyle {
  let isExpanded: Bool

  func makeBody(configuration: Configuration) -> some View {
    HStack {
      configuration.icon
        .imageScale(.small)
        .fontWeight(.semibold)
        .foregroundStyle(.secondary)
        .rotationEffect(isExpanded ? .degrees(90) : .zero)
        .animation(.default, value: isExpanded)
      configuration.title
      Spacer()
    }
  }
}

#Preview("Verified Batch", traits: .sampleSession(PreviewHelper.selectAppliedBatch)) {
  @Environment(LogbookSession.self)
  @Previewable var session
  InspectorColumnPreview {
    if let entry = session.journal?.entries.first {
      JournalEntryDetail(entry: entry, session: session)
    }
  }
}
