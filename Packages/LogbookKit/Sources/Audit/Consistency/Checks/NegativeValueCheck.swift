import Foundation
import LogbookModel

/// Flags times and counts below zero.
struct NegativeValueCheck: ConsistencyCheck {
  private static let checkedNames: Set = [
    "totaltime", "actualinstrument", "simulatedinstrument", "pic", "sic", "night",
    "totallandings", "totaltakeoffs", "fullstops"
  ]
  private static let checkedPrefixes = ["customtime", "customlanding", "customtakeoff"]

  var rules: [ConsistencyRule] { [.negativeValue] }

  func check(_ context: ConsistencyContext, into collector: inout FindingCollector) {
    for flight in context.flights {
      for (name, value) in flight.values where isChecked(name) {
        guard let number = flight.number(name), number < 0 else { continue }
        collector.emit(
          .negativeValue,
          [flight.id],
          message: String(
            localized: "\(context.title(of: name, in: flight)) is negative.",
            bundle: .module
          ),
          evidence: .object([name: value.evidenceJSON]),
          severity: .discrepancy
        )
      }
    }
  }

  private func isChecked(_ name: String) -> Bool {
    Self.checkedNames.contains(name) || Self.checkedPrefixes.contains(where: name.hasPrefix)
  }
}
