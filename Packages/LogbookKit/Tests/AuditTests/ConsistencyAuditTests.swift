@testable import Audit
import Foundation
import LogbookModel
import Testing

@Suite
struct `Consistency audit` {
  private typealias Fixtures = ConsistencyFixtures

  private func run(
    _ flights: [Flight],
    settings: LogbookSettings = Fixtures.settings,
    options: ConsistencyAuditOptions = .init()
  ) -> ConsistencyAuditResult {
    ConsistencyAudit(settings: settings, options: options).run(on: Fixtures.logbook(flights))
  }

  private func rules(_ result: ConsistencyAuditResult) -> [String] {
    result.findings.map(\.rule.rawValue)
  }

  @Test
  func `produces the finding identifiers cleanup-logten produces for the same values`() {
    let options = ConsistencyAuditOptions(boundedCustomTimeFields: [Fixtures.simInstrument])
    let result = ConsistencyAudit(settings: Fixtures.settings, options: options)
      .run(on: Fixtures.cleanupComparison)

    let identifiers = Dictionary(
      uniqueKeysWithValues: result.findings.map { ($0.rule.rawValue, $0.id.rawValue) }
    )
    #expect(
      identifiers == [
        "block_duration": "b0f1f0b005744408fd36",
        "count_subset": "01f71fcc2050ea00158f",
        "flight_overlap": "93d232011bd77419beef",
        "implausible_duration": "cabb16c625ef13997485",
        "missing_full_stops": "9719d09ca57af9f16062",
        "time_subset": "464875dbd5c6f451cf32",
        "timestamp_order": "3de4ffdc3ecc08a3d3af",
        "custom_time_bounds": "e5b60e0402b2255a78f7"
      ]
    )
  }

  @Test
  func `drops findings of disabled rules`() {
    var settings = Fixtures.settings
    settings.rules.disabledRules = [ConsistencyRule.timeSubset.id]
    let flight = Fixtures.flight("F1", day: 1) { $0.times.night = 90 }

    #expect(rules(run([flight], settings: settings)).isEmpty)
    #expect(rules(run([flight])) == ["time_subset"])
  }

  @Test
  func `has one registered check per implemented rule`() {
    let reported = ConsistencyCheckRegistry.checks.flatMap(\.rules)

    #expect(reported.count == Set(reported).count)
  }

  @Test
  func `skips night-full-stop checks when the role is unmapped`() {
    let flight = Fixtures.flight("F1", day: 1) {
      $0[field: Fixtures.nightFullStops] = .integer(2)
      $0.counts.nightLandings = 2
    }

    #expect(rules(run([flight], settings: LogbookSettings())).isEmpty)
    #expect(rules(run([flight])) == ["missing_full_stops"])
  }

  @Test
  func `exempts simulator sessions from time and duration checks`() {
    let session = Fixtures.flight("F1", day: 1, totalMinutes: 1500, aircraft: Fixtures.simulator) {
      $0.times.simulator = 1500
      $0.times.simulatedInstrument = 1600
    }
    #expect(rules(run([session])).isEmpty)
  }

  @Test
  func `flags IFR time only in aircraft marked not IFR-capable`() {
    var settings = Fixtures.settings
    settings.aircraft["N12345"] = AircraftSettings(isIFRCapable: false)
    let instrument = Fixtures.flight("F1", day: 1) { $0.times.actualInstrument = 20 }
    let hood = Fixtures.flight("F2", day: 2) { $0.times.simulatedInstrument = 20 }

    let result = run([instrument, hood], settings: settings)
    #expect(result.findings.map(\.recordIDs) == [["F1"]])
    #expect(result.findings.first?.evidence["recorded_minutes"] == ["actualinstrument": 20])
  }

  @Test
  func `flags approaches without instrument time and named approaches without a quantity`() {
    let approach = Approach(id: "AP1", type: .ILS, count: 2)
    let uncounted = Approach(id: "AP2", type: .RNAV, count: 0)
    let visual = Fixtures.flight("F1", day: 1) { $0.approaches = [approach, uncounted] }
    let hood = Fixtures.flight("F2", day: 2) {
      $0.approaches = [approach]
      $0.times.simulatedInstrument = 30
    }

    #expect(
      rules(run([visual, hood])) == [
        "approach_quantity_missing", "approach_without_instrument_context"
      ]
    )
  }

  @Test
  func `offers day-shifted out and in times that fit the logged total`() throws {
    let flight = Fixtures.flight(
      "F1",
      day: 10,
      totalMinutes: 90,
      out: Fixtures.time(10, 23, 30),
      in: Fixtures.time(10, 1)
    )
    let result = run([flight])
    let order = try #require(result.findings.first { $0.rule == ConsistencyRule.timestampOrder.id })
    let candidates = try #require(result.analyses[order.id]?.dateErrorCandidates)

    #expect(candidates.map { [$0.outDayShift, $0.inDayShift] } == [[-1, 0], [0, 1]])
    #expect(candidates.allSatisfy { $0.minutes == 90 && !$0.swapsOutAndIn })
  }

  @Test
  func `links an overlap to the duration finding that explains it`() throws {
    let misdated = Fixtures.flight(
      "F1",
      day: 10,
      totalMinutes: 60,
      out: Fixtures.time(10, 10),
      in: Fixtures.time(11, 11)
    )
    let next = Fixtures.flight(
      "F2",
      day: 11,
      out: Fixtures.time(11, 9),
      in: Fixtures.time(11, 10),
      aircraft: Fixtures.cirrus
    )
    let result = run([misdated, next])
    let duration = try #require(
      result.findings.first { $0.rule == ConsistencyRule.blockDuration.id }
    )
    let overlap = try #require(
      result.findings.first { $0.rule == ConsistencyRule.flightOverlap.id }
    )

    #expect(result.analyses[duration.id]?.dateErrorCandidates.isEmpty == false)
    #expect(result.analyses[overlap.id]?.relatedFindings == [duration.id])
  }

  @Test
  func `notes partial credit described in the remarks`() throws {
    let flight = Fixtures.flight(
      "F1",
      day: 1,
      totalMinutes: 30,
      out: Fixtures.time(1, 10),
      in: Fixtures.time(1, 11)
    ) { $0.remarks = "Acted as Safety Pilot for the second half" }

    let result = run([flight])
    let finding = try #require(result.findings.first)
    #expect(result.analyses[finding.id]?.isPartialCredit == true)
  }

  @Test
  func `uses the aircraft's own flight-time limit in place of the default`() {
    var settings = Fixtures.settings
    settings.aircraft["N12345"] = AircraftSettings(maximumFlightTime: 120)
    let skyhawk = Fixtures.flight("F1", day: 1, totalMinutes: 150)
    let cirrus = Fixtures.flight("F2", day: 2, totalMinutes: 150, aircraft: Fixtures.cirrus)

    let result = run([skyhawk, cirrus], settings: settings)

    #expect(result.findings.map(\.recordIDs) == [["F1"]])
    #expect(result.findings.first?.evidence["threshold_minutes"] == 120)
  }

  @Test
  func `does not call back-to-back flights overlapping`() {
    let first = Fixtures.flight("F1", day: 1, out: Fixtures.time(1, 10), in: Fixtures.time(1, 11))
    let second = Fixtures.flight(
      "F2",
      day: 1,
      out: Fixtures.time(1, 11),
      in: Fixtures.time(1, 12),
      aircraft: Fixtures.cirrus
    )

    #expect(rules(run([first, second])).isEmpty)
  }

  @Test
  func `flags a negative built-in count, titled as LogTen titles it`() {
    let flight = Fixtures.flight("F1", day: 1) { $0[field: Fixtures.totalLandings] = .integer(-1) }

    let findings = run([flight]).findings.filter { $0.rule == ConsistencyRule.negativeValue.id }

    #expect(findings.map(\.message) == ["Total Landings is negative."])
  }
}

