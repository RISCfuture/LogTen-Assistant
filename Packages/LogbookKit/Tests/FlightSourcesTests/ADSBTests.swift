import Foundation
import LogbookModel
import LogbookTestSupport
import Testing
import Tracks

@testable import FlightSources

private enum Traces {
  static let hex = "a97ded"

  /// A trace in readsb's `trace_full` format: a taxi, a takeoff roll, a climb and a landing.
  static func json(icao: String = hex, registration: String? = "N12345") -> Data {
    let points = """
      [0, 37.0, -122.0, "ground", 0, 0, 0],
      [30, 37.0, -122.0, "ground", 12.5, 90, 0],
      [60, 37.1, -122.0, 500, 95.0, 90, 0],
      [90, 37.2, -122.0, 2500.5, 120, 90, 0],
      [100, null, -122.0, 2500, 120, 90, 0],
      [110, 37.3, -122.0, null, 119.5, 90, 0],
      [120, 37.3]
      """
    let registrationField = registration.map { #""r": "\#($0)","# } ?? ""
    return Data(
      """
      {"icao": "\(icao)", \(registrationField) "t": "SF50", "timestamp": 1741132800.0, "trace": \
      [\(points)]}
      """.utf8
    )
  }
}

@Suite
struct `ADSB trace file` {
  private static let day = ADSBArchiveDay(year: 2025, month: 3, day: 5)!
  private static let icao = ICAOAddress(hex: Traces.hex)!

  private func provenance() -> ADSBProvenance {
    ADSBProvenance(
      day: Self.day,
      icao: Self.icao,
      registration: nil,
      pointCount: 0,
      source: SourceProvenance(source: .adsbLol, retrievedAt: Date(timeIntervalSince1970: 0))
    )
  }

  @Test
  func `reads positioned points with ground flag, altitude and speed`() throws {
    let trace = try ADSBTraceFile(json: Traces.json(), provenance: provenance())
    let samples = trace.track.samples

    #expect(trace.track.registration == "N12345")
    #expect(trace.provenance.pointCount == 7)
    #expect(samples.count == 5)
    #expect(samples[0].time == Date(timeIntervalSince1970: 1_741_132_800))
    #expect(samples[0].isOnGround == true)
    #expect(samples[0].altitudeFt == nil)
    #expect(samples[1].groundSpeedKts == 12.5)
    #expect(samples[2].altitudeFt == 500)
    #expect(samples[2].isOnGround == nil)
    #expect(samples[4].altitudeFt == nil)
    #expect(samples.map(\.sourceRow) == [1, 2, 3, 4, 6])
  }

  @Test
  func `hashes the file contents into the provenance`() throws {
    let json = Traces.json()

    let trace = try ADSBTraceFile(json: json, provenance: provenance())

    #expect(trace.provenance.source.sha256 == sha256Hex(of: json))
    #expect(trace.track.provenance == trace.provenance.source)
  }

  @Test
  func `rejects a trace for a different aircraft`() throws {
    #expect(throws: FlightSourceError.self) {
      try ADSBTraceFile(json: Traces.json(icao: "abcdef"), provenance: provenance())
    }
  }

  @Test
  func `detects the flight in the trace's samples`() throws {
    let trace = try ADSBTraceFile(json: Traces.json(), provenance: provenance())
    var settings = TrackDetectionSettings()
    settings.gapSeconds = 60

    let events = trace.track.detectEvents(settings: settings).map(\.kind)

    #expect(events == [.out, .takeoff])
  }
}

@Suite
struct `ADSB trace cache` {
  private static let day = ADSBArchiveDay(year: 2025, month: 3, day: 5)!

  private func makeTrace() throws -> ADSBTraceFile {
    try ADSBTraceFile(
      json: Traces.json(),
      provenance: ADSBProvenance(
        day: Self.day,
        icao: ICAOAddress(hex: Traces.hex)!,
        registration: nil,
        pointCount: 0,
        source: SourceProvenance(source: .adsbLol, retrievedAt: Date(timeIntervalSince1970: 0))
      )
    )
  }

