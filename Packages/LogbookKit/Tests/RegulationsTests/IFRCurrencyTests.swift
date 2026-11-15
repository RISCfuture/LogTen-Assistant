import Foundation
import LogbookModel
import Testing

@testable import Regulations

@Suite
struct `IFR currency rule` {
  private func ipc(_ id: String, _ date: Date) -> Flight {
    .fixture(id, date) {
      $0.isInstrumentProficiencyCheck = true
      $0.times.actualInstrument = 30
    }
  }

  /// A flight of six approaches, a hold and intercepting and tracking.
  private func tasks(_ id: String, _ date: Date, tracking: Bool = true, approaches: Int = 6)
    -> Flight
  {
    .fixture(id, date) {
      $0.times.simulatedInstrument = 60
      $0.counts.holds = 1
      $0.approaches = (0..<approaches).map {
        Approach(id: RecordID(rawValue: "\(id)-\($0)"), type: .ILS)
      }
      if tracking { $0.mark(.interceptingAndTracking) }
    }
  }

  private func imc(_ id: String, _ date: Date) -> Flight {
    .fixture(id, date) { $0.times.actualInstrument = 30 }
  }

  private func flagged(_ flights: [Flight], configure: (inout LogbookSettings) -> Void = { _ in })
    async throws -> Set<String>
  {
    try await Scenario(flights: flights, configure: configure).flagged(by: .noIFRCurrency)
  }

  @Test
  func `flags IFR flights with no proficiency check or rating on record`() async throws {
    let violations = try await Scenario(flights: [imc("a", day(2025, 3, 1))])
      .violations(of: .noIFRCurrency)
    #expect(violations.map(\.flightID.rawValue) == ["a"])
  }

  @Test
  func `stays current through the sixth month after a proficiency check`() async throws {
    let flights = [
      ipc("ipc", day(2025, 1, 10)), imc("last-day", day(2025, 7, 31)),
      imc("lapsed", day(2025, 8, 1))
    ]
    #expect(try await flagged(flights) == ["lapsed"])
  }

  @Test
  func `exempts the proficiency check itself, dual received and flights with a safety pilot`()
    async throws
  {
    var safety = imc("safety", day(2025, 3, 3))
    safety.crew.custom[1] = Person(id: RecordID(rawValue: "safety-pilot"), name: "Safety")
    let flights = [
      ipc("ipc", day(2025, 3, 1)),
      .fixture("dual", day(2025, 3, 2)) {
        $0.times.actualInstrument = 30
        $0.times.dualReceived = 60
      },
      safety
    ]
    #expect(try await flagged(flights).isEmpty)
  }

  @Test
  func `extends currency with six approaches, a hold and tracking`() async throws {
    let lapsing = [ipc("ipc", day(2025, 1, 10)), imc("a", day(2025, 10, 1))]
    let restored = [
      ipc("ipc", day(2025, 1, 10)), tasks("tasks", day(2025, 6, 20)), imc("a", day(2025, 10, 1))
    ]

    #expect(try await flagged(lapsing) == ["a"])
    #expect(try await flagged(restored).isEmpty)
  }

  @Test
  func `extends currency only to the sixth month after the earliest task`() async throws {
    let flights = [
      ipc("ipc", day(2025, 1, 10)), tasks("tasks", day(2025, 6, 20)),
      imc("last", day(2025, 12, 31)),
      imc("lapsed", day(2026, 1, 1))
    ]
    #expect(try await flagged(flights) == ["lapsed"])
  }

