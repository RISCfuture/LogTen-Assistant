/// An arbitrary JSON value, used for finding evidence and record fingerprints.
///
/// Integers and floating-point numbers are distinct so that canonical JSON keeps the
/// difference between `5` and `5.0`, as Python's `json` module does.
public enum JSONValue: Hashable, Sendable {
  /// JSON `null`.
  case null
  /// `true` or `false`.
  case bool(Bool)
  /// An integer.
  case integer(Int)
  /// A floating-point number.
  case double(Double)
  /// A string.
  case string(String)
  /// An array.
  indirect case array([Self])
  /// An object.
  indirect case object([String: Self])

  /// The value as an object, or `nil` if it isn't one.
  public var objectValue: [String: Self]? {
    guard case .object(let value) = self else { return nil }
    return value
  }

  /// The value as an array, or `nil` if it isn't one.
  public var arrayValue: [Self]? {
    guard case .array(let value) = self else { return nil }
    return value
  }

  /// The value as a string, or `nil` if it isn't one.
  public var stringValue: String? {
    guard case .string(let value) = self else { return nil }
    return value
  }

  /// The value as a floating-point number, converting integers.
  public var doubleValue: Double? {
    switch self {
      case .integer(let value): Double(value)
      case .double(let value): value
      default: nil
    }
  }

  /// The member of an object, or `nil` if this isn't an object or has no such member.
  public subscript(key: String) -> Self? { objectValue?[key] }
}

extension JSONValue: ExpressibleByNilLiteral, ExpressibleByBooleanLiteral,
  ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral, ExpressibleByStringLiteral,
  ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral
{
  public init(nilLiteral _: ()) { self = .null }
  public init(booleanLiteral value: Bool) { self = .bool(value) }
  public init(integerLiteral value: Int) { self = .integer(value) }
  public init(floatLiteral value: Double) { self = .double(value) }
  public init(stringLiteral value: String) { self = .string(value) }
  public init(arrayLiteral elements: Self...) { self = .array(elements) }

  public init(dictionaryLiteral elements: (String, Self)...) {
    self = .object(Dictionary(elements) { _, last in last })
  }
}

extension JSONValue: Codable {
  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Int.self) {
      self = .integer(value)
    } else if let value = try? container.decode(Double.self) {
      self = .double(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([Self].self) {
      self = .array(value)
    } else {
      self = .object(try container.decode([String: Self].self))
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
      case .null: try container.encodeNil()
      case .bool(let value): try container.encode(value)
      case .integer(let value): try container.encode(value)
      case .double(let value): try container.encode(value)
      case .string(let value): try container.encode(value)
      case .array(let value): try container.encode(value)
      case .object(let value): try container.encode(value)
    }
  }
}
