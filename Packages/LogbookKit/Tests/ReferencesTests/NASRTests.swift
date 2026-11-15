import Foundation
import SwiftNASR
import Testing

@testable import References

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
  func `saves a cycle and reads it back by any date in the cycle, ignoring other files`()
    async throws
  {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: "nasr-store-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = NASRCycleStore(directory: directory)
    let index = try await NASRAirportLoader.load(from: fixtureURL("NASR/30_Oct_2025_CSV"))

    try await store.save(index)
    for name in ["notes.txt", "nasr-latest.json", "nasr-2025-10-30.bak"] {
      try Data().write(to: directory.appending(path: name))
    }
    let reopened = NASRCycleStore(directory: directory)

    #expect(await reopened.savedCycles() == [utc("2025-10-30T00:00:00Z")])
    let found = try await reopened.savedIndex(covering: utc("2025-11-10T12:00:00Z"))
    #expect(found?.airports.count == 2)
    #expect(try await reopened.savedIndex(covering: utc("2025-12-10T12:00:00Z")) == nil)
  }

  @Test
  func `takes the downloaded cycle when the distribution names none`() async throws {
    let unnamed = try copyOfFixture("NASR/30_Oct_2025_CSV", named: "airports")
    defer { try? FileManager.default.removeItem(at: unnamed.deletingLastPathComponent()) }
    let cycle = try #require(Cycle.effectiveCycle(for: utc("2025-11-10T00:00:00Z")))

    let index = try await NASRAirportLoader.index(
      from: .fromLocalDirectory(unnamed, format: .csv),
      downloadedCycle: cycle
    )
    #expect(index.effectiveDate == utc("2025-10-30T00:00:00Z"))
    await #expect {
      try await NASRAirportLoader.index(from: .fromLocalDirectory(unnamed, format: .csv))
    } throws: { error in
      if case .unknownCycle = error as? ReferenceDataError { true } else { false }
    }
  }

  private func copyOfFixture(_ path: String, named name: String) throws -> URL {
    let copy = FileManager.default.temporaryDirectory
      .appending(path: "nasr-\(UUID().uuidString)")
      .appending(path: name)
    try FileManager.default.createDirectory(
      at: copy.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try FileManager.default.copyItem(at: fixtureURL(path), to: copy)
    return copy
  }
}
