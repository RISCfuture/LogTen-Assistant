import CryptoKit
import Foundation
import LogbookModel

/// A small synthetic logbook for previews and UI tests, built so that several regulations find
/// violations, one rule can't run for lack of a mapped field, and one consistency check offers
/// alternative corrections.
///
/// UI tests open it with the `-UITestFixture sample` launch argument; it never touches LogTen's
/// files.
nonisolated struct SampleLogbook: Sendable {
  /// The fixture's name in the `-UITestFixture` launch argument.
  static let standardName = "sample"

  /// A reference that opens the fixture in a logbook window.
  static var reference: LogbookReference {
    LogbookReference(fixture: standardName, displayName: String(localized: "Sample Logbook"))
  }

  /// The logbook's records.
  let logbook: Logbook

  /// Settings for the logbook, with its custom fields mapped.
  let settings: LogbookSettings

  /// The fixture with a name, if there is one.
  init?(named name: String) {
    guard name == Self.standardName else { return nil }
    self.init()
  }

  private init() {
    logbook = Logbook(
      identity: LogbookIdentity(storeUUID: Self.storeUUID, modelVersionIdentifiers: ["sample"]),
      flights: Self.flights,
      aircraft: [Self.skyhawk, Self.visionJet, Self.warrior],
      people: [Self.me, Self.passenger, Self.safetyPilot, Self.instructor],
      places: [Self.paloAlto, Self.sanCarlos, Self.monterey],
      customFields: Self.customFields,
      fingerprints: Self.fingerprints(of: Self.flights)
    )
    settings = LogbookSettings(
      pilot: PilotProfile(
        certificateLevel: .private,
        categoryClassRatings: [.airplaneSingleEngineLand],
        instrumentRatings: [.airplane],
        homeTimeZone: Self.timeZone,
        ownerPersonID: Self.me.id
      ),
      fieldMapping: .suggested(for: Self.customFields)
    )
  }
}

// MARK: - Records

