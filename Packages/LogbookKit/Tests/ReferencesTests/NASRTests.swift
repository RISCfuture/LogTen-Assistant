import Foundation
import References
import Testing

@Suite
struct `NASR airports` {
  @Test
  func `loads airports and runway ends from a CSV distribution`() async throws {
    let index = try await NASRAirportLoader.load(
      from: fixtureURL("NASR/30_Oct_2025_CSV")
    )

    #expect(index.effectiveDate == utc("2025-10-30T00:00:00Z"))
    #expect(index.airports.count == 2)
    #expect(index.runwayEnds.count == 4)
    let sanCarlos = try #require(index.airport(matching: "KSQL"))
    #expect(sanCarlos.locationID == "SQL")
    #expect(abs(sanCarlos.latitudeDeg - 37.5119) < 0.0001)
    #expect(index.airport(onRunwayAtLatitudeDeg: 37.5124, longitudeDeg: -122.2518) != nil)
  }

  @Test
  func `saves a cycle and reads it back by any date in the cycle`() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: "nasr-store-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = NASRCycleStore(directory: directory)
    let index = try await NASRAirportLoader.load(from: fixtureURL("NASR/30_Oct_2025_CSV"))

    try await store.save(index)
    let reopened = NASRCycleStore(directory: directory)

    #expect(await reopened.savedCycles() == [utc("2025-10-30T00:00:00Z")])
    let found = try await reopened.savedIndex(covering: utc("2025-11-10T12:00:00Z"))
    #expect(found?.airports.count == 2)
    #expect(try await reopened.savedIndex(covering: utc("2025-12-10T12:00:00Z")) == nil)
  }
}
