public import Foundation
public import LogbookModel

/// A daily adsb.lol release, which is one tar archive split into parts.
public struct ADSBRelease: Hashable, Sendable {
  /// The day the release covers.
  public var day: ADSBArchiveDay
  /// The `PREFERRED_RELEASES.txt` the release is listed in.
  public var listing: URL
  /// The archive's parts, in order.
  public var parts: [URL]
}

/// How far a download has come.
public struct ADSBFetchProgress: Hashable, Sendable {
  /// Bytes of the release delivered so far, across all parts.
  public var bytesRead: Int64
  /// The release's size, if the caller or the server said.
  public var totalBytes: Int64?
  /// The part being downloaded, counting from one.
  public var part: Int
  /// The number of parts.
  public var partCount: Int
  /// The size of the part being downloaded, if the server said.
  public var partSize: Int64?
  /// Traces extracted so far.
  public var found: Int
  /// Traces being looked for.
  public var wanted: Int
  /// The retry the download is waiting for, or `nil` while it is transferring.
  public var retry: ADSBRetry?
}

/// The outcome of searching a daily release for some aircraft.
public struct ADSBFetchResult: Sendable {
  /// The release that was searched.
  public var release: ADSBRelease
  /// The traces found.
  public var traces: [ADSBTraceFile]
  /// The aircraft with no trace in the release. Absence from an archive doesn't prove the
  /// aircraft didn't fly.
  public var missing: Set<ICAOAddress>
}

/// A client for adsb.lol's open historical data (https://www.adsb.lol/docs/open-data/historical).
///
/// Each day's data is published as a multi-gigabyte tar archive split across GitHub release
/// assets. The client finds the day's preferred release, streams its parts as one tar, and
/// extracts only the `trace_full` files of the aircraft asked for. A dropped or stalled
/// connection is resumed where it left off, as ``ADSBRetryPolicy`` describes. Nothing needs
/// credentials.
public struct ADSBLolClient: Sendable {
  /// The name tracks from this source carry.
  public static let sourceName = "adsb.lol"

  /// How many bytes to download between progress reports.
  private static let progressInterval: Int64 = 4 * 1_024 * 1_024

  /// How long a connection may go without delivering data before it counts as stalled.
  private static let stallTimeout: TimeInterval = 60

  /// A session for archive downloads: a stalled transfer times out, and nothing is cached.
  @usableFromInline static let downloadSession: URLSession = {
    let configuration = URLSessionConfiguration.default
    configuration.timeoutIntervalForRequest = stallTimeout
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.urlCache = nil
    return URLSession(configuration: configuration)
  }()

  private let transport: any HTTPTransport
  private let retryPolicy: ADSBRetryPolicy
  private let now: @Sendable () -> Date

  /**
   Creates a client.

   - Parameters:
     - transport: The network layer. The default times out a connection that delivers nothing
       for a minute, which the download treats as a stall and retries.
     - retryPolicy: How a dropped or stalled download is retried.
     - now: The clock used to stamp provenance.
   */
  public init(
    transport: any HTTPTransport = URLSessionTransport(session: downloadSession),
    retryPolicy: ADSBRetryPolicy = ADSBRetryPolicy(),
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.transport = transport
    self.retryPolicy = retryPolicy
    self.now = now
  }

  private static func listingURL(year: Int) -> URL {
    URL(
      string:
        "https://raw.githubusercontent.com/adsblol/globe_history_\(year)/main/PREFERRED_RELEASES.txt"
    )!
  }