  @Test
  func `needs every task`() async throws {
    let base = ipc("ipc", day(2025, 1, 10))
    let subject = imc("a", day(2025, 10, 1))

    #expect(
      try await flagged([base, tasks("t", day(2025, 6, 20), tracking: false), subject]) == ["a"]
    )
    #expect(
      try await flagged([base, tasks("t", day(2025, 6, 20), tracking: false), subject]) {
        try? $0.fieldMapping.assign(nil, to: .interceptingAndTracking)
      }.isEmpty,
      "With no intercepting and tracking field, the approaches count as tracking"
    )
    #expect(
      try await flagged([base, tasks("t", day(2025, 6, 20), approaches: 5), subject]) == ["a"]
    )
    var noHold = tasks("t", day(2025, 6, 20))
    noHold.counts.holds = 0
    #expect(try await flagged([base, noHold, subject]) == ["a"])
  }

  @Test
  func `adds tasks across flights`() async throws {
    var first = tasks("first", day(2025, 6, 1), tracking: false, approaches: 3)
    first.counts.holds = 0
    var second = tasks("second", day(2025, 6, 20), approaches: 3)
    second.mark(.interceptingAndTracking)
    second.counts.holds = 1

    #expect(
      try await flagged([ipc("ipc", day(2025, 1, 10)), first, second, imc("a", day(2025, 10, 1))])
        .isEmpty
    )
  }

  @Test
  func `ignores approaches flown outside instrument conditions`() async throws {
    var visual = tasks("t", day(2025, 6, 20))
    visual.times.simulatedInstrument = 0

    #expect(
      try await flagged([ipc("ipc", day(2025, 1, 10)), visual, imc("a", day(2025, 10, 1))]) == ["a"]
    )
  }

  @Test
  func `restores currency in the six months after a lapse`() async throws {
    let flights = [
      ipc("ipc", day(2025, 1, 10)), tasks("tasks", day(2025, 9, 20)), imc("a", day(2025, 10, 1))
    ]
    #expect(try await flagged(flights).isEmpty)
  }

  @Test
  func `requires a proficiency check once a lapse passes six months`() async throws {
    let flights = [
      ipc("ipc", day(2025, 1, 10)), tasks("late-tasks", day(2026, 2, 20)), imc("a", day(2026, 3, 1))
    ]
    let violations = try await Scenario(flights: flights).violations(of: .noIFRCurrency)

    #expect(violations.map(\.flightID.rawValue) == ["a"])
    let missingTasks = try await Scenario(flights: [
      ipc("ipc", day(2025, 1, 10)), imc("a", day(2025, 10, 1))
    ])
    .violations(of: .noIFRCurrency)
    #expect(violations[0].explanation != missingTasks[0].explanation)
  }

  @Test
  func `starts from a new proficiency check after a lapse`() async throws {
    let flights = [
      ipc("ipc", day(2025, 1, 10)), ipc("renewed", day(2026, 3, 1)), imc("a", day(2026, 4, 1))
    ]
    #expect(try await flagged(flights).isEmpty)
  }

  @Test
  func `accepts an instrument rating or check confirmed in the settings`() async throws {
    for kind in [ConfirmedCurrencyEvent.Kind.instrumentRating, .instrumentProficiencyCheck] {
      let flights = [imc("a", day(2025, 3, 1))]
      let violations = try await flagged(flights) {
        $0.rules.confirmedCurrencyEvents = [
          ConfirmedCurrencyEvent(date: DateComponents(year: 2025, month: 1), kind: kind)
        ]
      }
      #expect(violations.isEmpty)
    }
  }

  @Test
  func `keeps currency per category`() async throws {
    let helicopter = Flight.fixture("heli", day(2025, 1, 10), in: .helicopter) {
      $0.isInstrumentProficiencyCheck = true
      $0.times.actualInstrument = 30
    }
    let flights = [helicopter, imc("a", day(2025, 2, 1))]

    let violations = try await flagged(flights) {
      $0.pilot.instrumentRatings = [.airplane, .helicopter]
    }
    #expect(violations == ["a"])
  }

  @Test
  func `does not judge a category without an instrument rating`() async throws {
    let flight = Flight.fixture("heli", day(2025, 3, 1), in: .helicopter) {
      $0.times.actualInstrument = 30
    }
    #expect(try await flagged([flight]).isEmpty)
  }

  @Test
  func `counts a full flight simulator proficiency check`() async throws {
    let check = Flight.fixture(
      "ffs",
      day(2025, 1, 10),
      in: .simulator(representing: "C172", device: .FFS)
    ) {
      $0.isInstrumentProficiencyCheck = true
    }
    #expect(try await flagged([check, imc("a", day(2025, 2, 1))]).isEmpty)
  }

  @Test
  func `does not count its own approaches toward its own currency`() async throws {
    var flight = tasks("a", day(2025, 3, 1))
    flight.times.actualInstrument = 30

    #expect(try await flagged([flight]) == ["a"])
  }
}
