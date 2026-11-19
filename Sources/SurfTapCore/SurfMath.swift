import Foundation

public enum WindOrientation: String, Codable, Sendable { case onshore, offshore, crossShore }
public enum TideTrend: String, Codable, Sendable { case rising, falling, steady }

public enum SurfMath {
  public static func metersToFeet(_ meters: Double) -> Double { meters / 0.3048 }
  public static func metersPerSecondToMPH(_ speed: Double) -> Double { speed / 0.44704 }
  public static func celsiusToFahrenheit(_ celsius: Double) -> Double { celsius * 1.8 + 32 }

  public static func normalizedBearing(_ degrees: Double) -> Double? {
    guard degrees.isFinite else { return nil }
    let value = degrees.truncatingRemainder(dividingBy: 360)
    let wrapped = value < 0 ? value + 360 : value
    // A tiny negative input rounds up to exactly 360; keep the result inside 0..<360.
    return wrapped >= 360 ? 0 : wrapped
  }

  public static func cardinalDirection(_ degrees: Double) -> String? {
    guard let degrees = normalizedBearing(degrees) else { return nil }
    let directions = [
      "N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
      "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW",
    ]
    return directions[Int((degrees + 11.25) / 22.5) % 16]
  }

  /// Opposing bearings have no meaningful mean and return nil.
  public static func circularMean(_ bearings: [Double]) -> Double? {
    guard !bearings.isEmpty, bearings.allSatisfy(\.isFinite) else { return nil }
    let radians = bearings.compactMap(normalizedBearing).map { $0 * .pi / 180 }
    let x = radians.reduce(0) { $0 + cos($1) } / Double(radians.count)
    let y = radians.reduce(0) { $0 + sin($1) } / Double(radians.count)
    guard hypot(x, y) > 1e-10 else { return nil }
    let result = normalizedBearing(atan2(y, x) * 180 / .pi)
    return result.map { abs($0 - 360) < 1e-10 ? 0 : $0 }
  }

  /// Requires the actual beach's oceanward bearing. No regional/geographic guesses.
  public static func windOrientation(
    from windBearing: Double,
    oceanwardBearing: Double
  ) -> WindOrientation? {
    guard let angle = incidenceAngle(from: windBearing, oceanwardBearing: oceanwardBearing)
    else { return nil }
    if angle <= 75 { return .onshore }
    if angle >= 105 { return .offshore }
    return .crossShore
  }

  /// Selects one intact swell component; never combines one train's height with another's period.
  public static func dominantSwell(primary: Swell, secondary: Swell) -> Swell? {
    switch (primary.relativeEnergy, secondary.relativeEnergy) {
    case (let a?, let b?): return b > a ? secondary : primary
    case (_?, nil): return primary
    case (nil, _?): return secondary
    case (nil, nil): return nil
    }
  }

  /// Interpolates only inside coverage, across gaps of at most two hours by default.
  public static func tideHeight(
    at time: Date, levels: [TideLevel],
    maximumGap: TimeInterval = 7200
  ) -> Double? {
    guard maximumGap.isFinite, maximumGap > 0, time.timeIntervalSince1970.isFinite else {
      return nil
    }
    let points = validTideLevels(levels)
    if let exact = points.first(where: { $0.time == time }) { return exact.heightMeters }
    guard let before = points.last(where: { $0.time < time }),
      let after = points.first(where: { $0.time > time })
    else { return nil }
    let span = after.time.timeIntervalSince(before.time)
    guard span > 0, span <= maximumGap else { return nil }
    let fraction = time.timeIntervalSince(before.time) / span
    // Weighted terms avoid overflowing the difference between large opposite-signed values.
    let height = before.heightMeters * (1 - fraction) + after.heightMeters * fraction
    return height.isFinite ? height : nil
  }

  /// Change in predicted water level, not a prediction of slack water or current speed.
  /// Uses the same gap limit as `tideHeight`, two hours by default.
  public static func tideTrend(
    at time: Date, levels: [TideLevel],
    maximumGap: TimeInterval = 7200
  ) -> TideTrend? {
    guard maximumGap.isFinite, maximumGap > 0, time.timeIntervalSince1970.isFinite else {
      return nil
    }
    let points = validTideLevels(levels)
    guard let before = points.last(where: { $0.time <= time }),
      let after = points.first(where: { $0.time > time })
    else { return nil }
    let span = after.time.timeIntervalSince(before.time)
    guard span > 0, span <= maximumGap else { return nil }
    let metersPerHour = (after.heightMeters - before.heightMeters) * 3600 / span
    guard metersPerHour.isFinite else { return nil }
    if abs(metersPerHour) < 0.02 { return .steady }
    return metersPerHour > 0 ? .rising : .falling
  }

  private static func validTideLevels(_ levels: [TideLevel]) -> [TideLevel] {
    var byTime: [Date: Double] = [:]
    for point in levels
    where point.heightMeters.isFinite && point.time.timeIntervalSince1970.isFinite {
      if let existing = byTime[point.time], existing != point.heightMeters {
        // Conflicting samples have no reliable interpolation; never choose by array order.
        return []
      }
      byTime[point.time] = point.heightMeters
    }
    return byTime.map { TideLevel(time: $0.key, heightMeters: $0.value) }.sorted {
      $0.time < $1.time
    }
  }
}
