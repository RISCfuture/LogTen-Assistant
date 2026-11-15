public import Foundation
public import LogbookModel
public import Tracks

/// A folder of downloaded adsb.lol traces, each saved with a provenance record, and the
/// ``TrackSource`` that serves them.
///
/// Each trace is stored as `adsblol-<day>-<hex>.json` (the file as extracted) next to
/// `adsblol-<day>-<hex>.provenance.json`. Reading verifies the trace against the digest in its
/// provenance record, so a modified file is rejected rather than trusted. The source never
/// touches the network: traces enter the cache through ``store(_:)`` after an explicit fetch.
public struct ADSBTraceCache: TrackSource {
  private static let provenanceSuffix = ".provenance.json"
  private static let ownerOnlyPermissions = 0o600

  public let name = ADSBLolClient.sourceName

  /// The folder the traces are stored in.
  public let directory: URL

  /// Creates a cache over a folder, which is created on first use.
  public init(directory: URL) {
    self.directory = directory
  }

  /// Whether the cache holds the trace for an aircraft on a day.
  public func contains(day: ADSBArchiveDay, icao: ICAOAddress) -> Bool {
    FileManager.default.fileExists(
      atPath: directory.appending(path: ADSBTraceFile.fileName(day: day, icao: icao)).path
    )
  }

  /// Saves a trace and its provenance, replacing any earlier copy.
  public func store(_ trace: ADSBTraceFile) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let traceURL = directory.appending(path: trace.fileName)
    try trace.json.write(to: traceURL, options: .atomic)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(trace.provenance)
      .write(to: provenanceURL(for: traceURL), options: .atomic)
    for file in [traceURL, provenanceURL(for: traceURL)] {
      try FileManager.default.setAttributes(
        [.posixPermissions: Self.ownerOnlyPermissions],
        ofItemAtPath: file.path
      )
    }
  }

  /**
   Reads every stored trace.

   A trace file without a provenance record is ignored.

   - Throws: ``FlightSourceError/checksumMismatch(file:)`` if a trace doesn't match its recorded
     digest or registration.
   */
  public func traces() throws -> [ADSBTraceFile] {
    guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
    let names = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
    return try names.filter(isTraceFile).compactMap(trace(named:))
  }

  // swiftlint:disable:next async_without_await
  public func tracks(for registration: String, during interval: DateInterval) async throws
    -> [Track]
  {
    try traces().map(\.track).filter {
      $0.registration.caseInsensitiveCompare(registration) == .orderedSame
        && $0.interval?.intersects(interval) == true
    }
  }

  private func isTraceFile(_ name: String) -> Bool {
    name.hasPrefix("adsblol-") && name.hasSuffix(".json") && !name.hasSuffix(Self.provenanceSuffix)
  }

  private func provenanceURL(for trace: URL) -> URL {
    trace.deletingPathExtension().appendingPathExtension("provenance.json")
  }

  private func trace(named name: String) throws -> ADSBTraceFile? {
    let url = directory.appending(path: name)
    guard let provenanceData = try? Data(contentsOf: provenanceURL(for: url)) else { return nil }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let provenance = try decoder.decode(ADSBProvenance.self, from: provenanceData)
    let json = try Data(contentsOf: url)
    guard sha256Hex(of: json) == provenance.source.sha256 else {
      throw FlightSourceError.checksumMismatch(file: name)
    }
    let trace = try ADSBTraceFile(json: json, provenance: provenance)
    guard trace.provenance.registration == provenance.registration else {
      throw FlightSourceError.checksumMismatch(file: name)
    }
    return trace
  }
}
