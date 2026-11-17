import Foundation

public enum ScoringTransform: String, Sendable, Equatable, Codable {
  case identity, naturalLog

  func apply(_ value: Double) -> Double? {
    let result: Double
    switch self {
    case .identity: result = value
    case .naturalLog:
      guard value > 0 else { return nil }
      result = log(value)
    }
    return result.isFinite ? result : nil
  }
}

public struct ScoreBands: Sendable, Equatable, Codable {
  public let middleStartsAt: Double
  public let upperStartsAt: Double

  public init(middleStartsAt: Double = 40, upperStartsAt: Double = 70) {
    self.middleStartsAt = middleStartsAt
    self.upperStartsAt = upperStartsAt
  }
}

/// Configurable Diel heuristics. These are neither Garmin's formulas nor clinical thresholds.
public struct ScoringConfig: Sendable, Equatable, Codable {
  public let baselineWindowDays: Int
  public let minimumBaselineSamples: Int
  public let loadReferenceWindowDays: Int
  public let hrvTrendWindowDays: Int
  public let minimumHRVTrendSamples: Int
  public let hrvTransform: ScoringTransform
  public let restingHeartRateTransform: ScoringTransform
  public let madScale: Double
  public let maximumDeviation: Double
  public let hrvWeight: Double
  public let restingHeartRateWeight: Double
  public let readinessCenter: Double
  public let readinessDeviationScale: Double
  public let sleepDurationWeight: Double
  public let sleepEfficiencyWeight: Double
  public let maximumSleepRatio: Double
  public let scoreMinimum: Double
  public let scoreMaximum: Double
  public let readinessBands: ScoreBands
  public let sleepBands: ScoreBands
  public let loadBands: ScoreBands

  public enum ValidationError: Error { case invalidConfiguration }

  public init(
    baselineWindowDays: Int = 28, minimumBaselineSamples: Int = 14,
    loadReferenceWindowDays: Int = 28, hrvTrendWindowDays: Int = 7, minimumHRVTrendSamples: Int = 4,
    hrvTransform: ScoringTransform = .naturalLog,
    restingHeartRateTransform: ScoringTransform = .identity,
    madScale: Double = 1.4826, maximumDeviation: Double = 3,
    hrvWeight: Double = 0.6, restingHeartRateWeight: Double = 0.4,
    readinessCenter: Double = 50, readinessDeviationScale: Double = 15,
    sleepDurationWeight: Double = 0.7, sleepEfficiencyWeight: Double = 0.3,
    maximumSleepRatio: Double = 1, scoreMinimum: Double = 0, scoreMaximum: Double = 100,
    readinessBands: ScoreBands = ScoreBands(), sleepBands: ScoreBands = ScoreBands(),
    loadBands: ScoreBands = ScoreBands()
  ) throws {
    let numbers = [
      madScale, maximumDeviation, hrvWeight, restingHeartRateWeight, readinessCenter,
      readinessDeviationScale, sleepDurationWeight, sleepEfficiencyWeight, maximumSleepRatio,
      scoreMinimum, scoreMaximum,
    ]
    let bands = [readinessBands, sleepBands, loadBands]
    guard baselineWindowDays > 0, minimumBaselineSamples > 0,
      loadReferenceWindowDays > 0, hrvTrendWindowDays > 0, minimumHRVTrendSamples > 0,
      minimumHRVTrendSamples <= hrvTrendWindowDays,
      minimumBaselineSamples <= baselineWindowDays, numbers.allSatisfy(\.isFinite),
      madScale > 0, maximumDeviation > 0, readinessDeviationScale > 0,
      hrvWeight >= 0, restingHeartRateWeight >= 0, hrvWeight + restingHeartRateWeight == 1,
      sleepDurationWeight >= 0, sleepEfficiencyWeight >= 0,
      sleepDurationWeight + sleepEfficiencyWeight == 1,
      maximumSleepRatio > 0, maximumSleepRatio <= 1,
      scoreMinimum == 0, scoreMaximum > scoreMinimum,
      (scoreMinimum...scoreMaximum).contains(readinessCenter),
      bands.allSatisfy({
        $0.middleStartsAt.isFinite && $0.upperStartsAt.isFinite
          && $0.middleStartsAt >= scoreMinimum && $0.upperStartsAt <= scoreMaximum
          && $0.middleStartsAt < $0.upperStartsAt
      })
    else { throw ValidationError.invalidConfiguration }
    self.baselineWindowDays = baselineWindowDays
    self.minimumBaselineSamples = minimumBaselineSamples
    self.loadReferenceWindowDays = loadReferenceWindowDays
    self.hrvTrendWindowDays = hrvTrendWindowDays
    self.minimumHRVTrendSamples = minimumHRVTrendSamples
    self.hrvTransform = hrvTransform
    self.restingHeartRateTransform = restingHeartRateTransform
    self.madScale = madScale
    self.maximumDeviation = maximumDeviation
    self.hrvWeight = hrvWeight
    self.restingHeartRateWeight = restingHeartRateWeight
    self.readinessCenter = readinessCenter
    self.readinessDeviationScale = readinessDeviationScale
    self.sleepDurationWeight = sleepDurationWeight
    self.sleepEfficiencyWeight = sleepEfficiencyWeight
    self.maximumSleepRatio = maximumSleepRatio
    self.scoreMinimum = scoreMinimum
    self.scoreMaximum = scoreMaximum
    self.readinessBands = readinessBands
    self.sleepBands = sleepBands
    self.loadBands = loadBands
  }

  public static let v1 = try! Self()

  func clamp(_ value: Double) -> Double { min(scoreMaximum, max(scoreMinimum, value)) }

  func bands(for kind: ScoreKind) -> ScoreBands {
    switch kind {
    case .readiness: readinessBands
    case .sleep: sleepBands
    case .load: loadBands
    }
  }
}
