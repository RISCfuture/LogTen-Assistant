import Foundation
import LogbookModel

/// In-memory logbooks for the consistency-rule tests.
enum ConsistencyFixtures {
  static let skyhawk = Aircraft(
    id: "A-N12345",
    registration: "N12345",
    type: Self.classified(id: "T-C172", type: "C172", category: .airplane)
  )
  static let cirrus = Aircraft(
    id: "A-N54321",
    registration: "N54321",
    type: Self.classified(id: "T-SR22", type: "SR22", category: .airplane)
  )
  static let simulator = Aircraft(
    id: "A-SIM",
    registration: "SIM1",
    type: Self.classified(id: "T-SIM", type: "FTD", category: .simulator)
  )
  static let sanCarlos = Place(id: "PL-SQL", identifier: "SQL", ICAO: "KSQL")
  static let halfMoonBay = Place(id: "PL-HAF", identifier: "HAF", ICAO: "KHAF")

  static let nightFullStops = LogTenFieldKey.custom(.flightLanding, 5)
  static let simInstrument = LogTenFieldKey.custom(.flightTime, 1)
  static let totalLandings = LogTenFieldKey(.flight, "totalLandings")

  static var settings: LogbookSettings {
    var settings = LogbookSettings()
    try? settings.fieldMapping.assign(nightFullStops, to: .nightFullStops)
    return settings
  }

  /// The flights whose finding identifiers were computed by cleanup-logten's `audit.py` and
  /// `expanded_audit.py` for the same values.
  static var cleanupComparison: Logbook {
    Logbook(
      identity: LogbookIdentity(storeUUID: UUID()),
      flights: [
        flight("F-counts", day: 10, out: time(10, 15), in: time(10, 16, 30)) { flight in
          flight.times.night = 70
          flight.counts.nightLandings = 3
          flight[field: totalLandings] = .integer(2)
          flight[field: nightFullStops] = .integer(1)
          flight[field: simInstrument] = .integer(80)
        },
        flight("F-order", day: 11, out: time(11, 10), off: time(11, 9, 50), in: time(11, 11)),
        flight("F-long", day: 12, totalMinutes: 1200),
        flight("F-overlap-1", day: 13, out: time(13, 10), in: time(13, 11), to: sanCarlos),
        flight(
          "F-overlap-2",
          day: 13,
          out: time(13, 10, 30),
          in: time(13, 11, 30),
          aircraft: cirrus,
          to: sanCarlos
        ) { $0.remarks = "Different flight" }
      ],
      aircraft: [skyhawk, cirrus],
      customFields: [CustomFieldDefinition(key: simInstrument, title: "Sim Instrument")]
    )
  }

  /// An aircraft type with every classification filled in.
  static func classified(id: RecordID, type: String, category: AircraftCategory) -> AircraftType {
    AircraftType(
      id: id,
      type: type,
      category: category,
      aircraftClass: .singleEngineLand,
      engineType: .reciprocating
    )
  }

  /// A UTC time on a day in January 2026.
  static func time(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    var components = DateComponents(year: 2026, month: 1, day: day, hour: hour, minute: minute)
    components.timeZone = .gmt
    return Calendar(identifier: .gregorian).date(from: components)!
  }

  /// A flight in the Skyhawk from San Carlos to Half Moon Bay.
  static func flight(
    _ id: RecordID,
    day: Int,
    totalMinutes: UInt = 60,
    out: Date? = nil,
    off: Date? = nil,
    in: Date? = nil,
    aircraft: Aircraft = skyhawk,
    to: Place = halfMoonBay,
    configure: (inout Flight) -> Void = { _ in }
  ) -> Flight {
    var flight = Flight(
      id: id,
      date: time(day, 0),
      aircraft: aircraft,
      from: sanCarlos,
      to: to,
      events: FlightEvents(out: out, off: off, in: `in`),
      times: FlightTimes(total: totalMinutes, PIC: totalMinutes)
    )
    configure(&flight)
    return flight
  }

  static func logbook(_ flights: [Flight]) -> Logbook {
    Logbook(
      identity: LogbookIdentity(storeUUID: UUID()),
      flights: flights,
      aircraft: [skyhawk, cirrus, simulator],
      places: [sanCarlos, halfMoonBay]
    )
  }
}
