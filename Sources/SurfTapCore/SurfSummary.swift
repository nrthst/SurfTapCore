import Foundation

/// A display-independent summary. Sample time and requested summary time stay distinct.
public struct SurfSummary: Equatable, Sendable {
  public let time: Date
  public let currentHour: ForecastHour
  /// Range of available modeled wave heights over the current hour and next two hours.
  /// This is not a breaking-wave face-height prediction.
  public let nearTermWaveHeightMeters: ClosedRange<Double>?
  /// Estimated breaker for the current hour, from the swell component that breaks largest.
  /// A simplified formula, not an observation; see `SurfMath.breakingWaveHeight`.
  public let breakingWave: BreakingWaveEstimate?
  /// Range of the hourly breaker estimates over the current hour and next two hours.
  public let nearTermBreakingWaveHeightMeters: ClosedRange<Double>?
  /// The component with the most `H²T` in open water, before any allowance for the beach's
  /// orientation. `breakingWave?.swell` is the component expected to break largest at the spot.
  public let dominantSwell: Swell?
  public let windOrientation: WindOrientation?
  public let tideHeightMeters: Double?
  public let tideTrend: TideTrend?
  public let nextTide: TideExtreme?

  /// Returns nil when no measured forecast hour covers the requested instant.
  /// Callers must not label an arbitrary future/past sample as "current".
  /// Without an oceanward bearing, wind orientation is unknown and breaker estimates assume
  /// the swell arrives straight on.
  public init?(forecast: SurfForecast, at time: Date, oceanwardBearing: Double? = nil) {
    guard time.timeIntervalSince1970.isFinite,
      time >= forecast.query.start, time <= forecast.query.end
    else { return nil }
    let firstHour = forecast.query.hourAlignedStart
    let hours = forecast.hours.filter {
      $0.time >= firstHour && $0.time <= forecast.query.end
    }.sorted { $0.time < $1.time }
    guard
      let current = hours.last(where: {
        $0.time <= time && time.timeIntervalSince($0.time) < 3600 && $0.hasMeasurements
      })
    else { return nil }
    self.time = time
    self.currentHour = current
    let nearTerm = hours.filter {
      $0.time >= current.time && $0.time < current.time.addingTimeInterval(3 * 3600)
    }
    let heights = nearTerm.compactMap(\.waveHeightMeters).filter { $0.isFinite && $0 >= 0 }
    if let low = heights.min(), let high = heights.max() {
      nearTermWaveHeightMeters = low...high
    } else {
      nearTermWaveHeightMeters = nil
    }
    func breaker(_ hour: ForecastHour) -> BreakingWaveEstimate? {
      SurfMath.breakingWave(
        primary: hour.primarySwell, secondary: hour.secondarySwell,
        oceanwardBearing: oceanwardBearing)
    }
    breakingWave = breaker(current)
    let breakers = nearTerm.compactMap { breaker($0)?.heightMeters }
    if let low = breakers.min(), let high = breakers.max() {
      nearTermBreakingWaveHeightMeters = low...high
    } else {
      nearTermBreakingWaveHeightMeters = nil
    }
    dominantSwell = SurfMath.dominantSwell(
      primary: current.primarySwell, secondary: current.secondarySwell)
    if let wind = current.windDirectionDegrees, let oceanwardBearing {
      windOrientation = SurfMath.windOrientation(from: wind, oceanwardBearing: oceanwardBearing)
    } else {
      windOrientation = nil
    }
    tideHeightMeters = SurfMath.tideHeight(at: time, levels: forecast.tideLevels)
    tideTrend = SurfMath.tideTrend(at: time, levels: forecast.tideLevels)
    nextTide = forecast.tideExtremes.filter { $0.time > time }.min { $0.time < $1.time }
  }
}
