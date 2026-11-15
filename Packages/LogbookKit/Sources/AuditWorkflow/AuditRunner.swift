public import Audit
public import FlightSources
public import Foundation
public import LogbookModel
public import References
public import Tracks

/// Everything one Audit & Fix run works from.
public struct AuditInputs: Sendable {
  /// The snapshot to audit.
  public var logbook: Logbook

  /// The logbook's settings.
  public var settings: LogbookSettings

  /// The FlySto records synced or imported for the logbook.
  public var flyStoRecords: [FlyStoRecord]

  /// ADS-B or other tracks of the logbook's aircraft.
  public var tracks: [Track]

  /// The global track-detection thresholds.
  public var trackDetection: TrackDetectionSettings

  /// FAA airport data, if a cycle has been downloaded.
  public var airportIndex: AirportIndex?

  /// Published approach procedures, if loaded.
  public var approachLookup: (any ApproachLookup)?

  /// Evaluates smart-group membership against the snapshot; `nil` skips evaluation.
  public var groupResolver: (any GroupMembershipResolving)?

  /// Options for the consistency rules.
  public var consistencyOptions: ConsistencyAuditOptions

  /// Options for the night audit.
  public var nightOptions: NightAuditOptions

  /// Options for the geography audit.
  public var geographyOptions: GeographyAuditOptions

  /// The user's assignments of track segments to entries.
  public var correlationOverrides: [CorrelationOverride]

  /// The date the audit is run as of.
  public var asOf: Date

  /// Creates the inputs for a run.
  public init(
    logbook: Logbook,
    settings: LogbookSettings,
    flyStoRecords: [FlyStoRecord] = [],
    tracks: [Track] = [],
    trackDetection: TrackDetectionSettings = .init(),
    airportIndex: AirportIndex? = nil,
    approachLookup: (any ApproachLookup)? = nil,
    groupResolver: (any GroupMembershipResolving)? = nil,
    consistencyOptions: ConsistencyAuditOptions = .init(),
    nightOptions: NightAuditOptions = .init(),
    geographyOptions: GeographyAuditOptions = .init(),
    correlationOverrides: [CorrelationOverride] = [],
    asOf: Date = .now
  ) {
    self.logbook = logbook
    self.settings = settings
    self.flyStoRecords = flyStoRecords
    self.tracks = tracks
    self.trackDetection = trackDetection
    self.airportIndex = airportIndex
    self.approachLookup = approachLookup
    self.groupResolver = groupResolver
    self.consistencyOptions = consistencyOptions
    self.nightOptions = nightOptions
    self.geographyOptions = geographyOptions
    self.correlationOverrides = correlationOverrides
    self.asOf = asOf
  }
}

/**
 Runs every Audit & Fix check over a snapshot: the logbook's own consistency, its smart groups,
 FlySto and ADS-B comparisons, and the night, geography and navigation audits.

 FlySto records are matched to entries by aircraft, route and time, then by two UTC times for
 records that didn't match. Tracks are segmented and correlated. The evidence is merged per
 entry with FlySto preferred, and each evidence audit runs on the merged contexts. Audits that
 lack their data are skipped and noted. Findings of disabled rules are dropped, and when the
 pilot ignores instruction activity, student-activity findings on instructional entries are
 withheld. Findings on signed or locked flights offer no corrections.
 */
public struct AuditRunner: Sendable {
  /// The steps `run` reports: consistency, smart groups, six evidence steps and places.
  private static let stepCount = 9

  /// Creates a runner.
  public init() {}

  private static func unique(_ findings: [Finding]) -> [Finding] {
    var seen = Set<FindingID>()
    return findings.filter { seen.insert($0.id).inserted }
  }

