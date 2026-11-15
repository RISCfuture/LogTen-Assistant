import Corrections
import Foundation
import LogbookModel
import LogbookStore
import LogbookTestSupport
import Testing

/// A synthetic logbook that stands in for LogTen while batches are applied: the test plays
/// LogTen's import by updating the open store.
private final class LogTenStandIn {
  let directory: TemporaryDirectory
  let store: SyntheticStore

  init() throws {
    directory = try TemporaryDirectory()
    let flights = ["F1", "F2"].map { id in
      SyntheticLogbook.Flight(
        id: id,
        date: Date(timeIntervalSinceReferenceDate: 800_000_000),
        values: [
          .flightKey: .text("KEY-\(id)"), .flightTotalTime: .integer(60), .flightNight: .integer(60)
        ]
      )
    }
    store = try SyntheticLogbook(flights: flights).write(into: directory.url)
  }

  func snapshot() async throws -> Logbook {
    let snapshot = try await LogbookSnapshotter()
      .snapshot(of: store.location, into: directory.path("snapshot-\(UUID().uuidString)"))
    return try await LogbookReader(snapshot: snapshot).read()
  }

  /// Applies a batch as LogTen's import would.
  func importBatch(_ batch: CorrectionBatch) throws {
    for change in batch.changes {
      try store.updateFlight(change.recordID.rawValue, [change.field: change.new])
    }
  }
}

private func nightBatch(_ id: String, from old: Int = 60, to new: Int = 30) -> CorrectionBatch {
  CorrectionBatch(changes: [
    FieldChange(
      flightKey: "KEY-\(id)",
      recordID: RecordID(rawValue: id),
      field: .flightNight,
      old: .integer(old),
      new: .integer(new)
    )
  ])
}

@Suite(.requiresLogTen)
struct `Applying and verifying batches` {
  private let logTen: LogTenStandIn
  private let verifier = BatchVerifier(timeout: .seconds(2), pollInterval: .milliseconds(100))

  init() throws {
    logTen = try LogTenStandIn()
  }

  @Test
  func `verifies a batch that changed exactly its fields`() async throws {
    let before = try await logTen.snapshot()
    let batch = nightBatch("F1")
    try logTen.importBatch(batch)

    let verification = try await verifier.waitAndVerify(batch, before: before) {
      try await logTen.snapshot()
    }
    #expect(verification.isVerified)
    #expect(
      verification.observedChanges == [
        ObservedChange(
          recordID: "F1",
          field: .flightNight,
          old: .integer(60),
          new: .integer(30),
          isSideEffect: false
        )
      ]
    )
  }

  @Test
  func `reports a batch that didn't arrive and changes nobody planned`() async throws {
    let before = try await logTen.snapshot()
    try logTen.store.updateFlight("F2", [.flightTotalTime: .integer(75)])

    let verification = try await verifier.waitAndVerify(nightBatch("F1"), before: before) {
      try await logTen.snapshot()
    }
    #expect(
      verification.issues == [
        .unexpectedValue("F1", .flightNight, expected: .integer(30), found: .integer(60)),
        .unexpectedValue("F2", .flightTotalTime, expected: .integer(60), found: .integer(75))
      ]
    )
  }

  @Test
  func `journals batches and reverts them with compensating batches`() async throws {
    let before = try await logTen.snapshot()
    let writer: any CorrectionWriter = RecordingWriter(directory: logTen.directory.path("packages"))
    let metadata = ImportPackageMetadata(version: "1.0")
    var journal = ApplyJournal(storeUUID: before.identity.storeUUID)

    let batch = nightBatch("F1")
    let package = try ImportPackage(batch: batch, metadata: metadata)
    let entry = journal.recordDelivery(
      of: batch,
      package: package,
      receipt: try await writer.write(package, for: batch)
    )
    try logTen.importBatch(batch)
    journal.recordVerification(
      try await verifier.waitAndVerify(batch, before: before) { try await logTen.snapshot() },
      for: entry
    )
    #expect(journal.appliedBatches == [batch])

    let revert = try #require(journal.revertBatch(for: entry))
    #expect(Preflight.check(revert.changes, against: try await logTen.snapshot()) == [[]])
    let revertPackage = try ImportPackage(batch: revert, metadata: metadata)
    let revertEntry = journal.recordDelivery(
      of: revert,
      package: revertPackage,
      receipt: try await writer.write(revertPackage, for: revert),
      reverting: entry
    )
    try logTen.importBatch(revert)
    journal.recordVerification(
      try await verifier.waitAndVerify(revert, after: journal.appliedBatches, before: before) {
        try await logTen.snapshot()
      },
      for: revertEntry
    )
    #expect(journal.entry(revertEntry)?.status == .verified)
    #expect(journal.appliedBatches.isEmpty)
  }

  @Test
  func `records packages instead of sending them`() throws {
    let batch = nightBatch("F1")
    let package = try ImportPackage(batch: batch, metadata: .init(version: "1.0"))
    let receipt = try RecordingWriter(directory: logTen.directory.path("packages"))
      .write(package, for: batch)

    let file = try #require(receipt.recordedFile)
    #expect(try String(contentsOf: file, encoding: .utf8) == package.json)
    #expect(
      try String(
        contentsOf: file.deletingPathExtension().appendingPathExtension("url"),
        encoding: .utf8
      )
        == package.url.absoluteString
    )
  }
}

@Suite(.requiresLogTen)
struct `Logbook backups` {
  @Test
  func `copy the whole data folder and detect damage to the copy`() async throws {
    let logTen = try LogTenStandIn()
    let images = logTen.store.location.directory.appending(
      path: "Images",
      directoryHint: .isDirectory
    )
    try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
    try Data("photo".utf8).write(to: images.appending(path: "photo.jpg"))

    let manifest = try await LogbookBackup()
      .backUp(logTen.store.location, into: logTen.directory.path("Backups"))
    let paths = manifest.files.map(\.path)

    #expect(paths.contains("Images/photo.jpg"))
    #expect(paths.contains(LogbookLocation.storeFileName))
    #expect(try manifest.damagedFiles().isEmpty)
    #expect(try LogbookBackup.manifest(in: manifest.directory) == manifest)

    try Data("edited".utf8).write(to: manifest.copiedFolder.appending(path: "Images/photo.jpg"))
    #expect(try manifest.damagedFiles() == ["Images/photo.jpg"])
  }
}

@Suite
struct `Live write authorization` {
  @Test
  func `is refused in development builds unless a disposable logbook is open`() async throws {
    #if DEBUG
      #expect(throws: CorrectionError.liveWritingDisabled) {
        try LiveWriteAuthorization.grant(disposableLogbookOpen: false)
      }
    #endif
    let opened = OpenedURLs()
    let writer = LogTenURLWriter(
      authorization: try LiveWriteAuthorization.grant(disposableLogbookOpen: true)
    ) { await opened.append($0) }
    let batch = nightBatch("F1")
    let package = try ImportPackage(batch: batch, metadata: .init(version: "1.0"))

    _ = try await writer.write(package, for: batch)
    #expect(await opened.urls == [package.url])
  }

  private actor OpenedURLs {
    var urls = [URL]()

    func append(_ url: URL) { urls.append(url) }
  }
}
