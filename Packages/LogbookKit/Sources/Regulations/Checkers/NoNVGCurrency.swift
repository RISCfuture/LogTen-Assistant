import Foundation
import LogbookModel

/// NVG flights as pilot in command without three NVG takeoffs and landings in the same category
/// within the preceding 4 calendar months, or an NVG proficiency check (14 CFR 61.57(f)).
struct NoNVGCurrency: ViolationChecker {
  static let rule = RegulationRule.noNVGCurrency
  private static let months = 4

  private let experience: NVGExperience

  init(context: RegulationContext) {
    experience = NVGExperience(context: context, months: Self.months)
  }

  func check(_ flight: Flight) -> Violation? {
    guard experience.isSubject(flight), let shortfall = experience.shortfall(before: flight)
    else { return nil }
    return violation(
      on: flight,
      contributing: shortfall.flightIDs,
      explanation: String(
        localized:
          "Used night-vision goggles with \(shortfall.takeoffs, format: .number) NVG takeoffs and \(shortfall.landings, format: .number) NVG landings in the preceding 4 calendar months and no NVG proficiency check; 3 of each, or a check, are required.",
        bundle: .module
      )
    )
  }
}
