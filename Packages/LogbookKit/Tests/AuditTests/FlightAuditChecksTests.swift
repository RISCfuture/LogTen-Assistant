@testable import Audit
import Foundation
import LogbookModel
import Testing

@Suite
struct `Flight Audit checks` {
  private typealias Fixtures = ConsistencyFixtures

  private static let now = Fixtures.time(20, 12)

  private func findings(
    _ rule: ConsistencyRule,
    _ flights: [Flight],
    asOf: Date = now
  ) -> [Finding] {
    ConsistencyAudit(settings: Fixtures.settings)
      .run(on: Fixtures.logbook(flights), asOf: asOf).findings
      .filter { $0.rule == rule.id }
      .sorted { $0.recordIDs[0] < $1.recordIDs[0] }
  }

  private func titles(_ finding: Finding) -> [String] { finding.corrections.map(\.title) }

  @Test
  func `offers clearing either PIC or SIC with its night time when both fill the flight`() throws {
    let flight = Fixtures.flight("F1", day: 1, totalMinutes: 120) {
      $0.times.PIC = 120
      $0.times.SIC = 120
      $0[field: LogTenFieldKey(.flight, "sicNight")] = .integer(6)
    }

    let finding = try #require(findings(.seatTime, [flight]).first)

    #expect(finding.severity == .discrepancy)
    #expect(titles(finding) == ["Clear SIC", "Clear PIC"])
    let clearSIC = try #require(finding.corrections.first)
    #expect(clearSIC.changes.map(\.field.rawValue) == ["flight_sic", "flight_sicNight"])
    #expect(clearSIC.changes.map(\.new) == [.integer(0), .integer(0)])
    let clearPIC = try #require(finding.corrections.last)
    #expect(clearPIC.changes.map(\.field.rawValue) == ["flight_pic"])
  }

  @Test
  func `accepts PIC logged with dual received, solo and dual given for the same period`() {
    let flights = [
      Fixtures.flight("F1", day: 1, totalMinutes: 90) { $0.times.dualReceived = 90 },
      Fixtures.flight("F2", day: 2, totalMinutes: 90) { $0.times.solo = 90 },
      Fixtures.flight("F3", day: 3, totalMinutes: 90) {
        $0.times.PIC = 90
        $0.times.dualGiven = 90
      },
      Fixtures.flight("F4", day: 4, totalMinutes: 90) {
        $0.times.PIC = 0
        $0.times.dualReceived = 90
      }
    ]

    #expect(findings(.seatTime, flights).isEmpty)
  }