  /// Runs the audit.
  ///
  /// - Parameter progress: Called with the fraction of the audit's steps finished, from `0` to
  ///   `1`, at most once per percent.
  /// - Throws: `EvidenceError` if instruction activity is ignored but the owner isn't
  ///   identified, or a correlation override names an unknown entry.
  public func run(_ inputs: AuditInputs, progress: ProgressTally.Report? = nil) async throws
    -> AuditRun
  {
    var tally = ProgressTally(total: Self.stepCount, report: progress)
    var run = AuditRun(generatedAt: inputs.asOf, findings: [])
    var findings = runConsistency(inputs, into: &run)
    tally.advance()
    findings += await runSmartGroups(inputs, into: &run)
    tally.advance()
    findings += try await runEvidence(inputs, into: &run, tally: &tally)
    findings += await runPlaceReferences(inputs, into: &run)
    tally.advance()

    let enabled = findings.filter { inputs.settings.rules.runs($0.rule) }
    let (retained, excluded) = try suppressInstruction(enabled, inputs: inputs)
    let flights = Dictionary(inputs.logbook.flights.map { ($0.id, $0) }) { first, _ in first }
    return AuditRun(
      generatedAt: .now,
      findings: Self.unique(retained).map { $0.markingCorrectionRestriction(on: flights) },
      excluded: excluded,
      analyses: run.analyses,
      followUps: run.followUps,
      contexts: run.contexts,
      sourceChoices: run.sourceChoices,
      flyStoRecords: inputs.flyStoRecords,
      flyStoMatches: run.flyStoMatches,
      segments: run.segments,
      segmentMatches: run.segmentMatches,
      groupEvaluations: run.groupEvaluations,
      notes: run.notes
    )
  }

  private func runConsistency(_ inputs: AuditInputs, into run: inout AuditRun) -> [Finding] {
    let result = ConsistencyAudit(settings: inputs.settings, options: inputs.consistencyOptions)
      .run(on: inputs.logbook, asOf: inputs.asOf)
    run.analyses = result.analyses
    return result.findings
  }

  private func runSmartGroups(_ inputs: AuditInputs, into run: inout AuditRun) async -> [Finding] {
    guard let resolver = inputs.groupResolver else {
      if !inputs.logbook.groups.isEmpty {
        run.notes.append(
          AuditNote(
            subject: .smartGroups,
            message: String(
              localized: "Smart groups weren’t evaluated, because the snapshot isn’t available.",
              bundle: .module
            )
          )
        )
      }
      return []
    }
    let result = await SmartGroupAudit(
      mapping: inputs.settings.fieldMapping,
      disabledRules: inputs.settings.rules.disabledRules
    )
    .run(on: inputs.logbook.groups, resolver: resolver)
    run.groupEvaluations = result.evaluations
    return result.findings
  }

  private func runPlaceReferences(_ inputs: AuditInputs, into run: inout AuditRun) async
    -> [Finding]
  {
    guard let index = inputs.airportIndex else {
      run.notes.append(
        AuditNote(
          subject: .airportData,
          message: String(
            localized:
              "Airports, distances and night landings weren’t checked against FAA data, because no NASR cycle has been downloaded.",
            bundle: .module
          )
        )
      )
      return []
    }
    return await PlaceReferenceAudit(
      index: index,
      nonAirportPlaces: inputs.settings.rules.nonAirportPlaces
    )
    .run(on: inputs.logbook.places, asOf: inputs.asOf)
  }

  private func suppressInstruction(_ findings: [Finding], inputs: AuditInputs) throws -> (
    [Finding], [ExcludedFinding]
  ) {
    let pilot = inputs.settings.pilot
    guard pilot.ignoresInstructionActivity else { return (findings, []) }
    let instructional = try InstructionPolicy.instructionalFlightIDs(
      in: inputs.logbook.flights,
      owner: pilot.ownerPersonID
    )
    let (retained, excluded) = InstructionPolicy.suppress(findings, instructional: instructional)
    return (retained, excluded)
  }
}

// MARK: - Evidence

