/// The stable identifier of a record in a LogTen logbook.
///
/// LogTen gives every record a unique ID (`logTen_uniqueID`), which survives sync and is the
/// same on every device. Records without one are identified by their SQLite primary key as
/// `pk:<number>`, which is only stable within one store.
public struct RecordID: RawRepresentable, Hashable, Comparable, Codable, CodingKeyRepresentable,
  Sendable,
  CustomStringConvertible
{
  public let rawValue: String

  public var description: String { rawValue }

  /// Creates an identifier from LogTen's unique ID or a `pk:` fallback.
  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// Creates the fallback identifier for a record without a LogTen unique ID.
  ///
  /// - Parameter primaryKey: The record's SQLite primary key.
  public init(primaryKey: Int64) {
    rawValue = "pk:\(primaryKey)"
  }

  /// Orders identifiers by Unicode code point, matching Python's string ordering.
  public static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.rawValue.unicodeScalars.lexicographicallyPrecedes(rhs.rawValue.unicodeScalars)
  }
}

/// The identifier of an audit or regulation rule, such as `duplicate_flight` or `far_61_56`.
///
/// Rule identifiers key findings, disabled-rule settings and review decisions, so they must not
/// change once a rule has shipped.
public struct RuleID: RawRepresentable, Hashable, Comparable, Codable, Sendable,
  CustomStringConvertible, ExpressibleByStringLiteral
{
  public let rawValue: String

  public var description: String { rawValue }

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  public init(stringLiteral value: String) {
    rawValue = value
  }

  public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}
