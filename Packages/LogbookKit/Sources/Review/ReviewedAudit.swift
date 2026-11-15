public import Foundation
public import LogbookModel

/**
 The audit run a set of review decisions was made against: its findings and the state of every
 record they involve.

 Decisions are only meaningful for the data they were made about. Keeping the record
 fingerprints alongside the findings lets the next run tell whether a decision still applies;
 see ``DecisionCarryForward``.
 */
public struct ReviewedAudit: Hashable, Codable, Sendable {
  /// The audit's identity.
  public var identity: AuditIdentity

  /// The findings the audit produced.
  public var findings: [Finding]

  /// The fingerprint of every record in the snapshot the audit read, including groups.
  public var recordFingerprints: [RecordID: RecordFingerprint]

  /// Creates a reviewed audit from its parts.
  public init(
    identity: AuditIdentity,
    findings: [Finding],
    recordFingerprints: [RecordID: RecordFingerprint]
  ) {
    self.identity = identity
    self.findings = findings
    self.recordFingerprints = recordFingerprints
  }

  /**
   Creates a reviewed audit for findings produced from a logbook snapshot.

   - Parameters:
     - findings: Every finding the audit produced.
     - logbook: The snapshot audited.
     - settings: The settings the audit ran with.
     - asOf: The date currency-dependent rules were evaluated for, if any.
   */
  public init(findings: [Finding], logbook: Logbook, settings: LogbookSettings, asOf: Date? = nil) {
    recordFingerprints = Self.fingerprints(of: logbook)
    self.findings = findings
    identity = AuditIdentity(
      storeUUID: logbook.identity.storeUUID,
      logbookFingerprint: Self.combinedFingerprint(recordFingerprints),
      settingsFingerprint: Self.fingerprint(of: settings),
      asOf: asOf,
      findingIDs: findings.map(\.id)
    )
  }

  /// The fingerprints of a logbook's records, with its groups fingerprinted by definition and
  /// membership.
  public static func fingerprints(of logbook: Logbook) -> [RecordID: RecordFingerprint] {
    var fingerprints = logbook.fingerprints
    for group in logbook.groups {
      fingerprints[group.id] = RecordFingerprint(rawValue: fingerprint(of: group))
    }
    return fingerprints
  }

  private static func combinedFingerprint(_ fingerprints: [RecordID: RecordFingerprint]) -> String {
    CanonicalJSON.sha256(
      of: .object(
        Dictionary(
          uniqueKeysWithValues: fingerprints.map { ($0.key.rawValue, .string($0.value.rawValue)) }
        )
      )
    )
  }

  /// The SHA-256 of a value's canonical JSON encoding, with every array sorted, since sets
  /// encode as arrays in no fixed order.
  static func fingerprint(of value: some Encodable) -> String {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .secondsSince1970
    guard let data = try? encoder.encode(value),
      let json = try? JSONDecoder().decode(JSONValue.self, from: data)
    else { preconditionFailure("Model values always encode as JSON") }
    return CanonicalJSON.sha256(of: unordered(json))
  }

  private static func unordered(_ value: JSONValue) -> JSONValue {
    switch value {
      case .array(let elements):
        .array(
          elements.map(unordered).sorted {
            CanonicalJSON.string(for: $0) < CanonicalJSON.string(for: $1)
          }
        )
      case .object(let members): .object(members.mapValues(unordered))
      default: value
    }
  }
}

/**
 Identifies one audit run: the logbook, its contents, the settings, the evaluation date and
 the findings produced.

 Two runs over the same snapshot with the same settings have the same identity. A decision
 export names the identity it was made against, so it can't be applied to a different run.
 */
public struct AuditIdentity: RawRepresentable, Hashable, Codable, Sendable,
  CustomStringConvertible
{
  public let rawValue: String

  public var description: String { rawValue }

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /**
   Derives an identity: the SHA-256 of the canonical JSON of its inputs.

   - Parameters:
     - storeUUID: The logbook's store UUID.
     - logbookFingerprint: A hash of every record in the snapshot.
     - settingsFingerprint: A hash of the settings the audit ran with.
     - asOf: The evaluation date, if the audit had one.
     - findingIDs: The findings the audit produced, in report order.
   */
  public init(
    storeUUID: UUID,
    logbookFingerprint: String,
    settingsFingerprint: String,
    asOf: Date?,
    findingIDs: [FindingID]
  ) {
    rawValue = CanonicalJSON.sha256(of: [
      "source": .string(storeUUID.uuidString),
      "book": .string(logbookFingerprint),
      "config": .string(settingsFingerprint),
      "as_of": asOf.map { .double($0.timeIntervalSince1970) } ?? .null,
      "findings": .array(findingIDs.map { .string($0.rawValue) })
    ])
  }
}
