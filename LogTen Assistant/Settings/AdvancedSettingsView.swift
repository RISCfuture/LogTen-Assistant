import SwiftUI

/// How approved fixes reach the logbook.
nonisolated enum WriterMode: String, CaseIterable {
  /// Packages are written to disk for inspection and never sent to LogTen.
  case recordPackages = "record_packages"

  /// Packages are sent to LogTen through `logten://` links, after a backup.
  case sendToLogTen = "send_to_logten"

  var title: String {
    switch self {
      case .recordPackages: String(localized: "Record the import packages")
      case .sendToLogTen: String(localized: "Send them to LogTen")
    }
  }
}

/// Settings ▸ Advanced.
struct AdvancedSettingsView: View {
  @AppStorage(AppSettingsKey.showsFindingIDs)
  private var showsFindingIDs = false
  @AppStorage(AppSettingsKey.writerMode)
  private var writerMode = WriterMode.recordPackages
  @AppStorage(WriterPolicy.disposableLogbookKey)
  private var hasDisposableLogbook = false

  private var isRecording: Bool { writerMode == .recordPackages || !hasDisposableLogbook }

  var body: some View {
    Form {
      Section {
        Picker("When applying fixes", selection: $writerMode) {
          ForEach(WriterMode.allCases, id: \.self) { mode in
            Text(mode.title)
              .tag(mode)
              .disabled(mode == .sendToLogTen && !hasDisposableLogbook)
          }
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("settings.writerMode")
      } footer: {
        WriterModeFooter(isRecording: isRecording, canSend: hasDisposableLogbook)
      }
      Section("Troubleshooting") {
        Toggle(isOn: $showsFindingIDs) {
          Text("Show finding IDs")
          Text("Adds each finding’s identifier to the inspector.")
        }
        .accessibilityIdentifier("settings.showsFindingIDs")
      }
    }
    .formStyle(.grouped)
    .scrollDisabled(true)
    .fixedSize(horizontal: false, vertical: true)
  }
}

/// Where recorded packages go, and why sending is unavailable when it is.
private struct WriterModeFooter: View {
  let isRecording: Bool
  let canSend: Bool

  var body: some View {
    VStack(alignment: .leading) {
      if isRecording {
        Text("Packages are recorded in the logbook’s workspace folder for review.")
      }
      if !canSend {
        Text("Sending needs a disposable test logbook open in LogTen.")
      }
    }
    .font(.caption)
    .foregroundStyle(.secondary)
  }
}

#Preview("Advanced") {
  SettingsPanePreview { AdvancedSettingsView() }
}
