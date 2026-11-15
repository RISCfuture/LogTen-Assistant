import GitHubUpdateChecker
import SwiftUI

/// The About and Check for Updates items in the app menu, and the Help menu's links to the
/// website and the issue tracker.
struct AppInfoCommands: Commands {
  let updates: GitHubUpdates

  var body: some Commands {
    CommandGroup(replacing: .appInfo) {
      AboutMenuButton()
    }
    CommandGroup(after: .appInfo) {
      UpdateMenuButton(updates: updates)
    }
    CommandGroup(after: .help) {
      Divider()
      Link("LogTen Assistant Website", destination: AppLinks.website)
      Link("Report an Issue…", destination: AppLinks.issues)
    }
  }
}

/// The custom “About LogTen Assistant” item, which opens the About window.
private struct AboutMenuButton: View {
  @Environment(\.openWindow)
  private var openWindow

  var body: some View {
    Button("About LogTen Assistant") { openWindow(id: AboutWindow.id) }
  }
}

/// The “Check for Updates…” item. The checker presents its own result window.
private struct UpdateMenuButton: View {
  let updates: GitHubUpdates

  var body: some View {
    Button("Check for Updates…") { Task { await updates.checkForUpdatesAndShowUI() } }
      .disabled(!updates.checker.canCheckForUpdates)
  }
}
