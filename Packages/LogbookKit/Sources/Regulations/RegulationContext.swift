package import Foundation
public import LogbookModel

/// Everything a checker needs: the logbook's flights, the pilot and the field mapping.
package struct RegulationContext: Sendable {
  /// The logbook's settings.
  package let settings: LogbookSettings

  /// The flights, sorted for date queries.
  package let index: FlightIndex

  /// Resolves what each flight counts as.
  package let resolver: AircraftResolver

  package var pilot: PilotProfile { settings.pilot }
  package var mapping: FieldMapping { settings.fieldMapping }
  package var calendar: Calendar { index.calendar }
  package var flights: [Flight] { index.flights }

  /// Creates a context.
  ///
  /// - Parameters:
  ///   - settings: The logbook's settings.
  ///   - flights: The logbook's flights.
  package init(settings: LogbookSettings, flights: [Flight]) {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = settings.pilot.homeTimeZone
    self.settings = settings
    index = FlightIndex(flights: flights, calendar: calendar)
    resolver = AircraftResolver(settings: settings)
  }

  /// Matching criteria that accept any flight credited for the experience.
  package func anyAircraft(for flight: Flight, credit: SimulatorCredit) -> FlightMatchCriteria {
    .none(for: flight, resolver: resolver, credit: credit)
  }

  /// Matching criteria that require the flight's category.
  package func sameCategory(for flight: Flight, credit: SimulatorCredit) -> FlightMatchCriteria {
    .category(for: flight, resolver: resolver, credit: credit)
  }

  /// Matching criteria that require the flight's category, class and, if rated, type.
  package func sameClassAndType(
    for flight: Flight,
    credit: SimulatorCredit
  ) -> FlightMatchCriteria {
    .full(for: flight, resolver: resolver, credit: credit)
  }

  /// Matching criteria that require the flight's type, if it requires a type rating.
  package func sameType(for flight: Flight, credit: SimulatorCredit) -> FlightMatchCriteria {
    .type(for: flight, resolver: resolver, credit: credit)
  }

  /// The earlier flights in a window that match criteria.
  package func flights(
    within window: TimeWindow,
    of flight: Flight,
    matching criteria: FlightMatchCriteria
  ) -> [Flight] {
    index.flights(within: window, of: flight, matching: criteria)
  }

  /// The dates of the user-confirmed events of a kind that fall in a window ending at a flight.
  ///
  /// An event that gives only a year and month is dated the first of that month, so it counts
  /// in every window that includes the month.
  package func confirmedEventDates(
    _ kinds: Set<ConfirmedCurrencyEvent.Kind>,
    category: AircraftCategory? = nil,
    within window: TimeWindow,
    of flight: Flight
  ) -> [Date] {
    let start = window.startDate(from: flight.date, in: calendar)
    return confirmedEvents(kinds, category: category).filter { start <= $0 && $0 <= flight.date }
  }

  /// The dates of the user-confirmed events of a kind, for a category or for any category.
  package func confirmedEvents(
    _ kinds: Set<ConfirmedCurrencyEvent.Kind>,
    category: AircraftCategory? = nil
  ) -> [Date] {
    settings.rules.confirmedCurrencyEvents.compactMap { event in
      guard kinds.contains(event.kind) else { return nil }
      if let category, let eventCategory = event.category, eventCategory != category { return nil }
      var components = event.date
      components.day = components.day ?? 1
      components.calendar = calendar
      components.timeZone = calendar.timeZone
      return calendar.date(from: components)
    }
  }

  /// Whether the flight has the field of a role marked, `false` if the role is unmapped.
  package func isMarked(_ role: FieldRole, on flight: Flight) -> Bool {
    flight.isMarked(role, in: mapping) ?? false
  }

  /// Whether the flight included intercepting and tracking courses: the mapped field when there
  /// is one, otherwise whether any instrument approach was flown.
  package func performedInterceptingAndTracking(on flight: Flight) -> Bool {
    guard mapping[.interceptingAndTracking] != nil else {
      return flight.instrumentApproachCount > 0
    }
    return isMarked(.interceptingAndTracking, on: flight)
  }

  /// The person in the crew role of a field role, `nil` if there is none or the role is unmapped.
  package func person(_ role: FieldRole, on flight: Flight) -> Person? {
    flight.person(for: role, in: mapping)
  }

  /// The count in the field of a role, zero if unmapped.
  package func count(_ role: FieldRole, on flight: Flight) -> UInt {
    flight.count(for: role, in: mapping) ?? 0
  }
}

extension Sequence<Flight> {
  /// The record identifiers of the flights.
  package var ids: [RecordID] { map(\.id) }

  /// The sum of a count or duration across the flights.
  package func total(_ value: KeyPath<Flight, UInt>) -> UInt {
    reduce(0) { $0 + $1[keyPath: value] }
  }
}

extension Flight {
  /// Whether pilot-in-command time was logged.
  package var isPIC: Bool { times.PIC > 0 }

  /// Whether second-in-command time was logged.
  package var isSIC: Bool { times.SIC > 0 }

  /// Whether dual instruction was received, so the instructor was pilot in command.
  package var isDualReceived: Bool { times.dualReceived > 0 }

  /// Whether dual instruction was given.
  package var isDualGiven: Bool { times.dualGiven > 0 }

  /// Whether solo time was logged, as for a student pilot.
  package var isStudentSolo: Bool { times.solo > 0 }

  /// Whether night time was logged.
  package var isNight: Bool { times.night > 0 }

  /// Whether actual instrument time was logged.
  package var isIFR: Bool { times.actualInstrument > 0 }

  /// Whether the flight had passengers.
  package var hasPassengers: Bool { !passengers.isEmpty }

  /// Whether the flight was in instrument conditions, actual or simulated, or in a simulator.
  package var hasInstrumentConditions: Bool {
    times.actualInstrument > 0 || times.simulatedInstrument > 0 || times.simulator > 0
  }

  /// The number of instrument approaches flown. Visual and contact approaches don't count.
  package var instrumentApproachCount: UInt {
    approaches.filter { $0.type?.isInstrumentApproach != false }.reduce(0) { $0 + $1.count }
  }

  /// The takeoffs, day and night.
  package var takeoffs: UInt { counts.takeoffs }

  /// The landings, day and night.
  package var landings: UInt { counts.landings }

  /// The moment the flight started: block-out or takeoff time if logged, otherwise its date.
  package var startInstant: Date { events.out ?? events.off ?? date }

  /// Whether the aircraft is a tailwheel airplane.
  package var isTailwheel: Bool { aircraft?.isTailwheel == true }
}
