public import Foundation

/// Whether a moment at a position was night under the two definitions pilots use.
public struct NightClassification: Hashable, Sendable {
  /// Whether the Sun's geometric center was more than six degrees below the horizon, the end of
  /// evening civil twilight to the beginning of morning civil twilight (14 CFR 1.1).
  public var isCivilNight: Bool

  /// Whether the moment fell between one hour after sunset and one hour before sunrise, the
  /// window 14 CFR 61.57(b) uses for night landing currency. `nil` where the Sun doesn't set or
  /// rise within a day and a half of the moment.
  public var isCurrencyNight: Bool?
}

/// Night as 14 CFR defines it, computed from ``SolarPosition``.
public enum NightWindow {
  /// The Sun's elevation below which it is civil night, in degrees.
  public static let civilTwilightElevation = -6.0

  /// The Sun's elevation at sunrise and sunset: the upper limb on the horizon, with standard
  /// refraction, in degrees.
  public static let sunriseElevation = -0.833

  private static let currencyMargin: TimeInterval = 3_600
  private static let searchRadius: TimeInterval = 36 * 3_600
  private static let searchStep: TimeInterval = 600
  private static let bisectionTolerance: TimeInterval = 1

  /**
   Whether a moment at a position was night.

   - Parameters:
     - date: The moment.
     - latitudeDeg: The latitude, north positive.
     - longitudeDeg: The longitude, east positive.
   */
  public static func classify(at date: Date, latitudeDeg: Double, longitudeDeg: Double)
    -> NightClassification
  {
    let elevation = { (moment: Date) in
      SolarPosition.elevation(at: moment, latitudeDeg: latitudeDeg, longitudeDeg: longitudeDeg)
    }
    return NightClassification(
      isCivilNight: elevation(date) < civilTwilightElevation,
      isCurrencyNight: isCurrencyNight(at: date, elevation: elevation)
    )
  }

  private static func isCurrencyNight(at date: Date, elevation: (Date) -> Double) -> Bool? {
    guard elevation(date) < sunriseElevation else { return false }
    guard let sunset = lastCrossing(before: date, rising: false, elevation: elevation),
      let sunrise = nextCrossing(after: date, rising: true, elevation: elevation)
    else { return nil }
    return sunset.addingTimeInterval(currencyMargin) <= date
      && date <= sunrise.addingTimeInterval(-currencyMargin)
  }

  private static func lastCrossing(
    before date: Date,
    rising: Bool,
    elevation: (Date) -> Double
  ) -> Date? {
    var later = date
    var earlier = later.addingTimeInterval(-searchStep)
    while date.timeIntervalSince(earlier) <= searchRadius {
      if crosses(earlier, later, rising: rising, elevation: elevation) {
        return refine(earlier, later, rising: rising, elevation: elevation)
      }
      later = earlier
      earlier = later.addingTimeInterval(-searchStep)
    }
    return nil
  }

  private static func nextCrossing(after date: Date, rising: Bool, elevation: (Date) -> Double)
    -> Date?
  {
    var earlier = date
    var later = earlier.addingTimeInterval(searchStep)
    while later.timeIntervalSince(date) <= searchRadius {
      if crosses(earlier, later, rising: rising, elevation: elevation) {
        return refine(earlier, later, rising: rising, elevation: elevation)
      }
      earlier = later
      later = earlier.addingTimeInterval(searchStep)
    }
    return nil
  }

  private static func crosses(
    _ earlier: Date,
    _ later: Date,
    rising: Bool,
    elevation: (Date) -> Double
  ) -> Bool {
    let before = elevation(earlier) < sunriseElevation
    let after = elevation(later) < sunriseElevation
    return rising ? (before && !after) : (!before && after)
  }

  private static func refine(
    _ earlier: Date,
    _ later: Date,
    rising: Bool,
    elevation: (Date) -> Double
  ) -> Date {
    var low = earlier
    var high = later
    while high.timeIntervalSince(low) > bisectionTolerance {
      let middle = low.addingTimeInterval(high.timeIntervalSince(low) / 2)
      if crosses(low, middle, rising: rising, elevation: elevation) {
        high = middle
      } else {
        low = middle
      }
    }
    return high
  }
}
