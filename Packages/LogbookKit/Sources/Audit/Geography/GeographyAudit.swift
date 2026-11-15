import Foundation
import FlightSources
public import LogbookModel
public import References
import Tracks

extension RuleID {
  /// Aircraft evidence places a flight boundary at a different airport than the entry's route.
  public static let telemetryAirport: Self = "telemetry_airport"
  /// Aircraft evidence suggests a landing at an airport other than the route's endpoints.
  public static let telemetryIntermediateStop: Self = "telemetry_intermediate_stop"
  /// The entry's date matches the observed departure on neither the UTC nor the local calendar.
  public static let telemetryFlightDate: Self = "telemetry_flight_date"
  /// The logged distance matches none of the measured distances.
  public static let telemetryDistance: Self = "telemetry_distance"
  /// The aircraft went more than 50 NM from its departure while the ATP cross-country field is
  /// zero.
  public static let telemetryATPCrossCountryCandidate: Self =
    "telemetry_atp_cross_country_candidate"
  /// A complete track stayed within 50 NM of its departure while the ATP cross-country field is
  /// set.
  public static let telemetryATPCrossCountryIneligible: Self =
    "telemetry_atp_cross_country_ineligible"
}

/// Settings for ``GeographyAudit``.
public struct GeographyAuditOptions: Hashable, Codable, Sendable {
  /// Whether the logbook's distance field is in nautical miles. Distances are compared only
  /// when this has been verified.
  public var isDistanceUnitNauticalMiles: Bool

  /// How far the logged distance must differ from every measure to be reported, in nautical
  /// miles; the larger of this and ``distanceToleranceFraction`` applies.
  public var distanceToleranceNM: Double

  /// The same tolerance as a fraction of the measured distance.
  public var distanceToleranceFraction: Double

  /// The longest interval between positions that still counts as continuous coverage, in
  /// seconds.
  public var maximumGapSeconds: Double

  /// The fastest the aircraft could plausibly have flown between positions, in knots.
  public var speedBoundKnots: Double

  /// Creates options.
  public init(
    isDistanceUnitNauticalMiles: Bool = false,
    distanceToleranceNM: Double = 10,
    distanceToleranceFraction: Double = 0.2,
    maximumGapSeconds: Double = 120,
    speedBoundKnots: Double = 600
  ) {
    self.isDistanceUnitNauticalMiles = isDistanceUnitNauticalMiles
    self.distanceToleranceNM = distanceToleranceNM
    self.distanceToleranceFraction = distanceToleranceFraction
    self.maximumGapSeconds = maximumGapSeconds
    self.speedBoundKnots = speedBoundKnots
  }
}

/// The findings of a geography audit and what helps a reviewer decide them.
public struct GeographyAuditResult: Hashable, Sendable {
  /// The findings.
  public var findings: [Finding]
  /// The follow-up of each finding.
  public var followUps: [FindingID: AuditFollowUp]
}

/// The distances 14 CFR 61.1 cross-country definitions use, measured from the original
/// departure.
public struct CrossCountryDistances: Hashable, Sendable {
  /// The direct distance from departure to destination, in nautical miles, which decides
  /// ordinary cross-country time. FlySto's measure stands in when the airports are unknown.
  public var crossCountryNM: Double?

  /// The farthest the aircraft got from its departure, in nautical miles, which decides ATP
  /// cross-country time.
  public var atpCrossCountryNM: Double?
}

/**
 Reviews the airports, route, date and distance of entries against the aircraft's track and
 FlySto's record, a port of cleanup-logten's `geography_audit`.

 Airports are named from runway geometry or from FlySto, and only for a flight boundary that
 the evidence shows completely. Every finding is review-only: the audit never assigns personal
 credit and never proposes a numeric change.
 */
public struct GeographyAudit: Sendable {
  private typealias Item = (finding: Finding, followUp: AuditFollowUp)

  private static let crossCountryCitation =
    "https://www.ecfr.gov/current/title-14/chapter-I/subchapter-D/part-61/subpart-A/section-61.1"
  private static let atpThresholdNM = 50.0
  private static let positionMarginNM = 3.0
  private static let finalLandingMatchSeconds = 120.0
  private static let secondsPerHour = 3_600.0
  private static let shortestAirportNameForMention = 3

  private let index: AirportIndex
  private let mapping: FieldMapping
  private let tolerances: AuditTolerances
  private let options: GeographyAuditOptions
  private let timeZones: AirportTimeZones?

