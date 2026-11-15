public import Foundation

/// An array that drops elements that fail to decode instead of failing the whole array.
struct LossyArray<Element: Decodable & Sendable>: Decodable, Sendable {
  var elements: [Element]

  /// How many elements failed to decode.
  var droppedCount: Int

  init(from decoder: any Decoder) throws {
    var container = try decoder.unkeyedContainer()
    var elements = [Element]()
    var droppedCount = 0
    while !container.isAtEnd {
      if let element = try? container.decode(Element.self) {
        elements.append(element)
      } else {
        droppedCount += 1
        _ = try? container.decode(Discarded.self)
      }
    }
    self.elements = elements
    self.droppedCount = droppedCount
  }

  private struct Discarded: Decodable {}
}

/// A value of a FlySto parameter, which the API reports as a string, number or Boolean
/// depending on the parameter.
public enum FlyStoValue: Hashable, Codable, Sendable {
  /// A string, such as an ISO 8601 time or a tag list.
  case text(String)
  /// A number.
  case number(Double)
  /// A Boolean.
  case flag(Bool)
  /// A value of a type the client doesn't know.
  case unknown

  /// The value as text; numbers are formatted without a trailing “.0”.
  public var text: String? {
    switch self {
      case .text(let value): value
      case .number(let value): Int(exactly: value).map(String.init) ?? String(value)
      case .flag, .unknown: nil
    }
  }

  /// The value as a number, parsing numeric strings.
  public var number: Double? {
    switch self {
      case .number(let value): value
      case .text(let value): Double(value.trimmingCharacters(in: .whitespaces))
      case .flag, .unknown: nil
    }
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let value = try? container.decode(Bool.self) {
      self = .flag(value)
    } else if let value = try? container.decode(Double.self) {
      self = .number(value)
    } else if let value = try? container.decode(String.self) {
      self = .text(value)
    } else {
      self = .unknown
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
      case .text(let value): try container.encode(value)
      case .number(let value): try container.encode(value)
      case .flag(let value): try container.encode(value)
      case .unknown: try container.encodeNil()
    }
  }
}

/// A named value on a FlySto log, takeoff or approach.
public struct FlyStoParameter: Hashable, Codable, Sendable {
  /// The parameter's name, such as “Brakes off”.
  public var name: String

  /// The value, if the parameter has one.
  public var value: FlyStoValue?
  /// The unit of ``value``, such as “nm”.
  public var units: String?
  /// The people listed, for the “Crew” parameter.
  public var crew: [FlyStoCrewMember]

  /// Creates a parameter.
  public init(
    name: String,
    value: FlyStoValue? = nil,
    units: String? = nil,
    crew: [FlyStoCrewMember] = []
  ) {
    self.name = name
    self.value = value
    self.units = units
    self.crew = crew
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    name = try container.decode(String.self, forKey: .name)
    value = try? container.decodeIfPresent(FlyStoValue.self, forKey: .value)
    units = try? container.decodeIfPresent(String.self, forKey: .units)
    crew = (try? container.decodeIfPresent(LossyCrew.self, forKey: .crew))?.members ?? []
  }

  private enum CodingKeys: String, CodingKey {
    case name, value, units, crew
  }

  private struct LossyCrew: Decodable {
    let members: [FlyStoCrewMember]

    init(from decoder: any Decoder) throws {
      members = try LossyArray<CrewEntry>(from: decoder).elements.map(\.member)
    }
  }

  private struct CrewEntry: Decodable, Sendable {
    let member: FlyStoCrewMember

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: Keys.self)
      member = FlyStoCrewMember(
        id: try container.decode(Int.self, forKey: .id),
        name: try container.decode(String.self, forKey: .name),
        role: try? container.decodeIfPresent(String.self, forKey: .role)
      )
    }

    private enum Keys: String, CodingKey { case id, name, role }
  }
}

/// A takeoff or approach on a FlySto log.
public struct FlyStoLogEvent: Hashable, Codable, Sendable {
  /// When it happened, as the ISO 8601 string FlySto reports.
  public var time: String?
  /// The airport.
  public var airport: String?
  /// The runway.
  public var runway: String?
  /// FlySto's classification, for approaches (“Landing” and so on).
  public var type: String?
  /// FlySto's detail parameters.
  public var parameters: [FlyStoParameter]

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    time = try? container.decodeIfPresent(String.self, forKey: .time)
    airport = try? container.decodeIfPresent(String.self, forKey: .airport)
    runway = try? container.decodeIfPresent(String.self, forKey: .runway)
    type = try? container.decodeIfPresent(String.self, forKey: .type)
    parameters =
      (try? container.decodeIfPresent(LossyArray<FlyStoParameter>.self, forKey: .parameters))?
      .elements ?? []
  }

  private enum CodingKeys: String, CodingKey {
    case time, airport, runway, type, parameters
  }
}

