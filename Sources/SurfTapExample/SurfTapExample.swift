import Foundation
import SurfTapCore
import SurfTapStormglass

#if canImport(Darwin)
  import Darwin
#else
  import Glibc
#endif

@main
struct SurfTapExample {
  static func main() async {
    do { try await run() } catch {
      let message =
        (error as? LocalizedError)?.errorDescription
        ?? "Unable to build a forecast. Check the arguments."
      FileHandle.standardError.write(Data("\(message)\n".utf8))
      exit(EXIT_FAILURE)
    }
  }

  private static func run() async throws {
    let arguments = Array(CommandLine.arguments.dropFirst())
    let live = arguments.first == "--live"
    guard arguments.isEmpty || (live && (3...4).contains(arguments.count)) else {
      let usage = "Usage: swift run surftap-example [--live LATITUDE LONGITUDE [OCEANWARD_BEARING]]"
      FileHandle.standardError.write(Data("\(usage)\n".utf8))
      exit(EXIT_FAILURE)
    }
    let now = live ? Date() : Date(timeIntervalSince1970: 1_735_689_600)
    let coordinate: Coordinate
    // The demo bearing is illustrative. Check a chart for the beach you care about.
    var oceanwardBearing: Double? = 210
    if live {
      guard let lat = Double(arguments[1]), let lon = Double(arguments[2]) else {
        throw ForecastValidationError.invalidCoordinate
      }
      coordinate = try Coordinate(latitude: lat, longitude: lon)
      oceanwardBearing = nil
      if arguments.count == 4 {
        guard let bearing = Double(arguments[3]) else {
          throw ForecastValidationError.invalidBearing
        }
        oceanwardBearing = bearing
      }
    } else {
      coordinate = try Coordinate(latitude: 33.66, longitude: -118.00)
    }
    // Without a bearing there is no spot: wind orientation and swell exposure stay unknown.
    let spot = try oceanwardBearing.map {
      try SurfSpot(name: "Example beach", coordinate: coordinate, oceanwardBearing: $0)
    }
    let hour = Date(timeIntervalSince1970: floor(now.timeIntervalSince1970 / 3600) * 3600)
    let query = try ForecastQuery(
      coordinate: coordinate, start: hour,
      end: hour.addingTimeInterval(24 * 3600), datum: .meanSeaLevel)
    let forecast: SurfForecast
    if live {
      let key = ProcessInfo.processInfo.environment["STORMGLASS_API_KEY"] ?? ""
      let client = try StormglassClient(apiKey: key)
      forecast = try await client.forecast(for: query)
    } else {
      // Invented values that show the output format. They describe no real place or time.
      forecast = SurfForecast(
        query: query, source: "synthetic-demo",
        hours: [
          ForecastHour(
            time: hour, waveHeightMeters: 1.2,
            primarySwell: Swell(heightMeters: 1, periodSeconds: 11, directionDegrees: 200),
            // Bigger in open water, but it glances past a beach that faces 210°.
            secondarySwell: Swell(heightMeters: 1.5, periodSeconds: 8, directionDegrees: 285),
            windSpeedMetersPerSecond: 3, windDirectionDegrees: 30, waterTemperatureCelsius: 18),
          ForecastHour(
            time: hour.addingTimeInterval(3600), waveHeightMeters: 1.4,
            primarySwell: Swell(heightMeters: 1.2, periodSeconds: 12, directionDegrees: 200)),
          ForecastHour(
            time: hour.addingTimeInterval(7200), waveHeightMeters: 1.3,
            primarySwell: Swell(heightMeters: 1.1, periodSeconds: 12, directionDegrees: 205)),
        ],
        tideLevels: [
          TideLevel(time: hour, heightMeters: 0.3),
          TideLevel(time: hour.addingTimeInterval(3600), heightMeters: 0.6),
        ])
    }
    print(
      live
        ? "Live Stormglass forecast"
        : "DEMO ONLY — invented numbers, not a forecast for any real beach or time")
    if live {
      print("Estimates only. Not for safety decisions; check official forecasts and warnings.")
    }
    let summary =
      if let spot {
        SurfSummary(forecast: forecast, at: now, spot: spot)
      } else {
        SurfSummary(forecast: forecast, at: now)
      }
    guard let summary else {
      print("No forecast sample covers the current hour.")
      return
    }
    if let range = summary.nearTermWaveHeightMeters {
      print(
        String(
          format: "Near-term modeled wave height: %.1f–%.1f m", range.lowerBound, range.upperBound))
    }
    if let swell = summary.dominantSwell, let period = swell.periodSeconds {
      print(String(format: "Dominant open-water swell period: %.1f s", period))
    }
    if let range = summary.nearTermBreakingWaveHeightMeters {
      print(
        String(
          format: "Estimated breaking wave height: %.1f–%.1f m (simplified formula)",
          range.lowerBound, range.upperBound))
    }
    if let breaker = summary.breakingWave {
      if let angle = breaker.incidenceDegrees, let period = breaker.swell.periodSeconds {
        print(
          String(format: "Largest breaker: %.1f s swell, %.0f° off straight-on", period, angle))
      } else {
        print("Swell angle to the beach unknown: estimate assumes it arrives straight on")
      }
    }
    if let wind = summary.windOrientation { print("Wind: \(wind.rawValue)") }
    if let height = summary.tideHeightMeters {
      print(String(format: "Predicted tide height: %.2f m (%@)", height, query.datum.rawValue))
    }
    for issue in forecast.issues { print("\(issue.component.rawValue): \(issue.reason.rawValue)") }
    if !live {
      print("For a real forecast, run with --live and your own Stormglass API key.")
    }
  }
}
