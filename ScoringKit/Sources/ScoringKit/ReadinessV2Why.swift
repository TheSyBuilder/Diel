import Foundation

public enum ReadinessV2WhyRuleCode: String, Sendable, Equatable, Codable {
  case copingWellPattern, ambiguousAdversePattern, largestContributor, blockingEvidence
}

public enum ReadinessV2WhyReasonCode: String, Sendable, Equatable, Codable {
  case copingWellPattern, hrvTrendAboveReference, hrvTrendBelowReference, hrvTrendAtReference
  case latestHRVAboveReference, latestHRVBelowReference, latestHRVAtReference
  case rhrAboveReference, rhrBelowReference, rhrAtReference, sleepBelowNeed, sleepAtNeed
  case rhrTrendAboveReference, rhrTrendBelowReference, rhrTrendAtReference
  case sleepAcuteAboveNeed, sleepAcuteBelowNeed, sleepAcuteAtNeed
  case sleepHistoryAboveNeed, sleepHistoryBelowNeed, sleepHistoryAtNeed
  case missingEvidence, insufficientHistory, duplicateDay, zeroDispersion, invalidEvidence
}

public struct ReadinessV2WhyRule: Sendable, Equatable, Codable {
  public let code: ReadinessV2WhyRuleCode
  public let requirements: String
  public let sourceLinks: [String]
  public let limitation: String
}

public struct ReadinessV2WhyEvidence: Sendable, Equatable, Codable {
  /// Favorable-direction raw z values; positive RHR deviation means a lower RHR.
  public let hrvTrendDeviation: Double?
  public let rhrTrendDeviation: Double?
  public let hrvAcuteDeviation: Double?
  public let hrvTrendMilliseconds: Double?
  public let rhrTrendBPM: Double?
  public let hrvReferenceLogMean: Double?
  public let hrvReferenceLogSampleSD: Double?
  public let rhrReferenceMeanBPM: Double?
  public let rhrReferenceSampleSDBPM: Double?
  public let hrvTrendSampleCount: Int
  public let rhrTrendSampleCount: Int
  public let directionalGate: Double
  public let extremeHighHRV: Bool
  public let favorableTrendComparisonContribution: Double
  public let adverseAcuteOrSleepContribution: Double
  public let largerAdverseAcuteOrSleep: Bool
  public let completeTrendWindows: Bool
  public let weightedContributions: [Double?]
  public let blockingIssue: ScoreIssue?
  public var pointContributions: [Double?] = []
  public var previousReasonStreak: Int = 0
  public var usedSecondContributor: Bool = false
  public var familyContributions: [ReadinessV2FamilyContribution] = []
  public var selectedFamily: ReadinessV2Family? = nil
  public var selectedPart: ReadinessV2SelectedPart? = nil
}

/// Qualified explanations, never a fatigue/maladaptation diagnosis.
public struct ReadinessV2Why: Sendable, Equatable, Codable {
  public let rule: ReadinessV2WhyRuleCode
  public let reasonCode: ReadinessV2WhyReasonCode
  public let line: String
  public let contributor: ReadinessV2ComponentKind?
  public let evidence: ReadinessV2WhyEvidence
  public let sourceLinks: [String]

