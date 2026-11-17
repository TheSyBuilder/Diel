import Foundation

/// Complete prior daily totals in Garmin's native load units. No minimum sample count applies.
public struct LoadReference: Sendable, Equatable, Codable {
  public let windowStart: ScoringDate?
  public let endExclusive: ScoringDate
  public let observations: [BaselineObservation]
  public let duplicateDates: [ScoringDate]
  public let maximum: Double?
  public let reason: ScoringMissingReason?

  public var sampleCount: Int { observations.count }
}

/// Load has no score band or health grade. `allDay` identifies the bounded TRIMP estimate;
/// its absence retains the legacy native activity total and independent reference ring.
public struct LoadResult: Sendable, Equatable, Codable {
  public let date: ScoringDate
  public let value: Double?
  public let status: ScoreStatus
  public let input: ScoringMetric
  public let ringFraction: Double?
  public let ringReason: ScoringMissingReason?
  public let reference: LoadReference
  public let issues: [ScoreIssue]
  public let config: ScoringConfig
  public var allDay: AllDayLoadEvidence? = nil

  public var isRestDay: Bool { value == 0 }
}
