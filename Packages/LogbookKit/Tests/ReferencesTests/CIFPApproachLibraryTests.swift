import Foundation
import Testing

import References

@Suite
struct `CIFP approach library` {
  @Test
  func `names the final approach routes of an airport`() async throws {
    let library = try await CIFPApproachLibrary(
      contentsOf: fixtureURL("CIFP/koak-approaches.cifp")
    )

    let approaches = await library.approaches(at: "koak")

    let ils = try #require(approaches.first { $0.identifier == "I12" })
    #expect(ils.name == "ILS RWY 12")
    #expect(ils.family == .ils)
    let rnav = try #require(approaches.first { $0.identifier == "R12-Y" })
    #expect(rnav.name == "RNAV Y RWY 12")
    #expect(rnav.family == .rnav)
    #expect(approaches.count == 2)
  }

  @Test
  func `has no approaches for an unknown airport`() async throws {
    let library = try await CIFPApproachLibrary(
      contentsOf: fixtureURL("CIFP/koak-approaches.cifp")
    )

    #expect(await library.approaches(at: "KXYZ").isEmpty)
  }
}
