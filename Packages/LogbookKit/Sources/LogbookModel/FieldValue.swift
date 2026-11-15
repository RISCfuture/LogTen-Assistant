public import Foundation

/// The value of one LogTen attribute.
///
/// Values keep the attribute's storage type: durations and counts are integers (LogTen stores
/// times as whole minutes), places and people in text attributes are their identifiers or names.
/// ``null`` is an attribute with no value, which LogTen distinguishes from zero or empty text.
public enum FieldValue: Hashable, Sendable {
  /// No value.
  case null
  /// An integer attribute: a duration in minutes, a count, or an enumerated code.
  case integer(Int)
  /// A floating-point attribute, such as distance or a Hobbs reading.
  case number(Double)
  /// A Boolean attribute.
  case boolean(Bool)
  /// A text attribute.
  case text(String)
  /// A date attribute.
  case date(Date)

  /// Whether the value is ``null``.
  public var isNull: Bool { self == .null }

  /// The value as a non-negative integer, or `nil` if it isn't one.
  public var unsignedInteger: UInt? {
    guard case .integer(let value) = self, value >= 0 else { return nil }
    return UInt(value)
  }

  /// The value as text, or `nil` if it isn't text.
  public var text: String? {
    guard case .text(let value) = self else { return nil }
    return value
  }

  /// The value as a date, or `nil` if it isn't a date.
  public var date: Date? {
    guard case .date(let value) = self else { return nil }
    return value
  }

  /// The value as a floating-point number, converting integers.
  public var number: Double? {
    switch self {
      case .number(let value): value
      case .integer(let value): Double(value)
      default: nil
    }
  }

  /// Whether LogTen would show the field as set: a true flag, a non-zero number or non-blank
  /// text.
  public var isSet: Bool {
    switch self {
      case .null: false
      case .integer(let value): value != 0
      case .number(let value): value != 0
      case .boolean(let value): value
      case .text(let value): !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      case .date: true
    }
  }

  /// The value as JSON, with dates as seconds since the Core Data reference date.
  public var jsonValue: JSONValue {
    switch self {
      case .null: .null
      case .integer(let value): .integer(value)
      case .number(let value): .double(value)
      case .boolean(let value): .bool(value)
      case .text(let value): .string(value)
      case .date(let value): .double(value.timeIntervalSinceReferenceDate)
    }
  }
}

extension FieldValue: Codable {
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(Kind.self, forKey: .type) {
      case .null: self = .null
      case .integer: self = .integer(try container.decode(Int.self, forKey: .value))
      case .number: self = .number(try container.decode(Double.self, forKey: .value))
      case .boolean: self = .boolean(try container.decode(Bool.self, forKey: .value))
      case .text: self = .text(try container.decode(String.self, forKey: .value))
      case .date: self = .date(try container.decode(Date.self, forKey: .value))
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
      case .null:
        try container.encode(Kind.null, forKey: .type)
      case .integer(let value):
        try container.encode(Kind.integer, forKey: .type)
        try container.encode(value, forKey: .value)
      case .number(let value):
        try container.encode(Kind.number, forKey: .type)
        try container.encode(value, forKey: .value)
      case .boolean(let value):
        try container.encode(Kind.boolean, forKey: .type)
        try container.encode(value, forKey: .value)
      case .text(let value):
        try container.encode(Kind.text, forKey: .type)
        try container.encode(value, forKey: .value)
      case .date(let value):
        try container.encode(Kind.date, forKey: .type)
        try container.encode(value, forKey: .value)
    }
  }

  private enum CodingKeys: String, CodingKey {
    case type, value
  }

  private enum Kind: String, Codable {
    case null, integer, number, boolean, text, date
  }
}
