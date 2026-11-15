public import Foundation

/// The network layer the data-source clients talk through, so tests can substitute recorded
/// responses and the app can substitute a configured session.
public protocol HTTPTransport: Sendable {
  /// Performs a request and returns the whole response body.
  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)

  /**
   Performs a request and returns the body as it arrives, for responses too large to hold in
   memory. Cancelling the consuming task, or ending iteration early, cancels the transfer.
   */
  func stream(
    for request: URLRequest
  ) async throws -> (AsyncThrowingStream<Data, any Error>, HTTPURLResponse)
}

/// An ``HTTPTransport`` backed by a `URLSession`.
public struct URLSessionTransport: HTTPTransport {
  private static let chunkSize = 256 * 1_024

  private let session: URLSession

  /// Creates a transport over a session.
  public init(session: URLSession = .shared) {
    self.session = session
  }

  private static func httpResponse(_ response: URLResponse) throws -> HTTPURLResponse {
    guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
    return http
  }

  public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let (data, response) = try await session.data(for: request)
    return (data, try Self.httpResponse(response))
  }

  public func stream(
    for request: URLRequest
  ) async throws -> (AsyncThrowingStream<Data, any Error>, HTTPURLResponse) {
    let (bytes, response) = try await session.bytes(for: request)
    let http = try Self.httpResponse(response)
    let chunks = AsyncThrowingStream<Data, any Error> { continuation in
      let task = Task {
        do {
          var buffer = Data()
          buffer.reserveCapacity(Self.chunkSize)
          for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= Self.chunkSize {
              continuation.yield(buffer)
              buffer.removeAll(keepingCapacity: true)
            }
          }
          if !buffer.isEmpty { continuation.yield(buffer) }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
    return (chunks, http)
  }
}

/// A web service the app fetches flight evidence from.
public enum FlightService: String, CaseIterable, Codable, Sendable {
  /// FlySto's public API.
  case flySto = "fly_sto"
  /// The adsb.lol historical archive.
  case adsbLol = "adsb_lol"
  /// The OpenSky Network.
  case openSky = "open_sky"

  /// The service's display name.
  public var displayName: String {
    switch self {
      case .flySto: "FlySto"
      case .adsbLol: "adsb.lol"
      case .openSky: "OpenSky Network"
    }
  }
}

/// An error fetching or importing flight evidence.
public enum FlightSourceError: Error, Equatable {
  /// No credentials are stored for the service.
  case missingCredentials(FlightService)
  /// The service rejected the credentials or the token lacks a permission.
  case unauthorized(FlightService)
  /// The service answered with an unexpected HTTP status.
  case httpStatus(FlightService, Int)
  /// The service is rate limiting requests; `retryAfter` is how long it asked callers to wait.
  case rateLimited(FlightService, retryAfter: TimeInterval?)
  /// The service answered with data that doesn't have the expected shape.
  case malformedResponse(FlightService, detail: String)
  /// A URL points somewhere the client won't send credentials or download from.
  case untrustedURL(URL)
  /// An imported file isn't the export it was expected to be.
  case invalidImport(file: String, detail: String)
  /// The ADS-B archive has no single preferred release for a day.
  case noPreferredRelease(day: String, matches: Int)
  /// An ADS-B file's contents don't match its recorded SHA-256 digest.
  case checksumMismatch(file: String)
}

extension FlightSourceError: LocalizedError {
  public var errorDescription: String? {
    switch self {
      case .missingCredentials(let service):
        String(localized: "No credentials for \(service.displayName).", bundle: .module)
      case .unauthorized(let service):
        String(localized: "\(service.displayName) rejected the credentials.", bundle: .module)
      case .httpStatus(let service, _), .malformedResponse(let service, _):
        String(localized: "Couldn’t get data from \(service.displayName).", bundle: .module)
      case .rateLimited(let service, _):
        String(localized: "\(service.displayName) is limiting requests.", bundle: .module)
      case .untrustedURL:
        String(localized: "Refused to use an unexpected web address.", bundle: .module)
      case .invalidImport:
        String(localized: "Couldn’t import the file.", bundle: .module)
      case .noPreferredRelease:
        String(localized: "The ADS-B archive has no release for that day.", bundle: .module)
      case .checksumMismatch:
        String(localized: "A saved ADS-B file was modified.", bundle: .module)
    }
  }

  public var failureReason: String? {
    switch self {
      case .missingCredentials, .unauthorized:
        nil
      case .httpStatus(_, let status):
        String(localized: "The server answered with HTTP status \(status).", bundle: .module)
      case .rateLimited(_, let retryAfter):
        retryAfter.map {
          String(localized: "Try again in \($0, format: .number) seconds.", bundle: .module)
        }
      case .malformedResponse(_, detail: let detail), .invalidImport(file: _, detail: let detail):
        detail
      case .untrustedURL(let url):
        url.absoluteString
      case let .noPreferredRelease(day, matches):
        String(localized: "Found \(matches) releases for \(day).", bundle: .module)
      case .checksumMismatch(let file):
        file
    }
  }

  public var recoverySuggestion: String? {
    switch self {
      case .missingCredentials, .unauthorized:
        String(localized: "Check the account in Settings.", bundle: .module)
      default:
        nil
    }
  }
}

extension HTTPTransport {
  /// Performs a request and throws ``FlightSourceError`` for the statuses every service uses
  /// to report rejected credentials or rate limiting.
  func checkedData(
    for request: URLRequest,
    service: FlightService,
    acceptable: Set<Int> = Set(200..<300)
  ) async throws -> (Data, HTTPURLResponse) {
    let (data, response) = try await self.data(for: request)
    try response.validate(service: service, acceptable: acceptable)
    return (data, response)
  }
}

extension HTTPURLResponse {
  func validate(service: FlightService, acceptable: Set<Int>) throws {
    guard !acceptable.contains(statusCode) else { return }
    switch statusCode {
      case 401, 403:
        throw FlightSourceError.unauthorized(service)
      case 429:
        let wait =
          value(forHTTPHeaderField: "X-Rate-Limit-Retry-After-Seconds")
          ?? value(forHTTPHeaderField: "Retry-After")
        throw FlightSourceError.rateLimited(service, retryAfter: wait.flatMap(TimeInterval.init))
      default:
        throw FlightSourceError.httpStatus(service, statusCode)
    }
  }
}
