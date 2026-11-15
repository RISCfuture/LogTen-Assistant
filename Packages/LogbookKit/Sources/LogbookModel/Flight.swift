public import Foundation

/// A logbook entry.
///
/// The common fields are typed properties. Every other LogTen attribute is still available by
/// key through ``subscript(field:)``: custom slots live in ``customValues`` and the remaining
/// built-in attributes in ``otherValues``, so audits and custom rules can read any field LogTen
/// stores and proposed changes can name any of them.
public struct Flight: Identifiable, Hashable, Codable, Sendable {
  /// The record identifier.
  public var id: RecordID

  /// LogTen's import key (`flight_key`), which `logten://` packages use to address the entry.
  /// Entries created on some devices or by older versions have none and can't be corrected
  /// through LogTen's import.
  public var flightKey: String?

  /// Whether the entry is locked against editing.
  public var isLocked: Bool

  /// Whether the entry carries a signature, which editing would invalidate.
  public var isSigned: Bool

  /// The date of the flight.
  public var date: Date

  /// The aircraft flown.
  public var aircraft: Aircraft?

  /// The departure place.
  public var from: Place?

  /// The destination place.
  public var to: Place?

  /// The route of flight.
  public var route: String?

  /// The distance flown, in nautical miles.
  public var distanceNM: Double?

  /// The flight number.
  public var flightNumber: String?

  /// Remarks.
  public var remarks: String?

  /// Out, off, on, in and duty times.
  public var events: FlightEvents

  /// Hobbs meter at start.
  public var hobbsStart: Double?
  /// Hobbs meter at stop.
  public var hobbsStop: Double?
  /// Tachometer at start.
  public var tachStart: Double?
  /// Tachometer at stop.
  public var tachStop: Double?

  /// Logged durations.
  public var times: FlightTimes

  /// Logged takeoffs, landings and holds.
  public var counts: FlightCounts

  /// Crew positions.
  public var crew: FlightCrew

  /// Passengers.
  public var passengers: [Person]

  /// Instrument approaches.
  public var approaches: [Approach]

  /// Whether the flight was a flight review (14 CFR 61.56).
  public var isFlightReview: Bool

  /// Whether the flight included an instrument proficiency check (14 CFR 61.57(d)).
  public var isInstrumentProficiencyCheck: Bool

  /// Values of the flight's custom slots, keyed by field key; unset slots are absent.
  ///
  /// Crew slots (`flight_selectedCrewCustom…`) hold the person's name as text; the person
  /// is in ``FlightCrew/custom``.
  public var customValues: [LogTenFieldKey: FieldValue]

  /// Values of built-in attributes without a typed property, keyed by field key; attributes
  /// without a value are absent.
  public var otherValues: [LogTenFieldKey: FieldValue]

  /// The distance flown, if recorded.
  public var distance: Measurement<UnitLength>? {
    distanceNM.map { Measurement(value: $0, unit: .nauticalMiles) }
  }

  /// Creates a flight.
  public init(
    id: RecordID,
    date: Date,
    flightKey: String? = nil,
    isLocked: Bool = false,
    isSigned: Bool = false,
    aircraft: Aircraft? = nil,
    from: Place? = nil,
    to: Place? = nil,
    route: String? = nil,
    distanceNM: Double? = nil,
    flightNumber: String? = nil,
    remarks: String? = nil,
    events: FlightEvents = .init(),
    hobbsStart: Double? = nil,
    hobbsStop: Double? = nil,
    tachStart: Double? = nil,
    tachStop: Double? = nil,
    times: FlightTimes = .init(),
    counts: FlightCounts = .init(),
    crew: FlightCrew = .init(),
    passengers: [Person] = [],
    approaches: [Approach] = [],
    isFlightReview: Bool = false,
    isInstrumentProficiencyCheck: Bool = false,
    customValues: [LogTenFieldKey: FieldValue] = [:],
    otherValues: [LogTenFieldKey: FieldValue] = [:]
  ) {
    self.id = id
    self.date = date
    self.flightKey = flightKey
    self.isLocked = isLocked
    self.isSigned = isSigned
    self.aircraft = aircraft
    self.from = from
    self.to = to
    self.route = route
    self.distanceNM = distanceNM
    self.flightNumber = flightNumber
    self.remarks = remarks
    self.events = events
    self.hobbsStart = hobbsStart
    self.hobbsStop = hobbsStop
    self.tachStart = tachStart
    self.tachStop = tachStop
    self.times = times
    self.counts = counts
    self.crew = crew
    self.passengers = passengers
    self.approaches = approaches
    self.isFlightReview = isFlightReview
    self.isInstrumentProficiencyCheck = isInstrumentProficiencyCheck
    self.customValues = customValues
    self.otherValues = otherValues
  }

  private func values(for key: LogTenFieldKey) -> [LogTenFieldKey: FieldValue] {
    key.customSlot == nil ? otherValues : customValues
  }

