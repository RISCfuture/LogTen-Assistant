import FlightSources
import LogbookModel
import Testing

@Suite
struct `US registration addresses` {
  @Test(arguments: [
    ("N1", "a00001"),
    ("N1A", "a00002"),
    ("N1AA", "a00003"),
    ("N1AB", "a00004"),
    ("N1B", "a0001b"),
    ("N10", "a0025a"),
    ("n2", "a18d50"),
    ("N99999", "adf7c7")
  ])
  func `derives the FAA-assigned address`(registration: String, hex: String) {
    #expect(ICAOAddress(usRegistration: registration)?.hex == hex)
  }

  @Test(arguments: ["N0", "N", "N123456", "N1I", "N1ABC", "N1A2", "N12345A", "C-GABC"])
  func `rejects strings that aren't N-numbers`(_ registration: String) {
    #expect(ICAOAddress(usRegistration: registration) == nil)
  }
}
