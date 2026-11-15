public import Foundation

/// A moment in a flight that FlySto reports.
public enum FlyStoTimeKind: String, CaseIterable, Codable, Sendable {
  /// Engine start.
  case startup
  /// Brakes off.
  case out
  /// Wheels up.
  case takeoff
  /// Wheels down.
  case landing
  /// Brakes on.
  case `in`
  /// Engine shutdown.
  case shutdown
}

/// A count FlySto reports.
public enum FlyStoCountKind: String, CaseIterable, Codable, Sendable {
  /// Takeoffs.
  case takeoff
  /// Landings.
  case landing
}

/// A value on a ``FlyStoRecord`` that was reported inconsistently by repeated rows.
public enum FlyStoField: Hashable, Codable, Sendable {
  /// A time.
  case time(FlyStoTimeKind)
  /// A count.
  case count(FlyStoCountKind)
}

/// The times FlySto reports for a flight, in UTC; `nil` means unknown, not midnight.
public struct FlyStoTimes: Hashable, Codable, Sendable {
  /// Engine start.
  public var startup: Date?
  /// Brakes off.
  public var out: Date?
  /// Wheels up.
  public var takeoff: Date?
  /// Wheels down.
  public var landing: Date?
  /// Brakes on.
  public var `in`: Date?
  /// Engine shutdown.
  public var shutdown: Date?

  /// The reported times in order of occurrence, skipping unknown ones.
  public var known: [Date] { FlyStoTimeKind.allCases.compactMap { self[$0] } }

  /// Creates a set of times.
  public init(
    startup: Date? = nil,
    out: Date? = nil,
    takeoff: Date? = nil,
    landing: Date? = nil,
    in: Date? = nil,
    shutdown: Date? = nil
  ) {
    self.startup = startup
    self.out = out
    self.takeoff = takeoff
    self.landing = landing
    self.in = `in`
    self.shutdown = shutdown
  }

  /// One of the times.
  public subscript(kind: FlyStoTimeKind) -> Date? {
    get {
      switch kind {
        case .startup: startup
        case .out: out
        case .takeoff: takeoff
        case .landing: landing
        case .in: `in`
        case .shutdown: shutdown
      }
    }
    set {
      switch kind {
        case .startup: startup = newValue
        case .out: out = newValue
        case .takeoff: takeoff = newValue
        case .landing: landing = newValue
        case .in: `in` = newValue
        case .shutdown: shutdown = newValue
      }
    }
  }
}

/// The takeoff and landing counts FlySto reports for a flight; `nil` means unknown, not zero.
public struct FlyStoCounts: Hashable, Codable, Sendable {
  /// Takeoffs.
  public var takeoffs: UInt?
  /// Landings.
  public var landings: UInt?

  /// Creates a set of counts.
  public init(takeoffs: UInt? = nil, landings: UInt? = nil) {
    self.takeoffs = takeoffs
    self.landings = landings
  }

  /// One of the counts.
  public subscript(kind: FlyStoCountKind) -> UInt? {
    get {
      switch kind {
        case .takeoff: takeoffs
        case .landing: landings
      }
    }
    set {
      switch kind {
        case .takeoff: takeoffs = newValue
        case .landing: landings = newValue
      }
    }
  }
}

/// A reason a record's clock times can't be trusted.
public enum FlyStoTimeIssue: String, CaseIterable, Codable, Sendable {
  /// Engine running time doesn't match the time between startup and shutdown.
  case engineRunningTime = "engine_running_time"
  /// Block time doesn't match the time between brakes off and on.
  case blockTime = "block_time"
  /// The times span more than 18 hours, so a date rollover was probably misread.
  case excessiveSpan = "excessive_span"

  /// A localized description.
  public var message: String {
    switch self {
      case .engineRunningTime:
        String(
          localized: "Engine running time does not reconcile with exported clock times.",
          bundle: .module
        )
      case .blockTime:
        String(
          localized: "Block time does not reconcile with exported clock times.",
          bundle: .module
        )
      case .excessiveSpan:
        String(
          localized: "Exported clock sequence exceeds 18 hours; dates need review.",
          bundle: .module
        )
    }
  }
}

/// Distances FlySto computes for a flight, in nautical miles.
public struct FlyStoMetrics: Hashable, Codable, Sendable {
  /// The great-circle distance between the endpoints.
  public var directDistanceNM: Double?
  /// The distance over the ground.
  public var groundDistanceNM: Double?
  /// The distance through the air.
  public var airDistanceNM: Double?

