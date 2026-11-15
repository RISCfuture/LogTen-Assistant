import Foundation
import References

/// A date in UTC from an ISO 8601 string.
func utc(_ text: String) -> Date {
  guard let date = try? Date(text, strategy: .iso8601) else {
    preconditionFailure("Invalid test date \(text)")
  }
  return date
}

/// The folder of a fixture inside the test bundle.
func fixtureURL(_ path: String) -> URL {
  guard let url = Bundle.module.resourceURL?.appending(path: "Fixtures/\(path)"),
    FileManager.default.fileExists(atPath: url.path)
  else { preconditionFailure("Missing fixture \(path)") }
  return url
}

/// Two airports with one runway each, in the cycle that began 2025-10-30.
func sampleIndex() -> AirportIndex {
  AirportIndex(
    effectiveDate: utc("2025-10-30T00:00:00Z"),
    airports: [
      AirportReference(
        locationID: "SQL",
        ICAOID: "KSQL",
        name: "San Carlos",
        latitudeDeg: 37.5119,
        longitudeDeg: -122.2495,
        elevationFt: 5
      ),
      AirportReference(
        locationID: "SFO",
        ICAOID: "KSFO",
        name: "San Francisco Intl",
        latitudeDeg: 37.6188,
        longitudeDeg: -122.375,
        elevationFt: 13
      )
    ],
    runwayEnds: [
      RunwayEndReference(
        airportLocationID: "SQL",
        runwayID: "12/30",
        identifier: "12",
        latitudeDeg: 37.51525,
        longitudeDeg: -122.25362
      ),
      RunwayEndReference(
        airportLocationID: "SQL",
        runwayID: "12/30",
        identifier: "30",
        latitudeDeg: 37.50955,
        longitudeDeg: -122.2461
      ),
      RunwayEndReference(
        airportLocationID: "SFO",
        runwayID: "10L/28R",
        identifier: "10L",
        latitudeDeg: 37.6263,
        longitudeDeg: -122.393
      ),
      RunwayEndReference(
        airportLocationID: "SFO",
        runwayID: "10L/28R",
        identifier: "28R",
        latitudeDeg: 37.6131,
        longitudeDeg: -122.3569
      )
    ]
  )
}
