import Foundation

public struct ReadinessV2Reading: Sendable, Equatable, Codable {
  public let date: ScoringDate
  public let metric: ScoringMetricKind
  public let input: ScoringMetric
  public let value: Double?
  /// HRV is ln(Garmin lastNightAvg), not the mean of unavailable within-night log samples.
  public let transformedValue: Double?
  public let status: ScoreStatus
  public let reason: ScoringMissingReason?
  public let reference: ReadinessBaseline
  public let difference: Double?
}

public struct ReadinessV2Trend: Sendable, Equatable, Codable {
  public let metric: ScoringMetricKind
  public let windowStart: ScoringDate?
  public let endInclusive: ScoringDate
  public let requiredSampleCount: Int
  public let observations: [BaselineObservation]
  public let exclusions: [ReadinessV2Exclusion]
  /// Mean of log-nightly HRV or daily RHR, in the reference's transformed units.
  public let transformedMean: Double?
  /// exp(mean(log nightly HRV)) in ms, or mean daily RHR in bpm.
  public let value: Double?
  public let reason: ScoringMissingReason?
  public let reference: ReadinessBaseline
  public let difference: Double?
  public var rollingReference: ReadinessV2RollingReference? = nil
  /// Version 2.2 uses a causal calendar-age EWMA, never a seven-day mean.
  public var ewma: ReadinessV2EWMAPoint? = nil
  public var sampleCount: Int { observations.count }
  public var duplicateDates: [ScoringDate] {
    exclusions.filter { $0.reason == .duplicateDay }.map(\.date)
  }
}

public struct ReadinessV2SleepNight: Sendable, Equatable, Codable {
  public let date: ScoringDate
  public let duration: ScoringMetric
  /// Normalized seconds; the existing adapter infers Garmin actual minutes * 60. No nextSleepNeed.
  public let need: ScoringMetric
  public let cappedDurationSeconds: Double?
  public let issues: [ScoreIssue]
  /// Duplicate inputs are retained as exclusions, instead of choosing one silently.
  public let exclusions: [ReadinessV2Exclusion]
}

public struct ReadinessV2Sleep: Sendable, Equatable, Codable {
  public let windowStart: ScoringDate?
  public let endInclusive: ScoringDate
  public let requiredNightCount: Int
  public let nights: [ReadinessV2SleepNight]
  /// Need-weighted adequacy. Frozen v2 caps each night at need; v2.1 retains surplus.
  public let adequacy: Double?
  public let issues: [ScoreIssue]
  public var nightCount: Int { nights.filter { $0.issues.isEmpty }.count }
  public var latestNight: ReadinessV2SleepNight? { nights.last }
}

/// Independent, always-present context slots. No trend can stand in for a missing acute reading.
public struct ReadinessV2Context: Sendable, Equatable, Codable {
  /// Immutable backing keeps context copies pointer-sized while evidence setters retain value semantics.
  private var storage: Storage
  public var date: ScoringDate {
    storage.date
  }
  public var latestHRV: ReadinessV2Reading {
    storage.latestHRV
  }
  public var hrvTrend: ReadinessV2Trend {
    storage.hrvTrend
  }
  /// Garmin daily RHR proxy, not a verified overnight measurement.
  public var restingHeartRate: ReadinessV2Reading {
    storage.restingHeartRate
  }
  public var restingHeartRateTrend: ReadinessV2Trend {
    storage.restingHeartRateTrend
  }
  public var sleep: ReadinessV2Sleep {
    storage.sleep
  }
  public var scaleEvidence: ReadinessV2ScaleEvidence? {
    get { storage.scaleEvidence }
    set {
      storage = Storage(
        date: storage.date,
        latestHRV: storage.latestHRV,
        hrvTrend: storage.hrvTrend,
        restingHeartRate: storage.restingHeartRate,
        restingHeartRateTrend: storage.restingHeartRateTrend,
        sleep: storage.sleep,
        scaleEvidence: newValue,
        ewmaEvidence: storage.ewmaEvidence
      )
    }
  }
  public var ewmaEvidence: ReadinessV2EWMAEvidence? {
    get { storage.ewmaEvidence }
    set {
      storage = Storage(
        date: storage.date,
        latestHRV: storage.latestHRV,
        hrvTrend: storage.hrvTrend,
        restingHeartRate: storage.restingHeartRate,
        restingHeartRateTrend: storage.restingHeartRateTrend,
        sleep: storage.sleep,
        scaleEvidence: storage.scaleEvidence,
        ewmaEvidence: newValue
      )
    }
  }

