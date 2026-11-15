public import Foundation
import SwiftCIFP

/// The broad kind of an instrument approach, as a pilot records it.
public enum ApproachFamily: String, Codable, Sendable {
  /// An instrument landing system.
  case ils
  /// A localizer, localizer-type directional aid or similar course-only approach.
  case localizer
  /// An area-navigation (GPS) approach.
  case rnav
  /// Any other approach, such as VOR or NDB.
  case other
}

/// A fix on the final approach segment of a published approach.
public struct ApproachFix: Hashable, Codable, Sendable {
  /// The fix's identifier.
  public var name: String
  /// Latitude in degrees.
  public var latitudeDeg: Double
  /// Longitude in degrees.
  public var longitudeDeg: Double
  /// Whether the fix is the final approach fix.
  public var isFinalApproachFix: Bool

  /// Creates a fix.
  public init(name: String, latitudeDeg: Double, longitudeDeg: Double, isFinalApproachFix: Bool) {
    self.name = name
    self.latitudeDeg = latitudeDeg
    self.longitudeDeg = longitudeDeg
    self.isFinalApproachFix = isFinalApproachFix
  }
}

/// An instrument approach procedure, reduced to what naming a flown approach needs.
public struct PublishedApproach: Hashable, Codable, Sendable {
  /// The identifier of the airport the approach serves.
  public var airportIdentifier: String
  /// The procedure's coded identifier, such as `I09L` or `R30-Y`.
  public var identifier: String
  /// The kind of approach.
  public var family: ApproachFamily
  /// The approach's type as charted, such as `ILS`.
  public var typeName: String
  /// The runway served, such as `09L`; `nil` for a circling approach.
  public var runway: String?
  /// The letter that tells apart approaches of one type to one runway, such as `Z`.
  public var multipleIndicator: String?
  /// The fixes from the final approach course fix to the missed approach point, in order.
  public var fixes: [ApproachFix]

  /// The approach's name as charted, such as `ILS Z RWY 09L`.
  public var name: String {
    [typeName, multipleIndicator, runway.map { "RWY \($0)" }].compactMap(\.self).joined(
      separator: " "
    )
  }

  /// Creates an approach.
  public init(
    airportIdentifier: String,
    identifier: String,
    family: ApproachFamily,
    typeName: String,
    runway: String? = nil,
    multipleIndicator: String? = nil,
    fixes: [ApproachFix] = []
  ) {
    self.airportIdentifier = airportIdentifier
    self.identifier = identifier
    self.family = family
    self.typeName = typeName
    self.runway = runway
    self.multipleIndicator = multipleIndicator
    self.fixes = fixes
  }
}

/// A source of published approaches.
public protocol ApproachLookup: Sendable {
  /// The final approach routes published for an airport; none if the airport is unknown.
  func approaches(at airportIdentifier: String) async -> [PublishedApproach]
}

/// Published approaches read from an FAA CIFP file with SwiftCIFP.
public actor CIFPApproachLibrary: ApproachLookup {
  private static let runwayPrefix = "RW"

  private let data: CIFPData
  private var cache = [String: [PublishedApproach]]()

  /**
   Reads a CIFP file.

   - Parameter url: The unzipped FAA CIFP file (`FAACIFP18`).
   - Throws: The SwiftCIFP error if the file can't be read.
   */
  public init(contentsOf url: URL) async throws {
    data = try await CIFP(url: url).linked()
  }

  private static func family(of type: ApproachType) -> ApproachFamily {
    switch type {
      case .ils: .ils
      case .localizerOnly, .localizerBackcourse, .igs, .lda, .sdf: .localizer
      case .rnav, .gps, .rnpAR, .gls: .rnav
      default: .other
    }
  }

  public func approaches(at airportIdentifier: String) async -> [PublishedApproach] {
    let key = airportIdentifier.uppercased()
    if let cached = cache[key] { return cached }
    guard let airport = await data.airport(key) else { return [] }
    var result = [PublishedApproach]()
    for approach in airport.approaches where approach.routeType == .finalApproach {
      result.append(await published(approach, at: key))
    }
    cache[key] = result
    return result
  }

  private func published(_ approach: Approach, at airport: String) async -> PublishedApproach {
    let finalApproachFixID = approach.finalApproachFix?.fixId
    var fixes = [ApproachFix]()
    for leg in approach.legs {
      guard let name = leg.fixId,
        let coordinate = await leg.fix?.coordinate
      else { continue }
      fixes.append(
        ApproachFix(
          name: name,
          latitudeDeg: coordinate.latitudeDeg,
          longitudeDeg: coordinate.longitudeDeg,
          isFinalApproachFix: name == finalApproachFixID
        )
      )
    }
    return PublishedApproach(
      airportIdentifier: airport,
      identifier: approach.identifier,
      family: Self.family(of: approach.approachType),
      typeName: approach.approachType.description,
      runway: approach.runwayId.map { String($0.dropFirst(Self.runwayPrefix.count)) },
      multipleIndicator: approach.multipleIndicator,
      fixes: fixes
    )
  }
}
