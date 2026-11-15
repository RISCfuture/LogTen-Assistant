import FlightSources
import Foundation
import LogbookModel
import Observation

/**
 Drives the Fetch ADS-B Data sheet: finds the adsb.lol releases for the chosen days and reports
 how much they would download, then hands them to the session's ``ADSBDownloadJob``.

 Each day's archive is several gigabytes, so the size is shown before anything is downloaded.
 Days whose traces are already saved are left out.
 */
@Observable
final class ADSBFetchModel {
  private static let maximumDays = 31

  /// The first day to fetch.
  var startDate: Date

  /// The last day to fetch.
  var endDate: Date

  /// The aircraft to fetch, by registration.
  var selectedRegistrations: Set<String>

  /// Where the fetch stands.
  private(set) var phase = Phase.choosing

  @ObservationIgnored private let fetchable: [FetchableAircraft]

  @ObservationIgnored private let session: LogbookSession
  @ObservationIgnored private var task: Task<Void, Never>?

  /// The days chosen, at most a month.
  var days: [ADSBArchiveDay] {
    let start = min(startDate, endDate)
    let end = max(startDate, endDate)
    return Array(
      ADSBArchiveDay.days(covering: DateInterval(start: start, end: end)).prefix(Self.maximumDays)
    )
  }

  /// The aircraft with a known ICAO address that were flown on the chosen days.
  var aircraft: [FetchableAircraft] {
    let chosen = Set(days)
    return fetchable.filter { !$0.days.isDisjoint(with: chosen) }
  }

  /// Whether there are days and aircraft to check.
  var canCheckSize: Bool { !days.isEmpty && !addresses.isEmpty }

  private var addresses: Set<ICAOAddress> {
    Set(aircraft.filter { selectedRegistrations.contains($0.registration) }.map(\.address))
  }

  /// Creates the model, starting with the logbook's most recent day flown.
  init(session: LogbookSession) {
    self.session = session
    let latest = session.logbook?.flights.map(\.date).max() ?? .now
    startDate = latest
    endDate = latest
    let flights = session.logbook?.flights ?? []
    let daysFlown = Dictionary(grouping: flights) { $0.aircraft?.registration ?? "" }
      .mapValues { Set($0.map { ADSBArchiveDay($0.date) }) }
    fetchable = session.registrations.compactMap { registration in
      let override = session.settings.settings(forAircraft: registration).icaoAddress
      guard let address = override ?? ICAOAddress(usRegistration: registration) else {
        return nil
      }
      return FetchableAircraft(
        registration: registration,
        address: address,
        days: daysFlown[registration] ?? []
      )
    }
    selectedRegistrations = Set(fetchable.map(\.registration))
  }

  /// Finds the releases for the chosen days and their combined size.
  func checkSize() {
    let days = days
    let wanted = addresses
    let cache = session.services.adsbCache
    let download = ADSBDayDownload(client: session.services.adsb, cache: cache)
    phase = .checking
    task = Task {
      do {
        let needed = days.filter { day in wanted.contains { !cache.contains(day: day, icao: $0) } }
        let estimate = try await download.estimate(needed)
        phase = .confirming(estimate)
      } catch is CancellationError {
        phase = .choosing
      } catch {
        phase = .failed(error.localizedDescription)
      }
    }
  }

  /// Starts the session's download of the estimated releases, keeping the chosen aircraft's
  /// traces. Returns whether it started.
  @discardableResult
  func startDownload() -> Bool {
    guard case .confirming(let estimate) = phase, !estimate.days.isEmpty,
      !session.adsbDownload.isActive
    else { return false }
    session.adsbDownload.start(estimate, addresses: addresses)
    return true
  }

  /// Forgets an estimate that no longer matches the chosen days and aircraft.
  func choiceDidChange() {
    if case .checking = phase { return }
    phase = .choosing
  }

  /// Stops checking the size.
  func cancel() { task?.cancel() }

  /// Where the sheet stands.
  enum Phase {
    /// The user is choosing days and aircraft.
    case choosing
    /// The releases and their sizes are being looked up.
    case checking
    /// The download's size is known and awaits confirmation.
    case confirming(ADSBEstimate)
    /// Looking up the releases failed.
    case failed(String)
  }
}

/// An aircraft whose ADS-B traces can be fetched.
struct FetchableAircraft {
  /// The aircraft's registration.
  let registration: String

  /// The aircraft's ICAO address.
  let address: ICAOAddress

  /// The UTC days it was flown.
  let days: Set<ADSBArchiveDay>
}
