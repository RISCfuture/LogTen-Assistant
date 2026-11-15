public import LogbookModel

/**
 The logbook-consistency rules: arithmetic, ordering, completeness and reference checks that
 need nothing but the logbook itself.

 Raw values are the rule identifiers findings carry. The rules ported from cleanup-logten keep
 its identifiers, so finding identifiers and review decisions stay comparable; the rest cover
 the checks of LogTen's Flight Audit that cleanup-logten has no counterpart for. Each rule has a
 ``category``, ``title`` and ``summary`` to present it by, and ``isImplemented`` says whether
 the audit has a check for it.
 */
public enum ConsistencyRule: String, CaseIterable, Codable, Sendable {
  // MARK: Missing information

  /// Takeoffs or landings are logged on an entry with no total time.
  case landingsWithoutTime = "landings_without_time"
  /// A past entry logs neither total time nor takeoffs and landings, though it may log other
  /// times.
  case missingTotalTime = "missing_total_time"
  /// An entry logs time but has no aircraft type.
  case missingAircraftType = "missing_aircraft_type"
  /// An entry logs time but lacks a From or a To place.
  case missingFromTo = "missing_from_to"
  /// An entry logs time but has no aircraft.
  case missingAircraft = "missing_aircraft"

  // MARK: Times

  /// A time or count is negative.
  case negativeValue = "negative_value"
  /// A time exceeds total time, or cross-country night time exceeds cross-country or night time.
  case timeSubset = "time_subset"
  /// Role times (PIC, SIC, dual received, P1 u/s) don't fit within total time.
  case seatTime = "seat_time"
  /// Night role times don't fit within night time or their own role time.
  case nightSeatTime = "night_seat_time"
  /// Out, off, on and in times are out of order.
  case timestampOrder = "timestamp_order"
  /// The out-to-in interval differs from total time. Entries without total time aren't checked,
  /// since an unlogged total reads as zero.
  case blockDuration = "block_duration"
  /// A flight is longer than the plausible maximum, such as more than 24 hours.
  case implausibleDuration = "implausible_duration"
  /// A Hobbs or tach end reading is lower than its start reading.
  case hobbsTachOrder = "hobbs_tach_order"
  /// A custom time field exceeds total time.
  case customTimeBounds = "custom_time_bounds"

  // MARK: Landings and approaches

  /// Night full stops are logged but total full stops aren't.
  case missingFullStops = "missing_full_stops"
  /// Night full stops exceed total full stops.
  case nightFullStopsSubset = "night_full_stops_subset"
  /// A landing or takeoff count exceeds the count that contains it.
  case countSubset = "count_subset"
  /// Approaches are logged without actual, simulated or simulator instrument time.
  case approachWithoutInstrumentContext = "approach_without_instrument_context"
  /// A named approach records no quantity.
  case approachQuantityMissing = "approach_quantity_missing"

  // MARK: Duplicate entries

  /// Two entries are identical.
  case duplicateExact = "duplicate_exact"
  /// Two entries look like the same flight.
  case duplicateCandidate = "duplicate_candidate"
  /// Several aircraft, places or aircraft types share an identifier.
  case duplicateReference = "duplicate_reference"
  /// Two entries' out-to-in intervals overlap.
  case flightOverlap = "flight_overlap"

  // MARK: Crew and roles

  /// PIC or SIC time disagrees with the pilot's listing in the crew.
  case crewSeat = "crew_seat"
  /// SIC or P1 u/s time is logged without a PIC named, where the pilot usually names one.
  case picNotNamed = "pic_not_named"
  /// Dual given or received is logged with a missing or conflicting instructor or student,
  /// where the pilot usually names them.
  case instructionNames = "instruction_names"
  /// Solo time is logged on an entry that names an instructor.
  case soloWithInstructor = "solo_with_instructor"

  // MARK: Dates

  /// An entry dated or timed in the future already logs total time.
  case futureDate = "future_date"

  // MARK: Simulator

  /// Simulator or SFI time is logged in an aircraft type outside the simulator categories.
  case simulatorTimeInAircraft = "simulator_time_in_aircraft"
  /// A simulator session logs total time but no simulator or SFI time.
  case simulatorSessionTime = "simulator_session_time"

  // MARK: Aircraft, people and places

  /// IFR or actual instrument time is logged in an aircraft marked not IFR-capable.
  case aircraftIFRCapability = "aircraft_ifr_capability"
  /// A flight refers to an aircraft the logbook doesn't contain.
  case brokenAircraftReference = "broken_aircraft_reference"
  /// An aircraft type lacks a category, class or engine type.
  case aircraftTypeClassification = "aircraft_type_classification"
  /// An aircraft type has no identifying type.
  case aircraftTypeIdentifier = "aircraft_type_identifier"
  /// An aircraft lacks both its aircraft ID and secondary ID, or its type.
  case incompleteAircraft = "incomplete_aircraft"
  /// A place has neither a code nor a name.
  case incompletePlace = "incomplete_place"
  /// A person has neither a name nor an ID.
  case incompletePerson = "incomplete_person"

  /// The identifier findings of this rule carry.
  public var id: RuleID { RuleID(rawValue: rawValue) }

  /// The consistency rule a finding's rule identifier names, if it names one.
  public init?(id: RuleID) {
    self.init(rawValue: id.rawValue)
  }
}

/// The smart-group definition checks, which look for groups that can't establish the currency
/// they appear to track.
public enum SmartGroupRule: String, CaseIterable, Codable, Sendable {
  /// An approaches group doesn't test intercepting and tracking.
  case instrumentTracking = "group_instrument_tracking"
  /// A 12-month instrument group, which can only aid recovery.
  case instrumentRecovery = "group_instrument_recovery"
  /// A landings group with a window other than days.
  case passengerWindow = "group_passenger_window"
  /// A night-landings group without night full stops.
  case nightFullStops = "group_night_full_stops"
  /// A flight-review group without the alternatives that also satisfy 14 CFR 61.56.
  case reviewAlternatives = "group_review_alternatives"
  /// A 12-month proficiency-check group, which conflates the 61.58 windows.
  case proficiencyCheckWindows = "group_6158_windows"

  /// The identifier findings of this rule carry.
  public var id: RuleID { RuleID(rawValue: rawValue) }
}

extension CustomRule {
  /// The identifier findings of this custom rule carry: its own identifier prefixed by
  /// `custom.`.
  public var findingRule: RuleID { RuleID(rawValue: "custom.\(id.rawValue)") }
}
