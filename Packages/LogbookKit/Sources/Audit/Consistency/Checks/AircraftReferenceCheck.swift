import Foundation
import LogbookModel

/// Flags entries that refer to an aircraft the logbook doesn't contain.
struct AircraftReferenceCheck: ConsistencyCheck {
  var rules: [ConsistencyRule] { [.brokenAircraftReference] }

  func check(_ context: ConsistencyContext, into collector: inout FindingCollector) {
    let known = Set(context.logbook.aircraft.map(\.id))
    for flight in context.flights {
      guard let aircraft = flight.flight.aircraft, !known.contains(aircraft.id) else { continue }
      collector.emit(
        .brokenAircraftReference,
        [flight.id],
        message: String(
          localized: "The flight refers to an aircraft that isn’t in the logbook.",
          bundle: .module
        ),
        evidence: ["aircraft_pk": .string(aircraft.id.rawValue)],
        severity: .discrepancy
      )
    }
  }
}
