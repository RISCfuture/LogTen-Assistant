public import Foundation
public import LogbookModel

/**
 How far back the findings shown reach, by the dates of the flights they involve: the last 90
 days, this calendar year, or the whole logbook.

 Days and years are reckoned in the pilot's home time zone. A scope has no end, so flights
 dated after today are always in it. A finding is in scope when any flight it involves is; a
 finding that involves no flight, such as one about a place or a smart group, is in every
 scope.
 */
public enum AuditScope: String, CaseIterable, Codable, Sendable {
  /// Flights from the day 90 days before today onward.
  case last90Days = "last_90_days"
  /// Flights from January 1 of the current year onward.
  case thisYear = "this_year"
  /// Every flight.
  case all

  private static let recentDays = 90

  /**
   The earliest instant the scope includes, or `nil` if it includes everything.

   - Parameters:
     - date: Today, or the date the audit is reviewed as of.
     - timeZone: The pilot's home time zone.
   */
  public func start(asOf date: Date, in timeZone: TimeZone) -> Date? {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    switch self {
      case .last90Days:
        let earlier = calendar.date(byAdding: .day, value: -Self.recentDays, to: date) ?? date
        return calendar.startOfDay(for: earlier)
      case .thisYear:
        return calendar.dateInterval(of: .year, for: date)?.start
      case .all:
        return nil
    }
  }

  /**
   The findings in scope.

   - Parameters:
     - findings: The findings, in the order to keep.
     - logbook: The snapshot the findings came from, for their flights' dates.
     - date: Today, or the date the audit is reviewed as of.
     - timeZone: The pilot's home time zone.
   - Returns: The findings that involve a flight in scope or no flight at all.
   */
  public func findings(
    _ findings: [Finding],
    in logbook: Logbook,
    asOf date: Date,
    timeZone: TimeZone
  ) -> [Finding] {
    guard let start = start(asOf: date, in: timeZone) else { return findings }
    let dates = Dictionary(logbook.flights.map { ($0.id, $0.date) }) { first, _ in first }
    return findings.filter { finding in
      let flightDates = finding.recordIDs.compactMap { dates[$0] }
      return flightDates.isEmpty || flightDates.contains { $0 >= start }
    }
  }
}
