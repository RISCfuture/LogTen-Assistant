/**
 A problem or question about one or more logbook records, produced by an audit or regulation
 rule.

 A finding's ``id`` is content-addressed: it is derived from the rule, the records involved and
 the evidence, so re-running an audit over unchanged data yields the same identifiers, and
 review decisions can carry forward. New evidence produces a new identifier. The severity,
 texts and corrections are not part of the identifier.

 A finding offers zero or more ``corrections``, alternative ways of resolving it from which the
 reviewer picks one. When a flight a correction would change is signed or locked, the
 correction can't be applied through LogTen's import, and ``correctionRestriction`` says why;
 approving it adds the change to the manual checklist instead.
 */
public struct Finding: Identifiable, Hashable, Codable, Sendable {
  /// The content-addressed identifier.
  public let id: FindingID

  /// The rule that produced the finding.
  public let rule: RuleID

  /// The records involved, sorted.
  public let recordIDs: [RecordID]

  /// How serious the problem is.
  public var severity: Severity

  /// A localized, one-line description of the problem.
  public var message: String

  /// A localized paragraph on why the data is questioned, if the rule gives one.
  public var explanation: String?

  /// A localized paragraph on what the pilot should do about it, if the rule gives one.
  public var recommendation: String?

  /// The data the rule based its conclusion on.
  public let evidence: JSONValue

  /// The alternative ways of resolving the finding, in the order to offer them.
  public var corrections: [CorrectionOption]

  /// Why the corrections can only be made by hand in LogTen, if a flight they involve is signed
  /// or locked.
  public var correctionRestriction: CorrectionRestriction?

  /// The regulation or document that supports the rule, such as “14 CFR 61.57(c)”.
  public var citation: String?

  /**
   Creates a finding and derives its identifier.

   - Parameters:
     - rule: The rule that produced the finding.
     - recordIDs: The records involved, in any order.
     - message: A localized one-line description of the problem.
     - evidence: The data the conclusion is based on; an empty object if there is none.
     - severity: How serious the problem is.
     - explanation: Why the data is questioned.
     - recommendation: What the pilot should do about it.
     - corrections: Alternative ways of resolving the finding.
     - citation: The supporting regulation or document.
   */
  public init(
    rule: RuleID,
    recordIDs: some Sequence<RecordID>,
    message: String,
    evidence: JSONValue = [:],
    severity: Severity = .suggestion,
    explanation: String? = nil,
    recommendation: String? = nil,
    corrections: [CorrectionOption] = [],
    citation: String? = nil
  ) {
    let sortedIDs = recordIDs.sorted()
    id = FindingID(rule: rule, recordIDs: sortedIDs, evidence: evidence)
    self.rule = rule
    self.recordIDs = sortedIDs
    self.severity = severity
    self.message = message
    self.explanation = explanation
    self.recommendation = recommendation
    self.evidence = evidence
    self.corrections = corrections
    self.citation = citation
  }

  /// Decodes a finding; a missing correction list decodes as empty.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(FindingID.self, forKey: .id)
    rule = try container.decode(RuleID.self, forKey: .rule)
    recordIDs = try container.decode([RecordID].self, forKey: .recordIDs)
    severity = try container.decode(Severity.self, forKey: .severity)
    message = try container.decode(String.self, forKey: .message)
    explanation = try container.decodeIfPresent(String.self, forKey: .explanation)
    recommendation = try container.decodeIfPresent(String.self, forKey: .recommendation)
    evidence = try container.decode(JSONValue.self, forKey: .evidence)
    corrections =
      try container.decodeIfPresent([CorrectionOption].self, forKey: .corrections) ?? []
    correctionRestriction = try container.decodeIfPresent(
      CorrectionRestriction.self,
      forKey: .correctionRestriction
    )
    citation = try container.decodeIfPresent(String.self, forKey: .citation)
  }

  /// The correction option with an identifier, if the finding offers it.
  public func correction(_ id: CorrectionOptionID?) -> CorrectionOption? {
    corrections.first { $0.id == id }
  }

  /**
   The finding as it applies to flights that may be signed or locked: with the reason its
   corrections can only be made by hand, when any flight it involves or would change is
   protected. The corrections stay, so the reviewer sees the values to enter.

   - Parameter flights: The logbook's flights, by identifier.
   - Returns: The finding, restricted if it offers corrections and a flight it touches is signed
     or locked.
   */
  public func markingCorrectionRestriction(on flights: [RecordID: Flight]) -> Self {
    guard !corrections.isEmpty else { return self }
    let touched = recordIDs + corrections.flatMap { $0.changes.map(\.recordID) }
    let protected = touched.compactMap { flights[$0] }
    guard let restriction = CorrectionRestriction(protecting: protected) else { return self }
    var restricted = self
    restricted.correctionRestriction = restriction
    return restricted
  }

  private enum CodingKeys: String, CodingKey {
    case id, rule, recordIDs, severity, message, explanation, recommendation, evidence
    case corrections, correctionRestriction, citation
  }
}

