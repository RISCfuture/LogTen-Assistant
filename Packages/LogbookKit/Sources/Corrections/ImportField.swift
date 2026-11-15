import Foundation
public import LogbookModel

/**
 The flight fields corrections may change through LogTen's import, and how each is written in
 an import package.

 The allowlist is the set of fields verified to import correctly through LogTen's import, both
 when it creates a flight and when it modifies one. Everything else, including crew, approaches
 and signatures, is left to LogTen.
 */
public enum ImportField {
  private static let minutesPerHour = 60

  private static let encodings: [LogTenFieldKey: Encoding] = {
    var encodings: [LogTenFieldKey: Encoding] = [
      .flightTakeoffTime: .timestamp,
      .flightLandingTime: .timestamp,
      .flightActualDepartureTime: .timestamp,
      .flightActualArrivalTime: .timestamp,
      .flightDate: .date,
      .flightTotalTime: .minutes,
      .flightNight: .minutes,
      .flightPIC: .minutes,
      .flightSIC: .minutes,
      .flightSolo: .minutes,
      .flightP1US: .minutes,
      .flightDualGiven: .minutes,
      .flightDualReceived: .minutes,
      .flightCrossCountry: .minutes,
      .flightActualInstrument: .minutes,
      .flightSimulatedInstrument: .minutes,
      .flightPICNight: .minutes,
      .flightSICNight: .minutes,
      .flightP1USNight: .minutes,
      .flightDualReceivedNight: .minutes,
      .flightCrossCountryNight: .minutes,
      .flightHobbsStart: .number,
      .flightHobbsStop: .number,
      .flightTachStart: .number,
      .flightTachStop: .number,
      .flightDayTakeoffs: .count,
      .flightNightTakeoffs: .count,
      .flightDayLandings: .count,
      .flightNightLandings: .count,
      .flightFullStops: .count,
      .flightDistance: .number,
      .flightRemarks: .text,
      .flightFrom: .text,
      .flightTo: .text
    ]
    for slot in CustomFieldKind.flightTime.slots {
      encodings[.custom(.flightTime, slot)] = .minutes
    }
    return encodings
  }()

  /// Every field corrections may change.
  public static var allowlist: Set<LogTenFieldKey> { Set(encodings.keys) }

  /// Whether LogTen stores zero when an import clears the field: minute and count fields.
  static func clearsToZero(_ field: LogTenFieldKey) -> Bool {
    switch encodings[field] {
      case .minutes, .count: true
      default: false
    }
  }

  /// Whether corrections may change a field.
  public static func isImportable(_ field: LogTenFieldKey) -> Bool { encodings[field] != nil }

  /**
   The value as an import package writes it.

   Times of day are seconds since 1970 as floating-point numbers and the flight date is whole
   seconds since 1970, because the import reads Unix time while LogTen stores dates relative to
   2001. Durations are `H:MM` text, counts are integers, and `FieldValue.null` clears the
   field.

   - Returns: The JSON value, or `nil` if the field isn't importable or the value doesn't suit
     it.
   */
  public static func packageValue(_ value: FieldValue, for field: LogTenFieldKey) -> JSONValue? {
    guard let encoding = encodings[field] else { return nil }
    if value.isNull { return .null }
    switch (encoding, value) {
      case (.timestamp, .date(let date)):
        return .double(date.timeIntervalSince1970)
      case (.date, .date(let date)):
        let seconds = date.timeIntervalSince1970
        return seconds == seconds.rounded() ? .integer(Int(seconds)) : .double(seconds)
      case (.minutes, .integer(let minutes)) where minutes >= 0:
        let hours = minutes / minutesPerHour
        let rest = minutes % minutesPerHour
        return .string("\(hours):\(rest < 10 ? "0" : "")\(rest)")
      case (.count, .integer(let count)) where count >= 0:
        return .integer(count)
      case (.number, .integer(let number)):
        return .integer(number)
      case (.number, .number(let number)):
        return number == number.rounded() && abs(number) < Double(Int.max)
          ? .integer(Int(number)) : .double(number)
      case (.text, .text(let text)):
        return .string(text)
      default:
        return nil
    }
  }

  private enum Encoding {
    case timestamp, date, minutes, count, number, text
  }
}

extension CorrectionOption {
  /// Whether every change of the option can be made through LogTen's import. An option that
  /// can't ends on the manual checklist when approved.
  public var isImportable: Bool { changes.allSatisfy { ImportField.isImportable($0.field) } }
}
