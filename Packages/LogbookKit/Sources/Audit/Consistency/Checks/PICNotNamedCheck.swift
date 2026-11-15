import Foundation
import LogbookModel

/// Flags SIC or P1 u/s time with no PIC named, on aircraft types where the pilot usually
/// names one.
struct PICNotNamedCheck: ConsistencyCheck {
  var rules: [ConsistencyRule] { [.picNotNamed] }

  private static func logsSupportingRole(_ flight: AuditedFlight) -> Bool {
    flight.hasPositive("sic") || flight.hasPositive("p1us")
  }

  func check(_ context: ConsistencyContext, into collector: inout FindingCollector) {
    let namesPIC = FlightHabit(
      over: context.flights,
      similarity: .aircraftType,
      when: Self.logsSupportingRole,
      records: { $0.flight.crew.PIC != nil }
    )
    for flight in context.flights
    where Self.logsSupportingRole(flight) && flight.flight.crew.PIC == nil
      && namesPIC.isUsual(for: flight)
    {
      collector.emit(
        .picNotNamed,
        [flight.id],
        message: String(
          localized: "SIC or P1 u/s time is logged, but no pilot in command is named.",
          bundle: .module
        ),
        evidence: [
          "sic": flight["sic"].evidenceJSON,
          "p1us": flight["p1us"].evidenceJSON
        ],
        explanation: String(
          localized:
            "Naming the pilot in command records who held command while you flew in a supporting role. You usually name one on similar flights, so leaving it out is worth a look.",
          bundle: .module
        ),
        recommendation: String(
          localized:
            "Add the pilot in command to the crew, or correct the role time if you were in command. If the entry is intentional, keep it as logged.",
          bundle: .module
        )
      )
    }
  }
}
