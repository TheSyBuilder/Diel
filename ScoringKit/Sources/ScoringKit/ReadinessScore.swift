import Foundation

public enum ReadinessScore {
  public static func calculate(
    day: ScoringDayInput, history: [ScoringDayInput], config: ScoringConfig = .v1
  ) -> ScoreResult {
    let hrv = BaselineCalculator.calculate(
      metric: .nightlyHRVMilliseconds, before: day.date, history: history, config: config)
    let heart = BaselineCalculator.calculate(
      metric: .restingHeartRateBPM, before: day.date, history: history, config: config)
    let hrvComponent = deviation(
      day.nightlyHRVMilliseconds, metric: .nightlyHRVMilliseconds, kind: .hrvDeviation,
      baseline: hrv, reverse: false, allowPartial: false, config: config)
    let heartComponent = deviation(
      day.restingHeartRateBPM, metric: .restingHeartRateBPM, kind: .restingHeartRateDeviation,
      baseline: heart, reverse: true, allowPartial: true, config: config)
    let issues = hrvComponent.issues + heartComponent.issues
    var value: Double?
    if issues.isEmpty, let hrvValue = hrvComponent.value, let heartValue = heartComponent.value {
      value =
        config.readinessCenter + config.readinessDeviationScale
        * (config.hrvWeight * hrvValue + config.restingHeartRateWeight * heartValue)
    }
    return ScoreResult(
      day: day, kind: .readiness, value: value,
      provisional: day.restingHeartRateBPM.coverage == .partial,
      components: [hrvComponent, heartComponent],
      baselines: [.nightlyHRVMilliseconds: hrv, .restingHeartRateBPM: heart], issues: issues,
      config: config)
  }

  private static func deviation(
    _ input: ScoringMetric, metric: ScoringMetricKind, kind: ScoreComponentKind,
    baseline: BaselineSummary, reverse: Bool, allowPartial: Bool, config: ScoringConfig
  ) -> ScoreComponent {
    var issues: [ScoreIssue] = []
    if let reason = input.problem(for: metric, allowPartial: allowPartial) {
      issues.append(ScoreIssue(metric: metric, reason: reason))
    }
    if let reason = baseline.reason { issues.append(ScoreIssue(metric: metric, reason: reason)) }
    var deviation: Double?
    if issues.isEmpty, let raw = input.value, let current = baseline.transform.apply(raw),
      let median = baseline.median, let dispersion = baseline.scaledMAD
    {
      if dispersion == 0 {
        // Exactly matching measured values are neutral. No epsilon or fabricated spread.
        if current == median {
          deviation = 0
        } else {
          issues.append(ScoreIssue(metric: metric, reason: .zeroDispersion))
        }
      } else {
        let difference = reverse ? median - current : current - median
        // Bound extreme ratios before storing the component.
        let limit = config.maximumDeviation
        let ratio = difference / dispersion
        deviation = min(limit, max(-limit, ratio))
        if !difference.isFinite || ratio.isNaN {
          deviation = nil
          issues.append(ScoreIssue(metric: metric, reason: .invalidValue))
        }
      }
    }
    return ScoreComponent(kind: kind, inputs: [metric: input], value: deviation, issues: issues)
  }
}
