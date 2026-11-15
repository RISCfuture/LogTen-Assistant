import Foundation
import LogbookModel

extension ConsistencyContext {
  /// Every aircraft type the logbook's aircraft and flights refer to, once each.
  fileprivate var aircraftTypes: [AircraftType] {
    var seen = Set<RecordID>()
    return (logbook.aircraft.compactMap(\.type) + logbook.flights.compactMap { $0.aircraft?.type })
      .filter { seen.insert($0.id).inserted }
  }
}

extension Person {
  fileprivate var hasNoIdentity: Bool {
    name.isBlank && firstName.isMissing && lastName.isMissing && personID.isMissing
  }
}

extension AircraftCategory? {
  /// Whether aircraft of the category are classified into classes; an unknown category might be.
  fileprivate var hasClasses: Bool {
    switch self {
      case .glider, .poweredLift: false
      case let category?: !category.isSimulationDevice
      case nil: true
    }
  }
}

extension String {
  fileprivate var isBlank: Bool { allSatisfy(\.isWhitespace) }
}

extension String? {
  fileprivate var isMissing: Bool { self?.isBlank ?? true }
}

/// Flags aircraft types missing a category, class or engine type. Gliders and powered-lift
/// aircraft have no class, and simulators and training devices have neither class nor engine
/// type, so those aren't asked for.
struct AircraftTypeClassificationCheck: ConsistencyCheck {
  var rules: [ConsistencyRule] { [.aircraftTypeClassification] }

  func check(_ context: ConsistencyContext, into collector: inout FindingCollector) {
    for type in context.aircraftTypes {
      var missing = [String]()
      if type.category == nil { missing.append("category") }
      if type.aircraftClass == nil && type.category.hasClasses { missing.append("class") }
      if type.engineType == nil && !(type.category?.isSimulationDevice ?? false) {
        missing.append("engine_type")
      }
      guard !missing.isEmpty else { continue }
      collector.emit(
        .aircraftTypeClassification,
        [type.id],
        message: String(
          localized: "The aircraft type is missing a category, class or engine type.",
          bundle: .module
        ),
        evidence: ["type": .string(type.type), "missing": .array(missing.map { .string($0) })],
        explanation: String(
          localized:
            "Category, class and engine type decide which totals and currency rules the aircraft’s flights count toward.",
          bundle: .module
        ),
        recommendation: String(
          localized:
            "Fill in the missing details on the aircraft type. If the type is intentionally unclassified, keep it as logged.",
          bundle: .module
        )
      )
    }
  }
}

/// Flags aircraft types with no identifying type.
struct AircraftTypeIdentifierCheck: ConsistencyCheck {
  var rules: [ConsistencyRule] { [.aircraftTypeIdentifier] }

  func check(_ context: ConsistencyContext, into collector: inout FindingCollector) {
    for type in context.aircraftTypes where type.type.isBlank {
      collector.emit(
        .aircraftTypeIdentifier,
        [type.id],
        message: String(
          localized: "The aircraft type has no type designator.",
          bundle: .module
        ),
        evidence: [
          "make": type.make.map { .string($0) } ?? .null,
          "model": type.model.map { .string($0) } ?? .null
        ],
        explanation: String(
          localized:
            "The type designator is how the aircraft type is recognized in reports and type-rating checks.",
          bundle: .module
        ),
        recommendation: String(
          localized:
            "Enter the type designator. If the type is intentionally unnamed, keep it as logged.",
          bundle: .module
        )
      )
    }
  }
}

/// Flags aircraft with neither an aircraft ID nor a secondary ID, or with no aircraft type.
struct IncompleteAircraftCheck: ConsistencyCheck {
  var rules: [ConsistencyRule] { [.incompleteAircraft] }

  func check(_ context: ConsistencyContext, into collector: inout FindingCollector) {
    for aircraft in context.logbook.aircraft {
      var missing = [String]()
      if aircraft.registration.isBlank && aircraft.secondaryID.isMissing {
        missing.append("aircraft_id")
      }
      if aircraft.type == nil { missing.append("type") }
      guard !missing.isEmpty else { continue }
      collector.emit(
        .incompleteAircraft,
        [aircraft.id],
        message: String(
          localized: "The aircraft is missing its aircraft ID or its type.",
          bundle: .module
        ),
        evidence: [
          "aircraft_id": .string(aircraft.registration),
          "missing": .array(missing.map { .string($0) })
        ],
        explanation: String(
          localized:
            "An aircraft needs an identifier to be told apart from others and a type to count its flights correctly.",
          bundle: .module
        ),
        recommendation: String(
          localized:
            "Fill in the missing details on the aircraft. If the record is intentionally sparse, keep it as logged.",
          bundle: .module
        )
      )
    }
  }
}

/// Flags places with neither a code nor a name.
struct IncompletePlaceCheck: ConsistencyCheck {
  var rules: [ConsistencyRule] { [.incompletePlace] }

  func check(_ context: ConsistencyContext, into collector: inout FindingCollector) {
    for place in context.logbook.places
    where place.identifier.isBlank && place.ICAO.isMissing && place.FAAID.isMissing
      && place.IATA.isMissing && place.name.isMissing
    {
      collector.emit(
        .incompletePlace,
        [place.id],
        message: String(localized: "The place has no code and no name.", bundle: .module),
        evidence: ["place": .string(place.id.rawValue)],
        explanation: String(
          localized:
            "A place with neither a code nor a name can’t be recognized on the flights that use it.",
          bundle: .module
        ),
        recommendation: String(
          localized:
            "Enter an airport code or a name, or remove the place if nothing uses it. If the record is intentional, keep it as logged.",
          bundle: .module
        )
      )
    }
  }
}

/// Flags people with no name and no ID.
struct IncompletePersonCheck: ConsistencyCheck {
  var rules: [ConsistencyRule] { [.incompletePerson] }

  func check(_ context: ConsistencyContext, into collector: inout FindingCollector) {
    for person in context.logbook.people where person.hasNoIdentity {
      collector.emit(
        .incompletePerson,
        [person.id],
        message: String(localized: "The person has no name or ID.", bundle: .module),
        evidence: ["person": .string(person.id.rawValue)],
        explanation: String(
          localized:
            "A person without a name can’t be recognized in the crew of the flights that list them.",
          bundle: .module
        ),
        recommendation: String(
          localized:
            "Enter the person’s name, or remove the record if nothing uses it. If the record is intentional, keep it as logged.",
          bundle: .module
        )
      )
    }
  }
}
