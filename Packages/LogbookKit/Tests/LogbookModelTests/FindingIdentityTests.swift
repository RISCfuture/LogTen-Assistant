import Foundation
import LogbookModel
import Testing

@Suite
struct `Finding identity` {
  /// Evidence exercising key ordering, number forms and string escaping. The expected values
  /// were produced by cleanup-logten's `util.stable_hash` and `util.finding`.
  private let evidence: JSONValue = [
    "zeta": [1, 2.5, nil, true],
    "alpha": "Café 🛩 \"q\" \\ \n\t\u{01}\u{7F}/",
    "Beta": ["n": 5.0, "m": -3, "big": 1e16, "small": 1e-05]
  ]

  @Test
  func `serializes canonical JSON exactly as Python's json module does`() {
    #expect(
      CanonicalJSON.string(for: evidence)
        == #"{"Beta":{"big":1e+16,"m":-3,"n":5.0,"small":1e-05},"alpha":"Caf\u00e9 \ud83d\udee9 \"q\" \\ \n\t\u0001\u007f/","zeta":[1,2.5,null,true]}"#
    )
  }

  @Test
  func `derives the same identifier as cleanup-logten`() {
    let finding = Finding(
      rule: "duplicate_flight",
      recordIDs: ["b-2", "a-1", "pk:10"].map(RecordID.init(rawValue:)),
      message: "Duplicate",
      evidence: evidence
    )
    #expect(finding.id.rawValue == "f246fa78434fb3e9d89c")
    #expect(finding.recordIDs.map(\.rawValue) == ["a-1", "b-2", "pk:10"])
  }

  @Test
  func `uses an empty object when there is no evidence`() {
    let finding = Finding(
      rule: "duplicate_flight",
      recordIDs: [RecordID(rawValue: "a-1"), RecordID(rawValue: "b-2"), RecordID(primaryKey: 10)],
      message: "Duplicate"
    )
    #expect(finding.id.rawValue == "14528121a896bb7c85c9")
  }

  @Test
  func `changes identifier when evidence changes`() {
    let records = [RecordID(rawValue: "a-1")]
    let first = Finding(rule: "night", recordIDs: records, message: "", evidence: ["minutes": 30])
    let second = Finding(rule: "night", recordIDs: records, message: "", evidence: ["minutes": 31])
    #expect(first.id != second.id)
  }
}

@Suite
struct `Correction options` {
  private static let first = RecordID(rawValue: "F1")
  private static let second = RecordID(rawValue: "F2")

  private static func clear(_ field: LogTenFieldKey, on id: RecordID) -> FieldChange {
    FieldChange(flightKey: "key", recordID: id, field: field, old: .integer(120), new: .integer(0))
  }

  @Test
  func `are identified by their changes alone`() {
    let changes = [Self.clear(.flightSIC, on: Self.first)]

    #expect(
      CorrectionOption(title: "Clear SIC", changes: changes).id
        == CorrectionOption(title: "Remove SIC", detail: "SIC is cleared", changes: changes).id
    )
    #expect(
      CorrectionOption(title: "Clear SIC", changes: changes).id
        != CorrectionOption(title: "Clear SIC", changes: [Self.clear(.flightPIC, on: Self.first)])
        .id
    )
  }

  @Test
  func `keep their options when restricted by a signed or locked flight, signed first`() {
    let finding = Finding(
      rule: "seat_time",
      recordIDs: [Self.first, Self.second],
      message: "",
      corrections: [
        CorrectionOption(title: "Clear SIC", changes: [Self.clear(.flightSIC, on: Self.first)])
      ]
    )
    var signed = Flight(id: Self.first, date: .now)
    signed.isSigned = true
    var locked = Flight(id: Self.second, date: .now)
    locked.isLocked = true
    let open = Flight(id: Self.second, date: .now)

    let restricted = finding.markingCorrectionRestriction(on: [
      Self.first: signed, Self.second: locked
    ])
    #expect(restricted.corrections == finding.corrections)
    #expect(restricted.correctionRestriction == .signed)
    #expect(restricted.id == finding.id)
    #expect(
      finding.markingCorrectionRestriction(on: [Self.second: locked]).correctionRestriction
        == .locked
    )
    #expect(finding.markingCorrectionRestriction(on: [Self.second: open]) == finding)

    let informational = Finding(rule: "seat_time", recordIDs: [Self.first], message: "")
    #expect(informational.markingCorrectionRestriction(on: [Self.first: signed]) == informational)
  }

  @Test
  func `read the severity tiers' former names`() throws {
    let decoded = try JSONDecoder().decode(
      [Severity].self,
      from: Data(#"["review", "probable", "error", "warning"]"#.utf8)
    )
    #expect(decoded == [.suggestion, .questionable, .discrepancy, .questionable])
  }
}
