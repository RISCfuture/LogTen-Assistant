import Foundation
import LogbookModel
import LogbookTestSupport
import Testing
import Workspace

@Suite
struct `Workspace documents` {
  private let root: TemporaryDirectory
  private let storeUUID = UUID()

  init() throws {
    root = try TemporaryDirectory()
  }

  private func openWorkspace() throws -> Workspace {
    try Workspace(storeUUID: storeUUID, root: root.url)
  }

  @Test
  func `keeps a folder per logbook`() throws {
    let workspace = try openWorkspace()
    #expect(workspace.directory.lastPathComponent == storeUUID.uuidString)
    #expect(
      FileManager.default.fileExists(
        atPath: workspace.directory.appending(path: Workspace.databaseFileName).path(
          percentEncoded: false
        )
      )
    )
  }

  @Test
  func `stores, replaces and deletes documents by collection and identifier`() async throws {
    let workspace = try openWorkspace()
    try await workspace.save([Note(id: "b", text: "second"), Note(id: "a", text: "first")])
    try await workspace.save(Tag(id: "a"))
    try await workspace.save(Note(id: "b", text: "revised"))

    #expect(
      try await workspace.documents(Note.self) == [
        Note(id: "a", text: "first"), Note(id: "b", text: "revised")
      ]
    )
    #expect(try await workspace.document(Tag.self, id: "a") == Tag(id: "a"))

    try await workspace.deleteDocument(Note.self, id: "a")
    #expect(try await workspace.document(Note.self, id: "a") == nil)
    #expect(try await workspace.documents(Tag.self).count == 1)

    try await workspace.deleteDocuments(Note.self)
    #expect(try await workspace.documents(Note.self).isEmpty)
  }

  @Test
  func `keeps documents and settings across reopening`() async throws {
    var settings = LogbookSettings()
    settings.pilot.typeRatings = ["SF50"]
    settings.rules.disabledRules = ["duplicate_flight"]

    let first = try openWorkspace()
    #expect(try await first.settings() == LogbookSettings())
    try await first.save(settings)
    try await first.save(Note(id: "a", text: "kept"))

    let reopened = try openWorkspace()
    #expect(try await reopened.settings() == settings)
    #expect(try await reopened.document(Note.self, id: "a")?.text == "kept")
    #expect(try await reopened.modificationDate(of: Note.self, id: "a") != nil)
  }

  private struct Note: WorkspaceDocument, Equatable {
    static let collection = "notes"

    var id: String
    var text: String

    var documentID: String { id }
  }

  private struct Tag: WorkspaceDocument, Equatable {
    static let collection = "tags"

    var id: String

    var documentID: String { id }
  }
}
