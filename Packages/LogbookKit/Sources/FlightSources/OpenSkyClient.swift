public import Credentials
public import Foundation
public import LogbookModel
public import Tracks

/// A flight the OpenSky Network inferred from ADS-B and Mode S reception.
public struct OpenSkyFlight: Hashable, Decodable, Sendable {
  /// The aircraft's ICAO address as lowercase hexadecimal.
  public var icao24: String

  /// The estimated takeoff time.
  public var firstSeen: Date

  /// The estimated landing time.
  public var lastSeen: Date

  /// The estimated departure airport, as an ICAO identifier.
  public var estDepartureAirport: String?

  /// The estimated arrival airport, as an ICAO identifier.
  public var estArrivalAirport: String?

  /// The callsign, with trailing spaces removed.
  public var callsign: String?

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    icao24 = try container.decode(String.self, forKey: .icao24)
    firstSeen = Date(timeIntervalSince1970: try container.decode(Double.self, forKey: .firstSeen))
    lastSeen = Date(timeIntervalSince1970: try container.decode(Double.self, forKey: .lastSeen))
    estDepartureAirport = try container.decodeIfPresent(String.self, forKey: .estDepartureAirport)
    estArrivalAirport = try container.decodeIfPresent(String.self, forKey: .estArrivalAirport)
    callsign = try container.decodeIfPresent(String.self, forKey: .callsign)?
      .trimmingCharacters(in: .whitespaces)
  }

  private enum CodingKeys: String, CodingKey {
    case icao24, firstSeen, lastSeen, estDepartureAirport, estArrivalAirport, callsign
  }
}

