public import Foundation
import SwiftNASR

/**
 The data sources a logbook's audit draws on that are out of date.

 NASR airport data and CIFP approach data are out of date when the saved cycle isn't the AIRAC
 cycle in effect, or when none is saved. FlySto is out of date when an API token is stored and
 the last sync finished before the date of the newest flight logged up to now, or never
 happened; without a token there is nothing to sync. ADS-B traces are fetched for chosen days
 and never go out of date.
 */
public struct StaleDataSources: Hashable, Sendable {
  /// Whether the saved NASR airport data isn't from the cycle in effect.
  public var isAirportDataStale: Bool

  /// Whether the saved CIFP approach data isn't from the cycle in effect.
  public var isApproachDataStale: Bool

  /// Whether FlySto has flights to sync.
  public var isFlyStoStale: Bool

  /// When FlySto last synced, or `nil` if it never has.
  public var flyStoLastSynced: Date?

  /// Whether every data source is up to date.
  public var isEmpty: Bool { !isAirportDataStale && !isApproachDataStale && !isFlyStoStale }

  /// Creates a set of data sources that are out of date as stated.
  public init(
    isAirportDataStale: Bool = false,
    isApproachDataStale: Bool = false,
    isFlyStoStale: Bool = false,
    flyStoLastSynced: Date? = nil
  ) {
    self.isAirportDataStale = isAirportDataStale
    self.isApproachDataStale = isApproachDataStale
    self.isFlyStoStale = isFlyStoStale
    self.flyStoLastSynced = flyStoLastSynced
  }

  /**
   Works out which data sources are out of date.

   - Parameters:
     - airportCycle: The effective date of the newest saved NASR cycle, if any.
     - approachCycle: The effective date of the saved CIFP cycle, if any.
     - hasFlyStoToken: Whether a FlySto API token is stored.
     - flyStoLastSynced: When the last FlySto sync finished, if one did.
     - flightDates: The dates of the logbook's flights.
     - date: Now.
   */
  public init(
    airportCycle: Date?,
    approachCycle: Date?,
    hasFlyStoToken: Bool,
    flyStoLastSynced: Date?,
    flightDates: some Sequence<Date>,
    asOf date: Date = .now
  ) {
    let cycle = Cycle.effectiveCycle(for: date)?.effectiveDate
    isAirportDataStale = airportCycle == nil || airportCycle != cycle
    isApproachDataStale = approachCycle == nil || approachCycle != cycle
    self.flyStoLastSynced = flyStoLastSynced
    isFlyStoStale =
      hasFlyStoToken
      && Self.hasFlights(after: flyStoLastSynced, in: flightDates, upTo: date)
  }

  private static func hasFlights(
    after lastSynced: Date?,
    in flightDates: some Sequence<Date>,
    upTo date: Date
  ) -> Bool {
    guard let newest = flightDates.filter({ $0 <= date }).max() else { return lastSynced == nil }
    guard let lastSynced else { return true }
    return lastSynced < newest
  }
}
