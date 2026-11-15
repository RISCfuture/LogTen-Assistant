/// A LogTen entity whose attributes can be addressed by a ``LogTenFieldKey``.
public enum LogTenEntity: String, CaseIterable, Sendable {
  /// A logbook entry (`Flight`).
  case flight
  /// A specific aircraft, identified by registration (`Aircraft`).
  case aircraft
  /// An aircraft make and model shared by several aircraft (`AircraftType`).
  case aircraftType
  /// An airport or other location (`Place`).
  case place
  /// A crew member or passenger (`Person`).
  case person
  /// An instrument approach logged on a flight (`Approach`).
  case approach

  /// The name of the Core Data entity in LogTen's model.
  public var entityName: String {
    switch self {
      case .flight: "Flight"
      case .aircraft: "Aircraft"
      case .aircraftType: "AircraftType"
      case .place: "Place"
      case .person: "Person"
      case .approach: "Approach"
    }
  }
}

/// The key of a LogTen attribute, such as `flight_totalTime` or `flight_customTime7`.
///
/// Field keys are LogTen's own attribute names. They address values in the Core Data store, in
/// `LogTenCustomizationProperty` titles, and in `logten://` import packages, so a key read from
/// one is valid in the others. Parsing is strict: a key must start with a known entity prefix
/// followed by an underscore and an alphanumeric attribute name.
public struct LogTenFieldKey: RawRepresentable, Hashable, Comparable, Codable,
  CodingKeyRepresentable,
  Sendable,
  CustomStringConvertible
{
  public let rawValue: String

  /// The entity that owns the attribute.
  public let entity: LogTenEntity

  public var description: String { rawValue }

  /// The attribute name without its entity prefix, such as `totalTime`.
  public var attributeName: Substring {
    rawValue[rawValue.index(after: separatorIndex)...]
  }

  /// The custom slot this key addresses, or `nil` for a built-in LogTen field.
  public var customSlot: CustomFieldSlot? { CustomFieldSlot(key: self) }

  private var separatorIndex: String.Index { rawValue.firstIndex(of: "_")! }

  /// Parses a LogTen attribute name, returning `nil` unless it is well-formed.
  public init?(rawValue: String) {
    guard let separator = rawValue.firstIndex(of: "_"),
      let entity = LogTenEntity(rawValue: String(rawValue[..<separator]))
    else { return nil }
    let name = rawValue[rawValue.index(after: separator)...]
    guard !name.isEmpty, name.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else {
      return nil
    }
    self.rawValue = rawValue
    self.entity = entity
  }

  /// Creates the key for an attribute of an entity.
  ///
  /// - Parameters:
  ///   - entity: The entity that owns the attribute.
  ///   - attribute: The attribute name without its prefix; it must be alphanumeric.
  public init(_ entity: LogTenEntity, _ attribute: String) {
    guard let key = Self(rawValue: "\(entity.rawValue)_\(attribute)") else {
      preconditionFailure("Invalid LogTen attribute name “\(attribute)”")
    }
    self = key
  }

  public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

// MARK: - Custom slots

extension LogTenFieldKey {
  /// Returns the key of a numbered custom slot.
  ///
  /// - Parameters:
  ///   - kind: The kind of custom field.
  ///   - number: The slot number, which must be within `kind.slots`.
  /// - Returns: The key, such as `flight_customTime7`.
  public static func custom(_ kind: CustomFieldKind, _ number: UInt) -> Self {
    CustomFieldSlot(kind: kind, number: number).key
  }
}

// MARK: - Built-in flight fields

extension LogTenFieldKey {
  /// LogTen's import key for a flight, used by `logten://` packages to address an entry.
  public static let flightKey = Self(.flight, "key")
  /// Whether the entry is locked against editing.
  public static let flightIsLocked = Self(.flight, "isLocked")
  /// The date of the flight.
  public static let flightDate = Self(.flight, "flightDate")
  /// The departure place identifier as text.
  public static let flightFrom = Self(.flight, "from")
  /// The destination place identifier as text.
  public static let flightTo = Self(.flight, "to")
  /// The route of flight.
  public static let flightRoute = Self(.flight, "route")
  /// The distance flown, in nautical miles.
  public static let flightDistance = Self(.flight, "distance")
  /// The flight number.
  public static let flightNumber = Self(.flight, "flightNumber")
  /// Remarks.
  public static let flightRemarks = Self(.flight, "remarks")

  /// Block-out time.
  public static let flightActualDepartureTime = Self(.flight, "actualDepartureTime")
  /// Wheels-up time.
  public static let flightTakeoffTime = Self(.flight, "takeoffTime")
  /// Wheels-down time.
  public static let flightLandingTime = Self(.flight, "landingTime")
  /// Block-in time.
  public static let flightActualArrivalTime = Self(.flight, "actualArrivalTime")
  /// Start of duty.
  public static let flightOnDutyTime = Self(.flight, "onDutyTime")
  /// End of duty.
  public static let flightOffDutyTime = Self(.flight, "offDutyTime")

  /// Hobbs meter at start.
  public static let flightHobbsStart = Self(.flight, "hobbsStart")
  /// Hobbs meter at stop.
  public static let flightHobbsStop = Self(.flight, "hobbsStop")
  /// Tachometer at start.
  public static let flightTachStart = Self(.flight, "tachStart")
  /// Tachometer at stop.
  public static let flightTachStop = Self(.flight, "tachStop")

  /// Total time, in minutes.
  public static let flightTotalTime = Self(.flight, "totalTime")
  /// Pilot-in-command time, in minutes.
  public static let flightPIC = Self(.flight, "pic")
  /// Second-in-command time, in minutes.
  public static let flightSIC = Self(.flight, "sic")
  /// Solo time, in minutes.
  public static let flightSolo = Self(.flight, "solo")
  /// Night time, in minutes.
  public static let flightNight = Self(.flight, "night")
  /// Cross-country time, in minutes.
  public static let flightCrossCountry = Self(.flight, "crossCountry")
  /// Dual instruction given, in minutes.
  public static let flightDualGiven = Self(.flight, "dualGiven")
  /// Dual instruction received, in minutes.
  public static let flightDualReceived = Self(.flight, "dualReceived")
  /// Actual instrument time, in minutes.
  public static let flightActualInstrument = Self(.flight, "actualInstrument")
  /// Simulated instrument time, in minutes.
  public static let flightSimulatedInstrument = Self(.flight, "simulatedInstrument")
  /// Simulator time, in minutes.
  public static let flightSimulator = Self(.flight, "simulator")
  /// Ground training time, in minutes.
  public static let flightGround = Self(.flight, "ground")
  /// Night-vision-goggle time, in minutes.
  public static let flightNightVisionGoggle = Self(.flight, "nightVisionGoggle")
  /// Pilot-in-command time at night, in minutes.
  public static let flightPICNight = Self(.flight, "picNight")
  /// Second-in-command time at night, in minutes.
  public static let flightSICNight = Self(.flight, "sicNight")
  /// Dual instruction received at night, in minutes.
  public static let flightDualReceivedNight = Self(.flight, "dualReceivedNight")
  /// Pilot-in-command-under-supervision (P1 u/s) time, in minutes.
  public static let flightP1US = Self(.flight, "p1us")
  /// P1 u/s time at night, in minutes.
  public static let flightP1USNight = Self(.flight, "p1usNight")
  /// Cross-country time at night, in minutes.
  public static let flightCrossCountryNight = Self(.flight, "crossCountryNight")

  /// Day takeoffs.
  public static let flightDayTakeoffs = Self(.flight, "dayTakeoffs")
  /// Night takeoffs.
  public static let flightNightTakeoffs = Self(.flight, "nightTakeoffs")
  /// Day landings.
  public static let flightDayLandings = Self(.flight, "dayLandings")
  /// Night landings.
  public static let flightNightLandings = Self(.flight, "nightLandings")
  /// Full-stop landings, day or night.
  public static let flightFullStops = Self(.flight, "fullStops")
  /// Night-vision-goggle takeoffs.
  public static let flightNightVisionGoggleTakeoffs = Self(.flight, "nightVisionGoggleTakeoffs")
  /// Night-vision-goggle landings.
  public static let flightNightVisionGoggleLandings = Self(.flight, "nightVisionGoggleLandings")
  /// Holding procedures.
  public static let flightHolds = Self(.flight, "holds")

  /// Whether the flight was a flight review (14 CFR 61.56).
  public static let flightReview = Self(.flight, "review")
  /// Whether the flight included an instrument proficiency check (14 CFR 61.57(d)).
  public static let flightInstrumentProficiencyCheck = Self(.flight, "instrumentProficiencyCheck")
}