  /// Creates metrics.
  public init(
    directDistanceNM: Double? = nil,
    groundDistanceNM: Double? = nil,
    airDistanceNM: Double? = nil
  ) {
    self.directDistanceNM = directDistanceNM
    self.groundDistanceNM = groundDistanceNM
    self.airDistanceNM = airDistanceNM
  }
}

/// A person FlySto lists on a flight.
public struct FlyStoCrewMember: Hashable, Codable, Sendable {
  /// FlySto's identifier for the person.
  public var id: Int
  /// The person's name.
  public var name: String
  /// The role FlySto assigned, such as “PIC” or “Instructor”.
  public var role: String?

  /// Creates a crew member.
  public init(id: Int, name: String, role: String? = nil) {
    self.id = id
    self.name = name
    self.role = role
  }
}

/// A takeoff or approach FlySto detected.
public struct FlyStoRunwayEvent: Hashable, Codable, Sendable {
  /// When it happened.
  public var time: Date?
  /// The airport.
  public var airport: String?
  /// The runway.
  public var runway: String?
  /// FlySto's classification of an approach, such as “Landing”; `nil` for a takeoff.
  public var type: String?
  /// The approach's own “Type” parameter, such as “Full-Stop”.
  public var subtype: String?

  /// Creates an event.
  public init(
    time: Date? = nil,
    airport: String? = nil,
    runway: String? = nil,
    type: String? = nil,
    subtype: String? = nil
  ) {
    self.time = time
    self.airport = airport
    self.runway = runway
    self.type = type
    self.subtype = subtype
  }
}

/// Where one observation in a ``FlyStoRecord`` came from: a CSV export row, or an API log.
public struct FlyStoRow: Hashable, Codable, Sendable {
  /// The export file path, or the API path the log came from.
  public var file: String
  /// The one-based line in the export, counting the header as line one; `nil` for the API.
  public var number: Int?
  /// The link to the flight on flysto.net, if known.
  public var url: URL?
  /// The times this row reported.
  public var times: FlyStoTimes
  /// The counts this row reported.
  public var counts: FlyStoCounts
  /// The reason this row's clock times can't be trusted, if any.
  public var timeIssue: FlyStoTimeIssue?
  /// The row's columns by header, for exports; empty for the API.
  public var columns: [String: String]

  /// Creates a row.
  public init(
    file: String,
    number: Int? = nil,
    url: URL? = nil,
    times: FlyStoTimes = .init(),
    counts: FlyStoCounts = .init(),
    timeIssue: FlyStoTimeIssue? = nil,
    columns: [String: String] = [:]
  ) {
    self.file = file
    self.number = number
    self.url = url
    self.times = times
    self.counts = counts
    self.timeIssue = timeIssue
    self.columns = columns
  }
}

/// A flight (or ground activity) as FlySto reports it, from the API or a CSV export.
///
/// Records from both sources have the same shape, so matching and comparison don't care where
/// a record came from. A CSV export can list one flight on several rows; those are consolidated
/// here, with the values that disagree left unknown and listed in ``conflicts``.
public struct FlyStoRecord: Identifiable, Hashable, Codable, Sendable {
  /// FlySto's log identifier for API records; a content-addressed identifier for export rows.
  public var id: String

  /// Where the record was read from.
  public var origin: Origin

  /// The registration FlySto lists for the aircraft.
  public var registration: String

  /// FlySto's identifier for the aircraft, if known.
  public var flyStoAircraftID: String?

  /// The UTC calendar day of the flight, as midnight UTC.
  public var day: Date

  /// The departure airport identifier as FlySto reports it.
  public var from: String?

  /// The destination airport identifier as FlySto reports it.
  public var to: String?

  /// The reported times, consolidated across ``rows``.
  public var times: FlyStoTimes

  /// The reported counts, consolidated across ``rows``.
  public var counts: FlyStoCounts

  /// Values the rows disagree on.
  public var conflicts: Set<FlyStoField>

  /// The reasons any row's clock times can't be trusted.
  public var timeIssues: [FlyStoTimeIssue]

  /// The observations the record was consolidated from.
  public var rows: [FlyStoRow]

  /// Links to the flight on flysto.net.
  public var urls: [URL]

  /// Distances FlySto computed.
  public var metrics: FlyStoMetrics

  /// The crew FlySto lists.
  public var crew: [FlyStoCrewMember]

  /// Takeoffs FlySto detected.
  public var takeoffEvents: [FlyStoRunwayEvent]