  @Test
  func `serves stored traces as a track source`() async throws {
    let folder = try TemporaryDirectory()
    let cache = ADSBTraceCache(directory: folder.url)
    try cache.store(try makeTrace())

    let overlapping = DateInterval(
      start: Date(timeIntervalSince1970: 1_741_132_800 + 60),
      duration: 60
    )
    let tracks = try await cache.tracks(for: "n12345", during: overlapping)
    let elsewhere = try await cache.tracks(
      for: "N12345",
      during: DateInterval(start: .distantPast, duration: 10)
    )
    let other = try await cache.tracks(for: "N99999", during: overlapping)

    #expect(tracks.count == 1)
    #expect(elsewhere.isEmpty)
    #expect(other.isEmpty)
    #expect(cache.contains(day: Self.day, icao: ICAOAddress(hex: Traces.hex)!))
  }

  @Test
  func `refuses a trace that was modified after it was saved`() throws {
    let folder = try TemporaryDirectory()
    let cache = ADSBTraceCache(directory: folder.url)
    let trace = try makeTrace()
    try cache.store(trace)

    try Data(Traces.json(registration: "N99999")).write(
      to: folder.url.appending(path: trace.fileName)
    )

    #expect(throws: FlightSourceError.checksumMismatch(file: trace.fileName)) {
      try cache.traces()
    }
  }
}

@Suite
struct `ADSB archive reading` {
  private static let day = ADSBArchiveDay(year: 2025, month: 3, day: 5)!
  private static let listing = URL(
    string:
      "https://raw.githubusercontent.com/adsblol/globe_history_2025/main/PREFERRED_RELEASES.txt"
  )!
  private static let base =
    "https://github.com/adsblol/globe_history_2025/releases/download/v2025.03.05-planes-readsb-prod-0/"
  private static let partA = URL(string: base + "v2025.03.05-planes-readsb-prod-0.tar.aa")!
  private static let partB = URL(string: base + "v2025.03.05-planes-readsb-prod-0.tar.ab")!

  private static func release() -> ADSBRelease {
    ADSBRelease(day: day, listing: listing, parts: [partA, partB])
  }

  private func archive() throws -> Data {
    TarBuilder.archive([
      TarBuilder.entry(name: "./", contents: Data(), typeFlag: "5"),
      TarBuilder.entry(name: "./traces/de/trace_full_deadbe.json", contents: Data("{}".utf8)),
      TarBuilder.entry(
        name: "./traces/a9/trace_full_\(Traces.hex).json",
        contents: try gzipped(Traces.json())
      ),
      TarBuilder.entry(name: "./traces/aa/trace_full_aaaaaa.json", contents: Data("{}".utf8))
    ])
  }

  private func transport(split: Int, chunk: Int = 700) throws -> StubTransport {
    let data = try archive()
    let previousDay =
      "https://github.com/adsblol/globe_history_2025/releases/download/v2025.03.04-planes-readsb-prod-0/x.tar.aa"
    return StubTransport([
      "GET \(Self.listing.absoluteString)": .json(
        "\(previousDay)\n\(Self.partA.absoluteString),\(Self.partB.absoluteString)\n"
      ),
      "GET \(Self.partA.absoluteString)": .init(body: data.prefix(split), chunkSize: chunk),
      "GET \(Self.partB.absoluteString)": .init(body: data.dropFirst(split), chunkSize: chunk)
    ])
  }

  @Test
  func `extracts only the requested trace across archive parts and chunks`() async throws {
    let transport = try transport(split: 1_300)
    let client = ADSBLolClient(transport: transport, now: { Date(timeIntervalSince1970: 42) })
    let wanted = ICAOAddress(hex: Traces.hex)!

    let result = try await client.fetchTraces(in: Self.release(), for: [wanted])

    let trace = try #require(result.traces.first)
    #expect(result.traces.count == 1)
    #expect(result.missing.isEmpty)
    #expect(trace.track.registration == "N12345")
    #expect(trace.provenance.archiveMember == "traces/a9/trace_full_\(Traces.hex).json")
    #expect(trace.provenance.source.urls == [Self.partA, Self.partB])
    #expect(trace.provenance.source.license == "ODbL-1.0")
    #expect(trace.provenance.source.retrievedAt == Date(timeIntervalSince1970: 42))
    #expect(trace.provenance.archiveOffset == 1_536)
  }

  @Test
  func `reports aircraft that are absent from the archive`() async throws {
    let transport = try transport(split: 1_300)
    let absent = ICAOAddress(hex: "123456")!

    let result = try await ADSBLolClient(transport: transport)
      .fetchTraces(in: Self.release(), for: [absent, ICAOAddress(hex: Traces.hex)!])

    #expect(result.missing == [absent])
    #expect(result.traces.count == 1)
  }

