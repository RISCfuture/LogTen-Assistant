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

  func finding(_ id: RecordID, night: Int = 30, old: Int = 60, rule: RuleID = "night_time")
    -> Finding
  {
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
              old: .integer(old),
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
  func `proposes a finding approved twice once and keeps the reviewer's note`() throws {
    let finding = sample.finding("keyed")
    let approval = ApprovedCorrection(finding: finding, option: finding.corrections[0])
    let proposal = try CorrectionProposal(
      approving: [approval, approval],
      notes: [finding.id: "Checked the paper log"],
      logbook: sample.logbook
    )

    #expect(proposal.operations.count == 1)
    #expect(proposal.operations[0].note == "Checked the paper log")
    #expect(
      proposal.operations[0].recordFingerprints == ["keyed": RecordFingerprint(rawValue: "v1")]
    )
  }

  @Test
  func `identifies operations by finding and chosen changes`() throws {
    var finding = sample.finding("keyed")
    finding.corrections.append(sample.finding("keyed", night: 20).corrections[0])
    func operation(_ option: CorrectionOption) throws -> CorrectionOperation {
      try #require(
        CorrectionProposal(
          approving: [ApprovedCorrection(finding: finding, option: option)],
          logbook: sample.logbook
        )
        .operations.first
      )
    }
    let first = try operation(finding.corrections[0])
    let second = try operation(finding.corrections[1])

    #expect(first.findingID == second.findingID)
    #expect(first.id == (try operation(finding.corrections[0])).id)
    #expect(first.id != second.id)
  }

  @Test
  func `excludes operations whose flight vanished or that change nothing`() throws {
    var current = sample.logbook
    current.flights.removeAll { $0.id == "keyed" }
    current.fingerprints["keyed"] = nil
    #expect(
      try check([sample.finding("keyed")], against: current).excluded.first?.issues == [
        .recordMissing("keyed")
      ]
    )

    var empty = sample.finding("keyed")
    empty.corrections = [CorrectionOption(title: "Nothing", changes: [])]
    #expect(try check([empty]).excluded.first?.issues == [.noChanges])
  }

  @Test
  func `excludes changes to fields outside the import allowlist or to a changed flight key`() throws
  {
    var finding = sample.finding("keyed")
    finding.corrections = [
      CorrectionOption(
        title: "Ground",
        changes: [
          FieldChange(
            flightKey: "KEY-keyed",
            recordID: "keyed",
            field: .flightGround,
            old: .integer(0),
            new: .integer(5)
          ),
          FieldChange(
            flightKey: "OTHER",
            recordID: "keyed",
            field: .flightNight,
            old: .integer(60),
            new: .integer(30)
          )
        ]
      )
    ]
    #expect(
      try check([finding]).excluded.first?.issues == [
        .fieldNotImportable(.flightGround), .flightKeyChanged("keyed")
      ]
    )
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
  func `excludes flights that changed after approval, even locked ones`() throws {
    var current = sample.logbook
    for (index, id) in [(0, "keyed"), (2, "locked")] {
      current.fingerprints[RecordID(rawValue: id)] = RecordFingerprint(rawValue: "v2")
      current.flights[index].times.night = 45
    }

    let result = try check([sample.finding("keyed"), sample.finding("locked")], against: current)
    #expect(result.ready.isEmpty)
    #expect(
      result.excluded.first?.issues == [
        .recordChanged("keyed"), .oldValueMismatch("keyed", .flightNight, current: .integer(45))
      ]
    )
    #expect(result.checklist.items.map { $0.instruction.contains("audit again") } == [true, true])
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

    let otherwiseExcluded = try check([
      sample.finding("keyed", night: 30), sample.finding("keyed", night: 20, old: 59, rule: "other")
    ])
    #expect(otherwiseExcluded.ready.count == 1)
    #expect(
      otherwiseExcluded.excluded.map(\.issues) == [
        [.oldValueMismatch("keyed", .flightNight, current: .integer(60))]
      ]
    )
  }

  @Test
  func `matches old values the way LogTen stores them`() {
    let date = Date(timeIntervalSinceReferenceDate: 800_000_000)
    var logbook = sample.logbook
    logbook.flights[0].date = date
    logbook.flights[0].times.night = 0
    logbook.flights[0].hobbsStart = Double(Float(1233.4))
    func change(_ field: LogTenFieldKey, old: FieldValue, new: FieldValue) -> FieldChange {
      FieldChange(flightKey: "KEY-keyed", recordID: "keyed", field: field, old: old, new: new)
    }

    let matching = Preflight.check(
      [
        change(.flightNight, old: .null, new: .integer(30)),
        change(.flightDate, old: .date(date.addingTimeInterval(0.0005)), new: .null),
        change(.flightHobbsStart, old: .number(1233.4), new: .number(1240))
      ],
      against: logbook
    )
    #expect(matching == [[], [], []])

    let outside = Preflight.check(
      [change(.flightDate, old: .date(date.addingTimeInterval(1)), new: .null)],
      against: logbook
    )
    #expect(outside == [[.oldValueMismatch("keyed", .flightDate, current: .date(date))]])
  }

  @Test
  func `checks compensating changes against the flights as they are now`() {
    let reverts = CorrectionBatch(
      changes: ["keyed", "locked", "signed"].map {
        FieldChange(
          flightKey: "KEY-\($0)",
          recordID: RecordID(rawValue: $0),
          field: .flightNight,
          old: .integer(60),
          new: .integer(30)
        )
      }
    ).compensating
    var applied = sample.logbook
    for index in applied.flights.indices
    where ["keyed", "locked", "signed"].contains(applied.flights[index].id.rawValue) {
      applied.flights[index].times.night = 30
    }

    #expect(
      Preflight.check(reverts.changes, against: applied) == [
        [], [.locked("locked")], [.signed("signed")]
      ]
    )
    #expect(
      Preflight.check(reverts.changes, against: sample.logbook).first == [
        .oldValueMismatch("keyed", .flightNight, current: .integer(60))
      ]
    )
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
struct `Manual checklist` {
  private let sample = NightLogbook()

