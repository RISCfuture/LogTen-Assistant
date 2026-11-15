public import Foundation
import SwiftNASR

/// Keeps one parsed ``AirportIndex`` per 28-day NASR cycle in a folder, and downloads cycles
/// that are missing.
public actor NASRCycleStore {
  private static let filePrefix = "nasr-"
  private static let fileExtension = "json"

  private let directory: URL
  private var loaded = [Date: AirportIndex]()

  /// Creates a store.
  ///
  /// - Parameter directory: The folder the parsed cycles are saved in; it is created if needed.
  public init(directory: URL) {
    self.directory = directory
  }

  private static func effectiveDate(ofFileNamed name: String) -> Date? {
    guard name.hasPrefix(filePrefix), name.hasSuffix(".\(fileExtension)") else { return nil }
    let text = name.dropFirst(filePrefix.count).dropLast(fileExtension.count + 1)
    return try? Date(String(text), strategy: .iso8601.year().month().day())
  }

  /// The effective dates of the cycles saved on disk, oldest first.
  public func savedCycles() -> [Date] {
    let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
    return names.compactMap(Self.effectiveDate(ofFileNamed:)).sorted()
  }

  /**
   The saved index for the cycle in effect on a date.

   - Parameter date: A date.
   - Returns: The index, or `nil` if that cycle isn't saved.
   */
  public func savedIndex(covering date: Date) throws -> AirportIndex? {
    guard let cycle = Cycle.effectiveCycle(for: date)?.effectiveDate else { return nil }
    if let index = loaded[cycle] { return index }
    let url = fileURL(forCycleStarting: cycle)
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    let index = try JSONDecoder.references.decode(AirportIndex.self, from: Data(contentsOf: url))
    loaded[cycle] = index
    return index
  }

  /// Saves an index, replacing any saved index of the same cycle.
  public func save(_ index: AirportIndex) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let data = try JSONEncoder.references.encode(index)
    try data.write(to: fileURL(forCycleStarting: index.effectiveDate), options: .atomic)
    loaded[index.effectiveDate] = index
  }

  /**
   The index for the cycle in effect on a date, downloading the cycle from the FAA if it isn't
   saved.

   - Parameters:
     - date: A date.
     - progress: Reports download and parse progress.
   - Returns: The index.
   - Throws: ``ReferenceDataError/noCycle(_:)`` if no cycle covers the date, or the download or
     parse error.
   */
  public func index(covering date: Date, progress: consuming Subprogress? = nil)
    async throws -> AirportIndex
  {
    if let saved = try savedIndex(covering: date) { return saved }
    guard let cycle = Cycle.effectiveCycle(for: date) else {
      throw ReferenceDataError.noCycle(date)
    }
    let archive = FileManager.default.temporaryDirectory
      .appending(path: "nasr-\(UUID().uuidString).zip")
    defer { try? FileManager.default.removeItem(at: archive) }
    guard let nasr = NASR.fromInternetToFile(archive, activeAt: date, format: .csv) else {
      throw ReferenceDataError.noCycle(date)
    }
    let index = try await NASRAirportLoader.index(
      from: nasr,
      downloadedCycle: cycle,
      progress: progress
    )
    try save(index)
    return index
  }

  private func fileURL(forCycleStarting date: Date) -> URL {
    directory.appending(
      path:
        "\(Self.filePrefix)\(date.formatted(.iso8601.year().month().day())).\(Self.fileExtension)"
    )
  }
}

extension JSONEncoder {
  fileprivate static var references: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }
}

extension JSONDecoder {
  fileprivate static var references: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }
}
