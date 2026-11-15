public import Foundation

/// The Sun's position as seen from a point on the Earth, from NOAA's solar calculator
/// equations.
///
/// The equations are accurate to about a hundredth of a degree for dates between 1800 and
/// 2100, far finer than the six-degree threshold of civil twilight that 14 CFR 1.1 uses to
/// define night.
public enum SolarPosition {
  private static let unixEpochJulianDay = 2_440_587.5
  private static let j2000JulianDay = 2_451_545.0
  private static let daysPerJulianCentury = 36_525.0
  private static let secondsPerDay = 86_400.0
  private static let minutesPerDay = 1_440.0
  private static let minutesPerDegreeOfLongitude = 4.0

  /**
   The geometric elevation of the center of the Sun above the horizon, without refraction.

   - Parameters:
     - date: The moment.
     - latitudeDeg: The observer's latitude, north positive.
     - longitudeDeg: The observer's longitude, east positive.
   - Returns: The elevation in degrees, negative when the Sun is below the horizon.
   */
  public static func elevation(at date: Date, latitudeDeg: Double, longitudeDeg: Double) -> Double {
    let julianDay = date.timeIntervalSince1970 / secondsPerDay + unixEpochJulianDay
    let centuries = (julianDay - j2000JulianDay) / daysPerJulianCentury
    let (declination, equationOfTime) = declinationAndEquationOfTime(centuries: centuries)

    let utcMinutes = (date.timeIntervalSince1970 / 60).truncatingRemainder(
      dividingBy: minutesPerDay
    )
    var trueSolarMinutes =
      (utcMinutes + equationOfTime + minutesPerDegreeOfLongitude * longitudeDeg)
      .truncatingRemainder(dividingBy: minutesPerDay)
    if trueSolarMinutes < 0 { trueSolarMinutes += minutesPerDay }
    let hourAngle = radians(trueSolarMinutes / minutesPerDegreeOfLongitude - 180)

    let latitude = radians(latitudeDeg)
    let cosZenith =
      sin(latitude) * sin(declination) + cos(latitude) * cos(declination) * cos(hourAngle)
    return 90 - degrees(acos(min(1, max(-1, cosZenith))))
  }

  /// The solar declination in radians and the equation of time in minutes.
  private static func declinationAndEquationOfTime(centuries t: Double) -> (Double, Double) {
    let meanLongitude = (280.46646 + t * (36_000.76983 + t * 0.000_303_2))
      .truncatingRemainder(dividingBy: 360)
    let meanAnomaly = radians(357.52911 + t * (35_999.05029 - 0.000_153_7 * t))
    let eccentricity = 0.016_708_634 - t * (0.000_042_037 + 0.000_000_126_7 * t)
    let center =
      sin(meanAnomaly) * (1.914602 - t * (0.004817 + 0.000014 * t))
      + sin(2 * meanAnomaly) * (0.019993 - 0.000101 * t)
      + sin(3 * meanAnomaly) * 0.000289
    let omega = radians(125.04 - 1_934.136 * t)
    let apparentLongitude = radians(meanLongitude + center - 0.00569 - 0.00478 * sin(omega))

    let meanObliquity = 23 + (26 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60) / 60
    let obliquity = radians(meanObliquity + 0.00256 * cos(omega))
    let declination = asin(sin(obliquity) * sin(apparentLongitude))

    let y = pow(tan(obliquity / 2), 2)
    let l0 = radians(meanLongitude)
    let equationOfTime =
      4
      * degrees(
        y * sin(2 * l0) - 2 * eccentricity * sin(meanAnomaly)
          + 4 * eccentricity * y * sin(meanAnomaly) * cos(2 * l0)
          - 0.5 * y * y * sin(4 * l0)
          - 1.25 * eccentricity * eccentricity * sin(2 * meanAnomaly)
      )
    return (declination, equationOfTime)
  }

  private static func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }

  private static func degrees(_ radians: Double) -> Double { radians * 180 / .pi }
}
