import CoreLocation
import Foundation
import MapKit

/// Finds the time zone at a position.
public protocol TimeZoneResolving: Sendable {
  /**
   The time zone at a position.

   - Returns: An IANA time-zone identifier, or `nil` if the position has none.
   - Throws: If the lookup couldn't be completed, such as when the network is unavailable.
   */
  func timeZoneIdentifier(latitudeDeg: Double, longitudeDeg: Double) async throws -> String?
}

/// Finds time zones by reverse geocoding the position with MapKit.
public struct MapKitTimeZoneResolver: TimeZoneResolving {
  /// Creates a resolver.
  public init() {}

  public func timeZoneIdentifier(latitudeDeg: Double, longitudeDeg: Double) async throws
    -> String?
  {
    let location = CLLocation(latitude: latitudeDeg, longitude: longitudeDeg)
    guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
    return try await request.mapItems.lazy.compactMap(\.timeZone).first?.identifier
  }
}

/// Where an airport's time zone came from.
public enum TimeZoneSource: String, Codable, Sendable {
  /// The user set it.
  case override
  /// The airport reference data states it.
  case reference
  /// A geographic lookup found it.
  case lookup
}

/// An airport's time zone and how it was found.
public struct AirportTimeZone: Hashable, Codable, Sendable {
  /// The IANA time-zone identifier.
  public var identifier: String
  /// How the identifier was found.
  public var source: TimeZoneSource

  /// Creates a time zone.
  public init(identifier: String, source: TimeZoneSource) {
    self.identifier = identifier
    self.source = source
  }
}

/**
 Finds the time zone of an airport, preferring a manual override, then the reference data,
 then a geographic lookup whose answers are remembered.

 A lookup that fails isn't remembered, so it's tried again later.
 */
public actor AirportTimeZones {
  private let resolver: any TimeZoneResolving
  private var overrides: [String: String]
  private var lookedUp: [String: String]

  /// The identifiers found by geographic lookup, by airport identifier, for saving.
  public var lookups: [String: String] { lookedUp }

  /// The number of lookups that failed since creation.
  public private(set) var failedLookups = 0

  /**
   Creates a provider.

   - Parameters:
     - resolver: The geographic lookup.
     - overrides: Time zones the user set, by airport identifier.
     - lookups: Earlier lookup results, by airport identifier.
   */
  public init(
    resolver: any TimeZoneResolving,
    overrides: [String: String] = [:],
    lookups: [String: String] = [:]
  ) {
    self.resolver = resolver
    self.overrides = overrides.reduce(into: [:]) { $0[$1.key.uppercased()] = $1.value }
    lookedUp = lookups.reduce(into: [:]) { $0[$1.key.uppercased()] = $1.value }
  }

  /// Sets or, with `nil`, clears the override for an airport.
  public func setOverride(_ identifier: String?, forAirport airport: String) {
    overrides[airport.uppercased()] = identifier
  }

  /**
   The time zone of an airport.

   - Parameter airport: The airport.
   - Returns: The time zone, or `nil` if no source knows it.
   */
  public func timeZone(of airport: AirportReference) async -> AirportTimeZone? {
    let key = airport.identifier.uppercased()
    if let identifier = overrides[key] { return .init(identifier: identifier, source: .override) }
    if let identifier = airport.timeZoneIdentifier {
      return .init(identifier: identifier, source: .reference)
    }
    if let identifier = lookedUp[key] { return .init(identifier: identifier, source: .lookup) }
    do {
      guard
        let identifier = try await resolver.timeZoneIdentifier(
          latitudeDeg: airport.latitudeDeg,
          longitudeDeg: airport.longitudeDeg
        )
      else { return nil }
      lookedUp[key] = identifier
      return .init(identifier: identifier, source: .lookup)
    } catch {
      failedLookups += 1
      return nil
    }
  }
}
