import AuditWorkflow
import Corrections
import Foundation
import LogbookModel
import Review
import Testing

@Suite
struct `Review book` {
  private let changed = Finding(
    rule: "telemetry_time",
    recordIDs: [RecordID(rawValue: "A")],
    message: "In differs.",
    corrections: [
      CorrectionOption(
        title: "Use FlySto’s Time",
        changes: [
          FieldChange(
            flightKey: "key-A",
            recordID: RecordID(rawValue: "A"),
            field: .flightActualArrivalTime,
            old: .null,
            new: .date(utc("2026-10-12T15:25:00Z"))
          )
        ]
      )
    ]
  )
  private let seats = Finding(
    rule: "seat_time",
    recordIDs: [RecordID(rawValue: "D")],
    message: "PIC and SIC both fill total time.",
    corrections: [.flightSIC, .flightPIC].map { field in
      CorrectionOption(
        title: "Clear \(field.rawValue)",
        changes: [
          FieldChange(
            flightKey: "key-D",
            recordID: RecordID(rawValue: "D"),
            field: field,
            old: .integer(120),
            new: .integer(0)
          )
        ]
      )
    }
  )
  private let note = Finding(
    rule: "night_review",
    recordIDs: [RecordID(rawValue: "B")],
    message: ""
  )
  private let other = Finding(rule: "duplicate", recordIDs: [RecordID(rawValue: "C")], message: "")

  @Test
  func `restores the previous decisions it returns`() throws {
    var book = ReviewBook()
    book.decide(.falsePositive, for: [changed], note: "Logged right.")
    let original = book

    let previous = book.decide(.correction, for: [changed, note])
    for (id, record) in previous { book.set(record, for: id) }

    #expect(book == original)
  }

  @Test
  func `clears a finding decided unreviewed`() {
    var book = ReviewBook()
    book.decide(.correction, for: [changed])

    book.decide(.unreviewed, for: [changed])

    #expect(book.records.isEmpty)
  }

  @Test
  func `approves corrections through their only option or the one chosen`() {
    var book = ReviewBook()
    book.decide(.correction, for: [changed, note, seats])

    #expect(book.records[changed.id]?.correctionOptionID == changed.corrections[0].id)
    #expect(book.approved(in: [changed, note, seats, other]).map(\.option) == changed.corrections)

    book.decide(.correction, for: [seats], choosing: seats.corrections[1].id)

    #expect(
      book.approved(in: [changed, seats]).map(\.option) == [
        changed.corrections[0], seats.corrections[1]
      ]
    )
  }

  @Test
  func `finds the next unreviewed finding, wrapping around`() {
    var book = ReviewBook()
    book.decide(.needsEvidence, for: [note])
    let order = [changed.id, note.id, other.id]

    #expect(book.nextUnreviewed(after: changed.id, in: order) == other.id)
    #expect(book.nextUnreviewed(after: other.id, in: order) == changed.id)
    #expect(book.nextUnreviewed(after: other.id, in: order, forward: false) == changed.id)
    #expect(book.nextUnreviewed(after: nil, in: order) == changed.id)
  }

  @Test
  func `carries decisions forward only while the records are unchanged`() throws {
    let before = logbook([flight("A"), flight("B")])
    let previous = ReviewedAudit(findings: [changed, note], logbook: before, settings: .init())
    let decisions = [
      ReviewRecord(findingID: changed.id, decision: .correction, decidedAt: .now),
      ReviewRecord(findingID: note.id, decision: .falsePositive, decidedAt: .now)
    ]
    let after = logbook([flight("A"), flight("B", in: "2026-10-12T15:30:00Z")])
    let current = ReviewedAudit(findings: [changed, note], logbook: after, settings: .init())

    let (book, result) = ReviewBook.carriedForward(
      from: ReviewState(audit: previous, decisions: decisions),
      to: current
    )

    #expect(book.decision(for: changed.id) == .correction)
    #expect(book.decision(for: note.id) == .unreviewed)
    #expect(result?.history.map(\.outcome) == [.carried, .recordsOrEvidenceChanged])
  }
}

@Suite
struct `Finding export` {
  private let finding = Finding(
    rule: "telemetry_time",
    recordIDs: [RecordID(rawValue: "A")],
    message: "In is 10 minutes late, per “FlySto”, check it.",
    corrections: [
      CorrectionOption(
        title: "Use FlySto’s Time",
        changes: [
          FieldChange(
            flightKey: "key-A",
            recordID: RecordID(rawValue: "A"),
            field: .flightActualArrivalTime,
            old: .integer(5),
            new: .text("line one\nline \"two\"")
          )
        ]
      )
    ]
  )

  @Test
  func `writes a header and quotes fields that need it`() {
    var book = ReviewBook()
    book.decide(.correction, for: [finding], reason: .evidenceConfirms, note: "ok")
    let exporter = FindingExporter(
      findings: [finding],
      book: book,
      logbook: logbook([flight("A")])
    )

    let lines = exporter.csv().components(separatedBy: "\r\n")

    #expect(lines[0].hasPrefix("id,queue,rule,severity,flight_date,registration,flight_key"))
    #expect(
      lines[1]
        == "\(finding.id),aircraft_comparisons,telemetry_time,suggestion,2026-10-12,N111AA,key-A,A,"
        + "\"In is 10 minutes late, per “FlySto”, check it.\",,,"
        + "\"Use FlySto’s Time: flight_actualArrivalTime: 5 -> \"\"line one\\nline \\\"\"two\\\"\"\"\"\","
        + "\(finding.corrections[0].id),correction,evidence_confirms,ok,"
    )
  }

  @Test
  func `writes the same columns as JSON objects`() throws {
    let data = try FindingExporter(findings: [finding], book: ReviewBook(), logbook: nil).json()

    let objects = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    #expect(objects.first?["decision"] as? String == "unreviewed")
    #expect(objects.first?["record_ids"] as? [String] == ["A"])
    let corrections = try #require(objects.first?["corrections"] as? [[String: Any]])
    let changes = try #require(corrections.first?["changes"] as? [[String: String]])
    #expect(changes.first?["old"] == "5")
  }
}
