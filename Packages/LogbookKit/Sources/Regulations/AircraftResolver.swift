public import LogbookModel

/// Resolves what a flight counts as for currency: its category, class and type, taking
/// simulators into account.
///
/// A flight in a simulator or training device counts as the category, class and type it
/// represents, but only toward experience the device is credited for: full flight simulators are
/// credited for everything, other devices only for the credits listed in the aircraft's
/// ``AircraftSettings/simulatorCredit``.
package struct AircraftResolver: Sendable {
  private let mapping: FieldMapping
  private let aircraftSettings: [String: AircraftSettings]

  /// Creates a resolver.
  package init(settings: LogbookSettings) {
    mapping = settings.fieldMapping
    aircraftSettings = settings.aircraft
  }

  /// Whether the flight was in a simulator or training device.
  package func isSimulator(_ flight: Flight) -> Bool {
    flight.aircraft?.type?.category?.isSimulationDevice == true
  }

  /// The category the flight counts as: the represented category for a simulator.
  package func category(of flight: Flight) -> AircraftCategory? {
    guard isSimulator(flight) else { return flight.aircraft?.type?.category }
    return flight.aircraft?.type?.simulatorCategoryClass(in: mapping)?.category
  }

  /// The class the flight counts as: the represented class for a simulator.
  package func aircraftClass(of flight: Flight) -> AircraftClass? {
    guard isSimulator(flight) else { return flight.aircraft?.type?.aircraftClass }
    return flight.aircraft?.type?.simulatorCategoryClass(in: mapping)?.aircraftClass
  }

  /// The type designator the flight counts as, preferring the type rating configured for the
  /// aircraft.
  package func typeDesignator(of flight: Flight) -> String? {
    guard let aircraft = flight.aircraft else { return nil }
    return settings(for: aircraft).typeRating ?? aircraft.type?.typeCode(in: mapping)
  }

  /// Whether acting as a pilot of the aircraft requires a type rating, so that currency is
  /// type-specific.
  package func requiresTypeRating(_ aircraft: Aircraft) -> Bool {
    aircraft.requiresTypeRating || settings(for: aircraft).requiresProficiencyCheck
  }

  /// Whether the flight can count toward a kind of experience: always for an aircraft, and for a
  /// simulator only if it is a full flight simulator or credited for the experience.
  package func counts(_ flight: Flight, toward credit: SimulatorCredit) -> Bool {
    guard isSimulator(flight), let aircraft = flight.aircraft else { return true }
    if aircraft.type?.simulatorType(in: mapping) == .FFS { return true }
    return settings(for: aircraft).simulatorCredit.contains(credit)
  }

  private func settings(for aircraft: Aircraft) -> AircraftSettings {
    aircraftSettings[aircraft.registration] ?? .init()
  }
}
