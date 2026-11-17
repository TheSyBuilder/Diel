import Foundation

/// A latest reading and its independently available prior reference, in the metric's raw units.
public struct ReadinessReading: Sendable, Equatable, Codable {
  public let date: ScoringDate
  public let input: ScoringMetric
  public let value: Double?
  public let status: ScoreStatus
  public let reason: ScoringMissingReason?
  public let reference: BaselineSummary
  public let referenceValue: Double?
  public let difference: Double?
}

/// Geometric mean of complete, recorded HRV nights in an inclusive calendar window.
public struct ReadinessHRVTrend: Sendable, Equatable, Codable {
  public let windowStart: ScoringDate?
  public let endInclusive: ScoringDate
  public let requiredSampleCount: Int
  public let observations: [BaselineObservation]
  public let duplicateDates: [ScoringDate]
  public let value: Double?
  public let reason: ScoringMissingReason?
  public let referenceValue: Double?
  public let difference: Double?

  public var sampleCount: Int { observations.count }
}

/// Always-present slots. A historical trend never supplies a missing latest night.
public struct ReadinessContext: Sendable, Equatable, Codable {
  public let date: ScoringDate
  /// Latest night and reference in milliseconds, never substituted with the trend.
  public let latestHRV: ReadinessReading
  /// Geometric mean, reference and difference in milliseconds.
  public let hrvTrend: ReadinessHRVTrend
  /// Latest resting heart rate, reference and difference in beats per minute.
  public let restingHeartRate: ReadinessReading

  public static func calculate(
    day: ScoringDayInput, history: [ScoringDayInput], config: ScoringConfig = .v1
  ) -> Self {
    let hrv = BaselineCalculator.calculate(
      metric: .nightlyHRVMilliseconds, before: day.date, history: history, config: config)
    let heart = BaselineCalculator.calculate(
      metric: .restingHeartRateBPM, before: day.date, history: history, config: config)
    // A single identical history copy is the caller's usual all-days collection.
    // Conflicting or repeated current labels are ambiguous, just like prior duplicates.
    let sameDate = history.filter { $0.date == day.date }
    let ambiguous = sameDate.count > 1 || sameDate.first.map { $0 != day } == true
    let latest = reading(
      day: day, metric: .nightlyHRVMilliseconds, reference: hrv, allowPartial: false,
      ambiguous: ambiguous)
    let resting = reading(
      day: day, metric: .restingHeartRateBPM, reference: heart, allowPartial: true,
      ambiguous: ambiguous)
    let start = day.date.adding(days: 1 - config.hrvTrendWindowDays)
    var candidates = history.filter { candidate in
      start.map { candidate.date >= $0 && candidate.date < day.date } ?? false
    }
    candidates += ambiguous ? sameDate + [day] : [day]
    let groups = Dictionary(grouping: candidates, by: \.date)
    let duplicates = groups.filter { $0.value.count > 1 }.keys.sorted()
    let observations = groups.compactMap { date, days -> BaselineObservation? in
      guard days.count == 1, let candidate = days.first,
        candidate.nightlyHRVMilliseconds.problem(
          for: .nightlyHRVMilliseconds, allowPartial: false) == nil,
        let raw = candidate.nightlyHRVMilliseconds.value
      else { return nil }
      return BaselineObservation(
        date: date, input: candidate.nightlyHRVMilliseconds, transformedValue: log(raw))
    }.sorted { $0.date < $1.date }
    let geometric =
      observations.isEmpty
      ? nil
      : exp(
        observations.reduce(0) { $0 + $1.transformedValue / Double(observations.count) })
    let reason: ScoringMissingReason? =
      start == nil || geometric.map({ !$0.isFinite }) == true
      ? .invalidValue
      : observations.count < config.minimumHRVTrendSamples ? .insufficientHistory : nil
    let value = reason == nil ? geometric : nil
    return Self(
      date: day.date, latestHRV: latest,
      hrvTrend: ReadinessHRVTrend(
        windowStart: start, endInclusive: day.date,
        requiredSampleCount: config.minimumHRVTrendSamples, observations: observations,
        duplicateDates: duplicates, value: value, reason: reason,
        referenceValue: latest.referenceValue,
        difference: value.flatMap { current in latest.referenceValue.map { current - $0 } }),
      restingHeartRate: resting)
  }

  private static func reading(
    day: ScoringDayInput, metric: ScoringMetricKind, reference: BaselineSummary,
    allowPartial: Bool, ambiguous: Bool
  ) -> ReadinessReading {
    let input = day[metric]
    let reason =
      ambiguous
      ? ScoringMissingReason.duplicateDay
      : input.problem(for: metric, allowPartial: allowPartial)
    let value = reason == nil ? input.value : nil
    let referenceValue: Double? =
      reference.reason == nil
      ? reference.median.map { reference.transform == .naturalLog ? exp($0) : $0 } : nil
    return ReadinessReading(
      date: day.date, input: input, value: value,
      status: value == nil ? .unavailable : input.coverage == .partial ? .provisional : .available,
      reason: reason, reference: reference, referenceValue: referenceValue,
      difference: value.flatMap { current in referenceValue.map { current - $0 } })
  }
}