  /// The address in a member named `traces/xx/trace_full_<hex>.json`, or `nil` for any other
  /// member.
  static func traceAddress(inMemberNamed name: String) -> ICAOAddress? {
    guard let match = name.wholeMatch(of: #/traces\/[a-f0-9]{2}\/trace_full_([a-f0-9]{6})\.json/#)
    else { return nil }
    return ICAOAddress(hex: String(match.1))
  }

  /**
   Finds the preferred release for a day.

   - Throws: ``FlightSourceError/noPreferredRelease(day:matches:)`` unless the listing names
     exactly one release for the day, and ``FlightSourceError/untrustedURL(_:)`` if a part isn't
     hosted by adsb.lol's GitHub releases.
   */
  public func preferredRelease(on day: ADSBArchiveDay) async throws -> ADSBRelease {
    let listing = Self.listingURL(year: day.year)
    let (data, _) = try await transport.checkedData(
      for: URLRequest(url: listing),
      service: .adsbLol
    )
    let marker = "v\(day.releaseSpelling)-planes-"
    let matches = (String(bytes: data, encoding: .utf8) ?? "").split(whereSeparator: \.isNewline)
      .filter { $0.contains(marker) }
    guard matches.count == 1 else {
      throw FlightSourceError.noPreferredRelease(day: day.description, matches: matches.count)
    }
    let prefix = "https://github.com/adsblol/globe_history_\(day.year)/releases/download/"
    let parts = try matches[0].split(separator: ",").map { piece -> URL in
      let text = piece.trimmingCharacters(in: .whitespaces)
      guard text.hasPrefix(prefix), let url = URL(string: text) else {
        throw FlightSourceError.untrustedURL(URL(string: text) ?? listing)
      }
      return url
    }
    return ADSBRelease(day: day, listing: listing, parts: parts)
  }

  /// The combined size of a release's parts in bytes, for the confirmation shown before a
  /// download; `nil` if the server doesn't report every part's size.
  public func size(of release: ADSBRelease) async throws -> Int64? {
    var total: Int64 = 0
    for part in release.parts {
      var request = URLRequest(url: part)
      request.httpMethod = "HEAD"
      let (_, response) = try await transport.checkedData(for: request, service: .adsbLol)
      guard response.expectedContentLength >= 0 else { return nil }
      total += response.expectedContentLength
    }
    return total
  }

  /**
   Streams a release and extracts the traces of some aircraft.

   The download stops as soon as every aircraft has been found, and can be cancelled by
   cancelling the calling task. A part whose connection drops or stalls is resumed from the
   byte it reached, after a wait that ``ADSBRetryPolicy`` sets.

   - Parameters:
     - release: The release to search.
     - addresses: The aircraft to extract.
     - expectedSize: The release's size, such as ``size(of:)`` found, for progress reports.
     - progress: Called as the download proceeds, and before each wait to retry.
   - Throws: ``ADSBTransferError`` if a part can't be downloaded after retrying.
   */
  public func fetchTraces(
    in release: ADSBRelease,
    for addresses: Set<ICAOAddress>,
    expectedSize: Int64? = nil,
    progress: (@Sendable (ADSBFetchProgress) -> Void)? = nil
  ) async throws -> ADSBFetchResult {
    var search = TraceSearch(addresses: addresses)
    var report = ADSBFetchProgress(
      bytesRead: 0,
      totalBytes: expectedSize,
      part: 0,
      partCount: release.parts.count,
      partSize: nil,
      found: 0,
      wanted: addresses.count
    )
    var reported: Int64 = 0

    func send(retry: ADSBRetry? = nil) {
      report.found = search.traces.count
      report.retry = retry
      reported = report.bytesRead
      progress?(report)
    }

    for (index, part) in release.parts.enumerated() where !search.isComplete {
      report.part = index + 1
      report.partSize = nil
      var transfer = ResumableTransfer(
        transport: transport,
        url: part,
        part: index + 1,
        partCount: release.parts.count,
        policy: retryPolicy
      )
      try await transfer.run { size in
        report.partSize = size
        if expectedSize == nil, release.parts.count == 1 { report.totalBytes = size }
        send()
      } retrying: { retry in
        send(retry: retry)
      } consume: { chunk in
        try Task.checkCancellation()
        report.bytesRead += Int64(chunk.count)
        try search.append(chunk) { try trace(from: $0, address: $1, release: release) }
        if report.bytesRead - reported >= Self.progressInterval { send() }
        return !search.isComplete
      }
      send()
    }
    return ADSBFetchResult(release: release, traces: search.traces, missing: search.missing)
  }

  private func trace(
    from entry: USTAREntry,
    address: ICAOAddress,
    release: ADSBRelease
  ) throws -> ADSBTraceFile {
    let json = Gzip.isGzip(entry.data) ? try Gzip.decompress(entry.data) : entry.data
    let provenance = ADSBProvenance(
      day: release.day,
      icao: address,
      registration: nil,
      pointCount: 0,
      listing: release.listing,
      archiveMember: entry.name,
      archiveOffset: entry.offset,
      source: SourceProvenance(
        source: .adsbLol,
        urls: release.parts,
        license: ADSBProvenance.license,
        retrievedAt: now()
      )
    )
    return try ADSBTraceFile(json: json, provenance: provenance)
  }
}

/// The aircraft a download is looking for and the traces found so far, fed by a tar reader.
private struct TraceSearch {
  private(set) var missing: Set<ICAOAddress>
  private(set) var traces = [ADSBTraceFile]()
  private var reader = USTARStreamReader { ADSBLolClient.traceAddress(inMemberNamed: $0) != nil }

  /// Whether every aircraft has been found or the archive has ended.
  var isComplete: Bool { missing.isEmpty || reader.isFinished }

  init(addresses: Set<ICAOAddress>) {
    missing = addresses
  }

  /// Reads the next bytes of the archive and keeps the traces of the aircraft still missing.
  mutating func append(
    _ chunk: Data,
    trace: (USTAREntry, ICAOAddress) throws -> ADSBTraceFile
  ) throws {
    for entry in try reader.append(chunk) {
      guard let address = ADSBLolClient.traceAddress(inMemberNamed: entry.name),
        missing.contains(address)
      else { continue }
      traces.append(try trace(entry, address))
      missing.remove(address)
    }
  }
}
