import Foundation
import LogbookModel
import Testing

@Suite
struct `Aircraft classification` {
  @Test
  func `resolves a renamed slot by its title`() {
    #expect(AircraftCategory.resolve(key: "flight_category3", title: "Airplane") == .airplane)
    #expect(EngineType.resolve(key: "flight_engineType1", title: "Turbo-prop") == .turboprop)
    #expect(
      AircraftCategory.resolve(key: "flight_category9", title: "Power-Parachute")
        == .poweredParachute
    )
  }

  @Test
  func `falls back to LogTen's default slot for an unrecognized title`() {
    #expect(AircraftCategory.resolve(key: "flight_category6", title: "My Sims") == .simulator)
    #expect(AircraftClass.resolve(key: "flight_aircraftClass9", title: nil) == .helicopter)
    #expect(AircraftCategory.resolve(key: "flight_category13", title: "") == nil)
  }

  @Test(arguments: [
    (
      AircraftCategory.airplane, 12_500.0 as Double?, EngineType.reciprocating as EngineType?, false
    ),
    (.airplane, 12_501.0, .reciprocating, true),
    (.airplane, 3_400.0, .turbofan, true),
    (.airplane, 3_400.0, .turboprop, true),
    (.poweredLift, 3_000.0, .reciprocating, true),
    (.poweredLift, nil, .reciprocating, true),
    (.airplane, nil, nil, false)
  ])
  func `requires a type rating for large, turbine or powered-lift aircraft`(
    category: AircraftCategory,
    weightLbs: Double?,
    engine: EngineType?,
    required: Bool
  ) {
    let type = engine.map {
      AircraftType(id: RecordID(rawValue: "T1"), type: "TEST", category: category, engineType: $0)
    }
    let aircraft = Aircraft(
      id: RecordID(rawValue: "A1"),
      registration: "N12345",
      type: type,
      weightLbs: weightLbs
    )
    #expect(aircraft.requiresTypeRating == required)
  }

  @Test
  func `parses 24-bit ICAO addresses`() {
    #expect(ICAOAddress(hex: "A3F2C1")?.rawValue == 0xA3_F2C1)
    #expect(ICAOAddress(hex: "1")?.hex == "000001")
    #expect(ICAOAddress(hex: "1000000") == nil)
    #expect(ICAOAddress(hex: "G00000") == nil)
    #expect(ICAOAddress(hex: "") == nil)
    #expect(ICAOAddress(rawValue: 0x100_0000) == nil)
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode([ICAOAddress].self, from: Data(#"["1000000"]"#.utf8))
    }
  }

  @Test(arguments: ["flight_category", "flight_categoryX", "flight_engineType1", "category1"])
  func `resolves nothing from a key that isn't one of its slots`(key: String) {
    #expect(AircraftCategory.resolve(key: key, title: "Unknown") == nil)
  }
}