  @Test
  func `warns when total time is longer than its role times by any amount, with or without roles`()
    throws
  {
    let partial = Fixtures.flight("F1", day: 1, totalMinutes: 70) { $0.times.PIC = 60 }
    let none = Fixtures.flight("F2", day: 2, totalMinutes: 150) { $0.times.PIC = 0 }
    let slight = Fixtures.flight("F3", day: 3, totalMinutes: 68) { $0.times.PIC = 64 }
    let exact = Fixtures.flight("F4", day: 4, totalMinutes: 60) { $0.times.PIC = 60 }

    let result = findings(.seatTime, [partial, none, slight, exact])

    #expect(result.map(\.recordIDs) == [["F1"], ["F2"], ["F3"]])
    #expect(result.allSatisfy { $0.severity == .questionable && $0.corrections.isEmpty })
    #expect(
      result.last?.explanation
        == "Total time of 1.1 hours includes 4 minutes that no role time covers, so that part of the flight has no role."
    )
    #expect(
      result[0].explanation?.contains("includes 0.2 hours that no role time covers") == true
    )
    #expect(
      result[1].explanation
        == "No role time is logged, so none of the 2.5 hours of total time has a role."
    )
  }

  @Test
  func `reports roles on a flight with landings but no total time as a missing total`() throws {
    let flight = Fixtures.flight("F1", day: 1, totalMinutes: 0) {
      $0.times.PIC = 100
      $0.counts.dayLandings = 1
    }

    let finding = try #require(findings(.seatTime, [flight]).first)

    #expect(finding.message == "Total time is missing.")
    #expect(findings(.missingTotalTime, [flight]).isEmpty)
  }

  @Test
  func `limits night role times that exceed their role time`() throws {
    let picNight = LogTenFieldKey(.flight, "picNight")
    let flight = Fixtures.flight("F1", day: 1, totalMinutes: 60) {
      $0.times.night = 60
      $0[field: picNight] = .integer(60)
      $0.times.PIC = 30
    }

    let finding = try #require(findings(.nightSeatTime, [flight]).first)

    let option = try #require(finding.corrections.first)
    #expect(option.changes.map(\.field) == [picNight])
    #expect(option.changes.map(\.new) == [.integer(30)])
  }

  @Test
  func `flags night role times beyond night time without a correction`() throws {
    let flight = Fixtures.flight("F1", day: 1, totalMinutes: 60) {
      $0.times.night = 60
      $0[field: LogTenFieldKey(.flight, "picNight")] = .integer(60)
      $0[field: LogTenFieldKey(.flight, "sicNight")] = .integer(60)
      $0.times.SIC = 60
    }

    let finding = try #require(findings(.nightSeatTime, [flight]).first)

    #expect(finding.corrections.isEmpty)
  }

  @Test
  func `offers to copy the only place that is set to the other`() throws {
    var noTo = Fixtures.flight("F1", day: 1)
    noTo.to = nil
    var noFrom = Fixtures.flight("F2", day: 2)
    noFrom.from = nil
    var neither = Fixtures.flight("F3", day: 3)
    (neither.from, neither.to) = (nil, nil)

    let result = findings(.missingFromTo, [noTo, noFrom, neither])

    #expect(result.map(titles) == [["Set To to Match From"], ["Set From to Match To"], []])
    let change = try #require(result.first?.corrections.first?.changes.first)
    #expect(change.field == .flightTo)
    #expect(change.new == .text("KSQL"))
  }

  @Test
  func `reports a past flight without total time or counts but not a planned one`() {
    let past = Fixtures.flight("F1", day: 1, totalMinutes: 0) { $0.times.PIC = 100 }
    let planned = Fixtures.flight("F2", day: 28, totalMinutes: 0)
    let today = Fixtures.flight("F4", day: 20, totalMinutes: 0) { $0.date = Fixtures.time(20, 11) }
    let landed = Fixtures.flight("F3", day: 2, totalMinutes: 0) { $0.counts.dayLandings = 1 }
    let flights = [past, planned, today, landed]

    #expect(findings(.missingTotalTime, flights).map(\.recordIDs) == [["F1"]])
    #expect(findings(.landingsWithoutTime, flights).map(\.recordIDs) == [["F3"]])
  }

  @Test
  func `leaves simulator sessions and ground-only entries out of the total time checks`() {
    let session = Fixtures.flight("F1", day: 1, totalMinutes: 0, aircraft: Fixtures.simulator) {
      $0.times.simulator = 90
      $0.counts.dayLandings = 2
    }
    var ground = Fixtures.flight("F2", day: 2, totalMinutes: 0) { $0.times.ground = 180 }
    ground.aircraft = nil

    #expect(findings(.missingTotalTime, [session, ground]).isEmpty)
    #expect(findings(.landingsWithoutTime, [session, ground]).isEmpty)
  }

  @Test
  func `does not ask for a class on gliders or for a class and engine on simulators`() {
    let types = [
      AircraftType(id: "T1", type: "ASK21", category: .glider, engineType: .reciprocating),
      AircraftType(id: "T2", type: "FRASCA", category: .simulator),
      AircraftType(id: "T3", type: "C172", category: .airplane, engineType: .reciprocating)
    ]
    let flights = zip(types, ["F1", "F2", "F3"] as [RecordID]).enumerated().map { index, pair in
      Fixtures.flight(
        pair.1,
        day: 1 + index,
        aircraft: Aircraft(id: RecordID(rawValue: "A\(index)"), registration: "N", type: pair.0)
      )
    }

    let result = findings(.aircraftTypeClassification, flights)

    #expect(result.map(\.recordIDs) == [["T3"]])
  }

  @Test
  func `accepts an aircraft known by its secondary ID and a person known by an ID`() {
    let aircraft = [
      Aircraft(id: "A1", registration: "", secondaryID: "Fleet 7", type: Fixtures.skyhawk.type),
      Aircraft(id: "A2", registration: "", type: Fixtures.skyhawk.type)
    ]
    let people = [
      Person(id: "P1", name: "", personID: "CFI-123"),
      Person(id: "P2", name: "", firstName: "Ada"),
      Person(id: "P3", name: "")
    ]
    var logbook = Fixtures.logbook([])
    logbook.aircraft = aircraft
    logbook.people = people

    let result = ConsistencyAudit(settings: Fixtures.settings).run(on: logbook, asOf: Self.now)
      .findings

    #expect(
      result.filter { $0.rule == ConsistencyRule.incompleteAircraft.id }.map(\.recordIDs) == [
        ["A2"]
      ]
    )
    #expect(
      result.filter { $0.rule == ConsistencyRule.incompletePerson.id }.map(\.recordIDs) == [["P3"]]
    )
  }

  @Test
  func `still reports an implausible duration when block time disagreement is turned off`() {
    let flight = Fixtures.flight(
      "F1",
      day: 1,
      totalMinutes: 1_500,
      out: Fixtures.time(1, 10),
      in: Fixtures.time(1, 11)
    )
    var settings = Fixtures.settings
    settings.rules.setEnabled(false, ConsistencyRule.blockDuration.id)

    let result = ConsistencyAudit(settings: settings).run(
      on: Fixtures.logbook([flight]),
      asOf: Self.now
    )
    .findings

    #expect(result.map(\.rule) == [ConsistencyRule.implausibleDuration.id])
  }

  @Test
  func `reports a flight with time but no aircraft, and an aircraft without a type`() {
    var noAircraft = Fixtures.flight("F1", day: 1)
    noAircraft.aircraft = nil
    var untyped = Fixtures.flight("F2", day: 2)
    untyped.aircraft = Aircraft(id: "A-X", registration: "N999")

    #expect(findings(.missingAircraft, [noAircraft, untyped]).map(\.recordIDs) == [["F1"]])
    #expect(findings(.missingAircraftType, [noAircraft, untyped]).map(\.recordIDs) == [["F2"]])
  }

  @Test
  func `offers swapping reversed Hobbs readings`() throws {
    let flight = Fixtures.flight("F1", day: 1) {
      $0.hobbsStart = 1_250.4
      $0.hobbsStop = 1_248.9
      $0.tachStart = 100
      $0.tachStop = 101.5
    }

    let finding = try #require(findings(.hobbsTachOrder, [flight]).first)

    let changes = try #require(finding.corrections.first).changes
    #expect(changes.map(\.field) == [.flightHobbsStart, .flightHobbsStop])
    #expect(changes.map(\.new) == [.number(1_248.9), .number(1_250.4)])
  }

  @Test
  func `reports flights dated or timed after the audit date that log total time`() {
    let dated = Fixtures.flight("F1", day: 25)
    let timed = Fixtures.flight(
      "F2",
      day: 20,
      out: Fixtures.time(20, 11),
      in: Fixtures.time(20, 13)
    )
    let past = Fixtures.flight("F3", day: 19, out: Fixtures.time(19, 11), in: Fixtures.time(19, 12))
    let planned = Fixtures.flight("F4", day: 26, totalMinutes: 0)

    let result = findings(.futureDate, [dated, timed, past, planned])

    #expect(result.map(\.recordIDs) == [["F1"], ["F2"]])
  }

  @Test
  func `offers swapping two times that put the flight in order`() throws {
    let flight = Fixtures.flight(
      "F1",
      day: 1,
      out: Fixtures.time(1, 10),
      off: Fixtures.time(1, 11),
      in: Fixtures.time(1, 11, 30)
    ) {
      $0.events.on = Fixtures.time(1, 10, 30)
    }
    var unfixable = flight
    unfixable.id = "F2"
    unfixable.events.on = Fixtures.time(1, 9)

    let result = findings(.timestampOrder, [flight, unfixable])

    #expect(result.map(titles).filter { !$0.isEmpty } == [["Swap Off and On"]])
  }

  @Test
  func `offers the out-to-in time for an implausibly long total that disagrees with it`() throws {
    let flight = Fixtures.flight(
      "F1",
      day: 1,
      totalMinutes: 1_500,
      out: Fixtures.time(1, 10),
      in: Fixtures.time(1, 11)
    ) {
      $0.times.night = 30
      $0.times.dualReceived = 100
    }

    let finding = try #require(findings(.blockDuration, [flight]).first)

    let option = try #require(finding.corrections.first)
    #expect(option.changes.map(\.field) == [.flightTotalTime, .flightPIC, .flightDualReceived])
    #expect(option.changes.map(\.new) == [.integer(60), .integer(60), .integer(60)])
    #expect(option.changes[1].old == .integer(1_500))
    #expect(option.detail?.contains("Dual Received") == true)
  }

  @Test
  func `flags cross-country night above night or cross-country time and summed instrument time`() {
    let crossCountryNight = LogTenFieldKey(.flight, "crossCountryNight")
    let flights = [
      Fixtures.flight("F3", day: 3) { $0[field: LogTenFieldKey(.flight, "p1us")] = .integer(90) },
      Fixtures.flight("F1", day: 1) {
        $0.times.crossCountry = 60
        $0.times.night = 20
        $0[field: crossCountryNight] = .integer(30)
      },
      Fixtures.flight("F2", day: 2) {
        $0.times.actualInstrument = 40
        $0.times.simulatedInstrument = 40
      }
    ]

    let result = findings(.timeSubset, flights)

    #expect(result.map(\.recordIDs) == [["F1"], ["F2"], ["F3"]])
    #expect(result.first?.corrections.first?.changes.first?.new == .integer(20))
  }
}
