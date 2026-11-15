import Foundation
import LogbookModel

/// IFR flights as pilot in command without instrument currency (14 CFR 61.57(c) and (d)).
///
/// Currency starts from an instrument proficiency check or instrument rating and lasts through
/// the sixth calendar month after it. Six approaches, holding and intercepting and tracking
/// within six calendar months extend it, but only while a lapse hasn't run past six calendar
/// months. Only experience in instrument conditions or a simulator counts. Flights that are
/// themselves an instrument proficiency check, flights with a safety pilot and flights in a
/// category the pilot holds no instrument rating for are exempt.
struct NoIFRCurrency: ViolationChecker {
  static let rule = RegulationRule.noIFRCurrency
  private static let months = 6

  private let context: RegulationContext
  private let timelines: [AircraftCategory: IFRCurrencyTimeline]

  init(context: RegulationContext) {
    self.context = context
    let categories = Set(context.flights.compactMap(context.resolver.category(of:)))
    timelines = Dictionary(
      uniqueKeysWithValues: categories.map {
        ($0, IFRCurrencyTimeline(category: $0, context: context))
      }
    )
  }

  func check(_ flight: Flight) -> Violation? {
    if flight.isDualReceived || !flight.isPIC || !flight.isIFR { return nil }
    if flight.isInstrumentProficiencyCheck || context.person(.safetyPilot, on: flight) != nil {
      return nil
    }
    guard let category = context.resolver.category(of: flight),
      let timeline = timelines[category], holdsInstrumentRating(for: category)
    else { return nil }

    let state = timeline.state(before: flight)
    let month = context.calendar.monthOrdinal(of: flight.date)
    guard !timeline.isCurrent(state, inMonth: month) else { return nil }

    return violation(
      on: flight,
      contributing: contributingFlightIDs(for: flight, state: state),
      explanation: explanation(
        state: state,
        isBeyondRestoration: timeline.isBeyondRestoration(state, inMonth: month)
      )
    )
  }

  private func holdsInstrumentRating(for category: AircraftCategory) -> Bool {
    let rating: InstrumentRating? =
      switch category {
        case .airplane: .airplane
        case .rotorcraft: .helicopter
        case .poweredLift: .poweredLift
        default: nil
      }
    return rating.map(context.pilot.instrumentRatings.contains) ?? false
  }

  private func contributingFlightIDs(
    for flight: Flight,
    state: IFRCurrencyTimeline.State
  ) -> [RecordID] {
    let recent = context.flights(
      within: .calendarMonths(Self.months),
      of: flight,
      matching: context.sameCategory(for: flight, credit: .instrumentExperience)
    )
    let experience = recent.filter { $0.hasInstrumentConditions || $0.isInstrumentProficiencyCheck }
    return (state.baselineFlightID.map { [$0] } ?? [])
      + experience.ids.filter { $0 != state.baselineFlightID }
  }

  private func explanation(state: IFRCurrencyTimeline.State, isBeyondRestoration: Bool) -> String {
    if state.currentThrough == nil {
      return String(
        localized:
          "Acted as pilot in command under IFR with no instrument proficiency check or instrument rating on record before this flight.",
        bundle: .module
      )
    }
    if isBeyondRestoration {
      return String(
        localized:
          "Acted as pilot in command under IFR after instrument currency lapsed more than 6 calendar months earlier; an instrument proficiency check is required.",
        bundle: .module
      )
    }
    return String(
      localized:
        "Acted as pilot in command under IFR without 6 approaches, holding and intercepting and tracking in the preceding 6 calendar months, or an instrument proficiency check.",
      bundle: .module
    )
  }
}
