import Foundation
import LogbookModel

/// Checks flights for one kind of regulatory violation.
///
/// A checker sees the whole logbook through its ``RegulationContext`` and does any expensive
/// precomputation in its initializer.
protocol ViolationChecker: Sendable {
  /// The rule the checker enforces.
  static var rule: RegulationRule { get }

  /// Creates a checker for a logbook.
  init(context: RegulationContext)

  /// Checks one flight, returning `nil` if it complies or the rule doesn't apply to it.
  func check(_ flight: Flight) -> Violation?
}

extension ViolationChecker {
  /// Builds a violation of this checker's rule on a flight.
  func violation(
    on flight: Flight,
    contributing: some Sequence<RecordID> = [RecordID](),
    explanation: String
  ) -> Violation {
    Violation(
      rule: Self.rule,
      flightID: flight.id,
      contributingFlightIDs: Array(contributing),
      explanation: explanation
    )
  }
}

extension RegulationRule {
  /// The checker type that enforces the rule.
  var checkerType: any ViolationChecker.Type {
    switch self {
      case .noFlightReview: NoFlightReview.self
      case .noPassengerCurrency: NoPassengerCurrency.self
      case .noNightPassengerCurrency: NoNightPassengerCurrency.self
      case .noIFRCurrency: NoIFRCurrency.self
      case .noProficiencyCheck: NoProficiencyCheck.self
      case .noProficiencyCheckInType: NoProficiencyCheckInType.self
      case .noNVGCurrency: NoNVGCurrency.self
      case .noNVGPassengerCurrency: NoNVGPassengerCurrency.self
      case .dualGiven8In24: DualGiven8In24.self
      case .dualGivenTimeInType: DualGivenTimeInType.self
      case .noSICCurrency: NoSICCurrency.self
    }
  }
}
