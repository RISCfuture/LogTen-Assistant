public import Foundation

/// A crew member or passenger.
public struct Person: Identifiable, Hashable, Codable, Sendable {
  /// The record identifier.
  public var id: RecordID

  /// The name as LogTen displays it.
  public var name: String

  /// The email address, if recorded.
  public var email: String?

  /// The first name, if recorded separately from ``name``.
  public var firstName: String?

  /// The last name, if recorded separately from ``name``.
  public var lastName: String?

  /// The person's own identifier, such as a certificate or employee number, if recorded.
  public var personID: String?

  /// Whether LogTen marks this person as the logbook owner.
  public var isMe: Bool

  /// Values of the person's custom attributes, keyed by field key; unset fields are absent.
  public var customValues: [LogTenFieldKey: FieldValue]

  /// Creates a person.
  public init(
    id: RecordID,
    name: String,
    email: String? = nil,
    firstName: String? = nil,
    lastName: String? = nil,
    personID: String? = nil,
    isMe: Bool = false,
    customValues: [LogTenFieldKey: FieldValue] = [:]
  ) {
    self.id = id
    self.name = name
    self.email = email
    self.firstName = firstName
    self.lastName = lastName
    self.personID = personID
    self.isMe = isMe
    self.customValues = customValues
  }
}

/// An airport or other location.
public struct Place: Identifiable, Hashable, Codable, Sendable {
  /// The record identifier.
  public var id: RecordID

  /// LogTen's identifier for the place, usually the FAA location identifier.
  public var identifier: String

  /// The ICAO identifier, such as `KSQL`.
  public var ICAO: String?

  /// The FAA location identifier, such as `SQL`.
  public var FAAID: String?

  /// The IATA identifier.
  public var IATA: String?

  /// The place's name.
  public var name: String?

  /// Latitude in degrees, north positive.
  public var latitudeDeg: Double?

  /// Longitude in degrees, east positive.
  public var longitudeDeg: Double?

  /// Field elevation in feet.
  public var elevationFt: Int?

  /// The IANA time-zone identifier LogTen recorded for the place.
  public var timeZoneIdentifier: String?

  /// Values of the place's custom attributes, keyed by field key; unset fields are absent.
  public var customValues: [LogTenFieldKey: FieldValue]

  /// The identifier to show and match against references: ICAO, then FAA, then LogTen's own.
  public var preferredIdentifier: String { ICAO ?? FAAID ?? identifier }

  /// Field elevation, if recorded.
  public var elevation: Measurement<UnitLength>? {
    elevationFt.map { Measurement(value: Double($0), unit: .feet) }
  }

  /// Creates a place.
  public init(
    id: RecordID,
    identifier: String,
    ICAO: String? = nil,
    FAAID: String? = nil,
    IATA: String? = nil,
    name: String? = nil,
    latitudeDeg: Double? = nil,
    longitudeDeg: Double? = nil,
    elevationFt: Int? = nil,
    timeZoneIdentifier: String? = nil,
    customValues: [LogTenFieldKey: FieldValue] = [:]
  ) {
    self.id = id
    self.identifier = identifier
    self.ICAO = ICAO
    self.FAAID = FAAID
    self.IATA = IATA
    self.name = name
    self.latitudeDeg = latitudeDeg
    self.longitudeDeg = longitudeDeg
    self.elevationFt = elevationFt
    self.timeZoneIdentifier = timeZoneIdentifier
    self.customValues = customValues
  }
}

/// An instrument approach logged on a flight.
public struct Approach: Identifiable, Hashable, Codable, Sendable {
  /// The record identifier.
  public var id: RecordID

  /// The airport where the approach was flown.
  public var place: Place?

  /// The approach type; `nil` if unrecorded or not one LogTen defines.
  public var type: ApproachType?

  /// The runway, which LogTen keeps in the approach's comment.
  public var runway: String?

  /// How many times the approach was flown.
  public var count: UInt

  /// Whether the approach was flown at night.
  public var isNight: Bool

  /// Whether the approach was flown in a simulator or training device.
  public var isSimulated: Bool

  /// Creates an approach.
  public init(
    id: RecordID,
    place: Place? = nil,
    type: ApproachType? = nil,
    runway: String? = nil,
    count: UInt = 1,
    isNight: Bool = false,
    isSimulated: Bool = false
  ) {
    self.id = id
    self.place = place
    self.type = type
    self.runway = runway
    self.count = count
    self.isNight = isNight
    self.isSimulated = isSimulated
  }
}

/// An aircraft make and model shared by several aircraft.
public struct AircraftType: Identifiable, Hashable, Codable, Sendable {
  /// The record identifier.
  public var id: RecordID

  /// LogTen's type identifier, such as `C172` or `SR22T`.
  public var type: String

  /// The manufacturer.
  public var make: String?

  /// The model name.
  public var model: String?

