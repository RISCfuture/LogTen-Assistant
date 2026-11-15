import Foundation
import Testing

import References

/// A resolver that answers from a table and counts how often it was asked.
private actor StubResolver: TimeZoneResolving {
  private(set) var requests = 0
  private let answer: String?
  private let failure: (any Error)?

  init(answer: String? = nil, failure: (any Error)? = nil) {
    self.answer = answer
    self.failure = failure
  }

  // swiftlint:disable:next async_without_await
  func timeZoneIdentifier(latitudeDeg _: Double, longitudeDeg _: Double) async throws -> String? {
    requests += 1
    if let failure { throw failure }
    return answer
  }
}

private struct Unreachable: Error {}

@Suite
struct `Airport time zones` {
  private let airport = AirportReference(
    locationID: "SQL",
    ICAOID: "KSQL",
    name: "San Carlos",
    latitudeDeg: 37.5,
    longitudeDeg: -122.2
  )

  @Test
  func `prefers an override over reference data over a lookup`() async {
    let resolver = StubResolver(answer: "America/Los_Angeles")
    let timeZones = AirportTimeZones(resolver: resolver, overrides: ["ksql": "America/Phoenix"])
    var withReference = airport
    withReference.timeZoneIdentifier = "America/Denver"

    #expect(
      await timeZones.timeZone(of: airport)
        == .init(identifier: "America/Phoenix", source: .override)
    )
    await timeZones.setOverride(nil, forAirport: "KSQL")
    #expect(
      await timeZones.timeZone(of: withReference)
        == .init(identifier: "America/Denver", source: .reference)
    )
    #expect(await resolver.requests == 0)
  }

  @Test
  func `remembers a lookup so the resolver is asked once`() async {
    let resolver = StubResolver(answer: "America/Los_Angeles")
    let timeZones = AirportTimeZones(resolver: resolver)

    _ = await timeZones.timeZone(of: airport)
    let second = await timeZones.timeZone(of: airport)

    #expect(second == .init(identifier: "America/Los_Angeles", source: .lookup))
    #expect(await resolver.requests == 1)
    #expect(await timeZones.lookups == ["KSQL": "America/Los_Angeles"])
  }

  @Test
  func `counts a failed lookup and asks again next time`() async {
    let resolver = StubResolver(failure: Unreachable())
    let timeZones = AirportTimeZones(resolver: resolver)

    #expect(await timeZones.timeZone(of: airport) == nil)
    #expect(await timeZones.timeZone(of: airport) == nil)

    #expect(await resolver.requests == 2)
    #expect(await timeZones.failedLookups == 2)
  }
}
