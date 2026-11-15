import Foundation
import LogbookModel
import Testing

import References

private struct FixedResolver: TimeZoneResolving {
  let identifier: String

  // swiftlint:disable:next async_without_await
  func timeZoneIdentifier(latitudeDeg _: Double, longitudeDeg _: Double) async throws -> String? {
    identifier
  }
}

private struct Unreachable: Error {}

private struct FailingResolver: TimeZoneResolving {
  // swiftlint:disable:next async_without_await
  func timeZoneIdentifier(latitudeDeg _: Double, longitudeDeg _: Double) async throws -> String? {
    throw Unreachable()
  }
}

@Suite
struct `Place reference audit` {
  private let inCycle = utc("2025-11-10T00:00:00Z")

  private func place(
    _ identifier: String,
    zone: String? = nil,
    latitude: Double? = nil,
    longitude: Double? = nil,
    elevation: Int? = nil,
    ICAO: String? = nil,
    FAAID: String? = nil
  ) -> Place {
    Place(
      id: RecordID(rawValue: "place-\(identifier)"),
      identifier: identifier,
      ICAO: ICAO,
      FAAID: FAAID,
      latitudeDeg: latitude,
      longitudeDeg: longitude,
      elevationFt: elevation,
      timeZoneIdentifier: zone
    )
  }

  private func audit(
    _ places: [Place],
    index: AirportIndex? = sampleIndex(),
    nonAirport: Set<String> = [],
    zone: String? = "America/Los_Angeles",
    resolver: (any TimeZoneResolving)? = nil,
    asOf: Date? = nil
  ) async -> [Finding] {
    let resolver = resolver ?? zone.map(FixedResolver.init(identifier:))
    let timeZones = resolver.map { AirportTimeZones(resolver: $0) }
    return await PlaceReferenceAudit(
      index: index,
      nonAirportPlaces: nonAirport,
      timeZones: timeZones
    )
    .run(on: places, asOf: asOf ?? inCycle)
  }

  @Test
  func `only reports that it can't run without reference data`() async {
    let findings = await audit([place("SQL")], index: nil)

    #expect(findings.map(\.rule) == [.referenceUnavailable])
  }

  @Test
  func `reports a cycle that doesn't cover the audit date and proposes no corrections`() async {
    let findings = await audit(
      [place("SQL", zone: "America/New_York")],
      asOf: utc("2026-03-01T00:00:00Z")
    )

    #expect(findings.map(\.rule).contains(.referenceDate))
    let zone = findings.first { $0.rule == .airportTimeZone }
    #expect(zone != nil)
    #expect(zone?.corrections.isEmpty == true)
  }

  @Test
  func `reports an unmatched place unless it is a known non-airport`() async {
    let places = [place("HOME"), place("MYBASE")]

    let findings = await audit(places, nonAirport: ["home"])

    #expect(findings.map(\.rule) == [.airportUnmatched])
    #expect(findings[0].recordIDs == [RecordID(rawValue: "place-MYBASE")])
  }

  @Test
  func `proposes the airport's time zone when the stored one has different offsets`() async throws {
    let findings = await audit([place("SQL", zone: "America/New_York")])

    let finding = try #require(findings.first { $0.rule == .airportTimeZone })
    #expect(finding.severity == .questionable)
    let change = try #require(finding.corrections.first?.changes.first)
    #expect(change.new == .text("America/Los_Angeles"))
    #expect(change.old == .text("America/New_York"))
  }

  @Test
  func `accepts an alias with the same offsets all year`() async {
    let findings = await audit([place("SQL", zone: "US/Pacific")])

    #expect(findings.isEmpty)
  }

  @Test
  func `reports a position more than half a mile away and an elevation 100 feet off`() async {
    let findings = await audit(
      [
        place(
          "SQL",
          zone: "America/Los_Angeles",
          latitude: 37.53,
          longitude: -122.2495,
          elevation: 150
        )
      ]
    )

    #expect(Set(findings.map(\.rule)) == [.airportPosition, .airportElevation])
  }

  @Test
  func `matches a place by its ICAO or FAA identifier when its own is unknown`() async {
    let places = [
      place("CUSTOM1", ICAO: "KSQL"),
      place("CUSTOM2", FAAID: "SFO"),
      place("CUSTOM3", ICAO: "KXYZ")
    ]

    let findings = await audit(places, zone: nil)

    #expect(findings.map(\.rule) == [.airportUnmatched])
    #expect(findings[0].recordIDs == [RecordID(rawValue: "place-CUSTOM3")])
  }

  @Test
  func `matches a place by its ICAO before its FAA or own identifier`() async {
    let findings = await audit(
      [place("KSFO", zone: "America/New_York", ICAO: "KSQL", FAAID: "SFO")],
      zone: "America/Los_Angeles"
    )

    #expect(findings.first { $0.rule == .airportTimeZone }?.evidence["airport"] == .string("KSQL"))
  }

  @Test
  func `accepts a position within half a mile and an elevation within 100 feet`() async {
    // About 0.3 NM north of San Carlos, and 100 feet above its 5 foot elevation.
    let findings = await audit(
      [
        place(
          "SQL",
          zone: "America/Los_Angeles",
          latitude: 37.5169,
          longitude: -122.2495,
          elevation: 105
        )
      ]
    )

    #expect(findings.isEmpty)
  }

  @Test
  func `reports a place with no stored time zone and proposes setting it`() async throws {
    let findings = await audit([place("SQL")])

    let finding = try #require(findings.first { $0.rule == .airportTimeZone })
    let change = try #require(finding.corrections.first?.changes.first)
    #expect(change.old == .null)
    #expect(change.new == .text("America/Los_Angeles"))
  }

  @Test
  func `reports that time-zone checks were incomplete when a lookup failed`() async {
    let findings = await audit(
      [place("SQL", zone: "America/Los_Angeles")],
      resolver: FailingResolver()
    )

    #expect(findings.map(\.rule) == [.timeZoneUnavailable])
  }
}