  /// Approaches and landings FlySto detected.
  public var approachEvents: [FlyStoRunwayEvent]

  /// The resolution of the times, in seconds.
  public var precision: TimeInterval

  /// What the record shows about flight activity.
  public var activity: Activity {
    let boundaries: [(FlyStoTimeKind, FlyStoCountKind)] = [
      (.takeoff, .takeoff), (.landing, .landing)
    ]
    let hasContradiction = ([FlyStoRow(file: "", times: times, counts: counts)] + rows).contains {
      row in
      boundaries.contains { row.times[$0.0] != nil && row.counts[$0.1] == 0 }
    }
    if hasContradiction { return .incomplete }
    let observed = boundaries.map { times[$0.0] != nil || (counts[$0.1] ?? 0) > 0 }
    if observed.allSatisfy(\.self) { return .flight }
    if !observed.contains(true) && counts.takeoffs == 0 && counts.landings == 0 {
      return .nonflight
    }
    return .incomplete
  }

  /// Whether both a takeoff and a landing were observed.
  public var isFlight: Bool { activity == .flight }

  /// Creates a record.
  public init(
    id: String,
    origin: Origin,
    registration: String,
    flyStoAircraftID: String? = nil,
    day: Date,
    from: String? = nil,
    to: String? = nil,
    times: FlyStoTimes = .init(),
    counts: FlyStoCounts = .init(),
    conflicts: Set<FlyStoField> = [],
    timeIssues: [FlyStoTimeIssue] = [],
    rows: [FlyStoRow] = [],
    urls: [URL] = [],
    metrics: FlyStoMetrics = .init(),
    crew: [FlyStoCrewMember] = [],
    takeoffEvents: [FlyStoRunwayEvent] = [],
    approachEvents: [FlyStoRunwayEvent] = [],
    precision: TimeInterval
  ) {
    self.id = id
    self.origin = origin
    self.registration = registration
    self.flyStoAircraftID = flyStoAircraftID
    self.day = day
    self.from = from
    self.to = to
    self.times = times
    self.counts = counts
    self.conflicts = conflicts
    self.timeIssues = timeIssues
    self.rows = rows
    self.urls = urls
    self.metrics = metrics
    self.crew = crew
    self.takeoffEvents = takeoffEvents
    self.approachEvents = approachEvents
    self.precision = precision
  }

  /// What a record shows about flight activity.
  public enum Activity: String, Codable, Sendable {
    /// Both a takeoff and a landing were observed.
    case flight
    /// The aircraft only moved on the ground.
    case nonflight
    /// Evidence of a takeoff or landing is missing or contradictory.
    case incomplete
  }

  /// Where a record was read from.
  public enum Origin: String, Codable, Sendable {
    /// FlySto's public API.
    case api
    /// A CSV export.
    case csvExport = "csv_export"
  }
}

extension FlyStoRecord {
  /// Consolidates rows that describe the same flight.
  ///
  /// A time or count that only some rows report is taken from them; one the rows report
  /// differently is left unknown and recorded in ``conflicts``. Counts are never summed.
  static func consolidating(
    id: String,
    origin: Origin,
    rows: [FlyStoRow],
    registration: String,
    day: Date,
    from: String?,
    to: String?,
    metrics: FlyStoMetrics,
    precision: TimeInterval
  ) -> Self {
    var conflicts = Set<FlyStoField>()
    var times = FlyStoTimes()
    for kind in FlyStoTimeKind.allCases {
      let values = Set(rows.compactMap { $0.times[kind] })
      if values.count > 1 { conflicts.insert(.time(kind)) }
      times[kind] = values.count == 1 ? values.first : nil
    }
    var counts = FlyStoCounts()
    for kind in FlyStoCountKind.allCases {
      let values = Set(rows.compactMap { $0.counts[kind] })
      if values.count > 1 { conflicts.insert(.count(kind)) }
      counts[kind] = values.count == 1 ? values.first : nil
    }
    return Self(
      id: id,
      origin: origin,
      registration: registration,
      day: day,
      from: from,
      to: to,
      times: times,
      counts: counts,
      conflicts: conflicts,
      timeIssues: Set(rows.compactMap(\.timeIssue)).sorted { $0.rawValue < $1.rawValue },
      rows: rows,
      urls: rows.compactMap(\.url).reduce(into: []) { if !$0.contains($1) { $0.append($1) } },
      metrics: metrics,
      precision: precision
    )
  }
}
