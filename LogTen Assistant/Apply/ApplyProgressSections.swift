import Corrections
import SwiftUI

/// The mandatory backup.
struct BackupSection: View {
  @Bindable var model: ApplyModel

  var body: some View {
    Section {
      if let backup = model.backup {
        LabeledContent("Backup") {
          Text(
            "\(backup.files.count) files, \(backup.createdAt.formatted(date: .abbreviated, time: .standard))"
          )
        }
        .accessibilityIdentifier("apply.backupDone")
      } else if model.isBackingUp {
        ProgressView("Backing up the logbook…").progressViewStyle(.linear)
      } else {
        Button("Back Up Logbook") { Task { await model.backUp() } }
          .disabled(model.step != .ready)
          .accessibilityIdentifier("apply.backUp")
      }
      LogTenBackupToggle(
        isOn: $model.confirmsLogTenBackup,
        identifier: "apply.confirmsLogTenBackup"
      )
      .disabled(model.step != .ready)
    } header: {
      Text("Back Up")
    } footer: {
      Text(
        "The app copies the logbook’s folder first. To back up in LogTen, choose View ▸ Backups and click +. LogTen’s backups are the supported way to restore, since LogTen syncs changes to your other devices."
      )
      .foregroundStyle(.secondary)
    }
  }
}

/// The acknowledgement that the user backed up in LogTen’s Backups view.
struct LogTenBackupToggle: View {
  @Binding var isOn: Bool
  let identifier: String

  var body: some View {
    Toggle("I made a backup in LogTen’s Backups view", isOn: $isOn)
      .accessibilityIdentifier(identifier)
  }
}

/// The batches, pilot first, and where each stands.
struct ApplySection: View {
  let model: ApplyModel

  var body: some View {
    Section {
      if model.step == .applying {
        ProgressView(
          value: Double(model.deliveredCount),
          total: Double(max(1, model.batches.count))
        )
      }
      ForEach(Array(model.batches.enumerated()), id: \.element.id) { index, batch in
        LabeledContent {
          Text(batch.state.title)
        } label: {
          Text(
            "Batch \(index + 1, format: .number) · \(batch.batch.recordIDs.count) flights"
          )
        }
        .accessibilityIdentifier("apply.batch.\(index)")
      }
    } header: {
      Text("Apply")
    } footer: {
      if model.stoppedCount > 0 {
        StoppedNote(count: model.stoppedCount)
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("apply.stoppedNote")
      } else if model.sendsToLogTen {
        Text(
          "LogTen asks you to confirm each import. The first batch is a single flight, so a problem shows up before the rest are sent."
        )
        .foregroundStyle(.secondary)
      }
    }
  }
}

/// How many batches a stopped run left unapplied, and that their fixes stay approved.
private struct StoppedNote: View {
  let count: Int

  var body: some View {
    if count == 1 {
      Text("1 batch not applied. Its fixes are still approved; apply them later from Approved.")
    } else {
      Text(
        "\(count, format: .number) batches not applied. Their fixes are still approved; apply them later from Approved."
      )
    }
  }
}

extension BatchProgress.State {
  fileprivate var title: String {
    switch self {
      case .pending: String(localized: "Waiting")
      case .stopped: String(localized: "Not applied")
      case .recording: String(localized: "Recording…")
      case .waitingForLogTen: String(localized: "Waiting for LogTen…")
      case .finished(.delivered): String(localized: "Recorded")
      case .finished(let status): status.title
      case .error(let reason): reason
    }
  }
}

#Preview("Backup and Apply", traits: .sampleSession { PreviewHelper.approveCorrections(in: $0) }) {
  @Environment(LogbookSession.self)
  @Previewable var session
  ApplySheet(session: session, model: PreviewHelper.applyModel(in: session))
    .defaultScrollAnchor(.bottom)
}
