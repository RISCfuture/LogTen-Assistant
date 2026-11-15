import Foundation

nonisolated extension URL {
  /// This URL if it is an `https` or `http` web address with a host, so that data cannot make
  /// the app open a `file:` or custom-scheme link.
  var webLink: URL? {
    guard let scheme = scheme?.lowercased(), ["https", "http"].contains(scheme), host() != nil
    else { return nil }
    return self
  }

  /// This URL if it is an `https` address on `flysto.net` or one of its subdomains.
  var flyStoLink: URL? {
    guard scheme?.lowercased() == "https", let host = host()?.lowercased(),
      host == "flysto.net" || host.hasSuffix(".flysto.net")
    else { return nil }
    return self
  }
}
