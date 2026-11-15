public import Foundation
import LogbookModel
import StreamingCSV

/// A FlySto CSV export read into header-keyed rows.
struct FlyStoCSVTable {
  private static let byteOrderMark = "\u{FEFF}"
  private static let delimiter: Character = ";"

  var header: [String]
  var rows: [Row]

  static func read(from url: URL) async throws -> Self {
    let name = url.lastPathComponent
    var rows = [[String]]()
    do {
      let reader = try StreamingCSVReader(url: url, delimiter: delimiter)
      while let row = try await reader.readRow() { rows.append(row) }
    } catch {
      throw FlightSourceError.invalidImport(file: name, detail: error.localizedDescription)
    }
    guard var header = rows.first else {
      throw FlightSourceError.invalidImport(
        file: name,
        detail: String(localized: "The file is empty.", bundle: .module)
      )
    }
    header[0] = header[0].replacing(byteOrderMark, with: "")
    let records = rows.dropFirst().enumerated().map { offset, values in
      Row(number: offset + 2, fields: Dictionary(zip(header, values)) { first, _ in first })
    }
    return Self(header: header, rows: records)
  }

  struct Row {
    /// The one-based line, counting the header as line one.
    var number: Int
    var fields: [String: String]
  }
}

/// The result of importing FlySto CSV exports.
public struct FlyStoExport: Hashable, Sendable {
  /// A row that couldn't be used, with the reason.
  public typealias Exclusion = FlyStoRejection

  /// Every consolidated record, including ground activity and incomplete ones.
  public var records: [FlyStoRecord]

  /// Rows that were left out because they are unreadable or after the audit date.
  public var excluded: [Exclusion]

  /// The number of data rows read, including excluded ones.
  public var rowCount: Int

  /// The records with both a takeoff and a landing.
  public var flights: [FlyStoRecord] { records.filter { $0.activity == .flight } }

  /// The records that only show ground activity.
  public var nonflight: [FlyStoRecord] { records.filter { $0.activity == .nonflight } }

  /// The records missing a takeoff or landing.
  public var incomplete: [FlyStoRecord] { records.filter { $0.activity == .incomplete } }

  /// How many rows were folded into another row's record.
  public var duplicateRowsConsolidated: Int { records.reduce(0) { $0 + $1.rows.count - 1 } }
}

/// Reads FlySto CSV exports into ``FlyStoRecord`` values, a port of cleanup-logten's
/// `flysto.load_exports`.
///
/// Exports are semicolon-delimited with a units row under the header, and report clock times
/// as `HH:MMz` without dates. The importer restores dates from the row's date by carrying a
/// day forward whenever the clock moves backward, validates the times against the reported
/// block and engine times, and consolidates repeated rows for one flight without summing
/// their counts.
public struct FlyStoCSVImporter: Sendable {
  private static let requiredColumns: Set<String> = ["Aircraft", "Date", "Takeoffs", "Landings"]

  private static let timeColumns: [FlyStoTimeKind: String] = [
    .startup: "Startup time", .out: "Brakes off", .takeoff: "Takeoff time",
    .landing: "Landing time", .in: "Brakes on", .shutdown: "Shutdown time"
  ]

  private static let precision: TimeInterval = 60
  private static let reconciliationTolerance: TimeInterval = 90
  private static let maximumSpan: TimeInterval = 18 * 3_600
  private static let secondsPerDay: TimeInterval = 86_400
  private static let secondsPerHour: TimeInterval = 3_600

  private static var recordingName: Regex<(Substring, Substring, Substring)> {
    #/log_(\d{8})_(\d{6})_[A-Z0-9]+\.csv/#
  }