  private func change(_ field: LogTenFieldKey, old: FieldValue, new: FieldValue) -> FieldChange {
    FieldChange(flightKey: "KEY-keyed", recordID: "keyed", field: field, old: old, new: new)
  }

  /// The checklist items for changes to the keyed flight, which is excluded for being locked.
  private func items(_ changes: [FieldChange], logbook: Logbook? = nil) -> [ManualChecklistItem] {
    let logbook = logbook ?? sample.logbook
    var finding = sample.finding("keyed")
    finding.corrections = [CorrectionOption(title: "Fix", changes: changes)]
    let operation = CorrectionOperation(
      approval: ApprovedCorrection(finding: finding, option: finding.corrections[0]),
      logbook: logbook
    )
    return ManualChecklist(
      excluded: [ExcludedOperation(operation: operation, issues: [.locked("keyed")])],
      logbook: logbook
    ).items
  }

  @Test
  func `describes the flight and titles the field as the logbook does`() {
    let custom = LogTenFieldKey.custom(.flightTime, 3)
    var logbook = sample.logbook
    logbook.flights[0].aircraft = Aircraft(id: "AC", registration: "N123")
    logbook.flights[0].from = Place(id: "P1", identifier: "KSQL", ICAO: "KSQL")
    logbook.flights[0].to = Place(id: "P2", identifier: "O85")
    logbook.customFields = [CustomFieldDefinition(key: custom, title: "Night IFR")]
    let described = items(
      [
        change(custom, old: .integer(10), new: .integer(20)),
        change(.flightNight, old: .integer(60), new: .integer(30))
      ],
      logbook: logbook
    )

    #expect(described.map(\.fieldTitle) == ["Night IFR", "night"])
    #expect(described.allSatisfy { $0.route == "KSQL–O85" })
    #expect(described.allSatisfy { $0.registration == "N123" })
    #expect(described.allSatisfy { $0.flightDate == logbook.flights[0].date })

    logbook.flights[0].from = nil
    logbook.flights[0].to = nil
    #expect(items([change(.flightNight, old: .null, new: .null)], logbook: logbook)[0].route == nil)
  }

