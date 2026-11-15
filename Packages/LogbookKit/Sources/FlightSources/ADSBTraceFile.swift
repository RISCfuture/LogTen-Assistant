public import Foundation
public import LogbookModel
public import Tracks

/// A UTC calendar day, naming an adsb.lol daily release.
public struct ADSBArchiveDay: Hashable, Codable, Sendable, CustomStringConvertible {
  /// The four-digit year.
  public let year: Int

  /// The month, 1 to 12.
  public let month: Int

  /// The day of the month.
  public let day: Int

  /// The day as `yyyy-MM-dd`.
  public var description: String {
    "\(year.formatted(.number.grouping(.never).precision(.integerLength(4))))-"
      + "\(month.formatted(.number.precision(.integerLength(2))))-"
      + "\(day.formatted(.number.precision(.integerLength(2))))"
  }

  /// The day as `yyyy.MM.dd`, as release names spell it.
  var releaseSpelling: String { description.replacing("-", with: ".") }

  /// The start of the day, in UTC.
  public var start: Date {
    utcCalendar.date(from: DateComponents(year: year, month: month, day: day))!
  }

  /// Creates a day from components, or `nil` if they aren't a valid date.
  public init?(year: Int, month: Int, day: Int) {
    let components = DateComponents(calendar: utcCalendar, year: year, month: month, day: day)
    guard components.isValidDate, year > 0 else { return nil }
    self.year = year
    self.month = month
    self.day = day
  }

  /// Parses `yyyy-MM-dd`.
  public init?(_ text: String) {
    let parts = text.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3 else { return nil }
    self.init(year: parts[0], month: parts[1], day: parts[2])
  }

  /// The UTC day containing a moment.
  public init(_ date: Date) {
    let components = utcCalendar.dateComponents([.year, .month, .day], from: date)
    self.year = components.year!
    self.month = components.month!
    self.day = components.day!
  }

  /// The UTC days a time interval touches.
  public static func days(covering interval: DateInterval) -> [Self] {
    var days = [Self]()
    var current = utcCalendar.startOfDay(for: interval.start)
    while current <= interval.end {
      days.append(Self(current))
      current = utcCalendar.date(byAdding: .day, value: 1, to: current)!
    }
    return days
  }
}

/// How an adsb.lol trace file was obtained.
public struct ADSBProvenance: Hashable, Codable, Sendable {
  /// The license adsb.lol distributes its data under.
  public static let license = "ODbL-1.0"

  /// The archive's documentation.
  public static let documentation = URL(string: "https://www.adsb.lol/docs/open-data/historical")!

  /// The format of the trace files.
  public static let schema = URL(
    string: "https://github.com/wiedehopf/readsb/blob/dev/README-json.md#trace-jsons"
  )!

  /// The UTC day of the release the trace came from.
  public var day: ADSBArchiveDay
  /// The aircraft's ICAO address.
  public var icao: ICAOAddress
  /// The registration the trace file reports.
  public var registration: String?
  /// The number of points in the trace.
  public var pointCount: Int
  /// The `PREFERRED_RELEASES.txt` the release was found in.
  public var listing: URL?
  /// The archive member the trace was read from.
  public var archiveMember: String?
  /// The byte offset of the member in the concatenated archive.
  public var archiveOffset: Int?
  /// The data's source, download URLs, SHA-256 digest, license and retrieval time.
  public var source: SourceProvenance

  /// Creates a provenance record.
  public init(
    day: ADSBArchiveDay,
    icao: ICAOAddress,
    registration: String?,
    pointCount: Int,
    listing: URL? = nil,
    archiveMember: String? = nil,
    archiveOffset: Int? = nil,
    source: SourceProvenance
  ) {
    self.day = day
    self.icao = icao
    self.registration = registration
    self.pointCount = pointCount
    self.listing = listing
    self.archiveMember = archiveMember
    self.archiveOffset = archiveOffset
    self.source = source
  }
}

/// One aircraft's trace for one UTC day from adsb.lol, as downloaded.
public struct ADSBTraceFile: Hashable, Sendable {
  /// The trace file's JSON, exactly as extracted from the archive (decompressed).
  public var json: Data

  /// How it was obtained.
  public var provenance: ADSBProvenance

