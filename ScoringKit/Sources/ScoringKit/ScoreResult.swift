import Foundation

public enum ScoreKind: String, Sendable, Equatable, Codable { case readiness, sleep, load }
public enum ScoreStatus: String, Sendable, Equatable, Codable {
  case available, provisional, unavailable
}
/// Display ranges for bounded Readiness and Garmin Sleep values. Native Load has no band.
public enum ScoreBand: String, Sendable, Equatable, Codable { case lower, middle, upper }

public struct ScoreIssue: Sendable, Equatable, Codable {
  public let metric: ScoringMetricKind?
  public let reason: ScoringMissingReason

  public init(metric: ScoringMetricKind?, reason: ScoringMissingReason) {
    self.metric = metric
    self.reason = reason
  }
}

public enum ScoreComponentKind: String, Sendable, Equatable, Codable {
  case hrvDeviation, restingHeartRateDeviation, sleepDurationRatio, sleepEfficiency, dailyLoad
}

public struct ScoreComponent: Sendable, Equatable, Codable {
  public let kind: ScoreComponentKind
  public let inputs: [ScoringMetricKind: ScoringMetric]
  /// Bounded deviation, ratio, efficiency or the native daily load, as identified by kind.
  public let value: Double?
  public let issues: [ScoreIssue]
}

public struct ScoreResult: Sendable, Equatable, Codable {
  public let date: ScoringDate
  public let kind: ScoreKind
  public let value: Double?
  public let status: ScoreStatus
  public let band: ScoreBand?
  public let components: [ScoreComponent]
  public let primaryInput: ScoringMetric?
  public let baselines: [ScoringMetricKind: BaselineSummary]
  public let issues: [ScoreIssue]
  public let config: ScoringConfig

  init(
    day: ScoringDayInput, kind: ScoreKind, value: Double?, provisional: Bool,
    components: [ScoreComponent], baselines: [ScoringMetricKind: BaselineSummary] = [:],
    issues: [ScoreIssue], config: ScoringConfig, primaryInput: ScoringMetric? = nil
  ) {
    date = day.date
    self.kind = kind
    self.components = components
    self.primaryInput = primaryInput
    self.baselines = baselines
    self.config = config
    var problems = issues
    if let value, !value.isFinite {
      problems.append(ScoreIssue(metric: nil, reason: .invalidValue))
    }
    self.issues = problems
    if let value, value.isFinite, problems.isEmpty {
      let score = kind == .sleep ? value : config.clamp(value)
      self.value = score
      status = provisional ? .provisional : .available
      let bands = config.bands(for: kind)
      band =
        score >= bands.upperStartsAt ? .upper : score >= bands.middleStartsAt ? .middle : .lower
    } else {
      self.value = nil
      status = .unavailable
      band = nil
    }
  }
}
