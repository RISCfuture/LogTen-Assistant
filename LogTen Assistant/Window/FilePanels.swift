import AppKit
import UniformTypeIdentifiers

/// The Open and Save panels the logbook window's commands use.
enum FilePanels {
  private static let webArchive = UTType("com.apple.webarchive") ?? .data
  private static let lastDirectoryKey = "lastFilePanelDirectory"

  /// The folder the panels start in: the one the user last chose a file in, or Documents. Never
  /// the logbook’s own folder, which the app has access to but the user didn’t ask to browse.
  private static var startingDirectory: URL {
    UserDefaults.standard.url(forKey: lastDirectoryKey)
      ?? .documentsDirectory
  }

  private static func remember(_ url: URL?) {
    guard let url else { return }
    let folder = url.hasDirectoryPath ? url : url.deletingLastPathComponent()
    UserDefaults.standard.set(folder, forKey: lastDirectoryKey)
  }

  /// Asks for FlySto CSV exports and the Safari web archives of their flight lists.
  static func chooseFlyStoExports() -> [URL] {
    let panel = NSOpenPanel()
    panel.title = String(localized: "Import FlySto Export")
    panel.message = String(
      localized:
        "Choose the CSV exported from a FlySto flight list, and optionally a Safari web archive of the same list."
    )
    panel.allowedContentTypes = [.commaSeparatedText, webArchive]
    panel.allowsMultipleSelection = true
    panel.prompt = String(localized: "Import")
    return run(panel) ? panel.urls : []
  }

  /// Asks for data logs from the aircraft's avionics, to upload to FlySto.
  static func chooseDataLogs() -> [URL] {
    let panel = NSOpenPanel()
    panel.title = String(localized: "Upload Data Logs to FlySto")
    panel.message = String(localized: "Choose the data logs to upload. FlySto parses each one.")
    panel.allowsMultipleSelection = true
    panel.canChooseDirectories = false
    panel.prompt = String(localized: "Choose")
    return run(panel) ? panel.urls : []
  }

  /**
   Asks where to save a file.

   - Parameters:
     - name: The suggested file name.
     - type: The file's type.
     - title: The panel's title.
   - Returns: Where to save, or `nil` if the user cancelled.
   */
  static func saveLocation(named name: String, type: UTType, title: String) -> URL? {
    let panel = NSSavePanel()
    panel.title = title
    panel.nameFieldStringValue = name
    panel.allowedContentTypes = [type]
    panel.canCreateDirectories = true
    return run(panel) ? panel.url : nil
  }

  private static func run(_ panel: NSSavePanel) -> Bool {
    panel.directoryURL = startingDirectory
    guard panel.runModal() == .OK else { return false }
    remember(panel.url)
    return true
  }
}
