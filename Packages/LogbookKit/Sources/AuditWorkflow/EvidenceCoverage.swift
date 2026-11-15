import Audit
public import Foundation
public import LogbookModel

/// How much of one aircraft's logbook activity external evidence covers.
public struct AircraftCoverage: Identifiable, Hashable, Sendable {
  /// The aircraft's registration.
  public var registration: String

  /// The number of entries in the aircraft.
  public var flightCount: Int

  /// The entries matched to exactly one FlySto record.
  public var flyStoCount: Int

  /// The entries with ADS-B positions or a matched track segment.
  public var adsbCount: Int

  /// The earliest entry's date.
  public var firstFlight: Date?

  /// The latest entry's date.
  public var lastFlight: Date?

  public var id: String { registration }
}

extension AuditRun {
  /**
   The evidence coverage of each aircraft in a logbook.

   - Parameter logbook: The audited snapshot.
   - Returns: One summary per registration flown, ordered by registration.
   */
  public func coverage(of logbook: Logbook) -> [AircraftCoverage] {
    let flyStoFlights = Set(flyStoMatches.filter { $0.status == .matched }.compactMap(\.flightID))
    let trackedFlights = Set(
      contexts.filter { !$0.value.adsbPoints.isEmpty || !$0.value.segments.isEmpty }.keys
    )
    let aircraftFlights = logbook.flights.filter {
      $0.aircraft?.type?.category?.isSimulationDevice != true
    }
    let flown = Dictionary(grouping: aircraftFlights) { $0.aircraft?.registration ?? "" }
    let registered = flown.filter { !$0.key.isEmpty }
    return registered.map { registration, flights in
      let dates = flights.map(\.date)
      return AircraftCoverage(
        registration: registration,
        flightCount: flights.count,
        flyStoCount: flights.count(where: { flyStoFlights.contains($0.id) }),
        adsbCount: flights.count(where: { trackedFlights.contains($0.id) }),
        firstFlight: dates.min(),
        lastFlight: dates.max()
      )
    }
    .sorted { $0.registration < $1.registration }
  }
}
