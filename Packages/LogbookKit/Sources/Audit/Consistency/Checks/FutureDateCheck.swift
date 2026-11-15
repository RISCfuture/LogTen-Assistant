import Foundation
import LogbookModel

/**
 Flags entries dated or timed in the future that already log total time.

 An entry is in the future when its date, in the pilot's home time zone, is after the audit's
 date, or when its out or in time is after the audit's moment. Entries that log no total time
 are planned flights and aren't flagged.
 */
struct FutureDateCheck: ConsistencyCheck {
  var rules: [ConsistencyRule] { [.futureDate] }

  func check(_ context: ConsistencyContext, into collector: inout FindingCollector) {
    let calendar = context.calendar
    for flight in context.flights where flight.flight.times.total > 0 {
      let isDateInFuture = calendar.startOfDay(for: flight.flight.date) > context.asOf
      let futureTimes = [flight.flight.events.out, flight.flight.events.in].compactMap(\.self)
        .filter { $0 > context.asOf }
      guard isDateInFuture || !futureTimes.isEmpty else { continue }
      collector.emit(
        .futureDate,
        [flight.id],
        message: isDateInFuture
          ? String(localized: "The flight is dated in the future.", bundle: .module)
          : String(localized: "The flight has a time in the future.", bundle: .module),
        evidence: [
          "date": .string(PythonTimestamp.isoformat(flight.flight.date)),
          "totaltime": flight["totaltime"].evidenceJSON
        ],
        severity: .questionable,
        explanation: String(
          localized:
            "A flight can’t have been flown, with time to log, before its date and times have passed.",
          bundle: .module
        ),
        recommendation: String(
          localized:
            "Correct the date or times if they were mistyped. If this is a planned flight, clear its total time until it has been flown.",
          bundle: .module
        )
      )
    }
  }
}
