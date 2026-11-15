import FlightSources
import Foundation
import Observation
import SwiftUI

/// Audit ▸ Upload Data Logs to FlySto…: choose logs, watch FlySto take them, then sync.
struct UploadLogsSheet: View {
  @Environment(\.dismiss)
  private var dismiss
  @State private var model: UploadLogsModel

  let session: LogbookSession

  private var hasUploaded: Bool { !model.uploads.isEmpty && !model.isUploading }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Upload Data Logs to FlySto")
        .font(.headline)
        .padding([.top, .horizontal])
      Form {
        Section {
          if model.uploads.isEmpty {
            Text(
              "Choose the data logs your avionics recorded. FlySto parses them, and the next sync brings the results here."
            )
            .foregroundStyle(.secondary)
          }
          ForEach(model.uploads) { upload in
            LabeledContent(upload.file.lastPathComponent) {
              Text(upload.state.title)
            }
          }
        }
      }
      .formStyle(.grouped)
    }
    .frame(width: 480)
    .interactiveDismissDisabled(model.isUploading)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        if model.isUploading {
          Button("Stop") { model.cancel() }
            .accessibilityIdentifier("uploadLogs.stop")
        } else {
          Button("Close") { dismiss() }
            .accessibilityIdentifier("uploadLogs.close")
        }
      }
      ToolbarItem(placement: .confirmationAction) {
        if hasUploaded {
          Button("Sync FlySto") {
            dismiss()
            Task { await session.syncFlySto() }
          }
          .accessibilityIdentifier("uploadLogs.sync")
        } else {
          Button("Choose Logs…") { model.upload(FilePanels.chooseDataLogs()) }
            .disabled(model.isUploading)
            .accessibilityIdentifier("uploadLogs.choose")
        }
      }
    }
  }

  /// Creates the sheet for a session.
  init(session: LogbookSession) {
    self.session = session
    _model = State(initialValue: UploadLogsModel(client: session.services.flySto()))
  }
}

extension UploadLogsModel.State {
  fileprivate var title: String {
    switch self {
      case .waiting: String(localized: "Waiting")
      case .uploading: String(localized: "Uploading…")
      case .processed(let count): String(localized: "\(count, format: .number) logs")
      case .alreadyUploaded: String(localized: "Already in FlySto")
      case .pending: String(localized: "Still processing")
      case .failed(let reason): reason
    }
  }
}

#Preview("No Logs Chosen", traits: .sampleSession()) {
  @Environment(LogbookSession.self)
  @Previewable var session
  UploadLogsSheet(session: session)
}
