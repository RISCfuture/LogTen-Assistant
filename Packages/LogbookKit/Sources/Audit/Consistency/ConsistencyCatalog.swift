import Foundation
public import LogbookModel

/// The groups the consistency checks are presented in, following LogTen's Flight Audit, plus
/// groups for checks Flight Audit doesn't have.
public enum ConsistencyCategory: String, CaseIterable, Codable, Sendable {
  /// Entries without the times, aircraft or places they need.
  case missingInformation = "missing_information"
  /// Times that don't fit together.
  case times
  /// Takeoff, landing and approach counts that don't fit together.
  case landingsAndApproaches = "landings_and_approaches"
  /// Entries or records that may repeat one another.
  case duplicateEntries = "duplicate_entries"
  /// Role times that disagree with the crew named.
  case crewAndRoles = "crew_and_roles"
  /// Entries dated in the future.
  case dates
  /// Simulator time and simulator sessions.
  case simulator
  /// Aircraft, aircraft types, people and places that are incomplete or inconsistent.
  case aircraftPeopleAndPlaces = "aircraft_people_and_places"

  /// The category's localized title.
  public var title: String {
    switch self {
      case .missingInformation: String(localized: "Missing Information", bundle: .module)
      case .times: String(localized: "Times", bundle: .module)
      case .landingsAndApproaches: String(localized: "Landings & Approaches", bundle: .module)
      case .duplicateEntries: String(localized: "Duplicate Entries", bundle: .module)
      case .crewAndRoles: String(localized: "Crew & Roles", bundle: .module)
      case .dates: String(localized: "Dates", bundle: .module)
      case .simulator: String(localized: "Simulator", bundle: .module)
      case .aircraftPeopleAndPlaces:
        String(localized: "Aircraft, People & Places", bundle: .module)
    }
  }

  /// The rules in the category, in catalog order.
  public var rules: [ConsistencyRule] { ConsistencyRule.allCases.filter { $0.category == self } }
}

// MARK: - Catalog

extension ConsistencyRule {
  /// The category the rule is presented in.
  public var category: ConsistencyCategory {
    switch self {
      case .landingsWithoutTime, .missingTotalTime, .missingAircraftType, .missingFromTo,
        .missingAircraft:
        .missingInformation
      case .negativeValue, .timeSubset, .seatTime, .nightSeatTime, .timestampOrder, .blockDuration,
        .implausibleDuration, .hobbsTachOrder, .customTimeBounds:
        .times
      case .missingFullStops, .nightFullStopsSubset, .countSubset,
        .approachWithoutInstrumentContext, .approachQuantityMissing:
        .landingsAndApproaches
      case .duplicateExact, .duplicateCandidate, .duplicateReference, .flightOverlap:
        .duplicateEntries
      case .crewSeat, .picNotNamed, .instructionNames, .soloWithInstructor: .crewAndRoles
      case .futureDate: .dates
      case .simulatorTimeInAircraft, .simulatorSessionTime: .simulator
      case .aircraftIFRCapability, .brokenAircraftReference, .aircraftTypeClassification,
        .aircraftTypeIdentifier, .incompleteAircraft, .incompletePlace, .incompletePerson:
        .aircraftPeopleAndPlaces
    }
  }

  /// Whether the rule runs for a logbook whose settings don't turn it on or off.
  public var isEnabledByDefault: Bool { true }

  /// Whether the audit has a check for the rule; a rule without one produces no findings.
  public var isImplemented: Bool { ConsistencyCheckRegistry.implementedRules.contains(self) }

  /// Whether the rule runs under some rule settings.
  public func isEnabled(in settings: RuleSettings) -> Bool {
    settings.isEnabled(id, byDefault: isEnabledByDefault)
  }
}

extension RuleSettings {
  /// Whether a rule runs, taking a consistency rule's default into account.
  public func runs(_ rule: RuleID) -> Bool {
    ConsistencyRule(id: rule)?.isEnabled(in: self) ?? isEnabled(rule)
  }
}

// MARK: - Titles

