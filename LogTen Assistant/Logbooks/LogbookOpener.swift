import AppKit
import SwiftUI

/// Opens logbooks in their windows, from the Open window, Open Recent or the File menu.
struct LogbookOpener {
  /// The identifier of the Open Logbook window.
  static let openWindowID = "open-logbook"

  let library: LogbookLibrary
  let openWindow: OpenWindowAction
  let dismissWindow: DismissWindowAction

  /// Carries out a request to open logbooks.
  func callAsFunction(_ request: LogbookOpenRequest) {
    switch request {
      case .reference(let reference):
        open(reference)
      case .chooseFolder(let directory):
        Task { await chooseAndOpen(startingAt: directory) }
    }
  }

  private func chooseAndOpen(startingAt directory: URL?) async {
    do {
      for reference in try await library.chooseLogbooks(startingAt: directory) {
        open(reference)
      }
    } catch {
      NSAlert(error: error).runModal()
    }
  }

  private func open(_ reference: LogbookReference) {
    library.noteOpened(reference)
    openWindow(value: reference)
    dismissWindow(id: Self.openWindowID)
  }
}

/// A request to open logbooks.
enum LogbookOpenRequest {
  /// Ask the user to choose a folder, starting the Open panel in a directory.
  case chooseFolder(startingAt: URL?)

  /// Open a logbook the user has opened before.
  case reference(LogbookReference)
}

extension EnvironmentValues {
  /// Opens logbooks; `nil` outside a scene that provides it.
  @Entry var openLogbook: LogbookOpener?
}

/// Provides `openLogbook` to a scene's views.
struct ProvidesLogbookOpener: ViewModifier {
  @Environment(LogbookLibrary.self)
  private var library
  @Environment(\.openWindow)
  private var openWindow
  @Environment(\.dismissWindow)
  private var dismissWindow

  func body(content: Content) -> some View {
    content.environment(
      \.openLogbook,
      LogbookOpener(library: library, openWindow: openWindow, dismissWindow: dismissWindow)
    )
  }
}