  /**
   Creates an audit.

   - Parameters:
     - index: The airport reference data for the audit's date.
     - mapping: Which custom field holds ATP cross-country time.
     - tolerances: How far logged times may stray before partial credit is assumed.
     - options: Distance and coverage settings.
     - timeZones: Where to find the departure airport's time zone; without it dates are
       compared in UTC only.
   */
  public init(
    index: AirportIndex,
    mapping: FieldMapping,
    tolerances: AuditTolerances = .init(),
    options: GeographyAuditOptions = .init(),
    timeZones: AirportTimeZones? = nil
  ) {
    self.index = index
    self.mapping = mapping
    self.tolerances = tolerances
    self.options = options
    self.timeZones = timeZones
  }

  private static func dateText(_ date: Date, in timeZone: TimeZone) -> String {
    date.formatted(Date.ISO8601FormatStyle(timeZone: timeZone).year().month().day())
  }

  private static func rounded(_ value: Double) -> Double { (value * 1_000).rounded() / 1_000 }

  /**
   The distances for cross-country time.

   - Parameters:
     - context: The entry's evidence.
     - origin: The departure airport.
     - destination: The arrival airport.
   */
  public func crossCountryDistances(
    in context: EvidenceContext,
    from origin: AirportReference?,
    to destination: AirportReference?
  ) -> CrossCountryDistances {
    var endpoint = measuredDistances(of: context)["flysto_direct_distance_nm"]
    if let origin, let destination {
      endpoint = GreatCircle.distanceNM(
        origin.latitudeDeg,
        origin.longitudeDeg,
        destination.latitudeDeg,
        destination.longitudeDeg
      )
    }
    var displacements = endpoint.map { [$0] } ?? []
    if let origin {
      displacements += windowedPositions(of: context).map {
        GreatCircle.distanceNM(
          origin.latitudeDeg,
          origin.longitudeDeg,
          $0.latitudeDeg,
          $0.longitudeDeg
        )
      }
    }
    return CrossCountryDistances(crossCountryNM: endpoint, atpCrossCountryNM: displacements.max())
  }

  /**
   Audits the entries that have external evidence.

   - Parameters:
     - flights: The logbook entries.
     - contexts: The evidence for each entry.
     - places: The logbook's places, to name waypoints.
   */
  public func run(
    on flights: [Flight],
    contexts: [RecordID: EvidenceContext],
    places: [Place] = []
  ) async -> GeographyAuditResult {
    var result = GeographyAuditResult(findings: [], followUps: [:])
    let placesByID = Dictionary(places.map { ($0.id.rawValue, $0) }) { first, _ in first }
    for flight in flights where !flight.isSimulatorEntry {
      guard let context = contexts[flight.id] else { continue }
      let origin = endpoint(.departure, of: context)
      let destination = endpoint(.arrival, of: context)
      let subject = Subject(
        flight: flight,
        context: context,
        origin: origin,
        destination: destination
      )
      var items = airportFindings(subject)
      items += stopFindings(subject, placesByID)
      items += await dateFindings(subject)
      items += distanceFindings(subject)
      items += crossCountryFindings(subject)
      for item in items {
        result.findings.append(item.finding)
        result.followUps[item.finding.id] = item.followUp
      }
    }
    return result
  }

  // MARK: Endpoints

  /// Whether the evidence shows the boundary itself, not just a track that happens to start or
  /// end somewhere.
  private func isBoundaryObserved(_ side: Side, in context: EvidenceContext) -> Bool {
    if context.timeSources[side.timeKind] == .flySto {
      return context.times[side.timeKind] != nil
    }
    let ordered = context.segments.sorted { $0.start < $1.start }
    guard let segment = side == .departure ? ordered.first : ordered.last else { return false }
    let isComplete = side == .departure ? !segment.isIncompleteAtStart : !segment.isIncompleteAtEnd
    guard isComplete, let observed = boundaryEvent(side, in: context) else { return false }
    return observed.confidence != .low
  }

  private func boundaryEvent(_ side: Side, in context: EvidenceContext) -> TrackEvent? {
    let events = context.events.filter { $0.kind == side.eventKind }
    return side == .departure ? events.min { $0.time < $1.time } : events.max { $0.time < $1.time }
  }

