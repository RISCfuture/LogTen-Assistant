import Audit
import Foundation
import LogbookModel
import LogbookStore
import LogbookTestSupport
import Testing

@Suite
struct `Smart-group audit` {
  private static let nightFullStops = LogTenFieldKey.custom(.flightLanding, 5)
  private static let tracking = LogTenFieldKey.custom(.flightOperation, 1)
  private static let proficiency = LogTenFieldKey.custom(.flightNote, 2)

  private var mapping: FieldMapping {
    var mapping = FieldMapping()
    try? mapping.assign(Self.nightFullStops, to: .nightFullStops)
    try? mapping.assign(Self.tracking, to: .interceptingAndTracking)
    try? mapping.assign(Self.proficiency, to: .proficiencyCheck)
    return mapping
  }

  private func criteria(_ keys: String...) -> [SmartGroupCriterion] {
    keys.map { SmartGroupCriterion(searchKey: $0) }
  }

  @Test(.requiresLogTen)
  func `evaluates predicates and assigned members against the snapshot`() async throws {
    let directory = try TemporaryDirectory()
    let logbook = SyntheticLogbook(
      flights: [
        .init(id: "F-night", date: .now, values: [.flightNight: .integer(30)]),
        .init(id: "F-day", date: .now, values: [.flightTotalTime: .integer(60)])
      ],
      groups: [
        .init(id: "G-night", name: "Night", predicateFormat: "flight_night > 0"),
        .init(id: "G-broken", name: "Broken", predicateFormat: "flight_noSuchField > 0"),
        .init(id: "G-assigned", name: "Assigned", flightIDs: ["F-day"])
      ]
    )
    let store = try logbook.write(into: directory.url)
    let snapshot = try await LogbookSnapshotter()
      .snapshot(of: store.location, into: directory.path("snapshot"))
    let reader = try LogbookReader(snapshot: snapshot)
    let groups = try await reader.read().groups

    let result = await SmartGroupAudit(mapping: mapping).run(on: groups, resolver: reader)
    let statuses = Dictionary(
      uniqueKeysWithValues: result.evaluations.map { ($0.group.name, $0.status) }
    )

    #expect(statuses["Night"] == .evaluated([RecordID(rawValue: "F-night")]))
    #expect(statuses["Assigned"] == .evaluated([RecordID(rawValue: "F-day")]))
    guard case .failed = statuses["Broken"] else {
      Issue.record("An invalid predicate wasn’t reported as failed.")
      return
    }
  }

  @Test
  func `checks definitions for the parts of a requirement they omit`() async {
    let groups = [
      LogbookGroup(
        id: RecordID(rawValue: "G-ifr"),
        name: "IFR",
        criteria: criteria("flight_totalInstrumentApproaches", "flight_holds")
      ),
      LogbookGroup(
        id: RecordID(rawValue: "G-ifr-complete"),
        name: "IFR complete",
        criteria: criteria("flight_totalInstrumentApproaches", Self.tracking.rawValue)
      ),
      LogbookGroup(
        id: RecordID(rawValue: "G-night"),
        name: "Night passengers",
        criteria: criteria("flight_nightTakeoffs", "flight_nightLandings")
      ),
      LogbookGroup(
        id: RecordID(rawValue: "G-review"),
        name: "Flight review",
        predicateFormat: "flight_review == 1"
      ),
      LogbookGroup(
        id: RecordID(rawValue: "G-passenger-days"),
        name: "Passenger days",
        criteria: criteria("flight_totalLandings")
      ),
      LogbookGroup(
        id: RecordID(rawValue: "G-passenger-months"),
        name: "Passenger months",
        criteria: criteria("flight_totalLandings")
      ),
      LogbookGroup(
        id: RecordID(rawValue: "G-night-complete"),
        name: "Night complete",
        criteria: criteria("flight_nightLandings", Self.nightFullStops.rawValue)
      ),
      LogbookGroup(
        id: RecordID(rawValue: "G-proficiency"),
        name: "Proficiency check",
        criteria: criteria(Self.proficiency.rawValue)
      )
    ]
    let windows = [
      RecordID(rawValue: "G-ifr"): SmartGroupWindow(value: 12, increment: 3),
      RecordID(rawValue: "G-passenger-days"): SmartGroupWindow(value: 90, increment: 1),
      RecordID(rawValue: "G-passenger-months"): SmartGroupWindow(value: 3, increment: 3),
      RecordID(rawValue: "G-proficiency"): SmartGroupWindow(value: 12, increment: 3)
    ]

    let result = await SmartGroupAudit(mapping: mapping)
      .run(on: groups, resolver: NoMembers(), windows: windows)
    let findings = result.findings.map {
      "\($0.rule.rawValue) \($0.evidence["group"]?.stringValue ?? "")"
    }

    #expect(
      findings.sorted() == [
        "group_6158_windows Proficiency check", "group_instrument_recovery IFR",
        "group_instrument_tracking IFR", "group_night_full_stops Night passengers",
        "group_passenger_window Passenger months", "group_review_alternatives Flight review"
      ]
    )
    #expect(result.evaluations.map(\.status)[0] == .criteriaNotEvaluated)
  }

  @Test
  func `skips window checks for groups without a known window and drops disabled rules`() async {
    let groups = [
      LogbookGroup(
        id: "G-ifr",
        name: "IFR",
        criteria: criteria("flight_totalInstrumentApproaches")
      ),
      LogbookGroup(id: "G-landings", name: "Landings", criteria: criteria("flight_totalLandings"))
    ]
    let all = await SmartGroupAudit(mapping: mapping).run(on: groups, resolver: NoMembers())
    let muted = await SmartGroupAudit(
      mapping: mapping,
      disabledRules: [SmartGroupRule.instrumentTracking.id]
    ).run(on: groups, resolver: NoMembers())

    #expect(all.findings.map(\.rule.rawValue) == ["group_instrument_tracking"])
    #expect(muted.findings.isEmpty)
  }

  @Test
  func `reports a resolver failure and evaluates plain groups without a predicate`() async {
    let groups = [
      LogbookGroup(id: "G-plain", name: "Plain", memberFlightIDs: ["F1"]),
      LogbookGroup(id: "G-smart", name: "Smart", predicateFormat: "flight_night > 0")
    ]

    let result = await SmartGroupAudit(mapping: mapping)
      .run(on: groups, resolver: Failing())

    let reason = CocoaError(.fileReadUnknown).localizedDescription
    #expect(result.evaluations.map(\.status) == [.failed(reason: reason), .failed(reason: reason)])
  }

  private struct Failing: GroupMembershipResolving {
    func flightIDs(in _: LogbookGroup) throws -> [RecordID] { throw CocoaError(.fileReadUnknown) }
  }

  private struct NoMembers: GroupMembershipResolving {
    func flightIDs(in _: LogbookGroup) throws -> [RecordID] { [] }
  }
}
