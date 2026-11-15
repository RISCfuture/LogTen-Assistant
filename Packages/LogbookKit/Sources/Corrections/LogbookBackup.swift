import CryptoKit
public import Foundation
public import LogbookStore

/**
 Copies a whole LogTen data folder, with the store, its write-ahead log and the attached images,
 before corrections are applied.

 The copy is made under file coordination, and repeated if the store files change while it is
 being made. A manifest of every file's size and SHA-256 digest is saved beside the copy, so the
 backup can be checked later with ``BackupManifest/damagedFiles()``.

 A backup is a local safety copy, not a rollback: LogTen syncs its logbook to other devices, so
 restoring a file copy doesn't undo changes that have already synced. ``ApplyJournal`` keeps
 compensating batches for that.
 */
public struct LogbookBackup: Sendable {
  private static let manifestName = "manifest.json"
  private static let chunkSize = 1 << 20
  private static let hexDigits = Array("0123456789abcdef")

  /// How many times to copy before giving up on a folder that keeps changing.
  public var maximumAttempts: Int

  /// How long to wait between attempts.
  public var retryDelay: Duration

  /// Creates a backup maker.
  public init(maximumAttempts: Int = 5, retryDelay: Duration = .milliseconds(500)) {
    self.maximumAttempts = maximumAttempts
    self.retryDelay = retryDelay
  }

  /// Reads the manifest saved in a backup folder.
  public static func manifest(in backupDirectory: URL) throws -> BackupManifest {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    var manifest = try decoder.decode(
      BackupManifest.self,
      from: Data(contentsOf: backupDirectory.appending(path: manifestName))
    )
    manifest.directory = backupDirectory
    return manifest
  }

  private static func folderName(for date: Date) -> String {
    date.formatted(
      Date.VerbatimFormatStyle(
        format:
          "\(year: .defaultDigits)\(month: .twoDigits)\(day: .twoDigits)T\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased))\(minute: .twoDigits)\(second: .twoDigits)Z",
        timeZone: .gmt,
        calendar: Calendar(identifier: .gregorian)
      )
    )
  }

  private static func storeStates(of logbook: LogbookLocation) throws -> [SnapshotFileState] {
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

  private static func copyCoordinated(_ source: URL, to copy: URL) throws {
    var coordinationError: NSError?
    var copyError: (any Error)?
    unsafe NSFileCoordinator().coordinate(
      readingItemAt: source,
      options: .withoutChanges,
      error: &coordinationError
    ) { directory in
      do {
        try FileManager.default.copyItem(at: directory, to: copy)
      } catch {
        copyError = error
      }
    }
    if let coordinationError { throw coordinationError }
    if let copyError { throw copyError }
  }

  static func inventory(of folder: URL) throws -> [BackupManifest.File] {
    let root = folder.standardizedFileURL.path(percentEncoded: false)
    guard
      let enumerator = FileManager.default.enumerator(
        at: folder,
        includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]
      )
    else { return [] }
    var files = [BackupManifest.File]()
    for case let url as URL in enumerator {
      let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
      guard values.isRegularFile == true else { continue }
      let path = String(url.standardizedFileURL.path(percentEncoded: false).dropFirst(root.count))
      files.append(
        BackupManifest.File(
          path: path.hasPrefix("/") ? String(path.dropFirst()) : path,
          size: UInt64(values.fileSize ?? 0),
          sha256: try sha256(of: url)
        )
      )
    }
    return files.sorted { $0.path < $1.path }
  }

