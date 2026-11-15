public import FlightSources
public import Foundation
public import Workspace

/**
 The FlySto evidence saved for a logbook: records from the API and from imported exports, and
 the cursor for incremental syncing.

 Records from both origins are kept, keyed by their identifiers. When both describe the same
 aircraft on the same day, ``flyStoRecords()`` prefers the API's, since an export repeats what
 the API already supplied.
 */
public struct EvidenceLibrary: Sendable {
  private static let csvExtension = "csv"
  private static let archiveExtension = "webarchive"

  private let workspace: Workspace

  /// Creates a library over a logbook's workspace.
  public init(workspace: Workspace) {
    self.workspace = workspace
  }

  /// Whether a file is one ``importFlyStoExport(_:asOf:)`` reads.
  public static func isImportable(_ url: URL) -> Bool {
    [csvExtension, archiveExtension].contains(url.pathExtension.lowercased())
  }

  private static func pairs(in files: [URL]) async throws -> [(url: URL, links: FlyStoLinkIndex?)] {
    let exports = files.filter { $0.pathExtension.lowercased() == csvExtension }
    let archives = files.filter { $0.pathExtension.lowercased() == archiveExtension }
    var pairs = [(url: URL, links: FlyStoLinkIndex?)]()
    for export in exports {
      let archive =
        archives.count == 1 && exports.count == 1
        ? archives.first
        : archives.first { $0.deletingPathExtension().lastPathComponent == baseName(of: export) }
      if let archive {
        pairs.append((export, try await FlyStoLinkIndex.read(archive: archive, csv: export)))
      } else {
        pairs.append((export, nil))
      }
    }
    return pairs
  }

  private static func baseName(of url: URL) -> String {
    url.deletingPathExtension().lastPathComponent
  }

  /// The saved records, with export records dropped where the API covers the same aircraft and
  /// day.
  public func flyStoRecords() async throws -> [FlyStoRecord] {
    let records = try await workspace.documents(FlyStoRecordDocument.self).map(\.record)
    let covered = Set(records.filter { $0.origin == .api }.map(DayKey.init))
    return records.filter { $0.origin == .api || !covered.contains(DayKey($0)) }
  }

  /// Where syncing stands.
  public func syncState() async throws -> FlyStoSyncState {
    try await workspace.document(FlyStoSyncState.self, id: FlyStoSyncState.currentID) ?? .init()
  }

  /**
   Fetches the logs added since the last sync and saves them as records.

   - Parameters:
     - client: The FlySto client.
     - progress: Called with the number of logs fetched so far.
   - Returns: How many records were saved, which logs were rejected and how many couldn't be
     decoded. The sync cursor stays where it was while any log was rejected or undecodable, so
     the next sync fetches those logs again.
   */
  public func syncFlySto(
    with client: FlyStoClient,
    progress: (@Sendable (Int) -> Void)? = nil
  ) async throws -> FlyStoSyncSummary {
    var state = try await syncState()
    let sync = try await client.syncLogs(after: state.cursor, progress: progress)
    let (records, rejected) = FlyStoRecord.records(from: sync.logs)
    try await workspace.save(records.map(FlyStoRecordDocument.init))
    let lostNoLogs = rejected.isEmpty && sync.undecodableCount == 0
    if lostNoLogs { state.cursor = sync.cursor ?? state.cursor }
    state.lastSyncedAt = .now
    try await workspace.save(state)
    return FlyStoSyncSummary(
      saved: records.count,
      rejected: rejected,
      undecodableCount: sync.undecodableCount
    )
  }

  /**
   Imports FlySto CSV exports, each paired with a Safari web archive of its flight list when
   one is given.

   An archive pairs with the export whose file name it shares; a single archive and a single
   export pair regardless of their names.

   - Parameters:
     - files: The exports and archives.
     - asOf: The audit date; later rows are excluded.
   - Returns: What was imported.
   */
  public func importFlyStoExport(_ files: [URL], asOf: Date = .now) async throws
    -> FlyStoExport
  {
    let pairs = try await Self.pairs(in: files)
    let export = try await FlyStoCSVImporter(asOf: asOf).importFiles(pairs)
    try await workspace.save(export.records.map(FlyStoRecordDocument.init))
    var state = try await syncState()
    state.lastImportedAt = .now
    try await workspace.save(state)
    return export
  }

  /// Deletes every saved record and the sync cursor, so the next sync starts over.
  public func removeAll() async throws {
    try await workspace.deleteDocuments(FlyStoRecordDocument.self)
    try await workspace.deleteDocuments(FlyStoSyncState.self)
  }

  private struct DayKey: Hashable {
    let registration: String
    let day: Date

    init(_ record: FlyStoRecord) {
      registration = record.registration.uppercased()
      day = record.day
    }
  }
}

/// The outcome of a FlySto sync.
public struct FlyStoSyncSummary: Hashable, Sendable {
  /// How many records were saved, new or updated.
  public var saved: Int

  /// The logs that couldn't be read.
  public var rejected: [FlyStoRejection]

  /// How many logs FlySto returned that couldn't be decoded at all.
  public var undecodableCount: Int

  /// How many logs weren't saved.
  public var unreadableCount: Int { rejected.count + undecodableCount }
}
