import Foundation
import LogbookModel
import Testing

@testable import Regulations

@Suite
struct `Time windows` {
  private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
  }()

  @Test
  func `starts a day window at midnight`() {
    let start = TimeWindow.calendarDays(90).startDate(from: day(2025, 6, 15), in: utc)
    #expect(start == day(2025, 3, 17, hour: 0))
  }

  @Test
  func `starts a month window on the first of the month`() {
    let start = TimeWindow.calendarMonths(24).startDate(from: day(2025, 3, 15), in: utc)
    #expect(start == day(2023, 3, 1, hour: 0))
  }

  @Test
  func `starts an hour window exactly that many hours back`() {
    let start = TimeWindow.hours(24).startDate(from: day(2025, 3, 15), in: utc)
    #expect(start == day(2025, 3, 14))
  }

  @Test
  func `reckons days in the pilot’s time zone`() {
    var pacific = utc
    pacific.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    let reference = day(2025, 6, 15, hour: 3)

    let start = TimeWindow.calendarDays(90).startDate(from: reference, in: pacific)

    #expect(start == day(2025, 3, 16, hour: 7))
    #expect(start != TimeWindow.calendarDays(90).startDate(from: reference, in: utc))
  }

  @Test
  func `reckons months in the pilot’s time zone`() {
    var pacific = utc
    pacific.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    let reference = day(2025, 7, 1, hour: 3)

    let start = TimeWindow.calendarMonths(1).startDate(from: reference, in: pacific)

    #expect(start == day(2025, 5, 1, hour: 7))
  }

  @Test
  func `numbers months consecutively across years`() {
    #expect(utc.monthOrdinal(of: day(2025, 1, 5)) - utc.monthOrdinal(of: day(2024, 12, 5)) == 1)
    #expect(
      utc.startOfMonth(ordinal: utc.monthOrdinal(of: day(2024, 12, 5))) == day(2024, 12, 1, hour: 0)
    )
  }
}

@Suite
struct `Flight index` {
  private let calendar = Calendar(identifier: .gregorian)

  private func index() -> FlightIndex {
    FlightIndex(
      flights: [
        .fixture("c", day(2025, 3, 3)), .fixture("a", day(2025, 3, 1)),
        .fixture("b", day(2025, 3, 2)), .fixture("b2", day(2025, 3, 2))
      ],
      calendar: calendar
    )
  }

  @Test
  func `sorts flights by date and then identifier`() {
    #expect(index().flights.map(\.id.rawValue) == ["a", "b", "b2", "c"])
  }

  @Test
  func `finds inclusive bounds`() {
    let index = index()
    #expect(index.lowerBound(for: day(2025, 3, 2)) == 1)
    #expect(index.upperBound(for: day(2025, 3, 2)) == 3)
    #expect(index.lowerBound(for: day(2025, 4, 1)) == 4)
  }

  @Test
  func `returns same-day flights but not the reference flight`() {
    let index = index()
    let reference = index.flights[1]
    let resolver = AircraftResolver(settings: LogbookSettings())
    let found = index.flights(
      within: .calendarDays(1),
      of: reference,
      matching: .none(for: reference, resolver: resolver, credit: .takeoffsAndLandings)
    )
    #expect(found.map(\.id.rawValue) == ["a", "b2"])
  }
}

@Suite
struct `Flight match criteria` {
  private let resolver = AircraftResolver(settings: Scenario.defaultSettings())

  private func flight(in aircraft: Aircraft) -> Flight {
    .fixture("flight", day(2025, 3, 1), in: aircraft)
  }

  private func matches(
    _ criteria: (Flight, AircraftResolver, SimulatorCredit) -> FlightMatchCriteria,
    reference: Aircraft,
    candidate: Aircraft,
    resolver: AircraftResolver? = nil
  ) -> Bool {
    criteria(flight(in: reference), resolver ?? self.resolver, .takeoffsAndLandings)
      .matches(flight(in: candidate))
  }

  @Test
  func `requires the same category and class for full matching`() {
    #expect(matches(FlightMatchCriteria.full, reference: .cessna, candidate: .tailwheel))
    #expect(!matches(FlightMatchCriteria.full, reference: .cessna, candidate: .twin))
    #expect(!matches(FlightMatchCriteria.full, reference: .cessna, candidate: .helicopter))
  }

