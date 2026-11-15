public import Foundation

/// Where a piece of external evidence came from, kept with the evidence so findings can cite it.
public struct SourceProvenance: Hashable, Codable, Sendable {
  /// The provider.
  public var source: EvidenceSource

  /// The URLs the data was downloaded from.
  public var urls: [URL]

  /// The SHA-256 digest of the downloaded data, as lowercase hexadecimal.
  public var sha256: String?

  /// The license the data is distributed under, such as “ODbL-1.0”.
  public var license: String?

  /// When the data was retrieved.
  public var retrievedAt: Date

  /// Creates a provenance record.
  public init(
    source: EvidenceSource,
    urls: [URL] = [],
    sha256: String? = nil,
    license: String? = nil,
    retrievedAt: Date
  ) {
    self.source = source
    self.urls = urls
    self.sha256 = sha256
    self.license = license
    self.retrievedAt = retrievedAt
  }
}

/// A provider of evidence about flights, in order of precedence when sources disagree.
public enum EvidenceSource: String, CaseIterable, Comparable, Codable, Sendable {
  /// FlySto, which parses the aircraft's own data logs.
  case flySto = "fly_sto"
  /// The adsb.lol ADS-B archive.
  case adsbLol = "adsb_lol"
  /// The OpenSky Network.
  case openSky = "open_sky"

  public static func < (lhs: Self, rhs: Self) -> Bool {
    allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
  }
}
