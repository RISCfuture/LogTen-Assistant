import Foundation
import LogbookModel
import Observation
import PilotLookup
import SwiftAirmen

/// Looks up the pilot in the FAA's releasable airmen database, so their certificates can fill
/// in the pilot settings.
@Observable
final class AirmenLookupModel {
  /// The first name to look for.
  var firstName = ""

  /// The last name to look for.
  var lastName = ""

  /// Where the lookup is.
  private(set) var phase: Phase

  /// Whether the names are enough to search for.
  var canSearch: Bool {
    !lastName.trimmingCharacters(in: .whitespaces).isEmpty && !phase.isWorking
  }

  /// Creates a lookup, optionally already at a phase.
  init(phase: Phase = .idle) {
    self.phase = phase
  }

  private static func downloadDirectory() throws -> URL {
    let directory = URL.cachesDirectory.appending(path: "Airmen", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  @concurrent
  private static func airmen(in folder: URL, firstName: String, lastName: String) async throws
    -> [AirmanMatch]
  {
    let (airmen, _) = try await Parser(directory: folder).parse(files: [.pilotBasic, .pilotCert])
    return airmen.values
      .filter {
        matches($0.lastName, lastName) && (firstName.isEmpty || matches($0.firstName, firstName))
      }
      .map(AirmanMatch.init)
      .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }

  nonisolated private static func matches(_ name: String?, _ query: String) -> Bool {
    guard let name else { return false }
    return name.compare(query, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
  }

  /// Downloads the current database from the FAA and searches it.
  func downloadAndSearch() async {
    phase = .downloading
    do {
      let folder = try await Downloader(workingDirectory: Self.downloadDirectory()).download()
      await search(in: folder)
    } catch {
      phase = .failed(error.localizedDescription)
    }
  }

  /**
   Searches a downloaded database.

   - Parameter folder: A folder holding the database's CSV files, such as one the user chose in
     an Open panel.
   */
  func search(in folder: URL) async {
    phase = .searching
    let accessing = folder.startAccessingSecurityScopedResource()
    defer { if accessing { folder.stopAccessingSecurityScopedResource() } }
    do {
      let matches = try await Self.airmen(
        in: folder,
        firstName: firstName.trimmingCharacters(in: .whitespaces),
        lastName: lastName.trimmingCharacters(in: .whitespaces)
      )
      phase = .results(matches)
    } catch {
      phase = .failed(error.localizedDescription)
    }
  }

  /// Where a lookup is.
  enum Phase {
    case idle
    case downloading
    case searching
    case results([AirmanMatch])
    case failed(String)

    var isWorking: Bool {
      switch self {
        case .downloading, .searching: true
        default: false
      }
    }
  }
}

/// An airman whose name matched, with the certificates the pilot settings can use.
nonisolated struct AirmanMatch: Identifiable, Sendable {
  let id: String
  let name: String
  let location: String?
  let certificates: AirmanCertificates

  /// A one-line description of the certificates.
  var summary: String {
    let level = certificates.certificateLevel?.title ?? String(localized: "No pilot certificate")
    let ratings =
      certificates.categoryClassRatings.map(\.title).sorted()
      + certificates.instrumentRatings.map(\.title).sorted()
      + certificates.typeRatings.sorted()
    let instructor =
      certificates.instructorRatings.isEmpty ? [] : [String(localized: "Flight Instructor")]
    return ([level] + ratings + instructor).joined(separator: " · ")
  }

  init(_ airman: Airman) {
    id = airman.id
    name = airman.name ?? airman.id
    location = airman.address?.cityState
    certificates = AirmanCertificates(airman.certificates)
  }

  init(id: String, name: String, location: String?, certificates: AirmanCertificates) {
    self.id = id
    self.name = name
    self.location = location
    self.certificates = certificates
  }
}
