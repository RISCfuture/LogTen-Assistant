import Foundation
import LogbookModel

/// Flags simulator sessions that log total time but no simulator or SFI time.
struct SimulatorSessionTimeCheck: ConsistencyCheck {
  var rules: [ConsistencyRule] { [.simulatorSessionTime] }

  func check(_ context: ConsistencyContext, into collector: inout FindingCollector) {
    for flight in context.flights
    where flight.flight.aircraft?.type?.category?.isSimulationDevice == true
      && flight.hasPositive("totaltime")
      && !SimulatorTimes.names.contains(where: flight.hasPositive)
    {
      collector.emit(
        .simulatorSessionTime,
        [flight.id],
        message: String(
          localized: "A simulator session logs total time but no simulator time.",
          bundle: .module
        ),
        evidence: ["totaltime": flight["totaltime"].evidenceJSON],
        explanation: String(
          localized:
            "Time in a simulator or training device is counted under simulator time. Without it, the session adds to totals as if it were flown in an aircraft.",
          bundle: .module
        ),
        recommendation: String(
          localized:
            "Enter the session’s duration as simulator time, or as SFI time if you instructed. If the entry is intentional, keep it as logged.",
          bundle: .module
        )
      )
    }
  }
}
