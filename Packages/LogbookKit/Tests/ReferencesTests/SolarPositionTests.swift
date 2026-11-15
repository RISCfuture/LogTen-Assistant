import Foundation
import References
import Testing

@Suite
struct `Solar position` {
  private static let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    return calendar
  }()

  @Test(arguments: [
    Solstice(
      place: "San Francisco",
      latitudeDeg: 37.62,
      longitudeDeg: -122.38,
      date: DateComponents(year: 2024, month: 12, day: 21),
      northernSummer: false
    ),
    Solstice(
      place: "San Francisco",
      latitudeDeg: 37.62,
      longitudeDeg: -122.38,
      date: DateComponents(year: 2024, month: 6, day: 20),
      northernSummer: true
    ),
    Solstice(
      place: "Sydney",
      latitudeDeg: -33.95,
      longitudeDeg: 151.18,
      date: DateComponents(year: 2024, month: 12, day: 21),
      northernSummer: false
    )
  ])
  func `reaches the solstice noon elevation`(_ solstice: Solstice) throws {
    let midnight = try #require(Self.utc.date(from: solstice.date))
    let elevations = stride(from: 0.0, to: 86_400, by: 60).map { offset in
      SolarPosition.elevation(
        at: midnight.addingTimeInterval(offset),
        latitudeDeg: solstice.latitudeDeg,
        longitudeDeg: solstice.longitudeDeg
      )
    }
    let peak = try #require(elevations.max())
    #expect(abs(peak - solstice.noonElevationDeg) < 0.2)
  }

  @Test
  func `puts the Sun overhead at solar noon on the equinox at the equator`() throws {
    let solarNoon = try #require(
      Self.utc.date(from: DateComponents(year: 2024, month: 3, day: 20, hour: 12, minute: 7))
    )
    let solarMidnight = solarNoon.addingTimeInterval(12 * 3_600)
    #expect(SolarPosition.elevation(at: solarNoon, latitudeDeg: 0, longitudeDeg: 0) > 89.5)
    #expect(SolarPosition.elevation(at: solarMidnight, latitudeDeg: 0, longitudeDeg: 0) < -89.5)
  }

  /// A solstice day at a place, and the Sun's elevation at local noon: 90° less the angle
  /// between the latitude and the solar declination of ±23.44°.
  struct Solstice: Sendable, CustomTestStringConvertible {
    static let declinationDeg = 23.44

    let place: String
    let latitudeDeg: Double
    let longitudeDeg: Double
    let date: DateComponents
    let northernSummer: Bool

    var testDescription: String { "\(place) \(northernSummer ? "June" : "December")" }

    var noonElevationDeg: Double {
      90 - abs(latitudeDeg - (northernSummer ? Self.declinationDeg : -Self.declinationDeg))
    }
  }
}
