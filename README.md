# SurfTap Core

```text
                                              _.--~~~~~~--._
                                         _.-~~   _.--~~--._ ~~-._
                    ___               .-~     .-~          ~-.   ~-.
                   /   \            .~      .~                ~.    \
                   \___/          .~      .~                    \    \
             \       |       /   /       /                       |    |
              \______|______/   /       /                        |    |
                     |         /       |                        /    /
                     |        |        |                      .~   .~
                    / \       |         \                 _.-~  _.-~
                   /   \       \         ~-._________.--~~  _.-~
                __/     \__     ~-._                   _.--~
   ____________/___________\____________~~--.......--~~
   \___________________________________/
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  ~~~~    ~~~~~~~      ~~~~~        ~~~~~~~~      ~~~~~       ~~~~~~

                         S U R F T A P   C O R E
```

A surf forecast engine for Swift.

SurfTap Core is a small Swift package that turns a marine forecast into what a surfer wants to know at a particular beach: roughly how big the waves will break, which swell is doing the work, whether the wind is onshore or offshore, and where the tide is heading. A separate Stormglass adapter connects it to live weather and tide data using **your own API key**.

Output of the bundled offline demo. **These numbers are invented to show the format; they are not a forecast for any real beach or time.**

```text
DEMO ONLY — invented numbers, not a forecast for any real beach or time
Near-term modeled wave height: 1.2–1.4 m
Dominant open-water swell period: 8.0 s
Estimated breaking wave height: 1.6–1.9 m (simplified formula)
Largest breaker: 11.0 s swell, 10° off straight-on
Wind: offshore
Predicted tide height: 0.30 m (MSL)
For a real forecast, run with --live and your own Stormglass API key.
```

What it does:

- **Breaking-wave estimate.** Converts offshore swell height and period into an estimated breaker height with a published formula (Komar and Gaughan, 1972).
- **Spot-aware swell exposure.** Give a beach its oceanward bearing once, and swell arriving at an angle is reduced, while swell from behind the land is ruled out.
- **Wind orientation.** Onshore, offshore or cross-shore, from the same bearing.
- **Tides.** Interpolated height, rising/falling trend and the next high or low, without extrapolating past the data.
- **Honest gaps.** Missing values stay `nil`, failed tide requests are reported, and nothing is guessed from a coordinate.

It is a library, not an app: it has no user interface, location tracking, or persistent storage. Those belong to whatever you build with it.

**Status:** pre-1.0. The public API may change between minor versions until 1.0. No third-party package dependencies. Swift 6 language mode.

