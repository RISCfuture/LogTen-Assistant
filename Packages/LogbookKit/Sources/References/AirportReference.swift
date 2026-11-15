public import Foundation

/// Reference data for one airport, independent of the dataset it came from.
public struct AirportReference: Hashable, Codable, Sendable {
  /// The FAA location identifier, such as `SQL`.
  public var locationID: String

  /// The ICAO identifier, such as `KSQL`.
  public var ICAOID: String?

  /// The airport's name.
  public var name: String

  /// Latitude of the airport reference point, in degrees.
  public var latitudeDeg: Double

  /// Longitude of the airport reference point, in degrees.
  public var longitudeDeg: Double

  /// Field elevation in feet.
  public var elevationFt: Double?

  /// The IANA time-zone identifier for the airport.
  public var timeZoneIdentifier: String?

  /// The first day of the data cycle the record comes from.
  public var cycleEffectiveDate: Date?

  /// The identifier audits report the airport under: the ICAO identifier if it has one.
  public var identifier: String { ICAOID ?? locationID }

  /// The identifiers the airport answers to.
  public var aliases: [String] { [locationID, ICAOID].compactMap(\.self) }

  /// Creates an airport reference.
  public init(
    locationID: String,
    ICAOID: String? = nil,
    name: String,
    latitudeDeg: Double,
    longitudeDeg: Double,
    elevationFt: Double? = nil,
    timeZoneIdentifier: String? = nil,
    cycleEffectiveDate: Date? = nil
  ) {
    self.locationID = locationID
    self.ICAOID = ICAOID
    self.name = name
    self.latitudeDeg = latitudeDeg
    self.longitudeDeg = longitudeDeg
    self.elevationFt = elevationFt
    self.timeZoneIdentifier = timeZoneIdentifier
    self.cycleEffectiveDate = cycleEffectiveDate
  }
}

/// The threshold of one runway end.
public struct RunwayEndReference: Hashable, Codable, Sendable {
  /// The location identifier of the airport the runway belongs to.
  public var airportLocationID: String

  /// The runway's name, such as `11/29`.
  public var runwayID: String

  /// The runway end's name, such as `29`.
  public var identifier: String

  /// Latitude of the threshold, in degrees.
  public var latitudeDeg: Double

  /// Longitude of the threshold, in degrees.
  public var longitudeDeg: Double

  /// Creates a runway end.
  public init(
    airportLocationID: String,
    runwayID: String,
    identifier: String,
    latitudeDeg: Double,
    longitudeDeg: Double
  ) {
    self.airportLocationID = airportLocationID
    self.runwayID = runwayID
    self.identifier = identifier
    self.latitudeDeg = latitudeDeg
    self.longitudeDeg = longitudeDeg
  }
}
