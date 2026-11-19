import Foundation

/// A named place to surf: where it is and which way it faces.
///
/// The package never guesses a beach's orientation from its coordinate. Define each spot once,
/// with a bearing you have checked on a chart or map, and reuse it for queries and summaries.
public struct SurfSpot: Codable, Hashable, Sendable {
  public let name: String
  public let coordinate: Coordinate
  /// Bearing from the beach straight out to open water, perpendicular to the shoreline,
  /// in degrees clockwise from north. A beach that looks out to the south-west is about 225.
  /// Stored normalized to `0..<360`.
  public let oceanwardBearing: Double

  public init(name: String, coordinate: Coordinate, oceanwardBearing: Double) throws {
    guard let bearing = SurfMath.normalizedBearing(oceanwardBearing) else {
      throw ForecastValidationError.invalidBearing
    }
    self.name = name
    self.coordinate = coordinate
    self.oceanwardBearing = bearing
  }

  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      name: values.decode(String.self, forKey: .name),
      coordinate: values.decode(Coordinate.self, forKey: .coordinate),
      oceanwardBearing: values.decode(Double.self, forKey: .oceanwardBearing))
  }
}

extension ForecastQuery {
  /// A query for the spot's coordinate.
  public init(
    spot: SurfSpot, start: Date, end: Date,
    includesTides: Bool = true, datum: TideDatum = .meanSeaLevel
  ) throws {
    try self.init(
      coordinate: spot.coordinate, start: start, end: end,
      includesTides: includesTides, datum: datum)
  }
}

extension SurfSummary {
  /// A summary that uses the spot's oceanward bearing for wind orientation and swell exposure.
  /// The forecast should have been requested for this spot; the coordinate is not re-checked.
  public init?(forecast: SurfForecast, at time: Date, spot: SurfSpot) {
    self.init(forecast: forecast, at: time, oceanwardBearing: spot.oceanwardBearing)
  }
}
