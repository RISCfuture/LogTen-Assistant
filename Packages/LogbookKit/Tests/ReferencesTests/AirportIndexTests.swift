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