/// A flight in FlySto's `GET /logs` response.
///
/// Decoding is strict about the fields the audits rely on (the log's identifier, and the type
/// of each field that is present) and lenient about everything else: unknown fields are
/// ignored, and parameters, takeoffs and approaches that can't be read are dropped.
public struct FlyStoLog: Identifiable, Hashable, Codable, Sendable {
  /// FlySto's log identifier.
  public var id: String

  /// The link to the log on flysto.net.
  public var url: URL?

  /// The date as FlySto displays it, such as “12 Oct 2026”.
  public var date: String?

  /// The aircraft's registration.
  public var aircraft: String?

  /// FlySto's aircraft identifier.
  public var aircraftID: String?

  /// The departure airport.
  public var from: String?

  /// The destination airport.
  public var to: String?

  /// The log's parameters.
  public var parameters: [FlyStoParameter]

  /// The takeoffs, if the response includes them.
  public var takeoffs: [FlyStoLogEvent]?

  /// The approaches and landings, if the response includes them.
  public var approaches: [FlyStoLogEvent]?

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    url = try? container.decodeIfPresent(URL.self, forKey: .url)
    date = try container.decodeIfPresent(String.self, forKey: .date)
    aircraft = try container.decodeIfPresent(String.self, forKey: .aircraft)
    aircraftID = try container.decodeIfPresent(String.self, forKey: .aircraftID)
    from = try container.decodeIfPresent(String.self, forKey: .from)
    to = try container.decodeIfPresent(String.self, forKey: .to)
    parameters =
      try container.decodeIfPresent(LossyArray<FlyStoParameter>.self, forKey: .parameters)?
      .elements ?? []
    takeoffs = try container.decodeIfPresent(LossyArray<FlyStoLogEvent>.self, forKey: .takeoffs)?
      .elements
    approaches =
      try container.decodeIfPresent(LossyArray<FlyStoLogEvent>.self, forKey: .approaches)?
      .elements
  }

  /// The first parameter with a name.
  public func parameter(_ name: String) -> FlyStoParameter? {
    parameters.first { $0.name == name }
  }

  private enum CodingKeys: String, CodingKey {
    case id, url, date, aircraft, from, to, parameters, takeoffs, approaches
    case aircraftID = "aircraft-id"
  }
}

/// One page of `GET /logs`.
public struct FlyStoLogPage: Decodable, Sendable {
  /// The logs on the page, newest first.
  public var logs: [FlyStoLog]

  /// How many logs on the page couldn't be decoded and are missing from ``logs``.
  public var undecodableCount: Int

  /// The URL of the next page, to be followed as given.
  public var next: URL?

  /// The sync cursor for incremental fetches: pass it as `after` next time.
  public var timestamp: String?

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let lossyLogs = try container.decode(LossyArray<FlyStoLog>.self, forKey: .logs)
    logs = lossyLogs.elements
    undecodableCount = lossyLogs.droppedCount
    next = try container.decodeIfPresent(URL.self, forKey: .next)
    if let text = try? container.decodeIfPresent(String.self, forKey: .timestamp) {
      timestamp = text
    } else if let number = try? container.decodeIfPresent(Int.self, forKey: .timestamp) {
      timestamp = String(number)
    }
  }

  private enum CodingKeys: String, CodingKey {
    case logs, next, timestamp
  }
}

/// A person in FlySto's crew list.
public struct FlyStoCrewEntry: Decodable, Hashable, Sendable {
  /// FlySto's identifier for the person.
  public var id: Int
  /// The person's name.
  public var name: String
  /// The role FlySto assigns automatically when the person appears on a flight.
  public var automaticRole: String?

  private enum CodingKeys: String, CodingKey {
    case id, name
    case automaticRole = "automatic-role"
  }
}

/// The outcome of a `POST /log-upload`.
public struct FlyStoUpload: Hashable, Sendable {
  /// FlySto's identifier for the uploaded file, to poll with ``FlyStoClient/waitForProcessing(of:)``.
  public var fileID: String
  /// Whether FlySto already had this exact file, which is not an error.
  public var wasAlreadyUploaded: Bool
}

/// The processing state of an uploaded file.
public enum FlyStoProcessing: Hashable, Sendable {
  /// FlySto hasn't finished processing the file.
  case pending
  /// FlySto created these logs from the file.
  case processed(logIDs: [String])
}
