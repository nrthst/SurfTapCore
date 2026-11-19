import Foundation
import SurfTapCore
import Testing

@testable import SurfTapStormglass

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

private let fakeKey = "synthetic-test-credential"
private let weather =
  #"{"hours":[{"time":"2025-01-01T00:00:00+00:00","waveHeight":{"sg":1.2,"noaa":99},"waterTemperature":{"sg":null},"swellHeight":{"sg":1},"swellPeriod":{"sg":12}},{"time":"2025-01-01T01:00:00.000Z","waveHeight":{"sg":1.5}}]}"#
private let levels =
  #"{"data":[{"time":"2025-01-01T00:00:00Z","sg":-0.2},{"time":"2025-01-01T01:00:00Z","sg":0.4}],"meta":{"datum":"MSL","station":{"name":"Synthetic Station","source":"synthetic","distance":3}}}"#
private let extremes =
  #"{"data":[{"time":"2025-01-01T03:00:00Z","type":"high","height":0.9}],"meta":{"datum":"MSL"}}"#

private func makeQuery(tides: Bool = true) throws -> ForecastQuery {
  let start = Date(timeIntervalSince1970: 1_735_689_600)
  return try ForecastQuery(
    coordinate: Coordinate(latitude: 40, longitude: -73), start: start,
    end: start.addingTimeInterval(86400), includesTides: tides)
}

private actor MockTransport: HTTPTransport {
  enum Reply: Sendable {
    case response(Int, String, [String: String] = [:])
    case cancelled
    case offline
  }
  private let replies: [String: Reply]
  private(set) var requests: [URLRequest] = []
  init(
    weatherReply: Reply = .response(200, weather), levelReply: Reply = .response(200, levels),
    extremeReply: Reply = .response(200, extremes)
  ) {
    replies = [
      "/v2/weather/point": weatherReply, "/v2/tide/sea-level/point": levelReply,
      "/v2/tide/extremes/point": extremeReply,
    ]
  }
  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    requests.append(request)
    let url = try #require(request.url)
    switch try #require(replies[url.path]) {
    case .response(let status, let body, let headers):
      return (
        Data(body.utf8),
        try #require(
          HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers))
      )
    case .cancelled: throw URLError(.cancelled)
    case .offline: throw URLError(.notConnectedToInternet)
    }
  }
}

@Test func requestContractDecodingAndNoCredentialInURL() async throws {
  let transport = MockTransport()
  let client = try StormglassClient(apiKey: fakeKey, transport: transport)
  let query = try makeQuery()
  let result = try await client.forecast(for: query)
  #expect(result.hours.count == 2)
  #expect(result.hours.first?.waveHeightMeters == 1.2)
  #expect(result.hours.first?.waterTemperatureCelsius == nil)
  #expect(result.tideLevels.first?.heightMeters == -0.2)
  #expect(result.levelStation?.distanceKilometers == 3)
  #expect(result.levelStation?.provider == "synthetic")
  #expect(result.tideExtremes.first?.kind == .high)
  #expect(result.issues.isEmpty)
  let requests = await transport.requests
  #expect(requests.count == 3)
  #expect(requests.first?.url?.path == "/v2/weather/point")
  for request in requests {
    #expect(request.value(forHTTPHeaderField: "Authorization") == fakeKey)
    #expect(request.url?.host == "api.stormglass.io")
    #expect(request.url?.scheme == "https")
    #expect(request.url?.absoluteString.contains(fakeKey) == false)
    let url = try #require(request.url)
    let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
    let values = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    #expect(values["lat"] == "40.000000")
    #expect(values["lng"] == "-73.000000")
    #expect(values["start"] == "1735689600")
    #expect(values["end"] == "1735776000")
    if request.url?.path.contains("tide") == true {
      #expect(values["datum"] == "MSL")
    } else {
      #expect(values["source"] == "sg")
      #expect(values["params"]?.contains("waterTemperature") == true)
    }
  }
}

@Test func smallCoordinatesAreSentInFixedNotation() async throws {
  let transport = MockTransport()
  let start = Date(timeIntervalSince1970: 1_735_689_600)
  let query = try ForecastQuery(
    coordinate: Coordinate(latitude: 0.00001, longitude: -0.00002), start: start,
    end: start.addingTimeInterval(86400), includesTides: false)
  _ = try await StormglassClient(apiKey: fakeKey, transport: transport).forecast(for: query)
  let url = try #require(await transport.requests.first?.url)
  let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
  let values = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
  // String(0.00001) is "1e-05"; the service expects plain decimal degrees.
  #expect(values["lat"] == "0.000010")
  #expect(values["lng"] == "-0.000020")
}

