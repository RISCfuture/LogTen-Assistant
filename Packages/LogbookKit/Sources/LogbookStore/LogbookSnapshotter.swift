public import Foundation
import GRDB
public import LogbookModel

/// A self-contained copy of a LogTen store, safe to read without affecting LogTen.
public struct LogbookSnapshot: Hashable, Codable, Sendable {
  /// The folder holding the copy.
  public let directory: URL

  /// When the copy was taken.
  public let createdAt: Date

  /// The size and modification date of each source file at the time of the copy.
  public let sourceFiles: [SnapshotFileState]

  /// The copied store file, which has no write-ahead log and uses rollback journaling.
  public var storeURL: URL { directory.appending(path: LogbookLocation.storeFileName) }

  /// Creates a description of a snapshot.
  public init(directory: URL, createdAt: Date, sourceFiles: [SnapshotFileState]) {
    self.directory = directory
    self.createdAt = createdAt
    self.sourceFiles = sourceFiles
  }
}

/// The size and modification date of one file, used to detect a store changing during a copy.
public struct SnapshotFileState: Hashable, Codable, Sendable {
  /// The file's name.
  public let name: String

  /// The file's size in bytes.
  public let size: UInt64

  /// The file's modification date.
  public let modificationDate: Date

  /// Creates a file state.
  public init(name: String, size: UInt64, modificationDate: Date) {
    self.name = name
    self.size = size
    self.modificationDate = modificationDate
  }
}

/**
 Copies a live LogTen store into a snapshot that can be read safely.

 LogTen may be writing to its store at any moment, and a sandboxed app can only read it.
 The snapshotter therefore never opens the live files. It:

 1. copies the store, write-ahead log and shared-memory file under file coordination;
 2. compares each file's size and modification date before and after the copy, and copies
    again if anything changed;
 3. on the copy only, checkpoints the write-ahead log into the store, switches it to
    rollback journaling, and runs SQLite's integrity check.
 */
public struct LogbookSnapshotter: Sendable {
  private static let chunkSize = 4 * 1_024 * 1_024

  /// How many times to copy before giving up on a store that keeps changing.
  public var maximumAttempts: Int

  /// How long to wait between attempts.
  public var retryDelay: Duration

  /// Creates a snapshotter.
  public init(maximumAttempts: Int = 5, retryDelay: Duration = .milliseconds(500)) {
    self.maximumAttempts = maximumAttempts
    self.retryDelay = retryDelay
  }

  /**
   Takes a snapshot of a logbook.

   - Parameters:
     - logbook: The logbook to copy. If its folder came from a security-scoped bookmark, the
       snapshotter accesses it for the duration of the copy.
     - destination: A folder that doesn't exist yet, which will hold the snapshot.
     - progress: Called with the fraction of the bytes copied, from `0` to `1`, at most once
       per percent. It starts over if the store changes and the copy is retried.
   - Returns: The snapshot.
   - Throws: `CocoaError.fileWriteFileExists` if `destination` exists,
     ``LogbookStoreError/sourceKeptChanging(_:)`` if every attempt saw the store change,
     ``LogbookStoreError/integrityCheckFailed(_:messages:)`` if the copy is damaged, or a file or
     SQLite error.
   */
  public func snapshot(
    of logbook: LogbookLocation,
    into destination: URL,
    progress: ProgressTally.Report? = nil
  ) async throws -> LogbookSnapshot {
    guard !FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) else {
      throw CocoaError(.fileWriteFileExists, userInfo: [NSURLErrorKey: destination])
    }
    let accessing = logbook.directory.startAccessingSecurityScopedResource()
    defer { if accessing { logbook.directory.stopAccessingSecurityScopedResource() } }

