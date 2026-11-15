/// The checks the consistency audit runs, in the order it runs them.
enum ConsistencyCheckRegistry {
  /// Every implemented check. A check that reads another's findings or analyses comes after
  /// it: the duration check reads the block-time findings it makes itself, and the overlap
  /// check reads the duration findings' analyses.
  static let checks: [any ConsistencyCheck] = [
    CountSubsetCheck(),
    NegativeValueCheck(),
    TimeSubsetCheck(),
    ApproachCheck(),
    TimestampOrderCheck(),
    DurationCheck(),
    IFRCapabilityCheck(),
    AircraftReferenceCheck(),
    DuplicateFlightCheck(),
    DuplicateReferenceCheck(),
    OverlapCheck(),
    CustomTimeBoundsCheck(),
    MissingInformationCheck(),
    SeatTimeCheck(),
    NightSeatTimeCheck(),
    HobbsTachOrderCheck(),
    FutureDateCheck(),
    CrewSeatCheck(),
    PICNotNamedCheck(),
    InstructionNamesCheck(),
    SoloWithInstructorCheck(),
    SimulatorTimeInAircraftCheck(),
    SimulatorSessionTimeCheck(),
    AircraftTypeClassificationCheck(),
    AircraftTypeIdentifierCheck(),
    IncompleteAircraftCheck(),
    IncompletePlaceCheck(),
    IncompletePersonCheck()
  ]

  /// The rules some check reports.
  static let implementedRules = Set(checks.flatMap(\.rules))
}
