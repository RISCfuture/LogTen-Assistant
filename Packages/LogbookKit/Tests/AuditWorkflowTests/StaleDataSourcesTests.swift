import AuditWorkflow
import Foundation
import Testing

@Suite
struct `Stale data sources` {
  private static let today = utc("2026-11-09T12:00:00Z")
  private static let currentCycle = utc("2026-10-29T00:00:00Z")
  private static let previousCycle = utc("2026-10-01T00:00:00Z")
  private static let flights = [utc("2026-11-01T00:00:00Z"), utc("2026-11-07T00:00:00Z")]

  private static func stale(
    cycle: Date? = currentCycle,
    hasToken: Bool = true,
    lastSynced: Date?,
    flights: [Date] = flights
  ) -> StaleDataSources {
    StaleDataSources(
      airportCycle: cycle,
      approachCycle: cycle,
      hasFlyStoToken: hasToken,
      flyStoLastSynced: lastSynced,
      flightDates: flights,
      asOf: today
    )
  }

  @Test(arguments: [(currentCycle, false), (previousCycle, true), (nil, true)])
  func `finds reference data stale unless it is from the cycle in effect`(
    cycle: Date?,
    isStale: Bool
  ) {
    let sources = Self.stale(cycle: cycle, lastSynced: Self.today)

    #expect(sources.isAirportDataStale == isStale)
    #expect(sources.isApproachDataStale == isStale)
  }

  @Test
  func `finds FlySto stale when it last synced before the newest flight`() {
    #expect(Self.stale(lastSynced: utc("2026-11-06T20:00:00Z")).isFlyStoStale)
    #expect(Self.stale(lastSynced: nil).isFlyStoStale)
    #expect(!Self.stale(lastSynced: utc("2026-11-07T20:00:00Z")).isFlyStoStale)
  }

  @Test
  func `leaves FlySto alone without a token or for flights dated after today`() {
    let tomorrow = utc("2026-11-10T00:00:00Z")
    let lastSynced = utc("2026-11-08T00:00:00Z")

    #expect(!Self.stale(hasToken: false, lastSynced: nil).isFlyStoStale)
    #expect(!Self.stale(lastSynced: lastSynced, flights: Self.flights + [tomorrow]).isFlyStoStale)
  }
}
