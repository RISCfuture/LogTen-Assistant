import Foundation
import LogbookModel

/// NVG flights with passengers without three NVG takeoffs and landings in the same category
/// within the preceding 2 calendar months, or an NVG proficiency check (14 CFR 61.57(f)).
struct NoNVGPassengerCurrency: ViolationChecker {
  static let rule = RegulationRule.noNVGPassengerCurrency
  private static let months = 2

  private let experience: NVGExperience

  init(context: RegulationContext) {
    experience = NVGExperience(context: context, months: Self.months)
  }

  func check(_ flight: Flight) -> Violation? {
    guard flight.hasPassengers, experience.isSubject(flight),
      let shortfall = experience.shortfall(before: flight)
    else { return nil }
    return violation(
      on: flight,
      contributing: shortfall.flightIDs,
      explanation: String(
        localized:
          "Carried passengers using night-vision goggles with \(shortfall.takeoffs, format: .number) NVG takeoffs and \(shortfall.landings, format: .number) NVG landings in the preceding 2 calendar months and no NVG proficiency check; 3 of each, or a check, are required.",
        bundle: .module
      )
    )
  }
}
