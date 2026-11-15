import Foundation
import LogbookModel
import Testing
import Tracks

@testable import FlightSources

@Suite
struct `OpenSky client` {
  private static let tokenKey = "POST \(OpenSkyClient.tokenURL.absoluteString)"
  private static let address = ICAOAddress(hex: "a97ded")!
  private static let flightsKey =
    "GET https://opensky-network.org/api/flights/aircraft?icao24=a97ded&begin=1741132800&end=1741136400"
  private static let tracksKey =
    "GET https://opensky-network.org/api/tracks?icao24=a97ded&time=1741134000"
  private static let interval = DateInterval(
    start: Date(timeIntervalSince1970: 1_741_132_800),
    duration: 3_600
  )
  private static let token = StubTransport.Reply.json(
    #"{"access_token": "tok-1", "expires_in": 1800}"#
  )

  private func client(
    _ transport: StubTransport,
    retryPolicy: OpenSkyClient.RetryPolicy = .init(),
    secret: String? = "shh"
  ) -> OpenSkyClient {
    OpenSkyClient(
      credentials: { secret.map { .init(id: "my-client", secret: $0) } },
      transport: transport,
      retryPolicy: retryPolicy,
      now: { Date(timeIntervalSince1970: 1_741_132_800) },
      sleep: { _ in }
    )
  }

  @Test
  func `fetches a token with client credentials and uses it as a bearer token`() async throws {
    let body =
      #"[{"icao24": "a97ded", "firstSeen": 1741133000, "lastSeen": 1741135000, "estDepartureAirport": "KSQL", "estArrivalAirport": null, "callsign": "N12345  "}]"#
    let transport = StubTransport([Self.tokenKey: Self.token, Self.flightsKey: .json(body)])

    let flights = try await client(transport).flights(of: Self.address, during: Self.interval)

    #expect(flights.first?.callsign == "N12345")
    #expect(flights.first?.estArrivalAirport == nil)
    let tokenRequest = try #require(transport.requests.first)
    let form = (String(bytes: try #require(tokenRequest.httpBody), encoding: .utf8) ?? "")
    #expect(form == "grant_type=client_credentials&client_id=my-client&client_secret=shh")
    #expect(transport.requests.last?.value(forHTTPHeaderField: "Authorization") == "Bearer tok-1")
  }

  @Test
  func `reuses the token until it nears expiry`() async throws {
    let transport = StubTransport([Self.tokenKey: Self.token, Self.flightsKey: .json("[]")])
    let client = client(transport)

    _ = try await client.flights(of: Self.address, during: Self.interval)
    _ = try await client.flights(of: Self.address, during: Self.interval)

    #expect(transport.requests.filter { $0.httpMethod == "POST" }.count == 1)
  }

  @Test
  func `waits out a short rate limit and retries`() async throws {
    let limited = StubTransport.Reply.status(
      429,
      headers: ["X-Rate-Limit-Retry-After-Seconds": "5"]
    )
    let transport = StubTransport([
      Self.tokenKey: [Self.token],
      Self.flightsKey: [limited, .json("[]")]
    ])

    let flights = try await client(transport).flights(of: Self.address, during: Self.interval)

    #expect(flights.isEmpty)
    #expect(transport.requests.filter { $0.httpMethod == "GET" }.count == 2)
  }

  @Test
  func `reports a long rate limit instead of waiting`() async throws {
    let limited = StubTransport.Reply.status(
      429,
      headers: ["X-Rate-Limit-Retry-After-Seconds": "3600"]
    )
    let transport = StubTransport([Self.tokenKey: Self.token, Self.flightsKey: limited])

    await #expect(throws: FlightSourceError.rateLimited(.openSky, retryAfter: 3_600)) {
      try await client(transport).flights(of: Self.address, during: Self.interval)
    }
  }

  @Test
  func `refreshes the token once after a 401`() async throws {
    let transport = StubTransport([
      Self.tokenKey: [
        .json(#"{"access_token": "old", "expires_in": 1800}"#),
        .json(#"{"access_token": "new", "expires_in": 1800}"#)
      ],
      Self.flightsKey: [.status(401), .json("[]")]
    ])

    _ = try await client(transport).flights(of: Self.address, during: Self.interval)

    #expect(transport.requests.last?.value(forHTTPHeaderField: "Authorization") == "Bearer new")
  }

  @Test
  func `treats a 404 as no flights and reports bad credentials`() async throws {
    let transport = StubTransport([Self.tokenKey: Self.token, Self.flightsKey: .status(404)])
    #expect(try await client(transport).flights(of: Self.address, during: Self.interval).isEmpty)

    let rejected = StubTransport([Self.tokenKey: .status(401)])
    await #expect(throws: FlightSourceError.unauthorized(.openSky)) {
      try await client(rejected).testConnection()
    }
    await #expect(throws: FlightSourceError.missingCredentials(.openSky)) {
      try await client(transport, secret: nil).testConnection()
    }
  }

  @Test
  func `reads a track and converts altitude to feet`() async throws {
    let body =
      #"{"icao24": "a97ded", "startTime": 1741133000, "endTime": 1741135000, "path": [[1741133000, 37.0, -122.0, 1000.0, 90, false], [1741133010, 37.1, -122.0, null, 90, true], [1741133020, null, -122.0, 0, 0, false]]}"#
    let transport = StubTransport([Self.tokenKey: Self.token, Self.tracksKey: .json(body)])

    let track = try #require(
      try await client(transport).track(
        of: Self.address,
        at: Date(timeIntervalSince1970: 1_741_134_000)
      )
    )

    #expect(track.samples.count == 2)
    #expect(abs((track.samples[0].altitudeFt ?? 0) - 3_280.84) < 0.01)
    #expect(track.samples[1].altitudeFt == nil)
    #expect(track.samples[1].isOnGround == true)
    #expect(track.provenance?.source == .openSky)
    #expect(track.provenance?.sha256 == sha256Hex(of: Data(body.utf8)))
  }

  @Test
  func `serves tracks for a registration through its flights`() async throws {
    let flights = #"[{"icao24": "a97ded", "firstSeen": 1741133000, "lastSeen": 1741135000}]"#
    let track = #"{"path": [[1741133000, 37.0, -122.0, 100, 0, false]]}"#
    let transport = StubTransport([
      Self.tokenKey: Self.token,
      Self.flightsKey: .json(flights),
      "GET https://opensky-network.org/api/tracks?icao24=a97ded&time=1741134000": .json(track)
    ])
    let source = OpenSkyTrackSource(client: client(transport)) {
      ICAOAddress(usRegistration: $0) == nil ? nil : Self.address
    }

    let tracks = try await source.tracks(for: "N12345", during: Self.interval)
    let unknown = try await source.tracks(for: "G-ABCD", during: Self.interval)

    #expect(tracks.map(\.registration) == ["N12345"])
    #expect(unknown.isEmpty)
  }
}
