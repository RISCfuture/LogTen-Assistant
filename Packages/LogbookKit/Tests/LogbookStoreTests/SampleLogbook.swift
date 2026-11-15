import Foundation
import LogbookModel
import LogbookTestSupport

extension SyntheticLogbook {
  static let departure = Date(timeIntervalSinceReferenceDate: 800_000_000)

  /// Two flights in one aircraft: a keyed night flight with crew, passengers, an approach and
  /// custom values, and a locked, signed entry without a key.
  static let sample = Self(
    customFieldTitles: [
      .custom(.flightLanding, 5): "Night Full Stops",
      .custom(.flightCrew, 1): "Safety Pilot",
      .custom(.flightNote, 1): "FAR 61.58",
      .custom(.aircraftTypeAttribute, 4): "Type Code",
      .custom(.flightTime, 2): "Custom 2"
    ],
    people: [
      Person(id: "P-pilot", name: "Pat Pilot", isMe: true),
      Person(id: "P-safety", name: "Sam Safety"),
      Person(id: "P-passenger", name: "Quinn Passenger")
    ],
    places: [
      Place(id: "PL-SQL", identifier: "SQL", ICAO: "KSQL"),
      Place(id: "PL-HAF", identifier: "HAF", ICAO: "KHAF")
    ],
    aircraftTypes: [
      AircraftType(id: "T-SR22T", type: "SR22T", customAttributes: [4: "S22T"])
    ],
    aircraft: [
      Aircraft(id: "A-N12345", registration: "N12345", typeID: "T-SR22T")
    ],
    flights: [
      Flight(
        id: "F-night",
        date: departure,
        aircraftID: "A-N12345",
        fromID: "PL-SQL",
        toID: "PL-HAF",
        values: [
          .flightKey: .text("KEY-1"),
          .flightActualDepartureTime: .date(departure),
          .flightActualArrivalTime: .date(departure + 5_400),
          .flightTotalTime: .integer(90),
          .flightPIC: .integer(90),
          .flightNight: .integer(30),
          .flightNightTakeoffs: .integer(1),
          .flightNightLandings: .integer(2),
          .flightFullStops: .integer(2),
          .flightHobbsStart: .number(1233.4),
          .custom(.flightLanding, 5): .integer(2),
          .custom(.flightNote, 1): .text("PPC with examiner")
        ],
        crew: ["flightCrew_PIC": "P-pilot", "flightCrew_custom1": "P-safety"],
        passengerIDs: ["P-passenger"],
        approaches: [Approach(id: "AP-1", type: "ILS", placeID: "PL-HAF", runway: "12")]
      ),
      Flight(
        id: "F-signed",
        date: departure + 86_400,
        aircraftID: "A-N12345",
        fromID: "PL-HAF",
        toID: "PL-SQL",
        values: [
          .flightIsLocked: .boolean(true),
          .flightTotalTime: .integer(60),
          LogTenFieldKey(.flight, "touchAndGoes"): .integer(3)
        ],
        isSigned: true
      )
    ],
    groups: [
      Group(id: "G-night", name: "Night", predicateFormat: "flight_night > 0"),
      Group(id: "G-signed", name: "Signed", flightIDs: ["F-signed"])
    ]
  )
}
