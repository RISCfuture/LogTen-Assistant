public import CoreData
public import Foundation

/// The location of LogTen's compiled Core Data model (`CNLogBookDocument.momd`).
///
/// LogTen's model ships inside the app, so reading a logbook requires LogTen to be installed.
/// The reader never bundles or migrates the model; it uses whichever version is installed.
public struct LogTenModel: Hashable, Sendable {
  /// LogTen's bundle identifier.
  public static let bundleIdentifier = "com.coradine.LogTenProX"

  /// The model inside LogTen installed in `/Applications`.
  public static let defaultURL = URL(
    filePath: "/Applications/LogTen.app/Contents/Resources/CNLogBookDocument.momd",
    directoryHint: .isDirectory
  )

  private static let modelPath = "Contents/Resources/CNLogBookDocument.momd"

  /// The `.momd` directory.
  public let url: URL

  /// Whether a model exists at ``url``.
  public var isInstalled: Bool {
    FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
  }

  /// Creates a reference to the model at a URL.
  public init(url: URL = Self.defaultURL) {
    self.url = url
  }

  /// Creates a reference to the model inside a LogTen application bundle.
  public init(applicationURL: URL) {
    url = applicationURL.appending(path: Self.modelPath, directoryHint: .isDirectory)
  }

  /// Loads a private, editable copy of the model whose entities all use `NSManagedObject`.
  ///
  /// LogTen's entities name its own classes (`CNFlight` and so on), which don't exist here;
  /// records are read through key-value coding instead.
  ///
  /// - Throws: ``LogbookStoreError/modelUnavailable(_:)`` if there's no model at ``url``.
  public func load() throws(LogbookStoreError) -> NSManagedObjectModel {
    guard let shared = NSManagedObjectModel(contentsOf: url),
      let model = shared.copy() as? NSManagedObjectModel
    else { throw .modelUnavailable(url) }
    let genericClass = NSStringFromClass(NSManagedObject.self)
    for entity in model.entities { entity.managedObjectClassName = genericClass }
    return model
  }
}
