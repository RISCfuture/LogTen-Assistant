import FlightSources
import Foundation
import Observation

/// Uploads data logs to FlySto, one at a time, and waits for FlySto to process each.
@Observable
final class UploadLogsModel {
  /// Each file and where its upload stands.
  private(set) var uploads = [Upload]()

  /// Whether uploads are under way.
  private(set) var isUploading = false

  @ObservationIgnored private let client: FlyStoClient
  @ObservationIgnored private var task: Task<Void, Never>?

  /// Creates a model that uploads through a FlySto client.
  init(client: FlyStoClient) {
    self.client = client
  }

  /// Uploads files.
  func upload(_ files: [URL]) {
    uploads = files.map { Upload(file: $0) }
    isUploading = true
    let sender = LogUploader(client: client)
    task = Task {
      for index in uploads.indices {
        uploads[index].state = .uploading
        uploads[index].state = await sender.upload(uploads[index].file)
      }
      isUploading = false
    }
  }

  /// Stops after the file being uploaded.
  func cancel() { task?.cancel() }

  /// One file's upload.
  struct Upload: Identifiable {
    /// The file.
    let file: URL
    /// Where the upload stands.
    var state = State.waiting

    var id: URL { file }
  }

  /// Where an upload stands.
  enum State: Sendable {
    /// Not started.
    case waiting
    /// Being sent or processed.
    case uploading
    /// FlySto made these many logs from it.
    case processed(Int)
    /// FlySto already had the file.
    case alreadyUploaded
    /// FlySto is still processing it.
    case pending
    /// The upload failed.
    case failed(String)
  }
}

/// Zips and uploads one log, off the main actor.
nonisolated private struct LogUploader: Sendable {
  let client: FlyStoClient

  @concurrent
  func upload(_ file: URL) async -> UploadLogsModel.State {
    let accessing = file.startAccessingSecurityScopedResource()
    defer { if accessing { file.stopAccessingSecurityScopedResource() } }
    do {
      try Task.checkCancellation()
      let archive = try ZipArchive.archive(
        name: file.lastPathComponent,
        contents: try Data(contentsOf: file)
      )
      let upload = try await client.upload(archive: archive, reference: file.lastPathComponent)
      if upload.wasAlreadyUploaded { return .alreadyUploaded }
      let logs = try await client.waitForProcessing(of: upload.fileID)
      return logs.map { .processed($0.count) } ?? .pending
    } catch {
      return .failed(error.localizedDescription)
    }
  }
}
