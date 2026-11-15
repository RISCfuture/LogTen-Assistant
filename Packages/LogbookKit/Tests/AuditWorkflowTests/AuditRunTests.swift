import Audit
import AuditWorkflow
import FlightSources
import Foundation
import LogbookModel
import Testing
import Tracks

@Suite
struct `Review queues` {
  @Test(
    arguments: [
      (RuleID.unmatchedTelemetry, ReviewQueue.unmatchedActivity),
      (.ambiguousCorrelation, .unmatchedActivity),
      (SmartGroupRule.nightFullStops.id, .groupsAndCurrency),
      ("telemetry_time", .aircraftComparisons),
      ("seat_time", .logbookConsistency)
    ]
  )
  func `files a rule's findings under its queue`(rule: RuleID, queue: ReviewQueue) {
    #expect(ReviewQueue(rule: rule) == queue)
  }
}

@Suite
struct `Audit run` {
  @Test
  func `orders findings by rule and then identifier`() {
    let findings = ["seat_time", "duplicate", "seat_time"].enumerated().map { index, rule in
      Finding(
        rule: RuleID(rawValue: rule),
        recordIDs: [RecordID(rawValue: "F\(index)")],
        message: ""
      )
    }

    let run = AuditRun(generatedAt: .now, findings: findings)

    #expect(run.findings.map(\.rule.rawValue) == ["duplicate", "seat_time", "seat_time"])
    #expect(run.findings[1].id < run.findings[2].id)
  }

  @Test
  func `finds the track segment behind an unmatched-telemetry finding`() async throws {
    let run = try await AuditRunner().run(
      AuditInputs(
        logbook: logbook([flight("A")]),
        settings: LogbookSettings(),
        tracks: [track(on: "2026-10-14")]
      )
    )

    let finding = try #require(run.findings(in: .unmatchedActivity).first)
    let segment = try #require(run.segment(for: finding))
    #expect(segment.interval.contains(utc("2026-10-14T14:34:00Z")))
  }
}

@Suite
struct `Evidence coverage` {
  /// A flight of `registration` on the given day.
  private static func entry(
    _ id: String,
    registration: String = "N111AA",
    category: AircraftCategory = .airplane,
    day: String = "2026-10-12"
  ) -> Flight {
    var flight = flight(id)
    let shift = utc("\(day)T00:00:00Z").timeIntervalSince(flight.date)
    flight.date = flight.date.addingTimeInterval(shift)
    flight.events = FlightEvents(
      out: flight.events.out?.addingTimeInterval(shift),
      off: flight.events.off?.addingTimeInterval(shift),
      on: flight.events.on?.addingTimeInterval(shift),
      in: flight.events.in?.addingTimeInterval(shift)
    )
    flight.aircraft?.registration = registration
    flight.aircraft?.type?.category = category
    return flight
  }

  @Test
  func `summarizes each registration's flights and the evidence covering them`() async throws {
    let flights = [
      Self.entry("A"),
      Self.entry("B", day: "2026-10-14"),
      Self.entry("C", registration: "N222BB", day: "2026-10-15"),
      Self.entry("S", registration: "SIM1", category: .simulator)
    ]
    let logbook = logbook(flights)
    let run = try await AuditRunner().run(
      AuditInputs(
        logbook: logbook,
        settings: LogbookSettings(),
        flyStoRecords: [record()],
        tracks: [track(on: "2026-10-14")]
      )
    )

    let coverage = run.coverage(of: logbook)

    #expect(coverage.map(\.registration) == ["N111AA", "N222BB"])
    let first = try #require(coverage.first)
    #expect(first.flightCount == 2)
    #expect(first.flyStoCount == 1)
    #expect(first.adsbCount == 1)
    #expect(first.firstFlight == flights[0].date)
    #expect(first.lastFlight == flights[1].date)
    #expect(coverage[1].flyStoCount == 0)
    #expect(coverage[1].adsbCount == 0)
  }
}
