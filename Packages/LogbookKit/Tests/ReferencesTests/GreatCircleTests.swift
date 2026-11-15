import Testing

@testable import References

@Suite
struct `Great circle` {
  @Test(arguments: [
    (10.0, 350.0, 20.0),
    (350.0, 10.0, 20.0),
    (0.0, 180.0, 180.0),
    (90.0, 90.0, 0.0),
    (359.0, 1.0, 2.0)
  ])
  func `measures the smaller angle between bearings`(
    first: Double,
    second: Double,
    expected: Double
  ) {
    #expect(abs(GreatCircle.angleBetween(first, second) - expected) < 0.000_001)
  }
}