  @Test
  func `stops downloading once every aircraft is found`() async throws {
    let transport = try transport(split: 3_000)

    _ = try await ADSBLolClient(transport: transport)
      .fetchTraces(in: Self.release(), for: [ICAOAddress(hex: Traces.hex)!])

    let downloaded = transport.requests.compactMap(\.url)
    #expect(downloaded.contains(Self.partA))
    #expect(downloaded.contains(Self.partB) == false)
  }

  @Test
  func `reports progress`() async throws {
    let transport = try transport(split: 1_300)
    let log = ProgressLog()

    _ = try await ADSBLolClient(transport: transport)
      .fetchTraces(in: Self.release(), for: [ICAOAddress(hex: "123456")!]) { log.record($0) }

    let last = try #require(log.last)
    #expect(last.partCount == 2)
    #expect(last.found == 0)
    #expect(last.wanted == 1)
  }

  /// A connection that drops partway through the trace, and the server's answer to the
  /// reconnection, which either honors the `Range` header or sends the whole part again.
  private func droppingTransport(honorsRange: Bool) throws -> (StubTransport, dropAt: Int) {
    let data = try archive()
    let dropAt = 2_100
    let resumed: StubTransport.Reply =
      honorsRange
      ? .init(
        status: 206,
        body: data.dropFirst(dropAt),
        headers: ["Content-Range": "bytes \(dropAt)-\(data.count - 1)/\(data.count)"],
        chunkSize: 300
      )
      : .init(body: data, chunkSize: 300)
    let transport = StubTransport([
      "GET \(Self.partA.absoluteString)": [
        .init(body: data.prefix(dropAt), chunkSize: 300, failure: URLError(.networkConnectionLost)),
        resumed
      ]
    ])
    return (transport, dropAt)
  }

  private func client(_ transport: StubTransport, retries: Int = 3) -> ADSBLolClient {
    ADSBLolClient(
      transport: transport,
      retryPolicy: ADSBRetryPolicy(maximumRetries: retries) { _ in }
    )
  }

  @Test(arguments: [true, false])
  func `resumes a dropped part from the byte it reached`(honorsRange: Bool) async throws {
    let (transport, dropAt) = try droppingTransport(honorsRange: honorsRange)
    let release = ADSBRelease(day: Self.day, listing: Self.listing, parts: [Self.partA])
    let log = ProgressLog()

    let result = try await client(transport)
      .fetchTraces(in: release, for: [ICAOAddress(hex: Traces.hex)!]) { log.record($0) }

    let trace = try #require(result.traces.first)
    #expect(trace.track.registration == "N12345")
    #expect(trace.provenance.archiveOffset == 1_536)
    #expect(
      transport.requests.map { $0.value(forHTTPHeaderField: "Range") } == [nil, "bytes=\(dropAt)-"]
    )
    #expect(log.all.compactMap(\.retry).map(\.attempt) == [1])
    #expect(log.all.compactMap(\.retry).first?.reason == .connectionLost)
  }

  @Test
  func `fails with the reason once retries run out`() async throws {
    let transport = StubTransport([
      "GET \(Self.partA.absoluteString)": .init(failure: URLError(.timedOut))
    ])
    let release = ADSBRelease(day: Self.day, listing: Self.listing, parts: [Self.partA])

    await #expect(
      throws: ADSBTransferError.retriesExhausted(
        part: 1,
        partCount: 1,
        attempts: 3,
        reason: .stalled
      )
    ) {
      try await client(transport, retries: 2).fetchTraces(
        in: release,
        for: [ICAOAddress(hex: Traces.hex)!]
      )
    }
    #expect(transport.requests.count == 3)
  }

  @Test
  func `finds the preferred release in the yearly listing`() async throws {
    let transport = try transport(split: 1_300)

    let release = try await ADSBLolClient(transport: transport).preferredRelease(on: Self.day)

    #expect(release.parts == [Self.partA, Self.partB])
    #expect(release.listing == Self.listing)
  }

  @Test
  func `refuses release parts hosted elsewhere`() async throws {
    let line = "https://evil.example/v2025.03.05-planes-x.tar.aa"
    let transport = StubTransport(["GET \(Self.listing.absoluteString)": .json(line)])

    await #expect(throws: FlightSourceError.self) {
      try await ADSBLolClient(transport: transport).preferredRelease(on: Self.day)
    }
  }

  @Test
  func `requires exactly one release for the day`() async throws {
    let transport = StubTransport([
      "GET \(Self.listing.absoluteString)": .json(
        "https://github.com/adsblol/globe_history_2025/releases/download/v2025.03.04-planes-x/a"
      )
    ])

    await #expect(throws: FlightSourceError.noPreferredRelease(day: "2025-03-05", matches: 0)) {
      try await ADSBLolClient(transport: transport).preferredRelease(on: Self.day)
    }
  }
}

