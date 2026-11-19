import Foundation

public struct CachedForecast: Sendable {
  public let forecast: SurfForecast
  /// When the app fetched this response, not when the forecast model was generated.
  public let fetchedAt: Date

  public func isFresh(at time: Date, maximumAge: TimeInterval) -> Bool {
    let age = time.timeIntervalSince(fetchedAt)
    return maximumAge.isFinite && maximumAge >= 0 && age >= 0 && age <= maximumAge
  }
}

/// Bounded, in-memory cache. Use a separate instance per provider/account/source.
/// Keys contain the exact coordinate, window, tide option and datum. No location rounding.
/// No automatic refreshes, persistence, request coalescing or silent stale fallback.
public actor ForecastCache {
  private struct Entry {
    let value: CachedForecast
    var lastAccess: UInt64
  }
  private let capacity: Int
  private var sequence: UInt64 = 0
  private var entries: [ForecastQuery: Entry] = [:]

  public init(capacity: Int = 32) { self.capacity = max(1, capacity) }

  public func insert(_ forecast: SurfForecast, fetchedAt: Date) {
    sequence &+= 1
    entries[forecast.query] = Entry(
      value: CachedForecast(forecast: forecast, fetchedAt: fetchedAt), lastAccess: sequence
    )
    if entries.count > capacity,
      let oldest = entries.min(by: { $0.value.lastAccess < $1.value.lastAccess })
    {
      entries.removeValue(forKey: oldest.key)
    }
  }

  /// Returns the entry even if stale. Inspect isFresh before deciding whether to display it.
  public func entry(for query: ForecastQuery) -> CachedForecast? {
    guard var entry = entries[query] else { return nil }
    sequence &+= 1
    entry.lastAccess = sequence
    entries[query] = entry
    return entry.value
  }

  public func removeAll() { entries.removeAll() }
}