extension AuditRunner {
  private func runEvidence(
    _ inputs: AuditInputs,
    into run: inout AuditRun,
    tally: inout ProgressTally
  ) async throws -> [Finding] {
    let flights = inputs.logbook.flights
    let aircraft = inputs.settings.aircraft
    noteMissingEvidence(inputs, into: &run)

    run.flyStoMatches = matchFlySto(inputs.flyStoRecords, to: flights, aircraft: aircraft)
    tally.advance()
    let segmentation = TrackSegmenter(settings: inputs.trackDetection, aircraft: aircraft)
      .segment(inputs.tracks)
    let allSegments = segmentation.flights + segmentation.nonflight + segmentation.incomplete
    run.segments = Dictionary(allSegments.map { ($0.id, $0) }) { first, _ in first }
    tally.advance()
    let correlation = try SegmentCorrelator(aircraft: aircraft)
      .correlate(segmentation.flights, with: flights, overrides: inputs.correlationOverrides)
    run.segmentMatches = correlation.matches
    tally.advance()

    let builder = try EvidenceContextBuilder(
      aircraft: aircraft,
      pilot: inputs.settings.pilot,
      flights: flights
    )
    var contexts = builder.contexts(
      for: flights,
      records: inputs.flyStoRecords,
      flyStoMatches: run.flyStoMatches,
      segments: segmentation.flights,
      segmentMatches: correlation.matches
    )
    builder.addADSBPositions(to: &contexts, flights: flights, tracks: inputs.tracks)
    run.contexts = contexts
    tally.advance()

    let comparison = SourceComparison(tolerances: inputs.settings.rules.tolerances).compare(
      flights: flights,
      records: inputs.flyStoRecords,
      matches: run.flyStoMatches,
      segments: segmentation.flights,
      segmentMatches: correlation.matches
    )
    run.sourceChoices = Dictionary(grouping: comparison.choices, by: \.flightID)
    tally.advance()

    var findings = correlation.findings + comparison.findings
    findings += await runContextAudits(inputs, contexts: contexts, into: &run)
    tally.advance()
    return findings
  }

  private func matchFlySto(
    _ records: [FlyStoRecord],
    to flights: [Flight],
    aircraft: [String: AircraftSettings]
  ) -> [EvidenceMatch] {
    let matcher = EvidenceMatcher(aircraft: aircraft)
    let byRoute = matcher.matchExports(records, to: flights)
    let claimed = Set(byRoute.compactMap { $0.status == .matched ? $0.flightID : nil })
    let unmatched = Set(byRoute.filter { $0.status != .matched }.map(\.sourceID))
    let byTime = matcher.matchByTime(records.filter { unmatched.contains($0.id) }, to: flights)
      .filter { $0.status == .matched && $0.flightID.map(claimed.contains) == false }
    let timeMatches = Dictionary(byTime.map { ($0.sourceID, $0) }) { first, _ in first }
    return byRoute.map { timeMatches[$0.sourceID] ?? $0 }
  }

  private func runContextAudits(
    _ inputs: AuditInputs,
    contexts: [RecordID: EvidenceContext],
    into run: inout AuditRun
  ) async -> [Finding] {
    guard !contexts.isEmpty else { return [] }
    let flights = inputs.logbook.flights
    let settings = inputs.settings

    let night = NightAudit(
      mapping: settings.fieldMapping,
      tolerances: settings.rules.tolerances,
      options: inputs.nightOptions,
      index: inputs.airportIndex
    )
    .run(on: flights, contexts: contexts)
    var findings = night.findings
    run.followUps.merge(night.followUps) { first, _ in first }

    if let index = inputs.airportIndex {
      let geography = await GeographyAudit(
        index: index,
        mapping: settings.fieldMapping,
        tolerances: settings.rules.tolerances,
        options: inputs.geographyOptions
      )
      .run(on: flights, contexts: contexts, places: inputs.logbook.places)
      findings += geography.findings
      run.followUps.merge(geography.followUps) { first, _ in first }
    }

    if inputs.approachLookup == nil {
      run.notes.append(
        AuditNote(
          subject: .approachData,
          message: String(
            localized: "Approaches weren’t named, because no CIFP approach data is loaded.",
            bundle: .module
          )
        )
      )
    }
    let navigation = await NavigationAudit(
      index: inputs.airportIndex,
      lookup: inputs.approachLookup
    )
    .run(on: flights, contexts: contexts)
    findings += navigation.findings
    run.followUps.merge(navigation.followUps) { first, _ in first }
    return findings
  }

  private func noteMissingEvidence(_ inputs: AuditInputs, into run: inout AuditRun) {
    if inputs.flyStoRecords.isEmpty {
      run.notes.append(
        AuditNote(
          subject: .flySto,
          message: String(
            localized: "No FlySto records have been synced or imported.",
            bundle: .module
          )
        )
      )
    }
    if inputs.tracks.isEmpty {
      run.notes.append(
        AuditNote(
          subject: .adsb,
          message: String(localized: "No ADS-B tracks have been downloaded.", bundle: .module)
        )
      )
    }
  }
}