@Suite
struct `Duplicate and reference detection` {
  private typealias Fixtures = ConsistencyFixtures

  private func findings(_ flights: [Flight], logbook: Logbook? = nil) -> [Finding] {
    let logbook = logbook ?? Fixtures.logbook(flights)
    return ConsistencyAudit(settings: Fixtures.settings).run(on: logbook).findings
  }

  @Test
  func `calls identical entries exact duplicates and notes protected ones`() throws {
    let first = Fixtures.flight("F1", day: 1)
    var second = Fixtures.flight("F2", day: 1)
    second.isSigned = true

    let finding = try #require(findings([first, second]).first)
    #expect(finding.rule == ConsistencyRule.duplicateExact.id)
    #expect(finding.severity == .questionable)
    #expect(finding.evidence["locked_or_signed"] == true)
  }

  @Test
  func `treats entries with nearby out times as duplicate candidates`() {
    let first = Fixtures.flight("F1", day: 1, out: Fixtures.time(1, 10), in: Fixtures.time(1, 11))
    let near = Fixtures.flight(
      "F2",
      day: 1,
      out: Fixtures.time(1, 10, 4),
      in: Fixtures.time(1, 11, 4)
    )
    let far = Fixtures.flight(
      "F3",
      day: 1,
      out: Fixtures.time(1, 14),
      in: Fixtures.time(1, 15)
    )

    let duplicates = findings([first, near, far]).filter {
      $0.rule == ConsistencyRule.duplicateCandidate.id
    }
    #expect(duplicates.map(\.recordIDs) == [["F1", "F2"]])
  }

