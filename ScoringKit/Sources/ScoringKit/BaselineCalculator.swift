import Foundation

public struct BaselineObservation: Sendable, Equatable, Codable {
  public let date: ScoringDate
  public let input: ScoringMetric
  public let transformedValue: Double
}

public struct BaselineSummary: Sendable, Equatable, Codable {
  public let metric: ScoringMetricKind
  public let windowStart: ScoringDate?
  public let endExclusive: ScoringDate
  public let requiredSampleCount: Int
  public let observations: [BaselineObservation]
  /// Duplicate labels are excluded rather than double counted or chosen by input order.
  public let duplicateDates: [ScoringDate]
  public let transform: ScoringTransform
  public let median: Double?
  public let medianAbsoluteDeviation: Double?
  public let scaledMAD: Double?
  public let mean: Double?
  public let reason: ScoringMissingReason?

  public var sampleCount: Int { observations.count }
}

public enum BaselineCalculator {
  public static func calculate(
    metric: ScoringMetricKind, before date: ScoringDate, history: [ScoringDayInput],
    config: ScoringConfig = .v1
  ) -> BaselineSummary {
    let start = date.adding(days: -config.baselineWindowDays)
    let transform: ScoringTransform
    switch metric {
    case .nightlyHRVMilliseconds: transform = config.hrvTransform
    case .restingHeartRateBPM: transform = config.restingHeartRateTransform
    default: transform = .identity
    }
    let inWindow = history.filter { day in
      guard let start else { return false }
      return day.date >= start && day.date < date
    }
    let groups = Dictionary(grouping: inWindow, by: \.date)
    let duplicates = groups.filter { $0.value.count > 1 }.keys.sorted()
    let observations = groups.compactMap { date, days -> BaselineObservation? in
      guard days.count == 1, let day = days.first,
        day[metric].problem(for: metric, allowPartial: false) == nil,
        let raw = day[metric].value, let value = transform.apply(raw)
      else { return nil }
      return BaselineObservation(date: date, input: day[metric], transformedValue: value)
    }.sorted { $0.date < $1.date }
    let values = observations.map(\.transformedValue)
    let median = medianValue(values)
    let deviations = median.map { center in values.map { abs($0 - center) } } ?? []
    let mad = medianValue(deviations)
    let scaled = mad.map { $0 * config.madScale }
    // Divide before summing to avoid overflowing a finite collection's mean.
    let mean = values.isEmpty ? nil : values.reduce(0) { $0 + $1 / Double(values.count) }
    let finite = [median, mad, scaled, mean].compactMap { $0 }.allSatisfy(\.isFinite)
    let reason: ScoringMissingReason? =
      start == nil || !finite
      ? .invalidValue
      : observations.count < config.minimumBaselineSamples ? .insufficientHistory : nil
    return BaselineSummary(
      metric: metric, windowStart: start, endExclusive: date,
      requiredSampleCount: config.minimumBaselineSamples, observations: observations,
      duplicateDates: duplicates, transform: transform,
      median: finite ? median : nil, medianAbsoluteDeviation: finite ? mad : nil,
      scaledMAD: finite ? scaled : nil, mean: finite ? mean : nil, reason: reason)
  }

  private static func medianValue(_ values: [Double]) -> Double? {
    guard !values.isEmpty else { return nil }
    let sorted = values.sorted()
    let middle = sorted.count / 2
    return sorted.count.isMultiple(of: 2)
      ? sorted[middle - 1] / 2 + sorted[middle] / 2 : sorted[middle]
  }
}
