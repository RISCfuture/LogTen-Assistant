import Foundation
import LogbookModel
import Regulations

/// One flight in the Violations table, with the violations it shows.
nonisolated struct ViolationRow: Identifiable, Hashable {
  /// The flight.
  let flight: Flight

  /// The violations on the flight that the table is showing.
  let violations: [Violation]

  var id: RecordID { flight.id }

  var date: Date { flight.date }

  var registration: String { flight.aircraft?.registration ?? "" }

  var aircraftType: String { flight.aircraft?.type?.type ?? "" }

  var route: String { LogbookFormat.route(of: flight) ?? "" }

  var ruleTitles: String { violations.map(\.rule.title).formatted(.list(type: .and)) }

  var explanation: String { violations.map(\.explanation).joined(separator: " ") }

  var PICMinutes: UInt { flight.times.PIC }

  var passengerCount: Int { flight.passengers.count }

  /**
   Builds the table rows for a report.

   - Parameters:
     - report: The regulation report.
     - rule: The rule to show, or `nil` for every rule.
     - flight: Looks up a flight by identifier.
     - searchText: Text that one of the row's columns must contain, ignoring case; empty for
       all rows.
     - timeZone: The time zone the Date column shows days in.
   - Returns: One row per flight with a matching violation, oldest first.
   */
  static func rows(
    in report: RegulationReport,
    for rule: RegulationRule?,
    flight: (RecordID) -> Flight?,
    matching searchText: String,
    in timeZone: TimeZone
  ) -> [Self] {
    report.flights.compactMap { entry in
      let violations = entry.violations.filter { rule == nil || $0.rule == rule }
      guard !violations.isEmpty, let flight = flight(entry.flightID) else { return nil }
      let row = Self(flight: flight, violations: violations)
      return row.matches(searchText, in: timeZone) ? row : nil
    }
  }

  private func matches(_ searchText: String, in timeZone: TimeZone) -> Bool {
    let query = searchText.trimmingCharacters(in: .whitespaces)
    guard !query.isEmpty else { return true }
    return [
      LogbookFormat.date(date, in: timeZone), registration, aircraftType, route, ruleTitles,
      LogbookFormat.duration(minutes: PICMinutes), explanation, flight.remarks ?? ""
    ]
    .contains { $0.localizedStandardContains(query) }
  }
}
