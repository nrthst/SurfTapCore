import Foundation
import SurfTapCore
import Testing

private let epoch = Date(timeIntervalSince1970: 1_735_689_600)
private func query(latitude: Double = 40, datum: TideDatum = .meanSeaLevel) throws -> ForecastQuery
{
  try ForecastQuery(
    coordinate: Coordinate(latitude: latitude, longitude: -73),
    start: epoch, end: epoch.addingTimeInterval(86400), datum: datum)
}

@Test func summariesCannotEscapeTheRequestedWindow() throws {
  let coordinate = try Coordinate(latitude: 40, longitude: -73)
  let query = try ForecastQuery(
    coordinate: coordinate, start: epoch.addingTimeInterval(1800),
    end: epoch.addingTimeInterval(4500))
  let forecast = SurfForecast(
    query: query, source: "synthetic",
    hours: [
      ForecastHour(time: epoch, waveHeightMeters: 1),
      ForecastHour(time: epoch.addingTimeInterval(3600), waveHeightMeters: 2),
      ForecastHour(time: epoch.addingTimeInterval(7200), waveHeightMeters: 99),
    ])
  #expect(SurfSummary(forecast: forecast, at: epoch) == nil)
  #expect(SurfSummary(forecast: forecast, at: query.start)?.nearTermWaveHeightMeters == 1...2)
  #expect(SurfSummary(forecast: forecast, at: query.end) != nil)
  #expect(SurfSummary(forecast: forecast, at: query.end.addingTimeInterval(1)) == nil)
}

@Test func hourAlignedStartRoundsDownAndLeavesAlignedStartsAlone() throws {
  let coordinate = try Coordinate(latitude: 40, longitude: -73)
  let end = epoch.addingTimeInterval(86400)
  #expect(try query().hourAlignedStart == epoch)
  let midHour = try ForecastQuery(
    coordinate: coordinate, start: epoch.addingTimeInterval(3599.5), end: end)
  #expect(midHour.hourAlignedStart == epoch)
  let beforeEpoch = try ForecastQuery(
    coordinate: coordinate, start: Date(timeIntervalSince1970: -1800),
    end: Date(timeIntervalSince1970: 3600))
  #expect(beforeEpoch.hourAlignedStart == Date(timeIntervalSince1970: -3600))
}

@Test func decodedForecastsAreSortedLikeConstructedOnes() throws {
  let later = ForecastHour(time: epoch.addingTimeInterval(3600), waveHeightMeters: 2)
  let earlier = ForecastHour(time: epoch, waveHeightMeters: 1)
  let original = SurfForecast(
    query: try query(), source: "synthetic", hours: [later, earlier],
    tideLevels: [
      TideLevel(time: epoch.addingTimeInterval(3600), heightMeters: 1),
      TideLevel(time: epoch, heightMeters: 0),
    ],
    tideExtremes: [TideExtreme(time: epoch, kind: .low)],
    levelStation: TideStation(name: "Synthetic Station"),
    issues: [ForecastIssue(component: .tideExtremes, reason: .noData)])
  #expect(original.hours == [earlier, later])
  let encoded = try JSONEncoder().encode(original)
  #expect(try JSONDecoder().decode(SurfForecast.self, from: encoded) == original)

  // Reverse the stored order in the JSON itself; decoding must restore time order.
  var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
  let storedHours = try #require(object["hours"] as? [Any])
  let storedLevels = try #require(object["tideLevels"] as? [Any])
  object["hours"] = Array(storedHours.reversed())
  object["tideLevels"] = Array(storedLevels.reversed())
  let shuffled = try JSONSerialization.data(withJSONObject: object)
  #expect(try JSONDecoder().decode(SurfForecast.self, from: shuffled) == original)
}

@Test func conflictingTidesAreUnknownAndIdenticalDuplicatesAreHarmless() {
  let first = TideLevel(time: epoch, heightMeters: 1)
  let later = TideLevel(time: epoch.addingTimeInterval(3600), heightMeters: 2)
  let conflict = TideLevel(time: epoch, heightMeters: 5)
  let time = epoch.addingTimeInterval(1800)
  #expect(SurfMath.tideHeight(at: time, levels: [first, later, first]) == 1.5)
  #expect(SurfMath.tideHeight(at: time, levels: [first, later, conflict]) == nil)
  #expect(SurfMath.tideTrend(at: time, levels: [conflict, later, first]) == nil)
}