  private func endpoint(_ side: Side, of context: EvidenceContext) -> AirportReference? {
    guard isBoundaryObserved(side, in: context) else { return nil }
    if context.timeSources[side.timeKind] != .flySto, let event = boundaryEvent(side, in: context) {
      return airport(at: event)
    }
    return (side == .departure ? context.from : context.to).flatMap(index.airport(matching:))
  }

  private func airport(at event: TrackEvent) -> AirportReference? {
    guard event.confidence != .low, let position = event.validPosition else { return nil }
    return index.airport(
      onRunwayAtLatitudeDeg: position.latitudeDeg,
      longitudeDeg: position.longitudeDeg
    )
  }

  private func loggedAirport(_ place: Place?) -> AirportReference? {
    guard let place else { return nil }
    let identifiers = [place.identifier, place.ICAO, place.FAAID].compactMap(\.self)
    return identifiers.compactMap(index.airport(matching:)).first
  }

  /// The landings and full stops inside the entry's interval with the airport each was on.
  private func landings(of context: EvidenceContext) -> [(
    event: TrackEvent, airport: AirportReference
  )] {
    context.eventsWithinInterval.sorted { $0.time < $1.time }
      .filter { $0.kind == .landing || $0.kind == .fullStop }
      .compactMap { event in airport(at: event).map { (event, $0) } }
  }

  // MARK: Airports

  private func airportFindings(_ subject: Subject) -> [Item] {
    [
      (Side.departure, subject.origin, subject.flight.from),
      (.arrival, subject.destination, subject.flight.to)
    ]
    .compactMap { side, observed, place in
      guard let observed, let logged = loggedAirport(place),
        observed.identifier != logged.identifier
      else { return nil }
      return item(
        subject,
        rule: .telemetryAirport,
        message: String(
          localized:
            "Independently matched aircraft evidence places a flight boundary at a different airport; review the entry route.",
          bundle: .module
        ),
        field: side.rawValue,
        logged: .string(place?.identifier ?? ""),
        observed: .string(observed.identifier),
        notes: [
          String(
            localized:
              "NASR aliases and runway geometry use the \(index.effectiveDate, format: .dateTime.year().month().day()) reference cycle. Historical identifiers and layouts, and combined entries, require review.",
            bundle: .module
          )
        ]
      )
    }
  }

  private func stopFindings(_ subject: Subject, _ placesByID: [String: Place]) -> [Item] {
    let arrivals = landings(of: subject.context)
    let lastLanding = arrivals.map(\.event.time).max()
    let landingTime = subject.context.times[.landing]
    let flight = subject.flight
    let remarks = [flight.remarks, flight.route].compactMap(\.self).joined(separator: " ")
    let waypoints = waypointPlaces(of: flight, placesByID)
    var seen = Set<String>()
    return arrivals.compactMap { event, airport in
      let isLast = event.time == lastLanding
      let isFinal: Bool
      if let destination = subject.destination {
        isFinal =
          destination.identifier == airport.identifier
          && (isLast || isNearLanding(event, landingTime))
      } else {
        isFinal = isLast
      }
      guard !isFinal, seen.insert(airport.identifier).inserted else { return nil }
      let isWaypoint = waypoints.contains { loggedAirport($0)?.identifier == airport.identifier }
      var logged: [String: JSONValue] = [
        "from": .string(flight.from?.identifier ?? ""),
        "to": .string(flight.to?.identifier ?? ""),
        "remarks": .string(remarks)
      ]
      var observed: [String: JSONValue] = [
        "airport": .string(airport.identifier),
        "time": .string(event.time.formatted(.iso8601)),
        "mentioned_in_remarks": .bool(isMentioned(airport, in: remarks))
      ]
      if isWaypoint {
        logged["waypoints"] = .array(waypoints.map { .string($0.identifier) })
        observed["mentioned_in_waypoints"] = .bool(true)
      }
      return item(
        subject,
        rule: .telemetryIntermediateStop,
        message: String(
          localized:
            "Aircraft evidence suggests an intermediate landing; review whether this entry intentionally combines legs.",
          bundle: .module
        ),
        field: "route",
        logged: .object(logged),
        observed: .object(observed),
        notes: [
          String(
            localized:
              "A landing candidate does not prove a diversion or an erroneous combined entry. Remarks or recorded waypoints may document the intended itinerary.",
            bundle: .module
          )
        ]
      )
    }
  }

  private func isNearLanding(_ event: TrackEvent, _ landingTime: Date?) -> Bool {
    landingTime.map { abs(event.time.timeIntervalSince($0)) < Self.finalLandingMatchSeconds }
      == true
  }

