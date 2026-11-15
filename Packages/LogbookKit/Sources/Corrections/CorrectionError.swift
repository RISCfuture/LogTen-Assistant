public import Foundation
public import LogbookModel

/// Why corrections couldn't be proposed, packaged or delivered.
public enum CorrectionError: Error, Hashable, Sendable {
  /// No findings were selected; an empty selection never means “everything”.
  case emptySelection
  /// A change has no flight key, so LogTen's import can't address the flight.
  case missingFlightKey(RecordID)
  /// A change names a field corrections may not change.
  case fieldNotImportable(LogTenFieldKey)
  /// A change's new value doesn't suit its field.
  case unsuitableValue(LogTenFieldKey, FieldValue)
  /// One flight's field is changed twice in one batch.
  case conflictingChanges(RecordID, LogTenFieldKey)
  /// Writing to LogTen is disabled in this build.
  case liveWritingDisabled
  /// LogTen couldn't be asked to import the package.
  case deliveryFailed(reason: String)
  /// The backup copy doesn't match its manifest.
  case backupDamaged([String])
}

extension CorrectionError: LocalizedError {
  public var errorDescription: String? {
    switch self {
      case .emptySelection:
        String(localized: "The corrections couldn’t be proposed.", bundle: .module)
      case .missingFlightKey, .fieldNotImportable, .unsuitableValue, .conflictingChanges:
        String(localized: "The corrections couldn’t be packaged for LogTen.", bundle: .module)
      case .liveWritingDisabled, .deliveryFailed:
        String(localized: "The corrections couldn’t be sent to LogTen.", bundle: .module)
      case .backupDamaged:
        String(localized: "The logbook backup is damaged.", bundle: .module)
    }
  }

  public var failureReason: String? {
    switch self {
      case .emptySelection:
        String(localized: "No findings were selected.", bundle: .module)
      case .missingFlightKey(let id):
        String(
          localized:
            "Entry \(id.rawValue) has no flight key, so LogTen can’t import changes to it.",
          bundle: .module
        )
      case .fieldNotImportable(let field):
        String(
          localized: "\(field.rawValue) can’t be changed through LogTen’s import.",
          bundle: .module
        )
      case let .unsuitableValue(field, value):
        String(
          localized: "\(String(describing: value)) isn’t a valid value for \(field.rawValue).",
          bundle: .module
        )
      case let .conflictingChanges(id, field):
        String(
          localized: "Entry \(id.rawValue) changes \(field.rawValue) more than once.",
          bundle: .module
        )
      case .liveWritingDisabled:
        String(
          localized:
            "This development build only records import packages, unless a disposable logbook is declared open in LogTen.",
          bundle: .module
        )
      case .deliveryFailed(let reason):
        reason
      case .backupDamaged(let paths):
        String(
          localized: "These files don’t match the manifest: \(paths.formatted(.list(type: .and))).",
          bundle: .module
        )
    }
  }

  public var recoverySuggestion: String? {
    switch self {
      case .missingFlightKey:
        String(localized: "Edit the entry in LogTen instead.", bundle: .module)
      case .backupDamaged:
        String(localized: "Back up the logbook again before applying corrections.", bundle: .module)
      default:
        nil
    }
  }
}
