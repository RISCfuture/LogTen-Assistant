import Foundation
import References
import Testing

@Suite
struct `Airport index` {
  @Test
  func `matches an airport by either identifier in any case`() {
    let index = sampleIndex()

    #expect(index.airport(matching: "ksql")?.locationID == "SQL")
    #expect(index.airport(matching: " SFO ")?.ICAOID == "KSFO")
    #expect(index.airport(matching: "KXYZ") == nil)
  }

  @Test
  func `matches no airport when an identifier names several`() {
    let twin = AirportReference(
      locationID: "SQL",
      name: "Another",
      latitudeDeg: 40,
      longitudeDeg: -100
    )
    let index = AirportIndex(
      effectiveDate: utc("2025-10-30T00:00:00Z"),
      airports: sampleIndex().airports + [twin]
    )

    #expect(index.airport(matching: "SQL") == nil)
    #expect(index.airport(matching: "KSQL")?.name == "San Carlos")
  }

  @Test
  func `finds the nearest airport within the limit`() {
    let index = sampleIndex()

    #expect(index.nearestAirport(latitudeDeg: 37.52, longitudeDeg: -122.25)?.locationID == "SQL")
    #expect(index.nearestAirport(latitudeDeg: 37.9, longitudeDeg: -122.25) == nil)
    #expect(
      index.nearestAirport(latitudeDeg: 37.60, longitudeDeg: -122.37)?.locationID == "SFO"
    )
    #expect(
      index.nearestAirport(latitudeDeg: 37.60, longitudeDeg: -122.37, limitNM: 0.1) == nil
    )
  }

  @Test
  func `finds the nearest runway end of an airport`() throws {
    let index = sampleIndex()
    let airport = try #require(index.airport(matching: "SQL"))

    let end = index.nearestRunwayEnd(of: airport, latitudeDeg: 37.5096, longitudeDeg: -122.2463)

    #expect(end?.identifier == "30")
  }

  @Test
  func `puts a position on a runway only inside its corridor`() {
    let index = sampleIndex()

    #expect(
      index.airport(onRunwayAtLatitudeDeg: 37.5124, longitudeDeg: -122.2518)?.locationID == "SQL"
    )
    // Past the end of the runway but within the overshoot allowance.
    #expect(
      index.airport(onRunwayAtLatitudeDeg: 37.5159, longitudeDeg: -122.2542)?.locationID == "SQL"
    )
    // About half a mile beside the runway.
    #expect(index.airport(onRunwayAtLatitudeDeg: 37.5124, longitudeDeg: -122.2330) == nil)
  }

  @Test(arguments: [
    // Across the antimeridian, where longitude cells wrap.
    (latitude: 60.0, airportLongitude: 179.995, queryLongitude: -179.995),
    // Near the pole, where one degree of longitude is a short distance.
    (latitude: 80.0, airportLongitude: 10.0, queryLongitude: 12.0)
  ])
  func `finds an airport in a neighboring longitude cell`(
    latitude: Double,
    airportLongitude: Double,
    queryLongitude: Double
  ) {
    let airport = AirportReference(
      locationID: "FAR",
      name: "Far",
      latitudeDeg: latitude,
      longitudeDeg: airportLongitude
    )
    let index = AirportIndex(effectiveDate: utc("2025-10-30T00:00:00Z"), airports: [airport])

    #expect(
      index.nearestAirport(latitudeDeg: latitude, longitudeDeg: queryLongitude, limitNM: 25)
        == airport
    )
  }

  @Test(arguments: [
    (Double.nan, -122.2518),
    (37.5124, Double.nan),
    (Double.infinity, -122.2518),
    (37.5124, -Double.infinity),
    (1e300, -122.2518)
  ])
  func `puts a position on no runway when it is not on the globe`(
    latitude: Double,
    longitude: Double
  ) {
    #expect(sampleIndex().airport(onRunwayAtLatitudeDeg: latitude, longitudeDeg: longitude) == nil)
  }

  @Test
  func `puts a position on no runway when runways of several airports contain it`() {
    let twin = AirportReference(
      locationID: "TWN",
      name: "Twin",
      latitudeDeg: 37.5,
      longitudeDeg: -122
    )
    let sample = sampleIndex()
    let twinEnds = sample.runwayEnds.filter { $0.airportLocationID == "SQL" }.map {
      RunwayEndReference(
        airportLocationID: "TWN",
        runwayID: $0.runwayID,
        identifier: $0.identifier,
        latitudeDeg: $0.latitudeDeg,
        longitudeDeg: $0.longitudeDeg
      )
    }
    let index = AirportIndex(
      effectiveDate: sample.effectiveDate,
      airports: sample.airports + [twin],
      runwayEnds: sample.runwayEnds + twinEnds
    )

    #expect(index.airport(onRunwayAtLatitudeDeg: 37.5124, longitudeDeg: -122.2518) == nil)
  }

  @Test(arguments: [
    RunwayCase(name: "a helipad", first: "H1", second: "H2"),
    RunwayCase(name: "a number above 36", first: "37", second: "19"),
    RunwayCase(name: "a number below 01", first: "00", second: "18"),
    RunwayCase(name: "a runway under 0.1 NM", first: "12", second: "30", lengthDeg: 0.0005),
    RunwayCase(name: "a runway over 4 NM", first: "12", second: "30", lengthDeg: 0.1)
  ])
  func `ignores runways that are not numbered runways of plausible length`(_ runway: RunwayCase) {
    let airport = AirportReference(
      locationID: "TST",
      name: "Test",
      latitudeDeg: 10,
      longitudeDeg: 10
    )
    let index = AirportIndex(
      effectiveDate: utc("2025-10-30T00:00:00Z"),
      airports: [airport],
      runwayEnds: runway.ends(at: airport)
    )

    #expect(index.airport(onRunwayAtLatitudeDeg: 10.001, longitudeDeg: 10) == nil)
  }

  @Test
  func `covers the 28 days from the effective date`() {
    let index = sampleIndex()

    #expect(index.covers(utc("2025-10-30T00:00:00Z")))
    #expect(index.covers(utc("2025-11-26T23:59:59Z")))
    #expect(!index.covers(utc("2025-11-27T00:00:00Z")))
    #expect(!index.covers(utc("2025-10-29T23:59:59Z")))
  }

  @Test
  func `survives encoding with its lookups intact`() throws {
    let index = sampleIndex()

    let decoded = try JSONDecoder().decode(
      AirportIndex.self,
      from: JSONEncoder().encode(index)
    )

    #expect(decoded.airport(matching: "SFO")?.name == "San Francisco Intl")
    #expect(decoded.airport(onRunwayAtLatitudeDeg: 37.5124, longitudeDeg: -122.2518) != nil)
  }
}

/// A two-ended runway whose shape may make the index ignore it.
struct RunwayCase: Sendable, CustomTestStringConvertible {
  let name: String
  let first: String
  let second: String
  var lengthDeg = 0.02

  var testDescription: String { name }

  /// The runway's ends, running north from the airport's position.
  func ends(at airport: AirportReference) -> [RunwayEndReference] {
    [
      (first, airport.latitudeDeg),
      (second, airport.latitudeDeg + lengthDeg)
    ].map { identifier, latitude in
      RunwayEndReference(
        airportLocationID: airport.locationID,
        runwayID: "\(first)/\(second)",
        identifier: identifier,
        latitudeDeg: latitude,
        longitudeDeg: airport.longitudeDeg
      )
    }
  }
}
