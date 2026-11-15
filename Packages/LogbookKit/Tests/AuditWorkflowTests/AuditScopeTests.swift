import AuditWorkflow
import Foundation
import LogbookModel
import Testing

@Suite
struct `Audit scope` {
  private static let pacific = TimeZone(identifier: "America/Los_Angeles")!
  private static let today = utc("2026-11-06T18:00:00Z")

  /// One finding per flight, for flights dated at the given instants.
  private static func findings(dated dates: [String]) -> (findings: [Finding], logbook: Logbook) {
    let flights = dates.enumerated().map { index, date in
      Flight(id: RecordID(rawValue: "F\(index)"), date: utc(date))
    }
    let findings = flights.map { Finding(rule: "seat_time", recordIDs: [$0.id], message: "") }
    return (findings, logbook(flights))
  }

  private static func scoped(_ scope: AuditScope, _ dates: [String]) -> [String] {
    let (findings, logbook) = findings(dated: dates)
    let scoped = scope.findings(findings, in: logbook, asOf: today, timeZone: pacific)
    return scoped.flatMap(\.recordIDs).map(\.rawValue)
  }

  @Test
  func `reaches back 90 days to midnight in the pilot's time zone`() {
    let dates = ["2026-08-08T06:59:59Z", "2026-08-08T07:00:00Z", "2026-12-01T00:00:00Z"]

    #expect(Self.scoped(.last90Days, dates) == ["F1", "F2"])
  }

  @Test
  func `starts this year on January 1 in the pilot's time zone`() {
    let dates = ["2026-01-01T07:59:59Z", "2026-01-01T08:00:00Z"]

    #expect(Self.scoped(.thisYear, dates) == ["F1"])
    #expect(Self.scoped(.all, dates) == ["F0", "F1"])
  }

  @Test
  func `keeps findings that involve no flight`() {
    let (findings, logbook) = Self.findings(dated: ["2020-01-01T00:00:00Z"])
    let place = Finding(
      rule: "incomplete_place",
      recordIDs: [RecordID(rawValue: "PL")],
      message: ""
    )

    let scoped = AuditScope.last90Days.findings(
      findings + [place],
      in: logbook,
      asOf: Self.today,
      timeZone: Self.pacific
    )

    #expect(scoped == [place])
  }
}
