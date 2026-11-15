public import Foundation
import SwiftNASR

/// Why a NASR cycle couldn't be turned into an ``AirportIndex``.
public enum ReferenceDataError: LocalizedError, Sendable {
  /// The distribution holds no airports.
  case noAirports

  /// The distribution doesn't say which cycle it is.
  case unknownCycle

  /// No NASR cycle covers the date.
  case noCycle(Date)

  /// The FAA's server didn't return the CIFP archive.
  case cifpDownloadFailed(statusCode: Int)

  /// The CIFP archive doesn't hold the FAACIFP18 file.
  case cifpFileMissing

  public var errorDescription: String? {
    String(localized: "Couldn’t load the airport reference data.", bundle: .module)
  }

  public var failureReason: String? {
    switch self {
      case .noAirports:
        String(localized: "The NASR distribution contains no airports.", bundle: .module)
      case .unknownCycle:
        String(localized: "The NASR distribution doesn’t identify its cycle.", bundle: .module)
      case .cifpDownloadFailed(let statusCode):
        String(
          localized: "The FAA’s server answered with status \(statusCode, format: .number).",
          bundle: .module
        )
      case .cifpFileMissing:
        String(localized: "The CIFP download doesn’t contain FAACIFP18.", bundle: .module)
      case .noCycle(let date):
        String(
          localized:
            "No NASR cycle was in effect on \(date, format: .dateTime.year().month().day()).",
          bundle: .module
        )
    }
  }
}

/// Builds an ``AirportIndex`` from a FAA NASR distribution in CSV format, using SwiftNASR.
public enum NASRAirportLoader {
  private static let arcsecondsPerDegree = 3_600.0

  /**
   Parses the airports and runway ends of a distribution.

   - Parameters:
     - location: A NASR CSV ZIP archive, or a directory holding the extracted files.
     - progress: Reports loading and parsing progress.
   - Returns: The cycle's airports and runway ends.
   - Throws: ``ReferenceDataError`` if the distribution is empty or unidentified, or a SwiftNASR
     error if it can't be read.
   */
  public static func load(from location: URL, progress: consuming Subprogress? = nil)
    async throws
    -> AirportIndex
  {
    let isDirectory =
      (try? location.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    let nasr =
      isDirectory
      ? NASR.fromLocalDirectory(location, format: .csv)
      : NASR.fromLocalArchive(location, format: .csv)
    return try await index(from: nasr, progress: progress)
  }

  /**
   Parses an index from a distribution that is ready to load.

   - Parameters:
     - nasr: The distribution.
     - downloadedCycle: The cycle the distribution was downloaded for, used when the
       distribution doesn't name its own cycle, as a CSV archive doesn't.
     - progress: Reports loading and parsing progress.
   */
  static func index(
    from nasr: NASR,
    downloadedCycle: Cycle? = nil,
    progress: consuming Subprogress? = nil
  ) async throws -> AirportIndex {
    try await nasr.load()
    try await nasr.parse(.airports, progress: progress) { _ in .proceed }
    guard let airports = await nasr.data.airports, !airports.isEmpty else {
      throw ReferenceDataError.noAirports
    }
    guard let effective = await nasr.data.cycle?.effectiveDate ?? downloadedCycle?.effectiveDate
    else {
      throw ReferenceDataError.unknownCycle
    }
    return AirportIndex(
      effectiveDate: effective,
      airports: airports.compactMap { reference(of: $0, effective: effective) },
      runwayEnds: airports.flatMap(runwayEnds(of:))
    )
  }

  private static func reference(of airport: SwiftNASR.Airport, effective: Date) -> AirportReference?
  {
    let point = airport.referencePoint
    return AirportReference(
      locationID: airport.LID,
      ICAOID: airport.ICAOIdentifier,
      name: airport.name,
      latitudeDeg: Double(point.latitudeArcsec) / arcsecondsPerDegree,
      longitudeDeg: Double(point.longitudeArcsec) / arcsecondsPerDegree,
      elevationFt: point.elevationFtMSL.map(Double.init),
      cycleEffectiveDate: effective
    )
  }

  private static func runwayEnds(of airport: SwiftNASR.Airport) -> [RunwayEndReference] {
    airport.runways.flatMap { runway in
      [runway.baseEnd, runway.reciprocalEnd].compactMap { end -> RunwayEndReference? in
        guard let threshold = end?.threshold, let end else { return nil }
        return RunwayEndReference(
          airportLocationID: airport.LID,
          runwayID: runway.identification,
          identifier: end.id,
          latitudeDeg: Double(threshold.latitudeArcsec) / arcsecondsPerDegree,
          longitudeDeg: Double(threshold.longitudeArcsec) / arcsecondsPerDegree
        )
      }
    }
  }
}
