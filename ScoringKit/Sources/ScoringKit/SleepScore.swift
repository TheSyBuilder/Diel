import Foundation

public enum SleepScore {
  public static func calculate(
    day: ScoringDayInput, config: ScoringConfig = .v1
  ) -> ScoreResult {
    var durationIssues = problems(day, metrics: [.sleepSeconds, .sleepNeedSeconds])
    var efficiencyIssues = problems(day, metrics: [.sleepSeconds, .awakeSeconds])
    var ratio: Double?
    var efficiency: Double?
    if durationIssues.isEmpty, let sleep = day.sleepSeconds.value,
      let need = day.sleepNeedSeconds.value
    {
      // Compare before dividing so an extreme finite ratio cannot overflow.
      ratio = sleep >= need ? config.maximumSleepRatio : min(config.maximumSleepRatio, sleep / need)
    }
    if efficiencyIssues.isEmpty, let sleep = day.sleepSeconds.value,
      let awake = day.awakeSeconds.value
    {
      if sleep == 0, awake == 0 {
        efficiencyIssues.append(ScoreIssue(metric: .awakeSeconds, reason: .invalidValue))
      } else {
        // Equivalent to sleep / (sleep + awake), without overflowing the denominator.
        let scale = max(sleep, awake)
        let scaledSleep = sleep / scale
        efficiency = scaledSleep / (scaledSleep + awake / scale)
      }
    }
    if let ratio, !ratio.isFinite {
      durationIssues.append(ScoreIssue(metric: .sleepSeconds, reason: .invalidValue))
    }
    let components = [
      ScoreComponent(
        kind: .sleepDurationRatio,
        inputs: [.sleepSeconds: day.sleepSeconds, .sleepNeedSeconds: day.sleepNeedSeconds],
        value: ratio, issues: durationIssues),
      ScoreComponent(
        kind: .sleepEfficiency,
        inputs: [.sleepSeconds: day.sleepSeconds, .awakeSeconds: day.awakeSeconds],
        value: efficiency, issues: efficiencyIssues),
    ]
    let issues = problems(day, metrics: [.garminSleepScore])
    return ScoreResult(
      day: day, kind: .sleep, value: issues.isEmpty ? day.garminSleepScore.value : nil,
      provisional: false, components: components,
      issues: issues, config: config, primaryInput: day.garminSleepScore)
  }

  private static func problems(_ day: ScoringDayInput, metrics: [ScoringMetricKind]) -> [ScoreIssue]
  {
    metrics.compactMap { metric in
      day[metric].problem(for: metric, allowPartial: false).map {
        ScoreIssue(metric: metric, reason: $0)
      }
    }
  }
}