extension ConsistencyRule {
  /// The rule's localized title, such as “Seat Time”.
  public var title: String {
    switch self {
      case .landingsWithoutTime: String(localized: "Landings Without Time", bundle: .module)
      case .missingTotalTime: String(localized: "Missing Total Time", bundle: .module)
      case .missingAircraftType: String(localized: "Missing Aircraft Type", bundle: .module)
      case .missingFromTo: String(localized: "Missing From or To", bundle: .module)
      case .missingAircraft: String(localized: "Missing Aircraft", bundle: .module)
      case .negativeValue: String(localized: "Negative Value", bundle: .module)
      case .timeSubset: String(localized: "Time Exceeds Total", bundle: .module)
      case .seatTime: String(localized: "Seat Time", bundle: .module)
      case .nightSeatTime: String(localized: "Night Seat Time", bundle: .module)
      case .timestampOrder: String(localized: "Times Out of Order", bundle: .module)
      case .blockDuration: String(localized: "Block Time Disagrees with Total", bundle: .module)
      case .implausibleDuration: String(localized: "Implausible Duration", bundle: .module)
      case .hobbsTachOrder: String(localized: "Hobbs and Tach Order", bundle: .module)
      case .customTimeBounds: String(localized: "Custom Time Exceeds Total", bundle: .module)
      case .missingFullStops: String(localized: "Missing Full Stops", bundle: .module)
      case .nightFullStopsSubset:
        String(localized: "Night Full Stops Exceed Landings", bundle: .module)
      case .countSubset: String(localized: "Counts Exceed Totals", bundle: .module)
      case .approachWithoutInstrumentContext:
        String(localized: "Approach Without Instrument Time", bundle: .module)
      case .approachQuantityMissing: String(localized: "Approach Count Missing", bundle: .module)
      case .duplicateExact: String(localized: "Duplicate Entry", bundle: .module)
      case .duplicateCandidate: String(localized: "Possible Duplicate", bundle: .module)
      case .duplicateReference: String(localized: "Duplicate Record", bundle: .module)
      case .flightOverlap: String(localized: "Overlapping Entries", bundle: .module)
      case .crewSeat: String(localized: "Crew Seat", bundle: .module)
      case .picNotNamed: String(localized: "PIC Not Named", bundle: .module)
      case .instructionNames: String(localized: "Instructor and Student Names", bundle: .module)
      case .soloWithInstructor: String(localized: "Solo with Instructor", bundle: .module)
      case .futureDate: String(localized: "Future Date", bundle: .module)
      case .simulatorTimeInAircraft:
        String(localized: "Simulator Time in an Aircraft", bundle: .module)
      case .simulatorSessionTime: String(localized: "Simulator Session Time", bundle: .module)
      case .aircraftIFRCapability:
        String(localized: "Instrument Time in a VFR Aircraft", bundle: .module)
      case .brokenAircraftReference: String(localized: "Unknown Aircraft", bundle: .module)
      case .aircraftTypeClassification:
        String(localized: "Unclassified Aircraft Type", bundle: .module)
      case .aircraftTypeIdentifier: String(localized: "Unidentified Aircraft Type", bundle: .module)
      case .incompleteAircraft: String(localized: "Incomplete Aircraft", bundle: .module)
      case .incompletePlace: String(localized: "Incomplete Place", bundle: .module)
      case .incompletePerson: String(localized: "Incomplete Person", bundle: .module)
    }
  }
}

// MARK: - Descriptions