@Test func tideArithmeticDoesNotProduceInfinityFromFiniteInputs() {
  let levels = [
    TideLevel(time: epoch, heightMeters: -1e308),
    TideLevel(time: epoch.addingTimeInterval(3600), heightMeters: 1e308),
  ]
  #expect(SurfMath.tideHeight(at: epoch.addingTimeInterval(1800), levels: levels) == 0)
  #expect(SurfMath.tideTrend(at: epoch.addingTimeInterval(1800), levels: levels) == nil)
}

@Test func tenDayLimitIncludesRequestRounding() throws {
  let coordinate = try Coordinate(latitude: 40, longitude: -73)
  let end = epoch.addingTimeInterval(10 * 86400)
  _ = try ForecastQuery(coordinate: coordinate, start: epoch, end: end)
  #expect(throws: ForecastValidationError.invalidTimeRange) {
    try ForecastQuery(
      coordinate: coordinate, start: epoch.addingTimeInterval(1800),
      end: end.addingTimeInterval(1800))
  }
  #expect(throws: ForecastValidationError.invalidTimeRange) {
    try ForecastQuery(
      coordinate: coordinate, start: epoch.addingTimeInterval(0.5),
      end: end.addingTimeInterval(0.5))
  }
}

@Test(arguments: [Double.nan, .infinity, -91, 91])
func rejectsInvalidLatitude(_ latitude: Double) {
  #expect(throws: ForecastValidationError.invalidCoordinate) {
    try Coordinate(latitude: latitude, longitude: 0)
  }
}

@Test func validatesDecodedCoordinatesAndQueries() throws {
  #expect(throws: (any Error).self) {
    try JSONDecoder().decode(Coordinate.self, from: Data(#"{"latitude":0,"longitude":181}"#.utf8))
  }
  let original = try query()
  #expect(
    try JSONDecoder().decode(ForecastQuery.self, from: JSONEncoder().encode(original)) == original)
  #expect(throws: ForecastValidationError.invalidTimeRange) {
    try ForecastQuery(coordinate: original.coordinate, start: epoch, end: epoch)
  }
  #expect(throws: ForecastValidationError.invalidTimeRange) {
    try ForecastQuery(
      coordinate: original.coordinate, start: epoch, end: epoch.addingTimeInterval(11 * 86400))
  }
}

@Test func conversionsAndCardinalBoundaries() {
  #expect(abs(SurfMath.metersToFeet(0.3048) - 1) < 1e-10)
  #expect(abs(SurfMath.metersPerSecondToMPH(0.44704) - 1) < 1e-10)
  #expect(SurfMath.celsiusToFahrenheit(0) == 32)
  #expect(SurfMath.cardinalDirection(-90) == "W")
  #expect(SurfMath.cardinalDirection(360) == "N")
  #expect(SurfMath.cardinalDirection(11.25) == "NNE")
  #expect(SurfMath.cardinalDirection(.infinity) == nil)
  #expect(SurfMath.normalizedBearing(-1e-20) == 0)
  #expect(SurfMath.normalizedBearing(-90) == 270)
  #expect(SurfMath.normalizedBearing(720) == 0)
}

@Test func circularMeansHandleNorthAndOpposition() throws {
  #expect(abs(try #require(SurfMath.circularMean([350, 10]))) < 1e-8)
  #expect(SurfMath.circularMean([90, 270]) == nil)
  #expect(SurfMath.circularMean([]) == nil)
  #expect(SurfMath.circularMean([.nan]) == nil)
}

@Test func windUsesFromDirectionAndExplicitCoast() {
  #expect(SurfMath.windOrientation(from: 90, oceanwardBearing: 90) == .onshore)
  #expect(SurfMath.windOrientation(from: 270, oceanwardBearing: 90) == .offshore)
  #expect(SurfMath.windOrientation(from: 0, oceanwardBearing: 90) == .crossShore)
  #expect(SurfMath.windOrientation(from: .nan, oceanwardBearing: 90) == nil)
}

