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
  func `extracts the fixes that have coordinates and flags the final approach fix`() async throws {
    let library = try await CIFPApproachLibrary(
      contentsOf: fixtureURL("CIFP/koak-approaches.cifp")
    )

    let ils = try #require(await library.approaches(at: "KOAK").first { $0.identifier == "I12" })

    let plaza = try #require(ils.fixes.first { $0.name == "PLAZA" })
    #expect(plaza.isFinalApproachFix)
    #expect(abs(plaza.latitudeDeg - 37.6283) < 0.0001)
    #expect(abs(plaza.longitudeDeg + 122.2336) < 0.0001)
    #expect(ils.fixes.filter { !$0.isFinalApproachFix }.map(\.name) == ["ALCAT"])
  }

  @Test
  func `has no approaches for an unknown airport`() async throws {
    let library = try await CIFPApproachLibrary(
      contentsOf: fixtureURL("CIFP/koak-approaches.cifp")
    )

    #expect(await library.approaches(at: "KXYZ").isEmpty)
  }
}
