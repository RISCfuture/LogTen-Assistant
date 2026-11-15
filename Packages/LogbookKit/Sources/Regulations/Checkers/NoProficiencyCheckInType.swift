import Foundation
import LogbookModel

/// Flights in a type-rated aircraft without a proficiency check in that type in the preceding
/// 24 calendar months (14 CFR 61.58(a)(2)).
///
/// A check in a simulator that represents the type counts if the device is credited for it.
struct NoProficiencyCheckInType: ViolationChecker {
  static let rule = RegulationRule.noProficiencyCheckInType
  private static let months = 24

  private let context: RegulationContext

  init(context: RegulationContext) {
    self.context = context
  }

  func check(_ flight: Flight) -> Violation? {
    guard let aircraft = flight.aircraft, context.resolver.requiresTypeRating(aircraft),
      !flight.isDualReceived, !context.isMarked(.proficiencyCheck, on: flight)
    else { return nil }

    let recent = context.flights(
      within: .calendarMonths(Self.months),
      of: flight,
      matching: context.sameType(for: flight, credit: .proficiencyCheck)
    )
    let checks = recent.filter { context.isMarked(.proficiencyCheck, on: $0) }
    guard checks.isEmpty else { return nil }

    return violation(
      on: flight,
      explanation: String(
        localized:
          "Flew an aircraft that requires a type rating with no proficiency check in this type in the preceding 24 calendar months.",
        bundle: .module
      )
    )
  }
}
