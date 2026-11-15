import Foundation

/// The titles LogTen shows for its built-in flight attributes, which findings use instead of the
/// stored attribute names.
enum FieldTitle {
  private static let titles: [String: String.LocalizationValue] = [
    "totaltime": "Total Time", "night": "Night", "pic": "PIC", "sic": "SIC",
    "picnight": "PIC Night", "sicnight": "SIC Night", "p1us": "P1 u/s",
    "p1usnight": "P1 u/s Night", "solo": "Solo", "dualreceived": "Dual Received",
    "dualreceivednight": "Dual Received Night", "dualgiven": "Dual Given",
    "crosscountry": "Cross-Country", "crosscountrynight": "Cross-Country Night",
    "actualinstrument": "Actual Instrument", "simulatedinstrument": "Simulated Instrument",
    "simulator": "Simulator", "ground": "Ground", "nightvisiongoggle": "Night Vision Goggle",
    "fullstops": "Full Stops", "totallandings": "Total Landings",
    "daylandings": "Day Landings", "nightlandings": "Night Landings",
    "totaltakeoffs": "Total Takeoffs", "daytakeoffs": "Day Takeoffs",
    "nighttakeoffs": "Night Takeoffs", "holds": "Holds", "distance": "Distance",
    "hobbsstart": "Hobbs Out", "hobbsstop": "Hobbs In", "tachstart": "Tach Out",
    "tachstop": "Tach In", "actualdeparturetime": "Out", "takeofftime": "Off",
    "landingtime": "On", "actualarrivaltime": "In"
  ]

  /// The title of a built-in attribute by its lowercased name, or `nil` if there is none.
  static func title(ofAttribute name: String) -> String? {
    titles[name].map { String(localized: $0, bundle: .module) }
  }
}
