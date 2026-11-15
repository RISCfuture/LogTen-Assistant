public import LogbookModel

/// The aircraft matching rules for counting a past flight toward a reference flight's currency.
///
/// Currency is established in the same category, class and, for aircraft that require a type
/// rating, type. A past simulator flight counts as the category, class and type it represents,
/// if the device is credited for the kind of experience being counted.
package struct FlightMatchCriteria: Sendable {
  /// The flight being checked.
  package let referenceFlight: Flight

  /// Resolves what each flight counts as.
  package let resolver: AircraftResolver

  /// The kind of experience being counted, which decides whether simulators qualify.
  package let credit: SimulatorCredit

  /// Whether to require the same category.
  package let matchCategory: Bool

  /// Whether to require the same class.
  package let matchClass: Bool

  /// Whether to require the same type when the reference aircraft requires a type rating.
  package let matchTypeIfRequired: Bool

  /// Criteria that accept any flight credited for the experience.
  package static func none(
    for flight: Flight,
    resolver: AircraftResolver,
    credit: SimulatorCredit
  ) -> Self {
    Self(
      referenceFlight: flight,
      resolver: resolver,
      credit: credit,
      matchCategory: false,
      matchClass: false,
      matchTypeIfRequired: false
    )
  }

  /// Criteria that require the same category.
  package static func category(
    for flight: Flight,
    resolver: AircraftResolver,
    credit: SimulatorCredit
  ) -> Self {
    Self(
      referenceFlight: flight,
      resolver: resolver,
      credit: credit,
      matchCategory: true,
      matchClass: false,
      matchTypeIfRequired: false
    )
  }

  /// Criteria that require the same category, class and, if rated, type.
  package static func full(
    for flight: Flight,
    resolver: AircraftResolver,
    credit: SimulatorCredit
  ) -> Self {
    Self(
      referenceFlight: flight,
      resolver: resolver,
      credit: credit,
      matchCategory: true,
      matchClass: true,
      matchTypeIfRequired: true
    )
  }

  /// Criteria that require the same type, if the reference aircraft requires a type rating.
  package static func type(
    for flight: Flight,
    resolver: AircraftResolver,
    credit: SimulatorCredit
  ) -> Self {
    Self(
      referenceFlight: flight,
      resolver: resolver,
      credit: credit,
      matchCategory: false,
      matchClass: false,
      matchTypeIfRequired: true
    )
  }

  /// Whether a past flight counts toward the reference flight's currency.
  package func matches(_ candidate: Flight) -> Bool {
    guard resolver.counts(candidate, toward: credit) else { return false }
    if matchCategory && !matchesCategory(candidate) { return false }
    if matchClass && !matchesClass(candidate) { return false }
    if matchTypeIfRequired && !matchesType(candidate) { return false }
    return true
  }

  private func matchesCategory(_ candidate: Flight) -> Bool {
    guard let category = resolver.category(of: referenceFlight) else { return false }
    return category == resolver.category(of: candidate)
  }

  private func matchesClass(_ candidate: Flight) -> Bool {
    guard resolver.category(of: referenceFlight) != nil else { return false }
    return resolver.aircraftClass(of: referenceFlight) == resolver.aircraftClass(of: candidate)
  }

  private func matchesType(_ candidate: Flight) -> Bool {
    guard let aircraft = referenceFlight.aircraft else { return false }
    guard resolver.requiresTypeRating(aircraft) else { return true }
    guard let type = resolver.typeDesignator(of: referenceFlight) else { return false }
    return type == resolver.typeDesignator(of: candidate)
  }
}
