public import Foundation

/// The airports and runway ends of one 28-day NASR cycle, searchable by identifier and
/// position.
public struct AirportIndex: Codable, Sendable {
  /// How long a NASR cycle is in effect.
  public static let cycleLength: TimeInterval = 28 * 86_400

  /// The default radius for matching a position to an airport, in nautical miles.
  public static let defaultMatchRadiusNM = 3.0

  private static let runwayCorridorHalfWidthNM = 0.3
  private static let runwayCorridorOvershootNM = 0.5
  private static let runwayLengthRangeNM = 0.1...4.0
  private static let nauticalMilesPerDegree = 60.0

  /// The first day of the cycle.
  public let effectiveDate: Date

  /// Every airport in the cycle.
  public let airports: [AirportReference]

  /// Every runway end whose position is known.
  public let runwayEnds: [RunwayEndReference]

  private let airportsByIdentifier: [String: [AirportReference]]
  private let airportsByCell: [Cell: [AirportReference]]
  private let runwaysByCell: [Cell: [Runway]]

  /// The first day after the cycle.
  public var expirationDate: Date { effectiveDate.addingTimeInterval(Self.cycleLength) }

  /// Creates an index.
  public init(
    effectiveDate: Date,
    airports: [AirportReference],
    runwayEnds: [RunwayEndReference] = []
  ) {
    self.effectiveDate = effectiveDate
    self.airports = airports
    self.runwayEnds = runwayEnds
    var byIdentifier = [String: [AirportReference]]()
    var byCell = [Cell: [AirportReference]]()
    for airport in airports {
      for key in Set(airport.aliases.map { $0.uppercased() }) {
        byIdentifier[key, default: []].append(airport)
      }
      byCell[
        Cell(latitudeDeg: airport.latitudeDeg, longitudeDeg: airport.longitudeDeg),
        default: []
      ]
      .append(airport)
    }
    airportsByIdentifier = byIdentifier
    airportsByCell = byCell
    runwaysByCell = Self.runways(of: airports, ends: runwayEnds)
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      effectiveDate: try container.decode(Date.self, forKey: .effectiveDate),
      airports: try container.decode([AirportReference].self, forKey: .airports),
      runwayEnds: try container.decode([RunwayEndReference].self, forKey: .runwayEnds)
    )
  }

  private static func runways(of airports: [AirportReference], ends: [RunwayEndReference])
    -> [Cell: [Runway]]
  {
    let airportsByLocationID = Dictionary(airports.map { ($0.locationID, $0) }) { first, _ in first
    }
    let grouped = Dictionary(grouping: ends.filter(\.hasNumberedName)) {
      "\($0.airportLocationID)\u{0}\($0.runwayID)"
    }
    var result = [Cell: [Runway]]()
    for group in grouped.values where group.count == 2 {
      guard let airport = airportsByLocationID[group[0].airportLocationID] else { continue }
      let runway = Runway(airport: airport, first: group[0], second: group[1])
      guard runwayLengthRangeNM.contains(runway.lengthNM) else { continue }
      result[runway.midpointCell, default: []].append(runway)
    }
    return result
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(effectiveDate, forKey: .effectiveDate)
    try container.encode(airports, forKey: .airports)
    try container.encode(runwayEnds, forKey: .runwayEnds)
  }

  /// Whether the cycle was in effect on a date.
  public func covers(_ date: Date) -> Bool {
    effectiveDate <= date && date < expirationDate
  }

  /**
   The airport an identifier names.

   - Parameter identifier: An FAA location identifier or ICAO identifier, in any case.
   - Returns: The airport, or `nil` if no airport or several different airports answer to it.
   */
  public func airport(matching identifier: String) -> AirportReference? {
    let matches = airportsByIdentifier[identifier.trimmingCharacters(in: .whitespaces).uppercased()]
    guard let matches, Set(matches.map(\.identifier)).count == 1 else { return nil }
    return matches[0]
  }

  /**
   The airport nearest a position.

   - Parameters:
     - latitudeDeg: The position's latitude.
     - longitudeDeg: The position's longitude.
     - limitNM: The farthest an airport may be to count, in nautical miles.
   - Returns: The airport, or `nil` if none is within the limit.
   */
  public func nearestAirport(
    latitudeDeg: Double,
    longitudeDeg: Double,
    limitNM: Double = defaultMatchRadiusNM
  ) -> AirportReference? {
    let candidates = Cell.neighbors(latitudeDeg: latitudeDeg, longitudeDeg: longitudeDeg)
      .flatMap { airportsByCell[$0] ?? [] }
    let nearest = candidates.min {
      distance(of: $0, latitudeDeg, longitudeDeg) < distance(of: $1, latitudeDeg, longitudeDeg)
    }
    return nearest.flatMap { distance(of: $0, latitudeDeg, longitudeDeg) <= limitNM ? $0 : nil }
  }

  /// The runway end of an airport nearest a position.
  public func nearestRunwayEnd(
    of airport: AirportReference,
    latitudeDeg: Double,
    longitudeDeg: Double
  ) -> RunwayEndReference? {
    runwayEnds.filter { $0.airportLocationID == airport.locationID }.min {
      GreatCircle.distanceNM($0.latitudeDeg, $0.longitudeDeg, latitudeDeg, longitudeDeg)
        < GreatCircle.distanceNM($1.latitudeDeg, $1.longitudeDeg, latitudeDeg, longitudeDeg)
    }
  }

  /**
   The one airport whose runway a position lies on.

   A position is on a runway when it lies within a narrow corridor along the runway's centerline,
   extended slightly past each end. Only numbered runways between 0.1 and 4 nautical miles long
   count.

   - Returns: The airport, or `nil` if the position is on no runway or on runways of several
     airports.
   */
  public func airport(onRunwayAtLatitudeDeg latitude: Double, longitudeDeg longitude: Double)
    -> AirportReference?
  {
    guard (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
    let hits = Cell.neighbors(latitudeDeg: latitude, longitudeDeg: longitude)
      .flatMap { runwaysByCell[$0] ?? [] }
      .filter { $0.contains(latitude: latitude, longitude: longitude) }
      .map(\.airport)
    return Set(hits.map(\.identifier)).count == 1 ? hits[0] : nil
  }

  private func distance(of airport: AirportReference, _ latitude: Double, _ longitude: Double)
    -> Double
  {
    GreatCircle.distanceNM(latitude, longitude, airport.latitudeDeg, airport.longitudeDeg)
  }

  private enum CodingKeys: String, CodingKey {
    case effectiveDate, airports, runwayEnds
  }

  private struct Cell: Hashable, Sendable {
    let latitude: Int
    let longitude: Int

    init(latitudeDeg: Double, longitudeDeg: Double) {
      latitude = Int(latitudeDeg.rounded(.down))
      longitude = Int(longitudeDeg.rounded(.down))
    }

    private init(latitude: Int, longitude: Int) {
      self.latitude = latitude
      self.longitude = longitude
    }

    /// The cells around a position, wider in longitude near the poles.
    static func neighbors(latitudeDeg: Double, longitudeDeg: Double) -> [Self] {
      let center = Self(latitudeDeg: latitudeDeg, longitudeDeg: longitudeDeg)
      let cosine = max(0.01, cos(latitudeDeg * .pi / 180))
      let width = min(180, Int((1 / cosine).rounded(.up)))
      return (-1...1).flatMap { row in
        (-width...width).map { column in
          Self(
            latitude: center.latitude + row,
            longitude: (center.longitude + column + 180 + 360) % 360 - 180
          )
        }
      }
    }
  }

  private struct Runway: Sendable {
    let airport: AirportReference
    let first: RunwayEndReference
    let second: RunwayEndReference

    var lengthNM: Double {
      GreatCircle.distanceNM(
        first.latitudeDeg,
        first.longitudeDeg,
        second.latitudeDeg,
        second.longitudeDeg
      )
    }

    var midpointCell: Cell {
      Cell(
        latitudeDeg: (first.latitudeDeg + second.latitudeDeg) / 2,
        longitudeDeg: (first.longitudeDeg + second.longitudeDeg) / 2
      )
    }

    /// Whether a position lies in the corridor along the centerline, in a flat-earth frame.
    func contains(latitude: Double, longitude: Double) -> Bool {
      let meanLatitude = (first.latitudeDeg + second.latitudeDeg) / 2
      let scale = AirportIndex.nauticalMilesPerDegree * cos(meanLatitude * .pi / 180)
      let dx = (second.longitudeDeg - first.longitudeDeg) * scale
      let dy = (second.latitudeDeg - first.latitudeDeg) * AirportIndex.nauticalMilesPerDegree
      let x = (longitude - first.longitudeDeg) * scale
      let y = (latitude - first.latitudeDeg) * AirportIndex.nauticalMilesPerDegree
      let length = (dx * dx + dy * dy).squareRoot()
      let along = (x * dx + y * dy) / length
      let lateral = abs(x * dy - y * dx) / length
      return lateral <= AirportIndex.runwayCorridorHalfWidthNM
        && along >= -AirportIndex.runwayCorridorOvershootNM
        && along <= length + AirportIndex.runwayCorridorOvershootNM
    }
  }
}

extension RunwayEndReference {
  /// Whether the end's name is a runway number from 01 to 36 with an optional L, R or C, at a
  /// valid position.
  fileprivate var hasNumberedName: Bool {
    identifier.wholeMatch(of: /(0[1-9]|[12][0-9]|3[0-6])[LRC]?/) != nil
      && (-90...90).contains(latitudeDeg) && (-180...180).contains(longitudeDeg)
  }
}
