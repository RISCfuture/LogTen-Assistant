public import Foundation
public import LogbookModel

extension RuleID {
  /// No airport reference data was available, so airport checks didn't run.
  public static let referenceUnavailable: Self = "reference_unavailable"
  /// The airport reference cycle doesn't cover the audit date.
  public static let referenceDate: Self = "reference_date"
  /// A place has no unambiguous match in the airport reference data.
  public static let airportUnmatched: Self = "airport_unmatched"
  /// A place's time zone differs from the airport's.
  public static let airportTimeZone: Self = "airport_timezone"
  /// A place's position differs from the airport's.
  public static let airportPosition: Self = "airport_position"
  /// A place's elevation differs from the airport's.
  public static let airportElevation: Self = "airport_elevation"
  /// Time zones couldn't be looked up, so time-zone checks didn't run.
  public static let timeZoneUnavailable: Self = "timezone_unavailable"
}

/// Compares the logbook's places with the FAA airport reference data, a port of
/// cleanup-logten's `references.audit_places`.
public struct PlaceReferenceAudit: Sendable {
  /// Where the data the checks rest on is documented.
  public static let citation =
    "https://www.faa.gov/air_traffic/flight_info/aeronav/aero_data/NASR_Subscription/"

  private static let positionToleranceNM = 0.5
  private static let elevationToleranceFt = 100.0
  private static let seasonalMonths = [1, 4, 7, 10]
  private static let midMonthDay = 15

  private let index: AirportIndex?
  private let nonAirportPlaces: Set<String>
  private let timeZones: AirportTimeZones?

  /**
   Creates an audit.

   - Parameters:
     - index: The airport reference data; without it the audit only reports that it can't run.
     - nonAirportPlaces: Identifiers of places that are known not to be airports.
     - timeZones: Where to find airport time zones; without it time zones aren't checked.
   */
  public init(
    index: AirportIndex?,
    nonAirportPlaces: Set<String> = [],
    timeZones: AirportTimeZones? = nil
  ) {
    self.index = index
    self.nonAirportPlaces = Set(nonAirportPlaces.map { $0.uppercased() })
    self.timeZones = timeZones
  }

  /// Whether two zones have the same UTC offset in the middle of each season of a year, so that
  /// differently spelled aliases of one zone compare equal.
  private static func sameSeasonalOffsets(_ expected: String, _ actual: String?, year: Int) -> Bool
  {
    guard let actual, let expectedZone = TimeZone(identifier: expected),
      let actualZone = TimeZone(identifier: actual)
    else { return false }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    return seasonalMonths.allSatisfy { month in
      guard
        let moment = calendar.date(
          from: DateComponents(year: year, month: month, day: midMonthDay)
        )
      else { return false }
      return expectedZone.secondsFromGMT(for: moment) == actualZone.secondsFromGMT(for: moment)
    }
  }

  private static func year(of date: Date) -> Int {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    return calendar.component(.year, from: date)
  }

  private static func iso(_ date: Date) -> String {
    date.formatted(.iso8601.year().month().day())
  }

  /**
   Checks places against the reference data.

   - Parameters:
     - places: The logbook's places.
     - date: The date the audit is for, which decides whether the reference cycle is current and
       so whether corrections may be proposed.
   - Returns: The findings.

   */
  public func run(on places: [Place], asOf date: Date) async -> [Finding] {
    guard let index else {
      return [
        Finding(
          rule: .referenceUnavailable,
          recordIDs: [RecordID](),
          message: String(
            localized: "Airport checks were not evaluated: configure a dated NASR dataset.",
            bundle: .module
          )
        )
      ]
    }
    var findings = [Finding]()
    let isCurrent = index.covers(date)
    if !isCurrent {
      findings.append(outOfCycleFinding(index, date))
    }
    for place in places {
      guard let airport = airport(for: place, in: index) else {
        findings += unmatchedFinding(place, index).map { [$0] } ?? []
        continue
      }
      let evidence = [
        "airport": JSONValue.string(airport.identifier),
        "nasr_effective": .string(Self.iso(index.effectiveDate))
      ]
      if let timeZones {
        if let finding = await timeZoneFinding(
          place,
          airport,
          evidence,
          date,
          isCurrent,
          timeZones
        ) {
          findings.append(finding)
        }
      }
      findings += positionFinding(place, airport, evidence)
      findings += elevationFinding(place, airport, evidence)
    }
    if let timeZones, await timeZones.failedLookups > 0 {
      findings.append(
        Finding(
          rule: .timeZoneUnavailable,
          recordIDs: [RecordID](),
          message: String(
            localized:
              "Some airport time zones could not be looked up, so time-zone checks were incomplete.",
            bundle: .module
          )
        )
      )
    }
    return findings
  }

