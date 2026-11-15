import Foundation
import LogbookModel

/// How long instrument currency lasts, walked forward through a category's history.
///
/// A baseline (an instrument proficiency check or instrument rating) makes the pilot current
/// through the sixth calendar month after it (14 CFR 61.57(c) and (d)). Instrument experience
/// extends that: six approaches, a hold and intercepting and tracking within six calendar months
/// make the pilot current through the sixth month after the earliest of those tasks. Experience
/// can restore currency only while the lapse has lasted no more than six calendar months;
/// after that an instrument proficiency check is required, and experience in between doesn't
/// help.
struct IFRCurrencyTimeline: Sendable {
  private static let currencyMonths = 6
  private static let required: UInt = 6

  private let steps: [Step]
  private let stepIndexByFlightID: [RecordID: Int]

  /// Builds the timeline for one aircraft category.
  ///
  /// - Parameters:
  ///   - category: The category.
  ///   - context: The logbook.
  init(category: AircraftCategory, context: RegulationContext) {
    let items = Self.items(for: category, in: context)
    var steps = [Step]()
    var state = State()
    var history = [Experience]()
    for item in items {
      let before = state
      Self.apply(item, to: &state, history: &history, context: context)
      steps.append(
        Step(date: item.date, flightID: item.flight?.id, stateBefore: before, stateAfter: state)
      )
    }
    self.steps = steps
    stepIndexByFlightID = Dictionary(
      steps.enumerated().compactMap { index, step in step.flightID.map { ($0, index) } },
      uniquingKeysWith: { first, _ in first }
    )
  }

  private static func items(for category: AircraftCategory, in context: RegulationContext)
    -> [Item]
  {
    let resolver = context.resolver
    let flightItems = context.flights.compactMap { flight -> Item? in
      guard resolver.category(of: flight) == category else { return nil }
      let isBaseline =
        flight.isInstrumentProficiencyCheck
        && resolver.counts(flight, toward: .instrumentProficiencyCheck)
      let isExperience =
        isBaseline
        || (flight.hasInstrumentConditions
          && resolver.counts(flight, toward: .instrumentExperience))
      guard isBaseline || isExperience else { return nil }
      return Item(
        date: flight.date,
        flight: flight,
        isBaseline: isBaseline,
        isExperience: isExperience
      )
    }
    let eventDates = context.confirmedEvents(
      [.instrumentProficiencyCheck, .instrumentRating],
      category: category
    )
    let eventItems = eventDates.map {
      Item(date: $0, flight: nil, isBaseline: true, isExperience: false)
    }
    return (eventItems + flightItems).sorted {
      ($0.date, $0.flight == nil ? 0 : 1) < ($1.date, $1.flight == nil ? 0 : 1)
    }
  }

  private static func apply(
    _ item: Item,
    to state: inout State,
    history: inout [Experience],
    context: RegulationContext
  ) {
    let month = context.calendar.monthOrdinal(of: item.date)
    if item.isBaseline {
      state = State(currentThrough: month + currencyMonths, baselineFlightID: item.flight?.id)
      history = []
    }
    guard item.isExperience, let flight = item.flight, state.currentThrough != nil else { return }

    if let through = state.currentThrough, month - through > currencyMonths {
      state.isLapsed = true
    }
    history.append(
      Experience(
        month: month,
        approaches: flight.instrumentApproachCount,
        holds: flight.counts.holds,
        tracking: context.performedInterceptingAndTracking(on: flight)
      )
    )
    history.removeAll { $0.month < month - currencyMonths }
    guard !state.isLapsed else { return }
    extendCurrency(&state, history: history, fromMonth: month)
  }

  /// Extends currency through the latest month for which the recent experience suffices.
  private static func extendCurrency(
    _ state: inout State,
    history: [Experience],
    fromMonth month: Int
  ) {
    for probe in month...(month + currencyMonths) {
      let window = history.filter { $0.month >= probe - currencyMonths }
      if isSufficient(window), probe > (state.currentThrough ?? probe - 1) {
        state.currentThrough = probe
      }
    }
  }

  private static func isSufficient(_ experience: [Experience]) -> Bool {
    experience.reduce(0) { $0 + $1.approaches } >= required
      && experience.contains { $0.holds > 0 } && experience.contains(where: \.tracking)
  }

  /// The pilot's standing when a flight began, not counting the flight itself.
  func state(before flight: Flight) -> State {
    if let index = stepIndexByFlightID[flight.id] { return steps[index].stateBefore }
    return steps.last { $0.date <= flight.date }?.stateAfter ?? State()
  }

  /// Whether the pilot is current in a month.
  func isCurrent(_ state: State, inMonth month: Int) -> Bool {
    guard !state.isLapsed, let through = state.currentThrough else { return false }
    return month <= through
  }

  /// Whether a lapse of the state's currency, as of a month, has outlasted the grace period in
  /// which experience can restore it.
  func isBeyondRestoration(_ state: State, inMonth month: Int) -> Bool {
    guard let through = state.currentThrough else { return false }
    return state.isLapsed || month - through > Self.currencyMonths
  }
}

extension IFRCurrencyTimeline {
  /// Where a pilot stands on instrument currency.
  struct State: Hashable, Sendable {
    /// The last calendar month, as a month ordinal, in which the pilot is current.
    var currentThrough: Int?

    /// Whether a lapse has run past the point where experience can restore currency.
    var isLapsed = false

    /// The most recent baseline flight, if the baseline is a flight.
    var baselineFlightID: RecordID?
  }

  private struct Step {
    let date: Date
    let flightID: RecordID?
    let stateBefore: State
    let stateAfter: State
  }

  private struct Experience {
    let month: Int
    let approaches: UInt
    let holds: UInt
    let tracking: Bool
  }

  private struct Item {
    let date: Date
    let flight: Flight?
    let isBaseline: Bool
    let isExperience: Bool
  }
}
