import Foundation
import SurfTapCore

typealias SourceValues = [String: Double?]

struct WeatherPayload: Decodable, Sendable { let hours: [WeatherHourPayload] }

struct WeatherHourPayload: Decodable, Sendable {
  let time: Date
  let waveHeight: SourceValues?
  let wavePeriod: SourceValues?
  let waveDirection: SourceValues?
  let swellHeight: SourceValues?
  let swellPeriod: SourceValues?
  let swellDirection: SourceValues?
  let secondarySwellHeight: SourceValues?
  let secondarySwellPeriod: SourceValues?
  let secondarySwellDirection: SourceValues?
  let windSpeed: SourceValues?
  let windDirection: SourceValues?
  let gust: SourceValues?
  let waterTemperature: SourceValues?

  func model(source: String) -> ForecastHour {
    func value(_ values: SourceValues?, nonnegative: Bool = false) -> Double? {
      guard let value = values?[source] ?? nil, value.isFinite,
        !nonnegative || value >= 0
      else { return nil }
      return value
    }
    func direction(_ values: SourceValues?) -> Double? {
      value(values).flatMap(SurfMath.normalizedBearing)
    }
    return ForecastHour(
      time: time, waveHeightMeters: value(waveHeight, nonnegative: true),
      wavePeriodSeconds: value(wavePeriod, nonnegative: true),
      waveDirectionDegrees: direction(waveDirection),
      primarySwell: Swell(
        heightMeters: value(swellHeight, nonnegative: true),
        periodSeconds: value(swellPeriod, nonnegative: true),
        directionDegrees: direction(swellDirection)),
      secondarySwell: Swell(
        heightMeters: value(secondarySwellHeight, nonnegative: true),
        periodSeconds: value(secondarySwellPeriod, nonnegative: true),
        directionDegrees: direction(secondarySwellDirection)),
      windSpeedMetersPerSecond: value(windSpeed, nonnegative: true),
      windDirectionDegrees: direction(windDirection),
      windGustMetersPerSecond: value(gust, nonnegative: true),
      waterTemperatureCelsius: value(waterTemperature)
    )
  }
}

struct TidePayload<Value: Decodable & Sendable>: Decodable, Sendable {
  let data: [Value]
  let meta: TideMetaPayload?
}

struct TideMetaPayload: Decodable, Sendable {
  let datum: String?
  let station: StationPayload?
}

struct StationPayload: Decodable, Sendable {
  let name: String?
  let source: String?
  let provider: String?
  let distance: Double?
  var model: TideStation {
    TideStation(name: name, provider: provider ?? source, distanceKilometers: distance)
  }
}

protocol TimedTidePayload: Decodable, Sendable { var time: Date { get } }
struct TideLevelPayload: TimedTidePayload {
  let time: Date
  let sg: Double?
}
struct TideExtremePayload: TimedTidePayload {
  let time: Date
  let type: TideExtreme.Kind
  let height: Double?
}

enum StormglassDecoding {
  static func decoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let container = try decoder.singleValueContainer()
      let value = try container.decode(String.self)
      // Value-type parsers: no shared mutable state under concurrent requests, and far
      // cheaper than allocating an ISO8601DateFormatter for every timestamp.
      if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(value) {
        return date
      }
      if let date = try? Date.ISO8601FormatStyle().parse(value) { return date }
      throw DecodingError.dataCorruptedError(
        in: container, debugDescription: "Invalid ISO 8601 timestamp")
    }
    return decoder
  }
}