@Test func keyWhitespaceIsTrimmedBeforeItReachesTheHeader() async throws {
  let transport = MockTransport()
  let padded = "  " + fakeKey + "\n"
  let client = try StormglassClient(apiKey: padded, transport: transport)
  _ = try await client.forecast(for: makeQuery(tides: false))
  let request = try #require(await transport.requests.first)
  #expect(request.value(forHTTPHeaderField: "Authorization") == fakeKey)
}

@Test(arguments: ["soon", "-5", "inf", "nan", ""])
func unusableRetryAfterValuesAreDropped(_ header: String) async throws {
  let transport = MockTransport(weatherReply: .response(429, "{}", ["Retry-After": header]))
  let client = try StormglassClient(apiKey: fakeKey, transport: transport)
  await #expect(throws: StormglassError.rateLimited(retryAfterSeconds: nil)) {
    try await client.forecast(for: makeQuery())
  }
}

@Test func tideSamplesOutsideTheWindowAreDropped() async throws {
  let outside =
    #"{"data":[{"time":"2024-12-31T22:00:00Z","type":"low","height":0.1},{"time":"2025-01-01T03:00:00Z","type":"high","height":0.9},{"time":"2025-01-03T00:00:00Z","type":"low","height":0.2}],"meta":{"datum":"MSL"}}"#
  let kept = try await StormglassClient(
    apiKey: fakeKey, transport: MockTransport(extremeReply: .response(200, outside))
  ).forecast(for: makeQuery())
  #expect(kept.tideExtremes.map(\.kind) == [.high])
  #expect(kept.issues.isEmpty)

  // When nothing falls inside the window, that is reported instead of passing silently.
  let allOutside =
    #"{"data":[{"time":"2024-12-31T22:00:00Z","type":"low","height":0.1}],"meta":{"datum":"MSL"}}"#
  let none = try await StormglassClient(
    apiKey: fakeKey, transport: MockTransport(extremeReply: .response(200, allOutside))
  ).forecast(for: makeQuery())
  #expect(none.tideExtremes.isEmpty)
  #expect(none.issues == [.init(component: .tideExtremes, reason: .noData)])
}

@Test func credentialsAreValidatedAndRedacted() throws {
  #expect(throws: StormglassError.missingAPIKey) { try StormglassClient(apiKey: " ") }
  #expect(throws: StormglassError.missingAPIKey) { try StormglassClient(apiKey: "YOUR_KEY_HERE") }
  #expect(throws: StormglassError.missingAPIKey) {
    try StormglassClient(apiKey: "YOUR_STORMGLASS_API_KEY_HERE")
  }
  #expect(throws: StormglassError.invalidAPIKey) {
    let malformedKey = ["synthetic-test", "Header:value"].joined(separator: "\r\n")
    _ = try StormglassClient(apiKey: malformedKey)
  }
  #expect(throws: StormglassError.invalidSource) {
    try StormglassClient(apiKey: fakeKey, source: "sg,noaa")
  }
  let client = try StormglassClient(apiKey: fakeKey)
  var output = ""
  dump(client, to: &output)
  #expect(!output.contains(fakeKey))
  #expect(!String(reflecting: client).contains(fakeKey))
}

@Test(arguments: [401, 403, 402, 429, 500, 302])
func httpFailuresDoNotRetryOrSpendTideRequests(_ status: Int) async throws {
  let transport = MockTransport(
    weatherReply: .response(status, "secret echo: \(fakeKey)", ["Retry-After": "60"]))
  let client = try StormglassClient(apiKey: fakeKey, transport: transport)
  let expected: StormglassError
  switch status {
  case 401, 403: expected = .authentication
  case 402: expected = .quotaExceeded
  case 429: expected = .rateLimited(retryAfterSeconds: 60)
  default: expected = .http(status: status)
  }
  await #expect(throws: expected) { try await client.forecast(for: makeQuery()) }
  #expect(await transport.requests.count == 1)
  #expect(!expected.localizedDescription.contains(fakeKey))
}

@Test func optionalTideFailureIsVisibleAndWeatherStillSucceeds() async throws {
  let transport = MockTransport(levelReply: .response(500, "{}"))
  let result = try await StormglassClient(apiKey: fakeKey, transport: transport).forecast(
    for: makeQuery())
  #expect(result.hours.count == 2)
  #expect(result.tideLevels.isEmpty)
  #expect(result.tideExtremes.count == 1)
  #expect(result.issues == [ForecastIssue(component: .tideLevels, reason: .server)])
}