  public static let ruleMatrix: [ReadinessV2WhyRule] = [
    ReadinessV2WhyRule(
      code: .copingWellPattern,
      requirements:
        "Both complete 7-day windows beyond 0.5 reference SD in favorable directions; available score; no HRV above 2 SD; no larger adverse acute/sleep contribution.",
      sourceLinks: [ais, trendSource],
      limitation:
        "Diel's strict half-SD gate and contribution comparison are product choices, not a validated classifier."
    ),
    ReadinessV2WhyRule(
      code: .ambiguousAdversePattern,
      requirements:
        "Both complete 7-day windows beyond 0.5 reference SD in adverse directions; explain the largest contributor.",
      sourceLinks: [trendSource],
      limitation:
        "HRV variability and training context are unavailable. Possible maladaptation and possible accumulated fatigue cannot be distinguished or emitted."
    ),
    ReadinessV2WhyRule(
      code: .largestContributor,
      requirements:
        "Largest absolute weighted contribution among HRV trend, acute HRV, aggregate RHR and sleep, in that tie order.",
      sourceLinks: [dailySource, trendSource],
      limitation:
        "The contributor is score attribution, not a diagnosis or a claim that sleep duration establishes recovery."
    ),
    ReadinessV2WhyRule(
      code: .blockingEvidence,
      requirements:
        "An unavailable score explains the first blocking component and issue before any pattern.",
      sourceLinks: [dailySource],
      limitation:
        "Missing evidence is never replaced by older observations or interpreted as physiology."),
  ]

