import GitHubUpdateChecker
import SwiftUI

/// Settings ▸ Updates: how often the app looks for a new release, and controls to check now or
/// reconsider a skipped version.
struct UpdatesSettingsView: View {
  let updates: GitHubUpdates

  var body: some View {
    @Bindable var preferences = updates.checker.preferences
    Form {
      Picker("Check for updates", selection: $preferences.updateCadence) {
        ForEach(UpdateCadence.allCases, id: \.self) { cadence in
          Text(cadence.title).tag(cadence)
        }
      }
      .accessibilityIdentifier("settings.updateCadence")
      Toggle("Include prerelease versions", isOn: $preferences.checkForPrereleases)
        .accessibilityIdentifier("settings.updatePrereleases")
      LabeledContent("Last checked") {
        LastCheckedLabel(date: updates.checker.lastCheckDate)
      }
      HStack {
        Button("Check Now") { Task { await updates.checkForUpdatesAndShowUI() } }
          .disabled(!updates.checker.canCheckForUpdates)
          .accessibilityIdentifier("settings.checkForUpdates")
        Spacer(minLength: 0)
        Button("Reset Skipped Versions") { preferences.resetSkippedVersions() }
          .disabled(preferences.skippedVersions.isEmpty)
          .accessibilityIdentifier("settings.resetSkippedVersions")
      }
    }
    .formStyle(.grouped)
    .scrollDisabled(true)
    .fixedSize(horizontal: false, vertical: true)
  }
}

/// When the last check ran, or a dash before the first one has.
private struct LastCheckedLabel: View {
  let date: Date?

  var body: some View {
    Group {
      if let date {
        Text(date, format: .relative(presentation: .named))
      } else {
        Text(verbatim: "—")
      }
    }
    .foregroundStyle(.secondary)
  }
}

extension UpdateCadence {
  /// The cadence's name in the Updates picker.
  fileprivate var title: String {
    switch self {
      case .hourly: String(localized: "Hourly")
      case .daily: String(localized: "Daily")
      case .weekly: String(localized: "Weekly")
      case .never: String(localized: "Never")
    }
  }
}

#Preview("Updates") {
  SettingsPanePreview { UpdatesSettingsView(updates: GitHubUpdates()) }
}
