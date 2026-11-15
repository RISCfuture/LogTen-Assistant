public import Foundation

/// A LogTen logbook on disk: a `LogTenProData_<id>` folder holding the Core Data store and its
/// SQLite companions.
public struct LogbookLocation: Hashable, Sendable {
  /// The name of LogTen's store file.
  public static let storeFileName = "LogTenCoreDataStore.sql"

  /// The suffixes of SQLite's write-ahead log and shared-memory files.
  public static let companionSuffixes = ["-wal", "-shm"]

  /// The prefix of LogTen's per-installation data folders.
  public static let dataFolderPrefix = "LogTenProData_"

  /// LogTen's group-container identifier.
  public static let groupContainerIdentifier = "group.com.coradine.LogTenPro"

  /// LogTen's group container in the user's real home folder, where its logbooks live.
  ///
  /// A sandboxed app can't read this folder until the user chooses it in an Open panel; this is
  /// where the panel should start.
  public static var defaultGroupContainerURL: URL {
    URL(filePath: realHomeDirectory, directoryHint: .isDirectory)
      .appending(
        path: "Library/Group Containers/\(groupContainerIdentifier)",
        directoryHint: .isDirectory
      )
  }

  private static var realHomeDirectory: String {
    guard let entry = unsafe getpwuid(getuid()), let directory = unsafe entry.pointee.pw_dir else {
      return NSHomeDirectory()
    }
    return unsafe String(cString: directory)
  }

  /// The folder holding the store.
  public let directory: URL

  /// The store file.
  public var storeURL: URL { directory.appending(path: Self.storeFileName) }

  /// The store file and its write-ahead log and shared-memory companions.
  public var storeFileURLs: [URL] {
    [storeURL] + Self.companionSuffixes.map { directory.appending(path: Self.storeFileName + $0) }
  }

  /// The installation identifier in the folder name, if it follows LogTen's naming.
  public var installationIdentifier: String? {
    let name = directory.lastPathComponent
    guard name.hasPrefix(Self.dataFolderPrefix) else { return nil }
    return String(name.dropFirst(Self.dataFolderPrefix.count))
  }

  /// Creates a location for a folder that holds a store.
  public init(directory: URL) {
    self.directory = directory
  }

  /**
   Finds the logbooks in a folder the user chose.

   The folder may be a `LogTenProData_<id>` folder itself or a folder containing them, such as
   LogTen's group container.

   - Parameter folder: The chosen folder.
   - Returns: The logbooks found, sorted by folder name.
   - Throws: ``LogbookStoreError/noLogbookFound(_:)`` if there are none.
   */
  public static func logbooks(in folder: URL) throws -> [Self] {
    let fileManager = FileManager.default
    if containsStore(folder, fileManager: fileManager) { return [Self(directory: folder)] }
    let children =
      (try? fileManager.contentsOfDirectory(
        at: folder,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
      )) ?? []
    let logbooks =
      children
      .filter { $0.lastPathComponent.hasPrefix(dataFolderPrefix) }
      .filter { containsStore($0, fileManager: fileManager) }
      .sorted { $0.lastPathComponent < $1.lastPathComponent }
      .map { Self(directory: $0) }
    guard !logbooks.isEmpty else { throw LogbookStoreError.noLogbookFound(folder) }
    return logbooks
  }

  private static func containsStore(_ folder: URL, fileManager: FileManager) -> Bool {
    fileManager.fileExists(
      atPath: folder.appending(path: storeFileName).path(percentEncoded: false)
    )
  }
}
