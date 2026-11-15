public import Foundation
public import LogbookModel

/// Chronologically sorted flights with logarithmic date-range lookups.
///
/// Date queries use binary search over the sorted array, then filter only the slice that falls
/// in range, so a query costs O(log N + K) instead of O(N).
package struct FlightIndex: Sendable {
  /// All flights in chronological order, ties broken by record identifier.
  package let flights: [Flight]

  /// The calendar, in the pilot's time zone, that defines the days and months of windows.
  package let calendar: Calendar

  /// Creates an index.
  ///
  /// - Parameters:
  ///   - flights: The flights, in any order.
  ///   - calendar: The calendar that defines days and months.
  package init(flights: [Flight], calendar: Calendar) {
    self.flights = flights.sorted { ($0.date, $0.id) < ($1.date, $1.id) }
    self.calendar = calendar
  }

  /// The index of the first flight on or after a date, or `flights.count` if there is none.
  package func lowerBound(for targetDate: Date) -> Int {
    partitionPoint { $0.date < targetDate }
  }

  /// The index of the first flight after a date, or `flights.count` if there is none.
  package func upperBound(for targetDate: Date) -> Int {
    partitionPoint { $0.date <= targetDate }
  }

  /**
   Returns the flights in a window that precede or coincide with a flight and match criteria.

   - Parameters:
     - window: The lookback window.
     - flight: The reference flight, which is excluded from the result.
     - criteria: Aircraft matching criteria.
   */
  package func flights(
    within window: TimeWindow,
    of flight: Flight,
    matching criteria: FlightMatchCriteria
  ) -> [Flight] {
    flights(
      from: window.startDate(from: flight.date, in: calendar),
      to: flight.date,
      excluding: flight,
      matching: criteria
    )
  }

  /**
   Returns the flights in an inclusive date range that match criteria.

   - Parameters:
     - startDate: The start of the range.
     - endDate: The end of the range.
     - excludedFlight: A flight to leave out, usually the reference flight.
     - criteria: Aircraft matching criteria.
   */
  package func flights(
    from startDate: Date,
    to endDate: Date,
    excluding excludedFlight: Flight,
    matching criteria: FlightMatchCriteria
  ) -> [Flight] {
    let range = lowerBound(for: startDate)..<upperBound(for: endDate)
    guard !range.isEmpty else { return [] }
    return flights[range].filter { $0.id != excludedFlight.id && criteria.matches($0) }
  }

  /// Returns the flights dated strictly before a flight.
  package func flights(before flight: Flight) -> ArraySlice<Flight> {
    flights[..<lowerBound(for: flight.date)]
  }

  private func partitionPoint(where isBefore: (Flight) -> Bool) -> Int {
    var low = 0
    var high = flights.count
    while low < high {
      let middle = low + (high - low) / 2
      if isBefore(flights[middle]) {
        low = middle + 1
      } else {
        high = middle
      }
    }
    return low
  }
}
