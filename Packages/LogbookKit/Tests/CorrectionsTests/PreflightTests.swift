import Corrections
import Foundation
import LogbookModel
import Testing

/// An in-memory logbook of keyed, keyless, locked and signed flights, each logging 60 minutes of
/// night time that findings propose to change to 30.
private struct NightLogbook {
  static let ids = ["keyed", "keyless", "locked", "signed", "twin-1", "twin-2"].map {
    RecordID(rawValue: $0)
  }

  var logbook: Logbook

  init() {
    let flights = Self.ids.map { id in
      var flight = Flight(id: id, date: .now, flightKey: "KEY-\(id.rawValue)")
      flight.times = FlightTimes(total: 60, night: 60)
      switch id.rawValue {
        case "keyless": flight.flightKey = nil
        case "locked": flight.isLocked = true
        case "signed": flight.isSigned = true
        case "twin-1", "twin-2": flight.flightKey = "KEY-twin"
        default: break
      }
      return flight
    }
    logbook = Logbook(
      identity: LogbookIdentity(storeUUID: UUID()),
      flights: flights,
      fingerprints: Dictionary(
        uniqueKeysWithValues: Self.ids.map { ($0, RecordFingerprint(rawValue: "v1")) }
      )
    )
  }

  func finding(_ id: RecordID, night: Int = 30, rule: RuleID = "night_time") -> Finding {
    let flight = logbook.flights.first { $0.id == id }!
    return Finding(
      rule: rule,
      recordIDs: [id],
      message: "Night time is wrong.",
      evidence: ["night": .integer(night)],
      corrections: [
        CorrectionOption(
          title: "Correct Night",
          changes: [
            FieldChange(
              flightKey: flight.flightKey,
              recordID: id,
              field: .flightNight,
              old: .integer(60),
              new: .integer(night)
            )
          ]
        )
      ]
    )
  }
}

@Suite
struct `Correction preflight` {
  private let sample = NightLogbook()

  private func check(_ findings: [Finding], against logbook: Logbook? = nil) throws
    -> PreflightResult
  {
    let proposal = try CorrectionProposal(
      approving: findings.map { ApprovedCorrection(finding: $0, option: $0.corrections[0]) },
      logbook: sample.logbook
    )
    return Preflight.check(proposal, against: logbook ?? sample.logbook)
  }

  @Test
  func `requires an explicit selection`() {
    #expect(throws: CorrectionError.emptySelection) {
      try CorrectionProposal(approving: [], logbook: sample.logbook)
    }
  }

  @Test
  func `excludes keyless, locked, signed and ambiguously keyed flights`() throws {
    let result = try check(NightLogbook.ids.map { sample.finding($0) })

    #expect(result.ready.map(\.recordIDs) == [[RecordID(rawValue: "keyed")]])
    let issues = Dictionary(
      uniqueKeysWithValues: result.excluded.map { ($0.operation.recordIDs[0].rawValue, $0.issues) }
    )
    #expect(issues["keyless"] == [.missingFlightKey("keyless")])
    #expect(issues["locked"] == [.locked("locked")])
    #expect(issues["signed"] == [.signed("signed")])
    #expect(issues["twin-1"] == [.flightKeyNotUnique("twin-1")])
  }

  @Test
  func `excludes flights that changed after approval`() throws {
    var current = sample.logbook
    current.fingerprints[RecordID(rawValue: "keyed")] = RecordFingerprint(rawValue: "v2")
    current.flights[0].times.night = 45

    let result = try check([sample.finding("keyed")], against: current)
    #expect(result.ready.isEmpty)
    #expect(
      result.excluded.first?.issues == [
        .recordChanged("keyed"), .oldValueMismatch("keyed", .flightNight, current: .integer(45))
      ]
    )
  }

  @Test
  func `excludes findings that set the same field differently`() throws {
    let result = try check([sample.finding("keyed", night: 30), sample.finding("keyed", night: 20)])
    #expect(result.ready.isEmpty)
    #expect(result.excluded.allSatisfy { $0.issues == [.conflictingChange("keyed", .flightNight)] })

    let agreeing = try check([
      sample.finding("keyed", night: 30), sample.finding("keyed", night: 30, rule: "other")
    ])
    #expect(agreeing.ready.count == 2)
    #expect(agreeing.readyChanges.count == 1)
  }

  @Test
  func `routes excluded changes to a manual checklist with copyable values`() throws {
    let result = try check(
      ["keyless", "locked", "signed"].map { sample.finding(RecordID(rawValue: $0)) }
    )
    let items = result.checklist.items

    #expect(items.map(\.oldValue) == ["1:00", "1:00", "1:00"])
    #expect(items.map(\.newValue) == ["0:30", "0:30", "0:30"])
    #expect(
      items.map(\.issues) == [
        [.missingFlightKey("keyless")], [.locked("locked")], [.signed("signed")]
      ]
    )
    #expect(items[0].instruction.contains("Flight Audit"))
    #expect(items[1].instruction.contains("lock it again"))
    #expect(items[2].instruction.contains("signature"))
    #expect(items[2].instruction.contains("iPhone or iPad"))
  }
}

