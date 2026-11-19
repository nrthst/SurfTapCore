import Foundation

public enum ForecastValidationError: Error, Equatable, Sendable, LocalizedError {
  case invalidCoordinate
  case invalidTimeRange
  case invalidBearing

  public var errorDescription: String? {
    switch self {
    case .invalidCoordinate:
      "Latitude must be between -90 and 90, and longitude between -180 and 180."
    case .invalidTimeRange:
      "The end must be after the start, and the window can cover at most ten days."
    case .invalidBearing:
      "The oceanward bearing must be a finite number of degrees."
    }
  }
}

/// A geographic coordinate in decimal degrees. Validation also applies when decoding.
public struct Coordinate: Codable, Hashable, Sendable {
  public let latitude: Double
  public let longitude: Double

  public init(latitude: Double, longitude: Double) throws {
    guard latitude.isFinite, longitude.isFinite,
      (-90...90).contains(latitude), (-180...180).contains(longitude)
    else {
      throw ForecastValidationError.invalidCoordinate
    }
    self.latitude = latitude
    self.longitude = longitude
  }

  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      latitude: values.decode(Double.self, forKey: .latitude),
      longitude: values.decode(Double.self, forKey: .longitude))
  }
}

/// Reference level for tide heights; neither value represents water depth.
public enum TideDatum: String, Codable, Sendable {
  case meanSeaLevel = "MSL"
  case meanLowerLowWater = "MLLW"
}

/// Explicit time window, shared by all endpoints. The ten-day cap includes hour rounding.
public struct ForecastQuery: Codable, Hashable, Sendable {
  public let coordinate: Coordinate
  public let start: Date
  public let end: Date
  public let includesTides: Bool
  public let datum: TideDatum

  public init(
    coordinate: Coordinate, start: Date, end: Date,
    includesTides: Bool = true, datum: TideDatum = .meanSeaLevel
  ) throws {
    let duration = end.timeIntervalSince(start)
    let requestDuration =
      ceil(end.timeIntervalSince1970) - Self.hourAligned(start).timeIntervalSince1970
    guard start.timeIntervalSince1970.isFinite, end.timeIntervalSince1970.isFinite,
      start >= .distantPast, end <= .distantFuture,
      duration > 0, requestDuration <= 10 * 24 * 3600
    else {
      throw ForecastValidationError.invalidTimeRange
    }
    self.coordinate = coordinate
    self.start = start
    self.end = end
    self.includesTides = includesTides
    self.datum = datum
  }

  /// The start rounded down to the top of its hour. Hourly samples at or after this instant,
  /// up to `end`, belong to the window, so a mid-hour start still includes the current hour.
  public var hourAlignedStart: Date { Self.hourAligned(start) }

  private static func hourAligned(_ date: Date) -> Date {
    Date(timeIntervalSince1970: floor(date.timeIntervalSince1970 / 3600) * 3600)
  }

  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      coordinate: values.decode(Coordinate.self, forKey: .coordinate),
      start: values.decode(Date.self, forKey: .start),
      end: values.decode(Date.self, forKey: .end),
      includesTides: values.decode(Bool.self, forKey: .includesTides),
      datum: values.decode(TideDatum.self, forKey: .datum)
    )
  }
}

/// Implement this protocol to supply forecasts from another service or local fixtures.
public protocol ForecastProvider: Sendable {
  func forecast(for query: ForecastQuery) async throws -> SurfForecast
}
