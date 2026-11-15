import Foundation
import LogbookModel

/// Flights with passengers without three takeoffs and landings in the preceding 90 days
/// (14 CFR 61.57(a)).
///
/// The experience must be in the same category and class and, for aircraft that require a type
/// rating, the same type. Landings in a tailwheel airplane must be to a full stop, and the
/// experience must itself be in a tailwheel airplane.
struct NoPassengerCurrency: ViolationChecker {
  static let rule = RegulationRule.noPassengerCurrency
  private static let days = 90
  private static let required: UInt = 3

  private let context: RegulationContext

  init(context: RegulationContext) {
    self.context = context
  }

  func check(_ flight: Flight) -> Violation? {
    if flight.isDualReceived || !flight.isPIC || !flight.hasPassengers { return nil }
    guard flight.aircraft != nil else { return nil }

    let recent = context.flights(
      within: .calendarDays(Self.days),
      of: flight,
      matching: context.sameClassAndType(for: flight, credit: .takeoffsAndLandings)
    )
    let (takeoffs, landings) = (recent.total(\.takeoffs), recent.total(\.landings))
    if takeoffs < Self.required || landings < Self.required {
      return violation(
        on: flight,
        contributing: recent.ids,
        explanation: String(
          localized:
            "Carried passengers with \(takeoffs, format: .number) takeoffs and \(landings, format: .number) landings in the preceding 90 days in this category, class and type; 3 of each are required.",
          bundle: .module
        )
      )
    }
    return tailwheelViolation(on: flight, among: recent)
  }

  private func tailwheelViolation(on flight: Flight, among recent: [Flight]) -> Violation? {
    guard flight.isTailwheel else { return nil }
    let tailwheel = recent.filter(\.isTailwheel)
    let (takeoffs, fullStops) = (tailwheel.total(\.takeoffs), tailwheel.total(\.counts.fullStops))
    guard takeoffs < Self.required || fullStops < Self.required else { return nil }
    return violation(
      on: flight,
      contributing: tailwheel.ids,
      explanation: String(
        localized:
          "Carried passengers in a tailwheel airplane with \(takeoffs, format: .number) takeoffs and \(fullStops, format: .number) full-stop landings in tailwheel airplanes in the preceding 90 days; 3 of each are required.",
        bundle: .module
      )
    )
  }
}
