import Testing

import References

@Suite
struct `Published approach` {
  @Test
  func `is named without a runway for a circling approach`() {
    let approach = PublishedApproach(
      airportIdentifier: "KXYZ",
      identifier: "A",
      family: .ils,
      typeName: "ILS",
      multipleIndicator: "A"
    )

    #expect(approach.name == "ILS A")
  }
}
