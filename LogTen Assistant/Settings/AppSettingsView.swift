import SwiftUI

/// The app-wide Settings window (⌘,). Settings for one logbook are in its Logbook Settings
/// sheet instead.
struct AppSettingsView: View {
  /// The width of every pane: each is a grouped form that sets its own height.
  static let width: CGFloat = 460

  let updates: GitHubUpdates

  @AppStorage(SettingsTab.storageKey)
  private var tab = SettingsTab.accounts

  var body: some View {
    TabView(selection: $tab) {
      Tab("Accounts", systemImage: "person.crop.circle", value: SettingsTab.accounts) {
        AccountsSettingsView()
      }
      Tab("Data", systemImage: "externaldrive", value: SettingsTab.data) {
        DataSettingsView()
      }
      Tab("Track Detection", systemImage: "airplane.departure", value: SettingsTab.trackDetection) {
        TrackDetectionSettingsView()
      }
      Tab("Updates", systemImage: "arrow.down.circle", value: SettingsTab.updates) {
        UpdatesSettingsView(updates: updates)
      }
      Tab("Advanced", systemImage: "gearshape.2", value: SettingsTab.advanced) {
        AdvancedSettingsView()
      }
    }
    .frame(width: Self.width)
    .safeAreaInset(edge: .bottom, alignment: .trailing) {
      HelpTopicLink(anchor: helpAnchor, accessibilityIdentifier: "settings.help")
        .padding([.trailing, .bottom])
    }
  }

  private var helpAnchor: HelpAnchor {
    switch tab {
      case .accounts: .flySto
      case .data: .adsbData
      case .trackDetection: .appSettings
      case .updates: .updates
      case .advanced: .applyingFixes
    }
  }
}

/// The keys of app-wide settings in user defaults.
nonisolated enum AppSettingsKey {
  static let adsbCacheLimitGB = "ADSBCacheLimitGB"
  static let updatesNASRAutomatically = "UpdatesNASRAutomatically"
  static let showsFindingIDs = "ShowsFindingIDs"
  static let writerMode = "WriterMode"
  static let trackAirborneKts = "TrackDetectionAirborneKts"
  static let trackGroundKts = "TrackDetectionGroundKts"
  static let trackConfirmSeconds = "TrackDetectionConfirmSeconds"
  static let trackStopSeconds = "TrackDetectionStopSeconds"
  static let trackGapSeconds = "TrackDetectionGapSeconds"
}

#Preview("Settings Window") {
  AppSettingsView(updates: GitHubUpdates())
}