  private func airport(for place: Place, in index: AirportIndex) -> AirportReference? {
    let identifiers = [place.ICAO, place.FAAID, place.identifier].compactMap(\.self)
    return identifiers.compactMap(index.airport(matching:)).first
  }

  private func outOfCycleFinding(_ index: AirportIndex, _ date: Date) -> Finding {
    Finding(
      rule: .referenceDate,
      recordIDs: [RecordID](),
      message: String(
        localized:
          "NASR cycle does not cover the audit date; differences require historical review.",
        bundle: .module
      ),
      evidence: [
        "effective": .string(Self.iso(index.effectiveDate)), "as_of": .string(Self.iso(date))
      ]
    )
  }

  private func unmatchedFinding(_ place: Place, _ index: AirportIndex) -> Finding? {
    guard !nonAirportPlaces.contains(place.identifier.uppercased()) else { return nil }
    return Finding(
      rule: .airportUnmatched,
      recordIDs: [place.id],
      message: String(
        localized: "Airport has no unambiguous match in this NASR release.",
        bundle: .module
      ),
      evidence: [
        "identifier": .string(place.identifier),
        "nasr_effective": .string(Self.iso(index.effectiveDate))
      ]
    )
  }

  private func timeZoneFinding(
    _ place: Place,
    _ airport: AirportReference,
    _ evidence: [String: JSONValue],
    _ date: Date,
    _ isCurrent: Bool,
    _ timeZones: AirportTimeZones
  ) async -> Finding? {
    guard let expected = await timeZones.timeZone(of: airport),
      !Self.sameSeasonalOffsets(
        expected.identifier,
        place.timeZoneIdentifier,
        year: Self.year(of: date)
      )
    else { return nil }
    var detail = evidence
    detail["actual"] = place.timeZoneIdentifier.map(JSONValue.string) ?? .null
    detail["expected"] = .string(expected.identifier)
    detail["timezone_source"] = .string(expected.source.rawValue)
    return Finding(
      rule: .airportTimeZone,
      recordIDs: [place.id],
      message: String(
        localized: "Stored airport timezone differs from geographic timezone data.",
        bundle: .module
      ),
      evidence: .object(detail),
      severity: .questionable,
      corrections: isCurrent
        ? [
          CorrectionOption(
            title: String(localized: "Use the Geographic Time Zone", bundle: .module),
            detail: String(
              localized: "Time zone becomes “\(expected.identifier)”.",
              bundle: .module
            ),
            changes: [
              FieldChange(
                flightKey: nil,
                recordID: place.id,
                field: LogTenFieldKey(.place, "timeZoneName"),
                old: place.timeZoneIdentifier.map(FieldValue.text) ?? .null,
                new: .text(expected.identifier)
              )
            ]
          )
        ] : [],
      citation: Self.citation
    )
  }

  private func positionFinding(
    _ place: Place,
    _ airport: AirportReference,
    _ evidence: [String: JSONValue]
  ) -> [Finding] {
    guard let latitude = place.latitudeDeg, let longitude = place.longitudeDeg else { return [] }
    let distance = GreatCircle.distanceNM(
      latitude,
      longitude,
      airport.latitudeDeg,
      airport.longitudeDeg
    )
    guard distance > Self.positionToleranceNM else { return [] }
    var detail = evidence
    detail["distance_nm"] = .double((distance * 1_000).rounded() / 1_000)
    return [
      Finding(
        rule: .airportPosition,
        recordIDs: [place.id],
        message: String(
          localized: "Stored airport position differs by more than 0.5 NM.",
          bundle: .module
        ),
        evidence: .object(detail),
        citation: Self.citation
      )
    ]
  }

  private func elevationFinding(
    _ place: Place,
    _ airport: AirportReference,
    _ evidence: [String: JSONValue]
  ) -> [Finding] {
    guard let actual = place.elevationFt, let expected = airport.elevationFt,
      abs(Double(actual) - expected) > Self.elevationToleranceFt
    else { return [] }
    var detail = evidence
    detail["actual"] = .integer(actual)
    detail["expected"] = .double(expected)
    return [
      Finding(
        rule: .airportElevation,
        recordIDs: [place.id],
        message: String(
          localized: "Stored airport elevation differs by more than 100 feet.",
          bundle: .module
        ),
        evidence: .object(detail),
        citation: Self.citation
      )
    ]
  }
}