  private func isMentioned(_ airport: AirportReference, in text: String) -> Bool {
    var names = airport.aliases
    if airport.name.count > Self.shortestAirportNameForMention { names.append(airport.name) }
    return names.contains { name in
      let pattern = "\\b\(NSRegularExpression.escapedPattern(for: name))\\b"
      return (try? Regex(pattern).ignoresCase()).map { text.contains($0) } ?? false
    }
  }

  private func waypointPlaces(of flight: Flight, _ placesByID: [String: Place]) -> [Place] {
    let value = flight.otherValues.first {
      $0.key.attributeName.lowercased() == "waypointplaceids"
    }?
    .value
    guard case .text(let text)? = value else { return [] }
    return text.components(separatedBy: "::").compactMap { placesByID[$0] }
  }

  // MARK: Date

  private func dateFindings(_ subject: Subject) async -> [Item] {
    guard let origin = subject.origin, let timeZones,
      let zone = await timeZones.timeZone(of: origin),
      let timeZone = TimeZone(identifier: zone.identifier)
    else { return [] }
    let context = subject.context
    let moments = [context.start, context.times[.out], context.times[.takeoff]].compactMap(\.self)
    let dates = Set(
      moments.flatMap { [Self.dateText($0, in: .gmt), Self.dateText($0, in: timeZone)] }
    )
    let logged = Self.dateText(subject.flight.date, in: .gmt)
    guard !dates.isEmpty, !dates.contains(logged) else { return [] }
    return [
      item(
        subject,
        rule: .telemetryFlightDate,
        message: String(
          localized:
            "The entry date differs from observed departure dates in both UTC and the departure airport timezone; review the date convention.",
          bundle: .module
        ),
        field: LogTenFieldKey.flightDate.attributeName.lowercased(),
        logged: .string(logged),
        observed: [
          "departure_dates": .array(dates.sorted().map(JSONValue.string)),
          "timezone": .string(zone.identifier)
        ],
        notes: [
          String(
            localized:
              "UTC date and local logbook date need not agree. This comparison does not authorize a date or timezone edit.",
            bundle: .module
          )
        ]
      )
    ]
  }

  // MARK: Distance

  private func measuredDistances(of context: EvidenceContext) -> [String: Double] {
    guard context.primarySource == .flySto else { return [:] }
    let metrics = context.metrics
    return [
      "flysto_direct_distance_nm": metrics.directDistanceNM,
      "flysto_ground_distance_nm": metrics.groundDistanceNM,
      "flysto_air_distance_nm": metrics.airDistanceNM
    ].compactMapValues { $0 }.filter { $0.value >= 0 }
  }

  /// The distance flown through the airports landed at on the way, if there were any.
  private func recordedLegsNM(_ subject: Subject) -> Double? {
    guard let origin = subject.origin, let destination = subject.destination else { return nil }
    var route = [origin]
    for (_, airport) in landings(of: subject.context)
    where airport.identifier != route.last?.identifier {
      route.append(airport)
    }
    if destination.identifier != route.last?.identifier { route.append(destination) }
    guard route.count > 2 else { return nil }
    return zip(route, route.dropFirst()).reduce(0) {
      $0
        + GreatCircle.distanceNM(
          $1.0.latitudeDeg,
          $1.0.longitudeDeg,
          $1.1.latitudeDeg,
          $1.1.longitudeDeg
        )
    }
  }

  private func distanceFindings(_ subject: Subject) -> [Item] {
    guard options.isDistanceUnitNauticalMiles, let logged = subject.flight.distanceNM, logged > 0
    else { return [] }
    var observed = measuredDistances(of: subject.context)
    if let origin = subject.origin, let destination = subject.destination {
      observed["airport_direct_distance_nm"] = Self.rounded(
        GreatCircle.distanceNM(
          origin.latitudeDeg,
          origin.longitudeDeg,
          destination.latitudeDeg,
          destination.longitudeDeg
        )
      )
    }
    if let legs = recordedLegsNM(subject) {
      observed["recorded_legs_distance_nm"] = Self.rounded(legs)
    }
    guard !observed.isEmpty,
      observed.values.allSatisfy({
        abs(logged - $0) > max(options.distanceToleranceNM, options.distanceToleranceFraction * $0)
      })
    else { return [] }
    var detail = observed.mapValues(JSONValue.double)
    detail["logged_distance_unit"] = "nm"
    return [
      item(
        subject,
        rule: .telemetryDistance,
        message: String(
          localized:
            "Logged distance differs from the available direct and FlySto distance measures; review the intended distance convention.",
          bundle: .module
        ),
        field: LogTenFieldKey.flightDistance.attributeName.lowercased(),
        logged: .double(logged),
        observed: .object(detail),
        notes: [
          String(
            localized:
              "Airport direct distance, ground track length and air distance measure different things. A difference alone does not establish an incorrect value; no numeric change is proposed.",
            bundle: .module
          )
        ]
      )
    ]
  }

