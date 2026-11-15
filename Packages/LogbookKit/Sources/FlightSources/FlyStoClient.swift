public import Credentials
public import Foundation

/// A client for FlySto's public API (an early-preview API; see
/// https://www.flysto.net/public-api/swagger).
///
/// Requests carry the user's API token as a bearer token. The token comes from a closure so it
/// is read from the Keychain on each request and never held here.
public struct FlyStoClient: Sendable {
  /// The API's root.
  public static let baseURL = URL(string: "https://www.flysto.net/public-api")!

  /// The number of logs FlySto returns per page unless asked for fewer.
  public static let defaultPageSize = 250

  /// How many times and how often ``waitForProcessing(of:)`` polls by default.
  public static let defaultPolling = Polling(interval: .seconds(2), attempts: 30)

  private let transport: any HTTPTransport

  private let token: @Sendable () throws -> String?
  private let baseURL: URL

  private let polling: Polling
  private let sleep: @Sendable (Duration) async throws -> Void

  /// Creates a client that reads the token from the Keychain.
  public init(keychain: Keychain = Keychain(), transport: any HTTPTransport = URLSessionTransport())
  {
    self.init(token: { try keychain.string(for: .flyStoAPIToken) }, transport: transport)
  }

  /**
   Creates a client.

   - Parameters:
     - token: Returns the API token, or `nil` if none is stored.
     - transport: The network layer.
     - baseURL: The API root; tests substitute their own.
     - polling: How to poll for upload processing.
     - sleep: Pauses between polls; tests substitute an immediate one.
   */
  public init(
    token: @escaping @Sendable () throws -> String?,
    transport: any HTTPTransport = URLSessionTransport(),
    baseURL: URL = Self.baseURL,
    polling: Polling = Self.defaultPolling,
    sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
  ) {
    self.token = token
    self.transport = transport
    self.baseURL = baseURL
    self.polling = polling
    self.sleep = sleep
  }

  /**
   Fetches logs, following the `next` link until the list ends.

   - Parameters:
     - cursor: The ``Sync/cursor`` of a previous sync, to fetch only logs added since.
     - type: Which logs to list.
     - limit: The page size.
     - progress: Called with the number of logs fetched so far after each page.
   - Throws: ``FlightSourceError`` for a missing or rejected token, and for a `next` link that
     leaves FlySto's host.
   */
  public func syncLogs(
    after cursor: String? = nil,
    type: LogType = .all,
    limit: Int = defaultPageSize,
    progress: (@Sendable (Int) -> Void)? = nil
  ) async throws -> Sync {
    var query = [URLQueryItem(name: "type", value: type.rawValue)]
    query.append(URLQueryItem(name: "limit", value: String(limit)))
    if let cursor { query.append(URLQueryItem(name: "after", value: cursor)) }

    var logs = [FlyStoLog]()
    var syncCursor: String?
    var undecodableCount = 0
    var url: URL? = endpoint("logs", query: query)
    var isFirstPage = true
    while let pageURL = url {
      try Task.checkCancellation()
      let page = try await fetchPage(pageURL)
      if isFirstPage { syncCursor = page.timestamp }
      isFirstPage = false
      logs += page.logs
      undecodableCount += page.undecodableCount
      progress?(logs.count)
      url = try page.next.map(trusted)
    }
    return Sync(logs: logs, undecodableCount: undecodableCount, cursor: syncCursor)
  }

  /// Fetches the crew list.
  public func crew() async throws -> [FlyStoCrewEntry] {
    let (data, _) = try await send(URLRequest(url: endpoint("crew")))
    return try decode(LossyArray<FlyStoCrewEntry>.self, from: data).elements
  }

