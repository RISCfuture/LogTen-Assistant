public import Foundation
import LogbookStore
public import Testing

extension Trait where Self == ConditionTrait {
  /// Skips a test when LogTen, whose data model synthetic stores are built with, isn't installed.
  public static var requiresLogTen: Self {
    .enabled(if: LogTenModel().isInstalled, "LogTen isn’t installed in /Applications")
  }
}

/// A uniquely named folder in the temporary directory, removed when the value is released.
public final class TemporaryDirectory: Sendable {
  /// The folder.
  public let url: URL

  /// Creates the folder.
  public init() throws {
    url = FileManager.default.temporaryDirectory.appending(
      path: "LogbookKitTests-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  }

  /// A path inside the folder that doesn't exist yet.
  public func path(_ name: String) -> URL { url.appending(path: name) }

  deinit {
    try? FileManager.default.removeItem(at: url)
  }
}
