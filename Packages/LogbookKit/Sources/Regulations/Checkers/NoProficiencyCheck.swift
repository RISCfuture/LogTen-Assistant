import Foundation
import LogbookModel

/// Flights in a type-rated aircraft without a pilot-in-command proficiency check in the preceding
/// 12 calendar months (14 CFR 61.58(a)(1)).
///
/// The check can be in any aircraft that requires a type rating. A proficiency check the user
/// confirmed in the logbook settings counts in the month given, which is how a check credited to
/// the month before or after the month it was due is recorded.
struct NoProficiencyCheck: ViolationChecker {
  static let rule = RegulationRule.noProficiencyCheck
  private static let months = 12

  private let context: RegulationContext

  init(context: RegulationContext) {
    self.context = context
  }

  func check(_ flight: Flight) -> Violation? {
    guard let aircraft = flight.aircraft, context.resolver.requiresTypeRating(aircraft),
      !flight.isDualReceived, !context.isMarked(.proficiencyCheck, on: flight)
    else { return nil }

    let window = TimeWindow.calendarMonths(Self.months)
    let recent = context.flights(
      within: window,
      of: flight,
      matching: context.anyAircraft(for: flight, credit: .proficiencyCheck)
    )
    let checks = recent.filter { context.isMarked(.proficiencyCheck, on: $0) }
    let confirmed = context.confirmedEventDates([.proficiencyCheck], within: window, of: flight)
    guard checks.isEmpty && confirmed.isEmpty else { return nil }

    return violation(
      on: flight,
      explanation: String(
        localized:
          "Flew an aircraft that requires a type rating with no proficiency check in the preceding 12 calendar months.",
        bundle: .module
      )
    )
  }
}