@Test func dominantSwellKeepsComponentsTogether() {
  let primary = Swell(heightMeters: 1, periodSeconds: 6, directionDegrees: 90)
  let secondary = Swell(heightMeters: 0.9, periodSeconds: 16, directionDegrees: 180)
  #expect(SurfMath.dominantSwell(primary: primary, secondary: secondary) == secondary)
  #expect(SurfMath.dominantSwell(primary: Swell(periodSeconds: 18), secondary: Swell()) == nil)
}

@Test func tidesInterpolateWithoutExtrapolationOrLargeGaps() throws {
  let levels = [
    TideLevel(time: epoch.addingTimeInterval(3600), heightMeters: 1),
    TideLevel(time: epoch, heightMeters: -1),
  ]
  #expect(SurfMath.tideHeight(at: epoch.addingTimeInterval(1800), levels: levels) == 0)
  #expect(SurfMath.tideHeight(at: epoch, levels: levels) == -1)
  #expect(SurfMath.tideHeight(at: epoch.addingTimeInterval(-1), levels: levels) == nil)
  #expect(SurfMath.tideHeight(at: epoch.addingTimeInterval(3601), levels: levels) == nil)
  #expect(
    SurfMath.tideHeight(at: epoch.addingTimeInterval(1800), levels: levels, maximumGap: 60) == nil)
  #expect(SurfMath.tideTrend(at: epoch.addingTimeInterval(1800), levels: levels) == .rising)
  #expect(SurfMath.tideTrend(at: epoch.addingTimeInterval(4000), levels: levels) == nil)
  #expect(
    SurfMath.tideTrend(at: epoch.addingTimeInterval(1800), levels: levels, maximumGap: 60) == nil)
  #expect(
    SurfMath.tideTrend(at: epoch.addingTimeInterval(1800), levels: levels, maximumGap: .nan) == nil)
}

@Test func summaryUsesTimesInsteadOfArrayOrderOrSampleCount() throws {
  let forecast = SurfForecast(
    query: try query(), source: "test",
    hours: [
      ForecastHour(time: epoch.addingTimeInterval(10 * 3600), waveHeightMeters: 99),
      ForecastHour(time: epoch.addingTimeInterval(3600), waveHeightMeters: 2),
      ForecastHour(time: epoch, waveHeightMeters: 1, windDirectionDegrees: 270),
    ])
  let summary = try #require(SurfSummary(forecast: forecast, at: epoch.addingTimeInterval(60)))
  #expect(summary.nearTermWaveHeightMeters == 1...2)
  #expect(summary.windOrientation == nil)
  #expect(
    SurfSummary(forecast: forecast, at: epoch, oceanwardBearing: 90)?.windOrientation == .offshore)
  #expect(SurfSummary(forecast: forecast, at: epoch.addingTimeInterval(-1)) == nil)
  #expect(SurfSummary(forecast: forecast, at: epoch.addingTimeInterval(5 * 3600)) == nil)
}

@Test func cacheSeparatesCoordinatesAndDatumsAndMarksStaleEntries() async throws {
  let cache = ForecastCache(capacity: 2)
  let first = try query()
  let second = try query(latitude: 41)
  let third = try query(datum: .meanLowerLowWater)
  await cache.insert(SurfForecast(query: first, source: "test", hours: []), fetchedAt: epoch)
  let cached = try #require(await cache.entry(for: first))
  #expect(cached.isFresh(at: epoch.addingTimeInterval(30), maximumAge: 60))
  #expect(!cached.isFresh(at: epoch.addingTimeInterval(61), maximumAge: 60))
  #expect(!cached.isFresh(at: epoch.addingTimeInterval(-1), maximumAge: 60))
  #expect(await cache.entry(for: second) == nil)
  #expect(await cache.entry(for: third) == nil)
  await cache.insert(SurfForecast(query: second, source: "test", hours: []), fetchedAt: epoch)
  _ = await cache.entry(for: first)
  await cache.insert(SurfForecast(query: third, source: "test", hours: []), fetchedAt: epoch)
  #expect(await cache.entry(for: second) == nil)
  #expect(await cache.entry(for: first) != nil)
  await cache.removeAll()
  #expect(await cache.entry(for: first) == nil)
}

