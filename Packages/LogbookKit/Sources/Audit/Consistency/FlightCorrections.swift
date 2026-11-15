import Foundation
import LogbookModel

extension AuditedFlight {
  /// The field key of a flight attribute, by its attribute name such as `picNight`.
  static func fieldKey(_ attribute: String) -> LogTenFieldKey {
    LogTenFieldKey(.flight, attribute)
  }

  /// A change that sets a flight field, recording the value it holds now.
  func change(_ key: LogTenFieldKey, to new: FieldValue) -> FieldChange {
    FieldChange(
      flightKey: flight.flightKey,
      recordID: id,
      field: key,
      old: flight[field: key],
      new: new
    )
  }

  /// Changes that set each of the named minute fields to zero, leaving out those that are
  /// already zero or unset.
  func clearing(_ attributes: [String]) -> [FieldChange] {
    attributes.map(Self.fieldKey)
      .filter { key in
        let value = flight[field: key]
        return !value.isNull && value != .integer(0)
      }
      .map { change($0, to: .integer(0)) }
  }
}

/// A change to total time with the changes LogTen would otherwise make on its own.
struct TotalTimeChange {
  /// The change to total time, followed by one limiting each time that exceeds it.
  let changes: [FieldChange]

  /// The titles of the times the changes limit to the new total.
  let limitedTitles: [String]
}

extension AuditedFlight {
  private static let totalTimeSubsets: [LogTenFieldKey] = [
    .flightPIC, .flightSIC, .flightP1US, .flightSolo, .flightDualGiven, .flightDualReceived,
    .flightNight, .flightCrossCountry, .flightActualInstrument, .flightSimulatedInstrument
  ]

  /// Sets total time and limits every time that is part of total time to the new total.
  ///
  /// LogTen silently clamps those times when total time falls below them, so the changes spell
  /// the clamping out for the reviewer to approve.
  func settingTotalTime(to minutes: Int) -> TotalTimeChange {
    let limited = Self.totalTimeSubsets.filter { (flight[field: $0].number ?? 0) > Double(minutes) }
    return TotalTimeChange(
      changes: [change(.flightTotalTime, to: .integer(minutes))]
        + limited.map { change($0, to: .integer(minutes)) },
      limitedTitles: limited.map {
        FieldTitle.title(ofAttribute: $0.attributeName.lowercased()) ?? String($0.attributeName)
      }
    )
  }
}

/// Formats flight times for the messages of the consistency checks.
enum FlightTimeText {
  private static let minutesPerHour = 60.0
  private static let minutesPerTenthOfAnHour: UInt = 6

  /// Minutes as decimal hours with one decimal place, such as `1.7`.
  static func hours(_ minutes: UInt) -> String {
    hours(Double(minutes))
  }

  /// Fractional minutes as decimal hours.
  static func hours(_ minutes: Double) -> String {
    (minutes / minutesPerHour).formatted(.number.precision(.fractionLength(1)))
  }

  /// Minutes as a spelled-out length of time in a single unit: decimal hours such as “2.4
  /// hours”, or whole minutes for under a tenth of an hour, where decimal hours would round away.
  static func span(_ minutes: UInt) -> String {
    guard minutes >= minutesPerTenthOfAnHour else {
      return Measurement(value: Double(minutes), unit: UnitDuration.minutes).formatted(
        .measurement(width: .wide, numberFormatStyle: .number.precision(.fractionLength(0)))
      )
    }
    return Measurement(value: Double(minutes) / minutesPerHour, unit: UnitDuration.hours).formatted(
      .measurement(width: .wide, numberFormatStyle: .number.precision(.fractionLength(1)))
    )
  }

  /// Names joined as a localized list, such as “PIC, SIC, and P1 u/s”.
  static func list(_ items: [String]) -> String {
    items.formatted(.list(type: .and, width: .standard))
  }
}
