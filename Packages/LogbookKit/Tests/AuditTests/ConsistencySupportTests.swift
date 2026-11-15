@testable import Audit
import Foundation
import LogbookModel
import Testing

@Suite
struct `Python-compatible timestamps` {
  @Test(
    arguments: [
      (0.5, "2001-01-01T00:00:00.500000+00:00"),
      (-0.25, "2000-12-31T23:59:59.750000+00:00"),
      (86_400, "2001-01-02T00:00:00+00:00")
    ]
  )
  func `writes isoformat with microseconds only when they are not zero`(
    seconds: Double,
    expected: String
  ) {
    #expect(PythonTimestamp.isoformat(Date(timeIntervalSinceReferenceDate: seconds)) == expected)
  }
}

@Suite
struct `Flight time text` {
  @Test
  func `spells a span in minutes only below a tenth of an hour`() {
    let minutes = Measurement(value: 5, unit: UnitDuration.minutes)
    let tenthOfAnHour = Measurement(value: 0.1, unit: UnitDuration.hours)
    let wholeNumbers = Measurement<UnitDuration>.FormatStyle.measurement(
      width: .wide,
      numberFormatStyle: .number.precision(.fractionLength(0))
    )
    let oneDecimal = Measurement<UnitDuration>.FormatStyle.measurement(
      width: .wide,
      numberFormatStyle: .number.precision(.fractionLength(1))
    )

    #expect(FlightTimeText.span(5) == minutes.formatted(wholeNumbers))
    #expect(FlightTimeText.span(6) == tenthOfAnHour.formatted(oneDecimal))
  }
}

@Suite
struct `Audited flights` {
  private typealias Fixtures = ConsistencyFixtures

  @Test
  func `reads numbers from integers, decimals and Booleans only`() {
    let flight = AuditedFlight(
      Fixtures.flight("F1", day: 1) {
        $0[field: LogTenFieldKey(.flight, "flag")] = .boolean(true)
        $0[field: LogTenFieldKey(.flight, "ratio")] = .number(1.5)
        $0[field: LogTenFieldKey(.flight, "label")] = .text("7")
      }
    )

    #expect(flight.number("flag") == 1)
    #expect(flight.number("ratio") == 1.5)
    #expect(flight.number("label") == nil)
    #expect(flight.number("missing") == nil)
    #expect(flight.hasPositive("flag"))
    #expect(!flight.hasPositive("label"))
  }

  @Test
  func `treats simulator time or a simulator aircraft as a simulator session`() {
    let device = AuditedFlight(Fixtures.flight("F1", day: 1, aircraft: Fixtures.simulator))
    let logged = AuditedFlight(Fixtures.flight("F2", day: 1) { $0.times.simulator = 30 })
    let airborne = AuditedFlight(Fixtures.flight("F3", day: 1))

    #expect(device.isSimulator && logged.isSimulator)
    #expect(!airborne.isSimulator)
  }

  @Test
  func `records Booleans in evidence as SQLite stores them`() {
    #expect(FieldValue.boolean(true).evidenceJSON == .integer(1))
    #expect(FieldValue.boolean(false).evidenceJSON == .integer(0))
  }
}

@Suite
struct `Field titles` {
  private typealias Fixtures = ConsistencyFixtures

  @Test
  func `prefers a custom title, then the built-in title, then the attribute name`() {
    let logbook = Fixtures.cleanupComparison

    #expect(logbook.title(of: Fixtures.simInstrument) == "Sim Instrument")
    #expect(logbook.title(of: .flightPIC) == "PIC")
    #expect(logbook.title(of: LogTenFieldKey(.flight, "unlistedField")) == "unlistedField")
  }
}

@Suite
struct `Finding collection` {
  @Test
  func `keeps enabled rules ordered by rule and identifier, with only their analyses`() {
    var collector = FindingCollector()
    let late = collector.emit(.timeSubset, ["F1"], message: "", evidence: [:])
    let early = collector.emit(.negativeValue, ["F1"], message: "", evidence: [:])
    let sameRule = ["F2", "F3", "F4"].map {
      collector.emit(.timeSubset, [$0], message: "", evidence: [:])
    }
    let dropped = collector.emit(.seatTime, ["F1"], message: "", evidence: [:])
    collector.attach(FindingAnalysis(summary: "kept"), to: early.id)
    collector.attach(FindingAnalysis(summary: "dropped"), to: dropped.id)

    let result = collector.result { $0 != ConsistencyRule.seatTime.id }

    #expect(result.findings.map(\.id) == [early.id] + ([late] + sameRule).map(\.id).sorted())
    #expect(Set(result.analyses.keys) == [early.id])
  }
}
