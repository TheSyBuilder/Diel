import Foundation

/// Every excluded label keeps its reason and original inputs, including coverage and sources.
public struct ReadinessV2Exclusion: Sendable, Equatable, Codable {
  public let date: ScoringDate
  public let metric: ScoringMetricKind
  public let reason: ScoringMissingReason
  public let inputs: [ScoringMetric]
}

/// Mean and sample SD of individual log-nightly HRV or daily RHR readings. Never MAD or SEM.
public struct ReadinessBaseline: Sendable, Equatable, Codable {
  public let metric: ScoringMetricKind
  public let windowStart: ScoringDate?
  public let endExclusive: ScoringDate
  public let requiredSampleCount: Int
  public let transform: ScoringTransform
  public let observations: [BaselineObservation]
  public let exclusions: [ReadinessV2Exclusion]
  public let mean: Double?
  public let sampleSD: Double?
  public let reason: ScoringMissingReason?

  public var sampleCount: Int { observations.count }
  public var duplicateDates: [ScoringDate] {
    exclusions.filter { $0.reason == .duplicateDay }.map(\.date)
  }
  /// Geometric reference in ms for HRV, arithmetic reference in bpm for daily RHR.
  public var displayMean: Double? {
    guard reason == nil, let mean else { return nil }
    return transform == .naturalLog ? exp(mean) : mean
  }

  public static func calculate(
    metric: ScoringMetricKind, before date: ScoringDate, history: [ScoringDayInput],
    config: ReadinessV2Config = .v2
  ) -> Self {
    let start = date.adding(days: -config.referenceWindowDays)
    let transform: ScoringTransform = metric == .nightlyHRVMilliseconds ? .naturalLog : .identity
    let window = ReadinessV2Window.collect(
      metric: metric, start: start, endInclusive: date.adding(days: -1),
      candidates: history, transform: transform)
    let mean = ReadinessV2Window.mean(window.observations.map(\.transformedValue))
    let sd = mean.flatMap { center -> Double? in
      guard window.observations.count > 1 else { return nil }
      // Sample SD of individual observations, denominator n-1, with no spread floor.
      let divisor = Double(window.observations.count - 1)
      return sqrt(
        window.observations.reduce(0) { sum, item in
          let difference = item.transformedValue - center
          return sum + difference * difference / divisor
        })
    }
    let finite = [mean, sd].compactMap { $0 }.allSatisfy(\.isFinite)
    let reason: ScoringMissingReason? =
      start == nil || !finite
      ? .invalidValue
      : window.observations.count < config.minimumReferenceSamples ? .insufficientHistory : nil
    return Self(
      metric: metric, windowStart: start, endExclusive: date,
      requiredSampleCount: config.minimumReferenceSamples, transform: transform,
      observations: window.observations, exclusions: window.exclusions,
      mean: finite ? mean : nil, sampleSD: finite ? sd : nil, reason: reason)
  }
}

enum ReadinessV2Window {
  static func mean(_ values: [Double]) -> Double? {
    guard let first = values.first else { return nil }
    // Identical observations retain exact equality for the zero-SD rule.
    return first + values.reduce(0) { $0 + ($1 - first) / Double(values.count) }
  }

  static func collect(
    metric: ScoringMetricKind, start: ScoringDate?, endInclusive: ScoringDate?,
    candidates: [ScoringDayInput], transform: ScoringTransform
  ) -> (observations: [BaselineObservation], exclusions: [ReadinessV2Exclusion]) {
    guard let start, let endInclusive, start <= endInclusive else { return ([], []) }
    let groups = Dictionary(
      grouping: candidates.filter { $0.date >= start && $0.date <= endInclusive }, by: \.date)
    var observations: [BaselineObservation] = []
    var exclusions: [ReadinessV2Exclusion] = []
    var label = start
    while label <= endInclusive {
      let inputs = (groups[label] ?? []).map { $0[metric] }
      let reason: ScoringMissingReason?
      if inputs.count > 1 {
        reason = .duplicateDay
      } else if let input = inputs.first {
        reason = input.problem(for: metric, allowPartial: false)
      } else {
        reason = .missing
      }
      if let reason {
        exclusions.append(
          ReadinessV2Exclusion(date: label, metric: metric, reason: reason, inputs: inputs))
      } else if let input = inputs.first, let raw = input.value,
        let transformed = transform.apply(raw)
      {
        observations.append(
          BaselineObservation(date: label, input: input, transformedValue: transformed))
      } else {
        exclusions.append(
          ReadinessV2Exclusion(date: label, metric: metric, reason: .invalidValue, inputs: inputs))
      }
      guard let next = label.adding(days: 1) else { break }
      label = next
    }
    return (observations, exclusions)
  }

  static func currentCandidates(day: ScoringDayInput, history: [ScoringDayInput])
    -> [ScoringDayInput]
  {
    let sameDate = history.filter { $0.date == day.date }
    let ambiguous = sameDate.count > 1 || sameDate.first.map { $0 != day } == true
    return history.filter { $0.date != day.date } + (ambiguous ? sameDate + [day] : [day])
  }
}