/// The content-addressed identifier of a ``Finding``.
///
/// The identifier is the first 20 hexadecimal digits of the SHA-256 digest of the canonical JSON
/// array `[rule, sortedRecordIDs, evidence]`, the same derivation cleanup-logten's
/// `util.finding` uses.
public struct FindingID: RawRepresentable, Hashable, Comparable, Codable, Sendable,
  CustomStringConvertible
{
  private static let length = 20

  public let rawValue: String

  public var description: String { rawValue }

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// Derives the identifier for a rule, its records and its evidence.
  public init(rule: RuleID, recordIDs: [RecordID], evidence: JSONValue) {
    let ids = recordIDs.sorted().map { JSONValue.string($0.rawValue) }
    let digest = CanonicalJSON.sha256(of: [.string(rule.rawValue), .array(ids), evidence])
    rawValue = String(digest.prefix(Self.length))
  }

  public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// How serious a finding is.
public enum Severity: String, CaseIterable, Comparable, Codable, Sendable {
  /// The entry is unusual or incomplete, and worth a look.
  case suggestion
  /// The entry is probably wrong.
  case questionable
  /// The entry is certainly wrong.
  case discrepancy

  private static let formerNames: [String: Self] = [
    "review": .suggestion,
    "probable": .questionable,
    "warning": .questionable,
    "error": .discrepancy
  ]

  private var rank: Int {
    switch self {
      case .suggestion: 0
      case .questionable: 1
      case .discrepancy: 2
    }
  }

  /// Decodes a severity, reading the tiers' former names: `review` as ``suggestion``, `probable`
  /// and `warning` as ``questionable``, and `error` as ``discrepancy``.
  public init(from decoder: any Decoder) throws {
    let name = try decoder.singleValueContainer().decode(String.self)
    guard let severity = Self(rawValue: name) ?? Self.formerNames[name] else {
      throw DecodingError.dataCorrupted(
        .init(codingPath: decoder.codingPath, debugDescription: "Unknown severity “\(name)”")
      )
    }
    self = severity
  }

  public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rank < rhs.rank }
}

/// A proposed edit to one field of one logbook record.
public struct FieldChange: Hashable, Codable, Sendable {
  /// LogTen's import key for the flight, which a `logten://` package needs to address the
  /// entry; `nil` for records that have none.
  public var flightKey: String?

  /// The record to change.
  public var recordID: RecordID

  /// The field to change.
  public var field: LogTenFieldKey

  /// The value the record holds now, which must still match before the change is applied.
  public var old: FieldValue

  /// The value to write.
  public var new: FieldValue

  /// The change as canonical JSON, for content-addressed identifiers.
  public var canonicalJSON: JSONValue {
    [
      "flightKey": flightKey.map(JSONValue.string) ?? .null,
      "recordID": .string(recordID.rawValue),
      "field": .string(field.rawValue),
      "old": old.jsonValue,
      "new": new.jsonValue
    ]
  }

  /// Creates a field change.
  public init(
    flightKey: String?,
    recordID: RecordID,
    field: LogTenFieldKey,
    old: FieldValue,
    new: FieldValue
  ) {
    self.flightKey = flightKey
    self.recordID = recordID
    self.field = field
    self.old = old
    self.new = new
  }
}
