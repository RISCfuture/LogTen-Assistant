import Foundation
import LogbookModel

/// Second-in-command flights in a type-rated aircraft without three takeoffs and landings in the
/// type in the preceding 90 days (14 CFR 61.55(b)).
///
/// The rule is not applied to flights with passengers aboard.
struct NoSICCurrency: ViolationChecker {
  static let rule = RegulationRule.noSICCurrency
  private static let days = 90
  private static let required: UInt = 3

  private let context: RegulationContext

  init(context: RegulationContext) {
    self.context = context
  }

  func check(_ flight: Flight) -> Violation? {
    guard let aircraft = flight.aircraft, flight.isSIC, !flight.hasPassengers,
      context.resolver.requiresTypeRating(aircraft)
    else { return nil }

    let recent = context.flights(
      within: .calendarDays(Self.days),
      of: flight,
      matching: context.sameClassAndType(for: flight, credit: .takeoffsAndLandings)
    )
    let (takeoffs, landings) = (recent.total(\.takeoffs), recent.total(\.landings))
    guard takeoffs < Self.required || landings < Self.required else { return nil }

    return violation(
      on: flight,
      contributing: recent.ids,
      explanation: String(
        localized:
          "Served as second in command of an aircraft that requires a type rating with \(takeoffs, format: .number) takeoffs and \(landings, format: .number) landings in this type in the preceding 90 days; 3 of each are required.",
        bundle: .module
      )
    )
  }
}