  /// The FAA category; `nil` when the logbook's category slot isn't recognized.
  public var category: AircraftCategory?

  /// The FAA class, if the category has classes.
  public var aircraftClass: AircraftClass?

  /// The engine type.
  public var engineType: EngineType?

  /// Whether the type requires a multi-pilot crew.
  public var isMultiPilot: Bool

  /// Values of the type's custom attributes (`aircraftType_customAttribute1`–`5`), keyed by
  /// field key; unset fields are absent.
  public var customValues: [LogTenFieldKey: FieldValue]

  /// Creates an aircraft type.
  public init(
    id: RecordID,
    type: String,
    make: String? = nil,
    model: String? = nil,
    category: AircraftCategory? = nil,
    aircraftClass: AircraftClass? = nil,
    engineType: EngineType? = nil,
    isMultiPilot: Bool = false,
    customValues: [LogTenFieldKey: FieldValue] = [:]
  ) {
    self.id = id
    self.type = type
    self.make = make
    self.model = model
    self.category = category
    self.aircraftClass = aircraftClass
    self.engineType = engineType
    self.isMultiPilot = isMultiPilot
    self.customValues = customValues
  }
}

/// A specific aircraft or simulator, identified by registration.
public struct Aircraft: Identifiable, Hashable, Codable, Sendable {
  private static let typeRatingWeightLbs = 12_500.0

  /// The record identifier.
  public var id: RecordID

  /// The registration (tail number) or simulator identifier.
  public var registration: String

  /// The secondary identifier, such as a fleet number, if recorded.
  public var secondaryID: String?

  /// The aircraft's make and model.
  public var type: AircraftType?

  /// Maximum gross weight in pounds.
  public var weightLbs: Double?

  /// Year of manufacture.
  public var year: Int?

  /// Whether the aircraft is complex.
  public var isComplex: Bool
  /// Whether the aircraft is high-performance.
  public var isHighPerformance: Bool
  /// Whether the aircraft is pressurized.
  public var isPressurized: Bool
  /// Whether the aircraft is technically advanced.
  public var isTechnicallyAdvanced: Bool
  /// Whether the landing gear retracts.
  public var hasRetractableGear: Bool
  /// Whether the aircraft is amphibious.
  public var isAmphibious: Bool
  /// Whether the aircraft is on floats.
  public var hasFloats: Bool
  /// Whether the aircraft is on skis.
  public var hasSkis: Bool
  /// Whether the aircraft has skids.
  public var hasSkids: Bool
  /// Whether the aircraft has conventional (tailwheel) gear.
  public var isTailwheel: Bool
  /// Whether the aircraft has a radial engine.
  public var hasRadialEngine: Bool

  /// Values of the aircraft's custom attributes and texts, keyed by field key; unset fields are
  /// absent.
  public var customValues: [LogTenFieldKey: FieldValue]

  /// Maximum gross weight, if recorded.
  public var weight: Measurement<UnitMass>? {
    weightLbs.map { Measurement(value: $0, unit: .pounds) }
  }

  /// Whether a type rating is needed to act as pilot in command: powered-lift, turbine-powered,
  /// or over 12,500 pounds (14 CFR 61.31(a)).
  public var requiresTypeRating: Bool {
    if type?.category == .poweredLift { return true }
    if type?.engineType?.isTurbine == true { return true }
    return (weightLbs ?? 0) > Self.typeRatingWeightLbs
  }

  /// Creates an aircraft.
  public init(
    id: RecordID,
    registration: String,
    secondaryID: String? = nil,
    type: AircraftType? = nil,
    weightLbs: Double? = nil,
    year: Int? = nil,
    isComplex: Bool = false,
    isHighPerformance: Bool = false,
    isPressurized: Bool = false,
    isTechnicallyAdvanced: Bool = false,
    hasRetractableGear: Bool = false,
    isAmphibious: Bool = false,
    hasFloats: Bool = false,
    hasSkis: Bool = false,
    hasSkids: Bool = false,
    isTailwheel: Bool = false,
    hasRadialEngine: Bool = false,
    customValues: [LogTenFieldKey: FieldValue] = [:]
  ) {
    self.id = id
    self.registration = registration
    self.secondaryID = secondaryID
    self.type = type
    self.weightLbs = weightLbs
    self.year = year
    self.isComplex = isComplex
    self.isHighPerformance = isHighPerformance
    self.isPressurized = isPressurized
    self.isTechnicallyAdvanced = isTechnicallyAdvanced
    self.hasRetractableGear = hasRetractableGear
    self.isAmphibious = isAmphibious
    self.hasFloats = hasFloats
    self.hasSkis = hasSkis
    self.hasSkids = hasSkids
    self.isTailwheel = isTailwheel
    self.hasRadialEngine = hasRadialEngine
    self.customValues = customValues
  }
}
