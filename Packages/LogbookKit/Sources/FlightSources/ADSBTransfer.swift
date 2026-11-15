public import Foundation

/// How an ADS-B download recovers from a dropped or stalled connection.
///
/// Each retry waits twice as long as the one before, with some jitter, up to a ceiling. The
/// count starts over whenever bytes arrive, so only failures in a row use up the attempts.
public struct ADSBRetryPolicy: Sendable {
  @usableFromInline static let defaultMaximumRetries = 8
  @usableFromInline static let defaultInitialDelay = Duration.seconds(2)
  @usableFromInline static let defaultMaximumDelay = Duration.seconds(60)
  private static let longestRetryAfter = Duration.seconds(15 * 60)
  private static let jitter = 0.8...1.2

  /// How many times in a row a part is retried before the download fails.
  public var maximumRetries: Int

  /// The wait before the first retry.
  public var initialDelay: Duration

  /// The longest wait between retries, unless the server asks for longer.
  public var maximumDelay: Duration

  private let sleep: @Sendable (Duration) async throws -> Void

  /**
   Creates a policy.

   - Parameters:
     - maximumRetries: How many times in a row a part is retried before the download fails.
     - initialDelay: The wait before the first retry.
     - maximumDelay: The longest wait between retries, unless the server asks for longer.
     - sleep: Waits between retries; throws `CancellationError` if the task is cancelled.
   */
  public init(
    maximumRetries: Int = defaultMaximumRetries,
    initialDelay: Duration = defaultInitialDelay,
    maximumDelay: Duration = defaultMaximumDelay,
    sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
  ) {
    self.maximumRetries = maximumRetries
    self.initialDelay = initialDelay
    self.maximumDelay = maximumDelay
    self.sleep = sleep
  }

  /// The wait before a retry, counting from one: exponential with jitter, or what a rate
  /// limit asked for.
  func delay(beforeRetry retry: Int, reason: ADSBRetryReason) -> Duration {
    if case .rateLimited(let retryAfter?) = reason {
      return min(.seconds(retryAfter), Self.longestRetryAfter)
    }
    let exponential = initialDelay * (1 << min(retry - 1, Int.bitWidth - 2))
    return min(exponential, maximumDelay) * Double.random(in: Self.jitter)
  }

  /// Waits before a retry.
  func wait(_ delay: Duration) async throws { try await sleep(delay) }
}

/// Why an ADS-B download is waiting to retry.
public enum ADSBRetryReason: Hashable, Sendable, CustomStringConvertible {
  /// The connection dropped or couldn't be made.
  case connectionLost
  /// No data arrived for too long.
  case stalled
  /// The server answered with a temporary error, such as HTTP 503.
  case serverError(status: Int)
  /// The server is rate limiting requests and asked to wait the given seconds, if it said.
  case rateLimited(retryAfter: TimeInterval?)

  public var description: String {
    switch self {
      case .connectionLost:
        String(localized: "Connection lost", bundle: .module)
      case .stalled:
        String(localized: "The connection stalled", bundle: .module)
      case .serverError(let status):
        String(
          localized:
            "The server answered with HTTP status \(status, format: .number.grouping(.never))",
          bundle: .module
        )
      case .rateLimited:
        String(localized: "adsb.lol is limiting requests", bundle: .module)
    }
  }
}

/// A retry an ADS-B download is waiting for.
public struct ADSBRetry: Hashable, Sendable {
  /// Which retry in a row this is, counting from one.
  public var attempt: Int
  /// Why the download is retrying.
  public var reason: ADSBRetryReason
  /// How long the download waits before reconnecting.
  public var delay: Duration
}

/// An ADS-B download that couldn't be completed.
public enum ADSBTransferError: Error, Equatable {
  /// A part kept failing until the retries ran out.
  case retriesExhausted(part: Int, partCount: Int, attempts: Int, reason: ADSBRetryReason)
  /// The server resumed a part from a different byte than was asked for.
  case unexpectedRange(part: Int, requested: Int64, contentRange: String?)
}

extension ADSBTransferError: LocalizedError {
  public var errorDescription: String? {
    String(localized: "Couldn’t download the ADS-B archive.", bundle: .module)
  }

  public var failureReason: String? {
    switch self {
      case let .retriesExhausted(part, partCount, attempts, reason):
        String(
          localized:
            "\(reason.description) on part \(part, format: .number) of \(partCount, format: .number), after \(attempts, format: .number) attempts.",
          bundle: .module
        )
      case let .unexpectedRange(part, requested, contentRange):
        String(
          localized:
            "Part \(part, format: .number) resumed at “\(contentRange ?? "")” instead of byte \(requested, format: .number.grouping(.never)).",
          bundle: .module
        )
    }
  }

  public var recoverySuggestion: String? {
    switch self {
      case .retriesExhausted:
        String(localized: "Check the internet connection, then retry.", bundle: .module)
      case .unexpectedRange:
        nil
    }
  }
}

/**
 Streams one part of an archive, reconnecting where it left off after a transient failure.

 A reconnection asks for the rest of the part with `Range: bytes=<offset>-`, always from the
 part's original URL so a signed redirect is issued afresh. A server that ignores the range and
 sends the whole part has the bytes already read skipped, so the consumer sees each byte once,
 in order. A body that ends short of the part's size counts as a dropped connection. A stall
 surfaces as `URLError.timedOut` from the session's request timeout, which applies between
 packets.
 */
