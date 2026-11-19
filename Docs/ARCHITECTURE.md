# Architecture

```text
Your application / watch UI / backend
                 |
          ForecastProvider
          /              \
 StormglassClient    Other providers
          |
     HTTPTransport

SurfSpot (name, coordinate, oceanward bearing)
    |
ForecastQuery -> SurfForecast -> SurfSummary / SurfMath
                              -> optional ForecastCache
```

`SurfTapCore` imports Foundation only. Its public value types are Sendable. Coordinates and query windows validate both direct initialization and decoding. No SwiftUI, CoreLocation, HealthKit, WidgetKit, app groups, or application-global settings are required.

`SurfTapStormglass` owns wire-format decoding, Authorization, and HTTP error classification. It requests weather first to avoid spending tide quota when the main request fails. Tide failures carry component/reason information. Transport injection allows tests to exercise the actual request construction and response mapping without accessing the network.

## Design decisions

| Area | Package behavior |
| --- | --- |
| Credentials | Throwing initializer with caller-supplied credentials; nothing global or persisted |
| Units and formatting | Typed SI measurements; the consuming app owns display strings and conversions |
| Location | Explicit validated coordinate; geocoding and location permissions stay with the app |
| Beach orientation | Caller supplies the actual oceanward bearing, usually through a `SurfSpot`, or gets no wind label |
| Breaking waves | Published formula, one swell component at a time, labelled as an estimate; a missing height or period gives no estimate, and an unknown direction is treated as straight on |
| Swell exposure | Refraction term for a straight coast; swell from 90° or more off the oceanward bearing gives zero |
| Optional tide data | Structured issues identify the failed or missing component |
| Tide coverage | No extrapolation; gaps over two hours return unknown |
| Tide range | Small ranges remain valid; no universal tide-amplitude rejection |
| Direction averaging | Undefined circular means, such as opposing bearings, return nil |
| Retries and cancellation | No automatic retries; cancellation propagates |
| Logging | No raw response body or header logging |
| Caching | Bounded isolated in-memory cache with explicit freshness |

## Deliberate limits for the first release

The original watch screens, descriptions, icons, artwork, complications, location permissions, workout/session code and storage are not included. Geographic guesses about which way a coastline faces are also left out: a beach's orientation comes from the caller, as a `SurfSpot`, never from its coordinate.

Near-term height ranges, the breaking-wave estimate and dominant-swell selection are documented heuristics. There is no surf-quality score, safe-to-surf recommendation, claim of real-time observation, or tide-current prediction.

## Breaking-wave model

`SurfMath.breakingWaveHeight` implements Komar and Gaughan (1972), `Hb = 0.39 · g^(1/5) · (T · H0² · cos θ)^(2/5)`. It was chosen over a hand-tuned empirical fit because it is published, has one fixed coefficient, and can be checked by hand. The `cos θ` term is Snell's-law refraction over straight, parallel depth contours (`Kr² = cos θ / cos θb`) with the breaking angle taken as zero.

The rules around it are deliberately strict:

- Each swell component is estimated on its own and the larger breaker wins. Because `Hb` rises with `H²T · cos θ`, this is the `H²T` dominant-swell heuristic weighted by exposure, so a spot can favor a different component than open water does. `SurfSummary.dominantSwell` keeps its open-water meaning; `breakingWave.swell` is the spot-aware answer.
- Missing data never lowers the estimate. A component with no usable direction is estimated as straight on even when a bearing is known, and without a bearing no reduction is applied at all. In both cases `incidenceDegrees` is nil, which marks the value as the formula's upper case for that swell.
- Blocked swell yields an estimate of zero; a missing height or period yields no estimate. The two are kept distinct, and zero is documented as "blocked in this model", not calm water.
- `SurfSummary` reports a range across the current hour and the next two, using the same window as the open-water range.

The model has no bathymetry, tide, wind, sheltering or diffraction, and is unreliable for short, steep wind waves. It is a comparison aid, documented as such in the README.

## Time, datum and validation rules

Forecast timestamps are retained as absolute instants. `SurfSummary` uses timestamps, not array order, to locate the current hour and the following two hours. It does not move future data backward to fill a missing current hour. The adapter accepts ISO 8601 timestamps with or without fractional seconds and converts request boundaries to UTC UNIX seconds. The start is rounded down to include the current hour, exposed as `ForecastQuery.hourAlignedStart`; returned measurements are bounded by that hour and the requested end.

The adapter defaults to MSL. Apps that need MLLW must request it explicitly and label it. Both tide endpoints receive the same datum; contradictory response metadata rejects that endpoint. Station provenance stays separate because the endpoints may return different stations.

Queries cap the effective request interval, including hour/second rounding, at ten days. Summaries honor the requested start and end and exclude samples beyond the requested end from their range. The adapter rejects duplicate tide timestamps; direct calculation helpers accept identical duplicates but return unknown for conflicting duplicates. Tide interpolation uses weighted terms to avoid overflowing a subtraction; non-finite tide slopes return unknown.

## Adopting the package in an existing app

Add this package locally first. Adapt `SurfForecast`/`SurfSummary` into your app's existing report/view model. Keep formatting, localization, time zone lookup, app-group caching, and complication updates in the app. Pass credentials from app-owned storage or replace the direct adapter with an authenticated backend provider. Compare results with representative saved synthetic cases before removing an older forecast service.
