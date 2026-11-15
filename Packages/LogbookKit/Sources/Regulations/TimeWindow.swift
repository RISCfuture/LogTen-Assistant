package import Foundation

/// A lookback window for currency calculations.
///
/// Regulations measure recent experience in hours (14 CFR 61.195(a)), calendar days
/// (14 CFR 61.57(a)) or calendar months (14 CFR 61.56(c)). Days and months are reckoned in the
/// calendar passed to ``startDate(from:in:)``, which carries the pilot's time zone.
package enum TimeWindow: Hashable, Sendable {
  /// A number of consecutive hours.
  case hours(Int)

  /// A number of days back, beginning at midnight.
  case calendarDays(Int)

  /// A number of calendar months back, beginning on the first day of that month.
  case calendarMonths(Int)

  /**
   The earliest instant the window includes.

   For a 90-day window from March 15, the window begins at midnight on the day 90 days
   earlier. For a 6-month window from March 15, it begins on September 1.

   - Parameters:
     - referenceDate: The end of the window.
     - calendar: The calendar, in the pilot's time zone, that defines days and months.
   */
  package func startDate(from referenceDate: Date, in calendar: Calendar) -> Date {
    switch self {
      case .hours(let hours):
        return calendar.date(byAdding: .hour, value: -hours, to: referenceDate) ?? referenceDate
      case .calendarDays(let days):
        let shifted = calendar.date(byAdding: .day, value: -days, to: referenceDate)
        return calendar.startOfDay(for: shifted ?? referenceDate)
      case .calendarMonths(let months):
        let shifted = calendar.date(byAdding: .month, value: -months, to: referenceDate)
        let date = shifted ?? referenceDate
        return calendar.dateInterval(of: .month, for: date)?.start ?? date
    }
  }
}

extension Calendar {
  private static let monthsPerYear = 12

  /// A number identifying the calendar month of a date, increasing by one each month.
  package func monthOrdinal(of date: Date) -> Int {
    monthOrdinal(of: dateComponents([.year, .month], from: date)) ?? 0
  }

  /// The month ordinal of possibly partial date components, or `nil` without a year and month.
  package func monthOrdinal(of components: DateComponents) -> Int? {
    guard let year = components.year, let month = components.month else { return nil }
    return year * Self.monthsPerYear + month - 1
  }

  /// The first instant of the month with a given ordinal.
  package func startOfMonth(ordinal: Int) -> Date {
    var components = DateComponents()
    components.year = Int((Double(ordinal) / Double(Self.monthsPerYear)).rounded(.down))
    components.month = ordinal - (components.year ?? 0) * Self.monthsPerYear + 1
    components.day = 1
    return date(from: components) ?? .distantPast
  }
}
