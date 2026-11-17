import Foundation

/// One historical seven-calendar-day mean, including all original inputs and exclusions.
public struct ReadinessV2RollingWindow: Sendable, Equatable, Codable {
  public let windowStart: ScoringDate
  public let endInclusive: ScoringDate
  public let requiredSampleCount: Int
  public let observations: [BaselineObservation]
  public let exclusions: [ReadinessV2Exclusion]
  public let mean: Double?
  public let reason: ScoringMissingReason?
  public var sampleCount: Int { observations.count }
}

public struct ReadinessV2RollingReference: Sendable, Equatable, Codable {
  public let metric: ScoringMetricKind
  public let windowStart: ScoringDate?
  public let endExclusive: ScoringDate
  public let requiredSampleCount: Int
  /// Includes rejected windows, rather than silently dropping their evidence.
  public let windows: [ReadinessV2RollingWindow]
  public let mean: Double?
  public let sampleSD: Double?
  public let reason: ScoringMissingReason?
  public var displayMean: Double? {
    guard reason == nil, let mean else { return nil }
    return metric == .nightlyHRVMilliseconds ? exp(mean) : mean
  }
  public var observations: [ReadinessV2RollingWindow] { windows.filter { $0.reason == nil } }
  public var sampleCount: Int { observations.count }
}

public struct ReadinessV2SleepReference: Sendable, Equatable, Codable {
  public let windowStart: ScoringDate?
  public let endExclusive: ScoringDate
  public let windowNightCount: Int
  public let requiredSampleCount: Int
  public let windows: [ReadinessV2Sleep]
  /// Descriptive only. Sleep deviations are centered on need, adequacy 1, never this mean.
  public let mean: Double?
  public let sampleSD: Double?
  public let reason: ScoringMissingReason?
  public var observations: [ReadinessV2Sleep] { windows.filter { $0.adequacy != nil } }
  public var sampleCount: Int { observations.count }
}

public struct ReadinessV2ScaleEvidence: Sendable, Equatable, Codable {
  public let hrvTrendReference: ReadinessV2RollingReference
  public let rhrTrendReference: ReadinessV2RollingReference
  public let acuteSleep: ReadinessV2Sleep
  public let acuteSleepReference: ReadinessV2SleepReference
  public let historySleepReference: ReadinessV2SleepReference
}

enum ReadinessV2ScaleContext {
  static func calculate(
    day: ScoringDayInput, history: [ScoringDayInput], config: ReadinessV2Config
  ) -> ReadinessV2Context {
    let hrv = ReadinessBaseline.calculate(
      metric: .nightlyHRVMilliseconds, before: day.date, history: history, config: config)
    let heart = ReadinessBaseline.calculate(
      metric: .restingHeartRateBPM, before: day.date, history: history, config: config)
    let candidates = ReadinessV2Window.currentCandidates(day: day, history: history)
    let ambiguous = candidates.filter { $0.date == day.date }.count > 1
    let groups = Dictionary(grouping: history.filter { $0.date < day.date }, by: \.date)
    // Collect each historical night once. Exact-three windows reuse these source-bearing nights.
    let nights = (1...config.referenceWindowDays).reversed().compactMap { offset in
      day.date.adding(days: -offset).flatMap { label in
        ReadinessV2Context.sleep(
          date: label, candidates: groups[label] ?? [], config: config, nightCount: 1
        ).latestNight
      }
    }
    let hrvReference = rollingReference(hrv, config: config)
    let rhrReference = rollingReference(heart, config: config)
    return ReadinessV2Context(
      date: day.date,
      latestHRV: ReadinessV2Context.reading(
        day: day, reference: hrv, allowPartial: false, ambiguous: ambiguous),
      hrvTrend: ReadinessV2Context.trend(
        date: day.date, reference: hrv, candidates: candidates, config: config,
        rollingReference: hrvReference),
      restingHeartRate: ReadinessV2Context.reading(
        day: day, reference: heart, allowPartial: true, ambiguous: ambiguous),
      restingHeartRateTrend: ReadinessV2Context.trend(
        date: day.date, reference: heart, candidates: candidates, config: config,
        rollingReference: rhrReference),
      sleep: ReadinessV2Context.sleep(date: day.date, candidates: candidates, config: config),
      scaleEvidence: ReadinessV2ScaleEvidence(
        hrvTrendReference: hrvReference, rhrTrendReference: rhrReference,
        acuteSleep: ReadinessV2Context.sleep(
          date: day.date, candidates: candidates, config: config, nightCount: 1),
        acuteSleepReference: sleepReference(nights, date: day.date, count: 1, config: config),
        historySleepReference: sleepReference(
          nights, date: day.date, count: config.sleepWindowDays, config: config)))
  }

