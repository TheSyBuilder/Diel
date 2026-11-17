import Foundation

/// A measured sample's offset from the start of Garmin's recorded local day.
public struct LoadHeartRateSample: Sendable, Equatable, Codable {
  public let seconds: Double
  public let bpm: Double
  public init(seconds: Double, bpm: Double) {
    self.seconds = seconds
    self.bpm = bpm
  }
}

public struct LoadHeartRateDay: Sendable, Equatable, Codable {
  public let samples: [LoadHeartRateSample]
  public let restingHeartRate: ScoringMetric
  public let evidence: ScoringMetric
  public let elapsedSeconds: Double
  public init(
    samples: [LoadHeartRateSample], restingHeartRate: ScoringMetric,
    evidence: ScoringMetric, elapsedSeconds: Double
  ) {
    self.samples = samples
    self.restingHeartRate = restingHeartRate
    self.evidence = evidence
    self.elapsedSeconds = elapsedSeconds
  }
}

public struct AllDayLoadEvidence: Sendable, Equatable, Codable {
  public let version: String
  public let trimp: Double?
  public let maximumHeartRate: Double?
  public let maximumSources: [ScoringSource]
  public let k: Double
  public let integratedSeconds: Double
  public let comparisonMedian: Double?
  public let comparisonIsSameTime: Bool
  public let calibrationReason: ScoringMissingReason?
  /// A previously emitted score can be retained without inventing replacement HR samples.
  public var retainedMinimum: Double?
  public var retainedSources: [ScoringSource]?
}

/// Diel's all-day Banister TRIMP estimate. Garmin activity load remains a separate input.
public enum AllDayLoadScore {
  public static let version = "all-day-load-v1"
  public static let k = 500.0
  public static let gapCapSeconds = 300.0

  public static func calculate(
    day: ScoringDayInput, history: [ScoringDayInput],
    config: ScoringConfig = .v1, previous: LoadResult? = nil
  ) -> LoadResult {
    let measured = measure(day: day, history: history)
    let start = day.date.adding(days: -28)
    let prior = history.filter { candidate in
      candidate.date < day.date && start.map { candidate.date >= $0 } == true
    }
    let groups = Dictionary(grouping: prior, by: \.date)
    let unique = groups.values.compactMap { $0.count == 1 ? $0.first : nil }.sorted {
      $0.date < $1.date
    }
    let elapsed = day.heartRateDay?.elapsedSeconds ?? 86_400
    var sameTime: [Double] = []
    var observations: [BaselineObservation] = []
    for candidate in unique {
      guard let heart = candidate.heartRateDay, heart.evidence.coverage == .complete else {
        continue
      }
      let full = measure(day: candidate, history: history)
      guard full.reason == nil, let fullValue = full.value else { continue }
      let input = metric(value: fullValue, heart: heart)
      observations.append(
        BaselineObservation(date: candidate.date, input: input, transformedValue: fullValue))
      if elapsed < 86_400, heart.samples.last.map({ $0.seconds >= elapsed - gapCapSeconds }) == true
      {
        let prefix = measure(day: candidate, history: history, cutoff: elapsed)
        if prefix.reason == nil, let value = prefix.value { sameTime.append(value) }
      }
    }
    let comparisonIsSameTime = !sameTime.isEmpty
    let comparison = median(comparisonIsSameTime ? sameTime : observations.map(\.transformedValue))
    let input = day.heartRateDay.map { metric(value: measured.value, heart: $0) } ?? .missing
    var value = measured.value
    var evidence = AllDayLoadEvidence(
      version: version, trimp: measured.trimp,
      maximumHeartRate: measured.maximum, maximumSources: measured.sources, k: k,
      integratedSeconds: measured.seconds, comparisonMedian: comparison,
      comparisonIsSameTime: comparisonIsSameTime, calibrationReason: measured.reason)
    if let previous, previous.date == day.date, day.heartRateDay != nil,
      day.heartRateDay?.evidence.coverage == .partial, previous.allDay?.version == version,
      let old = previous.value,
      old > (value ?? -1)
    {
      value = old
      evidence.retainedMinimum = old
      evidence.retainedSources =
        (previous.input.sources
        + (previous.allDay?.maximumSources ?? []) + (previous.allDay?.retainedSources ?? []))
        .reduce(into: []) { sources, source in
          if !sources.contains(where: {
            $0.responseID == source.responseID && $0.family == source.family
          }) {
            sources.append(source)
          }
        }
    }
    return LoadResult(
      date: day.date, value: value,
      status: value == nil
        ? .unavailable
        : input.coverage == .complete && measured.reason == nil ? .available : .provisional,
      input: input, ringFraction: value.map { $0 / 100 }, ringReason: value == nil ? .missing : nil,
      reference: LoadReference(
        windowStart: start, endExclusive: day.date,
        observations: observations,
        duplicateDates: groups.filter { $0.value.count > 1 }.keys.sorted(),
        maximum: observations.map(\.transformedValue).max(),
        reason: comparison == nil ? .insufficientHistory : nil),
      issues: measured.reason.map { [ScoreIssue(metric: .activityLoad, reason: $0)] } ?? [],
      config: config, allDay: evidence)
  }