  @Test
  func `requires only the category for category matching`() {
    #expect(matches(FlightMatchCriteria.category, reference: .cessna, candidate: .twin))
    #expect(!matches(FlightMatchCriteria.category, reference: .cessna, candidate: .helicopter))
  }

  @Test
  func `requires the same type only when the reference aircraft needs a type rating`() {
    let otherJet = Aircraft.fixture(
      "N51",
      type: .fixture("SF51", engine: .turbofan),
      weightLbs: 6_000
    )

    #expect(matches(FlightMatchCriteria.type, reference: .cessna, candidate: .jet))
    #expect(matches(FlightMatchCriteria.type, reference: .jet, candidate: .jet))
    #expect(!matches(FlightMatchCriteria.type, reference: .jet, candidate: otherJet))
  }

  @Test
  func `matches types by configured type rating rather than type code`() {
    let otherJet = Aircraft.fixture(
      "N51",
      type: .fixture("SF51", engine: .turbofan),
      weightLbs: 6_000
    )
    var settings = Scenario.defaultSettings()
    settings.aircraft[Aircraft.jet.registration] = AircraftSettings(typeRating: "SF50")
    settings.aircraft[otherJet.registration] = AircraftSettings(typeRating: "SF50")

    #expect(
      matches(
        FlightMatchCriteria.type,
        reference: .jet,
        candidate: otherJet,
        resolver: AircraftResolver(settings: settings)
      )
    )
  }
}

@Suite
struct `Regulation context` {
  private func context(_ events: [ConfirmedCurrencyEvent]) -> RegulationContext {
    var settings = Scenario.defaultSettings()
    settings.rules.confirmedCurrencyEvents = events
    return RegulationContext(settings: settings, flights: [])
  }

  @Test
  func `dates a month-only event the first of the month and filters by category`() {
    let context = context([
      ConfirmedCurrencyEvent(date: DateComponents(year: 2025, month: 3), kind: .instrumentRating),
      ConfirmedCurrencyEvent(
        date: DateComponents(year: 2025, month: 4, day: 9),
        kind: .instrumentRating,
        category: .rotorcraft
      ),
      ConfirmedCurrencyEvent(
        date: DateComponents(year: 2025, month: 5),
        kind: .instrumentProficiencyCheck
      )
    ])

    #expect(
      context.confirmedEvents([.instrumentRating])
        == [day(2025, 3, 1, hour: 0), day(2025, 4, 9, hour: 0)]
    )
    #expect(
      context.confirmedEvents([.instrumentRating], category: .airplane)
        == [day(2025, 3, 1, hour: 0)]
    )
  }

  @Test
  func `limits events to the window ending at a flight`() {
    let context = context([
      ConfirmedCurrencyEvent(date: DateComponents(year: 2024, month: 11), kind: .instrumentRating),
      ConfirmedCurrencyEvent(date: DateComponents(year: 2025, month: 1), kind: .instrumentRating),
      ConfirmedCurrencyEvent(date: DateComponents(year: 2025, month: 3), kind: .instrumentRating),
      ConfirmedCurrencyEvent(date: DateComponents(year: 2025, month: 6), kind: .instrumentRating)
    ])
    let flight = Flight.fixture("a", day(2025, 3, 15))

    let dates = context.confirmedEventDates(
      [.instrumentRating],
      within: .calendarDays(90),
      of: flight
    )

    #expect(dates == [day(2025, 1, 1, hour: 0), day(2025, 3, 1, hour: 0)])
  }

  @Test
  func `counts only instrument approaches`() {
    let flight = Flight.fixture("a", day(2025, 3, 1)) {
      $0.approaches = [
        Approach(id: RecordID(rawValue: "ils"), type: .ILS, count: 2),
        Approach(id: RecordID(rawValue: "visual"), type: .visual, count: 3),
        Approach(id: RecordID(rawValue: "contact"), type: .contact),
        Approach(id: RecordID(rawValue: "untyped"))
      ]
    }

    #expect(flight.instrumentApproachCount == 3)
  }
}