extension ConsistencyRule {
  /// A localized one-line description of what the rule looks for.
  public var summary: String {
    switch self {
      case .landingsWithoutTime:
        String(localized: "Takeoffs or landings on an entry with no total time.", bundle: .module)
      case .missingTotalTime:
        String(
          localized: "Past entries with neither total time nor takeoffs and landings.",
          bundle: .module
        )
      case .missingAircraftType:
        String(localized: "Entries that log time without an aircraft type.", bundle: .module)
      case .missingFromTo:
        String(localized: "Entries that log time without a From or a To place.", bundle: .module)
      case .missingAircraft:
        String(localized: "Entries that log time without an aircraft.", bundle: .module)
      case .negativeValue:
        String(localized: "Times and counts below zero.", bundle: .module)
      case .timeSubset:
        String(
          localized:
            "Night, instrument, role or instruction time above total time, or cross-country night above cross-country or night time.",
          bundle: .module
        )
      case .seatTime:
        String(localized: "Role times that don’t fit within total time.", bundle: .module)
      case .nightSeatTime:
        String(
          localized: "Night role times that don’t fit within night time or their role’s time.",
          bundle: .module
        )
      case .timestampOrder:
        String(localized: "Out, off, on and in times entered out of order.", bundle: .module)
      case .blockDuration:
        String(localized: "Out-to-in time that differs from total time.", bundle: .module)
      case .implausibleDuration:
        String(
          localized: "Entries longer than is plausible for their aircraft, such as over 24 hours.",
          bundle: .module
        )
      case .hobbsTachOrder:
        String(
          localized: "Hobbs or tach end readings lower than their start readings.",
          bundle: .module
        )
      case .customTimeBounds:
        String(
          localized: "Custom times chosen in the audit options that exceed total time.",
          bundle: .module
        )
      case .missingFullStops:
        String(localized: "Night full stops logged without total full stops.", bundle: .module)
      case .nightFullStopsSubset:
        String(
          localized: "Night full stops above total full stops or night landings.",
          bundle: .module
        )
      case .countSubset:
        String(
          localized: "Takeoff and landing counts above the totals that contain them.",
          bundle: .module
        )
      case .approachWithoutInstrumentContext:
        String(
          localized: "Approaches logged without actual, simulated or simulator instrument time.",
          bundle: .module
        )
      case .approachQuantityMissing:
        String(localized: "Named approaches with no count.", bundle: .module)
      case .duplicateExact:
        String(localized: "Entries identical to one another.", bundle: .module)
      case .duplicateCandidate:
        String(localized: "Entries that look like one flight logged twice.", bundle: .module)
      case .duplicateReference:
        String(
          localized: "Aircraft, places or aircraft types that share an identifier.",
          bundle: .module
        )
      case .flightOverlap:
        String(localized: "Entries whose out-to-in times overlap.", bundle: .module)
      case .crewSeat:
        String(
          localized: "PIC or SIC time that disagrees with where you’re listed in the crew.",
          bundle: .module
        )
      case .picNotNamed:
        String(
          localized: "SIC or P1 u/s time with no PIC named, where you usually name one.",
          bundle: .module
        )
      case .instructionNames:
        String(
          localized:
            "Dual given or received with a missing or conflicting instructor or student, where you usually name them.",
          bundle: .module
        )
      case .soloWithInstructor:
        String(localized: "Solo time on an entry that names an instructor.", bundle: .module)
      case .futureDate:
        String(
          localized: "Entries dated or timed in the future that already log total time.",
          bundle: .module
        )
      case .simulatorTimeInAircraft:
        String(
          localized: "Simulator or SFI time in an aircraft type that isn’t a simulator.",
          bundle: .module
        )
      case .simulatorSessionTime:
        String(
          localized: "Simulator sessions with total time but no simulator or SFI time.",
          bundle: .module
        )
      case .aircraftIFRCapability:
        String(
          localized: "Instrument time in an aircraft marked not IFR-capable.",
          bundle: .module
        )
      case .brokenAircraftReference:
        String(
          localized: "Entries that refer to an aircraft the logbook doesn’t contain.",
          bundle: .module
        )
      case .aircraftTypeClassification:
        String(
          localized: "Aircraft types without a category, class or engine type.",
          bundle: .module
        )
      case .aircraftTypeIdentifier:
        String(localized: "Aircraft types without an identifying type.", bundle: .module)
      case .incompleteAircraft:
        String(
          localized: "Aircraft with neither an aircraft ID nor a secondary ID, or without a type.",
          bundle: .module
        )
      case .incompletePlace:
        String(localized: "Places with neither a code nor a name.", bundle: .module)
      case .incompletePerson:
        String(localized: "People with neither a name nor an ID.", bundle: .module)
    }
  }
}
