import Foundation
import Testing

@testable import FlightSources

@Suite
struct `FlySto client` {
  private static let logsURL = "https://www.flysto.net/public-api/logs?type=all&limit=250"
  private static let nextURL =
    "https://www.flysto.net/public-api/logs?limit=250&cursor=e5f6a7b8:123456"

  private func client(
    _ transport: StubTransport,
    token: String? = "secret-token"
  ) -> FlyStoClient {
    FlyStoClient(token: { token }, transport: transport, sleep: { _ in })
  }

  @Test
  func `follows next links as given and keeps the first page's cursor`() async throws {
    let transport = StubTransport([
      "GET \(Self.logsURL)": .init(body: try fixture("flysto-logs-page1.json")),
      "GET \(Self.nextURL)": .init(body: try fixture("flysto-logs-page2.json"))
    ])

    let sync = try await client(transport).syncLogs()

    #expect(sync.logs.map(\.id) == ["a1b2c3d4", "e5f6a7b8", "c9d0e1f2"])
    #expect(sync.cursor == "123456")
    #expect(transport.requests.map(\.url?.absoluteString) == [Self.logsURL, Self.nextURL])
    #expect(
      transport.requests.allSatisfy {
        $0.value(forHTTPHeaderField: "Authorization") == "Bearer secret-token"
      }
    )
  }

  @Test
  func `asks only for logs added after a cursor`() async throws {
    let url = "https://www.flysto.net/public-api/logs?type=all&limit=250&after=123456"
    let transport = StubTransport(["GET \(url)": .json(#"{"logs": [], "timestamp": 123999}"#)])

    let sync = try await client(transport).syncLogs(after: "123456")

    #expect(sync.logs.isEmpty)
    #expect(sync.cursor == "123999")
  }

  @Test
  func `reads mixed-type parameters and ignores unknown ones`() async throws {
    let transport = StubTransport([
      "GET \(Self.logsURL)": .init(body: try fixture("flysto-logs-page1.json")),
      "GET \(Self.nextURL)": .init(body: try fixture("flysto-logs-page2.json"))
    ])

    let log = try #require(try await client(transport).syncLogs().logs.first)

    #expect(log.parameter("Takeoffs/landings")?.value == .text("1"))
    #expect(log.parameter("Airtime")?.value == .number(46))
    #expect(log.parameter("Airtime")?.value?.text == "46")
    #expect(log.parameter("Unfamiliar")?.value == .unknown)
    #expect(log.parameters.count == 11)
    #expect(log.parameter("Crew")?.crew.map(\.role) == ["PIC", "Instructor"])
  }

  @Test(arguments: [
    (FlyStoValue.number(46), "46" as String?, 46 as Double?),
    (.number(1.5), "1.5", 1.5),
    (.number(1e19), "1e+19", 1e19),
    (.text(" 12.5 "), " 12.5 ", 12.5),
    (.text("KSQL"), "KSQL", nil),
    (.flag(true), nil, nil),
    (.unknown, nil, nil)
  ])
  func `reads values as text or number where they allow`(
    value: FlyStoValue,
    text: String?,
    number: Double?
  ) {
    #expect(value.text == text)
    #expect(value.number == number)
  }

  @Test
  func `refuses to follow a next link to another host`() async throws {
    let page = #"{"logs": [], "next": "https://evil.example/public-api/logs?cursor=1"}"#
    let transport = StubTransport(["GET \(Self.logsURL)": .json(page)])

    await #expect(
      throws: FlightSourceError.untrustedURL(
        URL(string: "https://evil.example/public-api/logs?cursor=1")!
      )
    ) {
      try await client(transport).syncLogs()
    }
    #expect(transport.requests.count == 1)
  }

  @Test
  func `drops and counts logs it can't read, and drops unreadable parameters and events`()
    async throws
  {
    let page = """
      {"logs": [
        {"date": "1 Jan 2026"},
        {"id": "ok123456", "parameters": [{"name": "A", "value": 1}, {"value": 2}, {"name": "B"}],
         "takeoffs": [{"time": "t", "parameters": [{"name": "C"}, 7]}, 3]},
        {"id": 5}, "junk"
      ], "timestamp": "1"}
      """
    let transport = StubTransport(["GET \(Self.logsURL)": .json(page)])

    let sync = try await client(transport).syncLogs()

    #expect(sync.logs.map(\.id) == ["ok123456"])
    #expect(sync.undecodableCount == 3)
    let log = try #require(sync.logs.first)
    #expect(log.parameters.map(\.name) == ["A", "B"])
    #expect(log.takeoffs?.count == 1)
    #expect(log.takeoffs?.first?.parameters.map(\.name) == ["C"])
    #expect(log.approaches == nil)
  }

  @Test
  func `reports a missing token without a request`() async throws {
    let transport = StubTransport([String: StubTransport.Reply]())

    await #expect(throws: FlightSourceError.missingCredentials(.flySto)) {
      try await client(transport, token: nil).syncLogs()
    }
    #expect(transport.requests.isEmpty)
  }

  @Test(arguments: [
    (401, FlightSourceError.unauthorized(.flySto)), (500, .httpStatus(.flySto, 500))
  ])
  func `maps HTTP failures to errors`(status: Int, expected: FlightSourceError) async throws {
    let transport = StubTransport(["GET \(Self.logsURL)": .status(status)])

    await #expect(throws: expected) { try await client(transport).syncLogs() }
  }

  @Test
  func `reads the crew list`() async throws {
    let body =
      #"[{"id": 5, "name": "John Smith", "automatic-role": "PIC"}, {"id": 7, "name": "Jane Doe", "linked": {"accepted": true}}]"#
    let transport = StubTransport(["GET https://www.flysto.net/public-api/crew": .json(body)])

    let crew = try await client(transport).crew()

    #expect(crew.map(\.name) == ["John Smith", "Jane Doe"])
    #expect(crew.first?.automaticRole == "PIC")
  }
}