  private static var clock: Regex<(Substring, Substring, Substring)> { #/(\d{1,2}):(\d{2})z/# }

  private let asOf: Date

  /// Creates an importer.
  ///
  /// - Parameter asOf: The audit date; rows dated after it are excluded.
  public init(asOf: Date) {
    self.asOf = asOf
  }

  private static func verifiedLinks(_ links: FlyStoLinkIndex?, for file: URL) throws -> [Int: URL] {
    guard let links else { return [:] }
    guard links.sha256 == (try sha256Hex(of: file)) else {
      throw FlightSourceError.invalidImport(
        file: file.lastPathComponent,
        detail: String(localized: "The FlySto link index does not match this CSV.", bundle: .module)
      )
    }
    return links.rows
  }

  private static func identifier(for row: FlyStoRow, dateText: String) -> String {
    let fields = row.columns
    let anchors: [JSONValue] = [.out, .takeoff, .landing, .in].map { kind in
      row.times[kind].map { .string(isoString($0)) } ?? .null
    }
    var key: [JSONValue] = [
      .string(fields["Aircraft"] ?? ""), .string(dateText),
      .string(airportKey(fields["From"])), .string(airportKey(fields["To"])), .array(anchors)
    ]
    if anchors.allSatisfy({ $0 == .null }) {
      key.append(.array([.string(row.file), .integer(row.number ?? 0)]))
    }
    return String(CanonicalJSON.sha256(of: .array(key)).prefix(20))
  }

  private static func record(id: String, rows: [FlyStoRow], first: [String: String]) throws
    -> FlyStoRecord
  {
    let day = try Date(first["Date"] ?? "", strategy: .iso8601.year().month().day())
    return FlyStoRecord.consolidating(
      id: id,
      origin: .csvExport,
      rows: rows,
      registration: first["Aircraft"] ?? "",
      day: day,
      from: first["From"].flatMap { $0.isEmpty ? nil : $0 },
      to: first["To"].flatMap { $0.isEmpty ? nil : $0 },
      metrics: metrics(of: rows),
      precision: precision
    )
  }

  private static func metrics(of rows: [FlyStoRow]) -> FlyStoMetrics {
    func consensus(_ column: String) -> Double? {
      let values = Set(rows.compactMap { number($0.columns[column]) }.filter { $0 >= 0 })
      return values.count == 1 ? values.first : nil
    }
    return FlyStoMetrics(
      directDistanceNM: consensus("Direct distance"),
      groundDistanceNM: consensus("Ground distance"),
      airDistanceNM: consensus("Air distance")
    )
  }

  private static func recordingStart(of fields: [String: String], on day: Date) -> Date? {
    guard fields["Log formats"] == "Garmin G3X",
      let match = (fields["Log files"] ?? "").trimmingCharacters(in: .whitespaces)
        .wholeMatch(of: recordingName),
      let started = try? Date(
        String(match.1) + String(match.2),
        strategy: Date.ParseStrategy(
          format:
            "\(year: .defaultDigits)\(month: .twoDigits)\(day: .twoDigits)\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased))\(minute: .twoDigits)\(second: .twoDigits)",
          locale: Locale(identifier: "en_US_POSIX"),
          timeZone: .gmt
        )
      ),
      utcCalendar.startOfDay(for: started) == day
    else { return nil }
    return utcCalendar.date(bySetting: .second, value: 0, of: started)
  }

  private static func timeIssue(times: FlyStoTimes, fields: [String: String]) -> FlyStoTimeIssue? {
    let intervals: [(FlyStoTimeKind, FlyStoTimeKind, String, FlyStoTimeIssue)] = [
      (.startup, .shutdown, "Engine running time", .engineRunningTime),
      (.out, .in, "Block time", .blockTime)
    ]
    for (start, end, column, issue) in intervals {
      guard let a = times[start], let b = times[end], let hours = number(fields[column]) else {
        continue
      }
      if abs(b.timeIntervalSince(a) - hours * secondsPerHour) > reconciliationTolerance {
        return issue
      }
    }
    let known = times.known
    if let first = known.min(), let last = known.max(),
      last.timeIntervalSince(first) > maximumSpan
    {
      return .excessiveSpan
    }
    return nil
  }

  private static func count(_ text: String?) -> UInt? {
    guard let value = number(text), value >= 0, value.rounded() == value else { return nil }
    return UInt(value)
  }

  private static func number(_ text: String?) -> Double? {
    guard let text, let value = Double(text.trimmingCharacters(in: .whitespaces)), value.isFinite
    else { return nil }
    return value
  }

  private static func isoString(_ date: Date) -> String {
    date.formatted(.iso8601)
      .replacing(/Z$/, with: "+00:00")
  }

  /**
   Restores each clock time's date. Times are processed in order of occurrence; whenever one
   is earlier than the one before it, the flight has crossed midnight UTC and the date moves
   forward a day. A Garmin G3X log named for its recording start seeds the order, so a flight
   that begins before midnight but lists its first time after is placed correctly.
   */
  private static func times(of fields: [String: String], on date: Date) throws -> FlyStoTimes {
    var day = date
    var previous = recordingStart(of: fields, on: date)
    var times = FlyStoTimes()
    for kind in FlyStoTimeKind.allCases {
      let text = (fields[timeColumns[kind]!] ?? "").trimmingCharacters(in: .whitespaces)
      guard !text.isEmpty, text != "?" else { continue }
      guard let match = text.wholeMatch(of: clock), let hour = Int(match.1),
        let minute = Int(match.2), hour < 24, minute < 60
      else {
        throw RowError.invalidClock(text)
      }
      var current = day + TimeInterval(hour * 3_600 + minute * 60)
      if let previous, current < previous {
        current += secondsPerDay
        day = utcCalendar.startOfDay(for: current)
      }
      previous = current
      times[kind] = current
    }
    return times
  }

  /**
   Imports exports and consolidates their rows.

   - Parameter files: The export files, each with the link index recovered for it, if any.
   - Throws: ``FlightSourceError/invalidImport(file:detail:)`` if a file isn't a FlySto export or
     its link index belongs to a different file.
   */
  public func importFiles(_ files: [(url: URL, links: FlyStoLinkIndex?)]) async throws
    -> FlyStoExport
  {
    var groups = [String: [FlyStoRow]]()
    var order = [String]()
    var firsts = [String: [String: String]]()
    var excluded = [FlyStoRejection]()
    var rowCount = 0
    for (url, links) in files {
      let table = try await FlyStoCSVTable.read(from: url)
      guard Self.requiredColumns.isSubset(of: table.header) else {
        throw FlightSourceError.invalidImport(
          file: url.lastPathComponent,
          detail: String(localized: "Unrecognized FlySto export.", bundle: .module)
        )
      }
      let urls = try Self.verifiedLinks(links, for: url)
      for row in table.rows
      where !(row.fields["Aircraft"] ?? "").isEmpty || !(row.fields["Date"] ?? "").isEmpty {
        rowCount += 1
        do {
          let imported = try importRow(row, file: url, link: urls[row.number])
          let key = imported.key
          if groups[key] == nil {
            order.append(key)
            firsts[key] = row.fields
          }
          groups[key, default: []].append(imported.row)
        } catch {
          excluded.append(
            FlyStoRejection(
              source: "\(url.lastPathComponent):\(row.number)",
              reason: error.localizedDescription
            )
          )
        }
      }
    }
    let records = try order.map { key in
      try Self.record(id: key, rows: groups[key]!, first: firsts[key]!)
    }
    return FlyStoExport(records: records, excluded: excluded, rowCount: rowCount)
  }

  private func importRow(
    _ row: FlyStoCSVTable.Row,
    file: URL,
    link: URL?
  ) throws -> (key: String, row: FlyStoRow) {
    let fields = row.fields
    guard let dateText = fields["Date"],
      let day = try? Date(dateText, strategy: .iso8601.year().month().day())
    else {
      throw RowError.invalidDate(fields["Date"] ?? "")
    }
    guard day <= asOf else { throw RowError.afterAuditDate }
    let times = try Self.times(of: fields, on: day)
    let counts = FlyStoCounts(
      takeoffs: Self.count(fields["Takeoffs"]),
      landings: Self.count(fields["Landings"])
    )
    let imported = FlyStoRow(
      file: file.path,
      number: row.number,
      url: link,
      times: times,
      counts: counts,
      timeIssue: Self.timeIssue(times: times, fields: fields),
      columns: fields
    )
    let key = Self.identifier(for: imported, dateText: dateText)
    return (key, imported)
  }

  private enum RowError: LocalizedError {
    case invalidDate(String)
    case afterAuditDate
    case invalidClock(String)

    var errorDescription: String? {
      switch self {
        case .invalidDate(let text):
          String(localized: "“\(text)” isn’t a valid date.", bundle: .module)
        case .afterAuditDate:
          String(localized: "Source flight is after the audit date.", bundle: .module)
        case .invalidClock(let text):
          String(localized: "“\(text)” isn’t a valid clock time.", bundle: .module)
      }
    }
  }
}

/// Compares US FAA identifiers and their four-character ICAO equivalents.
public func airportKey(_ identifier: String?) -> String {
  let trimmed = (identifier ?? "").uppercased().trimmingCharacters(in: .whitespaces)
  return trimmed.count == 4 && trimmed.hasPrefix("K") ? String(trimmed.dropFirst()) : trimmed
}
