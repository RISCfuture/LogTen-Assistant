public import Foundation
import GRDB
public import LogbookModel

/// A value a module persists in a logbook's workspace.
///
/// Documents are stored as JSON, grouped by ``collection`` and keyed by ``documentID``, so a
/// module can persist new record types without a schema migration.
public protocol WorkspaceDocument: Codable, Sendable {
  /// The collection the type's documents are stored in; unique per document type.
  static var collection: String { get }

  /// The document's key within its collection.
  var documentID: String { get }
}

/**
 The app's private data for one logbook: settings, review decisions, caches and the apply
 journal.

 Each logbook gets a folder named for its store UUID, holding a SQLite database
 (`workspace.sqlite`) plus folders for snapshots and backups. The database is a typed document
 store: a ``WorkspaceDocument`` type picks a collection, and the workspace stores and loads its
 values as JSON.
 */
public final class Workspace: Sendable {
  /// The database's file name.
  public static let databaseFileName = "workspace.sqlite"

  private static let documentsTable = "documents"
  fileprivate static let settingsDocumentID = "logbook"

  /// The folder that holds every logbook's workspace by default:
  /// `Application Support/Logbooks`.
  public static var defaultRoot: URL {
    URL.applicationSupportDirectory.appending(path: "Logbooks", directoryHint: .isDirectory)
  }

  private static var migrator: DatabaseMigrator {
    var migrator = DatabaseMigrator()
    migrator.registerMigration("documents") { db in
      try db.create(table: documentsTable) { table in
        table.column("collection", .text).notNull()
        table.column("id", .text).notNull()
        table.column("json", .blob).notNull()
        table.column("updatedAt", .datetime).notNull()
        table.primaryKey(["collection", "id"])
      }
    }
    return migrator
  }

  /// The folder holding the workspace.
  public let directory: URL

  private let database: DatabasePool
  private let encoder: JSONEncoder
  private let decoder = JSONDecoder()

  /// The folder holding the logbook's snapshots.
  public var snapshotsDirectory: URL {
    directory.appending(path: "Snapshots", directoryHint: .isDirectory)
  }

  /// The folder holding the logbook's backups.
  public var backupsDirectory: URL {
    directory.appending(path: "Backups", directoryHint: .isDirectory)
  }

  /**
   Opens or creates the workspace for a logbook.

   - Parameters:
     - storeUUID: The logbook's store UUID.
     - root: The folder holding every logbook's workspace.
   */
  public convenience init(storeUUID: UUID, root: URL = Workspace.defaultRoot) throws {
    try self.init(
      directory: root.appending(path: storeUUID.uuidString, directoryHint: .isDirectory)
    )
  }

  /// Opens or creates a workspace in a folder.
  public init(directory: URL) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    self.directory = directory
    database = try DatabasePool(
      path: directory.appending(path: Self.databaseFileName).path(percentEncoded: false)
    )
    encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    try Self.migrator.migrate(database)
  }

  /// A new, unused folder for a snapshot taken at a given time.
  public func snapshotDirectory(for date: Date) -> URL {
    let stamp = date.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: true))
      .replacing(":", with: "")
    return snapshotsDirectory.appending(
      path: "\(stamp)-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
  }
}

// MARK: - Documents

extension Workspace {
  /// Stores a document, replacing any with the same collection and identifier.
  public func save<Document: WorkspaceDocument>(_ document: Document) async throws {
    try await save([document])
  }

  /// Stores several documents in one transaction.
  public func save<Document: WorkspaceDocument>(_ documents: some Sequence<Document> & Sendable)
    async throws
  {
    let rows = try documents.map { ($0.documentID, try encoder.encode($0)) }
    let now = Date.now
    try await database.write { db in
      for (id, json) in rows {
        try db.execute(
          sql: """
            INSERT INTO \(Self.documentsTable) (collection, id, json, updatedAt) VALUES (?, ?, ?, ?)
            ON CONFLICT (collection, id) DO UPDATE SET json = excluded.json, updatedAt = \
            excluded.updatedAt
            """,
          arguments: [Document.collection, id, json, now]
        )
      }
    }
  }

  /// Loads a document, or returns `nil` if there's none with that identifier.
  public func document<Document: WorkspaceDocument>(_: Document.Type, id: String) async throws
    -> Document?
  {
    let json = try await database.read { db in
      try Data.fetchOne(
        db,
        sql: "SELECT json FROM \(Self.documentsTable) WHERE collection = ? AND id = ?",
        arguments: [Document.collection, id]
      )
    }
    return try json.map { try decoder.decode(Document.self, from: $0) }
  }

  /// Loads every document of a type, ordered by identifier.
  public func documents<Document: WorkspaceDocument>(_: Document.Type) async throws -> [Document] {
    let rows = try await database.read { db in
      try Data.fetchAll(
        db,
        sql: "SELECT json FROM \(Self.documentsTable) WHERE collection = ? ORDER BY id",
        arguments: [Document.collection]
      )
    }
    return try rows.map { try decoder.decode(Document.self, from: $0) }
  }

  /// When a document was last saved, or `nil` if it doesn't exist.
  public func modificationDate<Document: WorkspaceDocument>(of _: Document.Type, id: String)
    async throws -> Date?
  {
    try await database.read { db in
      try Date.fetchOne(
        db,
        sql: "SELECT updatedAt FROM \(Self.documentsTable) WHERE collection = ? AND id = ?",
        arguments: [Document.collection, id]
      )
    }
  }

  /// Deletes a document, if it exists.
  public func deleteDocument<Document: WorkspaceDocument>(_: Document.Type, id: String) async throws
  {
    try await database.write { db in
      try db.execute(
        sql: "DELETE FROM \(Self.documentsTable) WHERE collection = ? AND id = ?",
        arguments: [Document.collection, id]
      )
    }
  }

  /// Deletes every document of a type.
  public func deleteDocuments<Document: WorkspaceDocument>(_: Document.Type) async throws {
    try await database.write { db in
      try db.execute(
        sql: "DELETE FROM \(Self.documentsTable) WHERE collection = ?",
        arguments: [Document.collection]
      )
    }
  }
}

// MARK: - Settings

extension Workspace {
  /// The logbook's settings, or the defaults if none have been saved.
  public func settings() async throws -> LogbookSettings {
    try await document(SettingsDocument.self, id: Self.settingsDocumentID)?.settings ?? .init()
  }

  /// Saves the logbook's settings.
  public func save(_ settings: LogbookSettings) async throws {
    try await save(SettingsDocument(settings: settings))
  }
}

/// The stored form of a logbook's settings.
private struct SettingsDocument: WorkspaceDocument {
  static let collection = "settings"

  let settings: LogbookSettings

  var documentID: String { Workspace.settingsDocumentID }
}
