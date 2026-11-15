import AppKit
import Observation
import SwiftUI

/// Edit ▸ Undo and Redo, named for the action they would undo or redo, such as “Undo Keep as
/// Logged”. They act on the key window's responder chain, as the standard items do.
struct UndoCommands: Commands {
  let menu: UndoMenuState

  var body: some Commands {
    CommandGroup(replacing: .undoRedo) {
      Button(menu.undoTitle) { NSApp.sendAction(Selector(("undo:")), to: nil, from: nil) }
        .keyboardShortcut("z")
        .disabled(!menu.canUndo)
      Button(menu.redoTitle) { NSApp.sendAction(Selector(("redo:")), to: nil, from: nil) }
        .keyboardShortcut("z", modifiers: [.command, .shift])
        .disabled(!menu.canRedo)
    }
  }
}

/// The titles and availability of Undo and Redo for the key window, kept current as undo
/// managers change and windows become key.
@MainActor
@Observable
final class UndoMenuState {
  private static let changes: [Notification.Name] = [
    .NSUndoManagerCheckpoint, .NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange,
    .NSUndoManagerDidCloseUndoGroup, NSWindow.didBecomeKeyNotification,
    NSWindow.didResignKeyNotification
  ]

  private(set) var undoTitle = String(localized: "Undo")
  private(set) var redoTitle = String(localized: "Redo")
  private(set) var canUndo = false
  private(set) var canRedo = false

  @ObservationIgnored private var observers = [any NSObjectProtocol]()

  private var keyUndoManager: UndoManager? {
    let window = NSApp.keyWindow
    return (window?.firstResponder ?? window)?.undoManager
  }

  init() {
    observers = Self.changes.map { name in
      NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) {
        [weak self] _ in
        MainActor.assumeIsolated { self?.refresh() }
      }
    }
  }

  private func refresh() {
    let manager = keyUndoManager
    update(\.undoTitle, to: manager?.undoMenuItemTitle ?? String(localized: "Undo"))
    update(\.redoTitle, to: manager?.redoMenuItemTitle ?? String(localized: "Redo"))
    update(\.canUndo, to: manager?.canUndo ?? false)
    update(\.canRedo, to: manager?.canRedo ?? false)
  }

  /// Sets a property only when its value changes, so checkpoints that change nothing don't
  /// rebuild the menus.
  private func update<Value: Equatable>(
    _ property: ReferenceWritableKeyPath<UndoMenuState, Value>,
    to value: Value
  ) {
    if self[keyPath: property] != value { self[keyPath: property] = value }
  }
}
