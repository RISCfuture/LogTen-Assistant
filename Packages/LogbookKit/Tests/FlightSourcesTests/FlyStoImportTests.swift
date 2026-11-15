import Foundation
import LogbookTestSupport
import Testing

@testable import FlightSources

@Suite
struct `FlySto CSV import` {
  private func exportURL(in directory: TemporaryDirectory) throws -> URL {
    let url = directory.url.appending(path: "N111AA.csv")
    try fixture("flysto-export.csv").write(to: url)
    return url
  }

  private func imported(links: FlyStoLinkIndex? = nil, asOf: String = "2026-11-01T00:00:00Z")
    async throws
    -> FlyStoExport
  {
    let folder = try TemporaryDirectory()
    let url = try exportURL(in: folder)
    return try await FlyStoCSVImporter(asOf: utc(asOf)).importFiles([(url, links)])
  }

  @Test
  func `consolidates repeated rows without summing counts`() async throws {
    let export = try await imported()
    let record = try #require(export.records.first { $0.day == utc("2026-10-12T00:00:00Z") })

    #expect(record.rows.count == 2)
    #expect(record.counts == FlyStoCounts(takeoffs: 1, landings: 1))
    #expect(record.times.out == utc("2026-10-12T14:10:00Z"))
    #expect(record.metrics.directDistanceNM == 12.5)
    #expect(record.precision == 60)
    #expect(export.duplicateRowsConsolidated == 2)
  }

  @Test
  func `carries the date forward when the clock passes midnight`() async throws {
    let export = try await imported()
    let record = try #require(export.records.first { $0.day == utc("2026-10-13T00:00:00Z") })

    #expect(record.times.takeoff == utc("2026-10-13T23:50:00Z"))
    #expect(record.times.landing == utc("2026-10-14T00:20:00Z"))
    #expect(record.times.in == utc("2026-10-14T00:30:00Z"))
    #expect(record.timeIssues.isEmpty)
  }

  @Test
  func `classifies records by the activity they show`() async throws {
    let export = try await imported()

    #expect(export.flights.count == 4)
    #expect(export.nonflight.map(\.registration) == ["N111AA"])
    #expect(export.incomplete.isEmpty)
  }

  @Test
  func `flags clock times that disagree with the reported block time`() async throws {
    let export = try await imported()
    let record = try #require(export.records.first { $0.registration == "N222BB" })

    #expect(record.timeIssues == [.blockTime])
  }

  @Test
  func `leaves a value unknown when repeated rows disagree`() async throws {
    let export = try await imported()
    let record = try #require(export.records.first { $0.registration == "N333CC" })

    #expect(record.conflicts == [.count(.takeoff)])
    #expect(record.counts == FlyStoCounts(takeoffs: nil, landings: 1))
  }

  @Test
  func `excludes rows after the audit date or with unreadable clocks`() async throws {
    let export = try await imported()

    #expect(export.records.contains { $0.registration == "N444DD" } == false)
    #expect(export.excluded.count == 2)
    #expect(export.rowCount == 9)
  }

  @Test
  func `rejects a link index made for a different file`() async throws {
    let links = FlyStoLinkIndex(sha256: "0000", rows: [:])

    await #expect(throws: FlightSourceError.self) { try await imported(links: links) }
  }

  @Test
  func `attaches flight links by row number`() async throws {
    let folder = try TemporaryDirectory()
    let url = try exportURL(in: folder)
    let flight = URL(string: "https://www.flysto.net/logs/abcd1234")!
    let links = FlyStoLinkIndex(sha256: try sha256Hex(of: url), rows: [3: flight])

    let export = try await FlyStoCSVImporter(asOf: utc("2026-11-01T00:00:00Z")).importFiles([
      (url, links)
    ])

    let record = try #require(export.records.first { $0.day == utc("2026-10-12T00:00:00Z") })
    #expect(record.urls == [flight])
  }

