import Foundation
import LogbookModel

/// Flight instruction totaling more than eight hours in any 24 consecutive hours
/// (14 CFR 61.195(a)).
///
/// The total includes the flight being checked and every other flight whose start falls in the
/// 24 hours ending when it started. A flight starts at its block-out or takeoff time, or at its
/// date if it has no times.
struct DualGiven8In24: ViolationChecker {
  static let rule = RegulationRule.dualGiven8In24
  private static let limitMinutes: UInt = 8 * 60
  private static let window: TimeInterval = 24 * 60 * 60
  private static let searchMargin: TimeInterval = 24 * 60 * 60

  private let context: RegulationContext

  init(context: RegulationContext) {
    self.context = context
  }

  func check(_ flight: Flight) -> Violation? {
    if !flight.isDualGiven || !flight.isPIC { return nil }
    let end = flight.startInstant
    let instruction = nearbyFlights(around: flight).filter { candidate in
      candidate.isDualGiven && end - Self.window < candidate.startInstant
        && candidate.startInstant <= end
    }
    let minutes = instruction.total(\.times.dualGiven)
    guard minutes > Self.limitMinutes else { return nil }
    return violation(
      on: flight,
      contributing: instruction.ids.filter { $0 != flight.id },
      explanation: String(
        localized:
          "Gave \(Double(minutes) / 60, format: .number.precision(.fractionLength(0...1))) hours of flight instruction in the 24 hours ending when this flight started; the limit is 8.",
        bundle: .module
      )
    )
  }

  private func nearbyFlights(around flight: Flight) -> [Flight] {
    let index = context.index
    let start = flight.date - Self.window - Self.searchMargin
    let end = flight.date + Self.searchMargin
    return Array(index.flights[index.lowerBound(for: start)..<index.upperBound(for: end)])
  }
}

/// Flight instruction in a multi-engine airplane, helicopter or powered-lift aircraft without
/// five hours as pilot in command in that make and model (14 CFR 61.195(f)).
struct DualGivenTimeInType: ViolationChecker {
  static let rule = RegulationRule.dualGivenTimeInType
  private static let requiredMinutes: UInt = 5 * 60

  private let context: RegulationContext

  init(context: RegulationContext) {
    self.context = context
  }

  func check(_ flight: Flight) -> Violation? {
    if !flight.isDualGiven || !flight.isPIC { return nil }
    guard requiresTimeInType(flight), let type = context.resolver.typeDesignator(of: flight)
    else { return nil }

    let sameType = context.index.flights(before: flight).filter {
      context.resolver.typeDesignator(of: $0) == type
    }
    let minutes = sameType.total(\.times.PIC)
    guard minutes < Self.requiredMinutes else { return nil }
    return violation(
      on: flight,
      contributing: sameType.filter(\.isPIC).ids,
      explanation: String(
        localized:
          "Gave flight instruction with \(Double(minutes) / 60, format: .number.precision(.fractionLength(0...1))) hours as pilot in command in this make and model; 5 are required.",
        bundle: .module
      )
    )
  }

  private func requiresTimeInType(_ flight: Flight) -> Bool {
    switch context.resolver.category(of: flight) {
      case .airplane:
        context.resolver.aircraftClass(of: flight) == .multiEngineLand
          || context.resolver.aircraftClass(of: flight) == .multiEngineSea
      case .rotorcraft, .poweredLift: true
      default: false
    }
  }
}
