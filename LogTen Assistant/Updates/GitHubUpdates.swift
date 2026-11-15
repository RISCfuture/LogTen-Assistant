import GitHubUpdateChecker
import Observation

/// The app's update checker, which finds new releases on GitHub and installs the `.dmg` each
/// one carries.
@MainActor
@Observable
final class GitHubUpdates {
  private static let owner = "RISCfuture"
  private static let repo = "LogTen-Assistant"
  private static let diskImagePattern = #".*\.dmg$"#

  /// The checker, whose state and preferences the Updates settings observe.
  let checker: GitHubUpdateChecker

  init() {
    checker = GitHubUpdateChecker(owner: Self.owner, repo: Self.repo)
    checker.assetPattern = Self.diskImagePattern
  }

  /// Starts checking on the user's chosen cadence, for as long as the app runs.
  func startAutomaticChecks() { checker.startAutomaticChecks() }

  /// Checks now and presents the result: the update offer, a note that the app is current, or
  /// an error.
  func checkForUpdatesAndShowUI() async { await checker.checkForUpdatesAndShowUI() }
}
