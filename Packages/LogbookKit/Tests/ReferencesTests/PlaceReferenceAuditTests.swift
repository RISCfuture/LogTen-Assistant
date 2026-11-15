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

@Suite
struct `Place reference audit` {
  private let inCycle = utc("2025-11-10T00:00:00Z")

  private func place(
    _ identifier: String,
    zone: String? = nil,
    latitude: Double? = nil,
    longitude: Double? = nil,
    elevation: Int? = nil
  ) -> Place {
    Place(
      id: RecordID(rawValue: "place-\(identifier)"),
      identifier: identifier,
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
    asOf: Date? = nil
  ) async -> [Finding] {
    let timeZones = zone.map { AirportTimeZones(resolver: FixedResolver(identifier: $0)) }
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
}