  public static func calculate(
    context: ReadinessV2Context, components: [ReadinessV2Component], status: ScoreStatus,
    config: ReadinessV2Config = .v2,
    previousReason: ReadinessV2WhyReasonCode? = nil, previousReasonStreak: Int = 0
  ) -> Self {
    if config.isEWMARevision {
      return calculateEWMA(
        context: context, components: components, status: status, config: config,
        previousReason: previousReason, previousReasonStreak: previousReasonStreak)
    }
    let componentOrder: [ReadinessV2ComponentKind] =
      config.isScaleRevision
      ? [.hrvTrend, .hrvAcute, .restingHeartRate, .sleepAcute, .sleepHistory]
      : [.hrvTrend, .hrvAcute, .restingHeartRate, .sleep]
    let hrvTrend = components.first { $0.kind == .hrvTrend }
    let hrvAcute = components.first { $0.kind == .hrvAcute }
    let heart = components.first { $0.kind == .restingHeartRate }
    let heartTrend = heart?.subterms.first { $0.kind == .trend }
    let heartAcute = heart?.subterms.first { $0.kind == .acute }
    let sleep = components.first { $0.kind == .sleep }
    let hz = hrvTrend?.deviation.rawValue
    let rz = heartTrend?.deviation.rawValue
    let ha = hrvAcute?.deviation.rawValue
    let complete =
      context.hrvTrend.sampleCount == config.trendWindowDays
      && context.restingHeartRateTrend.sampleCount == config.trendWindowDays
      && context.hrvTrend.reason == nil && context.restingHeartRateTrend.reason == nil
      && context.latestHRV.reference.reason == nil
      && context.restingHeartRate.reference.reason == nil
    let extreme = [hz, ha].compactMap { $0 }.contains { $0 > config.extremeHighHRVGate }
    let favorableTrend = max(
      hrvTrend?.weightedContribution ?? 0,
      (heartTrend?.deviation.value ?? 0) * (heartTrend?.share ?? 0) * config.restingHeartRateWeight)
    let adverse = max(
      -(hrvAcute?.weightedContribution ?? 0),
      -(heartAcute?.deviation.value ?? 0) * (heartAcute?.share ?? 0)
        * config.restingHeartRateWeight,
      -(sleep?.weightedContribution ?? 0))
    let largerAdverse = adverse > max(0, favorableTrend)
    let blocker = components.first { !$0.deviation.issues.isEmpty }
    let issue = blocker?.deviation.issues.first
    var evidence = ReadinessV2WhyEvidence(
      hrvTrendDeviation: hz, rhrTrendDeviation: rz, hrvAcuteDeviation: ha,
      hrvTrendMilliseconds: context.hrvTrend.value,
      rhrTrendBPM: context.restingHeartRateTrend.value,
      hrvReferenceLogMean: config.isScaleRevision
        ? context.hrvTrend.rollingReference?.mean : context.latestHRV.reference.mean,
      hrvReferenceLogSampleSD: config.isScaleRevision
        ? context.hrvTrend.rollingReference?.sampleSD : context.latestHRV.reference.sampleSD,
      rhrReferenceMeanBPM: config.isScaleRevision
        ? context.restingHeartRateTrend.rollingReference?.mean
        : context.restingHeartRate.reference.mean,
      rhrReferenceSampleSDBPM: config.isScaleRevision
        ? context.restingHeartRateTrend.rollingReference?.sampleSD
        : context.restingHeartRate.reference.sampleSD,
      hrvTrendSampleCount: context.hrvTrend.sampleCount,
      rhrTrendSampleCount: context.restingHeartRateTrend.sampleCount,
      directionalGate: config.directionalGate, extremeHighHRV: extreme,
      favorableTrendComparisonContribution: max(0, favorableTrend),
      adverseAcuteOrSleepContribution: max(0, adverse),
      largerAdverseAcuteOrSleep: largerAdverse, completeTrendWindows: complete,
      weightedContributions: componentOrder.map { kind in
        components.first { $0.kind == kind }?.weightedContribution
      }, blockingIssue: issue)
    if config.isScaleRevision {
      evidence.pointContributions = components.map(\.pointContribution)
      evidence.previousReasonStreak = previousReasonStreak
    }
    if status == .unavailable {
      let code: ReadinessV2WhyReasonCode
      switch issue?.reason {
      case .insufficientHistory: code = .insufficientHistory
      case .duplicateDay: code = .duplicateDay
      case .zeroDispersion: code = .zeroDispersion
      case .invalidValue, .dateMismatch, .unverifiedUnit, .nonPositiveBaseline:
        code = .invalidEvidence
      default: code = .missingEvidence
      }
      let label = blocker.map { label($0.kind) } ?? "Readiness"
      let message: String
      switch code {
      case .insufficientHistory: message = "Insufficient history for \(label)"
      case .duplicateDay: message = "Conflicting date evidence for \(label)"
      case .zeroDispersion: message = "No reference variation for \(label)"
      case .invalidEvidence: message = "Invalid evidence for \(label)"
      default: message = "Missing complete evidence for \(label)"
      }
      return make(.blockingEvidence, code, message, blocker?.kind, evidence)
    }
    if !config.isScaleRevision, complete, status == .available, let hz, let rz,
      hz > config.directionalGate, rz > config.directionalGate, !extreme, !largerAdverse
    {
      return make(.copingWellPattern, .copingWellPattern, "Coping-well pattern", nil, evidence)
    }
    let ambiguous =
      !config.isScaleRevision && complete && (hz.map { $0 < -config.directionalGate } ?? false)
      && (rz.map { $0 < -config.directionalGate } ?? false)
    // Strict > preserves the fixed component order when magnitudes tie.
    let ordered = componentOrder.compactMap { kind in
      components.first { $0.kind == kind }
    }
    var largest = ordered.reduce(nil as ReadinessV2Component?) { best, candidate in
      let value =
        config.isScaleRevision ? candidate.pointContribution : candidate.weightedContribution
      guard let value else { return best }
      guard let best else { return candidate }
      let bestValue = config.isScaleRevision ? best.pointContribution : best.weightedContribution
      return abs(value) > abs(bestValue ?? 0) ? candidate : best
    }
    if config.isScaleRevision, let first = largest,
      let firstPoints = first.pointContribution, previousReasonStreak >= 3,
      contributorExplanation(first, direction: firstPoints > 0 ? 1 : firstPoints < 0 ? -1 : 0).0
        == previousReason
    {
      let remaining = ordered.enumerated().filter { $0.element.kind != first.kind }.sorted {
        let left = abs($0.element.pointContribution ?? 0)
        let right = abs($1.element.pointContribution ?? 0)
        return left == right ? $0.offset < $1.offset : left > right
      }.map(\.element)
      if let second = remaining.first, let points = second.pointContribution,
        abs(firstPoints) - abs(points) <= 2
      {
        largest = second
        evidence.usedSecondContributor = true
      }
    }
    guard let largest, let contribution = largest.weightedContribution else {
      return make(.blockingEvidence, .missingEvidence, "Missing Readiness evidence", nil, evidence)
    }
    let direction = contribution > 0 ? 1 : contribution < 0 ? -1 : 0
    let explanation = contributorExplanation(largest, direction: direction)
    return make(
      ambiguous ? .ambiguousAdversePattern : .largestContributor,
      explanation.0, explanation.1, largest.kind, evidence)
  }

