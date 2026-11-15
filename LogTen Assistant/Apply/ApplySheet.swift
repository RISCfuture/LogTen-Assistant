import AppKit
import AuditWorkflow
import Corrections
import LogbookModel
import Review
import SwiftUI

/// Applies the approved fixes: shows what will change and what can't, requires a backup, then
/// delivers the pilot batch and the rest, verifying each.
struct ApplySheet: View {
  private static let width = 560.0
  private static let minHeight = 480.0
  private static let idealHeight = 640.0

  let session: LogbookSession

  @Environment(\.dismiss)
  private var dismiss
  @State private var model: ApplyModel

  var body: some View {
    Form {
      switch model.step {
        case .preparing:
          ProgressView("Taking a fresh snapshot…")
            .frame(maxWidth: .infinity)
        case .failed(let reason):
          ContentUnavailableView(
            "Couldn’t Prepare the Fixes",
            systemImage: "exclamationmark.triangle",
            description: Text(reason)
          )
        case .ready, .applying, .finished:
          if let plan = model.plan {
            ApplyHeaderSection(session: session, model: model)
            PlanSections(plan: plan, session: session, recordedDates: model.recordedBefore)
            BackupSection(model: model)
            ApplySection(model: model)
          }
      }
    }
    .formStyle(.grouped)
    .frame(width: Self.width)
    .frame(minHeight: Self.minHeight, idealHeight: Self.idealHeight)
    .toolbar { ApplyToolbar(model: model, session: session, dismiss: { dismiss() }) }
    .task { if model.step == .preparing { await model.prepare() } }
    .interactiveDismissDisabled(model.step == .applying)
    .accessibilityIdentifier("applySheet")
  }

  /// Creates the sheet for a session's approved fixes.
  init(session: LogbookSession) {
    self.session = session
    _model = State(initialValue: ApplyModel(session: session))
  }

  /// Creates the sheet with a model that may already be past preparing.
  init(session: LogbookSession, model: ApplyModel) {
    self.session = session
    _model = State(initialValue: model)
  }
}

/// The sheet's buttons.
private struct ApplyToolbar: ToolbarContent {
  let model: ApplyModel
  let session: LogbookSession
  let dismiss: () -> Void

  var body: some ToolbarContent {
    ToolbarItem(placement: .cancellationAction) {
      if model.step == .applying {
        Button("Stop After This Batch") { model.cancel() }
          .disabled(model.isCancelled)
          .accessibilityIdentifier("apply.stop")
      } else {
        Button(model.step == .finished ? "Done" : "Cancel", action: dismiss)
          .accessibilityIdentifier("apply.close")
      }
    }
    ToolbarItem(placement: .secondaryAction) {
      HelpTopicLink(anchor: .applyingFixes, accessibilityIdentifier: "apply.help")
    }
    ToolbarItem(placement: .confirmationAction) {
      switch model.step {
        case .finished:
          Button("Show Applied History", action: showHistory)
            .accessibilityIdentifier("apply.showHistory")
        case .failed:
          Button("Try Again") { Task { await model.prepare() } }
            .accessibilityIdentifier("apply.retry")
        case .preparing, .ready, .applying:
          ApplyButton(model: model, fixCount: session.approvedCorrections.count)
      }
    }
  }

  private func showHistory() {
    session.sidebarSelection = .audit(.appliedHistory)
    session.selectedJournalEntryID = model.lastDeliveredEntryID
    dismiss()
  }
}

/// The button that starts delivery, named for what it does with the packages.
private struct ApplyButton: View {
  let model: ApplyModel
  let fixCount: Int

  var body: some View {
    Button {
      Task { await model.apply() }
    } label: {
      if model.sendsToLogTen {
        Text("Apply \(fixCount) Fixes")
      } else {
        Text("Record \(model.batches.count) Packages")
      }
    }
    .disabled(!model.canApply)
    .accessibilityIdentifier("apply.apply")
  }
}

extension PreviewHelper {
  /**
   An Apply sheet model with the approved fixes planned against the sample logbook.

   - Parameters:
     - session: A loaded session with approved fixes.
     - step: The step to show, after planning.
     - stopped: Whether to show the first batch delivered and the rest stopped.
   */
  static func applyModel(
    in session: LogbookSession,
    at step: ApplyModel.Step = .ready,
    stopped: Bool = false
  ) -> ApplyModel {
    let model = ApplyModel(session: session)
    model.plan(against: sample.logbook)
    if stopped {
      model.showStoppedForPreview()
    } else if step != .ready {
      model.showForPreview(step)
    }
    return model
  }
}

#Preview("Ready", traits: .sampleSession { PreviewHelper.approveCorrections(in: $0) }) {
  @Environment(LogbookSession.self)
  @Previewable var session
  ApplySheet(session: session, model: PreviewHelper.applyModel(in: session))
}

#Preview("Recorded Before", traits: .sampleSession { PreviewHelper.approveAndRecord(3, in: $0) }) {
  @Environment(LogbookSession.self)
  @Previewable var session
  ApplySheet(session: session, model: PreviewHelper.applyModel(in: session))
}

#Preview("Applying", traits: .sampleSession { PreviewHelper.approveCorrections(in: $0) }) {
  @Environment(LogbookSession.self)
  @Previewable var session
  ApplySheet(session: session, model: PreviewHelper.applyModel(in: session, at: .applying))
}

#Preview("Finished", traits: .sampleSession { PreviewHelper.approveCorrections(in: $0) }) {
  @Environment(LogbookSession.self)
  @Previewable var session
  ApplySheet(session: session, model: PreviewHelper.applyModel(in: session, at: .finished))
}

#Preview("Stopped", traits: .sampleSession { PreviewHelper.approveCorrections(in: $0) }) {
  @Environment(LogbookSession.self)
  @Previewable var session
  ApplySheet(session: session, model: PreviewHelper.applyModel(in: session, stopped: true))
}

#Preview("Failed", traits: .sampleSession { PreviewHelper.approveCorrections(in: $0) }) {
  @Environment(LogbookSession.self)
  @Previewable var session
  ApplySheet(
    session: session,
    model: PreviewHelper.applyModel(
      in: session,
      at: .failed("The logbook changed while the fixes were being prepared.")
    )
  )
}
