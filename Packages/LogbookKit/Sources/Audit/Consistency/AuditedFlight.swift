import Foundation
import LogbookModel

/// A flight as the consistency rules see it: every stored attribute by its lowercased name,
/// the same names cleanup-logten's evidence uses, plus the derived facts several rules share.
struct AuditedFlight {
  /// The typed ``Flight`` fields, which ``Flight/customValues`` and ``Flight/otherValues``
  /// don't hold.
  private static let typedKeys: [LogTenFieldKey] = [
    .flightKey, .flightIsLocked, .flightDate, .flightRoute, .flightDistance, .flightNumber,
    .flightRemarks, .flightActualDepartureTime, .flightTakeoffTime, .flightLandingTime,
    .flightActualArrivalTime, .flightOnDutyTime, .flightOffDutyTime, .flightHobbsStart,
    .flightHobbsStop, .flightTachStart, .flightTachStop, .flightTotalTime, .flightPIC, .flightSIC,
    .flightSolo, .flightNight, .flightCrossCountry, .flightDualGiven, .flightDualReceived,
    .flightActualInstrument, .flightSimulatedInstrument, .flightSimulator, .flightGround,
    .flightNightVisionGoggle, .flightDayTakeoffs, .flightNightTakeoffs, .flightDayLandings,
    .flightNightLandings, .flightFullStops, .flightNightVisionGoggleTakeoffs,
    .flightNightVisionGoggleLandings, .flightHolds, .flightReview,
    .flightInstrumentProficiencyCheck
  ]

  let flight: Flight

  /// Every set attribute, keyed by its lowercased attribute name, such as `totaltime`.
  let values: [String: FieldValue]

  /// The field key of each attribute in ``values``.
  let keys: [String: LogTenFieldKey]

  /// Whether the entry was flown in a simulator or training device rather than an aircraft.
  let isSimulator: Bool

  var id: RecordID { flight.id }

  /// The registration of the aircraft flown.
  var registration: String? { flight.aircraft?.registration }

  /// The flight's date as cleanup-logten keys it: the UTC calendar date of `flight_flightDate`.
  var dateKey: String { String(PythonTimestamp.isoformat(flight.date).prefix(10)) }

  init(_ flight: Flight) {
    self.flight = flight
    let stored = flight.otherValues.merging(flight.customValues) { $1 }
      .merging(Self.typedKeys.map { ($0, flight[field: $0]) }) { $1 }
      .filter { !$0.value.isNull }
    values = Dictionary(stored.map { (Self.name(of: $0.key), $0.value) }) { $1 }
    keys = Dictionary(stored.keys.map { (Self.name(of: $0), $0) }) { $1 }
    isSimulator =
      flight.times.simulator > 0 || flight.aircraft?.type?.category?.isSimulationDevice == true
  }

  /// The lowercased attribute name cleanup-logten keys evidence by.
  static func name(of key: LogTenFieldKey) -> String { key.attributeName.lowercased() }

  /// The value of an attribute as a number, or `nil` if it is unset or not numeric.
  func number(_ name: String) -> Double? {
    switch values[name] {
      case .integer(let value): Double(value)
      case .number(let value): value
      case .boolean(let value): value ? 1 : 0
      default: nil
    }
  }

  /// Whether an attribute holds a non-zero number.
  func hasPositive(_ name: String) -> Bool { (number(name) ?? 0) > 0 }

  /// The value of an attribute, or `nil` if it is unset.
  subscript(name: String) -> FieldValue? { values[name] }
}

extension FieldValue {
  /// The value as cleanup-logten's evidence records it: SQLite's storage form, so Booleans are
  /// `0` or `1` and dates are seconds since the Core Data reference date.
  var evidenceJSON: JSONValue {
    switch self {
      case .boolean(let value): .integer(value ? 1 : 0)
      default: jsonValue
    }
  }
}

extension Optional where Wrapped == FieldValue {
  /// The value as evidence, or JSON `null` if unset.
  var evidenceJSON: JSONValue { self?.evidenceJSON ?? .null }
}

/// Timestamps and intervals computed the way Python's `datetime` does, so evidence that holds
/// them serializes identically.
enum PythonTimestamp {
  private static let microsecondsPerSecond = 1_000_000.0
  private static let secondsPerMinute = 60.0

  private static let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    return calendar
  }()

  /// The whole microseconds since the Core Data reference date, rounded as Python's
  /// `timedelta(seconds:)` rounds.
  static func microseconds(_ date: Date) -> Int64 {
    Int64((date.timeIntervalSinceReferenceDate * microsecondsPerSecond).rounded(.toNearestOrEven))
  }

  /// The minutes from one time to another, as `(b - a).total_seconds() / 60`.
  static func minutes(from start: Date, to end: Date) -> Double {
    Double(microseconds(end) - microseconds(start)) / microsecondsPerSecond / secondsPerMinute
  }

  /// The time in UTC as `datetime.isoformat()` writes it, such as
  /// `2026-10-20T14:05:00+00:00`, with microseconds only when they aren't zero.
  static func isoformat(_ date: Date) -> String {
    let total = microseconds(date)
    let (seconds, fraction) = total.quotientAndRemainder(dividingBy: Int64(microsecondsPerSecond))
    let (wholeSeconds, micro) =
      fraction < 0 ? (seconds - 1, fraction + 1_000_000) : (seconds, fraction)
    let instant = Date(timeIntervalSinceReferenceDate: TimeInterval(wholeSeconds))
    let parts = calendar.dateComponents(
      [.year, .month, .day, .hour, .minute, .second],
      from: instant
    )
    var text =
      "\(pad(parts.year!, 4))-\(pad(parts.month!, 2))-\(pad(parts.day!, 2))"
      + "T\(pad(parts.hour!, 2)):\(pad(parts.minute!, 2)):\(pad(parts.second!, 2))"
    if micro != 0 { text += ".\(pad(Int(micro), 6))" }
    return text + "+00:00"
  }

  private static func pad(_ value: Int, _ width: Int) -> String {
    let digits = String(value)
    return String(repeating: "0", count: max(0, width - digits.count)) + digits
  }
}
