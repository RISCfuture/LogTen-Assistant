import FlightSources
import Foundation
import References

nonisolated extension SessionServices {
  private static let stubsArgument = "UITestStubs"
  private static let flyStoStubName = "flysto"

  /// The services for this launch: stubs when a debug build is launched with
  /// `-UITestStubs flysto`, otherwise the live services.
  static var current: Self {
    #if DEBUG
      if UserDefaults.standard.string(forKey: stubsArgument) == flyStoStubName { return stubbed }
    #endif
    return live
  }

  #if DEBUG
    /// Services that answer FlySto syncs with the sample logbook's flight and keep downloads in
    /// a temporary folder, so UI tests never reach the network.
    private static var stubbed: Self {
      let folder = FileManager.default.temporaryDirectory.appending(
        path: "LogTenAssistantUITests-\(UUID().uuidString)",
        directoryHint: .isDirectory
      )
      return Self(
        flySto: { FlyStoClient(token: { "ui-test" }, transport: SampleFlySto()) },
        hasFlyStoToken: { true },
        adsb: ADSBLolClient(transport: SampleFlySto()),
        adsbCache: ADSBTraceCache(directory: folder.appending(path: "ADS-B")),
        nasr: NASRCycleStore(directory: folder.appending(path: "NASR")),
        cifp: CIFPStore(directory: folder.appending(path: "CIFP"))
      )
    }
  #endif
}

#if DEBUG
  /**
   A FlySto API for UI tests. Every log list holds one log of the sample logbook's Monterey
   flight, with brakes on ten minutes after the time the logbook records; every other request
   fails.
   */
  nonisolated struct SampleFlySto: HTTPTransport {
    private static let logsPath = "/public-api/logs"
    private static let page = #"""
      {
        "logs": [{
          "id": "sample-log-002",
          "url": "https://www.flysto.net/logs/sample-log-002",
          "date": "1 Mar 2026",
          "aircraft": "N4321K",
          "from": "KPAO",
          "to": "KMRY",
          "parameters": [
            { "name": "Brakes off", "value": "2026-03-01T19:00:00Z" },
            { "name": "Takeoff time", "value": "2026-03-01T19:10:00Z" },
            { "name": "Landing time", "value": "2026-03-01T20:25:00Z" },
            { "name": "Brakes on", "value": "2026-03-01T20:40:00Z" }
          ]
        }],
        "timestamp": "1772400000"
      }
      """#

    func data(for request: URLRequest) throws -> (Data, HTTPURLResponse) {
      guard let url = request.url, url.path() == Self.logsPath,
        let response = HTTPURLResponse(
          url: url,
          statusCode: 200,
          httpVersion: nil,
          headerFields: nil
        )
      else { throw URLError(.cannotConnectToHost) }
      return (Data(Self.page.utf8), response)
    }

    func stream(for _: URLRequest) throws -> (
      AsyncThrowingStream<Data, any Error>, HTTPURLResponse
    ) {
      throw URLError(.cannotConnectToHost)
    }
  }
#endif