  /// The positions, as a track under the registration the file reports.
  public var track: Track

  /// The file name the cache stores the trace under.
  public var fileName: String { Self.fileName(day: provenance.day, icao: provenance.icao) }

  /**
   Reads a trace file.

   - Parameters:
     - json: The (decompressed) contents of `trace_full_<hex>.json`.
     - provenance: Where the file came from. Its ``ADSBProvenance/pointCount``,
       ``ADSBProvenance/registration`` and digest are replaced with values read from `json`.
     - fallbackRegistration: The registration to use if the file doesn't report one.
   - Throws: ``FlightSourceError/malformedResponse(_:detail:)`` if the file isn't a trace for
     the address in `provenance`.
   */
  public init(json: Data, provenance: ADSBProvenance, fallbackRegistration: String? = nil) throws {
    let trace: RawTrace
    do {
      trace = try JSONDecoder().decode(RawTrace.self, from: json)
    } catch {
      throw FlightSourceError.malformedResponse(.adsbLol, detail: "Unreadable trace file.")
    }
    guard trace.icao.lowercased() == provenance.icao.hex else {
      throw FlightSourceError.malformedResponse(
        .adsbLol,
        detail: "Trace is for \(trace.icao), not \(provenance.icao.hex)."
      )
    }
    let registration =
      trace.registration?.uppercased() ?? fallbackRegistration ?? provenance.icao.hex
    var updated = provenance
    updated.registration = trace.registration?.uppercased()
    updated.pointCount = trace.points.count
    updated.source.sha256 = sha256Hex(of: json)
    self.json = json
    self.provenance = updated
    self.track = Track(
      registration: registration,
      source: ADSBLolClient.sourceName,
      samples: trace.samples,
      provenance: updated.source
    )
  }

  static func fileName(day: ADSBArchiveDay, icao: ICAOAddress) -> String {
    "adsblol-\(day)-\(icao.hex).json"
  }

  /// The wire format of a readsb `trace_full` file.
  private struct RawTrace: Decodable {
    let icao: String

    let registration: String?
    let timestamp: Double

    let points: [Point]

    /// The samples for the points that have a position, numbered by their place in the trace.
    var samples: [TrackSample] {
      points.enumerated().compactMap { index, point in
        point.sample(base: timestamp, row: index + 1)
      }
    }

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      icao = try container.decode(String.self, forKey: .icao)
      registration = try container.decodeIfPresent(String.self, forKey: .registration)
      timestamp = try container.decode(Double.self, forKey: .timestamp)
      points = try container.decode([Point].self, forKey: .trace)
    }

    private enum CodingKeys: String, CodingKey {
      case icao, timestamp, trace
      case registration = "r"
    }
  }

  /// One point: `[seconds after the trace's timestamp, lat, lon, altitude or "ground", ground
  /// speed, track, flags, …]`. A point that can't be read decodes as empty and is dropped.
  private struct Point: Decodable {
    private static let minimumFields = 5

    private var offset: Double?
    private var latitude: Double?
    private var longitude: Double?
    private var isOnGround = false
    private var altitude: Double?
    private var groundSpeed: Double?
    private var fieldCount = 0

    init(from decoder: any Decoder) throws {
      guard var container = try? decoder.unkeyedContainer() else { return }
      fieldCount = container.count ?? 0
      offset = try? container.decode(Double.self)
      latitude = try? container.decode(Double.self)
      longitude = try? container.decode(Double.self)
      if let text = try? container.decode(String.self) {
        isOnGround = text == "ground"
      } else if (try? container.decodeNil()) == false {
        altitude = try? container.decode(Double.self)
      } else {
        altitude = nil
      }
      groundSpeed = try? container.decode(Double.self)
    }

    func sample(base: Double, row: Int) -> TrackSample? {
      guard fieldCount >= Self.minimumFields, let offset, let latitude, let longitude else {
        return nil
      }
      return TrackSample(
        time: Date(timeIntervalSince1970: base + offset),
        latitudeDeg: latitude,
        longitudeDeg: longitude,
        altitudeFt: altitude,
        groundSpeedKts: groundSpeed,
        isOnGround: isOnGround ? true : nil,
        sourceRow: row
      )
    }
  }
}
