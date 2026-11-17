import Foundation

/// Fixed contributor order is also the tie-break order for why-lines.
public enum ReadinessV2ComponentKind: String, Sendable, Equatable, CaseIterable, Codable {
  case hrvTrend, hrvAcute, restingHeartRate, sleep, sleepAcute, sleepHistory
}

public struct ReadinessV2Deviation: Sendable, Equatable, Codable {
  /// Standardized favorable-direction deviation before clipping. Sleep uses deficit units.
  public let rawValue: Double?
  public let value: Double?
  public let issues: [ScoreIssue]
  public var wasClipped: Bool {
    guard let rawValue, let value else { return false }
    return rawValue != value
  }
}

public struct ReadinessV2Subterm: Sendable, Equatable, Codable {
  public enum Kind: String, Sendable, Equatable, Codable { case trend, acute }
  public let kind: Kind
  public let share: Double
  public let deviation: ReadinessV2Deviation
}

public struct ReadinessV2Component: Sendable, Equatable, Codable {
  public let kind: ReadinessV2ComponentKind
  public let weight: Double
  public let deviation: ReadinessV2Deviation
  public let subterms: [ReadinessV2Subterm]
  /// Score points before the final score bound. Nil on the frozen v2 control.
  public var pointContribution: Double? = nil
  /// Contribution to Q, before the gain is applied. RHR aggregates its clipped subterms first.
  public var weightedContribution: Double? { deviation.value.map { weight * $0 } }
}

public final class ReadinessV2Result: Sendable, Equatable, Codable {
  public let date: ScoringDate
  public let value: Double?
  public let status: ScoreStatus
  public let band: ScoreBand?
  public let components: [ReadinessV2Component]
  public let context: ReadinessV2Context
  public let issues: [ScoreIssue]
  public let config: ReadinessV2Config
  public let why: ReadinessV2Why
  public var version: String { config.version }
  public var unclampedValue: Double? {
    weightedDeviation.map { config.center + config.gain * $0 / config.normalizer }
  }
  public var finalClampAdjustment: Double? {
    guard let value, let unclampedValue else { return nil }
    return value - unclampedValue
  }
  public var roundedValue: Double? { value?.rounded() }
  public var weightedDeviation: Double? {
    guard components.allSatisfy({ $0.weightedContribution != nil }) else { return nil }
    return components.compactMap(\.weightedContribution).reduce(0, +)
  }

  init(
    date: ScoringDate,
    value: Double? = nil,
    status: ScoreStatus,
    band: ScoreBand? = nil,
    components: [ReadinessV2Component],
    context: ReadinessV2Context,
    issues: [ScoreIssue],
    config: ReadinessV2Config,
    why: ReadinessV2Why
  ) {
    self.date = date
    self.value = value
    self.status = status
    self.band = band
    self.components = components
    self.context = context
    self.issues = issues
    self.config = config
    self.why = why
  }

  public static func == (lhs: ReadinessV2Result, rhs: ReadinessV2Result) -> Bool {
    lhs === rhs
      || (lhs.date == rhs.date
        && lhs.value == rhs.value
        && lhs.status == rhs.status
        && lhs.band == rhs.band
        && lhs.components == rhs.components
        && lhs.context == rhs.context
        && lhs.issues == rhs.issues
        && lhs.config == rhs.config
        && lhs.why == rhs.why)
  }
}
