import Foundation
import LogbookModel

/// Flags simulator or SFI time on an entry whose aircraft type isn't a simulator or training
/// device.
struct SimulatorTimeInAircraftCheck: ConsistencyCheck {
  var rules: [ConsistencyRule] { [.simulatorTimeInAircraft] }

  func check(_ context: ConsistencyContext, into collector: inout FindingCollector) {
    for flight in context.flights {
      guard let category = flight.flight.aircraft?.type?.category, !category.isSimulationDevice
      else { continue }
      var recorded = [String: JSONValue]()
      for name in SimulatorTimes.names where flight.hasPositive(name) {
        recorded[name] = flight[name].evidenceJSON
      }
      guard !recorded.isEmpty else { continue }
      collector.emit(
        .simulatorTimeInAircraft,
        [flight.id],
        message: String(
          localized: "Simulator time is logged in an aircraft type that isn’t a simulator.",
          bundle: .module
        ),
        evidence: [
          "category": .string(category.rawValue),
          "recorded_minutes": .object(recorded)
        ],
        severity: .questionable,
        explanation: String(
          localized:
            "Simulator and SFI time belongs to sessions in a simulator or training device. In a real aircraft it is counted in the wrong totals.",
          bundle: .module
        ),
        recommendation: String(
          localized:
            "Choose a simulator aircraft for the entry, or move the time to the roles you flew in the aircraft. If the entry is intentional, keep it as logged.",
          bundle: .module
        )
      )
    }
  }
}

/// The time fields that record work in a simulator or as a simulator instructor.
enum SimulatorTimes {
  /// Lowercased attribute names.
  static let names = ["simulator", "sfi"]
}
