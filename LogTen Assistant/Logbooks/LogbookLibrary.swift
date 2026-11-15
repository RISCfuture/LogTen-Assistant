import AppKit
import Foundation
import LogbookStore
import Observation

/// The logbooks the user has opened, and the Open panel that adds to them.
///
/// The app doesn't own LogTen's files, so it keeps its own Open Recent list of bookmarks
/// instead of using the document system's.
@Observable
final class LogbookLibrary {
  private static let defaultsKey = "RecentLogbooks"
  private static let maximumRecents = 10

  /// Recently opened logbooks, most recent first.
  private(set) var recents: [LogbookReference]

  @ObservationIgnored private let defaults: UserDefaults

  /// Creates a library that keeps its list in a defaults domain.
  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    recents = Self.load(from: defaults)
  }

  private static func load(from defaults: UserDefaults) -> [LogbookReference] {
    guard let data = defaults.data(forKey: defaultsKey) else { return [] }
    return (try? JSONDecoder().decode([LogbookReference].self, from: data)) ?? []
  }

  /// Records that a logbook was opened, moving it to the top of Open Recent.
  func noteOpened(_ reference: LogbookReference) {
    guard reference.isBookmarked else { return }
    var reference = reference
    reference.lastOpened = .now
    recents.removeAll { $0 == reference }
    recents.insert(reference, at: 0)
    recents = Array(recents.prefix(Self.maximumRecents))
    save()
  }

  /// Updates what Open Recent shows for a logbook, without reordering the list.
  func update(_ reference: LogbookReference) {
    guard let index = recents.firstIndex(of: reference) else { return }
    recents[index] = reference
    save()
  }

  /// Removes one logbook from Open Recent.
  func remove(_ reference: LogbookReference) {
    recents.removeAll { $0 == reference }
    save()
  }

  /// Empties Open Recent.
  func clearRecents() {
    recents = []
    save()
  }

  private func save() {
    guard let data = try? JSONEncoder().encode(recents) else { return }
    defaults.set(data, forKey: Self.defaultsKey)
  }
}

// MARK: - Open panel

extension LogbookLibrary {
  /**
   Asks the user to choose a logbook folder and returns the logbooks in it.

   The user must choose a folder, not the store file: SQLite needs the write-ahead log and
   shared-memory files next to the store, and only a folder grant covers them.

   - Parameter startingAt: The folder the panel shows first, such as LogTen's group container.
   - Returns: References to the logbooks in the chosen folder, or none if the user cancelled.
   - Throws: ``LogbookStoreError/noLogbookFound(_:)`` if the folder holds no logbook, or an
     error creating the bookmark.
   */
  func chooseLogbooks(startingAt directory: URL? = nil) async throws -> [LogbookReference] {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.directoryURL = directory
    panel.prompt = String(localized: "Open")
    panel.message = String(
      localized: "Choose LogTen’s “group.com.coradine.LogTenPro” folder or a LogTenProData folder."
    )
    guard await panel.begin() == .OK, let folder = panel.url else { return [] }
    return try references(in: folder)
  }

  /// Returns references to the logbooks in a folder the user chose.
  private func references(in folder: URL) throws -> [LogbookReference] {
    let accessing = folder.startAccessingSecurityScopedResource()
    defer { if accessing { folder.stopAccessingSecurityScopedResource() } }
    let bookmark = try LogbookReference.bookmark(for: folder)
    return try LogbookLocation.logbooks(in: folder).map {
      LogbookReference(logbook: $0, in: folder, bookmark: bookmark)
    }
  }
}