/// A client for the OpenSky Network REST API, authenticating with OAuth2 client credentials.
///
/// The client ID and secret come from closures (the Keychain, in the app). Access tokens are
/// cached until shortly before they expire. When OpenSky answers 429, the client waits the
/// number of seconds in `X-Rate-Limit-Retry-After-Seconds` and retries if the wait is short;
/// otherwise it throws ``FlightSourceError/rateLimited(_:retryAfter:)`` for the caller to show.
public actor OpenSkyClient {
  /// The OAuth2 token endpoint.
  public static let tokenURL = URL(
    string:
      "https://auth.opensky-network.org/auth/realms/opensky-network/protocol/openid-connect/token"
  )!

  /// The REST API's root.
  public static let apiURL = URL(string: "https://opensky-network.org/api")!

  /// The name tracks from this source carry.
  public static let sourceName = "OpenSky"

  /// The longest `flights/aircraft` window the API accepts.
  public static let longestFlightWindow: TimeInterval = 2 * 86_400

  private static let tokenSafetyMargin: TimeInterval = 30
  private static let metersToFeet = 3.280_84

  private let credentials: @Sendable () throws -> Credentials?
  private let transport: any HTTPTransport
  private let retryPolicy: RetryPolicy
  private let now: @Sendable () -> Date
  private let sleep: @Sendable (Duration) async throws -> Void
  private var token: Token?

  /// Creates a client that reads the OAuth client from the Keychain.
  public init(keychain: Keychain = Keychain(), transport: any HTTPTransport = URLSessionTransport())
  {
    self.init(
      credentials: {
        guard let id = try keychain.string(for: .openSkyClientID),
          let secret = try keychain.string(for: .openSkyClientSecret)
        else { return nil }
        return Credentials(id: id, secret: secret)
      },
      transport: transport
    )
  }

  /**
   Creates a client.

   - Parameters:
     - credentials: Returns the OAuth client credentials, or `nil` if none are stored.
     - transport: The network layer.
     - retryPolicy: How to respond to rate limiting.
     - now: The clock, for token expiry and provenance.
     - sleep: Pauses before a retry; tests substitute an immediate one.
   */
  public init(
    credentials: @escaping @Sendable () throws -> Credentials?,
    transport: any HTTPTransport = URLSessionTransport(),
    retryPolicy: RetryPolicy = .init(),
    now: @escaping @Sendable () -> Date = { Date() },
    sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
  ) {
    self.credentials = credentials
    self.transport = transport
    self.retryPolicy = retryPolicy
    self.now = now
    self.sleep = sleep
  }

  /// Requests a fresh token, to check that the stored credentials work.
  public func testConnection() async throws {
    token = nil
    _ = try await accessToken()
  }

  /**
   Lists the flights an aircraft made in a window.

   - Parameters:
     - address: The aircraft's ICAO address.
     - interval: The window, at most ``longestFlightWindow`` long.
   - Returns: The flights, or none if OpenSky has none (a 404 answer).
   */
  public func flights(of address: ICAOAddress, during interval: DateInterval) async throws
    -> [OpenSkyFlight]
  {
    let query = [
      URLQueryItem(name: "icao24", value: address.hex),
      URLQueryItem(name: "begin", value: String(Int(interval.start.timeIntervalSince1970))),
      URLQueryItem(name: "end", value: String(Int(interval.end.timeIntervalSince1970)))
    ]
    guard let (data, _) = try await get("flights/aircraft", query: query, allowsNotFound: true)
    else { return [] }
    return try decode([OpenSkyFlight].self, from: data)
  }

  /**
   Fetches the track of the flight in progress at a moment.

   - Parameters:
     - address: The aircraft's ICAO address.
     - time: Any moment during the flight, within OpenSky's retention (30 days).
   - Returns: The track, or `nil` if OpenSky has none.
   */
  public func track(of address: ICAOAddress, at time: Date) async throws -> Track? {
    let query = [
      URLQueryItem(name: "icao24", value: address.hex),
      URLQueryItem(name: "time", value: String(Int(time.timeIntervalSince1970)))
    ]
    guard let (data, response) = try await get("tracks", query: query, allowsNotFound: true)
    else { return nil }
    let raw = try decode(RawTrack.self, from: data)
    let source = SourceProvenance(
      source: .openSky,
      urls: response.url.map { [$0] } ?? [],
      sha256: sha256Hex(of: data),
      retrievedAt: now()
    )
    return Track(
      registration: address.hex,
      source: Self.sourceName,
      samples: raw.path.compactMap(\.sample),
      provenance: source
    )
  }

  private func get(
    _ path: String,
    query: [URLQueryItem],
    allowsNotFound: Bool = false
  ) async throws -> (Data, HTTPURLResponse)? {
    var components = URLComponents(
      url: Self.apiURL.appending(path: path),
      resolvingAgainstBaseURL: false
    )!
    components.queryItems = query
    let url = components.url!

    var retries = 0
    var hasRefreshedToken = false
    while true {
      var request = URLRequest(url: url)
      request.setValue("Bearer \(try await accessToken())", forHTTPHeaderField: "Authorization")
      let (data, response) = try await transport.data(for: request)
      switch response.statusCode {
        case 200..<300:
          return (data, response)
        case 404 where allowsNotFound:
          return nil
        case 401 where !hasRefreshedToken:
          hasRefreshedToken = true
          token = nil
        case 429:
          let retryAfter = response.value(forHTTPHeaderField: "X-Rate-Limit-Retry-After-Seconds")
            .flatMap(TimeInterval.init)
          guard retries < retryPolicy.maximumRetries, let wait = retryAfter,
            Duration.seconds(wait) <= retryPolicy.maximumWait
          else { throw FlightSourceError.rateLimited(.openSky, retryAfter: retryAfter) }
          retries += 1
          try await sleep(.seconds(wait))
        default:
          try response.validate(service: .openSky, acceptable: [])
      }
    }
  }

  private func accessToken() async throws -> String {
    if let token, token.expires > now() { return token.value }
    guard let credentials = try credentials() else {
      throw FlightSourceError.missingCredentials(.openSky)
    }
    var request = URLRequest(url: Self.tokenURL)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    var form = URLComponents()
    form.queryItems = [
      URLQueryItem(name: "grant_type", value: "client_credentials"),
      URLQueryItem(name: "client_id", value: credentials.id),
      URLQueryItem(name: "client_secret", value: credentials.secret)
    ]
    request.httpBody = Data((form.percentEncodedQuery ?? "").utf8)

    let (data, response) = try await transport.data(for: request)
    switch response.statusCode {
      case 200..<300:
        break
      case 400, 401:
        throw FlightSourceError.unauthorized(.openSky)
      default:
        try response.validate(service: .openSky, acceptable: [])
    }
    struct TokenResponse: Decodable {
      let accessToken: String
      let expiresIn: Double

      private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
      }
    }
    let issued = try decode(TokenResponse.self, from: data)
    let fresh = Token(
      value: issued.accessToken,
      expires: now().addingTimeInterval(issued.expiresIn - Self.tokenSafetyMargin)
    )
    token = fresh
    return fresh.value
  }

  private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
    do {
      return try JSONDecoder().decode(type, from: data)
    } catch {
      throw FlightSourceError.malformedResponse(.openSky, detail: String(describing: error))
    }
  }

  /// A client ID and secret.
  public struct Credentials: Sendable {
    /// The OAuth client ID.
    public var id: String
    /// The OAuth client secret.
    public var secret: String

    /// Creates credentials.
    public init(id: String, secret: String) {
      self.id = id
      self.secret = secret
    }
  }

  /// How the client responds to rate limiting.
  public struct RetryPolicy: Sendable {
    /// The longest wait the client will sit through before retrying.
    public var maximumWait: Duration
    /// The most retries after the first attempt.
    public var maximumRetries: Int

    /// Creates a policy.
    public init(maximumWait: Duration = .seconds(60), maximumRetries: Int = 2) {
      self.maximumWait = maximumWait
      self.maximumRetries = maximumRetries
    }
  }

  private struct Token {
    var value: String
    var expires: Date
  }

  /// The `/tracks` response; each path entry is
  /// `[time, latitude, longitude, barometric altitude (m), true track, on ground]`.
  private struct RawTrack: Decodable {
    let path: [Waypoint]

    struct Waypoint: Decodable {
      private var time: Double?
      private var latitude: Double?
      private var longitude: Double?
      private var altitudeMeters: Double?
      private var onGround: Bool?

      var sample: TrackSample? {
        guard let time, let latitude, let longitude else { return nil }
        return TrackSample(
          time: Date(timeIntervalSince1970: time),
          latitudeDeg: latitude,
          longitudeDeg: longitude,
          altitudeFt: altitudeMeters.map { $0 * OpenSkyClient.metersToFeet },
          isOnGround: onGround
        )
      }

      init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        time = try container.decodeIfPresent(Double.self)
        latitude = try container.decodeIfPresent(Double.self)
        longitude = try container.decodeIfPresent(Double.self)
        altitudeMeters = try container.decodeIfPresent(Double.self)
        _ = try container.decodeIfPresent(Double.self)
        onGround = try container.decodeIfPresent(Bool.self)
      }
    }
  }
}