@Test func tideCancellationIsNotHiddenAsPartialSuccess() async throws {
  let transport = MockTransport(levelReply: .cancelled)
  let client = try StormglassClient(apiKey: fakeKey, transport: transport)
  await #expect(throws: CancellationError.self) { try await client.forecast(for: makeQuery()) }
}

@Test func weatherOnlyMakesOneRequestAndDoesNotInventMissingSource() async throws {
  let transport = MockTransport()
  let client = try StormglassClient(apiKey: fakeKey, source: "noaa", transport: transport)
  let forecast = try await client.forecast(for: makeQuery(tides: false))
  #expect(forecast.hours.first?.waveHeightMeters == 99)
  #expect(forecast.hours.last?.waveHeightMeters == nil)
  #expect(forecast.tideLevels.isEmpty)
  #expect(forecast.issues.isEmpty)
  #expect(await transport.requests.count == 1)
}

@Test(arguments: [
  #"{"hours":[]}"#, #"{"hours":[{"time":"2025-01-01T00:00:00Z","waveHeight":{"noaa":99}}]}"#,
  #"{"hours":[{"time":"2020-01-01T00:00:00Z","waveHeight":{"sg":1}}]}"#,
])
func emptyOrUnusableWeatherFails(_ body: String) async throws {
  let transport = MockTransport(weatherReply: .response(200, body))
  let client = try StormglassClient(apiKey: fakeKey, transport: transport)
  await #expect(throws: StormglassError.emptyWeather) {
    try await client.forecast(for: makeQuery())
  }
  #expect(await transport.requests.count == 1)
}

