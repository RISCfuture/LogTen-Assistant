import Foundation
import LogbookModel

/// Flags approaches logged without instrument time, and named approaches without a count.
struct ApproachCheck: ConsistencyCheck {
  private static let instrumentContext = ["actualinstrument", "simulatedinstrument", "simulator"]

  var rules: [ConsistencyRule] { [.approachWithoutInstrumentContext, .approachQuantityMissing] }

  func check(_ context: ConsistencyContext, into collector: inout FindingCollector) {
    for flight in context.flights {
      checkInstrumentContext(of: flight, into: &collector)
      checkQuantities(of: flight, into: &collector)
    }
  }

  private func checkInstrumentContext(
    of flight: AuditedFlight,
    into collector: inout FindingCollector
  ) {
    let approaches = flight.flight.approaches
    let hasInstrumentContext = Self.instrumentContext.contains(where: flight.hasPositive)
    guard approaches.contains(where: { $0.count >= 1 }), !hasInstrumentContext,
      !flight.isSimulator
    else { return }
    collector.emit(
      .approachWithoutInstrumentContext,
      [flight.id],
      message: String(
        localized: "Approaches lack recorded actual, simulated, or simulator instrument context.",
        bundle: .module
      ),
      evidence: ["approaches": .array(approaches.map(\.evidence))],
      severity: .questionable
    )
  }

  private func checkQuantities(of flight: AuditedFlight, into collector: inout FindingCollector) {
    for approach in flight.flight.approaches where approach.count < 1 && approach.isNamed {
      collector.emit(
        .approachQuantityMissing,
        [flight.id],
        message: String(
          localized: "Named approach has no recorded quantity; no currency credit was inferred.",
          bundle: .module
        ),
        evidence: ["approach": approach.evidence]
      )
    }
  }
}

extension Approach {
  /// Whether the approach records a type, place or runway.
  fileprivate var isNamed: Bool { type != nil || place != nil || runway != nil }

  /// The approach as finding evidence.
  fileprivate var evidence: JSONValue {
    [
      "id": .string(id.rawValue),
      "type": type.map { .string($0.rawValue) } ?? .null,
      "place": place.map { .string($0.preferredIdentifier) } ?? .null,
      "comment": runway.map(JSONValue.string) ?? .null,
      "quantity": .integer(Int(count))
    ]
  }
}
