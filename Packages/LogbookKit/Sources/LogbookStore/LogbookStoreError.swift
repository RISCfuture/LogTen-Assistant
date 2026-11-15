public import Foundation
public import LogbookModel

/// An error locating, snapshotting or reading a LogTen logbook.
public enum LogbookStoreError: Error, Equatable {
  /// LogTen's data model couldn't be loaded, usually because LogTen isn't installed.
  case modelUnavailable(URL)

  /// The store was written by a LogTen version whose data model differs from the installed one.
  case modelMismatch(storeVersions: [String], installedVersions: [String])

  /// The folder contains no LogTen logbook.
  case noLogbookFound(URL)

  /// The store couldn't be opened or read.
  case unreadableStore(URL, reason: String)

  /// The store kept changing while it was being copied.
  case sourceKeptChanging(URL)

  /// SQLite found the copied store damaged.
  case integrityCheckFailed(URL, messages: [String])

  /// A smart group's predicate couldn't be parsed or evaluated.
  case invalidPredicate(String, reason: String)

  /// A field mapping names a field the installed LogTen model doesn't have.
  case unknownField(LogTenFieldKey)
}

extension LogbookStoreError: LocalizedError {
  public var errorDescription: String? {
    switch self {
      case .modelUnavailable, .modelMismatch:
        String(localized: "Couldn’t load LogTen’s data model.", bundle: .module)
      case .noLogbookFound, .unreadableStore, .unknownField:
        String(localized: "Couldn’t read the logbook.", bundle: .module)
      case .sourceKeptChanging, .integrityCheckFailed:
        String(localized: "Couldn’t make a snapshot of the logbook.", bundle: .module)
      case .invalidPredicate:
        String(localized: "Couldn’t evaluate the smart group.", bundle: .module)
    }
  }

  public var failureReason: String? {
    switch self {
      case .modelUnavailable(let url):
        String(
          localized: "No LogTen data model was found at “\(url.path(percentEncoded: false))”.",
          bundle: .module
        )
      case let .modelMismatch(storeVersions, installedVersions):
        String(
          localized: """
            The logbook uses data model “\(storeVersions.formatted(.list(type: .and)))”, but the \
            installed LogTen uses “\(installedVersions.formatted(.list(type: .and)))”.
            """,
          bundle: .module
        )
      case .noLogbookFound(let url):
        String(
          localized: "“\(url.lastPathComponent)” doesn’t contain a LogTen logbook.",
          bundle: .module
        )
      case let .unreadableStore(url, reason):
        String(
          localized: "“\(url.lastPathComponent)” couldn’t be opened: \(reason)",
          bundle: .module
        )
      case .sourceKeptChanging(let url):
        String(
          localized: "“\(url.lastPathComponent)” changed every time it was copied.",
          bundle: .module
        )
      case let .integrityCheckFailed(url, messages):
        String(
          localized:
            "SQLite reported problems in the copy of “\(url.lastPathComponent)”: \(messages.formatted(.list(type: .and)))",
          bundle: .module
        )
      case let .invalidPredicate(format, reason):
        String(localized: "The predicate “\(format)” is invalid: \(reason)", bundle: .module)
      case .unknownField(let key):
        String(localized: "LogTen has no field named “\(key.rawValue)”.", bundle: .module)
    }
  }

  public var recoverySuggestion: String? {
    switch self {
      case .modelUnavailable:
        String(localized: "Install LogTen in the Applications folder.", bundle: .module)
      case .modelMismatch:
        String(
          localized: "Update LogTen on this Mac to the version that last opened the logbook.",
          bundle: .module
        )
      case .noLogbookFound:
        String(
          localized: "Choose the LogTen group container or a “LogTenProData” folder inside it.",
          bundle: .module
        )
      case .sourceKeptChanging:
        String(localized: "Wait for LogTen to finish syncing, then try again.", bundle: .module)
      case .unknownField:
        String(localized: "Choose a different field in Logbook Settings.", bundle: .module)
      case .unreadableStore, .integrityCheckFailed, .invalidPredicate:
        nil
    }
  }
}
