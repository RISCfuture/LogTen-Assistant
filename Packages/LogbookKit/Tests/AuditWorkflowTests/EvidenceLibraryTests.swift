import AuditWorkflow
import FlightSources
import Foundation
import LogbookTestSupport
import Testing
import Workspace

@Suite
struct `Evidence library` {
  private let directory: TemporaryDirectory
  private let library: EvidenceLibrary

  init() throws {
    directory = try TemporaryDirectory()
    library = EvidenceLibrary(workspace: try Workspace(directory: directory.url))
  }

  @Test
  func `syncs from the cursor the previous sync saved`() async throws {
    let api = StubFlyStoAPI(pages: [
      logPage(id: "log-1", timestamp: "1000"), logPage(id: "log-2", timestamp: "2000")
    ])
    let client = FlyStoClient(token: { "token" }, transport: api)

    let first = try await library.syncFlySto(with: client)
    _ = try await library.syncFlySto(with: client)

    #expect(first.saved == 1)
    #expect(try await library.syncState().cursor == "2000")
    let queries = api.requestedURLs.map { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
    #expect(queries.map { $0?.queryItems?.first { $0.name == "after" }?.value } == [nil, "1000"])
    #expect(try await library.flyStoRecords().map(\.id).sorted() == ["log-1", "log-2"])
  }

  @Test
  func `keeps the cursor while a log can't be decoded`() async throws {
    let broken = #"{"logs": [{"id": 7}], "timestamp": "3000"}"#
    let api = StubFlyStoAPI(pages: [logPage(id: "log-1", timestamp: "1000"), broken])
    let client = FlyStoClient(token: { "token" }, transport: api)

    _ = try await library.syncFlySto(with: client)
    let second = try await library.syncFlySto(with: client)

    #expect(second.undecodableCount == 1)
    #expect(try await library.syncState().cursor == "1000")
  }

  @Test
  func `prefers API records over an export of the same aircraft and day`() async throws {
    let api = StubFlyStoAPI(pages: [logPage(id: "log-1", timestamp: "1000")])
    let csv = directory.path("export.csv")
    try Data(
      """
      Aircraft;Date;From;To;Brakes off;Takeoff time;Landing time;Brakes on;Takeoffs;Landings
      ;;;;hh:mm;hh:mm;hh:mm;hh:mm;;
      N111AA;2026-10-12;KSQL;KRHV;14:10z;14:22z;15:08z;15:25z;1;1
      N111AA;2026-10-13;KSQL;KRHV;14:10z;14:22z;15:08z;15:25z;1;1

      """.utf8
    )
    .write(to: csv)

    _ = try await library.syncFlySto(with: FlyStoClient(token: { "token" }, transport: api))
    let export = try await library.importFlyStoExport([csv], asOf: utc("2026-11-01T00:00:00Z"))
    let records = try await library.flyStoRecords()

    #expect(export.records.count == 2)
    #expect(records.count == 2)
    #expect(records.filter { $0.origin == .api }.map(\.id) == ["log-1"])
  }
}