private final class ProgressLog: @unchecked Sendable {
  private let lock = NSLock()
  private var values = [ADSBFetchProgress]()

  var all: [ADSBFetchProgress] { lock.withLock { values } }
  var last: ADSBFetchProgress? { all.last }

  func record(_ progress: ADSBFetchProgress) { lock.withLock { values.append(progress) } }
}

@Suite
struct `Tar stream reader` {
  @Test(arguments: [1, 7, 511, 512, 513, 4_096])
  func `extracts wanted members however the stream is chunked`(chunkSize: Int) throws {
    let wanted = Data((0..<1_500).map { UInt8($0 % 251) })
    let archive = TarBuilder.archive([
      TarBuilder.entry(name: "skip.bin", contents: Data(repeating: 9, count: 2_000)),
      TarBuilder.entry(name: "keep.bin", contents: wanted),
      TarBuilder.entry(name: "empty.bin", contents: Data())
    ])
    var reader = USTARStreamReader { $0 == "keep.bin" || $0 == "empty.bin" }
    var entries = [USTAREntry]()

    var start = archive.startIndex
    while start < archive.endIndex {
      let end = min(start + chunkSize, archive.endIndex)
      entries += try reader.append(archive[start..<end])
      start = end
    }

    #expect(entries.map(\.name) == ["keep.bin", "empty.bin"])
    #expect(entries[0].data == wanted)
    #expect(entries[0].offset == 512 + 2_048)
    #expect(reader.isFinished)
  }

  @Test
  func `joins a ustar prefix and honors GNU long names`() throws {
    let longName = String(repeating: "d/", count: 60) + "file.json"
    let archive = TarBuilder.archive([
      TarBuilder.entry(name: "file.json", contents: Data("a".utf8), prefix: "traces/ab"),
      TarBuilder.entry(
        name: "././@LongLink",
        contents: Data(longName.utf8) + Data([0]),
        typeFlag: "L"
      ),
      TarBuilder.entry(name: "truncated", contents: Data("b".utf8))
    ])
    var reader = USTARStreamReader { _ in true }

    let entries = try reader.append(archive)

    #expect(entries.map(\.name) == ["traces/ab/file.json", longName])
  }

  @Test
  func `rejects a corrupted header`() throws {
    var archive = TarBuilder.archive([TarBuilder.entry(name: "a", contents: Data("x".utf8))])
    archive[10] ^= 0xFF
    var reader = USTARStreamReader { _ in true }

    #expect(throws: USTARStreamReader.ReadError.malformedHeader(offset: 0)) {
      try reader.append(archive)
    }
  }
}

@Suite
struct `Archive formats` {
  @Test
  func `computes CRC-32 checksums`() {
    #expect(CRC32.checksum(Data("123456789".utf8)) == 0xCBF4_3926)
  }

  @Test
  func `round-trips gzip and verifies its trailer`() throws {
    let original = Data(String(repeating: "trace ", count: 500).utf8)
    let compressed = try gzipped(original)

    #expect(try Gzip.decompress(compressed) == original)

    var corrupted = compressed
    corrupted[corrupted.count - 8] ^= 0xFF
    #expect(throws: Gzip.DecodeError.corrupt) { try Gzip.decompress(corrupted) }
    #expect(throws: Gzip.DecodeError.notGzip) { try Gzip.decompress(Data("plain".utf8)) }
  }

  @Test
  func `builds a ZIP with the file stored and its checksum recorded`() throws {
    let contents = Data("log data".utf8)

    let zip = try ZipArchive.archive(name: "log.csv", contents: contents)

    #expect(zip.prefix(4) == Data([0x50, 0x4B, 0x03, 0x04]))
    #expect(zip.suffix(22).prefix(4) == Data([0x50, 0x4B, 0x05, 0x06]))
    #expect(zip.contains(contents))
    #expect(zip.contains(Data("log.csv".utf8)))
  }
}
