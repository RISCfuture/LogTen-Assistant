import Foundation

/// Identifying details read from the running app's bundle.
struct AppInfo: Equatable {
  static var current: Self {
    let info = Bundle.main.infoDictionary ?? [:]
    func string(_ key: String) -> String? {
      (info[key] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }
    return Self(
      name: string("CFBundleName") ?? "LogTen Assistant",
      version: string("CFBundleShortVersionString") ?? "—",
      build: string("CFBundleVersion") ?? "—",
      copyright: string("NSHumanReadableCopyright") ?? fallbackCopyright
    )
  }

  /// The notice shown when the bundle carries no `NSHumanReadableCopyright`, naming the
  /// current year.
  private static var fallbackCopyright: String {
    let year = Calendar.current.component(.year, from: .now)
    return String(localized: "Copyright © \(year, format: .number.grouping(.never))")
  }

  var name: String
  var version: String
  var build: String
  var copyright: String
}

/// A Swift package or data source the app builds on, as the About window credits it.
struct Acknowledgement: Identifiable, Equatable {
  let name: String
  let license: String
  let url: URL

  var id: String { name }
}

extension Acknowledgement {
  /// The Swift packages the app links directly.
  static let packages = [
    package("SwiftAirmen", license: "MIT", repository: "RISCfuture/SwiftAirmen"),
    package("SwiftNASR", license: "MIT", repository: "RISCfuture/SwiftNASR"),
    package("SwiftCIFP", license: "MIT", repository: "RISCfuture/SwiftCIFP"),
    package("MeasurementKit", license: "MIT", repository: "RISCfuture/MeasurementKit"),
    package("StreamingCSV", license: "MIT", repository: "RISCfuture/StreamingCSV"),
    package("GitHubUpdateChecker", license: "MIT", repository: "RISCfuture/GitHubUpdateChecker"),
    package("GRDB.swift", license: "MIT", repository: "groue/GRDB.swift"),
    package("ZIPFoundation", license: "MIT", repository: "weichsel/ZIPFoundation"),
    package("sentry-cocoa", license: "MIT", repository: "getsentry/sentry-cocoa")
  ]

  /// The sources of the flight and reference data the app audits against.
  static let dataSources = [
    source(
      "FAA National Airspace System Resource (NASR)",
      license: String(localized: "U.S. government data"),
      address: "https://www.faa.gov/air_traffic/flight_info/aeronav/aero_data/NASR_Subscription/"
    ),
    source(
      "FAA Coded Instrument Flight Procedures (CIFP)",
      license: String(localized: "U.S. government data"),
      address: "https://www.faa.gov/air_traffic/flight_info/aeronav/digital_products/cifp/"
    ),
    source(
      "FAA Airmen Certification Database",
      license: String(localized: "U.S. government data"),
      address: "https://www.faa.gov/licenses_certificates/airmen_certification/"
    ),
    source("adsb.lol", license: "ODbL", address: "https://www.adsb.lol/"),
    source(
      "OpenSky Network",
      license: String(localized: "OpenSky terms of use"),
      address: "https://opensky-network.org/"
    ),
    source(
      "FlySto",
      license: String(localized: "Your FlySto account"),
      address: "https://www.flysto.net/"
    )
  ]

  private static func package(_ name: String, license: String, repository: String) -> Self {
    source(name, license: license, address: "https://github.com/\(repository)")
  }

  private static func source(_ name: String, license: String, address: String) -> Self {
    Self(name: name, license: license, url: URL(string: address)!)
  }
}
