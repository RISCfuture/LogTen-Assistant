import Foundation
import MeasurementKit
import MeasurementKitLocation

/// Distances and bearings between latitude/longitude pairs, in the units the audits use.
package enum GreatCircle {
  /// The great-circle distance between two positions, in nautical miles.
  package static func distanceNM(
    _ latitude1: Double,
    _ longitude1: Double,
    _ latitude2: Double,
    _ longitude2: Double
  ) -> Double {
    coordinate(latitude1, longitude1).distance(to: coordinate(latitude2, longitude2))
      .converted(to: .nauticalMiles).value
  }

  /// The true bearing from one position to another, in degrees from 0 up to 360.
  package static func bearingDeg(
    _ latitude1: Double,
    _ longitude1: Double,
    _ latitude2: Double,
    _ longitude2: Double
  ) -> Double {
    let degrees = coordinate(latitude1, longitude1)
      .initialBearing(to: coordinate(latitude2, longitude2)).degrees
    return (degrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
  }

  /// The position `fraction` of the way along the great circle between two positions.
  package static func interpolate(
    _ latitude1: Double,
    _ longitude1: Double,
    _ latitude2: Double,
    _ longitude2: Double,
    fraction: Double
  ) -> (latitudeDeg: Double, longitudeDeg: Double) {
    let point = coordinate(latitude1, longitude1)
      .interpolated(to: coordinate(latitude2, longitude2), fraction: fraction)
    return (point.latitude.degrees, point.longitude.degrees)
  }

  /// The smallest angle between two bearings, in degrees from 0 through 180.
  package static func angleBetween(_ first: Double, _ second: Double) -> Double {
    abs((first - second + 540).truncatingRemainder(dividingBy: 360) - 180)
  }

  private static func coordinate(_ latitude: Double, _ longitude: Double) -> Coordinate {
    Coordinate(latitude: latitude, longitude: longitude)
  }
}