/// A ``TrackSource`` that reads aircraft tracks from OpenSky.
///
/// OpenSky identifies aircraft by ICAO address, so the source needs a way to turn a
/// registration into one; the app supplies a per-aircraft override or the address derived from
/// a US registration. Tracks are returned under the registration asked for.
public struct OpenSkyTrackSource: TrackSource {
  public let name = OpenSkyClient.sourceName

  private let client: OpenSkyClient
  private let address: @Sendable (String) -> ICAOAddress?

  /// Creates a source.
  public init(client: OpenSkyClient, address: @escaping @Sendable (String) -> ICAOAddress?) {
    self.client = client
    self.address = address
  }

  public func tracks(for registration: String, during interval: DateInterval) async throws
    -> [Track]
  {
    guard let icao = address(registration) else { return [] }
    var tracks = [Track]()
    var windowStart = interval.start
    while windowStart < interval.end {
      let window = DateInterval(
        start: windowStart,
        end: min(interval.end, windowStart.addingTimeInterval(OpenSkyClient.longestFlightWindow))
      )
      for flight in try await client.flights(of: icao, during: window) {
        let midpoint = flight.firstSeen.addingTimeInterval(
          flight.lastSeen.timeIntervalSince(flight.firstSeen) / 2
        )
        if var track = try await client.track(of: icao, at: midpoint) {
          track.registration = registration
          tracks.append(track)
        }
      }
      windowStart = window.end
    }
    return tracks
  }
}