@Suite
struct `Batch verification side effects` {
  private static let day = Date(timeIntervalSinceReferenceDate: 800_006_400)
  private static let takeoff = day.addingTimeInterval(15 * 3600)
  private static let duration = LogTenFieldKey(.flight, "duration")

  private func logbook(_ flight: Flight) -> Logbook {
    Logbook(identity: LogbookIdentity(storeUUID: UUID()), flights: [flight])
  }

  @Test
  func `allow LogTen's date anchoring and airborne duration for untimed entries only`() {
    let original = Flight(id: "F1", date: Self.day, flightKey: "KEY-1")
    let landing = Self.takeoff.addingTimeInterval(3600)
    let batch = CorrectionBatch(changes: [
      FieldChange(
        flightKey: "KEY-1",
        recordID: "F1",
        field: .flightTakeoffTime,
        old: .null,
        new: .date(Self.takeoff)
      ),
      FieldChange(
        flightKey: "KEY-1",
        recordID: "F1",
        field: .flightLandingTime,
        old: .null,
        new: .date(landing)
      )
    ])
    var imported = original
    imported.events.off = Self.takeoff
    imported.events.on = landing
    imported.date = Self.takeoff
    imported[field: Self.duration] = .integer(60)

    let verification = BatchVerifier.verify(
      batch,
      before: logbook(original),
      current: logbook(imported)
    )
    #expect(verification.isVerified)
    #expect(
      verification.observedChanges.filter(\.isSideEffect).map(\.field) == [
        Self.duration, .flightDate
      ]
    )

    var timed = original
    timed.events.out = Self.takeoff.addingTimeInterval(-600)
    var timedImport = imported
    timedImport.events.out = timed.events.out
    let refused = BatchVerifier.verify(batch, before: logbook(timed), current: logbook(timedImport))
    #expect(
      refused.issues == [
        .unexpectedValue("F1", .flightDate, expected: .date(Self.day), found: .date(Self.takeoff))
      ]
    )
  }

  @Test
  func `treat cleared minutes as zero and allow the fields LogTen derives from the change`() {
    var original = Flight(id: "F1", date: Self.day, flightKey: "KEY-1")
    original.times = FlightTimes(total: 60, PIC: 60, SIC: 0, night: 60)
    original[field: .flightPICNight] = .integer(60)
    original[field: .flightSICNight] = .integer(30)
    original[field: LogTenFieldKey(.flight, "category1")] = .integer(60)
    let batch = CorrectionBatch(changes: [
      FieldChange(
        flightKey: "KEY-1",
        recordID: "F1",
        field: .flightTotalTime,
        old: .integer(60),
        new: .integer(30)
      ),
      FieldChange(
        flightKey: "KEY-1",
        recordID: "F1",
        field: .flightSICNight,
        old: .integer(30),
        new: .null
      ),
      FieldChange(
        flightKey: "KEY-1",
        recordID: "F1",
        field: .flightSIC,
        old: .integer(0),
        new: .integer(30)
      )
    ])
    var imported = original
    imported.times.total = 30
    imported.times.SIC = 30
    imported[field: .flightSICNight] = .integer(0)
    imported[field: LogTenFieldKey(.flight, "category1")] = .integer(30)
    imported[field: LogTenFieldKey(.flight, "sicCapacity")] = .boolean(true)
    imported[field: LogTenFieldKey(.flight, "specialNightFlags")] = .integer(3)

    let verification = BatchVerifier.verify(
      batch,
      before: logbook(original),
      current: logbook(imported)
    )

    #expect(verification.issues.isEmpty)
    #expect(
      Set(verification.observedChanges.filter(\.isSideEffect).map(\.field.rawValue)) == [
        "flight_category1", "flight_sicCapacity", "flight_specialNightFlags"
      ]
    )

    var unexplained = imported
    unexplained[field: LogTenFieldKey(.flight, "picCapacity")] = .boolean(true)
    let refused = BatchVerifier.verify(
      batch,
      before: logbook(original),
      current: logbook(unexplained)
    )
    #expect(refused.issues.count == 1)
  }

  @Test
  func `compare numbers at the precision LogTen stores`() {
    let original = Flight(id: "F1", date: Self.day, flightKey: "KEY-1")
    let batch = CorrectionBatch(changes: [
      FieldChange(
        flightKey: "KEY-1",
        recordID: "F1",
        field: .flightHobbsStart,
        old: .null,
        new: .number(1233.4)
      )
    ])
    var imported = original
    imported.hobbsStart = Double(Float(1233.4))

    let verification = BatchVerifier.verify(
      batch,
      before: logbook(original),
      current: logbook(imported)
    )

    #expect(verification.isVerified)
  }
}

extension RecordID: ExpressibleByStringLiteral {
  init(stringLiteral value: String) { self.init(rawValue: value) }
}
