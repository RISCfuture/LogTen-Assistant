import Foundation
import LogbookModel

/// Flags IFR or actual instrument time in an aircraft the settings mark not IFR-capable.
struct IFRCapabilityCheck: ConsistencyCheck {
  private static let ifrTimes = ["ifr", "actualinstrument"]
  private static let capabilityBasis = "explicit aircraft configuration"
  private static let capabilityNote =
    "Confirm equipment at the flight date and the intended field. Simulated instrument practice alone is not flagged."

  var rules: [ConsistencyRule] { [.aircraftIFRCapability] }

  func check(_ context: ConsistencyContext, into collector: inout FindingCollector) {
    for flight in context.flights where !flight.isSimulator {
      guard let registration = flight.registration,
        context.settings.aircraft[registration]?.isIFRCapable == false
      else { continue }
      var recorded = [String: JSONValue]()
      for name in Self.ifrTimes where flight.hasPositive(name) {
        recorded[name] = flight[name].evidenceJSON
      }
      guard !recorded.isEmpty else { continue }
      collector.emit(
        .aircraftIFRCapability,
        [flight.id],
        message: String(
          localized:
            "IFR or actual instrument time is recorded in an aircraft marked not IFR-capable.",
          bundle: .module
        ),
        evidence: [
          "aircraft": .string(registration),
          "recorded_minutes": .object(recorded),
          "capability_basis": .string(Self.capabilityBasis),
          "equipment": .null,
          "note": .string(Self.capabilityNote)
        ],
        severity: .questionable
      )
    }
  }
}
