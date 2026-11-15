import Foundation
import LogbookStore
import LogbookTestSupport
import Testing

@Suite
struct `Logbook discovery` {
  private let container: TemporaryDirectory

  init() throws {
    container = try TemporaryDirectory()
  }

  private func makeDataFolder(_ name: String, withStore: Bool = true) throws -> URL {
    let folder = container.path(name)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    if withStore {
      try Data().write(to: folder.appending(path: LogbookLocation.storeFileName))
    }
    return folder
  }

  @Test
  func `finds the data folders in a group container`() throws {
    let second = try makeDataFolder("LogTenProData_bbb")
    let first = try makeDataFolder("LogTenProData_aaa")
    _ = try makeDataFolder("LogTenProData_empty", withStore: false)
    _ = try makeDataFolder("Library")

    let logbooks = try LogbookLocation.logbooks(in: container.url)

    #expect(logbooks.map(\.directory.lastPathComponent) == [first, second].map(\.lastPathComponent))
    #expect(logbooks.first?.installationIdentifier == "aaa")
  }

  @Test
  func `accepts a data folder chosen directly`() throws {
    let folder = try makeDataFolder("LogTenProData_aaa")
    #expect(try LogbookLocation.logbooks(in: folder).map(\.directory) == [folder])
  }

  @Test
  func `reports a folder with no logbook`() throws {
    #expect(throws: LogbookStoreError.noLogbookFound(container.url)) {
      try LogbookLocation.logbooks(in: container.url)
    }
  }
}
