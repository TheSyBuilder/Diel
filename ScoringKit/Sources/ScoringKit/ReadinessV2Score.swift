import Foundation

public enum ReadinessV2Score {
  public static func calculate(
    day: ScoringDayInput, history: [ScoringDayInput], config: ReadinessV2Config = .v2
  ) -> ReadinessV2Result {
    if config.isScaleRevision {
      return calculateChronologically(days: [day], history: history, config: config)[0]
    }
    let context = ReadinessV2Context.calculate(day: day, history: history, config: config)
    let hrvTrend = deviation(
      context.hrvTrend.transformedMean, reason: context.hrvTrend.reason,
      reference: context.hrvTrend.reference, reverse: false, config: config)
    let hrvAcute = deviation(
      context.latestHRV.transformedValue, reason: context.latestHRV.reason,
      reference: context.latestHRV.reference, reverse: false, config: config)
    let heartTrend = deviation(
      context.restingHeartRateTrend.transformedMean, reason: context.restingHeartRateTrend.reason,
      reference: context.restingHeartRateTrend.reference, reverse: true, config: config)
    let heartAcute = deviation(
      context.restingHeartRate.transformedValue, reason: context.restingHeartRate.reason,
      reference: context.restingHeartRate.reference, reverse: true, config: config)
    let heartIssues = heartTrend.issues + heartAcute.issues
    let heart = ReadinessV2Deviation(
      rawValue: combine(heartTrend.rawValue, heartAcute.rawValue, config: config),
      value: combine(heartTrend.value, heartAcute.value, config: config), issues: heartIssues)
    let sleepRaw = context.sleep.adequacy.map { ($0 - 1) / config.sleepDeficitPerDeviation }
    let sleep = ReadinessV2Deviation(
      rawValue: sleepRaw, value: sleepRaw.map { min(0, max(-config.maximumDeviation, $0)) },
      issues: context.sleep.issues)
    let components = [
      ReadinessV2Component(
        kind: .hrvTrend, weight: config.hrvTrendWeight, deviation: hrvTrend, subterms: []),
      ReadinessV2Component(
        kind: .hrvAcute, weight: config.hrvAcuteWeight, deviation: hrvAcute, subterms: []),
      ReadinessV2Component(
        kind: .restingHeartRate, weight: config.restingHeartRateWeight, deviation: heart,
        subterms: [
          ReadinessV2Subterm(
            kind: .trend, share: config.restingHeartRateTrendShare, deviation: heartTrend),
          ReadinessV2Subterm(
            kind: .acute, share: config.restingHeartRateAcuteShare, deviation: heartAcute),
        ]),
      ReadinessV2Component(
        kind: .sleep, weight: config.sleepWeight, deviation: sleep, subterms: []),
    ]
    var issues = components.flatMap { $0.deviation.issues }
    var value: Double?
    if issues.isEmpty, components.allSatisfy({ $0.weightedContribution != nil }) {
      let candidate =
        config.center + config.gain * components.compactMap(\.weightedContribution).reduce(0, +)
      if candidate.isFinite {
        // Protect the algebraic bounds against floating-point summation at an endpoint.
        value = min(config.reachableMaximum, max(config.conservativeMinimum, candidate))
      } else {
        issues.append(ScoreIssue(metric: nil, reason: .invalidValue))
      }
    }
    let status: ScoreStatus =
      value == nil
      ? .unavailable : context.restingHeartRate.status == .provisional ? .provisional : .available
    let band: ScoreBand? = value.map {
      $0 >= config.bands.upperStartsAt
        ? .upper : $0 >= config.bands.middleStartsAt ? .middle : .lower
    }
    return ReadinessV2Result(
      date: day.date, value: value, status: status, band: band, components: components,
      context: context, issues: issues, config: config,
      why: ReadinessV2Why.calculate(
        context: context, components: components, status: status, config: config))
  }

  static func combine(_ trend: Double?, _ acute: Double?, config: ReadinessV2Config)
    -> Double?
  {
    guard let trend, let acute else { return nil }
    return config.restingHeartRateTrendShare * trend + config.restingHeartRateAcuteShare * acute
  }

  static func deviation(
    _ current: Double?, reason: ScoringMissingReason?, reference: ReadinessBaseline,
    reverse: Bool, config: ReadinessV2Config
  ) -> ReadinessV2Deviation {
    var issues: [ScoreIssue] = []
    if let reason { issues.append(ScoreIssue(metric: reference.metric, reason: reason)) }
    if let reason = reference.reason {
      issues.append(ScoreIssue(metric: reference.metric, reason: reason))
    }
    var raw: Double?
    if issues.isEmpty, let current, let mean = reference.mean, let sd = reference.sampleSD {
      if sd == 0 {
        if current == mean {
          raw = 0
        } else {
          issues.append(ScoreIssue(metric: reference.metric, reason: .zeroDispersion))
        }
      } else {
        let difference = reverse ? mean - current : current - mean
        let ratio = difference / sd
        if difference.isFinite, !ratio.isNaN {
          raw = ratio
        } else {
          issues.append(ScoreIssue(metric: reference.metric, reason: .invalidValue))
        }
      }
    }
    return ReadinessV2Deviation(
      rawValue: raw,
      value: raw.map { min(config.maximumDeviation, max(-config.maximumDeviation, $0)) },
      issues: issues)
  }
}
