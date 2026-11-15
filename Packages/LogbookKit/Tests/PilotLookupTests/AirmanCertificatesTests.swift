import Foundation
import LogbookModel
import PilotLookup
import SwiftAirmen
import Testing

@Suite
struct `Airman certificate lookup` {
  private let certificates: [Certificate] = [
    .pilot(
      level: .airlineTransport,
      ratings: [
        .categoryClass(.airplaneMultiEngineLand, level: .airlineTransport),
        .categoryClass(.airplaneSingleEngineLand, level: .commercial),
        .instrument(.airplane),
        .type("SF50", level: .commercial)
      ],
      centerlineThrustOnly: false
    ),
    .flightInstructor(
      ratings: [.category(.airplaneSingleEngine), .instrument(.airplane)],
      expirationDate: DateComponents(year: 2027, month: 6)
    ),
    .remotePilot
  ]

  @Test
  func `collects the pilot and instructor ratings`() {
    let summary = AirmanCertificates(certificates)
    #expect(summary.certificateLevel == .airlineTransport)
    #expect(summary.categoryClassRatings == [.airplaneMultiEngineLand, .airplaneSingleEngineLand])
    #expect(summary.instrumentRatings == [.airplane])
    #expect(summary.instructorRatings == [.airplaneSingleEngine, .instrumentAirplane])
    #expect(summary.typeRatings == ["SF50"])
  }

  @Test
  func `replaces only certificate fields when applied to a profile`() throws {
    let timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
    let profile = PilotProfile(
      certificateLevel: .private,
      instructorRatings: [.glider],
      homeTimeZone: timeZone,
      ownerPersonID: RecordID(rawValue: "P1"),
      ignoresInstructionActivity: true
    )

    let updated = AirmanCertificates(certificates).applied(to: profile)

    #expect(updated.certificateLevel == .airlineTransport)
    #expect(updated.isFlightInstructor)
    #expect(!updated.instructorRatings.contains(.glider))
    #expect(updated.homeTimeZone == timeZone)
    #expect(updated.ownerPersonID == RecordID(rawValue: "P1"))
    #expect(updated.ignoresInstructionActivity)
  }

  @Test
  func `keeps the profile's level when the record lists no pilot certificate`() {
    let updated = AirmanCertificates([.remotePilot]).applied(
      to: PilotProfile(certificateLevel: .commercial)
    )
    #expect(updated.certificateLevel == .commercial)
    #expect(!updated.isFlightInstructor)
  }
}
