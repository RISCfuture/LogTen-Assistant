import Foundation

/// What launched the app: a normal run, Xcode rendering previews, or a UI test.
nonisolated enum LaunchEnvironment {
  /// Whether Xcode launched the app to render previews, which show no window of the app's own.
  static var isRunningForPreviews: Bool {
    ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
  }

  /// Whether a debug build was launched with the `-UITestFixture`, `-UITestStubs` or `-UITestRun`
  /// argument.
  static var isRunningUITests: Bool {
    #if DEBUG
      ["UITestFixture", "UITestStubs", "UITestRun"].contains {
        UserDefaults.standard.string(forKey: $0) != nil
      }
    #else
      false
    #endif
  }

  /// How long a debug build pauses while loading a sample logbook, set in seconds by the
  /// `-UITestLoadDelay` argument, so UI tests can watch the audit run.
  static var fixtureLoadDelay: Duration {
    #if DEBUG
      .seconds(UserDefaults.standard.double(forKey: "UITestLoadDelay"))
    #else
      .zero
    #endif
  }

  /// Whether the app should reach the network on its own: for crash reports and update checks.
  static var allowsBackgroundNetworking: Bool { !isRunningForPreviews && !isRunningUITests }
}
