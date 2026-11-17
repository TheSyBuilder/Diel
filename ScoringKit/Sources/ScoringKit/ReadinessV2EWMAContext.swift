import Foundation

/// A complete original reading and its calendar-age weight at a specific series date.
public struct ReadinessV2EWMAObservation: Sendable, Equatable, Codable {
  public let observation: BaselineObservation
  public let ageInDays: Int
  public let weight: Double
  public let normalizedWeight: Double
}

public struct ReadinessV2EWMAPoint: Sendable, Equatable, Codable {
  /// Series sample date, distinct from each underlying observation's date.
  public let date: ScoringDate
  public let metric: ScoringMetricKind
  public let halfLifeDays: Double
  public let recentWindowStart: ScoringDate?
  public let requiredRecentSampleCount: Int
  public let recentSampleCount: Int
  public let observations: [ReadinessV2EWMAObservation]
  public let exclusions: [ReadinessV2Exclusion]
  public let numerator: Double
  public let denominator: Double
  public let transformedMean: Double?
  public let value: Double?
  public let reason: ScoringMissingReason?
}

public struct ReadinessV2EWMAReference: Sendable, Equatable, Codable {
  public let metric: ScoringMetricKind
  public let windowStart: ScoringDate?
  public let endExclusive: ScoringDate
  public let requiredSampleCount: Int
  /// Every calendar series point in the reference period, including ineligible points.
  public let points: [ReadinessV2EWMAPoint]
  public let mean: Double?
  public let sampleSD: Double?
  public let reason: ScoringMissingReason?
  public var observations: [ReadinessV2EWMAPoint] { points.filter { $0.reason == nil } }
  public var sampleCount: Int { observations.count }
  public var displayMean: Double? {
    guard reason == nil, let mean else { return nil }
    return metric == .nightlyHRVMilliseconds ? exp(mean) : mean
  }
}

/// Sleep scale is fixed need-relative units. It has no historical reference or warmup gate.
public struct ReadinessV2EWMAEvidence: Sendable, Equatable, Codable {
  public let hrvTrendReference: ReadinessV2EWMAReference
  public let rhrTrendReference: ReadinessV2EWMAReference
  public let acuteSleep: ReadinessV2Sleep
  public let sleepDeviationUnit: Double
}

/// Recurrence arithmetic is performed once per calendar date from the earliest local input.
/// Evidence retains the full causal source prefix, including inputs older than the reference.
struct ReadinessV2EWMASeries {
  let points: [ScoringDate: ReadinessV2EWMAPoint]

  init(
    metric: ScoringMetricKind, groups: [ScoringDate: [ScoringDayInput]],
    end: ScoringDate, config: ReadinessV2Config
  ) {
    guard var date = groups.keys.min(), date <= end else {
      points = [:]
      return
    }
    let transform: ScoringTransform = metric == .nightlyHRVMilliseconds ? .naturalLog : .identity
    let lambda = pow(2, -1 / config.trendHalfLifeDays)
    var denominator = 0.0
    // Centering the numerator preserves exact equality for constant inputs and the zero-SD rule.
    var anchor: Double?
    var centeredNumerator = 0.0
    var sources: [(BaselineObservation, Int)] = []
    var exclusions: [ReadinessV2Exclusion] = []
    var result: [ScoringDate: ReadinessV2EWMAPoint] = [:]
    var index = 0
    while date <= end {
      denominator *= lambda
      centeredNumerator *= lambda
      let inputs = (groups[date] ?? []).map { $0[metric] }
      let issue: ScoringMissingReason? =
        inputs.count > 1
        ? .duplicateDay
        : (inputs.first ?? .missing).problem(for: metric, allowPartial: false)
      if let issue {
        exclusions.append(
          ReadinessV2Exclusion(date: date, metric: metric, reason: issue, inputs: inputs))
      } else if let input = inputs.first, let raw = input.value,
        let value = transform.apply(raw)
      {
        if anchor == nil { anchor = value }
        denominator += 1
        centeredNumerator += value - anchor!
        sources.append(
          (BaselineObservation(date: date, input: input, transformedValue: value), index))
      }
      let recent = sources.filter { index - $0.1 < config.trendWindowDays }.count
      let mean = anchor.map { $0 + centeredNumerator / denominator }
      let display = mean.map { transform == .naturalLog ? exp($0) : $0 }
      let reason: ScoringMissingReason? =
        recent < config.minimumTrendSamples
        ? .insufficientHistory
        : mean?.isFinite != true || display?.isFinite != true ? .invalidValue : nil
      let weighted = sources.map { source, sourceIndex in
        let age = index - sourceIndex
        let weight = pow(2, -Double(age) / config.trendHalfLifeDays)
        return ReadinessV2EWMAObservation(
          observation: source, ageInDays: age, weight: weight,
          normalizedWeight: weight / denominator)
      }
      result[date] = ReadinessV2EWMAPoint(
        date: date, metric: metric, halfLifeDays: config.trendHalfLifeDays,
        recentWindowStart: date.adding(days: 1 - config.trendWindowDays),
        requiredRecentSampleCount: config.minimumTrendSamples, recentSampleCount: recent,
        observations: weighted, exclusions: exclusions,
        numerator: (anchor ?? 0) * denominator + centeredNumerator, denominator: denominator,
        transformedMean: reason == nil ? mean : nil, value: reason == nil ? display : nil,
        reason: reason)
      guard let next = date.adding(days: 1) else { break }
      date = next
      index += 1
    }
    points = result
  }

  func reference(date: ScoringDate, metric: ScoringMetricKind, config: ReadinessV2Config)
    -> ReadinessV2EWMAReference
  {
    let samples = (1...config.referenceWindowDays).reversed().compactMap {
      date.adding(days: -$0).flatMap { points[$0] }
    }
    let stats = ReadinessV2ScaleContext.statistics(
      samples.compactMap(\.transformedMean), config: config)
    return ReadinessV2EWMAReference(
      metric: metric, windowStart: date.adding(days: -config.referenceWindowDays),
      endExclusive: date, requiredSampleCount: config.minimumReferenceSamples,
      points: samples, mean: stats.mean, sampleSD: stats.sd, reason: stats.reason)
  }
}