  static func sha256(of file: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: file)
    defer { try? handle.close() }
    var hasher = SHA256()
    while let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty {
      hasher.update(data: chunk)
    }
    let digest = hasher.finalize()
    return digest.map { String(hexDigits[Int($0 >> 4)]) + String(hexDigits[Int($0 & 0x0F)]) }
      .joined()
  }

  /**
   Backs up a logbook folder.

   - Parameters:
     - logbook: The logbook to copy. If its folder came from a security-scoped bookmark, it is
       accessed for the duration of the copy.
     - backupsDirectory: The logbook's backups folder; the backup goes into a new folder named
       for `date`.
     - date: When the backup is made; the manifest records it to the second.
   - Returns: The manifest, which is also saved in the backup folder.
   - Throws: `CocoaError.fileWriteFileExists` if a backup with the same timestamp exists,
     `LogbookStoreError.sourceKeptChanging(_:)` if every attempt saw the store change, or a
     file error.
   */
  public func backUp(_ logbook: LogbookLocation, into backupsDirectory: URL, at date: Date = .now)
    async throws -> BackupManifest
  {
    let destination = backupsDirectory.appending(
      path: Self.folderName(for: date),
      directoryHint: .isDirectory
    )
    guard !FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) else {
      throw CocoaError(.fileWriteFileExists, userInfo: [NSURLErrorKey: destination])
    }
    let accessing = logbook.directory.startAccessingSecurityScopedResource()
    defer { if accessing { logbook.directory.stopAccessingSecurityScopedResource() } }

    let copy = destination.appending(
      path: logbook.directory.lastPathComponent,
      directoryHint: .isDirectory
    )
    try await copyStableFolder(logbook, to: copy, cleaningUp: destination)
    let manifest = BackupManifest(
      createdAt: Date(
        timeIntervalSinceReferenceDate: date.timeIntervalSinceReferenceDate.rounded(.down)
      ),
      directory: destination,
      folderName: copy.lastPathComponent,
      files: try Self.inventory(of: copy)
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(manifest).write(
      to: destination.appending(path: Self.manifestName),
      options: .withoutOverwriting
    )
    return manifest
  }

  private func copyStableFolder(
    _ logbook: LogbookLocation,
    to copy: URL,
    cleaningUp destination: URL
  )
    async throws
  {
    for attempt in 1...maximumAttempts {
      try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
      let before = try Self.storeStates(of: logbook)
      try Self.copyCoordinated(logbook.directory, to: copy)
      if try Self.storeStates(of: logbook) == before { return }

      try FileManager.default.removeItem(at: destination)
      if attempt < maximumAttempts { try await Task.sleep(for: retryDelay) }
    }
    throw LogbookStoreError.sourceKeptChanging(logbook.storeURL)
  }
}

/// The contents of a logbook backup.
public struct BackupManifest: Hashable, Codable, Sendable {
  /// When the backup was made.
  public var createdAt: Date

  /// The backup folder, which holds the copied data folder and the manifest.
  public var directory: URL

  /// The name of the copied `LogTenProData_<id>` folder inside ``directory``.
  public var folderName: String

  /// Every file in the copy, by path relative to the copied folder.
  public var files: [File]

  /// The copied data folder.
  public var copiedFolder: URL {
    directory.appending(path: folderName, directoryHint: .isDirectory)
  }

  /// Creates a manifest.
  public init(createdAt: Date, directory: URL, folderName: String, files: [File]) {
    self.createdAt = createdAt
    self.directory = directory
    self.folderName = folderName
    self.files = files
  }

  /// The paths of files that are missing from the copy, were added to it, or no longer match
  /// their recorded size and digest.
  public func damagedFiles() throws -> [String] {
    let current = Dictionary(
      uniqueKeysWithValues: try LogbookBackup.inventory(of: copiedFolder).map { ($0.path, $0) }
    )
    let recorded = Dictionary(uniqueKeysWithValues: files.map { ($0.path, $0) })
    return Set(current.keys).union(recorded.keys).filter { current[$0] != recorded[$0] }.sorted()
  }

  /// One file in a backup.
  public struct File: Hashable, Codable, Sendable {
    /// The path relative to the copied data folder.
    public var path: String

    /// The size in bytes.
    public var size: UInt64

    /// The lowercase hexadecimal SHA-256 digest of the contents.
    public var sha256: String

    /// Creates a file entry.
    public init(path: String, size: UInt64, sha256: String) {
      self.path = path
      self.size = size
      self.sha256 = sha256
    }
  }
}
