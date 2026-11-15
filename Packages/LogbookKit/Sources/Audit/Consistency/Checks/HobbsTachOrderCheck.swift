import Foundation
import LogbookModel

/**
 Flags Hobbs or tach readings that end lower than they start.

 The finding offers swapping the two readings of each pair that is reversed, since a reading
 entered in the wrong box is the usual cause.
 */
struct HobbsTachOrderCheck: ConsistencyCheck {
  var rules: [ConsistencyRule] { [.hobbsTachOrder] }

  func check(_ context: ConsistencyContext, into collector: inout FindingCollector) {
    for flight in context.flights {
      let reversed = pairs(of: flight).filter { $0.stop < $0.start }
      guard !reversed.isEmpty else { continue }
      collector.emit(
        .hobbsTachOrder,
        [flight.id],
        message: String(
          localized: "\(FlightTimeText.list(reversed.map(\.title))) end below their start.",
          bundle: .module
        ),
        evidence: .object(
          Dictionary(
            uniqueKeysWithValues: reversed.flatMap {
              [
                (String($0.startKey.attributeName).lowercased(), JSONValue.double($0.start)),
                (String($0.stopKey.attributeName).lowercased(), JSONValue.double($0.stop))
              ]
            }
          )
        ),
        severity: .questionable,
        explanation: String(
          localized:
            "An engine meter only counts up, so its ending reading can’t be lower than its starting reading.",
          bundle: .module
        ),
        recommendation: String(
          localized:
            "Check the readings against the aircraft’s meter. If they were entered in the wrong boxes, swap them.",
          bundle: .module
        ),
        corrections: [swapOption(flight, reversed)]
      )
    }
  }

  private func pairs(of flight: AuditedFlight) -> [Pair] {
    let readings = [
      (
        String(localized: "Hobbs", bundle: .module), LogTenFieldKey.flightHobbsStart,
        LogTenFieldKey.flightHobbsStop, flight.flight.hobbsStart, flight.flight.hobbsStop
      ),
      (
        String(localized: "Tach", bundle: .module), .flightTachStart, .flightTachStop,
        flight.flight.tachStart, flight.flight.tachStop
      )
    ]
    return readings.compactMap { title, startKey, stopKey, start, stop in
      guard let start, let stop else { return nil }
      return Pair(title: title, startKey: startKey, stopKey: stopKey, start: start, stop: stop)
    }
  }

  private func swapOption(_ flight: AuditedFlight, _ reversed: [Pair]) -> CorrectionOption {
    CorrectionOption(
      title: String(localized: "Swap the Readings", bundle: .module),
      detail: String(
        localized:
          "The start and end readings of \(FlightTimeText.list(reversed.map(\.title))) trade places.",
        bundle: .module
      ),
      changes: reversed.flatMap {
        [
          flight.change($0.startKey, to: .number($0.stop)),
          flight.change($0.stopKey, to: .number($0.start))
        ]
      }
    )
  }

  private struct Pair {
    let title: String
    let startKey: LogTenFieldKey
    let stopKey: LogTenFieldKey
    let start: Double
    let stop: Double
  }
}
