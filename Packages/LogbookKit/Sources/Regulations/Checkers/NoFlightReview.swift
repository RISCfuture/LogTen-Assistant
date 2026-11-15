import Foundation
import LogbookModel

/// Flights as pilot in command without a flight review in the preceding 24 calendar months
/// (14 CFR 61.56(c)).
///
/// A passed practical test also satisfies the requirement, as does a flight review the user
/// confirmed in the logbook settings. Dual received, student solo flights, the review itself and
/// checkrides are exempt, and so are flights before the first checkride in the logbook, when the
/// pilot held no certificate the requirement could apply to (such as a failed first attempt at
/// the practical test).
struct NoFlightReview: ViolationChecker {
  static let rule = RegulationRule.noFlightReview
  private static let months = 24

  private let context: RegulationContext
  private let firstCheckrideDate: Date?

  init(context: RegulationContext) {
    self.context = context
    firstCheckrideDate = context.flights.first { context.isMarked(.checkride, on: $0) }?.date
  }

  func check(_ flight: Flight) -> Violation? {
    guard isSubject(flight) else { return nil }
    let window = TimeWindow.calendarMonths(Self.months)
    let recent = context.flights(
      within: window,
      of: flight,
      matching: context.anyAircraft(for: flight, credit: .flightReview)
    )
    let qualifying = recent.filter(qualifies)
    let confirmed = context.confirmedEventDates(
      [.flightReview],
      within: window,
      of: flight
    )
    guard qualifying.isEmpty && confirmed.isEmpty else { return nil }
    return violation(
      on: flight,
      explanation: String(
        localized:
          "Acted as pilot in command with no flight review or practical test in the preceding 24 calendar months.",
        bundle: .module
      )
    )
  }

  private func isSubject(_ flight: Flight) -> Bool {
    if flight.isDualReceived || !flight.isPIC || flight.isStudentSolo { return false }
    return !qualifies(flight) && !precedesFirstCheckride(flight)
  }

  private func precedesFirstCheckride(_ flight: Flight) -> Bool {
    firstCheckrideDate.map { flight.date < $0 } ?? false
  }

  private func qualifies(_ flight: Flight) -> Bool {
    flight.isFlightReview || context.isMarked(.checkride, on: flight)
  }
}
