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
