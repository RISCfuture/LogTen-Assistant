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
    (12_500.0, EngineType.reciprocating, false),
    (12_501.0, .reciprocating, true),
    (3_400.0, .turbofan, true)
  ])
  func `requires a type rating for large or turbine aircraft`(
    weightLbs: Double,
    engine: EngineType,
    required: Bool
  ) {
    let aircraft = Aircraft(
      id: RecordID(rawValue: "A1"),
      registration: "N12345",
      type: AircraftType(
        id: RecordID(rawValue: "T1"),
        type: "TEST",
        category: .airplane,
        engineType: engine
      ),
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
  }
}
