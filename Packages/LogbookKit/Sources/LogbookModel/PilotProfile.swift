public import Foundation

/// The logbook owner's certificates and preferences, which decide which regulations apply.
public struct PilotProfile: Hashable, Codable, Sendable {
  /// The highest pilot certificate held.
  public var certificateLevel: CertificateLevel

  /// Category and class ratings.
  public var categoryClassRatings: Set<CategoryClassRating>

  /// Instrument ratings, by category.
  public var instrumentRatings: Set<InstrumentRating>

  /// Flight-instructor ratings; empty if the pilot isn't a flight instructor.
  public var instructorRatings: Set<InstructorRating>

  /// Type ratings, as ICAO type designators such as `SF50`.
  public var typeRatings: Set<String>

  /// The time zone the pilot's calendar days and months are reckoned in.
  public var homeTimeZone: TimeZone

  /// The logbook person who is the pilot, if known.
  public var ownerPersonID: RecordID?

  /// Whether audits should ignore instruction-related activity, for pilots who aren't
  /// instructing.
  public var ignoresInstructionActivity: Bool

  /// Whether the pilot holds a flight-instructor certificate.
  public var isFlightInstructor: Bool { !instructorRatings.isEmpty }

  /// Creates a pilot profile.
  public init(
    certificateLevel: CertificateLevel = .private,
    categoryClassRatings: Set<CategoryClassRating> = [],
    instrumentRatings: Set<InstrumentRating> = [],
    instructorRatings: Set<InstructorRating> = [],
    typeRatings: Set<String> = [],
    homeTimeZone: TimeZone = .current,
    ownerPersonID: RecordID? = nil,
    ignoresInstructionActivity: Bool = false
  ) {
    self.certificateLevel = certificateLevel
    self.categoryClassRatings = categoryClassRatings
    self.instrumentRatings = instrumentRatings
    self.instructorRatings = instructorRatings
    self.typeRatings = typeRatings
    self.homeTimeZone = homeTimeZone
    self.ownerPersonID = ownerPersonID
    self.ignoresInstructionActivity = ignoresInstructionActivity
  }
}

/// Pilot certificate levels, lowest to highest.
public enum CertificateLevel: String, CaseIterable, Comparable, Codable, Sendable {
  /// Student pilot.
  case student
  /// Sport pilot.
  case sport
  /// Recreational pilot.
  case recreational
  /// Private pilot.
  case `private`
  /// Commercial pilot.
  case commercial
  /// Airline transport pilot.
  case airlineTransport = "airline_transport"

  public static func < (lhs: Self, rhs: Self) -> Bool {
    allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
  }
}

/// Category and class ratings on a pilot certificate.
public enum CategoryClassRating: String, CaseIterable, Codable, Sendable {
  /// Airplane single-engine land.
  case airplaneSingleEngineLand = "airplane_single_engine_land"
  /// Airplane single-engine sea.
  case airplaneSingleEngineSea = "airplane_single_engine_sea"
  /// Airplane multi-engine land.
  case airplaneMultiEngineLand = "airplane_multi_engine_land"
  /// Airplane multi-engine sea.
  case airplaneMultiEngineSea = "airplane_multi_engine_sea"
  /// Glider.
  case glider
  /// Rotorcraft helicopter.
  case rotorcraftHelicopter = "rotorcraft_helicopter"
  /// Rotorcraft gyroplane.
  case rotorcraftGyroplane = "rotorcraft_gyroplane"
  /// Lighter-than-air balloon.
  case lighterThanAirBalloon = "lighter_than_air_balloon"
  /// Lighter-than-air airship.
  case lighterThanAirAirship = "lighter_than_air_airship"
  /// Powered lift.
  case poweredLift = "powered_lift"
}

/// Instrument ratings, by aircraft category.
public enum InstrumentRating: String, CaseIterable, Codable, Sendable {
  /// Instrument airplane.
  case airplane
  /// Instrument helicopter.
  case helicopter
  /// Instrument powered lift.
  case poweredLift = "powered_lift"
}

/// Ratings on a flight-instructor certificate.
public enum InstructorRating: String, CaseIterable, Codable, Sendable {
  /// Airplane single-engine.
  case airplaneSingleEngine = "airplane_single_engine"
  /// Airplane multi-engine.
  case airplaneMultiEngine = "airplane_multi_engine"
  /// Glider.
  case glider
  /// Rotorcraft helicopter.
  case rotorcraftHelicopter = "rotorcraft_helicopter"
  /// Rotorcraft gyroplane.
  case rotorcraftGyroplane = "rotorcraft_gyroplane"
  /// Powered lift.
  case poweredLift = "powered_lift"
  /// Instrument airplane.
  case instrumentAirplane = "instrument_airplane"
  /// Instrument helicopter.
  case instrumentHelicopter = "instrument_helicopter"
  /// Instrument powered lift.
  case instrumentPoweredLift = "instrument_powered_lift"
  /// Sport pilot instructor.
  case sport
}
