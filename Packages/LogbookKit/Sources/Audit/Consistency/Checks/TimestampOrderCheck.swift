import Foundation
import LogbookModel

/// Flags out, off, on and in times entered out of order, with a diagnosis of likely date
/// errors.
struct TimestampOrderCheck: ConsistencyCheck {
  private static let eventNames = ["out", "takeoff", "landing", "in"]
  private static let eventFields: [String: LogTenFieldKey] = [
    "out": .flightActualDepartureTime, "takeoff": .flightTakeoffTime,
    "landing": .flightLandingTime, "in": .flightActualArrivalTime
  ]

  var rules: [ConsistencyRule] { [.timestampOrder] }

  func check(_ context: ConsistencyContext, into collector: inout FindingCollector) {
    for flight in context.flights {
      let known = events(of: flight)
      for (earlier, later) in zip(known, known.dropFirst()) where later.time < earlier.time {
        collector.emit(
          .timestampOrder,
          [flight.id],
          message: String(
            localized: "\(eventTitle(later.name)) precedes \(eventTitle(earlier.name)).",
            bundle: .module
          ),
          evidence: .object([
            earlier.name: .string(PythonTimestamp.isoformat(earlier.time)),
            later.name: .string(PythonTimestamp.isoformat(later.time))
          ]),
          severity: .discrepancy,
          explanation: String(
            localized:
              "Out, off, on and in are the four moments of a flight in order, so none can be earlier than the one before it.",
            bundle: .module
          ),
          recommendation: String(
            localized:
              "Check the date and clock time of each. If two times were entered in each other’s boxes, swap them.",
            bundle: .module
          ),
          corrections: swapOptions(earlier, later, in: known, of: flight)
        )
      }
      collector.attachTimeDiagnosis(of: flight, toFindingsOf: rules, context: context)
    }
  }

  /// An option that swaps the two times, offered when doing so puts every time in order.
  private func swapOptions(
    _ earlier: (name: String, time: Date),
    _ later: (name: String, time: Date),
    in known: [(name: String, time: Date)],
    of flight: AuditedFlight
  ) -> [CorrectionOption] {
    let swapped = known.map { event in
      event.name == earlier.name ? later.time : event.name == later.name ? earlier.time : event.time
    }
    guard zip(swapped, swapped.dropFirst()).allSatisfy({ $0 <= $1 }),
      let earlierField = Self.eventFields[earlier.name],
      let laterField = Self.eventFields[later.name]
    else { return [] }
    return [
      CorrectionOption(
        title: String(
          localized: "Swap \(eventTitle(earlier.name)) and \(eventTitle(later.name))",
          bundle: .module
        ),
        detail: String(
          localized:
            "The \(eventTitle(earlier.name)) and \(eventTitle(later.name)) times trade places.",
          bundle: .module
        ),
        changes: [
          flight.change(earlierField, to: .date(later.time)),
          flight.change(laterField, to: .date(earlier.time))
        ]
      )
    ]
  }

  private func events(of flight: AuditedFlight) -> [(name: String, time: Date)] {
    let events = flight.flight.events
    return zip(Self.eventNames, [events.out, events.off, events.on, events.in]).compactMap {
      name,
      time in time.map { (name, $0) }
    }
  }

  private func eventTitle(_ name: String) -> String {
    switch name {
      case "out": String(localized: "Out", bundle: .module)
      case "takeoff": String(localized: "Off", bundle: .module)
      case "landing": String(localized: "On", bundle: .module)
      default: String(localized: "In", bundle: .module)
    }
  }
}
