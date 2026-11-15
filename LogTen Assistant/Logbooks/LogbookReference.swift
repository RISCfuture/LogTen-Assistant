import Foundation
import LogbookStore

/// A logbook the user opened: a security-scoped bookmark to the folder they chose, and which
/// logbook inside it to read.
///
/// A logbook window's value is a reference, so each logbook has at most one window and windows
/// are restored on relaunch. Two references to the same logbook folder are equal, whatever else
/// they record.
nonisolated struct LogbookReference: Codable, Hashable, Identifiable, Sendable {
  private static let logbookFolderPrefix = "LogTenProData_"

  /// The name of a logbook whose owner isn't known.
  static var genericName: String { String(localized: "LogTen Pro Logbook") }

  /// Where the logbook's records come from.
  var source: Source

  /// The name to show for the logbook, such as its owner’s name.
  var displayName: String

  /// The logbook's store UUID, once it has been read.
  var storeUUID: UUID?

  /// When the logbook was last opened.
  var lastOpened: Date

  var id: String {
    switch source {
      case let .bookmark(_, folderPath, logbookFolderName):
        logbookFolderName.map { "\(folderPath)/\($0)" } ?? folderPath
      case .fixture(let name): "fixture:\(name)"
    }
  }

  /// Whether the logbook is in LogTen's own group container.
  var isDefaultLogbook: Bool {
    path?.hasPrefix(LogbookLocation.defaultGroupContainerURL.path(percentEncoded: false)) == true
  }

  /// The name shown for the logbook everywhere: its window, headers, exported file names and
  /// the recents list. It's ``displayName``, except that a logbook with only the generic name
  /// takes the name of its folder unless it's in LogTen's group container, so it differs from
  /// the default logbook.
  var title: String {
    guard hasGenericName, !isDefaultLogbook, let path else { return shownDisplayName }
    return URL(filePath: path).lastPathComponent
  }

  private var shownDisplayName: String {
    displayName.hasPrefix(Self.logbookFolderPrefix) ? Self.genericName : displayName
  }

  private var hasGenericName: Bool { shownDisplayName == Self.genericName }

  /// Whether the logbook is real, as opposed to a sample for UI tests.
  var isBookmarked: Bool {
    if case .bookmark = source { true } else { false }
  }

  /// The path of the logbook's folder, for display.
  var path: String? {
    guard case .bookmark = source else { return nil }
    return URL(filePath: id).standardizedFileURL.path(percentEncoded: false)
  }

  /// Creates a reference to a logbook in a folder the user chose.
  ///
  /// - Parameters:
  ///   - logbook: The logbook.
  ///   - folder: The folder the user chose, which is the logbook's folder or contains it.
  ///   - bookmark: A security-scoped bookmark to `folder`.
  init(logbook: LogbookLocation, in folder: URL, bookmark: Data) {
    let isNested = logbook.directory.standardizedFileURL != folder.standardizedFileURL
    source = .bookmark(
      bookmark,
      folderPath: folder.path(percentEncoded: false),
      logbookFolderName: isNested ? logbook.directory.lastPathComponent : nil
    )
    displayName = Self.genericName
    lastOpened = .now
  }

  /// Creates a reference to a built-in sample logbook.
  init(fixture name: String, displayName: String) {
    source = .fixture(name)
    self.displayName = displayName
    lastOpened = .now
  }

  static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }

  func hash(into hasher: inout Hasher) { hasher.combine(id) }

  /// Where a logbook's records come from.
  enum Source: Codable, Sendable {
    /// A folder the user chose, kept as a security-scoped bookmark; `logbookFolderName` names
    /// the `LogTenProData_<id>` folder inside it when the user chose a folder containing several.
    case bookmark(Data, folderPath: String, logbookFolderName: String?)

    /// A built-in sample logbook, for previews and UI tests.
    case fixture(String)
  }
}

// MARK: - Bookmarks

nonisolated extension LogbookReference {
  /// Creates a security-scoped, read-only bookmark to a folder.
  static func bookmark(for folder: URL) throws -> Data {
    try folder.bookmarkData(
      options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
      includingResourceValuesForKeys: nil,
      relativeTo: nil
    )
  }

  /**
   Resolves the bookmark to the folder the user chose.

   - Returns: The folder, which the caller must access with
     `startAccessingSecurityScopedResource()`, and a fresh bookmark if the stored one is stale.
   - Throws: ``LogbookOpeningError/notBookmarked`` for a sample logbook, or the error resolving
     the bookmark.
   */
  func resolvedFolder() throws -> (folder: URL, refreshedBookmark: Data?) {
    guard case .bookmark(let data, _, _) = source else { throw LogbookOpeningError.notBookmarked }
    var isStale = false
    let folder = try URL(
      resolvingBookmarkData: data,
      options: [.withSecurityScope],
      relativeTo: nil,
      bookmarkDataIsStale: &isStale
    )
    return (folder, isStale ? try Self.bookmark(for: folder) : nil)
  }

  /// The logbook inside a resolved folder.
  func location(in folder: URL) -> LogbookLocation {
    guard case .bookmark(_, _, let name?) = source else {
      return LogbookLocation(directory: folder)
    }
    return LogbookLocation(directory: folder.appending(path: name, directoryHint: .isDirectory))
  }

  /// Returns the reference with a replacement bookmark.
  func replacingBookmark(_ bookmark: Data) -> Self {
    guard case let .bookmark(_, folderPath, logbookFolderName) = source else { return self }
    var reference = self
    reference.source = .bookmark(
      bookmark,
      folderPath: folderPath,
      logbookFolderName: logbookFolderName
    )
    return reference
  }
}

/// An error opening a logbook.
nonisolated enum LogbookOpeningError: Error {
  /// The reference names a sample logbook, which has no bookmark.
  case notBookmarked

  /// The sample logbook named in a launch argument doesn't exist.
  case unknownFixture(String)
}

nonisolated extension LogbookOpeningError: LocalizedError {
  var errorDescription: String? { String(localized: "Couldn’t open the logbook.") }

  var failureReason: String? {
    switch self {
      case .notBookmarked:
        String(localized: "The logbook isn’t a folder on disk.")
      case .unknownFixture(let name):
        String(localized: "There’s no sample logbook named “\(name)”.")
    }
  }
}
