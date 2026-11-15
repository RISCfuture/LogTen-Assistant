import AppKit
import AuditWorkflow
import Corrections
import LogbookModel
import SwiftUI

/// The sheet's title and a sentence on what applying does in the current mode.
struct ApplyHeaderSection: View {
  let session: LogbookSession
  let model: ApplyModel

  var body: some View {
    Section {
      Text(
        "Apply ^[\(session.approvedCorrections.count) fix](inflect: true) to \(session.reference.title)"
      )
      .font(.headline)
      Text(
        model.sendsToLogTen
          ? "Each batch is sent to LogTen, which asks you to confirm it. ⌘Z can’t undo this. Revert a batch from Applied History."
          : "Packages are recorded in the logbook’s workspace folder, not sent to LogTen."
      )
      .foregroundStyle(.secondary)
      if let latest = recordedDates.max() {
        RecordedBeforeNote(
          count: recordedDates.count,
          latest: latest,
          sendsToLogTen: model.sendsToLogTen
        )
        .accessibilityIdentifier("apply.recordedNote")
      }
    }
  }

  private var recordedDates: [Date] { Array(model.recordedBefore.values) }
}

/// Says that some of the fixes were recorded before and never sent, and what applying them
/// again does.
private struct RecordedBeforeNote: View {
  let count: Int
  let latest: Date
  let sendsToLogTen: Bool

  var body: some View {
    Label {
      VStack(alignment: .leading) {
        RecordedFixesNote(count: count, latest: latest)
        Text(
          sendsToLogTen
            ? "Recording didn’t change the logbook, so they’re still approved. Applying sends them to LogTen now."
            : "Recording doesn’t change the logbook, so they’re still approved. Applying records new packages for them."
        )
        .foregroundStyle(.secondary)
      }
    } icon: {
      Image(systemName: "tray.and.arrow.down").foregroundStyle(.secondary)
    }
  }
}

/// What the plan changes, what it leaves out and why, and what to change by hand.
struct PlanSections: View {
  let plan: ApplyPlan
  let session: LogbookSession

  /// When fixes in the plan were recorded by an earlier apply, by finding.
  var recordedDates = [FindingID: Date]()

  private var customFields: [CustomFieldDefinition] { session.logbook?.customFields ?? [] }

  var body: some View {
    Section {
      ForEach(plan.preflight.ready) { operation in
        DisclosureGroup {
          ProposedChanges(changes: operation.changes, customFields: customFields)
        } label: {
          OperationLabel(
            summary: summary(of: operation.recordIDs),
            message: operation.message,
            recordedAt: recordedDates[operation.findingID]
          )
        }
      }
    } header: {
      Text(
        "^[\(plan.preflight.readyChanges.count) change](inflect: true) to ^[\(plan.flightCount) flight](inflect: true)"
      )
      .accessibilityIdentifier("apply.summary")
    }
    if !plan.preflight.excluded.isEmpty {
      Section("Can’t Be Imported") {
        ForEach(plan.preflight.excluded, id: \.operation.id) { excluded in
          VStack(alignment: .leading) {
            Text(operationTitle(excluded.operation.recordIDs, excluded.operation.message))
            ForEach(excluded.issues, id: \.self) { issue in
              Text(issue.explanation).foregroundStyle(.secondary)
            }
          }
        }
      }
    }
    if !plan.preflight.checklist.items.isEmpty {
      Section("Change by Hand") {
        ForEach(plan.preflight.checklist.items) { item in
          ChecklistRow(
            item: item,
            fieldTitle: LogbookFormat.fieldTitle(item.change.field, customFields: customFields),
            timeZone: session.settings.pilot.homeTimeZone
          )
        }
      }
    }
  }

  private func summary(of recordIDs: [RecordID]) -> String? {
    recordIDs.lazy.compactMap(session.flight).first.map { flight in
      [
        LogbookFormat.date(flight.date, in: session.settings.pilot.homeTimeZone),
        flight.aircraft?.registration, LogbookFormat.route(of: flight)
      ]
      .compactMap(\.self).joined(separator: " · ")
    }
  }

  private func operationTitle(_ recordIDs: [RecordID], _ message: String) -> String {
    [summary(of: recordIDs), message].compactMap(\.self).joined(separator: " — ")
  }
}

/// A planned operation's flight on one line and what it does below, with when it was recorded
/// before if it was.
private struct OperationLabel: View {
  let summary: String?
  let message: String
  let recordedAt: Date?

  var body: some View {
    VStack(alignment: .leading) {
      if let summary {
        Text(summary)
        Text(message).foregroundStyle(.secondary)
      } else {
        Text(message)
      }
      if let recordedAt {
        Text(RecordedFixText.note(recordedAt: recordedAt))
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("apply.operation.recorded")
      }
    }
  }
}

/// One change to make by hand, with copyable values and where to make it.
struct ChecklistRow: View {
  let item: ManualChecklistItem
  let fieldTitle: String
  let timeZone: TimeZone

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(
        [
          item.flightDate.map { LogbookFormat.date($0, in: timeZone) }, item.registration,
          item.route
        ]
        .compactMap(\.self).joined(separator: " · ")
      )
      LabeledContent(fieldTitle) {
        HStack {
          Text("\(item.oldValue) → \(item.newValue)").textSelection(.enabled).monospacedDigit()
          Button("Copy New Value", systemImage: "doc.on.doc") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(item.newValue, forType: .string)
          }
          .labelStyle(.iconOnly)
          .buttonStyle(.borderless)
          .help("Copy “\(item.newValue)” to paste into LogTen")
          .accessibilityIdentifier("apply.checklistItem.copy")
        }
      }
      Text(item.instruction).foregroundStyle(.secondary)
    }
    .accessibilityIdentifier("apply.checklistItem")
  }
}