@Test func breakerHeightMatchesKomarGaughanAndItsScaling() throws {
  // 0.39 · 9.80665^0.2 · (12 · 1²)^0.4, worked by hand.
  let reference = try #require(
    SurfMath.breakingWaveHeight(deepWaterHeightMeters: 1, periodSeconds: 12))
  #expect(abs(reference - 1.6636) < 0.0005)
  let doubledHeight = try #require(
    SurfMath.breakingWaveHeight(deepWaterHeightMeters: 2, periodSeconds: 12))
  #expect(abs(doubledHeight / reference - pow(2, 0.8)) < 1e-12)
  let doubledPeriod = try #require(
    SurfMath.breakingWaveHeight(deepWaterHeightMeters: 1, periodSeconds: 24))
  #expect(abs(doubledPeriod / reference - pow(2, 0.4)) < 1e-12)
  #expect(SurfMath.breakingWaveHeight(deepWaterHeightMeters: 0, periodSeconds: 12) == 0)
}

@Test func obliqueSwellBreaksSmallerAndBlockedSwellDoesNotBreak() throws {
  let straight = try #require(
    SurfMath.breakingWaveHeight(deepWaterHeightMeters: 1, periodSeconds: 12))
  let oblique = try #require(
    SurfMath.breakingWaveHeight(
      deepWaterHeightMeters: 1, periodSeconds: 12, incidenceDegrees: 60))
  #expect(abs(oblique / straight - pow(0.5, 0.4)) < 1e-9)
  for angle in [90.0, 135, 180] {
    #expect(
      SurfMath.breakingWaveHeight(
        deepWaterHeightMeters: 1, periodSeconds: 12, incidenceDegrees: angle) == 0)
  }
}

@Test(arguments: [
  (-1.0, 12.0, 0.0), (.nan, 12, 0), (.infinity, 12, 0), (1, 0, 0), (1, -5, 0), (1, .nan, 0),
  (1, 12, -1), (1, 12, 181), (1, 12, .nan), (1e200, 1e200, 0),
])
func breakerHeightRejectsInvalidInput(_ height: Double, _ period: Double, _ angle: Double) {
  #expect(
    SurfMath.breakingWaveHeight(
      deepWaterHeightMeters: height, periodSeconds: period, incidenceDegrees: angle) == nil)
}

@Test func incidenceAngleWrapsAroundNorth() {
  #expect(SurfMath.incidenceAngle(from: 350, oceanwardBearing: 10) == 20)
  #expect(SurfMath.incidenceAngle(from: 10, oceanwardBearing: 350) == 20)
  #expect(SurfMath.incidenceAngle(from: 90, oceanwardBearing: 270) == 180)
  #expect(SurfMath.incidenceAngle(from: -90, oceanwardBearing: 630) == 0)
  #expect(SurfMath.incidenceAngle(from: .nan, oceanwardBearing: 0) == nil)
  #expect(SurfMath.incidenceAngle(from: 0, oceanwardBearing: .infinity) == nil)
}

@Test func exposureCanChangeWhichSwellBreaksLargest() throws {
  let straightOn = Swell(heightMeters: 1, periodSeconds: 11, directionDegrees: 200)
  let glancing = Swell(heightMeters: 1.5, periodSeconds: 8, directionDegrees: 285)
  #expect(SurfMath.dominantSwell(primary: straightOn, secondary: glancing) == glancing)

  let open = try #require(SurfMath.breakingWave(primary: straightOn, secondary: glancing))
  #expect(open.swell == glancing)
  #expect(open.incidenceDegrees == nil)

  let atBeach = try #require(
    SurfMath.breakingWave(primary: straightOn, secondary: glancing, oceanwardBearing: 210))
  #expect(atBeach.swell == straightOn)
  #expect(atBeach.incidenceDegrees == 10)
  #expect(atBeach.heightMeters < open.heightMeters)

  // Both components come from behind the land: an estimate of zero, not a missing value.
  let blocked = try #require(
    SurfMath.breakingWave(primary: straightOn, secondary: glancing, oceanwardBearing: 60))
  #expect(blocked.heightMeters == 0)
  #expect(blocked.swell == straightOn)
}

