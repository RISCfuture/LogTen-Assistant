import Foundation
import Testing
import Workspace

@testable import LogTen_Assistant

struct WriterPolicyTests {
  private func sendsToLogTen(_ scenario: Scenario) throws -> Bool {
    let suite = "WriterPolicyTests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(scenario.mode?.rawValue, forKey: AppSettingsKey.writerMode)
    defaults.set(scenario.disposableLogbookOpen, forKey: WriterPolicy.disposableLogbookKey)

    let directory = FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: directory) }
    let workspace = try Workspace(directory: directory)

    return WriterPolicy.writer(
      for: workspace,
      isFixture: scenario.isFixture,
      defaults: defaults
    ).sendsToLogTen
  }

  @Test
  func sendsToLogTenOnlyWhenEveryGuardIsMet() throws {
    #expect(
      try sendsToLogTen(
        Scenario(isFixture: false, mode: .sendToLogTen, disposableLogbookOpen: true)
      )
    )
  }

  @Test(
    "Records instead whenever a guard is missing",
    arguments: [
      Scenario(isFixture: true, mode: .sendToLogTen, disposableLogbookOpen: true),
      Scenario(isFixture: false, mode: .recordPackages, disposableLogbookOpen: true),
      Scenario(isFixture: false, mode: nil, disposableLogbookOpen: true),
      Scenario(isFixture: false, mode: .sendToLogTen, disposableLogbookOpen: false)
    ]
  )
  func recordsWhenAGuardIsMissing(_ scenario: Scenario) throws {
    #expect(try !sendsToLogTen(scenario))
  }

  struct Scenario: Sendable {
    let isFixture: Bool
    let mode: WriterMode?
    let disposableLogbookOpen: Bool
  }
}