  private static func rollingReference(_ daily: ReadinessBaseline, config: ReadinessV2Config)
    -> ReadinessV2RollingReference
  {
    let observations = Dictionary(uniqueKeysWithValues: daily.observations.map { ($0.date, $0) })
    let exclusions = Dictionary(uniqueKeysWithValues: daily.exclusions.map { ($0.date, $0) })
    var windows: [ReadinessV2RollingWindow] = []
    for offset in (1...(config.referenceWindowDays - config.trendWindowDays + 1)).reversed() {
      guard let end = daily.endExclusive.adding(days: -offset),
        let start = end.adding(days: 1 - config.trendWindowDays)
      else { continue }
      let labels = (0..<config.trendWindowDays).compactMap { start.adding(days: $0) }
      let inputs = labels.compactMap { observations[$0] }
      let mean = ReadinessV2Window.mean(inputs.map(\.transformedValue))
      let reason: ScoringMissingReason? =
        inputs.count < config.minimumTrendSamples
        ? .insufficientHistory
        : mean?.isFinite != true ? .invalidValue : nil
      windows.append(
        ReadinessV2RollingWindow(
          windowStart: start, endInclusive: end, requiredSampleCount: config.minimumTrendSamples,
          observations: inputs, exclusions: labels.compactMap { exclusions[$0] },
          mean: reason == nil ? mean : nil, reason: reason))
    }
    let statistics = statistics(windows.compactMap(\.mean), config: config)
    return ReadinessV2RollingReference(
      metric: daily.metric, windowStart: daily.windowStart, endExclusive: daily.endExclusive,
      requiredSampleCount: config.minimumReferenceSamples, windows: windows,
      mean: statistics.mean, sampleSD: statistics.sd, reason: statistics.reason)
  }

  private static func sleepReference(
    _ nights: [ReadinessV2SleepNight], date: ScoringDate, count: Int, config: ReadinessV2Config
  ) -> ReadinessV2SleepReference {
    var windows: [ReadinessV2Sleep] = []
    if nights.count >= count {
      for index in (count - 1)..<nights.count {
        let members = Array(nights[(index + 1 - count)...index])
        var issues = members.flatMap(\.issues)
        var adequacy: Double?
        if issues.isEmpty {
          let duration = members.compactMap { $0.duration.value }.reduce(0, +)
          let need = members.compactMap { $0.need.value }.reduce(0, +)
          let ratio = duration / need
          if duration.isFinite, need.isFinite, ratio.isFinite {
            adequacy = ratio
          } else {
            issues.append(ScoreIssue(metric: .sleepSeconds, reason: .invalidValue))
          }
        }
        windows.append(
          ReadinessV2Sleep(
            windowStart: members.first?.date, endInclusive: nights[index].date,
            requiredNightCount: count, nights: members, adequacy: adequacy, issues: issues))
      }
    }
    let statistics = statistics(windows.compactMap(\.adequacy), config: config)
    return ReadinessV2SleepReference(
      windowStart: date.adding(days: -config.referenceWindowDays), endExclusive: date,
      windowNightCount: count, requiredSampleCount: config.minimumReferenceSamples,
      windows: windows, mean: statistics.mean, sampleSD: statistics.sd, reason: statistics.reason)
  }

  static func statistics(_ values: [Double], config: ReadinessV2Config)
    -> (mean: Double?, sd: Double?, reason: ScoringMissingReason?)
  {
    let mean = ReadinessV2Window.mean(values)
    let sd = mean.flatMap { center -> Double? in
      guard values.count > 1 else { return nil }
      return sqrt(values.reduce(0) { $0 + pow($1 - center, 2) / Double(values.count - 1) })
    }
    let finite = [mean, sd].compactMap { $0 }.allSatisfy(\.isFinite)
    let reason: ScoringMissingReason? =
      !finite
      ? .invalidValue : values.count < config.minimumReferenceSamples ? .insufficientHistory : nil
    return (finite ? mean : nil, finite ? sd : nil, reason)
  }
}
