import Foundation
import LogbookModel

@testable import Regulations

/// A pilot, a field mapping and a set of flights, evaluated by the engine.
struct Scenario {
  static let roleKeys: [FieldRole: LogTenFieldKey] = [
    .nightFullStops: .custom(.flightLanding, 5),
    .checkride: .custom(.flightNote, 1),
    .proficiencyCheck: .custom(.flightNote, 2),
    .nightVisionGoggleProficiencyCheck: .custom(.flightNote, 3),
    .interceptingAndTracking: .custom(.flightNote, 4),
    .safetyPilot: .custom(.flightCrew, 1),
    .simulatorType: .custom(.aircraftTypeAttribute, 1),
    .simulatorCategoryClass: .custom(.aircraftTypeAttribute, 2),
    .typeCode: .custom(.aircraftTypeAttribute, 3)
  ]

  var settings: LogbookSettings
  var flights: [Flight]

  init(
    flights: [Flight] = [],
    configure: (inout LogbookSettings) -> Void = { _ in }
  ) {
    var settings = Self.defaultSettings()
    configure(&settings)
    self.settings = settings
    self.flights = flights
  }

  /// A private pilot with an instrument airplane rating and an instructor certificate, in UTC,
  /// with every field role mapped.
  static func defaultSettings() -> LogbookSettings {
    var settings = LogbookSettings()
    settings.pilot = PilotProfile(
      certificateLevel: .commercial,
      instrumentRatings: [.airplane],
      instructorRatings: [.airplaneSingleEngine],
      homeTimeZone: TimeZone(identifier: "UTC")!
    )
    do {
      for (role, key) in roleKeys { try settings.fieldMapping.assign(key, to: role) }
    } catch {
      fatalError("\(error)")
    }
    return settings
  }

  /// The violations of a rule found by the engine.
  func violations(of rule: RegulationRule) async throws -> [Violation] {
    try await RegulationEngine(settings: settings).evaluate(flights).violations(of: rule)
  }

  /// The identifiers of the flights that violate a rule.
  func flagged(by rule: RegulationRule) async throws -> Set<String> {
    Set(try await violations(of: rule).map(\.flightID.rawValue))
  }
}

/// A calendar date at noon UTC.
func day(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(identifier: "UTC")!
  return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
}

extension Flight {
  /// A one-hour pilot-in-command flight in a Cessna.
  static func fixture(
    _ id: String,
    _ date: Date,
    in aircraft: Aircraft = .cessna,
    _ configure: (inout Flight) -> Void = { _ in }
  ) -> Flight {
    var flight = Flight(id: RecordID(rawValue: id), date: date, aircraft: aircraft)
    flight.times.total = 60
    flight.times.PIC = 60
    configure(&flight)
    return flight
  }

  /// A flight of three day takeoffs and landings, as for currency.
  static func landings(
    _ id: String,
    _ date: Date,
    in aircraft: Aircraft = .cessna,
    _ configure: (inout Flight) -> Void = { _ in }
  ) -> Flight {
    fixture(id, date, in: aircraft) {
      $0.counts.dayTakeoffs = 3
      $0.counts.dayLandings = 3
      $0.counts.fullStops = 3
      configure(&$0)
    }
  }

  mutating func mark(_ role: FieldRole) {
    self[field: Scenario.roleKeys[role]!] = .text("Y")
  }

  mutating func carryPassenger() {
    passengers = [Person(id: RecordID(rawValue: "passenger"), name: "Passenger")]
  }
}

extension AircraftType {
  static func fixture(
    _ code: String,
    category: AircraftCategory = .airplane,
    aircraftClass: AircraftClass? = .singleEngineLand,
    engine: EngineType = .reciprocating,
    isMultiPilot: Bool = false
  ) -> Self {
    Self(
      id: RecordID(rawValue: "type-\(code)"),
      type: code,
      category: category,
      aircraftClass: aircraftClass,
      engineType: engine,
      isMultiPilot: isMultiPilot
    )
  }
}

extension Aircraft {
  static let cessna = fixture("N172", type: .fixture("C172"))
  static let tailwheel = fixture("N140", type: .fixture("C140"), isTailwheel: true)
  static let twin = fixture(
    "N58",
    type: .fixture("BE58", aircraftClass: .multiEngineLand),
    weightLbs: 5_500
  )
  static let jet = fixture(
    "N50SF",
    type: .fixture("SF50", engine: .turbofan),
    weightLbs: 6_000
  )
  static let airliner = fixture(
    "N737",
    type: .fixture("B738", aircraftClass: .multiEngineLand, engine: .turbofan, isMultiPilot: true),
    weightLbs: 174_000
  )
  static let helicopter = fixture(
    "N44",
    type: .fixture("R44", category: .rotorcraft, aircraftClass: .helicopter)
  )

  static func fixture(
    _ registration: String,
    type: AircraftType,
    weightLbs: Double? = 2_500,
    isTailwheel: Bool = false
  ) -> Self {
    Self(
      id: RecordID(rawValue: "aircraft-\(registration)"),
      registration: registration,
      type: type,
      weightLbs: weightLbs,
      isTailwheel: isTailwheel
    )
  }

  /// A simulator that represents `code` as a single-engine land airplane.
  static func simulator(
    representing code: String,
    device: SimulatorType
  ) -> Self {
    var type = AircraftType.fixture("SIM-\(code)-\(device.rawValue)", category: .simulator)
    type.aircraftClass = nil
    type.customValues = [
      Scenario.roleKeys[.simulatorType]!: .text(device.rawValue),
      Scenario.roleKeys[.simulatorCategoryClass]!: .text("ASEL"),
      Scenario.roleKeys[.typeCode]!: .text(code)
    ]
    return fixture("SIM-\(device.rawValue)", type: type, weightLbs: nil)
  }
}
