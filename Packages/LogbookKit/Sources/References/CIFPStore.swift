public import Foundation
import SwiftNASR
import ZIPFoundation

/// Keeps the FAA's CIFP file, FAACIFP18, in a folder and downloads the cycle in effect when it
/// isn't the one saved.
///
/// The FAA publishes CIFP on the same 28-day AIRAC cycles as NASR, as `CIFP_YYMMDD.zip` named
/// for the cycle's effective date.
public struct CIFPStore: Sendable {
  /// Fetches a URL into a file and returns that file's location.
  public typealias Loader = @Sendable (URL) async throws -> URL

  private static let fileName = "FAACIFP18"
  private static let cycleFileName = "cycle.txt"
  private static let archiveFolder = URL(string: "https://aeronav.faa.gov/Upload_313-d/cifp/")!

  private let directory: URL
  private let loader: Loader

  /// Where the CIFP file is kept.
  public var fileURL: URL { directory.appending(path: Self.fileName) }

  /// Whether a CIFP file is saved, whether downloaded or placed there by hand.
  public var hasFile: Bool { FileManager.default.fileExists(atPath: fileURL.path) }

  /// The effective date of the downloaded cycle, or `nil` if none was downloaded.
  public var savedCycle: Date? {
    guard hasFile, let text = try? String(contentsOf: cycleFileURL, encoding: .utf8) else {
      return nil
    }
    return try? Date(
      text.trimmingCharacters(in: .whitespacesAndNewlines),
      strategy: .iso8601.year().month().day()
    )
  }

  private var cycleFileURL: URL { directory.appending(path: Self.cycleFileName) }

  /// Creates a store.
  ///
  /// - Parameters:
  ///   - directory: The folder the CIFP file is kept in; it is created when a cycle is saved.
  ///   - loader: Fetches a URL into a file; when `nil`, a `URLSession` download that fails
  ///     on an HTTP error status.
  public init(directory: URL, loader: Loader? = nil) {
    self.directory = directory
    self.loader = loader ?? Self.downloadWithURLSession
  }

  static func archiveURL(for cycle: Date) -> URL {
    let day = cycle.formatted(
      Date.VerbatimFormatStyle(
        format: "\(year: .twoDigits)\(month: .twoDigits)\(day: .twoDigits)",
        timeZone: .gmt,
        calendar: Calendar(identifier: .gregorian)
      )
    )
    return archiveFolder.appending(path: "CIFP_\(day).zip")
  }

  @Sendable
  private static func downloadWithURLSession(_ url: URL) async throws -> URL {
    let (file, response) = try await URLSession.shared.download(from: url)
    if let status = (response as? HTTPURLResponse)?.statusCode, status != 200 {
      try? FileManager.default.removeItem(at: file)
      throw ReferenceDataError.cifpDownloadFailed(statusCode: status)
    }
    return file
  }

  /**
   Downloads the cycle in effect on a date unless it is the saved one.

   - Parameter date: A date.
   - Returns: The effective date of the cycle now saved.
   - Throws: ``ReferenceDataError/noCycle(_:)`` if no cycle covers the date,
     ``ReferenceDataError/cifpDownloadFailed(statusCode:)`` or
     ``ReferenceDataError/cifpFileMissing``, or the download or file error.
   */
  @discardableResult
  public func download(covering date: Date) async throws -> Date {
    guard let cycle = Cycle.effectiveCycle(for: date)?.effectiveDate else {
      throw ReferenceDataError.noCycle(date)
    }
    if savedCycle == cycle { return cycle }
    let archive = try await loader(Self.archiveURL(for: cycle))
    defer { try? FileManager.default.removeItem(at: archive) }
    try save(extractingFrom: archive, cycle: cycle)
    return cycle
  }

  private func save(extractingFrom archive: URL, cycle: Date) throws {
    let fileManager = FileManager.default
    let scratch = fileManager.temporaryDirectory.appending(path: "cifp-\(UUID().uuidString)")
    try fileManager.createDirectory(at: scratch, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: scratch) }
    let extracted = scratch.appending(path: Self.fileName)
    let zip = try Archive(url: archive, accessMode: .read)
    guard let entry = zip.first(where: { $0.path.split(separator: "/").last == "FAACIFP18" })
    else { throw ReferenceDataError.cifpFileMissing }
    _ = try zip.extract(entry, to: extracted)
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    if fileManager.fileExists(atPath: fileURL.path) { try fileManager.removeItem(at: fileURL) }
    try fileManager.moveItem(at: extracted, to: fileURL)
    try cycle.formatted(.iso8601.year().month().day())
      .write(to: cycleFileURL, atomically: true, encoding: .utf8)
  }
}
