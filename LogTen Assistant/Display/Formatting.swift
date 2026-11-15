import Foundation
import LogbookModel

/// Formats logbook values the way a logbook shows them.
nonisolated enum LogbookFormat {
  private static let hourFractionDigits = 1
  private static let distanceFractionDigits = 0...1

  /// The effective date of an FAA data cycle, which starts at 0000Z.
  static let cycleDate = Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: .gmt)

  /// A UTC day, such as an ADS-B archive's: “Nov 1, 2026”.
  static let utcDay = cycleDate

  /// A duration in decimal hours, such as “1.3 hr”.
  static func duration(minutes: UInt) -> String {
    Measurement(value: Double(minutes), unit: UnitDuration.minutes)
      .converted(to: .hours)
      .formatted(
        .measurement(
          width: .abbreviated,
          usage: .asProvided,
          numberFormatStyle: .number.precision(.fractionLength(hourFractionDigits))
        )
      )
  }

  /// A flight's date, reckoned in the pilot's time zone.
  static func date(_ date: Date, in timeZone: TimeZone) -> String {
    var style = Date.FormatStyle(date: .abbreviated, time: .omitted)
    style.timeZone = timeZone
    return date.formatted(style)
  }

  /// A UTC clock time with its date, such as “Nov 5, 14:32Z”.
  static func zuluTime(_ date: Date) -> String {
    var day = Date.FormatStyle().month(.abbreviated).day()
    day.timeZone = .gmt
    return String(localized: "\(date.formatted(day)), \(clockTime(date, in: .gmt))Z")
  }

  /// A 24-hour clock time in a time zone, such as “14:32”, as aviation always writes times.
  static func clockTime(_ date: Date, in timeZone: TimeZone) -> String {
    date.formatted(
      Date.VerbatimFormatStyle(
        format:
          "\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)",
        timeZone: timeZone,
        calendar: Calendar(identifier: .gregorian)
      )
    )
  }

  /// A time zone's short name at a moment, such as “PST”.
  static func zoneName(_ timeZone: TimeZone, at date: Date) -> String {
    var style = Date.FormatStyle().timeZone(.specificName(.short))
    style.timeZone = timeZone
    return date.formatted(style)
  }

  /// A distance in nautical miles.
  static func distance(_ distance: Measurement<UnitLength>) -> String {
    distance.formatted(
      .measurement(
        width: .abbreviated,
        usage: .asProvided,
        numberFormatStyle: .number.precision(.fractionLength(distanceFractionDigits))
      )
    )
  }

  /// A flight's route as “From → To”, or `nil` if neither end is recorded.
  static func route(of flight: Flight) -> String? {
    let ends = [flight.from, flight.to].map { $0?.preferredIdentifier }
    guard ends.contains(where: { $0 != nil }) else { return nil }
    return ends.map { $0 ?? "—" }.joined(separator: " → ")
  }

  /// A logbook field's value as text, or `nil` if it is unset. Unless `explicit`, zero and a false
  /// flag are unset too; an explicit zero reads as a zero and a false flag as “No”.
  static func value(
    _ value: FieldValue,
    as kind: CustomFieldValueKind,
    explicit: Bool = false
  ) -> String? {
    switch (value, kind) {
      case (.null, _): nil
      case (.integer(0), _), (.number(0), _): explicit ? shown(value, as: kind) : nil
      case (.boolean(false), _): explicit ? String(localized: "No") : nil
      default: shown(value, as: kind)
    }
  }

  private static func shown(_ value: FieldValue, as kind: CustomFieldValueKind) -> String? {
    switch (value, kind) {
      case (.null, _), (.boolean(false), _): nil
      case (_, .minutes): value.unsignedInteger.map(duration(minutes:))
      case (_, .count): value.unsignedInteger.map { $0.formatted(.number) }
      case (_, .flag): String(localized: "Yes")
      case (.text(let text), _): text.isEmpty ? nil : text
      case (.integer(let number), _): number.formatted(.number)
      case (.number(let number), _): number.formatted(.number.precision(.fractionLength(0...1)))
      case (.date(let date), _): zuluTime(date)
      case (.boolean(true), _): String(localized: "Yes")
    }
  }
}
