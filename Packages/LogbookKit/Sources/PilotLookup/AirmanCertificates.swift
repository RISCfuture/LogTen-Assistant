public import LogbookModel
public import SwiftAirmen

/// The pilot and flight-instructor certificates an FAA airmen record lists, in the terms a
/// `PilotProfile` uses.
///
/// The FAA database lists certificates, not currency or personal preferences, so applying a
/// lookup changes only certificate fields and leaves the rest of the profile alone.
public struct AirmanCertificates: Hashable, Sendable {
  /// The highest pilot certificate level, or `nil` if the record lists no pilot certificate.
  public var certificateLevel: CertificateLevel?

  /// Category and class ratings.
  public var categoryClassRatings: Set<CategoryClassRating>

  /// Instrument ratings.
  public var instrumentRatings: Set<InstrumentRating>

  /// Flight-instructor ratings.
  public var instructorRatings: Set<InstructorRating>

  /// Type ratings, as ICAO type designators.
  public var typeRatings: Set<String>

  /// Collects the pilot and flight-instructor certificates from an airman's certificates.
  public init(_ certificates: [Certificate]) {
    certificateLevel = nil
    categoryClassRatings = []
    instrumentRatings = []
    instructorRatings = []
    typeRatings = []
    for certificate in certificates { add(certificate) }
  }

  /// Returns a profile with these certificates in place of its own.
  public func applied(to profile: PilotProfile) -> PilotProfile {
    var profile = profile
    if let certificateLevel { profile.certificateLevel = certificateLevel }
    profile.categoryClassRatings = categoryClassRatings
    profile.instrumentRatings = instrumentRatings
    profile.instructorRatings = instructorRatings
    profile.typeRatings = typeRatings
    return profile
  }

  private mutating func add(_ certificate: Certificate) {
    switch certificate {
      case let .pilot(level, ratings, _):
        let level = CertificateLevel(level)
        certificateLevel = max(certificateLevel ?? level, level)
        for rating in ratings { add(rating) }
      case let .flightInstructor(ratings, _):
        instructorRatings.formUnion(ratings.map(InstructorRating.init))
      default:
        break
    }
  }

  private mutating func add(_ rating: PilotRating) {
    switch rating {
      case let .categoryClass(categoryClass, _):
        categoryClassRatings.insert(CategoryClassRating(categoryClass))
      case .instrument(let category):
        instrumentRatings.insert(InstrumentRating(category))
      case let .type(type, _):
        typeRatings.insert(type)
    }
  }
}

extension CertificateLevel {
  fileprivate init(_ level: PilotLevel) {
    switch level {
      case .student: self = .student
      case .sport: self = .sport
      case .recreational: self = .recreational
      case .private: self = .private
      case .commercial: self = .commercial
      case .airlineTransport: self = .airlineTransport
    }
  }
}

extension CategoryClassRating {
  fileprivate init(_ categoryClass: PilotCategoryClass) {
    switch categoryClass {
      case .airplaneSingleEngineLand: self = .airplaneSingleEngineLand
      case .airplaneSingleEngineSea: self = .airplaneSingleEngineSea
      case .airplaneMultiEngineLand: self = .airplaneMultiEngineLand
      case .airplaneMultiEngineSea: self = .airplaneMultiEngineSea
      case .glider: self = .glider
      case .rotorcraftHelicopter: self = .rotorcraftHelicopter
      case .rotorcraftGyroplane: self = .rotorcraftGyroplane
      case .lighterThanAirBalloon: self = .lighterThanAirBalloon
      case .lighterThanAirAirship: self = .lighterThanAirAirship
      case .poweredLift: self = .poweredLift
    }
  }
}

extension InstrumentRating {
  fileprivate init(_ category: InstrumentCategory) {
    switch category {
      case .airplane: self = .airplane
      case .helicopter: self = .helicopter
      case .poweredLift: self = .poweredLift
    }
  }
}

extension InstructorRating {
  fileprivate init(_ rating: FlightInstructorRating) {
    switch rating {
      case .category(.airplaneSingleEngine): self = .airplaneSingleEngine
      case .category(.airplaneMultiEngine): self = .airplaneMultiEngine
      case .category(.glider): self = .glider
      case .category(.rotorcraftHelicopter): self = .rotorcraftHelicopter
      case .category(.rotorcraftGyroplane): self = .rotorcraftGyroplane
      case .category(.poweredLift): self = .poweredLift
      case .instrument(.airplane): self = .instrumentAirplane
      case .instrument(.helicopter): self = .instrumentHelicopter
      case .instrument(.poweredLift): self = .instrumentPoweredLift
      case .sport: self = .sport
    }
  }
}