  @Test
  func `shows values as LogTen displays them`() {
    let date = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let shown = items([
      change(.flightNight, old: .integer(75), new: .null),
      change(.flightFullStops, old: .integer(1200), new: .integer(1300)),
      change(.flightRemarks, old: .null, new: .text("Night")),
      change(.flightHobbsStart, old: .number(12), new: .number(13)),
      change(.flightIsLocked, old: .boolean(true), new: .boolean(false)),
      change(.flightDate, old: .date(date), new: .null)
    ])

    #expect(shown.map(\.oldValue) == ["1:15", "1200", "None", "12", "Yes", "2026-05-09T06:13:20"])
    #expect(shown.map(\.newValue) == ["None", "1300", "Night", "13", "No", "None"])
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

  private func nightBatch(_ ids: [RecordID], to night: Int = 30) -> CorrectionBatch {
    CorrectionBatch(
      changes: ids.map {
        FieldChange(
          flightKey: "KEY-\($0.rawValue)",
          recordID: $0,
          field: .flightNight,
          old: .integer(60),
          new: .integer(night)
        )
      }
    )
  }

  private func flights(_ ids: [RecordID]) -> [Flight] {
    ids.map {
      var flight = Flight(id: $0, date: Self.day, flightKey: "KEY-\($0.rawValue)")
      flight.times = FlightTimes(total: 60, night: 60)
      return flight
    }
  }

  private func logbook(_ flights: [Flight]) -> Logbook {
    Logbook(identity: LogbookIdentity(storeUUID: UUID()), flights: flights)
  }

  @Test
  func `report flights that appeared or vanished`() {
    let before = logbook(flights(["F1", "F2"]))
    var current = logbook(flights(["F1", "F3"]))
    current.flights[0].times.night = 30

    let verification = BatchVerifier.verify(nightBatch(["F1"]), before: before, current: current)

    #expect(verification.issues == [.flightsAdded(["F3"]), .flightsRemoved(["F2"])])
  }

  @Test
  func `refuse batch flights that were locked, signed or rekeyed after import`() {
    let ids: [RecordID] = ["F1", "F2", "F3", "F4", "F5"]
    let before = logbook(flights(ids))
    var current = before
    current.flights.indices.forEach { current.flights[$0].times.night = 30 }
    current.flights[0].isLocked = true
    current.flights[1].isSigned = true
    current.flights[2].flightKey = "OTHER"
    current.flights[4].flightKey = "KEY-F4"

    let issues = BatchVerifier.verify(nightBatch(ids), before: before, current: current).issues

    #expect(issues.contains(.batchFlightProtected("F1")))
    #expect(issues.contains(.batchFlightProtected("F2")))
    #expect(issues.contains(.flightKeyChanged("F3")))
    #expect(issues.contains(.flightKeyNotUnique("F4")))
    #expect(issues.contains(.flightKeyNotUnique("F5")))
  }

  @Test
  func `expect the fields of earlier applied batches to hold their new values`() {
    let before = logbook(flights(["F1"]))
    var current = before
    current.flights[0].times.night = 30
    current.flights[0].times.total = 45
    let earlier = nightBatch(["F1"])
    let batch = CorrectionBatch(changes: [
      FieldChange(
        flightKey: "KEY-F1",
        recordID: "F1",
        field: .flightTotalTime,
        old: .integer(60),
        new: .integer(45)
      )
    ])

    #expect(
      BatchVerifier.verify(batch, after: [earlier], before: before, current: current).isVerified
    )
    #expect(
      BatchVerifier.verify(batch, before: before, current: current).issues == [
        .unexpectedValue("F1", .flightNight, expected: .integer(60), found: .integer(30))
      ]
    )
  }

  @Test
  func `recognise an applied batch by its flights' values, treating cleared minutes as zero`() {
    let clearing = CorrectionBatch(changes: [
      FieldChange(
        flightKey: "KEY-F1",
        recordID: "F1",
        field: .flightNight,
        old: .integer(60),
        new: .null
      )
    ])
    var stored = flights(["F1"])
    #expect(!BatchVerifier.isApplied(clearing, in: logbook(stored)))

    stored[0].times.night = 0
    #expect(BatchVerifier.isApplied(clearing, in: logbook(stored)))
    #expect(!BatchVerifier.isApplied(clearing, in: logbook([])))
  }
}

extension RecordID: ExpressibleByStringLiteral {
  init(stringLiteral value: String) { self.init(rawValue: value) }
}
