import Foundation

/// An estimated breaker height for one swell component.
///
/// This is the output of a simplified textbook formula, not an observation. It ignores the
/// sea floor, tide, wind, currents, sheltering by headlands and the shape of the break.
public struct BreakingWaveEstimate: Equatable, Sendable {
  /// Estimated breaker height, trough to crest, in meters.
  ///
  /// Zero means the swell is blocked in this simplified model, because it travels along or
  /// away from the shore. It does not mean calm water: real swell wraps around headlands,
  /// and wind waves or other swell may still be breaking.
  public let heightMeters: Double
  /// The single swell component the estimate was computed from.
  public let swell: Swell
  /// Angle between the swell's direction and the oceanward bearing: 0 is straight onshore.
  /// Nil when no oceanward bearing was supplied or the swell's direction is unknown; the
  /// height then assumes a straight-on approach, the largest value this formula can give
  /// for that swell.
  public let incidenceDegrees: Double?

  public init(heightMeters: Double, swell: Swell, incidenceDegrees: Double? = nil) {
    self.heightMeters = heightMeters
    self.swell = swell
    self.incidenceDegrees = incidenceDegrees
  }
}

extension SurfMath {
  /// Standard gravity in m/s².
  static let gravity = 9.80665

  /// Angle in degrees, `0...180`, between the direction something comes from and the bearing
  /// that points from the beach out to sea. 0 is straight onshore, 90 runs along the beach,
  /// and 180 comes straight off the land.
  public static func incidenceAngle(from bearing: Double, oceanwardBearing: Double) -> Double? {
    guard let from = normalizedBearing(bearing), let ocean = normalizedBearing(oceanwardBearing)
    else { return nil }
    let difference = abs(from - ocean)
    return min(difference, 360 - difference)
  }

  /// Breaker height from deep-water swell height and period, after Komar and Gaughan (1972):
  /// `Hb = 0.39 · g^(1/5) · (T · H0² · cos θ)^(2/5)`.
  ///
  /// `θ` is the deep-water angle between the swell and the shore-normal. The `cos θ` term
  /// comes from refraction over straight, parallel depth contours (`Kr² = cos θ / cos θb`),
  /// taking the wave to be nearly shore-parallel when it breaks (`cos θb ≈ 1`). Swell at 90°
  /// or more cannot reach the beach in this model and gives zero.
  ///
  /// The relation was fitted to swell-like waves on gently sloping beaches. It is a rough
  /// guide for long-period swell and unreliable for short, steep wind waves.
  /// Returns nil for negative or non-finite heights, non-positive periods and invalid angles.
  public static func breakingWaveHeight(
    deepWaterHeightMeters height: Double, periodSeconds period: Double,
    incidenceDegrees: Double = 0
  ) -> Double? {
    guard height.isFinite, period.isFinite, incidenceDegrees.isFinite,
      height >= 0, period > 0, (0...180).contains(incidenceDegrees)
    else { return nil }
    guard incidenceDegrees < 90 else { return 0 }
    let exposure = cos(incidenceDegrees * .pi / 180)
    let result = 0.39 * pow(gravity, 0.2) * pow(period * height * height * exposure, 0.4)
    return result.isFinite ? result : nil
  }

  /// Estimates each swell component on its own and returns the larger breaker.
  ///
  /// With an oceanward bearing, each component is reduced for its angle to the beach, so a
  /// smaller swell that arrives straight on can outrank a larger one that glances past.
  /// A component whose direction is unknown is estimated as straight on, so missing data can
  /// never make the reported breaker smaller. Without a bearing, no reduction is applied to
  /// either component. In both cases `incidenceDegrees` is nil.
  /// Components are never combined: height, period and direction stay together.
  public static func breakingWave(
    primary: Swell, secondary: Swell, oceanwardBearing: Double? = nil
  ) -> BreakingWaveEstimate? {
    if let oceanwardBearing, !oceanwardBearing.isFinite { return nil }
    let estimates = [primary, secondary].compactMap {
      breakingWave(for: $0, oceanwardBearing: oceanwardBearing)
    }
    // Ties keep the primary component, which comes first.
    return estimates.reduce(nil) { best, next in
      guard let best else { return next }
      return next.heightMeters > best.heightMeters ? next : best
    }
  }

  private static func breakingWave(
    for swell: Swell, oceanwardBearing: Double?
  ) -> BreakingWaveEstimate? {
    guard let height = swell.heightMeters, let period = swell.periodSeconds else { return nil }
    // An unknown or unusable direction leaves the angle nil, which is estimated straight on.
    var incidence: Double?
    if let oceanwardBearing, let direction = swell.directionDegrees {
      incidence = incidenceAngle(from: direction, oceanwardBearing: oceanwardBearing)
    }
    guard
      let breaker = breakingWaveHeight(
        deepWaterHeightMeters: height, periodSeconds: period, incidenceDegrees: incidence ?? 0)
    else { return nil }
    return BreakingWaveEstimate(heightMeters: breaker, swell: swell, incidenceDegrees: incidence)
  }
}