  // MARK: ATP cross-country

  /// The positions between takeoff and landing, or between the interval's ends if either is
  /// unknown.
  private func windowedPositions(of context: EvidenceContext) -> [TrackSample] {
    let start = context.times[.takeoff] ?? context.start
    let end = context.times[.landing] ?? context.end
    return context.usablePositions.filter { sample in
      sample.hasValidPosition && (start.map { sample.time >= $0 } ?? true)
        && (end.map { sample.time <= $0 } ?? true)
    }
  }

  private func crossCountryFindings(_ subject: Subject) -> [Item] {
    let flight = subject.flight
    guard flight.aircraft?.type?.category != .rotorcraft,
      let field = mapping[.atpCrossCountry],
      flight.value(for: .atpCrossCountry, in: mapping)?.isNull == false,
      let logged = flight.minutes(for: .atpCrossCountry, in: mapping)
    else { return [] }
    var observed = measuredDistances(of: subject.context).mapValues(JSONValue.double)
    if let origin = subject.origin, let destination = subject.destination {
      observed["endpoint_displacement_nm"] = .double(
        Self.rounded(
          GreatCircle.distanceNM(
            origin.latitudeDeg,
            origin.longitudeDeg,
            destination.latitudeDeg,
            destination.longitudeDeg
          )
        )
      )
    }
    let rows = windowedPositions(of: subject.context)
    if let origin = subject.origin, !rows.isEmpty {
      observed["max_displacement_nm"] = .double(
        Self.rounded(rows.map { displacement(from: origin, $0) }.max() ?? 0)
      )
    }
    let atpDistance = crossCountryDistances(
      in: subject.context,
      from: subject.origin,
      to: subject.destination
    ).atpCrossCountryNM
    let isGeographic = (atpDistance ?? 0) > Self.atpThresholdNM
    let notes = [
      String(
        localized:
          "14 CFR 61.1(b), Cross-country time (vi), uses displacement more than 50 NM from original departure for ATP experience, without requiring a landing there. Navigation, aircraft eligibility and personal credit require separate evidence.",
        bundle: .module
      )
    ]
    if isGeographic && logged == 0 && !isPartialCredit(subject) {
      return [
        item(
          subject,
          rule: .telemetryATPCrossCountryCandidate,
          message: String(
            localized:
              "The aircraft met the ATP cross-country geographic threshold while the ATP field is zero; review personal eligibility and credit.",
            bundle: .module
          ),
          field: field.attributeName.lowercased(),
          logged: .integer(Int(logged)),
          observed: .object(observed),
          notes: notes,
          citation: Self.crossCountryCitation
        )
      ]
    }
    guard !isGeographic, logged > 0, let origin = subject.origin,
      let bound = trackBound(subject, from: origin),
      bound.conservativeUpperBoundNM < Self.atpThresholdNM
    else { return [] }
    return [
      item(
        subject,
        rule: .telemetryATPCrossCountryIneligible,
        message: String(
          localized:
            "A complete bounded track remains within 50 NM of departure; review the recorded ATP cross-country credit.",
          bundle: .module
        ),
        field: field.attributeName.lowercased(),
        logged: .integer(Int(logged)),
        observed: bound.jsonValue,
        notes: notes + [
          String(
            localized:
              "The upper bound includes travel possible between samples and a 3 NM position margin. Incomplete or widely spaced samples cannot disprove the threshold.",
            bundle: .module
          )
        ],
        citation: Self.crossCountryCitation
      )
    ]
  }

  private func displacement(from origin: AirportReference, _ sample: TrackSample) -> Double {
    GreatCircle.distanceNM(
      origin.latitudeDeg,
      origin.longitudeDeg,
      sample.latitudeDeg,
      sample.longitudeDeg
    )
  }

