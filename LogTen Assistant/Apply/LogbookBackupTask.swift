import Corrections
import Foundation
import LogbookStore
import Workspace

/// Backs up a logbook's whole folder into its workspace, off the main actor.
nonisolated struct LogbookBackupTask: Sendable {
  private static let sampleFolderName = "LogTenProData_SAMPLE"
  private static let sampleStoreContents = "Sample logbook placeholder"

  /// The logbook to back up.
  let reference: LogbookReference

  /// The logbook's workspace, whose Backups folder receives the copy.
  let workspace: Workspace

  /**
   Makes the backup.

   A logbook read from disk is copied from its bookmarked folder. The sample logbook has no
   folder, so a placeholder folder is backed up in its place.
   */
  @concurrent
  func run() async throws -> BackupManifest {
    let backup = LogbookBackup()
    switch reference.source {
      case .bookmark:
        let (folder, _) = try reference.resolvedFolder()
        let accessing = folder.startAccessingSecurityScopedResource()
        defer { if accessing { folder.stopAccessingSecurityScopedResource() } }
        return try await backup.backUp(
          reference.location(in: folder),
          into: workspace.backupsDirectory
        )
      case .fixture:
        return try await backup.backUp(
          try samplePlaceholder(),
          into: workspace.backupsDirectory
        )
    }
  }

  private func samplePlaceholder() throws -> LogbookLocation {
    let folder = workspace.directory.appending(
      path: Self.sampleFolderName,
      directoryHint: .isDirectory
    )
    let location = LogbookLocation(directory: folder)
    if !FileManager.default.fileExists(atPath: location.storeURL.path(percentEncoded: false)) {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      try Data(Self.sampleStoreContents.utf8).write(to: location.storeURL)
    }
    return location
  }
}
