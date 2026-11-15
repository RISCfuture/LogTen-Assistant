import SwiftUI

@main
struct LogTenAssistantApp: App {
  @State private var library = LogbookLibrary()
  @State private var updates: GitHubUpdates
  @State private var undoMenu = UndoMenuState()

  var body: some Scene {
    Window("Open Logbook", id: LogbookOpener.openWindowID) {
      OpenLogbookView()
        .modifier(OpensLaunchFixture())
        .modifier(ProvidesLogbookOpener())
        .environment(library)
    }
    .defaultSize(width: 640, height: 400)
    .windowResizability(.contentSize)
    .restorationBehavior(.disabled)
    .defaultLaunchBehavior(LaunchEnvironment.isRunningForPreviews ? .suppressed : .automatic)
    .commands {
      LogbookCommands(library: library)
      UndoCommands(menu: undoMenu)
      AppInfoCommands(updates: updates)
    }

    WindowGroup(for: LogbookReference.self) { $reference in
      LogbookWindowRoot(reference: $reference)
        .modifier(ProvidesLogbookOpener())
        .environment(library)
    }
    .defaultSize(LogbookSplitView.defaultWindowSize)
    .defaultLaunchBehavior(.suppressed)

    Window("About LogTen Assistant", id: AboutWindow.id) {
      AboutView()
    }
    .windowResizability(.contentSize)
    .restorationBehavior(.disabled)
    .defaultLaunchBehavior(.suppressed)

    Settings {
      AppSettingsView(updates: updates)
    }
  }

  init() {
    let updates = GitHubUpdates()
    _updates = State(initialValue: updates)
    guard LaunchEnvironment.allowsBackgroundNetworking else { return }
    CrashReporting.start()
    updates.startAutomaticChecks()
  }
}

/// A logbook window's root, which falls back to the Open view if it has no logbook.
private struct LogbookWindowRoot: View {
  @Binding var reference: LogbookReference?

  var body: some View {
    if let binding = Binding($reference) {
      LogbookWindow(reference: binding)
    } else {
      OpenLogbookView()
    }
  }
}

/// Opens the sample logbook named by the `-UITestFixture` launch argument, in debug builds.
private struct OpensLaunchFixture: ViewModifier {
  private static let argumentName = "UITestFixture"

  @Environment(\.openLogbook)
  private var openLogbook

  func body(content: Content) -> some View {
    content.task {
      #if DEBUG
        guard let name = UserDefaults.standard.string(forKey: Self.argumentName),
          SampleLogbook(named: name) != nil
        else { return }
        openLogbook?(.reference(SampleLogbook.reference))
      #endif
    }
  }
}
