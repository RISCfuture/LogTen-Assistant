import AppKit
public import Foundation

/// Something that delivers import packages to LogTen.
///
/// ``LogTenURLWriter`` hands LogTen a `logten://` URL; ``RecordingWriter`` saves the package
/// instead, so tests and development builds never touch a real logbook.
public protocol CorrectionWriter: Sendable {
  /// Delivers the package that applies a batch.
  ///
  /// - Returns: A record of the delivery. LogTen asks the user to confirm each import and
  ///   reports nothing back, so delivery doesn't mean the change was made; verify it with
  ///   ``BatchVerifier``.
  func write(_ package: ImportPackage, for batch: CorrectionBatch) async throws -> WriteReceipt
}

/// A record of one delivered package.
public struct WriteReceipt: Hashable, Codable, Sendable {
  /// The batch delivered.
  public var batchID: String

  /// When it was delivered.
  public var deliveredAt: Date

  /// Where a recording writer saved the package, if it was recorded rather than sent.
  public var recordedFile: URL?

  /// Creates a receipt.
  public init(batchID: String, deliveredAt: Date, recordedFile: URL? = nil) {
    self.batchID = batchID
    self.deliveredAt = deliveredAt
    self.recordedFile = recordedFile
  }
}

/**
 Saves import packages to a folder instead of sending them to LogTen.

 Each batch is written as `<batch ID>.json`, the exact package text, beside `<batch ID>.url`,
 the URL that would have been opened.
 */
public struct RecordingWriter: CorrectionWriter {
  /// The folder packages are saved in.
  public let directory: URL

  /// Creates a writer that saves into a folder, creating it if needed.
  public init(directory: URL) {
    self.directory = directory
  }

  public func write(_ package: ImportPackage, for batch: CorrectionBatch) throws -> WriteReceipt {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appending(path: "\(batch.id).json")
    try Data(package.json.utf8).write(to: file, options: .withoutOverwriting)
    try Data(package.url.absoluteString.utf8).write(
      to: directory.appending(path: "\(batch.id).url"),
      options: .withoutOverwriting
    )
    return WriteReceipt(batchID: batch.id, deliveredAt: .now, recordedFile: file)
  }
}

/**
 Sends import packages to LogTen by opening their `logten://` URLs.

 Creating one needs a ``LiveWriteAuthorization``, which development builds grant only when the
 user has declared that LogTen has a disposable logbook open.
 */
public struct LogTenURLWriter: CorrectionWriter {
  private let open: @Sendable (URL) async throws -> Void

  /**
   Creates a writer.

   - Parameters:
     - authorization: Proof that writing to LogTen is allowed in this build.
     - open: Opens a URL; `nil` opens it with `NSWorkspace`.
   */
  public init(
    authorization _: LiveWriteAuthorization,
    open: (@Sendable (URL) async throws -> Void)? = nil
  ) {
    self.open = open ?? { try await Self.openWithWorkspace($0) }
  }

  @MainActor
  private static func openWithWorkspace(_ url: URL) async throws {
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    _ = try await NSWorkspace.shared.open(url, configuration: configuration)
  }

  public func write(_ package: ImportPackage, for batch: CorrectionBatch) async throws
    -> WriteReceipt
  {
    do {
      try await open(package.url)
    } catch {
      throw CorrectionError.deliveryFailed(reason: error.localizedDescription)
    }
    return WriteReceipt(batchID: batch.id, deliveredAt: .now)
  }
}

/**
 Permission to send changes to LogTen.

 Release builds may always write. Development builds may write only when the user has declared
 that the logbook open in LogTen is a disposable one, so a debug run can never change a real
 logbook by accident.
 */
public struct LiveWriteAuthorization: Sendable {
  private init() {}

  /**
   Grants permission to write, if this build allows it.

   - Parameter disposableLogbookOpen: Whether the user has declared that LogTen has a
     disposable logbook open.
   - Throws: ``CorrectionError/liveWritingDisabled`` in a development build unless a disposable
     logbook is declared open.
   */
  public static func grant(disposableLogbookOpen: Bool) throws(CorrectionError) -> Self {
    #if DEBUG
      guard disposableLogbookOpen else { throw .liveWritingDisabled }
    #endif
    return Self()
  }
}