  init(
    date: ScoringDate,
    latestHRV: ReadinessV2Reading,
    hrvTrend: ReadinessV2Trend,
    restingHeartRate: ReadinessV2Reading,
    restingHeartRateTrend: ReadinessV2Trend,
    sleep: ReadinessV2Sleep,
    scaleEvidence: ReadinessV2ScaleEvidence? = nil,
    ewmaEvidence: ReadinessV2EWMAEvidence? = nil
  ) {
    storage = Storage(
      date: date, latestHRV: latestHRV, hrvTrend: hrvTrend, restingHeartRate: restingHeartRate,
      restingHeartRateTrend: restingHeartRateTrend, sleep: sleep, scaleEvidence: scaleEvidence,
      ewmaEvidence: ewmaEvidence)
  }

  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.storage === rhs.storage || lhs.storage == rhs.storage
  }

  public init(from decoder: any Decoder) throws {
    storage = try Storage(from: decoder)
  }

  public func encode(to encoder: any Encoder) throws {
    try storage.encode(to: encoder)
  }

  private final class Storage: Sendable, Equatable, Codable {
    let date: ScoringDate
    let latestHRV: ReadinessV2Reading
    let hrvTrend: ReadinessV2Trend
    let restingHeartRate: ReadinessV2Reading
    let restingHeartRateTrend: ReadinessV2Trend
    let sleep: ReadinessV2Sleep
    let scaleEvidence: ReadinessV2ScaleEvidence?
    let ewmaEvidence: ReadinessV2EWMAEvidence?

    init(
      date: ScoringDate,
      latestHRV: ReadinessV2Reading,
      hrvTrend: ReadinessV2Trend,
      restingHeartRate: ReadinessV2Reading,
      restingHeartRateTrend: ReadinessV2Trend,
      sleep: ReadinessV2Sleep,
      scaleEvidence: ReadinessV2ScaleEvidence? = nil,
      ewmaEvidence: ReadinessV2EWMAEvidence? = nil
    ) {
      self.date = date
      self.latestHRV = latestHRV
      self.hrvTrend = hrvTrend
      self.restingHeartRate = restingHeartRate
      self.restingHeartRateTrend = restingHeartRateTrend
      self.sleep = sleep
      self.scaleEvidence = scaleEvidence
      self.ewmaEvidence = ewmaEvidence
    }

    static func == (lhs: Storage, rhs: Storage) -> Bool {
      lhs === rhs
        || (lhs.date == rhs.date
          && lhs.latestHRV == rhs.latestHRV
          && lhs.hrvTrend == rhs.hrvTrend
          && lhs.restingHeartRate == rhs.restingHeartRate
          && lhs.restingHeartRateTrend == rhs.restingHeartRateTrend
          && lhs.sleep == rhs.sleep
          && lhs.scaleEvidence == rhs.scaleEvidence
          && lhs.ewmaEvidence == rhs.ewmaEvidence)
    }
  }

  public static func calculate(
    day: ScoringDayInput, history: [ScoringDayInput], config: ReadinessV2Config = .v2
  ) -> Self {
    if config.isEWMARevision {
      return ReadinessV2EWMAScore.context(day: day, history: history, config: config)
    }
    if config.isScaleRevision {
      return ReadinessV2ScaleContext.calculate(day: day, history: history, config: config)
    }
    let hrv = ReadinessBaseline.calculate(
      metric: .nightlyHRVMilliseconds, before: day.date, history: history, config: config)
    let heart = ReadinessBaseline.calculate(
      metric: .restingHeartRateBPM, before: day.date, history: history, config: config)
    let candidates = ReadinessV2Window.currentCandidates(day: day, history: history)
    let ambiguous = candidates.filter { $0.date == day.date }.count > 1
    return Self(
      date: day.date,
      latestHRV: reading(day: day, reference: hrv, allowPartial: false, ambiguous: ambiguous),
      hrvTrend: trend(date: day.date, reference: hrv, candidates: candidates, config: config),
      restingHeartRate: reading(
        day: day, reference: heart, allowPartial: true, ambiguous: ambiguous),
      restingHeartRateTrend: trend(
        date: day.date, reference: heart, candidates: candidates, config: config),
      sleep: sleep(date: day.date, candidates: candidates, config: config))
  }

  static func reading(
    day: ScoringDayInput, reference: ReadinessBaseline, allowPartial: Bool, ambiguous: Bool
  ) -> ReadinessV2Reading {
    let input = day[reference.metric]
    let reason =
      ambiguous ? .duplicateDay : input.problem(for: reference.metric, allowPartial: allowPartial)
    let value = reason == nil ? input.value : nil
    return ReadinessV2Reading(
      date: day.date, metric: reference.metric, input: input, value: value,
      transformedValue: value.flatMap { reference.transform.apply($0) },
      status: value == nil ? .unavailable : input.coverage == .partial ? .provisional : .available,
      reason: reason, reference: reference,
      difference: value.flatMap { current in reference.displayMean.map { current - $0 } })
  }

  static func trend(
    date: ScoringDate, reference: ReadinessBaseline, candidates: [ScoringDayInput],
    config: ReadinessV2Config, rollingReference: ReadinessV2RollingReference? = nil
  ) -> ReadinessV2Trend {
    let start = date.adding(days: 1 - config.trendWindowDays)
    let window = ReadinessV2Window.collect(
      metric: reference.metric, start: start, endInclusive: date, candidates: candidates,
      transform: reference.transform)
    let mean = ReadinessV2Window.mean(window.observations.map(\.transformedValue))
    let display = mean.map { reference.transform == .naturalLog ? exp($0) : $0 }
    let reason: ScoringMissingReason? =
      start == nil || [mean, display].compactMap { $0 }.contains { !$0.isFinite }
      ? .invalidValue
      : window.observations.count < config.minimumTrendSamples ? .insufficientHistory : nil
    let value = reason == nil ? display : nil
    let referenceMean =
      rollingReference?.mean.map {
        reference.transform == .naturalLog ? exp($0) : $0
      } ?? reference.displayMean
    return ReadinessV2Trend(
      metric: reference.metric, windowStart: start, endInclusive: date,
      requiredSampleCount: config.minimumTrendSamples, observations: window.observations,
      exclusions: window.exclusions, transformedMean: reason == nil ? mean : nil, value: value,
      reason: reason, reference: reference,
      difference: value.flatMap { current in referenceMean.map { current - $0 } },
      rollingReference: rollingReference)
  }

  static func sleep(
    date: ScoringDate, candidates: [ScoringDayInput], config: ReadinessV2Config,
    nightCount: Int? = nil
  ) -> ReadinessV2Sleep {
    let count = nightCount ?? config.sleepWindowDays
    let start = date.adding(days: 1 - count)
    let groups = Dictionary(grouping: candidates, by: \.date)
    let nights = (0..<count).reversed().compactMap {
      offset -> ReadinessV2SleepNight? in
      guard let label = date.adding(days: -offset) else { return nil }
      let days = groups[label] ?? []
      let duration = days.count == 1 ? days[0].sleepSeconds : .missing
      let need = days.count == 1 ? days[0].sleepNeedSeconds : .missing
      var issues: [ScoreIssue] = []
      var exclusions: [ReadinessV2Exclusion] = []
      for metric in [ScoringMetricKind.sleepSeconds, .sleepNeedSeconds] {
        let inputs = days.map { $0[metric] }
        let reason: ScoringMissingReason? =
          days.count > 1
          ? .duplicateDay : (inputs.first ?? .missing).problem(for: metric, allowPartial: false)
        if let reason {
          issues.append(ScoreIssue(metric: metric, reason: reason))
          exclusions.append(
            ReadinessV2Exclusion(date: label, metric: metric, reason: reason, inputs: inputs))
        }
      }
      let capped = issues.isEmpty ? min(duration.value!, need.value!) : nil
      return ReadinessV2SleepNight(
        date: label, duration: duration, need: need, cappedDurationSeconds: capped,
        issues: issues, exclusions: exclusions)
    }
    var issues = nights.flatMap(\.issues)
    var adequacy: Double?
    if start == nil || nights.count != count {
      issues.append(ScoreIssue(metric: .sleepSeconds, reason: .invalidValue))
    }
    if issues.isEmpty {
      let totalNeed = nights.compactMap { $0.need.value }.reduce(0, +)
      let totalCapped =
        config.isScaleRevision
        ? nights.compactMap { $0.duration.value }.reduce(0, +)
        : nights.compactMap(\.cappedDurationSeconds).reduce(0, +)
      let ratio = totalCapped / totalNeed
      if totalNeed.isFinite, totalCapped.isFinite, ratio.isFinite {
        adequacy = ratio
      } else {
        issues.append(ScoreIssue(metric: .sleepNeedSeconds, reason: .invalidValue))
      }
    }
    return ReadinessV2Sleep(
      windowStart: start, endInclusive: date, requiredNightCount: count,
      nights: nights, adequacy: adequacy, issues: issues)
  }
}