  private static let ais =
    "https://www.ausport.gov.au/ais/position_statements/heart-rate-variability"
  private static let trendSource = "https://www.hrv4training.com/blog2/interpreting-hrv-trends"
  private static let dailySource =
    "https://www.hrv4training.com/blog2/daily-score-baseline-and-normal-range-an-overview"

  static func make(
    _ rule: ReadinessV2WhyRuleCode, _ reason: ReadinessV2WhyReasonCode, _ line: String,
    _ contributor: ReadinessV2ComponentKind?, _ evidence: ReadinessV2WhyEvidence
  ) -> Self {
    Self(
      rule: rule, reasonCode: reason, line: line, contributor: contributor, evidence: evidence,
      sourceLinks: ruleMatrix.first { $0.code == rule }?.sourceLinks ?? [])
  }

  private static func label(_ kind: ReadinessV2ComponentKind) -> String {
    switch kind {
    case .hrvTrend: "HRV trend"
    case .hrvAcute: "last night's HRV"
    case .restingHeartRate: "daily RHR"
    case .sleep, .sleepHistory: "three-night sleep"
    case .sleepAcute: "last night's sleep"
    }
  }

  static func contributorExplanation(
    _ component: ReadinessV2Component, direction: Int
  ) -> (ReadinessV2WhyReasonCode, String) {
    switch component.kind {
    case .hrvTrend:
      return direction > 0
        ? (.hrvTrendAboveReference, "HRV trend above reference")
        : direction < 0
          ? (.hrvTrendBelowReference, "HRV trend below reference")
          : (.hrvTrendAtReference, "HRV trend at reference")
    case .hrvAcute:
      return direction > 0
        ? (.latestHRVAboveReference, "Last night's HRV above reference")
        : direction < 0
          ? (.latestHRVBelowReference, "Last night's HRV below reference")
          : (.latestHRVAtReference, "Last night's HRV at reference")
    case .restingHeartRate:
      let trend = component.subterms.first { $0.kind == .trend }
      let acute = component.subterms.first { $0.kind == .acute }
      if abs((trend?.deviation.value ?? 0) * (trend?.share ?? 0))
        >= abs((acute?.deviation.value ?? 0) * (acute?.share ?? 0))
      {
        return direction > 0
          ? (.rhrTrendBelowReference, "RHR trend below reference")
          : direction < 0
            ? (.rhrTrendAboveReference, "RHR trend above reference")
            : (.rhrTrendAtReference, "RHR trend at reference")
      }
      return direction > 0
        ? (.rhrBelowReference, "Daily RHR below reference")
        : direction < 0
          ? (.rhrAboveReference, "Daily RHR above reference")
          : (.rhrAtReference, "Daily RHR at reference")
    case .sleepAcute:
      return direction > 0
        ? (.sleepAcuteAboveNeed, "Last night's sleep above need")
        : direction < 0
          ? (.sleepAcuteBelowNeed, "Last night's sleep below need")
          : (.sleepAcuteAtNeed, "Last night's sleep at need")
    case .sleepHistory:
      return direction > 0
        ? (.sleepHistoryAboveNeed, "Three-night sleep above need")
        : direction < 0
          ? (.sleepHistoryBelowNeed, "Three-night sleep below need")
          : (.sleepHistoryAtNeed, "Three-night sleep at need")
    case .sleep:
      return direction < 0
        ? (.sleepBelowNeed, "Three-night sleep below need")
        : (.sleepAtNeed, "Three-night sleep at need")
    }
  }
}