@Test(arguments: ["<html>error</html>", #"{"hours":[{"time":"bad","waveHeight":{"sg":1}}]}"#])
func malformedPayloadsFailWithoutLeakingContents(_ body: String) async throws {
  let transport = MockTransport(weatherReply: .response(200, body))
  let client = try StormglassClient(apiKey: fakeKey, transport: transport)
  await #expect(throws: StormglassError.invalidPayload) {
    try await client.forecast(for: makeQuery())
  }
}

@Test func mismatchedDatumAndEmptyTidesAreExplicit() async throws {
  let transport = MockTransport(
    levelReply: .response(200, levels.replacingOccurrences(of: "MSL", with: "MLLW")),
    extremeReply: .response(200, #"{"data":[]}"#))
  let result = try await StormglassClient(apiKey: fakeKey, transport: transport).forecast(
    for: makeQuery())
  #expect(result.tideLevels.isEmpty)
  #expect(result.issues.contains(.init(component: .tideLevels, reason: .invalidResponse)))
  #expect(result.issues.contains(.init(component: .tideExtremes, reason: .noData)))
}

@Test func transportErrorsAreSanitized() async throws {
  let client = try StormglassClient(
    apiKey: fakeKey, transport: MockTransport(weatherReply: .offline))
  await #expect(throws: StormglassError.transport(code: URLError.notConnectedToInternet.rawValue)) {
    try await client.forecast(for: makeQuery())
  }
}

@Test func offsetDatesAndMidHourRequestsKeepTheCurrentSample() async throws {
  let transport = MockTransport(
    weatherReply: .response(
      200,
      weather.replacingOccurrences(
        of: "2025-01-01T00:00:00+00:00", with: "2024-12-31T19:00:00-05:00")))
  let original = try makeQuery(tides: false)
  let query = try ForecastQuery(
    coordinate: original.coordinate,
    start: original.start.addingTimeInterval(1800), end: original.end, includesTides: false)
  let forecast = try await StormglassClient(apiKey: fakeKey, transport: transport).forecast(
    for: query)
  #expect(forecast.hours.first?.time == original.start)
  #expect(SurfSummary(forecast: forecast, at: query.start) != nil)
  let request = try #require(await transport.requests.first)
  #expect(request.url?.absoluteString.contains("start=1735689600") == true)
}

@Test func swellDirectionsFromTheServiceDriveTheSpotEstimate() async throws {
  let body =
    #"{"hours":[{"time":"2025-01-01T00:00:00Z","swellHeight":{"sg":1},"swellPeriod":{"sg":12},"swellDirection":{"sg":200},"secondarySwellHeight":{"sg":1.5},"secondarySwellPeriod":{"sg":8},"secondarySwellDirection":{"sg":-75},"windDirection":{"sg":390}}]}"#
  let spot = try SurfSpot(
    name: "Synthetic Beach", coordinate: Coordinate(latitude: 40, longitude: -73),
    oceanwardBearing: 210)
  let start = Date(timeIntervalSince1970: 1_735_689_600)
  let query = try ForecastQuery(
    spot: spot, start: start, end: start.addingTimeInterval(86400), includesTides: false)
  let transport = MockTransport(weatherReply: .response(200, body))
  let forecast = try await StormglassClient(apiKey: fakeKey, transport: transport).forecast(
    for: query)
  // Bearings outside 0..<360 are normalized on the way in.
  #expect(forecast.hours.first?.secondarySwell.directionDegrees == 285)
  #expect(forecast.hours.first?.windDirectionDegrees == 30)
  let params = try #require(await transport.requests.first?.url?.query)
  #expect(params.contains("swellDirection"))
  #expect(params.contains("secondarySwellDirection"))

  let summary = try #require(SurfSummary(forecast: forecast, at: start, spot: spot))
  let breaker = try #require(summary.breakingWave)
  #expect(breaker.swell.periodSeconds == 12)
  #expect(breaker.incidenceDegrees == 10)
  #expect(summary.dominantSwell?.periodSeconds == 8)
  #expect(summary.windOrientation == .offshore)
}

@Test func timestampFormatsDecodeToTheSameInstantOrFail() throws {
  let decoder = StormglassDecoding.decoder()
  func decode(_ value: String) throws -> Date {
    try decoder.decode([Date].self, from: Data(#"["\#(value)"]"#.utf8))[0]
  }
  let expected = Date(timeIntervalSince1970: 1_735_689_600)
  for value in [
    "2025-01-01T00:00:00Z", "2025-01-01T00:00:00+00:00", "2025-01-01T00:00:00.000Z",
    "2024-12-31T19:00:00-05:00", "2025-01-01T05:30:00.000+05:30",
  ] {
    #expect(try decode(value) == expected)
  }
  for value in ["bad", "2025-01-01", "2025-01-01T00:00:00", "2025-01-01 00:00:00Z", ""] {
    #expect(throws: DecodingError.self) { try decode(value) }
  }
}

@Test func meanLowerLowWaterIsSentToBothTideEndpoints() async throws {
  let transport = MockTransport(
    levelReply: .response(200, levels.replacingOccurrences(of: "MSL", with: "MLLW")),
    extremeReply: .response(200, extremes.replacingOccurrences(of: "MSL", with: "MLLW")))
  let original = try makeQuery()
  let query = try ForecastQuery(
    coordinate: original.coordinate, start: original.start,
    end: original.end, datum: .meanLowerLowWater)
  let forecast = try await StormglassClient(apiKey: fakeKey, transport: transport).forecast(
    for: query)
  #expect(forecast.issues.isEmpty)
  let tideRequests = await transport.requests.filter { $0.url?.path.contains("tide") == true }
  #expect(tideRequests.count == 2)
  #expect(tideRequests.allSatisfy { $0.url?.absoluteString.contains("datum=MLLW") == true })
}

@Test func duplicateTimestampsAreRejectedInsteadOfChoosingArbitraryValues() async throws {
  let duplicateWeather = weather.replacingOccurrences(
    of: "2025-01-01T01:00:00.000Z", with: "2025-01-01T00:00:00Z")
  let client = try StormglassClient(
    apiKey: fakeKey, transport: MockTransport(weatherReply: .response(200, duplicateWeather)))
  await #expect(throws: StormglassError.invalidPayload) {
    try await client.forecast(for: makeQuery())
  }
  let duplicateLevels = levels.replacingOccurrences(
    of: "2025-01-01T01:00:00Z", with: "2025-01-01T00:00:00Z")
  let tideClient = try StormglassClient(
    apiKey: fakeKey, transport: MockTransport(levelReply: .response(200, duplicateLevels)))
  let forecast = try await tideClient.forecast(for: makeQuery())
  #expect(forecast.tideLevels.isEmpty)
  #expect(forecast.issues == [.init(component: .tideLevels, reason: .invalidResponse)])
}

@Test func defaultRedirectDelegateRejectsTheNewDestination() async throws {
  let delegate = RejectRedirects()
  let session = URLSession(configuration: .ephemeral)
  defer { session.invalidateAndCancel() }
  let url = try #require(URL(string: "https://example.invalid/redirect"))
  let task = session.dataTask(with: url)  // Never resumed: this test cannot make a request.
  let response = try #require(
    HTTPURLResponse(url: url, statusCode: 302, httpVersion: nil, headerFields: nil))
  let rejected = await withCheckedContinuation { continuation in
    delegate.urlSession(
      session, task: task, willPerformHTTPRedirection: response,
      newRequest: URLRequest(url: url)
    ) { request in
      continuation.resume(returning: request == nil)
    }
  }
  #expect(rejected)
}