  private static func metric(value: Double?, heart: LoadHeartRateDay) -> ScoringMetric {
    let sources =
      heart.evidence.sources
      + heart.restingHeartRate.sources.filter { !heart.evidence.sources.contains($0) }
    return ScoringMetric(
      value: value, reason: heart.evidence.reason, coverage: heart.evidence.coverage,
      dateProvenance: heart.evidence.dateProvenance,
      sources: sources, coverageSources: heart.evidence.coverageSources)
  }

  private struct Measurement {
    var value: Double?
    var trimp: Double?
    var maximum: Double?
    var sources: [ScoringSource] = []
    var seconds = 0.0
    var reason: ScoringMissingReason?
  }

  private static func measure(
    day: ScoringDayInput, history: [ScoringDayInput], cutoff: Double? = nil
  ) -> Measurement {
    guard let heart = day.heartRateDay, (heart.evidence.value ?? 0) > 0 else {
      return Measurement(reason: .missing)
    }
    guard !heart.samples.isEmpty else {
      return Measurement(value: 0, reason: .unverifiedCoverage)
    }
    let samples = heart.samples.filter { $0.seconds <= (cutoff ?? heart.elapsedSeconds) }
    guard !samples.isEmpty else { return Measurement(reason: .missing) }
    let first = day.date.adding(days: -89)!
    // Include the displayed day only through its known cutoff. Future calendar days never qualify.
    let candidates = (history.filter { $0.date >= first && $0.date < day.date } + [day])
    var maximum: Double?
    var sources: [ScoringSource] = []
    for candidate in candidates {
      guard let data = candidate.heartRateDay else { continue }
      let points = candidate.date == day.date ? samples : data.samples
      for (left, right) in zip(points, points.dropFirst()) {
        let interval = right.seconds - left.seconds
        guard interval > 0, interval <= gapCapSeconds, abs(left.bpm - right.bpm) <= 10 else {
          continue
        }
        let supported = max(left.bpm, right.bpm)
        if supported > (maximum ?? 0) {
          maximum = supported
          sources = data.evidence.sources
        }
      }
    }
    guard let rest = heart.restingHeartRate.value, rest.isFinite, rest > 0 else {
      return Measurement(value: 0, maximum: maximum, sources: sources, reason: .missing)
    }
    guard let maximum, maximum > rest else {
      return Measurement(value: 0, maximum: maximum, sources: sources, reason: .insufficientHistory)
    }
    guard samples.count >= 2 else {
      return Measurement(value: 0, maximum: maximum, sources: sources, reason: .partial)
    }
    func rate(_ bpm: Double) -> Double {
      let reserve = min(max((bpm - rest) / (maximum - rest), 0), 1)
      return reserve * 0.64 * exp(1.92 * reserve)
    }
    var trimp = 0.0
    var seconds = 0.0
    for (left, right) in zip(samples, samples.dropFirst()) {
      let interval = min(max(right.seconds - left.seconds, 0), gapCapSeconds)
      seconds += interval
      trimp += interval / 60 * (rate(left.bpm) + rate(right.bpm)) / 2
    }
    return Measurement(
      value: (100 * (1 - exp(-trimp / k))).rounded(), trimp: trimp,
      maximum: maximum, sources: sources, seconds: seconds)
  }

  private static func median(_ values: [Double]) -> Double? {
    let sorted = values.sorted()
    guard !sorted.isEmpty else { return nil }
    let middle = sorted.count / 2
    return sorted.count.isMultiple(of: 2)
      ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
  }
}
