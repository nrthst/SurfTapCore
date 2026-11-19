import Foundation
import SurfTapCore

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Stormglass v2 adapter. Credentials are supplied at runtime and never persisted here.
/// A successful forecast costs one request without tides, or three with tides.
/// There are no automatic retries: callers control quota, backoff and refresh policy.
public struct StormglassClient: ForecastProvider, CustomStringConvertible,
  CustomDebugStringConvertible, CustomReflectable
{
  private let apiKey: String
  private let source: String
  private let transport: any HTTPTransport

  public init(
    apiKey: String, source: String = "sg", transport: any HTTPTransport = URLSessionTransport()
  ) throws {
    let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    let placeholders = [
      "YOUR_KEY_HERE", "YOUR_API_KEY_HERE", "YOUR_STORMGLASS_API_KEY_HERE", "REPLACE_ME",
    ]
    guard !key.isEmpty, !placeholders.contains(key.uppercased()) else {
      throw StormglassError.missingAPIKey
    }
    guard key.unicodeScalars.allSatisfy({ (33...126).contains($0.value) }) else {
      throw StormglassError.invalidAPIKey
    }
    guard !source.isEmpty, source.utf8.count <= 32,
      source.unicodeScalars.allSatisfy({
        (97...122).contains($0.value) || (48...57).contains($0.value) || $0 == "_"
      })
    else {
      throw StormglassError.invalidSource
    }
    self.apiKey = key
    self.source = source
    self.transport = transport
  }

  public var description: String { "StormglassClient(source: \(source), credentials: redacted)" }
  public var debugDescription: String { description }
  public var customMirror: Mirror {
    Mirror(self, children: ["source": source, "credentials": "redacted"])
  }

  public func forecast(for query: ForecastQuery) async throws -> SurfForecast {
    try Task.checkCancellation()
    // Weather first prevents spending two more requests when credentials/quota are invalid.
    let weather: WeatherPayload = try await fetch(
      path: "weather/point", query: query,
      extra: [
        URLQueryItem(name: "source", value: source),
        URLQueryItem(
          name: "params",
          value: [
            "waveHeight", "wavePeriod", "waveDirection", "swellHeight", "swellPeriod",
            "swellDirection",
            "secondarySwellHeight", "secondarySwellPeriod", "secondarySwellDirection",
            "windSpeed", "windDirection", "gust", "waterTemperature",
          ].joined(separator: ",")),
      ])
    // A request beginning mid-hour can legitimately return that hour's sample.
    let firstHour = query.hourAlignedStart
    let hours = weather.hours.filter {
      $0.time >= firstHour && $0.time <= query.end
    }.map { $0.model(source: source) }
    guard hours.contains(where: \.hasMeasurements) else { throw StormglassError.emptyWeather }
    guard Set(hours.map(\.time)).count == hours.count else { throw StormglassError.invalidPayload }
    guard query.includesTides else {
      return SurfForecast(query: query, source: "stormglass:\(source)", hours: hours)
    }

    async let levels = optionalTides(
      TideLevelPayload.self, path: "tide/sea-level/point", query: query, component: .tideLevels)
    async let extremes = optionalTides(
      TideExtremePayload.self, path: "tide/extremes/point", query: query, component: .tideExtremes)
    let (levelResult, extremeResult) = try await (levels, extremes)
    try Task.checkCancellation()
    let levelModels = (levelResult.payload?.data ?? []).compactMap { point -> TideLevel? in
      guard let height = point.sg, height.isFinite,
        point.time >= firstHour, point.time <= query.end
      else { return nil }
      return TideLevel(time: point.time, heightMeters: height)
    }
    let extremeModels = (extremeResult.payload?.data ?? []).filter {
      $0.time >= firstHour && $0.time <= query.end
    }.map { TideExtreme(time: $0.time, kind: $0.type, heightMeters: $0.height) }
    var issues = [levelResult.issue, extremeResult.issue].compactMap { $0 }
    if levelResult.issue == nil && levelModels.isEmpty {
      issues.append(.init(component: .tideLevels, reason: .noData))
    }
    if extremeResult.issue == nil && extremeModels.isEmpty {
      issues.append(.init(component: .tideExtremes, reason: .noData))
    }
    return SurfForecast(
      query: query, source: "stormglass:\(source)", hours: hours,
      tideLevels: levelModels, tideExtremes: extremeModels,
      levelStation: levelResult.payload?.meta?.station?.model,
      extremeStation: extremeResult.payload?.meta?.station?.model, issues: issues
    )
  }

  private func optionalTides<T: TimedTidePayload>(
    _: T.Type, path: String, query: ForecastQuery,
    component: ForecastIssue.Component
  ) async throws
    -> (payload: TidePayload<T>?, issue: ForecastIssue?)
  {
    do {
      let payload: TidePayload<T> = try await fetch(
        path: path, query: query,
        extra: [URLQueryItem(name: "datum", value: query.datum.rawValue)])
      if let datum = payload.meta?.datum, datum != query.datum.rawValue {
        throw StormglassError.invalidPayload
      }
      guard Set(payload.data.map(\.time)).count == payload.data.count else {
        throw StormglassError.invalidPayload
      }
      return (payload, nil)
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      try Task.checkCancellation()
      let reason: ForecastIssue.Reason
      switch error as? StormglassError {
      case .authentication: reason = .authentication
      case .quotaExceeded: reason = .quotaExceeded
      case .rateLimited: reason = .rateLimited
      case .http: reason = .server
      case .invalidResponse, .invalidPayload: reason = .invalidResponse
      default: reason = .transport
      }
      return (nil, ForecastIssue(component: component, reason: reason))
    }
  }

  /// Fixed notation with six decimals, about 0.1 m. `String(Double)` would print a small
  /// value such as 0.00001 as "1e-05", which is not a decimal-degree coordinate.
  private static func decimalDegrees(_ value: Double) -> String {
    String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), value)
  }

  private func fetch<T: Decodable>(path: String, query: ForecastQuery, extra: [URLQueryItem])
    async throws -> T
  {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "api.stormglass.io"
    components.path = "/v2/\(path)"
    components.queryItems =
      [
        URLQueryItem(name: "lat", value: Self.decimalDegrees(query.coordinate.latitude)),
        URLQueryItem(name: "lng", value: Self.decimalDegrees(query.coordinate.longitude)),
        // UNIX seconds avoid local timezone/offset ambiguity; include the current forecast hour.
        URLQueryItem(
          name: "start", value: String(Int64(query.hourAlignedStart.timeIntervalSince1970))),
        URLQueryItem(name: "end", value: String(Int64(ceil(query.end.timeIntervalSince1970)))),
      ] + extra
    guard let url = components.url else { throw StormglassError.invalidResponse }
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue(apiKey, forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    let data: Data
    let response: HTTPURLResponse
    do {
      try Task.checkCancellation()
      (data, response) = try await transport.data(for: request)
      try Task.checkCancellation()
    } catch is CancellationError {
      throw CancellationError()
    } catch let error as URLError where error.code == .cancelled {
      throw CancellationError()
    } catch let error as StormglassError {
      throw error
    } catch {
      try Task.checkCancellation()
      throw StormglassError.transport(code: (error as? URLError)?.errorCode)
    }
    switch response.statusCode {
    case 200...299: break
    case 401, 403: throw StormglassError.authentication
    case 402: throw StormglassError.quotaExceeded
    case 429:
      let seconds = response.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
      throw StormglassError.rateLimited(
        retryAfterSeconds: seconds.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil })
    default: throw StormglassError.http(status: response.statusCode)
    }
    do { return try StormglassDecoding.decoder().decode(T.self, from: data) } catch {
      throw StormglassError.invalidPayload
    }
  }
}
