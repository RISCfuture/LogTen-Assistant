import Credentials
import FlightSources
import Foundation
import References
import Tracks

/// The outside services a logbook session works through: FlySto, adsb.lol, and the downloaded
/// reference data. UI tests replace them with stubs through launch arguments.
nonisolated struct SessionServices: Sendable {
  private static let applicationSupportFolder = "LogTen Assistant"

  /// The folder that holds downloaded ADS-B traces.
  static var adsbCacheDirectory: URL {
    URL.cachesDirectory.appending(path: "ADS-B", directoryHint: .isDirectory)
  }

  /// The services the app uses outside of tests.
  static var live: Self {
    let support = URL.applicationSupportDirectory.appending(
      path: applicationSupportFolder,
      directoryHint: .isDirectory
    )
    return Self(
      flySto: { FlyStoClient(keychain: Keychain()) },
      hasFlyStoToken: { (try? Keychain().string(for: .flyStoAPIToken))?.isEmpty == false },
      adsb: ADSBLolClient(),
      adsbCache: ADSBTraceCache(directory: adsbCacheDirectory),
      nasr: NASRCycleStore(directory: support.appending(path: "NASR", directoryHint: .isDirectory)),
      cifp: CIFPStore(directory: support.appending(path: "CIFP", directoryHint: .isDirectory))
    )
  }

  /// The global track-detection thresholds from Settings ▸ Track Detection.
  static var trackDetection: TrackDetectionSettings {
    var settings = TrackDetectionSettings()
    let defaults = UserDefaults.standard
    func read(_ key: String, into value: inout Double) {
      if defaults.object(forKey: key) != nil { value = defaults.double(forKey: key) }
    }
    read(AppSettingsKey.trackAirborneKts, into: &settings.airborneKts)
    read(AppSettingsKey.trackGroundKts, into: &settings.groundKts)
    read(AppSettingsKey.trackConfirmSeconds, into: &settings.confirmSeconds)
    read(AppSettingsKey.trackStopSeconds, into: &settings.stopSeconds)
    read(AppSettingsKey.trackGapSeconds, into: &settings.gapSeconds)
    return settings
  }

  /// Makes a FlySto client with the stored token.
  var flySto: @Sendable () -> FlyStoClient

  /// Whether a FlySto API token is stored.
  var hasFlyStoToken: @Sendable () -> Bool

  /// The adsb.lol archive.
  var adsb: ADSBLolClient

  /// Where downloaded ADS-B traces are kept.
  var adsbCache: ADSBTraceCache

  /// Where downloaded NASR cycles are kept.
  var nasr: NASRCycleStore

  /// Where the FAA's CIFP file is kept, and how it is downloaded.
  var cifp: CIFPStore
}