nonisolated extension SampleLogbook {
  // swiftlint:disable:next force_unwrapping
  private static let storeUUID = UUID(uuidString: "5A3B1C0D-0000-4000-8000-00000000A001")!
  private static let timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .gmt

  private static let nightFullStops = CustomFieldSlot(kind: .flightLanding, number: 1).key
  private static let checkride = CustomFieldSlot(kind: .flightNote, number: 1).key
  private static let proficiencyCheck = CustomFieldSlot(kind: .flightNote, number: 2).key
  private static let safetyPilotSlot = CustomFieldSlot(kind: .flightCrew, number: 1)
  private static let tracking = CustomFieldSlot(kind: .flightOperation, number: 1).key
  private static let formationTime = CustomFieldSlot(kind: .flightTime, number: 1).key

  private static let customFields = [
    CustomFieldDefinition(key: nightFullStops, title: "Night Full Stops", defaultTitle: "Custom 1"),
    CustomFieldDefinition(key: checkride, title: "Checkride", defaultTitle: "Custom Note 1"),
    CustomFieldDefinition(key: proficiencyCheck, title: "FAR 61.58", defaultTitle: "Custom Note 2"),
    CustomFieldDefinition(key: safetyPilotSlot.key, title: "Safety Pilot", defaultTitle: "Crew 1"),
    CustomFieldDefinition(key: tracking, title: "Intercept/Tracking", defaultTitle: "Custom Op 1"),
    CustomFieldDefinition(key: formationTime, title: "Formation", defaultTitle: "Custom Time 1")
  ]

  private static let me = Person(
    id: RecordID(rawValue: "person-me"),
    name: "Alex Aviator",
    isMe: true
  )
  private static let passenger = Person(id: RecordID(rawValue: "person-pat"), name: "Pat Passenger")
  private static let safetyPilot = Person(id: RecordID(rawValue: "person-sam"), name: "Sam Safety")
  private static let instructor = Person(
    id: RecordID(rawValue: "person-chris"),
    name: "Chris Instructor"
  )

  private static let paloAlto = Place(
    id: RecordID(rawValue: "place-pao"),
    identifier: "PAO",
    ICAO: "KPAO",
    FAAID: "PAO",
    name: "Palo Alto",
    latitudeDeg: 37.461,
    longitudeDeg: -122.115
  )
  private static let sanCarlos = Place(
    id: RecordID(rawValue: "place-sql"),
    identifier: "SQL",
    ICAO: "KSQL",
    FAAID: "SQL",
    name: "San Carlos",
    latitudeDeg: 37.512,
    longitudeDeg: -122.250
  )
  private static let monterey = Place(
    id: RecordID(rawValue: "place-mry"),
    identifier: "MRY",
    ICAO: "KMRY",
    FAAID: "MRY",
    name: "Monterey Regional",
    latitudeDeg: 36.587,
    longitudeDeg: -121.843
  )

  private static let skyhawk = Aircraft(
    id: RecordID(rawValue: "aircraft-n4321k"),
    registration: "N4321K",
    type: AircraftType(
      id: RecordID(rawValue: "type-c172"),
      type: "C172",
      make: "Cessna",
      model: "172S Skyhawk",
      category: .airplane,
      aircraftClass: .singleEngineLand,
      engineType: .reciprocating
    ),
    weightLbs: 2_550
  )

  private static let visionJet = Aircraft(
    id: RecordID(rawValue: "aircraft-n529sf"),
    registration: "N529SF",
    type: AircraftType(
      id: RecordID(rawValue: "type-sf50"),
      type: "SF50",
      make: "Cirrus",
      model: "Vision Jet",
      category: .airplane,
      aircraftClass: .singleEngineLand,
      engineType: .jet
    ),
    weightLbs: 6_000,
    isPressurized: true,
    hasRetractableGear: true
  )

  private static let warrior = Aircraft(
    id: RecordID(rawValue: "aircraft-n2468p"),
    registration: "N2468P",
    type: AircraftType(
      id: RecordID(rawValue: "type-pa28"),
      type: "PA28",
      make: "Piper",
      model: "PA-28-161 Warrior",
      category: .airplane,
      aircraftClass: .singleEngineLand,
      engineType: .reciprocating
    ),
    weightLbs: 2_440
  )

  private static var flights: [Flight] {
    [
      flightReview,
      passengerFlight,
      localPattern,
      nightPassengerFlight,
      jetFlight,
      doubleLoggedFlight
    ]
  }

  private static var flightReview: Flight {
    Flight(
      id: RecordID(rawValue: "flight-001"),
      date: day(2024, 1, 10),
      flightKey: "KEY-001",
      aircraft: skyhawk,
      from: paloAlto,
      to: paloAlto,
      remarks: "Flight review.",
      events: events(on: day(2024, 1, 10), minutes: 72),
      times: FlightTimes(total: 72, PIC: 72, dualReceived: 72),
      counts: FlightCounts(dayTakeoffs: 4, dayLandings: 4, fullStops: 2),
      crew: FlightCrew(PIC: me, instructor: instructor),
      isFlightReview: true
    )
  }

  private static var passengerFlight: Flight {
    Flight(
      id: RecordID(rawValue: "flight-002"),
      date: day(2026, 3, 1),
      flightKey: "KEY-002",
      aircraft: skyhawk,
      from: paloAlto,
      to: monterey,
      distanceNM: 62,
      remarks: "Lunch at Monterey.",
      events: events(on: day(2026, 3, 1), minutes: 90),
      times: FlightTimes(total: 90, PIC: 90, crossCountry: 90),
      counts: FlightCounts(dayTakeoffs: 1, dayLandings: 1, fullStops: 1),
      crew: FlightCrew(PIC: me),
      passengers: [passenger]
    )
  }

  private static var localPattern: Flight {
    Flight(
      id: RecordID(rawValue: "flight-003"),
      date: day(2026, 3, 15),
      flightKey: "KEY-003",
      aircraft: skyhawk,
      from: sanCarlos,
      to: sanCarlos,
      events: events(on: day(2026, 3, 15), minutes: 60),
      times: FlightTimes(total: 60, PIC: 60),
      counts: FlightCounts(dayTakeoffs: 3, dayLandings: 3, fullStops: 3),
      crew: FlightCrew(PIC: me)
    )
  }

  private static var nightPassengerFlight: Flight {
    Flight(
      id: RecordID(rawValue: "flight-004"),
      date: day(2026, 4, 2),
      flightKey: nil,
      isLocked: true,
      aircraft: skyhawk,
      from: monterey,
      to: paloAlto,
      distanceNM: 62,
      events: events(on: day(2026, 4, 2), minutes: 66),
      times: FlightTimes(total: 66, PIC: 66, night: 60, crossCountry: 66),
      counts: FlightCounts(nightTakeoffs: 1, nightLandings: 1, fullStops: 1),
      crew: FlightCrew(PIC: me),
      passengers: [passenger],
      customValues: [nightFullStops: .integer(1)]
    )
  }

  private static var jetFlight: Flight {
    Flight(
      id: RecordID(rawValue: "flight-005"),
      date: day(2026, 5, 20),
      flightKey: "KEY-005",
      aircraft: visionJet,
      from: sanCarlos,
      to: monterey,
      distanceNM: 70,
      events: events(on: day(2026, 5, 20), minutes: 48),
      times: FlightTimes(total: 48, PIC: 48, crossCountry: 48),
      counts: FlightCounts(dayTakeoffs: 1, dayLandings: 1, fullStops: 1),
      crew: FlightCrew(PIC: me, custom: [safetyPilotSlot.number: safetyPilot]),
      customValues: [safetyPilotSlot.key: .text(safetyPilot.name)]
    )
  }

  /// A local flight shortly after the flight review that logs the whole hour as both PIC and
  /// SIC, so Seat Time offers to clear either one.
  private static var doubleLoggedFlight: Flight {
    Flight(
      id: RecordID(rawValue: "flight-006"),
      date: day(2024, 2, 15),
      flightKey: "KEY-006",
      aircraft: warrior,
      from: paloAlto,
      to: paloAlto,
      events: events(on: day(2024, 2, 15), minutes: 60),
      times: FlightTimes(total: 60, PIC: 60, SIC: 60),
      counts: FlightCounts(dayTakeoffs: 1, dayLandings: 1, fullStops: 1),
      crew: FlightCrew(PIC: me)
    )
  }

  /// Fingerprints each flight by the SHA-256 of its JSON encoding, as the store reader
  /// fingerprints records by their attributes.
  private static func fingerprints(of flights: [Flight]) -> [RecordID: RecordFingerprint] {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    return Dictionary(
      uniqueKeysWithValues: flights.map { flight in
        let data = (try? encoder.encode(flight)) ?? Data()
        let bytes = SHA256.hash(data: data).map { ($0 < 0x10 ? "0" : "") + String($0, radix: 16) }
        return (flight.id, RecordFingerprint(rawValue: bytes.joined()))
      }
    )
  }

  private static func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let components = DateComponents(year: year, month: month, day: day, hour: 12)
    return calendar.date(from: components) ?? .distantPast
  }

  private static func events(on date: Date, minutes: Int) -> FlightEvents {
    let out = date.addingTimeInterval(-3_600)
    return FlightEvents(
      out: out,
      off: out.addingTimeInterval(600),
      on: out.addingTimeInterval(Double(minutes - 5) * 60),
      in: out.addingTimeInterval(Double(minutes) * 60)
    )
  }
}
