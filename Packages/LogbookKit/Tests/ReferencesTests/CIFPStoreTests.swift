import Foundation
import Testing

@testable import References

@Suite
struct `CIFP downloads` {
  /// The cycle that began on 2026-10-29, the one in effect on the dates below.
  private let cycle = utc("2026-10-29T00:00:00Z")

  private func makeDirectory() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "cifp-store-\(UUID().uuidString)")
  }

  private func fixtureLoader(requested: LockedURLs) -> CIFPStore.Loader {
    { url in
      requested.append(url)
      let copy = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).zip")
      try FileManager.default.copyItem(at: fixtureURL("CIFP/CIFP_261029.zip"), to: copy)
      return copy
    }
  }

  @Test
  func `downloads the archive named for the cycle and keeps its FAACIFP18`() async throws {
    let directory = makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let requested = LockedURLs()
    let store = CIFPStore(directory: directory, loader: fixtureLoader(requested: requested))

    let downloaded = try await store.download(covering: utc("2026-11-09T12:00:00Z"))

    #expect(downloaded == cycle)
    #expect(
      requested.urls.map(\.absoluteString)
        == ["https://aeronav.faa.gov/Upload_313-d/cifp/CIFP_261029.zip"]
    )
    #expect(try String(contentsOf: store.fileURL, encoding: .utf8).hasPrefix("HDR01"))
    #expect(store.savedCycle == cycle)
  }

  @Test
  func `skips the download when the cycle is already saved`() async throws {
    let directory = makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let requested = LockedURLs()
    let store = CIFPStore(directory: directory, loader: fixtureLoader(requested: requested))

    try await store.download(covering: utc("2026-11-09T12:00:00Z"))
    try await store.download(covering: utc("2026-11-20T12:00:00Z"))

    #expect(requested.urls.count == 1)
  }

  @Test
  func `reports a file placed by hand as having no downloaded cycle`() throws {
    let directory = makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data("x".utf8).write(to: directory.appending(path: "FAACIFP18"))
    let store = CIFPStore(directory: directory)

    #expect(store.hasFile)
    #expect(store.savedCycle == nil)
  }

  @Test
  func `fails when the archive lacks FAACIFP18, leaving nothing saved`() async throws {
    let directory = makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = CIFPStore(directory: directory) { _ in
      let copy = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).zip")
      try FileManager.default.copyItem(at: fixtureURL("CIFP/Other.zip"), to: copy)
      return copy
    }

    await #expect(throws: ReferenceDataError.self) {
      try await store.download(covering: utc("2026-11-09T12:00:00Z"))
    }
    #expect(!store.hasFile)
  }
}

private final class LockedURLs: @unchecked Sendable {
  private let lock = NSLock()
  private var stored = [URL]()

  var urls: [URL] { lock.withLock { stored } }

  func append(_ url: URL) { lock.withLock { stored.append(url) } }
}
