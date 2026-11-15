import Foundation
import References
import Testing

@Suite
struct `Night window` {
  private static let latitude = 37.62
  private static let longitude = -122.38

  private func classify(_ text: String, latitude: Double = latitude) -> NightClassification {
    NightWindow.classify(at: utc(text), latitudeDeg: latitude, longitudeDeg: Self.longitude)
  }

  @Test
  func `is day at midmorning`() {
    let result = classify("2024-12-22T18:00:00Z")

    #expect(!result.isCivilNight)
    #expect(result.isCurrencyNight == false)
  }

  @Test
  func `is neither night after sunset and before the end of twilight`() {
    // 17:05 PST on the winter solstice; sunset is about 16:52.
    let result = classify("2024-12-22T01:05:00Z")

    #expect(!result.isCivilNight)
    #expect(result.isCurrencyNight == false)
  }

  @Test
  func `is civil night but not currency night until an hour after sunset`() {
    // 17:35 PST: civil twilight ended about 17:22, an hour after sunset is about 17:52.
    let result = classify("2024-12-22T01:35:00Z")

    #expect(result.isCivilNight)
    #expect(result.isCurrencyNight == false)
  }

  @Test
  func `is civil night but not currency night until an hour before sunrise`() {
    // 06:40 PST: sunrise is about 07:22, and civil twilight begins about 06:55.
    let result = classify("2024-12-22T14:40:00Z")

    #expect(result.isCivilNight)
    #expect(result.isCurrencyNight == false)
  }

  @Test
  func `is night under both definitions in the middle of the night`() {
    let result = classify("2024-12-22T10:30:00Z")

    #expect(result.isCivilNight)
    #expect(result.isCurrencyNight == true)
  }

  @Test
  func `leaves currency night unknown where the Sun doesn't rise`() {
    let result = classify("2024-12-21T12:00:00Z", latitude: 80)

    #expect(result.isCivilNight)
    #expect(result.isCurrencyNight == nil)
  }
}