@Suite
struct `FlySto log upload` {
  private static let uploadURL = "https://www.flysto.net/public-api/log-upload?id=ref-1"

  @Test
  func `sends the archive and reports a 409 as already uploaded`() async throws {
    let transport = StubTransport([
      "POST \(Self.uploadURL)": .json(#"{"fileId": "file-9"}"#, status: 409)
    ])
    let client = FlyStoClient(token: { "t" }, transport: transport)

    let upload = try await client.upload(archive: Data([1, 2, 3]), reference: "ref-1")

    #expect(upload == FlyStoUpload(fileID: "file-9", wasAlreadyUploaded: true))
    let request = try #require(transport.requests.first)
    #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/zip")
    #expect(request.httpBody == Data([1, 2, 3]))
  }

  @Test
  func `polls until the file is processed`() async throws {
    let url = "https://www.flysto.net/public-api/log-files/file-9"
    let transport = StubTransport([
      "GET \(url)": [
        .json(#"{"processed": false}"#), .json(#"{"processed": false}"#),
        .json(#"{"processed": true, "logs": ["ab2sd22"]}"#)
      ]
    ])
    let client = FlyStoClient(token: { "t" }, transport: transport, sleep: { _ in })

    let logs = try await client.waitForProcessing(of: "file-9")

    #expect(logs == ["ab2sd22"])
    #expect(transport.requests.count == 3)
  }

  @Test
  func `gives up after the configured number of polls`() async throws {
    let url = "https://www.flysto.net/public-api/log-files/file-9"
    let transport = StubTransport(["GET \(url)": .json(#"{"processed": false}"#)])
    let client = FlyStoClient(
      token: { "t" },
      transport: transport,
      polling: .init(interval: .zero, attempts: 4),
      sleep: { _ in }
    )

    #expect(try await client.waitForProcessing(of: "file-9") == nil)
    #expect(transport.requests.count == 4)
  }
}

@Suite
struct `FlySto API records` {
  private func records() async throws -> (records: [FlyStoRecord], rejected: [FlyStoRejection]) {
    let transport = StubTransport([
      "GET https://www.flysto.net/public-api/logs?type=all&limit=250":
        .init(body: try fixture("flysto-logs-page1.json")),
      "GET https://www.flysto.net/public-api/logs?limit=250&cursor=e5f6a7b8:123456":
        .init(body: try fixture("flysto-logs-page2.json"))
    ])
    let sync = try await FlyStoClient(token: { "t" }, transport: transport).syncLogs()
    return FlyStoRecord.records(from: sync.logs + sync.logs)
  }

  @Test
  func `converts a flight log to a record with times, counts and events`() async throws {
    let record = try #require(try await records().records.first)

    #expect(record.activity == .flight)
    #expect(record.registration == "N123AB")
    #expect(record.day == utc("2026-10-12T00:00:00Z"))
    #expect(record.times.out == utc("2026-10-12T14:10:04Z"))
    #expect(record.times.landing == utc("2026-10-12T15:08:02Z"))
    #expect(record.counts == FlyStoCounts(takeoffs: 1, landings: 1))
    #expect(record.metrics.directDistanceNM == 95.5)
    #expect(record.approachEvents.first?.subtype == "Full-Stop")
    #expect(record.urls == [URL(string: "https://www.flysto.net/logs/a1b2c3d4")!])
    #expect(record.precision == 1)
  }

  @Test
  func `classifies an engine run that never flew as nonflight`() async throws {
    let record = try #require(try await records().records.last)

    #expect(record.counts == FlyStoCounts(takeoffs: 0, landings: 0))
    #expect(record.activity == .nonflight)
  }

  @Test
  func `rejects a log with an unreadable time instead of guessing`() async throws {
    let result = try await records()

    #expect(result.records.count == 2)
    #expect(result.rejected.map(\.source) == ["c9d0e1f2"])
  }

  @Test
  func `makes one record of a log returned twice`() async throws {
    let result = try await records()

    #expect(Set(result.records.map(\.id)).count == result.records.count)
  }
}