@Test func unknownSwellDirectionNeverLowersTheEstimate() throws {
  let noDirection = Swell(heightMeters: 1, periodSeconds: 12)
  let open = try #require(SurfMath.breakingWave(primary: noDirection, secondary: Swell()))
  // With a bearing, a component whose direction is unknown is estimated straight on.
  let atBeach = try #require(
    SurfMath.breakingWave(primary: noDirection, secondary: Swell(), oceanwardBearing: 90))
  #expect(atBeach.heightMeters == open.heightMeters)
  #expect(atBeach.incidenceDegrees == nil)

  // A large swell without a direction must not be hidden behind a small one that has one.
  let large = Swell(heightMeters: 3, periodSeconds: 14)
  let small = Swell(heightMeters: 0.5, periodSeconds: 8, directionDegrees: 90)
  let mixed = try #require(
    SurfMath.breakingWave(primary: large, secondary: small, oceanwardBearing: 90))
  #expect(mixed.swell == large)
  #expect(mixed.incidenceDegrees == nil)
  let reversed = try #require(
    SurfMath.breakingWave(primary: small, secondary: large, oceanwardBearing: 90))
  #expect(reversed.swell == large)

  // A non-finite direction counts as unknown, not as a reason to drop the component.
  let unusable = Swell(heightMeters: 1, periodSeconds: 12, directionDegrees: .nan)
  let fallback = try #require(
    SurfMath.breakingWave(primary: unusable, secondary: Swell(), oceanwardBearing: 90))
  #expect(fallback.heightMeters == open.heightMeters)
  #expect(fallback.incidenceDegrees == nil)
}

@Test func breakerEstimateNeedsHeightPeriodAndAUsableBearing() {
  #expect(SurfMath.breakingWave(primary: Swell(heightMeters: 1), secondary: Swell()) == nil)
  #expect(SurfMath.breakingWave(primary: Swell(periodSeconds: 12), secondary: Swell()) == nil)
  let complete = Swell(heightMeters: 1, periodSeconds: 12, directionDegrees: 90)
  #expect(
    SurfMath.breakingWave(primary: complete, secondary: Swell(), oceanwardBearing: .nan) == nil)
}

@Test func spotValidatesNormalizesAndRoundTrips() throws {
  let coordinate = try Coordinate(latitude: 40, longitude: -73)
  let spot = try SurfSpot(name: "Synthetic Beach", coordinate: coordinate, oceanwardBearing: -150)
  #expect(spot.oceanwardBearing == 210)
  #expect(
    try JSONDecoder().decode(SurfSpot.self, from: JSONEncoder().encode(spot)) == spot)
  #expect(throws: ForecastValidationError.invalidBearing) {
    try SurfSpot(name: "Bad", coordinate: coordinate, oceanwardBearing: .nan)
  }
  let invalid = #"{"name":"Bad","coordinate":{"latitude":95,"longitude":0},"oceanwardBearing":0}"#
  #expect(throws: ForecastValidationError.invalidCoordinate) {
    try JSONDecoder().decode(SurfSpot.self, from: Data(invalid.utf8))
  }
  let spotQuery = try ForecastQuery(spot: spot, start: epoch, end: epoch.addingTimeInterval(3600))
  #expect(spotQuery.coordinate == coordinate)
  #expect(spotQuery.datum == .meanSeaLevel)
}