  @Test
  func `tells untimed entries apart by lesson number and remarks`() {
    func untimed(_ id: RecordID, _ remarks: String) -> Flight {
      Fixtures.flight(id, day: 1) { $0.remarks = remarks }
    }
    let lessons = [untimed("F1", "FSTD lesson 4 holds"), untimed("F2", "FSTD lesson 5 holds")]
    let different = [
      untimed("F3", "pattern work at the home airport with three full stops"),
      untimed("F4", "pattern work at home airport, three full-stop landings")
    ]
    let similar = [untimed("F5", "Checkout flight"), untimed("F6", "checkout  flight.")]
    let candidate = [ConsistencyRule.duplicateCandidate.id]

    #expect(findings(lessons).isEmpty)
    #expect(findings(different).isEmpty)
    #expect(findings(similar).map(\.rule) == candidate)
    #expect(findings(untimedByTotal(60, 64)).map(\.rule) == candidate)
    #expect(findings(untimedByTotal(60, 90)).isEmpty)
  }

  private func untimedByTotal(_ first: UInt, _ second: UInt) -> [Flight] {
    [("F7", first), ("F8", second)].map { id, minutes in
      Fixtures.flight(RecordID(rawValue: id), day: 1, totalMinutes: minutes)
    }
  }

  @Test
  func `does not pair entries in different aircraft or between different places`() {
    let first = Fixtures.flight("F1", day: 1)
    let otherAircraft = Fixtures.flight("F2", day: 1, aircraft: Fixtures.cirrus)
    let otherPlace = Fixtures.flight("F3", day: 1, to: Fixtures.sanCarlos)

    #expect(findings([first, otherAircraft, otherPlace]).isEmpty)
  }

  @Test
  func `reports aircraft registrations shared by several records`() throws {
    let copy = Aircraft(id: "A-copy", registration: " n12345 ", type: Fixtures.skyhawk.type)
    var logbook = Fixtures.logbook([])
    logbook.aircraft.append(copy)

    let finding = try #require(findings([], logbook: logbook).first)
    #expect(finding.rule == ConsistencyRule.duplicateReference.id)
    #expect(finding.recordIDs == ["A-N12345", "A-copy"])
    #expect(finding.evidence["identifier"] == "N12345")
  }
}

@Suite
struct `Custom rules` {
  private typealias Fixtures = ConsistencyFixtures

  private func rules(_ customRules: [CustomRule], _ flights: [Flight]) -> [String] {
    var settings = Fixtures.settings
    settings.rules.customRules = customRules
    return ConsistencyAudit(settings: settings).run(on: Fixtures.logbook(flights)).findings
      .map { "\($0.rule.rawValue) \($0.recordIDs[0].rawValue)" }
  }

  @Test
  func `evaluate subset, non-negative and requires rules`() {
    let atp = LogTenFieldKey.custom(.flightTime, 2)
    let note = LogTenFieldKey.custom(.flightNote, 1)
    let landings = LogTenFieldKey.custom(.flightLanding, 1)
    let customRules = [
      CustomRule(id: "atp_xc", kind: .subset, field: atp, other: .flightCrossCountry),
      CustomRule(id: "landings", kind: .nonnegative, field: landings, severity: .discrepancy),
      CustomRule(id: "checkride_pic", kind: .requires, field: note, other: .flightPIC)
    ]
    let flights = [
      Fixtures.flight("F1", day: 1) {
        $0[field: atp] = .integer(50)
        $0.times.crossCountry = 40
      },
      Fixtures.flight("F2", day: 2) { $0[field: landings] = .integer(-1) },
      Fixtures.flight("F3", day: 3) {
        $0[field: note] = .text("Checkride")
        $0.times.PIC = 0
        $0.times.dualReceived = 60
      },
      Fixtures.flight("F4", day: 4) {
        $0[field: note] = .text("Checkride")
        $0.times.PIC = 60
      }
    ]

    #expect(
      rules(customRules, flights) == [
        "custom.atp_xc F1", "custom.checkride_pic F3", "custom.landings F2", "negative_value F2"
      ]
    )
  }
}

@Suite
struct `Text similarity` {
  @Test
  func `matches difflib's ratio, including its junk heuristic for long text`() {
    #expect(
      TextSimilarity.ratio(
        "pattern work at the home airport with three full stops",
        "pattern work at home airport, three full-stop landings"
      ) == 0.8148148148148148
    )
    let practice = String(repeating: "touch and go practice ", count: 12).trimmingCharacters(
      in: .whitespaces
    )
    let practise = practice.replacing("practice", with: "practise")
    #expect(TextSimilarity.ratio(practice, practise) == 0.07224334600760456)
  }
}
