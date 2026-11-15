public import Foundation

/// Links from a FlySto CSV export's rows to the flights on flysto.net, recovered from a saved
/// copy of the flight list page.
///
/// The export has no flight identifiers, but the page it was exported from does. A Safari
/// `.webarchive` of the complete list is paired with the export row by row, and every
/// rendered month, date, route and block time must agree before a link is accepted. The index
/// records the export's SHA-256 digest, so it can't be applied to a different file.
public struct FlyStoLinkIndex: Hashable, Codable, Sendable {
  /// The SHA-256 digest of the export file the links belong to, as lowercase hexadecimal.
  public var sha256: String

  /// The flight URL for each export row, keyed by the row's one-based line number counting the
  /// header as line one.
  public var rows: [Int: URL]

  /// Creates an index.
  public init(sha256: String, rows: [Int: URL]) {
    self.sha256 = sha256
    self.rows = rows
  }
}

extension FlyStoLinkIndex {
  /// The prefix of every FlySto flight URL.
  static let flightURLPrefix = "https://www.flysto.net/logs/"

  static var flightURLPattern: Regex<Substring> {
    #/https:\/\/www\.flysto\.net\/logs\/[a-z0-9]{8}/#
  }

  private static let monthFormat: Date.FormatStyle = {
    let base = Date.FormatStyle(locale: Locale(identifier: "en_US_POSIX"), timeZone: .gmt)
    return base.month(.wide).year()
  }()

  private static var clockPattern: Regex<Substring> { #/\d{2}:\d{2}z|\?/# }

  private static let shortMonthFormat: Date.FormatStyle = {
    let base = Date.FormatStyle(locale: Locale(identifier: "en_US_POSIX"), timeZone: .gmt)
    return base.month(.abbreviated)
  }()

  private static func check(
    _ saved: FlyStoFlightListPage.Row,
    against row: FlyStoCSVTable.Row,
    archive: URL
  ) throws {
    let fields = row.fields
    guard let text = fields["Date"],
      let day = try? Date(text, strategy: .iso8601.year().month().day())
    else {
      throw invalid(archive, "CSV row \(row.number) has no valid date.")
    }
    guard saved.month == day.formatted(monthFormat) else {
      throw invalid(archive, "Flight-list month does not match CSV row \(row.number).")
    }
    let components = utcCalendar.dateComponents([.day], from: day)
    if let shortDate = saved.cells["date-short"],
      shortDate != "\(components.day ?? 0) \(day.formatted(shortMonthFormat))"
    {
      throw invalid(archive, "Flight-list date does not match CSV row \(row.number).")
    }
    if let route = saved.cells["from-to"], route != (fields["From"] ?? "") + (fields["To"] ?? "") {
      throw invalid(archive, "Flight-list route does not match CSV row \(row.number).")
    }
    if let clocks = saved.cells["brakes-off-on"] {
      let rendered = clocks.matches(of: clockPattern).map { String($0.output) }
      let expected = ["Brakes off", "Brakes on"].map { name in
        fields[name].flatMap { $0.isEmpty ? nil : $0 } ?? "?"
      }
      guard rendered == expected else {
        throw invalid(archive, "Flight-list times do not match CSV row \(row.number).")
      }
    }
  }

  private static func invalid(_ file: URL, _ detail: String) -> FlightSourceError {
    .invalidImport(file: file.lastPathComponent, detail: detail)
  }

  /**
   Pairs a saved flight-list page with the CSV exported from it.

   - Parameters:
     - archive: A Safari `.webarchive` of the aircraft's complete flight list at
       `flysto.net/logs?aircraft=…`.
     - csv: The CSV exported from the same list.
   - Throws: ``FlightSourceError/invalidImport(file:detail:)`` if the archive isn't a FlySto
     flight list, is incomplete, or disagrees with the CSV.
   */
  public static func read(archive: URL, csv: URL) async throws -> Self {
    let page = try FlyStoFlightListPage(archive: archive)
    let table = try await FlyStoCSVTable.read(from: csv)
    let exported = table.rows.filter { !($0.fields["Aircraft"] ?? "").isEmpty }
    guard page.rows.count == exported.count, Set(page.rows.map(\.id)).count == exported.count else {
      throw invalid(
        archive,
        "The flight-list archive is incomplete or does not match the CSV row count."
      )
    }
    var links = [Int: URL]()
    for (saved, row) in zip(page.rows, exported) {
      try check(saved, against: row, archive: archive)
      guard let url = URL(string: flightURLPrefix + saved.id),
        url.absoluteString.wholeMatch(of: flightURLPattern) != nil
      else {
        throw invalid(archive, "Invalid FlySto flight ID at CSV row \(row.number).")
      }
      links[row.number] = url
    }
    return Self(sha256: try sha256Hex(of: csv), rows: links)
  }
}

/// The flight rows of a saved FlySto flight-list page.
struct FlyStoFlightListPage {
  private static var listURLPattern: Regex<Substring> {
    #/https:\/\/www\.flysto\.net\/logs\?aircraft=[a-z0-9]+/#
  }

  let rows: [Row]

  init(archive: URL) throws {
    let name = archive.lastPathComponent
    guard let data = try? Data(contentsOf: archive),
      let webArchive = try? PropertyListDecoder().decode(WebArchive.self, from: data),
      webArchive.main.address.wholeMatch(of: Self.listURLPattern) != nil,
      let html = String(data: webArchive.main.data, encoding: .utf8)
    else {
      throw FlightSourceError.invalidImport(
        file: name,
        detail: String(
          localized: "Expected a FlySto aircraft flight-list archive.",
          bundle: .module
        )
      )
    }
    rows = Self.rows(in: HTMLTokenizer.tokens(in: html))
  }

  /// Collects the `tr` elements with a `data-key`, tagging each with the preceding `h4`
  /// month heading and collecting its cells' text by `data-column-id`.
  private static func rows(in tokens: [HTMLToken]) -> [Row] {
    var rows = [Row]()
    var month = ""
    var isHeading = false
    var current: Row?
    var cell: String?
    for token in tokens {
      switch token {
        case .start("tr", let attributes):
          current =
            attributes["data-row-id"] == nil
            ? attributes["data-key"].map { Row(id: $0, month: month, cells: [:]) } : nil
        case .start("td", let attributes):
          cell = attributes["data-column-id"]
        case .start("h4", _):
          isHeading = true
          month = ""
        case .text(let text):
          if isHeading { month += text }
          if let cell, current != nil { current?.cells[cell, default: ""] += text }
        case .end("h4"):
          isHeading = false
        case .end("td"):
          cell = nil
        case .end("tr"):
          if let current, !current.id.isEmpty { rows.append(current) }
          current = nil
        default:
          break
      }
    }
    return rows
  }

  /// The part of a Safari `.webarchive` property list that holds the saved page.
  private struct WebArchive: Decodable {
    let main: Resource

    struct Resource: Decodable {
      let address: String
      let data: Data

      private enum CodingKeys: String, CodingKey {
        case address = "WebResourceURL"
        case data = "WebResourceData"
      }
    }

    private enum CodingKeys: String, CodingKey {
      case main = "WebMainResource"
    }
  }

  struct Row {
    var id: String
    var month: String
    var cells: [String: String]
  }
}