@Test func summaryReportsBreakersForTheSpotAndTheNearTermRange() throws {
  let spot = try SurfSpot(
    name: "Synthetic Beach", coordinate: Coordinate(latitude: 40, longitude: -73),
    oceanwardBearing: 180)
  func hour(_ offset: TimeInterval, height: Double, from direction: Double) -> ForecastHour {
    ForecastHour(
      time: epoch.addingTimeInterval(offset), waveHeightMeters: 1,
      primarySwell: Swell(heightMeters: height, periodSeconds: 12, directionDegrees: direction),
      windDirectionDegrees: 0)
  }
  let forecast = SurfForecast(
    query: try ForecastQuery(spot: spot, start: epoch, end: epoch.addingTimeInterval(86400)),
    source: "synthetic",
    hours: [
      hour(0, height: 1, from: 180), hour(3600, height: 2, from: 180),
      hour(7200, height: 1, from: 240), hour(10800, height: 9, from: 180),
    ])
  let summary = try #require(SurfSummary(forecast: forecast, at: epoch, spot: spot))
  let current = try #require(summary.breakingWave)
  let straight = try #require(
    SurfMath.breakingWaveHeight(deepWaterHeightMeters: 1, periodSeconds: 12))
  #expect(current.heightMeters == straight)
  #expect(current.incidenceDegrees == 0)
  #expect(summary.windOrientation == .offshore)
  // Lowest is the oblique third hour, highest the second; the fourth hour is outside the range.
  let range = try #require(summary.nearTermBreakingWaveHeightMeters)
  #expect(abs(range.lowerBound - straight * pow(0.5, 0.4)) < 1e-9)
  #expect(abs(range.upperBound - straight * pow(2, 0.8)) < 1e-9)

  // Without a spot the same forecast is estimated as if every swell arrived straight on.
  let open = try #require(SurfSummary(forecast: forecast, at: epoch))
  #expect(open.breakingWave?.incidenceDegrees == nil)
  #expect(open.nearTermBreakingWaveHeightMeters?.lowerBound == straight)
  #expect(open.windOrientation == nil)

  // Hours without swell components leave the estimate unknown instead of zero.
  let bare = SurfForecast(
    query: forecast.query, source: "synthetic",
    hours: [ForecastHour(time: epoch, waveHeightMeters: 1)])
  let bareSummary = try #require(SurfSummary(forecast: bare, at: epoch, spot: spot))
  #expect(bareSummary.breakingWave == nil)
  #expect(bareSummary.nearTermBreakingWaveHeightMeters == nil)
}

@Test func nextTideIsTheFirstExtremeStrictlyAfterTheSummaryTime() throws {
  let forecast = SurfForecast(
    query: try query(), source: "synthetic",
    hours: (0..<4).map {
      ForecastHour(time: epoch.addingTimeInterval(Double($0) * 3600), waveHeightMeters: 1)
    },
    tideExtremes: [
      TideExtreme(time: epoch.addingTimeInterval(7200), kind: .high, heightMeters: 1),
      TideExtreme(time: epoch.addingTimeInterval(-3600), kind: .high),
      TideExtreme(time: epoch.addingTimeInterval(3600), kind: .low, heightMeters: -0.5),
    ])
  let first = try #require(SurfSummary(forecast: forecast, at: epoch))
  #expect(first.nextTide?.kind == .low)
  #expect(first.nextTide?.time == epoch.addingTimeInterval(3600))
  // An extreme at exactly the summary time has already happened.
  let atLow = try #require(SurfSummary(forecast: forecast, at: epoch.addingTimeInterval(3600)))
  #expect(atLow.nextTide?.kind == .high)
  let afterAll = try #require(SurfSummary(forecast: forecast, at: epoch.addingTimeInterval(7200)))
  #expect(afterAll.nextTide == nil)
}

@Test func tideTrendReportsFallingAndSteadyWater() {
  let time = epoch.addingTimeInterval(1800)
  func trend(to height: Double) -> TideTrend? {
    SurfMath.tideTrend(
      at: time,
      levels: [
        TideLevel(time: epoch, heightMeters: 1),
        TideLevel(time: epoch.addingTimeInterval(3600), heightMeters: height),
      ])
  }
  #expect(trend(to: 0.5) == .falling)
  #expect(trend(to: 1.5) == .rising)
  // Less than 0.02 m per hour in either direction counts as steady.
  #expect(trend(to: 1.01) == .steady)
  #expect(trend(to: 0.99) == .steady)
  #expect(trend(to: 1) == .steady)
}

@Test(arguments: [0, -5])
func cacheCapacityNeverDropsBelowOneEntry(_ capacity: Int) async throws {
  let cache = ForecastCache(capacity: capacity)
  let first = try query()
  let second = try query(latitude: 41)
  await cache.insert(SurfForecast(query: first, source: "test", hours: []), fetchedAt: epoch)
  #expect(await cache.entry(for: first) != nil)
  await cache.insert(SurfForecast(query: second, source: "test", hours: []), fetchedAt: epoch)
  #expect(await cache.entry(for: first) == nil)
  #expect(await cache.entry(for: second) != nil)
}

@Test func validationErrorsExplainThemselves() {
  for error in [
    ForecastValidationError.invalidCoordinate, .invalidTimeRange, .invalidBearing,
  ] {
    #expect(error.errorDescription?.isEmpty == false)
  }
  #expect(ForecastValidationError.invalidBearing.localizedDescription.contains("bearing"))
}