  /**
   Uploads a zipped data log (a ZIP containing exactly one file).

   - Parameters:
     - archive: The ZIP file's contents.
     - reference: An optional reference FlySto stores with the upload.
   - Returns: The file's identifier. A 409 response means FlySto already has the file and is
     reported through ``FlyStoUpload/wasAlreadyUploaded`` instead of being thrown.
   */
  public func upload(archive: Data, reference: String? = nil) async throws -> FlyStoUpload {
    var query = [URLQueryItem]()
    if let reference { query.append(URLQueryItem(name: "id", value: reference)) }
    var request = URLRequest(url: endpoint("log-upload", query: query))
    request.httpMethod = "POST"
    request.setValue("application/zip", forHTTPHeaderField: "Content-Type")
    request.httpBody = archive
    let (data, response) = try await send(request, acceptable: Set(200..<300).union([409]))
    struct Body: Decodable { let fileId: String }
    let body = try decode(Body.self, from: data)
    return FlyStoUpload(fileID: body.fileId, wasAlreadyUploaded: response.statusCode == 409)
  }

  /// Asks whether FlySto has processed an uploaded file.
  public func processing(of fileID: String) async throws -> FlyStoProcessing {
    let (data, _) = try await send(URLRequest(url: endpoint("log-files/\(fileID)")))
    struct Body: Decodable {
      let processed: Bool
      let logs: [String]?
    }
    let body = try decode(Body.self, from: data)
    return body.processed ? .processed(logIDs: body.logs ?? []) : .pending
  }

  /**
   Polls until FlySto has processed an uploaded file.

   - Returns: The identifiers of the logs FlySto created, or `nil` if it hadn't finished after
     the configured number of polls.
   */
  public func waitForProcessing(of fileID: String) async throws -> [String]? {
    for attempt in 0..<polling.attempts {
      if attempt > 0 { try await sleep(polling.interval) }
      if case .processed(let logIDs) = try await processing(of: fileID) { return logIDs }
    }
    return nil
  }

  private func fetchPage(_ url: URL) async throws -> FlyStoLogPage {
    let (data, _) = try await send(URLRequest(url: url))
    return try decode(FlyStoLogPage.self, from: data)
  }

  private func endpoint(_ path: String, query: [URLQueryItem] = []) -> URL {
    var components = URLComponents(
      url: baseURL.appending(path: path),
      resolvingAgainstBaseURL: false
    )!
    if !query.isEmpty { components.queryItems = query }
    return components.url!
  }

  /// Returns a `next` link unchanged if it points at the API's own host, so the bearer token
  /// is never sent elsewhere.
  private func trusted(_ url: URL) throws -> URL {
    guard url.scheme == baseURL.scheme, url.host() == baseURL.host() else {
      throw FlightSourceError.untrustedURL(url)
    }
    return url
  }

  private func send(
    _ request: URLRequest,
    acceptable: Set<Int> = Set(200..<300)
  ) async throws -> (Data, HTTPURLResponse) {
    guard let token = try token() else { throw FlightSourceError.missingCredentials(.flySto) }
    var request = request
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    return try await transport.checkedData(for: request, service: .flySto, acceptable: acceptable)
  }

  private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
    do {
      return try JSONDecoder().decode(type, from: data)
    } catch {
      throw FlightSourceError.malformedResponse(.flySto, detail: String(describing: error))
    }
  }

  /// How to poll for an uploaded file to finish processing.
  public struct Polling: Sendable {
    /// The pause between polls.
    public var interval: Duration
    /// The most polls to make.
    public var attempts: Int

    /// Creates a polling schedule.
    public init(interval: Duration, attempts: Int) {
      self.interval = interval
      self.attempts = attempts
    }
  }

  /// Which logs `GET /logs` lists.
  public enum LogType: String, Sendable {
    /// Every recorded activity, including engine runs that never flew.
    case all
    /// Flights only.
    case flight
  }

  /// The logs fetched by a sync and the cursor to continue from next time.
  public struct Sync: Sendable {
    /// The logs, newest first.
    public var logs: [FlyStoLog]
    /// How many logs FlySto returned that couldn't be decoded and are missing from ``logs``.
    public var undecodableCount: Int
    /// The `timestamp` of the first page, to pass as `after` on the next sync.
    public var cursor: String?
  }
}
