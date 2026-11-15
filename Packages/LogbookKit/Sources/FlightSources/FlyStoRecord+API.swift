public import Foundation

/// A FlySto log that couldn't be turned into a record, with the reason.
public struct FlyStoRejection: Hashable, Codable, Sendable {
  /// The log's identifier, or the export row's location.
  public var source: String
  /// Why the log was rejected.
  public var reason: String
}

extension FlyStoRecord {
  /// The API path recorded as the file of rows read from the API.
  public static let apiSource = "public-api/logs"

  private static let parameterTimes: [(String, FlyStoTimeKind)] = [
    ("Startup time", .startup), ("Brakes off", .out), ("Takeoff time", .takeoff),
    ("Landing time", .landing), ("Brakes on", .in), ("Shutdown time", .shutdown)
  ]

  private static let landingType = "Landing"
  private static let apiPrecision: TimeInterval = 1

  private static let dateStrategy = Date.ParseStrategy(
    format: "\(day: .defaultDigits) \(month: .abbreviated) \(year: .defaultDigits)",
    locale: Locale(identifier: "en_US_POSIX"),
    timeZone: .gmt
  )

  private init(log: FlyStoLog) throws {
    guard let registration = log.aircraft, !registration.isEmpty else {
      throw APIError.missing("aircraft")
    }
    let times = try Self.times(in: log)
    guard let day = Self.day(of: log, times: times) else { throw APIError.missing("date") }
    let row = FlyStoRow(
      file: Self.apiSource,
      url: log.url,
      times: times,
      counts: Self.counts(of: log)
    )
    var record = Self.consolidating(
      id: log.id,
      origin: .api,
      rows: [row],
      registration: registration,
      day: day,
      from: log.from,
      to: log.to,
      metrics: Self.metrics(of: log),
      precision: Self.apiPrecision
    )
    record.flyStoAircraftID = log.aircraftID
    record.crew = log.parameter("Crew")?.crew ?? []
    record.takeoffEvents = try (log.takeoffs ?? []).map { try Self.event(from: $0) }
    record.approachEvents = try (log.approaches ?? []).map { try Self.event(from: $0) }
    self = record
  }

  private static func times(in log: FlyStoLog) throws -> FlyStoTimes {
    var times = FlyStoTimes()
    for (name, kind) in parameterTimes {
      guard let text = log.parameter(name)?.value?.text else { continue }
      guard let date = parseTimestamp(text) else { throw APIError.unreadable(name, text) }
      times[kind] = date
    }
    return times
  }

  private static func counts(of log: FlyStoLog) -> FlyStoCounts {
    FlyStoCounts(
      takeoffs: log.takeoffs.map { UInt($0.count) },
      landings: log.approaches.map { UInt($0.filter { $0.type == landingType }.count) }
    )
  }

  private static func metrics(of log: FlyStoLog) -> FlyStoMetrics {
    func nauticalMiles(_ name: String) -> Double? {
      guard let parameter = log.parameter(name), parameter.units?.lowercased() == "nm" else {
        return nil
      }
      return parameter.value?.number
    }
    return FlyStoMetrics(
      directDistanceNM: nauticalMiles("Direct distance"),
      groundDistanceNM: nauticalMiles("Ground distance"),
      airDistanceNM: nauticalMiles("Air distance")
    )
  }

  private static func event(from event: FlyStoLogEvent) throws -> FlyStoRunwayEvent {
    let time = try event.time.map { text -> Date in
      guard let date = parseTimestamp(text) else { throw APIError.unreadable("time", text) }
      return date
    }
    return FlyStoRunwayEvent(
      time: time,
      airport: event.airport,
      runway: event.runway,
      type: event.type,
      subtype: event.parameters.first { $0.name == "Type" }?.value?.text
    )
  }

  private static func day(of log: FlyStoLog, times: FlyStoTimes) -> Date? {
    if let text = log.date, let parsed = try? Date(text, strategy: dateStrategy) {
      return utcCalendar.startOfDay(for: parsed)
    }
    return times.known.first.map { utcCalendar.startOfDay(for: $0) }
  }

  /// Parses an ISO 8601 UTC timestamp, with or without fractional seconds.
  static func parseTimestamp(_ text: String) -> Date? {
    let formats: [Date.ISO8601FormatStyle] = [
      .iso8601, .iso8601.year().month().day().time(includingFractionalSeconds: true)
    ]
    return formats.lazy.compactMap { try? $0.parse(text) }.first
  }

  /**
   Converts API logs to records.

   A log with an unreadable time, or without a registration or a date, is rejected rather
   than guessed at. Takeoffs are counted from the log's takeoff list and landings from the
   approaches classified “Landing”; a log that doesn't list them has unknown counts.

   - Parameter logs: The logs from ``FlyStoClient/syncLogs(after:type:limit:progress:)``.
   - Returns: The records, in the logs' order, and the logs that were rejected. A log FlySto
     returned more than once yields one record.
   */
  public static func records(from logs: [FlyStoLog]) -> (
    records: [Self], rejected: [FlyStoRejection]
  ) {
    var records = [Self]()
    var rejected = [FlyStoRejection]()
    var seen = Set<String>()
    for log in logs where seen.insert(log.id).inserted {
      do {
        records.append(try Self(log: log))
      } catch {
        rejected.append(
          FlyStoRejection(source: log.id, reason: error.localizedDescription)
        )
      }
    }
    return (records, rejected)
  }

  private enum APIError: LocalizedError {
    case missing(String)
    case unreadable(String, String)

    var errorDescription: String? {
      switch self {
        case .missing(let field):
          String(localized: "The log has no \(field).", bundle: .module)
        case let .unreadable(field, value):
          String(localized: "The log’s \(field) “\(value)” isn’t a valid time.", bundle: .module)
      }
    }
  }
}

/// A Gregorian calendar fixed to UTC, for the day arithmetic FlySto's exports use.
let utcCalendar: Calendar = {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = .gmt
  return calendar
}()