> **Not for safety decisions.** SurfTap Core provides modeled estimates for general information and recreation only. Do not rely on it — or on any product built with it — to decide whether it is safe to enter the water, for navigation, search and rescue, or any emergency. See [Safety and disclaimer](#safety-and-disclaimer).

## Try it without an account

With Swift 6.0 or later installed, run these commands from the package directory:

```sh
swift test
swift run surftap-example
```

The example runs on invented data so you can see the package work without a key or a network connection. **It tells you nothing about real conditions anywhere.** The made-up numbers exist only in the example program and the tests; the two libraries contain no forecast data of their own. A real forecast needs live data from Stormglass with your own API key, described under [Fetch a forecast](#fetch-a-forecast).

Tests make no external requests and need no credentials.

## Package products

| Product | Purpose |
| --- | --- |
| `SurfTapCore` | Provider-independent models, surf spots, breaking-wave and tide calculations, summaries, and bounded in-memory cache |
| `SurfTapStormglass` | Stormglass v2 weather, sea-level and tide-extreme adapter |

Declared minimum deployment targets: macOS 13, iOS 16, watchOS 9 and tvOS 16. The source also supports Linux through FoundationNetworking. CI is configured for macOS and Linux; consult the actual run results before assuming a platform has passed.

## Install

Add the package to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/nrthst/SurfTapCore.git", .upToNextMinor(from: "0.1.0")),
],
targets: [
    .target(
        name: "YourTarget",
        dependencies: [
            .product(name: "SurfTapCore", package: "SurfTapCore"),
            .product(name: "SurfTapStormglass", package: "SurfTapCore"),
        ]
    ),
]
```

In Xcode, choose File > Add Package Dependencies, enter `https://github.com/nrthst/SurfTapCore.git`, and add `SurfTapCore` and `SurfTapStormglass` to your target. `SurfTapStormglass` is only needed for live data.

Until 1.0 a minor version may change the public API, so `.upToNextMinor` keeps updates to bug fixes; read the release notes before moving to a new minor version.

## Define a spot

A `SurfSpot` is a name, a coordinate and the direction the beach faces. Define it once and reuse it for queries and summaries.

```swift
import SurfTapCore

let spot = try SurfSpot(
    name: "Example beach",
    coordinate: Coordinate(latitude: 33.66, longitude: -118.00),
    oceanwardBearing: 210
)
```

`oceanwardBearing` is the compass bearing from the sand straight out to open water, perpendicular to the shoreline, in degrees clockwise from north. A beach that looks out to the south-west is about 225. Read it off a chart or map for your beach; the value above is illustrative. The package does not derive it from the coordinate, because doing that well needs a coastline dataset and local knowledge.

## Fetch a forecast

```swift
import Foundation
import SurfTapCore
import SurfTapStormglass

func loadForecast(for spot: SurfSpot, apiKey: String) async throws -> SurfForecast {
    let now = Date()
    let start = Date(timeIntervalSince1970:
        floor(now.timeIntervalSince1970 / 3600) * 3600)
    let query = try ForecastQuery(
        spot: spot,
        start: start,
        end: start.addingTimeInterval(24 * 3600),
        includesTides: true,
        datum: .meanSeaLevel
    )
    let client = try StormglassClient(apiKey: apiKey)
    return try await client.forecast(for: query)
}
```

Pass a key from your application's credential storage; do not paste it into source code. Each developer supplies their own Stormglass credentials. An app that serves users under one developer-owned key should place that key behind an authenticated backend. A key embedded in a distributed app can be extracted.

The command-line example reads `STORMGLASS_API_KEY` from its environment only when invoked with `--live`. [.env.example](.env.example) documents the variable with a placeholder; the package does not automatically load that file, and the client rejects the placeholder:

```sh
# Supply STORMGLASS_API_KEY through your local secret manager/environment first.
swift run surftap-example --live 33.66 -118.00 210
```

The arguments are latitude, longitude and an optional oceanward bearing. That command makes real, quota-consuming requests. No live request runs automatically during builds or tests.

## Turn measurements into a summary

```swift
if let summary = SurfSummary(forecast: forecast, at: Date(), spot: spot) {
    let breakers = summary.nearTermBreakingWaveHeightMeters  // estimated range, next three hours
    let breaker = summary.breakingWave                       // current hour, with the swell used
    let offshoreWaves = summary.nearTermWaveHeightMeters     // modeled open-water range
    let dominantSwell = summary.dominantSwell
    let wind = summary.windOrientation
    let tideHeight = summary.tideHeightMeters
    let tideTrend = summary.tideTrend
    let nextTide = summary.nextTide
}
```

Without a spot, use `SurfSummary(forecast:at:)`. Wind orientation is then unknown, and breaker estimates assume every swell arrives straight on.

All heights are meters, wind speeds are meters/second, periods are seconds, and temperatures are Celsius. Use `SurfMath` for display conversions. Dates represent absolute instants; localize them in your app. Missing measurements remain `nil`, rather than becoming zero.

- The wave range spans available samples in the current forecast hour and following two hours. It is a modeled offshore wave range, not breaking surf height; the breaker estimate is separate and described below.
- Dominant swell uses an `H²T` heuristic to choose one complete primary or secondary component in open water. It does not mix values between components, and it takes no account of the beach's orientation.
- Tide heights are relative to the requested datum (MSL by default; MLLW also supported). Low/negative heights are valid. Interpolation never extrapolates and refuses gaps over two hours.
- Tide trend describes changing water level. It does not predict slack currents or safe swimming conditions.
- A summary returns `nil` outside the requested window or when no measured hourly sample covers the instant. Samples beyond the requested end cannot widen the displayed wave range.
- Query windows are limited to ten days including the start's hour rounding. Conflicting tide samples at the same timestamp return unknown; arithmetic overflow never becomes a reported tide trend.

## How the breaking-wave estimate works

Forecast models report swell in open water. Waves grow as they slow down over a shallowing sea floor, and long-period swell grows more than short-period swell of the same height. The package estimates the breaker height with the relation of Komar and Gaughan (1972):

```text
Hb = 0.39 · g^(1/5) · (T · H0² · cos θ)^(2/5)
```

`H0` is the swell height in open water, `T` its period, `g` gravity, and `θ` the angle between the swell's direction and the spot's oceanward bearing.

| Open-water swell | Angle to the beach | Estimated breaker |
| --- | --- | --- |
| 1.0 m at 8 s | straight on | 1.4 m |
| 1.0 m at 12 s | straight on | 1.7 m |
| 1.0 m at 16 s | straight on | 1.9 m |
| 1.0 m at 12 s | 60° | 1.3 m |
| 1.0 m at 12 s | 90° or more | 0 m (blocked in this model) |

- **Exposure.** The `cos θ` term is the refraction result for a straight coast with parallel depth contours. Swell that runs along the beach or comes from behind the land gives zero. A smaller swell arriving straight on can therefore outrank a larger one that glances past, and `breakingWave.swell` tells you which component was used.
- **Zero is not calm water.** An estimate of zero means the swell is blocked in this simplified model. Real swell wraps around headlands and into bays, and wind waves or another swell may still be breaking.
- **Missing direction never lowers the estimate.** A swell with no reported direction is estimated as arriving straight on, and `incidenceDegrees` is `nil` to flag it.
- **One component at a time.** Primary and secondary swell are estimated separately and the larger breaker is reported. Their heights are never added together.
- **A range, not a number.** `nearTermBreakingWaveHeightMeters` spans the hourly estimates for the current hour and the next two.
- **Height convention.** The result is trough-to-crest breaker height in meters. It is not a surf-report "face height" or a locally scaled measure.

What the estimate leaves out: the shape and slope of the sea floor, reefs, sandbars and points, tide level, wind, currents, shadowing by headlands and islands, and waves wrapping around obstacles. The formula was fitted to swell on gently sloping beaches and is unreliable for short, steep wind waves. Real breaks can be much larger or smaller than the estimate. Treat it as a rough guide for comparing swells at a spot, and read the [Safety and disclaimer](#safety-and-disclaimer) section.

You can also call the pieces directly:

```swift
let height = SurfMath.breakingWaveHeight(
    deepWaterHeightMeters: 1.0, periodSeconds: 12, incidenceDegrees: 20)
let angle = SurfMath.incidenceAngle(from: 190, oceanwardBearing: 210)
```

Reference: Komar, P. D., and Gaughan, M. K. (1972). "Airy wave theory and breaker height prediction." *Proceedings of the 13th Coastal Engineering Conference*, ASCE, 405–418.

## Failures, quotas, and caching

Weather is required. If it fails, the adapter throws a typed `StormglassError` and does not request tides. After weather succeeds, the two optional tide requests run concurrently. Missing or failed tide data appears in `forecast.issues`, while usable weather remains available. Cancellation always propagates.

A full refresh issues three requests; `includesTides: false` issues one. There are no automatic retries, polling, or hidden refreshes. The adapter uses the requested weather source (`sg` by default) and never silently substitutes another model. It retains separate station metadata for the two tide endpoints.

`ForecastCache` is an optional bounded actor, keyed by the exact coordinate, time window, tide option and datum. Use a separate cache per provider/account/source. Reuse the same hour-aligned query to obtain cache hits. `entry(for:)` may return a stale entry; call `isFresh(at:maximumAge:)` and decide explicitly whether to display it. Cache timestamps mean retrieval time, not the provider's model update time. Persistence and request coalescing belong to your app.

Stormglass access and data use are governed separately from this code's license. Check the current [plans](https://stormglass.io/pricing/) and [terms](https://stormglass.io/terms-and-conditions/); open-source code does not include a subscription or grant data-redistribution rights. See the official [API documentation](https://docs.stormglass.io/) and [tide guide](https://stormglass.io/our-tide-api-better-than-ever/) for service details.

## Safety and disclaimer

**IMPORTANT — READ CAREFULLY.** SurfTap Core is provided for general informational and recreational purposes only. It is **not** a safety, navigation, life-saving, or emergency product, and it is **not** a substitute for official marine forecasts, warnings, or professional advice.

By using this software, or any application, service, or product that incorporates it, you acknowledge and agree to the following:

1. **No safety or navigation use.** Do not use this software, its output, or anything built with it to decide whether conditions are safe for surfing, swimming, diving, paddling, boating, fishing, or any other activity; for navigation or route planning; for search and rescue; or for any purpose where an error, omission, delay, or outage could lead to injury, death, property damage, or other loss.
2. **Estimates only; accuracy not guaranteed.** Wave heights, periods, directions, wind, temperature, tide heights, tide trends, breaking-wave estimates, swell exposure, wind orientation, and any other derived summary or heuristic are **modeled estimates**, not measurements of breaking surf, water depth, current speed, or observed conditions at a beach. The breaking-wave estimate in particular is the output of a simplified formula that ignores the sea floor and local geography; actual waves may be substantially larger, more powerful, or more dangerous than any value this software produces. Values may be inaccurate, incomplete, delayed, out of date, contradictory, or unavailable without notice. Ocean and weather conditions can change rapidly and can differ sharply from any forecast.
3. **Third-party data and heuristics.** Live forecasts depend on third-party services and numerical models (including Stormglass and the sources it uses) that this project does not control, verify, or endorse. This package also applies its own calculations and heuristics. Neither the authors nor the contributors warrant the fitness of any third-party data or of any calculation in this package for any particular purpose.
4. **Local hazards are not covered.** Nothing in this software accounts for rip currents, shore break, rocks, reefs, sandbars, piers, water quality, pollution, marine life, crowds, lightning, cold-water shock, equipment failure, or other site-specific hazards, or for your skill, fitness, judgment, or equipment.
5. **Official sources and your own judgment.** Always check official marine forecasts and warnings from the appropriate authority for your location, obey lifeguards and local regulations, observe the actual conditions yourself before entering the water, and when in doubt, stay out. **You assume all risk** arising from your use of this software and its output.
6. **No warranty; limitation of liability.** THE SOFTWARE IS PROVIDED "AS IS" AND "AS AVAILABLE", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, TITLE, AND NON-INFRINGEMENT. TO THE MAXIMUM EXTENT PERMITTED BY APPLICABLE LAW, THE AUTHORS AND CONTRIBUTORS SHALL NOT BE LIABLE FOR ANY CLAIM, DAMAGES, OR OTHER LIABILITY — WHETHER IN CONTRACT, TORT (INCLUDING NEGLIGENCE), STRICT LIABILITY, OR OTHERWISE — ARISING FROM, OUT OF, OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE, INCLUDING ANY RELIANCE ON ITS OUTPUT. The complete license terms are in [LICENSE](LICENSE) and govern.
7. **Downstream products are your responsibility.** If you build, distribute, or operate an application or service that uses this package, you are solely responsible for testing it, complying with applicable law and with your data provider's terms, obtaining any required rights, and giving your users clear, prominent warnings consistent with this section. Do not present this package's output as verified, real-time, observed, official, or endorsed by any government agency or by Stormglass. Inclusion of this disclaimer in your own materials does not create any affiliation with, or endorsement by, the SurfTap contributors.

## Contribute

Read [CONTRIBUTING.md](CONTRIBUTING.md), [SECURITY.md](SECURITY.md), and the [architecture notes](Docs/ARCHITECTURE.md). Before proposing a release, follow [RELEASING.md](Docs/RELEASING.md).

```sh
python3 scripts/check_public_files.py
python3 -B -m unittest discover -s scripts/tests
swift test
swift build -c release
```

## License

[MIT](LICENSE). Copyright (c) 2025-2026 SurfTap contributors.

You may use, modify, and distribute this code, including commercially. Keep the copyright notice and complete MIT license with copies or substantial portions of the code. For a compiled app, include them in your distributed third-party notices or equivalent license materials. MIT does not require a visible in-app badge, promotional credit, or publication of your own source code. See [ATTRIBUTION.md](ATTRIBUTION.md) for a suggested credit.

The license covers the files distributed in this package. The project is not affiliated with or endorsed by Stormglass.
