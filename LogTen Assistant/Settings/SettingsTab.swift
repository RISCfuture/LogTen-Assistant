/// A pane of the app's Settings window.
nonisolated enum SettingsTab: String, CaseIterable, Sendable {
  case accounts
  case data
  case trackDetection
  case updates
  case advanced

  /// The user-defaults key under which the Settings window keeps the pane it last showed.
  static let storageKey = "SettingsTab"
}
