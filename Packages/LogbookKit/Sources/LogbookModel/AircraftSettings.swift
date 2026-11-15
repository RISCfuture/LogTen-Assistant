/// Per-aircraft settings the logbook doesn't record, keyed by registration in
/// ``LogbookSettings``.
public struct AircraftSettings: Hashable, Codable, Sendable {
  /// Other registrations or identifiers the same aircraft appears under in other sources.
  public var aliases: [String]

  /// The ICAO 24-bit address, overriding the one derived from a US registration.
  public var icaoAddress: ICAOAddress?

  /// The aircraft's identifier in FlySto.
  public var flyStoAircraftID: String?

  /// Whether the aircraft is equipped and certified for IFR, if known.
  public var isIFRCapable: Bool?

  /// The type rating the aircraft requires, as an ICAO type designator.
  public var typeRating: String?

  /// Whether flights in the aircraft need a current 14 CFR 61.58 proficiency check.
  public var requiresProficiencyCheck: Bool

  /// The longest plausible flight, in minutes; longer entries are flagged.
  public var maximumFlightTime: UInt?

  /// Track-detection thresholds that differ from the global defaults for this aircraft.
  public var trackDetection: TrackDetectionOverrides

  /// The currency requirements a simulator or training device may be credited toward.
  public var simulatorCredit: Set<SimulatorCredit>

  /// Whether ADS-B activity that matches no logbook entry is ignored, for shared aircraft.
  public var ignoresUnmatchedActivity: Bool

  /// Creates aircraft settings.
  public init(
    aliases: [String] = [],
    icaoAddress: ICAOAddress? = nil,
    flyStoAircraftID: String? = nil,
    isIFRCapable: Bool? = nil,
    typeRating: String? = nil,
    requiresProficiencyCheck: Bool = false,
    maximumFlightTime: UInt? = nil,
    trackDetection: TrackDetectionOverrides = .init(),
    simulatorCredit: Set<SimulatorCredit> = [],
    ignoresUnmatchedActivity: Bool = false
  ) {
    self.aliases = aliases
    self.icaoAddress = icaoAddress
    self.flyStoAircraftID = flyStoAircraftID
    self.isIFRCapable = isIFRCapable
    self.typeRating = typeRating
    self.requiresProficiencyCheck = requiresProficiencyCheck
    self.maximumFlightTime = maximumFlightTime
    self.trackDetection = trackDetection
    self.simulatorCredit = simulatorCredit
    self.ignoresUnmatchedActivity = ignoresUnmatchedActivity
  }
}

/// Track-detection thresholds for one aircraft; `nil` uses the global default.
public struct TrackDetectionOverrides: Hashable, Codable, Sendable {
  /// Ground speed above which the aircraft is considered airborne, in knots.
  public var airborneSpeedKts: Double?

  /// Ground speed below which the aircraft is considered on the ground, in knots.
  public var groundSpeedKts: Double?

  /// How long a state must hold before it is confirmed, in seconds.
  public var confirmSeconds: Double?

  /// How long the aircraft must be stopped to end a segment, in seconds.
  public var stopSeconds: Double?

  /// The longest gap between samples that doesn't split a track, in seconds.
  public var gapSeconds: Double?

  /// Creates a set of overrides.
  public init(
    airborneSpeedKts: Double? = nil,
    groundSpeedKts: Double? = nil,
    confirmSeconds: Double? = nil,
    stopSeconds: Double? = nil,
    gapSeconds: Double? = nil
  ) {
    self.airborneSpeedKts = airborneSpeedKts
    self.groundSpeedKts = groundSpeedKts
    self.confirmSeconds = confirmSeconds
    self.stopSeconds = stopSeconds
    self.gapSeconds = gapSeconds
  }
}

/// A currency requirement a simulator or training device can be credited toward.
public enum SimulatorCredit: String, CaseIterable, Codable, Sendable {
  /// Instrument experience (14 CFR 61.57(c)).
  case instrumentExperience = "instrument_experience"
  /// Instrument proficiency check (14 CFR 61.57(d)).
  case instrumentProficiencyCheck = "instrument_proficiency_check"
  /// Passenger-carrying takeoffs and landings (14 CFR 61.57(a) and (b)).
  case takeoffsAndLandings = "takeoffs_and_landings"
  /// Flight review (14 CFR 61.56).
  case flightReview = "flight_review"
  /// Pilot-in-command proficiency check (14 CFR 61.58).
  case proficiencyCheck = "proficiency_check"
}

/// A 24-bit ICAO aircraft address, the identifier ADS-B transponders broadcast.
public struct ICAOAddress: RawRepresentable, Hashable, Codable, Sendable, CustomStringConvertible {
  private static let maximum: UInt32 = 0xFF_FFFF
  private static let hexDigits = 6

  public let rawValue: UInt32

  /// The address as six lowercase hexadecimal digits, as ADS-B archives name it.
  public var hex: String {
    let digits = String(rawValue, radix: 16)
    return String(repeating: "0", count: Self.hexDigits - digits.count) + digits
  }

  public var description: String { hex }

  /// Creates an address, or `nil` if the value exceeds 24 bits.
  public init?(rawValue: UInt32) {
    guard rawValue <= Self.maximum else { return nil }
    self.rawValue = rawValue
  }

  /// Parses an address from up to six hexadecimal digits, ignoring case.
  public init?(hex: String) {
    guard (1...Self.hexDigits).contains(hex.count), hex.allSatisfy(\.isHexDigit),
      let value = UInt32(hex, radix: 16)
    else { return nil }
    self.init(rawValue: value)
  }

  public init(from decoder: any Decoder) throws {
    let hex = try decoder.singleValueContainer().decode(String.self)
    guard let address = Self(hex: hex) else {
      throw DecodingError.dataCorrupted(
        .init(codingPath: decoder.codingPath, debugDescription: "Invalid ICAO address “\(hex)”")
      )
    }
    self = address
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(hex)
  }
}