struct ResumableTransfer {
  private static let partialContent = 206
  private static let requestTimeout = 408
  private static let serverErrors = 500..<600
  private static let resumableResetCodes: Set<Int32> = [ECONNRESET, ECONNABORTED, EPIPE]
  private static let sslClosedAbort = -9_806
  private static let streamErrorCodeKey = "_kCFStreamErrorCodeKey"

  let transport: any HTTPTransport
  let url: URL
  let part: Int
  let partCount: Int
  let policy: ADSBRetryPolicy

  /// The bytes of the part delivered so far.
  private(set) var offset: Int64 = 0
  private var size: Int64?
  private var failures = 0

  init(
    transport: any HTTPTransport,
    url: URL,
    part: Int,
    partCount: Int,
    policy: ADSBRetryPolicy
  ) {
    self.transport = transport
    self.url = url
    self.part = part
    self.partCount = partCount
    self.policy = policy
  }

  /// Why a failure is worth retrying, or `nil` if it isn't.
  static func retryReason(for error: any Error) -> ADSBRetryReason? {
    switch error {
      case let error as URLError: reason(for: error)
      case FlightSourceError.rateLimited(_, let retryAfter): .rateLimited(retryAfter: retryAfter)
      case FlightSourceError.httpStatus(_, let status) where isTransient(status: status):
        .serverError(status: status)
      default: nil
    }
  }

  private static func reason(for error: URLError) -> ADSBRetryReason? {
    switch error.code {
      case .timedOut:
        .stalled
      case .networkConnectionLost, .notConnectedToInternet, .cannotConnectToHost, .cannotFindHost,
        .dnsLookupFailed:
        .connectionLost
      case .secureConnectionFailed where wasReset(error as NSError):
        .connectionLost
      default:
        nil
    }
  }

  private static func isTransient(status: Int) -> Bool {
    status == requestTimeout || serverErrors.contains(status)
  }

  /// Whether a TLS failure came from the connection being reset under it.
  private static func wasReset(_ error: NSError) -> Bool {
    if error.domain == NSPOSIXErrorDomain, resumableResetCodes.contains(Int32(error.code)) {
      return true
    }
    if error.userInfo[streamErrorCodeKey] as? Int == sslClosedAbort { return true }
    guard let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError else { return false }
    return wasReset(underlying)
  }

  /// The first byte and the full size in a `Content-Range: bytes <start>-<end>/<total>` header.
  private static func parse(contentRange: String) -> (start: Int64, total: Int64?)? {
    guard let match = contentRange.wholeMatch(of: #/bytes (\d+)-\d+\/(\d+|\*)/#),
      let start = Int64(match.1)
    else { return nil }
    return (start, Int64(match.2))
  }

  /**
   Streams the part to its end, or until `consume` returns `false`.

   - Parameters:
     - connected: Called each time a connection starts delivering, with the part's full size if
       the server said.
     - retrying: Called before waiting to retry.
     - consume: Receives each chunk; returns whether to keep going.
   - Throws: ``ADSBTransferError`` once the retries run out, the first error that isn't
     transient, or `CancellationError`.
   */
  mutating func run(
    connected: (Int64?) -> Void,
    retrying: (ADSBRetry) -> Void,
    consume: (Data) throws -> Bool
  ) async throws {
    while true {
      let start = offset
      do {
        try await stream(connected: connected, consume: consume)
        return
      } catch {
        guard let reason = Self.retryReason(for: error) else { throw error }
        if let size, offset >= size { return }
        failures = offset > start ? 1 : failures + 1
        guard failures <= policy.maximumRetries else {
          throw ADSBTransferError.retriesExhausted(
            part: part,
            partCount: partCount,
            attempts: failures,
            reason: reason
          )
        }
        let retry = ADSBRetry(
          attempt: failures,
          reason: reason,
          delay: policy.delay(beforeRetry: failures, reason: reason)
        )
        retrying(retry)
        try await policy.wait(retry.delay)
      }
    }
  }

  private mutating func stream(
    connected: (Int64?) -> Void,
    consume: (Data) throws -> Bool
  ) async throws {
    let (chunks, response) = try await transport.stream(for: request())
    var skip = try bytesToSkip(in: response)
    connected(size)
    for try await chunk in chunks {
      var chunk = chunk
      if skip > 0 {
        let dropped = min(Int64(chunk.count), skip)
        chunk = chunk.dropFirst(Int(dropped))
        skip -= dropped
        if chunk.isEmpty { continue }
      }
      offset += Int64(chunk.count)
      guard try consume(chunk) else { return }
    }
    if let size, offset < size { throw URLError(.networkConnectionLost) }
  }

  private func request() -> URLRequest {
    var request = URLRequest(url: url)
    if offset > 0 { request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range") }
    return request
  }

  /// Validates a response and returns how many of its leading bytes were already delivered.
  private mutating func bytesToSkip(in response: HTTPURLResponse) throws -> Int64 {
    try response.validate(service: .adsbLol, acceptable: Set(200..<300))
    let length = response.expectedContentLength >= 0 ? response.expectedContentLength : nil
    guard response.statusCode == Self.partialContent else {
      size = length ?? size
      return offset
    }
    let contentRange = response.value(forHTTPHeaderField: "Content-Range")
    guard let range = contentRange.flatMap(Self.parse(contentRange:)), range.start == offset else {
      throw ADSBTransferError.unexpectedRange(
        part: part,
        requested: offset,
        contentRange: contentRange
      )
    }
    size = range.total ?? length.map { offset + $0 } ?? size
    return 0
  }
}
