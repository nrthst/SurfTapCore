import Foundation

/// Metric values use meters, seconds, meters/second and Celsius throughout the core.
/// Bearings are degrees clockwise from north, indicating where waves/wind come FROM.
public struct Swell: Codable, Equatable, Sendable {
  public let heightMeters: Double?
  public let periodSeconds: Double?
  public let directionDegrees: Double?

  public init(
    heightMeters: Double? = nil, periodSeconds: Double? = nil,
    directionDegrees: Double? = nil
  ) {
    self.heightMeters = heightMeters
    self.periodSeconds = periodSeconds
    self.directionDegrees = directionDegrees
  }

  /// H²T is a relative selection heuristic, not a measurement of breaking wave energy.
  public var relativeEnergy: Double? {
    guard let heightMeters, let periodSeconds, heightMeters.isFinite,
      periodSeconds.isFinite, heightMeters > 0, periodSeconds > 0
    else { return nil }
    let value = heightMeters * heightMeters * periodSeconds
    return value.isFinite ? value : nil
  }
}

public struct ForecastHour: Codable, Equatable, Sendable {
  public let time: Date
  public let waveHeightMeters: Double?
  public let wavePeriodSeconds: Double?
  public let waveDirectionDegrees: Double?
  public let primarySwell: Swell
  public let secondarySwell: Swell
  public let windSpeedMetersPerSecond: Double?
  public let windDirectionDegrees: Double?
  public let windGustMetersPerSecond: Double?
  public let waterTemperatureCelsius: Double?

  public init(
    time: Date, waveHeightMeters: Double? = nil, wavePeriodSeconds: Double? = nil,
    waveDirectionDegrees: Double? = nil, primarySwell: Swell = Swell(),
    secondarySwell: Swell = Swell(), windSpeedMetersPerSecond: Double? = nil,
    windDirectionDegrees: Double? = nil, windGustMetersPerSecond: Double? = nil,
    waterTemperatureCelsius: Double? = nil
  ) {
    self.time = time
    self.waveHeightMeters = waveHeightMeters
    self.wavePeriodSeconds = wavePeriodSeconds
    self.waveDirectionDegrees = waveDirectionDegrees
    self.primarySwell = primarySwell
    self.secondarySwell = secondarySwell
    self.windSpeedMetersPerSecond = windSpeedMetersPerSecond
    self.windDirectionDegrees = windDirectionDegrees
    self.windGustMetersPerSecond = windGustMetersPerSecond
    self.waterTemperatureCelsius = waterTemperatureCelsius
  }

  public var hasMeasurements: Bool {
    [
      waveHeightMeters, wavePeriodSeconds, waveDirectionDegrees,
      primarySwell.heightMeters, primarySwell.periodSeconds, primarySwell.directionDegrees,
      secondarySwell.heightMeters, secondarySwell.periodSeconds, secondarySwell.directionDegrees,
      windSpeedMetersPerSecond, windDirectionDegrees, windGustMetersPerSecond,
      waterTemperatureCelsius,
    ].contains { $0?.isFinite == true }
  }
}

public struct TideLevel: Codable, Equatable, Sendable {
  public let time: Date
  public let heightMeters: Double
  public init(time: Date, heightMeters: Double) {
    self.time = time
    self.heightMeters = heightMeters
  }
}

public struct TideExtreme: Codable, Equatable, Sendable {
  public enum Kind: String, Codable, Sendable { case high, low }
  public let time: Date
  public let kind: Kind
  public let heightMeters: Double?
  public init(time: Date, kind: Kind, heightMeters: Double? = nil) {
    self.time = time
    self.kind = kind
    self.heightMeters = heightMeters
  }
}

public struct TideStation: Codable, Equatable, Sendable {
  public let name: String?
  public let provider: String?
  public let distanceKilometers: Double?
  public init(name: String? = nil, provider: String? = nil, distanceKilometers: Double? = nil) {
    self.name = name
    self.provider = provider
    self.distanceKilometers = distanceKilometers
  }
}

/// A missing optional endpoint is visible to callers rather than silently discarded.
public struct ForecastIssue: Codable, Equatable, Sendable {
  public enum Component: String, Codable, Sendable { case tideLevels, tideExtremes }
  public enum Reason: String, Codable, Sendable {
    case noData, authentication, quotaExceeded, rateLimited, server, invalidResponse, transport
  }
  public let component: Component
  public let reason: Reason
  public init(component: Component, reason: Reason) {
    self.component = component
    self.reason = reason
  }
}

public struct SurfForecast: Codable, Equatable, Sendable {
  public let query: ForecastQuery
  public let source: String
  public let hours: [ForecastHour]
  public let tideLevels: [TideLevel]
  public let tideExtremes: [TideExtreme]
  /// Each endpoint can select a different station. Preserve both independently.
  public let levelStation: TideStation?
  public let extremeStation: TideStation?
  public let issues: [ForecastIssue]

  public init(
    query: ForecastQuery, source: String, hours: [ForecastHour],
    tideLevels: [TideLevel] = [], tideExtremes: [TideExtreme] = [],
    levelStation: TideStation? = nil, extremeStation: TideStation? = nil,
    issues: [ForecastIssue] = []
  ) {
    self.query = query
    self.source = source
    self.hours = hours.sorted { $0.time < $1.time }
    self.tideLevels = tideLevels.sorted { $0.time < $1.time }
    self.tideExtremes = tideExtremes.sorted { $0.time < $1.time }
    self.levelStation = levelStation
    self.extremeStation = extremeStation
    self.issues = issues
  }

  /// Decoding goes through the main initializer so decoded samples are sorted by time too.
  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      query: values.decode(ForecastQuery.self, forKey: .query),
      source: values.decode(String.self, forKey: .source),
      hours: values.decode([ForecastHour].self, forKey: .hours),
      tideLevels: values.decode([TideLevel].self, forKey: .tideLevels),
      tideExtremes: values.decode([TideExtreme].self, forKey: .tideExtremes),
      levelStation: values.decodeIfPresent(TideStation.self, forKey: .levelStation),
      extremeStation: values.decodeIfPresent(TideStation.self, forKey: .extremeStation),
      issues: values.decode([ForecastIssue].self, forKey: .issues)
    )
  }
}