  /**
   The value of any `flight_*` attribute, by key.

   Reading a typed field returns its value in LogTen's storage form (minutes and counts as
   integers); reading an unset custom slot or attribute returns ``FieldValue/null``. Writing a
   typed field converts the value back, treating ``FieldValue/null`` as zero, false or no
   value; writing ``FieldValue/null`` to any other field removes it.

   - Precondition: `key` is a flight field.
   */
  public subscript(field key: LogTenFieldKey) -> FieldValue {
    get {
      precondition(key.entity == .flight, "\(key) is not a flight field")
      if let accessor = FlightField.accessors[key] { return accessor.value(of: self) }
      return values(for: key)[key] ?? .null
    }
    set {
      precondition(key.entity == .flight, "\(key) is not a flight field")
      if let accessor = FlightField.accessors[key] {
        accessor.assign(newValue, to: &self)
      } else if key.customSlot != nil {
        customValues[key] = newValue.isNull ? nil : newValue
      } else {
        otherValues[key] = newValue.isNull ? nil : newValue
      }
    }
  }
}

/// The typed ``Flight`` properties that correspond to LogTen attributes.
enum FlightField: Sendable {
  case unsigned(any WritableKeyPath<Flight, UInt> & Sendable)
  case flag(any WritableKeyPath<Flight, Bool> & Sendable)
  case text(any WritableKeyPath<Flight, String?> & Sendable)
  case number(any WritableKeyPath<Flight, Double?> & Sendable)
  case date(any WritableKeyPath<Flight, Date?> & Sendable)
  case flightDate

  static let accessors: [LogTenFieldKey: Self] = [
    .flightKey: .text(\.flightKey),
    .flightIsLocked: .flag(\.isLocked),
    .flightDate: .flightDate,
    .flightRoute: .text(\.route),
    .flightDistance: .number(\.distanceNM),
    .flightNumber: .text(\.flightNumber),
    .flightRemarks: .text(\.remarks),
    .flightActualDepartureTime: .date(\.events.out),
    .flightTakeoffTime: .date(\.events.off),
    .flightLandingTime: .date(\.events.on),
    .flightActualArrivalTime: .date(\.events.in),
    .flightOnDutyTime: .date(\.events.onDuty),
    .flightOffDutyTime: .date(\.events.offDuty),
    .flightHobbsStart: .number(\.hobbsStart),
    .flightHobbsStop: .number(\.hobbsStop),
    .flightTachStart: .number(\.tachStart),
    .flightTachStop: .number(\.tachStop),
    .flightTotalTime: .unsigned(\.times.total),
    .flightPIC: .unsigned(\.times.PIC),
    .flightSIC: .unsigned(\.times.SIC),
    .flightSolo: .unsigned(\.times.solo),
    .flightNight: .unsigned(\.times.night),
    .flightCrossCountry: .unsigned(\.times.crossCountry),
    .flightDualGiven: .unsigned(\.times.dualGiven),
    .flightDualReceived: .unsigned(\.times.dualReceived),
    .flightActualInstrument: .unsigned(\.times.actualInstrument),
    .flightSimulatedInstrument: .unsigned(\.times.simulatedInstrument),
    .flightSimulator: .unsigned(\.times.simulator),
    .flightGround: .unsigned(\.times.ground),
    .flightNightVisionGoggle: .unsigned(\.times.nightVisionGoggle),
    .flightDayTakeoffs: .unsigned(\.counts.dayTakeoffs),
    .flightNightTakeoffs: .unsigned(\.counts.nightTakeoffs),
    .flightDayLandings: .unsigned(\.counts.dayLandings),
    .flightNightLandings: .unsigned(\.counts.nightLandings),
    .flightFullStops: .unsigned(\.counts.fullStops),
    .flightNightVisionGoggleTakeoffs: .unsigned(\.counts.nightVisionGoggleTakeoffs),
    .flightNightVisionGoggleLandings: .unsigned(\.counts.nightVisionGoggleLandings),
    .flightHolds: .unsigned(\.counts.holds),
    .flightReview: .flag(\.isFlightReview),
    .flightInstrumentProficiencyCheck: .flag(\.isInstrumentProficiencyCheck)
  ]

  func value(of flight: Flight) -> FieldValue {
    switch self {
      case .unsigned(let path): .integer(Int(flight[keyPath: path]))
      case .flag(let path): .boolean(flight[keyPath: path])
      case .text(let path): flight[keyPath: path].map(FieldValue.text) ?? .null
      case .number(let path): flight[keyPath: path].map(FieldValue.number) ?? .null
      case .date(let path): flight[keyPath: path].map(FieldValue.date) ?? .null
      case .flightDate: .date(flight.date)
    }
  }

  func assign(_ value: FieldValue, to flight: inout Flight) {
    switch self {
      case .unsigned(let path): flight[keyPath: path] = value.unsignedInteger ?? 0
      case .flag(let path): flight[keyPath: path] = value.isSet
      case .text(let path): flight[keyPath: path] = value.text
      case .number(let path): flight[keyPath: path] = value.number
      case .date(let path): flight[keyPath: path] = value.date
      case .flightDate: if let date = value.date { flight.date = date }
    }
  }
}
