@testable import Audit
import Foundation
import LogbookModel
import Testing

@Suite
struct `Flight habits` {
  private typealias Fixtures = ConsistencyFixtures

  private static let captain = Person(id: "P-CAPT", name: "A. Captain")

  /// A flight logging SIC time, naming the PIC or not.
  private static func sicFlight(
    _ id: String,
    namingPIC: Bool,
    aircraft: Aircraft = Fixtures.skyhawk
  ) -> AuditedFlight {
    AuditedFlight(
      Fixtures.flight(RecordID(rawValue: id), day: 1, aircraft: aircraft) { flight in
        flight.times.SIC = 60
        if namingPIC { flight.crew.PIC = captain }
      }
    )
  }

  private static func namesPIC(
    _ flights: [AuditedFlight],
    similarity: FlightSimilarity = .aircraftType
  ) -> FlightHabit {
    FlightHabit(
      over: flights,
      similarity: similarity,
      when: { $0.hasPositive("sic") },
      records: { $0.flight.crew.PIC != nil }
    )
  }

  @Test
  func `holds when the usual share of other similar flights records it`() {
    let target = Self.sicFlight("target", namingPIC: false)
    let others = (1...4).map { Self.sicFlight("named-\($0)", namingPIC: true) }
    let unnamed = Self.sicFlight("unnamed", namingPIC: false)

    #expect(Self.namesPIC(others + [unnamed, target]).isUsual(for: target))
    #expect(
      !Self.namesPIC(others + [unnamed, Self.sicFlight("unnamed-2", namingPIC: false), target])
        .isUsual(for: target)
    )
  }

  @Test
  func `learns only from enough flights alike in the chosen traits`() {
    let target = Self.sicFlight("target", namingPIC: false)
    let skyhawks = (1...4).map { Self.sicFlight("skyhawk-\($0)", namingPIC: true) }
    let cirruses = (1...4).map {
      Self.sicFlight("cirrus-\($0)", namingPIC: true, aircraft: Fixtures.cirrus)
    }
    let flights = skyhawks + cirruses + [target]

    #expect(!Self.namesPIC(flights).isUsual(for: target))
    #expect(Self.namesPIC(flights, similarity: []).isUsual(for: target))
  }
}