  private func isPartialCredit(_ subject: Subject) -> Bool {
    if subject.context.isInstruction { return true }
    guard let takeoff = subject.context.times[.takeoff],
      let landing = subject.context.times[.landing]
    else { return false }
    let elapsed = landing.timeIntervalSince(takeoff) / 60
    return Double(subject.flight.times.total) < elapsed - Double(tolerances.timeToleranceMinutes)
  }

  /// How far the aircraft could have got from its departure, if the track covers the whole
  /// flight with no gap, jump or missing boundary; otherwise `nil`.
  private func trackBound(_ subject: Subject, from origin: AirportReference) -> TrackBound? {
    let context = subject.context
    guard let takeoff = context.times[.takeoff], let landing = context.times[.landing],
      landing > takeoff, isBoundaryObserved(.departure, in: context),
      isBoundaryObserved(.arrival, in: context),
      !context.events.contains(where: { $0.kind == .gap })
    else { return nil }
    let rows = windowedPositions(of: context).filter { $0.time >= takeoff && $0.time <= landing }
    guard let first = rows.first, let last = rows.last else { return nil }
    let gaps = zip(rows, rows.dropFirst()).map { $1.time.timeIntervalSince($0.time) }
    let edgeGap = max(first.time.timeIntervalSince(takeoff), landing.timeIntervalSince(last.time))
    guard max(edgeGap, gaps.max() ?? 0) <= options.maximumGapSeconds,
      !rows.contains(where: { ($0.groundSpeedKts ?? 0) > options.speedBoundKnots })
    else { return nil }
    let farthest = rows.map { displacement(from: origin, $0) }.max() ?? 0
    let excursion =
      max(edgeGap, (gaps.max() ?? 0) / 2) * options.speedBoundKnots / Self.secondsPerHour
    return TrackBound(
      maximumDisplacementNM: farthest,
      conservativeUpperBoundNM: farthest + excursion + Self.positionMarginNM,
      maximumSampleGapSeconds: gaps.max() ?? 0,
      edgeGapSeconds: edgeGap,
      speedBoundKnots: options.speedBoundKnots
    )
  }

  // MARK: Findings

  private func item(
    _ subject: Subject,
    rule: RuleID,
    message: String,
    field: String,
    logged: JSONValue,
    observed: JSONValue,
    notes: [String],
    citation: String? = nil
  ) -> Item {
    let context = subject.context
    let endpointSources: JSONValue = [
      Side.departure.rawValue: context.timeSources[.takeoff].map { .string($0.rawValue) } ?? .null,
      Side.arrival.rawValue: context.timeSources[.landing].map { .string($0.rawValue) } ?? .null
    ]
    var evidence = context.provenanceEvidence
    evidence["source"] = .string(context.primarySource.rawValue)
    evidence["position_source"] = context.positionSource.map { .string($0.rawValue) } ?? .null
    evidence["endpoint_sources"] = endpointSources
    evidence["field"] = .string(field)
    evidence["logged"] = logged
    evidence["observed"] = observed
    evidence["preferred_source"] = nil
    return (
      Finding(
        rule: rule,
        recordIDs: [subject.flight.id],
        message: message,
        evidence: .object(evidence),
        citation: citation
      ),
      AuditFollowUp(notes: notes, events: context.events, sources: context.urls)
    )
  }

  private struct TrackBound {
    var maximumDisplacementNM: Double
    var conservativeUpperBoundNM: Double
    var maximumSampleGapSeconds: Double
    var edgeGapSeconds: Double
    var speedBoundKnots: Double

    var jsonValue: JSONValue {
      [
        "max_displacement_nm": .double(GeographyAudit.rounded(maximumDisplacementNM)),
        "conservative_upper_bound_nm": .double(GeographyAudit.rounded(conservativeUpperBoundNM)),
        "maximum_sample_gap_seconds": .double(maximumSampleGapSeconds),
        "edge_gap_seconds": .double(edgeGapSeconds),
        "assumed_speed_bound_knots": .double(speedBoundKnots),
        "position_margin_nm": .double(GeographyAudit.positionMarginNM)
      ]
    }
  }

  private enum Side: String {
    case departure = "from_place"
    case arrival = "to_place"

    var eventKind: TrackEvent.Kind { self == .departure ? .takeoff : .landing }
    var timeKind: FlyStoTimeKind { self == .departure ? .takeoff : .landing }
  }

  private struct Subject {
    var flight: Flight
    var context: EvidenceContext
    var origin: AirportReference?
    var destination: AirportReference?
  }
}
