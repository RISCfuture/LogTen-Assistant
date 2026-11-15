import Foundation

@testable import FlightSources

/// An ``HTTPTransport`` that answers from a table of canned responses and records requests.
final class StubTransport: HTTPTransport, @unchecked Sendable {
  private let lock = NSLock()
  private var replies: [String: [Reply]]
  private var seen = [URLRequest]()
  var requests: [URLRequest] { lock.withLock { seen } }

  /// Creates a stub; each key is `METHOD url`, and each reply is used once, in order, with the
  /// last one repeating.
  init(_ replies: [String: [Reply]]) {
    self.replies = replies
  }

  convenience init(_ replies: [String: Reply]) {
    self.init(replies.mapValues { [$0] })
  }

  private func reply(for request: URLRequest) throws -> (Reply, HTTPURLResponse) {
    let key = "\(request.httpMethod ?? "GET") \(request.url!.absoluteString)"
    let reply: Reply = try lock.withLock {
      seen.append(request)
      guard var queue = replies[key], let first = queue.first else {
        throw URLError(
          .fileDoesNotExist,
          userInfo: [NSLocalizedDescriptionKey: "No stub for \(key)"]
        )
      }
      if queue.count > 1 {
        queue.removeFirst()
        replies[key] = queue
      }
      return first
    }
    let response = HTTPURLResponse(
      url: request.url!,
      statusCode: reply.status,
      httpVersion: nil,
      headerFields: reply.headers
    )!
    return (reply, response)
  }

  // swiftlint:disable:next async_without_await
  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let (reply, response) = try reply(for: request)
    return (reply.body, response)
  }

  // swiftlint:disable:next async_without_await
  func stream(for request: URLRequest) async throws -> (
    AsyncThrowingStream<Data, any Error>, HTTPURLResponse
  ) {
    let (reply, response) = try reply(for: request)
    let chunks = AsyncThrowingStream<Data, any Error> { continuation in
      var start = reply.body.startIndex
      while start < reply.body.endIndex {
        let end = min(start + reply.chunkSize, reply.body.endIndex)
        continuation.yield(reply.body[start..<end])
        start = end
      }
      continuation.finish(throwing: reply.failure)
    }
    return (chunks, response)
  }

  struct Reply {
    var status = 200
    var body = Data()
    var headers = [String: String]()
    var chunkSize = 1_000_000
    /// An error the body stream ends with after its bytes, as when a connection drops.
    var failure: URLError?
  }
}

extension StubTransport.Reply {
  static func json(_ text: String, status: Int = 200) -> Self {
    Self(status: status, body: Data(text.utf8))
  }

  static func status(_ status: Int, headers: [String: String] = [:]) -> Self {
    Self(status: status, headers: headers)
  }
}

/// Builds tar archives for the reader tests.
enum TarBuilder {
  static func entry(
    name: String,
    contents: Data,
    typeFlag: Character = "0",
    prefix: String = ""
  ) -> Data {
    var header = Data(count: 512)
    func put(_ text: String, at offset: Int) {
      header.replaceSubrange(offset..<(offset + text.utf8.count), with: Data(text.utf8))
    }
    put(name, at: 0)
    put("0000644\0", at: 100)
    put("0000000\0", at: 108)
    put("0000000\0", at: 116)
    put(octal(contents.count, width: 11) + "\0", at: 124)
    put("00000000000\0", at: 136)
    put("        ", at: 148)
    put(String(typeFlag), at: 156)
    put("ustar\0", at: 257)
    put("00", at: 263)
    put(prefix, at: 345)
    let sum = header.reduce(0) { $0 + Int($1) }
    put(octal(sum, width: 6) + "\0 ", at: 148)
    let padding = Data(count: (512 - contents.count % 512) % 512)
    return header + contents + padding
  }

  static func archive(_ entries: [Data]) -> Data {
    entries.reduce(Data(), +) + Data(count: 1024)
  }

  private static func octal(_ value: Int, width: Int) -> String {
    let digits = String(value, radix: 8)
    return String(repeating: "0", count: width - digits.count) + digits
  }
}

/// Wraps data in a gzip container.
func gzipped(_ data: Data) throws -> Data {
  // swiftlint:disable:next legacy_objc_type
  let deflated = try (data as NSData).compressed(using: .zlib) as Data
  var trailer = Data()
  for value in [CRC32.checksum(data), UInt32(data.count)] {
    withUnsafeBytes(of: value.littleEndian) { trailer.append(contentsOf: $0) }
  }
  return Data([0x1F, 0x8B, 8, 0, 0, 0, 0, 0, 0, 3]) + deflated + trailer
}

func fixture(_ name: String) throws -> Data {
  guard let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")
  else { throw CocoaError(.fileNoSuchFile) }
  return try Data(contentsOf: url)
}

func utc(_ text: String) -> Date {
  guard let date = try? Date(text, strategy: .iso8601) else {
    preconditionFailure("Invalid test date \(text)")
  }
  return date
}