    let sourceFiles = try await copyStableFiles(
      of: logbook,
      into: destination,
      progress: progress
    )
    try finalizeCopy(at: destination.appending(path: LogbookLocation.storeFileName))
    return LogbookSnapshot(directory: destination, createdAt: .now, sourceFiles: sourceFiles)
  }

  private func copyStableFiles(
    of logbook: LogbookLocation,
    into destination: URL,
    progress: ProgressTally.Report?
  ) async throws -> [SnapshotFileState] {
    for attempt in 1...maximumAttempts {
      let before = try fileStates(of: logbook)
      var tally = ProgressTally(total: Int(before.reduce(0) { $0 + $1.size }), report: progress)
      try copyCoordinated(logbook, into: destination, tally: &tally)
      let after = try fileStates(of: logbook)
      if before == after, try copiedSizesMatch(before, in: destination) { return after }

      try FileManager.default.removeItem(at: destination)
      if attempt < maximumAttempts { try await Task.sleep(for: retryDelay) }
    }
    throw LogbookStoreError.sourceKeptChanging(logbook.storeURL)
  }

  private func fileStates(of logbook: LogbookLocation) throws -> [SnapshotFileState] {
    try logbook.storeFileURLs.compactMap { url in
      guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
        return nil
      }
      let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
      return SnapshotFileState(
        name: url.lastPathComponent,
        size: UInt64(values.fileSize ?? 0),
        modificationDate: values.contentModificationDate ?? .distantPast
      )
    }
  }

  private func copyCoordinated(
    _ logbook: LogbookLocation,
    into destination: URL,
    tally: inout ProgressTally
  ) throws {
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    var coordinationError: NSError?
    var copyError: (any Error)?
    unsafe NSFileCoordinator().coordinate(
      readingItemAt: logbook.directory,
      options: .withoutChanges,
      error: &coordinationError
    ) { directory in
      do {
        try copyStoreFiles(
          from: LogbookLocation(directory: directory),
          into: destination,
          tally: &tally
        )
      } catch {
        copyError = error
      }
    }
    if let coordinationError { throw coordinationError }
    if let copyError { throw copyError }
  }

  private func copyStoreFiles(
    from logbook: LogbookLocation,
    into destination: URL,
    tally: inout ProgressTally
  ) throws {
    for source in logbook.storeFileURLs
    where FileManager.default.fileExists(atPath: source.path(percentEncoded: false)) {
      try copyInChunks(
        from: source,
        to: destination.appending(path: source.lastPathComponent),
        tally: &tally
      )
    }
  }

  private func copyInChunks(from source: URL, to copy: URL, tally: inout ProgressTally) throws {
    guard FileManager.default.createFile(atPath: copy.path(percentEncoded: false), contents: nil)
    else {
      throw CocoaError(.fileWriteUnknown, userInfo: [NSURLErrorKey: copy])
    }
    let reader = try FileHandle(forReadingFrom: source)
    let writer = try FileHandle(forWritingTo: copy)
    defer {
      try? reader.close()
      try? writer.close()
    }
    while let chunk = try reader.read(upToCount: Self.chunkSize), !chunk.isEmpty {
      try writer.write(contentsOf: chunk)
      tally.advance(by: chunk.count)
    }
  }

  private func copiedSizesMatch(_ states: [SnapshotFileState], in destination: URL) throws -> Bool {
    try states.allSatisfy { state in
      let copy = destination.appending(path: state.name)
      let size = try copy.resourceValues(forKeys: [.fileSizeKey]).fileSize
      return size.map(UInt64.init) == state.size
    }
  }

  private func finalizeCopy(at storeURL: URL) throws {
    let database = try DatabaseQueue(path: storeURL.path(percentEncoded: false))
    let messages = try database.writeWithoutTransaction { db in
      try db.checkpoint(.truncate)
      try db.execute(sql: "PRAGMA journal_mode=DELETE")
      return try String.fetchAll(db, sql: "PRAGMA integrity_check")
    }
    try database.close()
    removeCompanions(of: storeURL)
    guard messages == ["ok"] else {
      throw LogbookStoreError.integrityCheckFailed(storeURL, messages: messages)
    }
  }

  private func removeCompanions(of storeURL: URL) {
    for suffix in LogbookLocation.companionSuffixes {
      try? FileManager.default.removeItem(
        at: URL(filePath: storeURL.path(percentEncoded: false) + suffix)
      )
    }
  }
}
