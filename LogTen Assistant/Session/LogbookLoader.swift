import Foundation
import LogbookModel
import LogbookStore
import Workspace

/// A logbook read from a fresh snapshot, with its workspace.
nonisolated struct LoadedLogbook: Sendable {
  /// The logbook's records.
  var logbook: Logbook

  /// The logbook's saved settings, or the defaults.
  var settings: LogbookSettings

  /// The logbook's workspace.
  var workspace: Workspace

  /// The snapshot the records were read from.
  var snapshot: LogbookSnapshot

  /// A replacement bookmark, if the one the reference held was stale.
  var refreshedBookmark: Data?
}

/// The steps of opening a logbook, for progress display.
nonisolated enum LoadStep: Sendable {
  case snapshotting
  case reading
  case checkingRegulations
  case auditing

  var title: String {
    switch self {
      case .snapshotting: String(localized: "Taking a snapshot of the logbook…")
      case .reading: String(localized: "Reading flights…")
      case .checkingRegulations: String(localized: "Checking regulations…")
      case .auditing: String(localized: "Auditing entries…")
    }
  }
}

/**
 Opens a logbook the way the app always does: by copying LogTen's live store into a snapshot in
 the logbook's workspace and reading only the copy.

 The live store is never opened, not even to read its metadata. The snapshot is taken into a
 staging folder first, because the workspace is keyed by the store UUID, which is known only once
 there is a copy to read it from.
 */
nonisolated struct LogbookLoader: Sendable {
  private static let stagingFolderName = "Staging"
  private static let retainedSnapshots = 3

  /// The folder holding every logbook's workspace.
  var workspaceRoot = Workspace.defaultRoot

  /// LogTen's installed data model.
  var model = LogTenModel()

  /**
   Snapshots and reads a logbook.

   - Parameters:
     - reference: The logbook to open.
     - protecting: A snapshot in use elsewhere, which pruning must not delete.
     - progress: Called on the main actor as each step starts, with `nil`, and again as the
       step reports how far it has got, with a fraction from 0 to 1.
   - Returns: The logbook and its workspace.
   */
  @concurrent
  func load(
    _ reference: LogbookReference,
    protecting protected: LogbookSnapshot? = nil,
    progress: @escaping @MainActor @Sendable (LoadStep, Double?) -> Void
  ) async throws -> LoadedLogbook {
    let (folder, refreshedBookmark) = try reference.resolvedFolder()
    let accessing = folder.startAccessingSecurityScopedResource()
    defer { if accessing { folder.stopAccessingSecurityScopedResource() } }

    await progress(.snapshotting, nil)
    let staged = try await withFractionReports(
      deliveredTo: { progress(.snapshotting, $0) },
      body: { try await stageSnapshot(of: reference.location(in: folder), progress: $0) }
    )
    let (workspace, snapshot) = try moveIntoWorkspace(staged, protecting: protected)
    try Task.checkCancellation()

    await progress(.reading, nil)
    let reader = try LogbookReader(snapshot: snapshot, model: model)
    let logbook = try await withFractionReports(
      deliveredTo: { progress(.reading, $0) },
      body: { try await reader.read(progress: $0) }
    )
    let settings = try await workspace.settings()
    return LoadedLogbook(
      logbook: logbook,
      settings: settings,
      workspace: workspace,
      snapshot: snapshot,
      refreshedBookmark: refreshedBookmark
    )
  }

  private func stageSnapshot(
    of location: LogbookLocation,
    progress: @escaping ProgressTally.Report
  ) async throws -> LogbookSnapshot {
    let staging = workspaceRoot.appending(path: Self.stagingFolderName, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
    let destination = staging.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    return try await LogbookSnapshotter()
      .snapshot(of: location, into: destination, progress: progress)
  }

  private func moveIntoWorkspace(_ staged: LogbookSnapshot, protecting protected: LogbookSnapshot?)
    throws -> (Workspace, LogbookSnapshot)
  {
    do {
      let identity = try LogbookReader.identity(ofStoreAt: staged.storeURL)
      let workspace = try Workspace(storeUUID: identity.storeUUID, root: workspaceRoot)
      let destination = workspace.snapshotDirectory(for: staged.createdAt)
      try FileManager.default.createDirectory(
        at: workspace.snapshotsDirectory,
        withIntermediateDirectories: true
      )
      try FileManager.default.moveItem(at: staged.directory, to: destination)
      pruneSnapshots(
        in: workspace,
        keeping: [destination] + [protected?.directory].compactMap(\.self)
      )
      let snapshot = LogbookSnapshot(
        directory: destination,
        createdAt: staged.createdAt,
        sourceFiles: staged.sourceFiles
      )
      return (workspace, snapshot)
    } catch {
      try? FileManager.default.removeItem(at: staged.directory)
      throw error
    }
  }

  /// Deletes all but the newest snapshots, always keeping the ones named.
  private func pruneSnapshots(in workspace: Workspace, keeping kept: [URL]) {
    let keptNames = Set(kept.map(\.lastPathComponent))
    let snapshots =
      (try? FileManager.default.contentsOfDirectory(
        at: workspace.snapshotsDirectory,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
      )) ?? []
    let stale =
      snapshots
      .filter { !keptNames.contains($0.lastPathComponent) }
      .sorted { $0.lastPathComponent > $1.lastPathComponent }
      .dropFirst(max(0, Self.retainedSnapshots - keptNames.count))
    for snapshot in stale { try? FileManager.default.removeItem(at: snapshot) }
  }
}
