import Foundation
import LogbookStore
import Testing

@testable import LogTen_Assistant

struct LogbookReferenceTests {
  private static let folder = URL(filePath: "/Volumes/Pilots/Logbooks", directoryHint: .isDirectory)

  private func nested(_ name: String = "LogTenProData_ABC") -> LogbookReference {
    let directory = Self.folder.appending(path: name, directoryHint: .isDirectory)
    return LogbookReference(
      logbook: LogbookLocation(directory: directory),
      in: Self.folder,
      bookmark: Data([1])
    )
  }

  @Test
  func aLogbookInsideTheChosenFolderIsIdentifiedByItsOwnFolder() {
    let reference = nested()
    #expect(reference.path == "/Volumes/Pilots/Logbooks/LogTenProData_ABC")
    #expect(reference.location(in: Self.folder).directory.lastPathComponent == "LogTenProData_ABC")
  }

  @Test
  func aChosenLogbookFolderIsItsOwnLocation() {
    let reference = LogbookReference(
      logbook: LogbookLocation(directory: Self.folder),
      in: Self.folder,
      bookmark: Data([1])
    )
    #expect(reference.path.map { URL(filePath: $0) } == Self.folder)
    #expect(reference.location(in: Self.folder).directory == Self.folder)
  }

  @Test
  func referencesToTheSameFolderAreEqualWhateverElseTheyRecord() {
    var other = nested()
    other.displayName = "Someone Else"
    other.source = other.replacingBookmark(Data([2])).source
    #expect(nested() == other)
    #expect(nested() != nested("LogTenProData_XYZ"))
  }

  @Test
  func replacingTheBookmarkKeepsTheLogbook() throws {
    let replaced = nested().replacingBookmark(Data([9]))
    guard case let .bookmark(data, folderPath, name) = replaced.source else {
      Issue.record("Expected a bookmark source")
      return
    }
    #expect(data == Data([9]))
    #expect(folderPath == Self.folder.path(percentEncoded: false))
    #expect(name == "LogTenProData_ABC")
    #expect(replaced.id == nested().id)
  }

  @Test
  func aGenericallyNamedLogbookTakesItsFolderName() {
    #expect(nested().title == "LogTenProData_ABC")
  }

  @Test
  func aGenericallyNamedLogbookInLogTensOwnContainerKeepsTheGenericName() {
    let container = LogbookLocation.defaultGroupContainerURL
    let reference = LogbookReference(
      logbook: LogbookLocation(directory: container.appending(path: "LogTenProData_ABC")),
      in: container,
      bookmark: Data([1])
    )
    #expect(reference.isDefaultLogbook)
    #expect(reference.title == LogbookReference.genericName)
  }

  @Test(
    "A named logbook is shown by its name, except a folder-style name",
    arguments: [("Tim Morgan", "Tim Morgan"), ("LogTenProData_123", "LogTenProData_ABC")]
  )
  func titleUsesTheDisplayName(displayName: String, expected: String) {
    var reference = nested()
    reference.displayName = displayName
    #expect(reference.title == expected)
  }

  @Test
  func aSampleLogbookHasNoBookmark() {
    let sample = LogbookReference(fixture: "sample", displayName: "Sample Logbook")
    #expect(sample.id == "fixture:sample")
    #expect(sample.title == "Sample Logbook")
    #expect(!sample.isBookmarked)
    #expect(sample.path == nil)
    #expect(throws: LogbookOpeningError.self) { try sample.resolvedFolder() }
  }
}
