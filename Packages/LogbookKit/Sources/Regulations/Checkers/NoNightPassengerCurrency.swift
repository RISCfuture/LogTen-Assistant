import Foundation
import LogbookModel

/// Night flights with passengers without three night takeoffs and three night full-stop landings
/// in the preceding 90 days (14 CFR 61.57(b)).
///
/// The experience must be in the same category, class and, for aircraft that require a type
/// rating, type; for a tailwheel airplane it must itself be in tailwheel airplanes.
///
/// ## Alternate currency
///
/// The pilot of a turbine-powered airplane certificated for more than one pilot may instead
/// count the preceding 6 calendar months if they have at least 1,500 hours and 15 hours in the
/// type in the preceding 90 days (14 CFR 61.57(e)(4)).
struct NoNightPassengerCurrency: ViolationChecker {
  static let rule = RegulationRule.noNightPassengerCurrency
  private static let days = 90
  private static let alternateMonths = 6
  private static let required: UInt = 3
  private static let alternateTotalMinutes: UInt = 1_500 * 60
  private static let alternateTypeMinutes: UInt = 15 * 60

  private let context: RegulationContext

  init(context: RegulationContext) {
    self.context = context
  }

  func check(_ flight: Flight) -> Violation? {
    if flight.isDualReceived || !flight.isPIC || !flight.hasPassengers || !flight.isNight {
      return nil
    }
    guard flight.aircraft != nil else { return nil }

    let recent = flights(in: .calendarDays(Self.days), of: flight)
    if hasNightCurrency(recent, for: flight) { return nil }
    if qualifiesForAlternateCurrency(flight),
      hasNightCurrency(flights(in: .calendarMonths(Self.alternateMonths), of: flight), for: flight)
    {
      return nil
    }

    let (takeoffs, landings) = (nightTakeoffs(in: recent), nightFullStops(in: recent))
    return violation(
      on: flight,
      contributing: recent.ids,
      explanation: String(
        localized:
          "Carried passengers at night with \(takeoffs, format: .number) night takeoffs and \(landings, format: .number) night full-stop landings in the preceding 90 days; 3 of each are required.",
        bundle: .module
      )
    )
  }

  private func flights(in window: TimeWindow, of flight: Flight) -> [Flight] {
    context.flights(
      within: window,
      of: flight,
      matching: context.sameClassAndType(for: flight, credit: .takeoffsAndLandings)
    )
  }

  private func hasNightCurrency(_ recent: [Flight], for flight: Flight) -> Bool {
    guard isCurrent(recent) else { return false }
    return !flight.isTailwheel || isCurrent(recent.filter(\.isTailwheel))
  }

  private func isCurrent(_ recent: [Flight]) -> Bool {
    nightTakeoffs(in: recent) >= Self.required && nightFullStops(in: recent) >= Self.required
  }

  private func nightTakeoffs(in flights: [Flight]) -> UInt {
    flights.reduce(0) { $0 + context.count(.nightTakeoffs, on: $1) }
  }

  private func nightFullStops(in flights: [Flight]) -> UInt {
    flights.reduce(0) { $0 + context.count(.nightFullStops, on: $1) }
  }

  private func qualifiesForAlternateCurrency(_ flight: Flight) -> Bool {
    guard let type = flight.aircraft?.type, type.isMultiPilot, type.engineType?.isTurbine == true
    else { return false }
    let priorMinutes = context.index.flights(before: flight).reduce(0) {
      $0 + $1.times.PIC + $1.times.SIC
    }
    guard priorMinutes >= Self.alternateTotalMinutes else { return false }
    let recent = context.flights(
      within: .calendarDays(Self.days),
      of: flight,
      matching: context.sameType(for: flight, credit: .takeoffsAndLandings)
    )
    let sameType = recent.filter {
      context.resolver.typeDesignator(of: $0) == context.resolver.typeDesignator(of: flight)
    }
    return sameType.reduce(0) { $0 + $1.times.PIC + $1.times.SIC } >= Self.alternateTypeMinutes
  }
}