  @Test(arguments: [("KSQL", "SQL"), ("sql", "SQL"), ("EGLL", "EGLL"), ("K1", "K1")])
  func `compares US airports by FAA identifier`(_ identifier: String, _ key: String) {
    #expect(airportKey(identifier) == key)
  }
}

@Suite
struct `FlySto flight-list archive` {
  private static let csv = """
    Aircraft;Date;From;To;Brakes off;Brakes on
    ;;;;hh:mm;hh:mm
    N111AA;2026-10-12;KSQL;KRHV;14:10z;15:15z
    N111AA;2026-09-03;KRHV;KSQL;;
    """

  private static func page(secondID: String = "zzzz9999", monthOfSecond: String = "September 2026")
    -> String
  {
    """
    <html><head><script>if (a < b) { x = "<tr data-key='fake'>"; }</script></head><body>
    <h4>October 2026</h4>
    <table>
    <tr data-row-id="virtual"><td data-column-id="date-short">skip</td></tr>
    <tr data-key="abcd1234"><td data-column-id="date-short">12 Oct</td>
      <td data-column-id="from-to">KSQLKRHV</td>
      <td data-column-id="brakes-off-on"><span>14:10z</span> &ndash; <span>15:15z</span></td></tr>
    <h4>\(monthOfSecond)</h4>
    <tr data-key="\(secondID)"><td data-column-id="date-short">3 Sep</td>
      <td data-column-id="from-to">KRHVKSQL</td>
      <td data-column-id="brakes-off-on">? &ndash; ?</td></tr>
    </table></body></html>
    """
  }

  private func write(
    page: String,
    address: String = "https://www.flysto.net/logs?aircraft=ac12ab",
    to folder: TemporaryDirectory
  ) throws -> (archive: URL, csv: URL) {
    let archive = folder.url.appending(path: "list.webarchive")
    let encoder = PropertyListEncoder()
    encoder.outputFormat = .binary
    try encoder.encode(Archive(main: .init(url: address, data: Data(page.utf8)))).write(to: archive)
    let csv = folder.url.appending(path: "export.csv")
    try Data(Self.csv.utf8).write(to: csv)
    return (archive, csv)
  }

  @Test
  func `pairs saved rows with export rows and records the export digest`() async throws {
    let folder = try TemporaryDirectory()
    let files = try write(page: Self.page(), to: folder)

    let index = try await FlyStoLinkIndex.read(archive: files.archive, csv: files.csv)

    #expect(
      index.rows == [
        3: URL(string: "https://www.flysto.net/logs/abcd1234")!,
        4: URL(string: "https://www.flysto.net/logs/zzzz9999")!
      ]
    )
    #expect(index.sha256 == (try sha256Hex(of: files.csv)))
  }

  @Test
  func `rejects an archive whose month headings disagree with the export`() async throws {
    let folder = try TemporaryDirectory()
    let files = try write(page: Self.page(monthOfSecond: "August 2026"), to: folder)

    await #expect(throws: FlightSourceError.self) {
      try await FlyStoLinkIndex.read(archive: files.archive, csv: files.csv)
    }
  }

  @Test
  func `rejects an archive of some other page`() async throws {
    let folder = try TemporaryDirectory()
    let files = try write(page: Self.page(), address: "https://example.com/", to: folder)

    await #expect(throws: FlightSourceError.self) {
      try await FlyStoLinkIndex.read(archive: files.archive, csv: files.csv)
    }
  }

  @Test
  func `rejects an identifier that isn't a FlySto flight`() async throws {
    let folder = try TemporaryDirectory()
    let files = try write(page: Self.page(secondID: "NOT-VALID"), to: folder)

    await #expect(throws: FlightSourceError.self) {
      try await FlyStoLinkIndex.read(archive: files.archive, csv: files.csv)
    }
  }

  private struct Archive: Encodable {
    let main: Resource

    private enum CodingKeys: String, CodingKey { case main = "WebMainResource" }

    struct Resource: Encodable {
      let url: String
      let data: Data

      private enum CodingKeys: String, CodingKey {
        case url = "WebResourceURL"
        case data = "WebResourceData"
      }
    }
  }
}
