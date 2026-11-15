import Corrections
import Foundation
import Workspace

/**
 Chooses how approved fixes reach the logbook.

 Packages are recorded to disk unless Settings ▸ Advanced says to send them to LogTen *and* the
 hidden `DisposableLogbookOpen` default declares that LogTen has a disposable logbook open.
 That declaration is required in every build, so the live logbook is never written to until
 the disposable-logbook validation has passed; development builds also need it to be granted
 a ``LiveWriteAuthorization``. The sample logbook always records.
 */
nonisolated enum WriterPolicy {
  /// The hidden default that declares a disposable logbook open in LogTen.
  static let disposableLogbookKey = "DisposableLogbookOpen"

  private static let recordedPackagesFolder = "Recorded Packages"

  /**
   The writer for a logbook.

   - Parameters:
     - workspace: The logbook's workspace, whose folder recorded packages are saved in.
     - isFixture: Whether the logbook is the built-in sample.
     - defaults: Where the writer mode and the disposable-logbook declaration are read.
   - Returns: The writer, and whether it sends packages to LogTen. A recording writer saves
     into a new folder of its own, so recording the same fixes again never collides.
   */
  static func writer(
    for workspace: Workspace,
    isFixture: Bool,
    defaults: UserDefaults = .standard
  ) -> (writer: any CorrectionWriter, sendsToLogTen: Bool) {
    let recording = RecordingWriter(
      directory: workspace.directory
        .appending(path: recordedPackagesFolder, directoryHint: .isDirectory)
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    )
    let mode = defaults.string(forKey: AppSettingsKey.writerMode).flatMap(WriterMode.init)
    let disposableLogbookOpen = defaults.bool(forKey: disposableLogbookKey)
    guard !isFixture, mode == .sendToLogTen, disposableLogbookOpen,
      let authorization = try? LiveWriteAuthorization.grant(
        disposableLogbookOpen: disposableLogbookOpen
      )
    else { return (recording, false) }
    return (LogTenURLWriter(authorization: authorization), true)
  }
}
