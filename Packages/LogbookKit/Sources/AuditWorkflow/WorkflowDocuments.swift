public import Corrections
public import FlightSources
public import Foundation
public import Review
public import Workspace

/// The decisions saved for a logbook, with the run they were made against.
public struct ReviewState: WorkspaceDocument {
  /// The collection review state is stored in.
  public static let collection = "review"

  private static let currentID = "current"

  /// The run the decisions were made against.
  public var audit: ReviewedAudit

  /// The decisions.
  public var decisions: [ReviewRecord]

  public var documentID: String { Self.currentID }

  /// Creates review state.
  public init(audit: ReviewedAudit, decisions: [ReviewRecord]) {
    self.audit = audit
    self.decisions = decisions
  }

  /// Loads the saved state from a workspace.
  public static func load(from workspace: Workspace) async throws -> Self? {
    try await workspace.document(Self.self, id: currentID)
  }
}

/// A logbook's apply journal, as saved in its workspace.
public struct JournalDocument: WorkspaceDocument {
  /// The collection journals are stored in.
  public static let collection = "apply_journal"

  private static let currentID = "journal"

  /// The journal.
  public var journal: ApplyJournal

  public var documentID: String { Self.currentID }

  /// Creates the document for a journal.
  public init(journal: ApplyJournal) {
    self.journal = journal
  }

  /// Loads the saved journal from a workspace.
  public static func load(from workspace: Workspace) async throws -> ApplyJournal? {
    try await workspace.document(Self.self, id: currentID)?.journal
  }
}

/// One FlySto record saved in a logbook's workspace.
struct FlyStoRecordDocument: WorkspaceDocument {
  static let collection = "flysto_records"

  var record: FlyStoRecord

  var documentID: String { record.id }
}

/// Where FlySto syncing stands for a logbook.
public struct FlyStoSyncState: WorkspaceDocument, Hashable {
  /// The collection sync state is stored in.
  public static let collection = "flysto_sync"

  static let currentID = "api"

  /// The cursor to sync from next time, from FlySto's last response.
  public var cursor: String?

  /// When the last sync finished.
  public var lastSyncedAt: Date?

  /// When an export was last imported.
  public var lastImportedAt: Date?

  public var documentID: String { Self.currentID }

  /// Creates sync state.
  public init(cursor: String? = nil, lastSyncedAt: Date? = nil, lastImportedAt: Date? = nil) {
    self.cursor = cursor
    self.lastSyncedAt = lastSyncedAt
    self.lastImportedAt = lastImportedAt
  }
}
