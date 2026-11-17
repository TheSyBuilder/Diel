import Foundation

public enum ReadinessV2Family: String, Sendable, Equatable, CaseIterable, Codable {
  case hrv, restingHeartRate, sleep
}

public struct ReadinessV2FamilyContribution: Sendable, Equatable, Codable {
  public let family: ReadinessV2Family
  /// Signed family sum before direction filtering and ranking. Opposing parts cancel.
  public let pointContribution: Double?
}

public struct ReadinessV2SelectedPart: Sendable, Equatable, Codable {
  public let component: ReadinessV2ComponentKind
  public let subterm: ReadinessV2Subterm.Kind?
  public let pointContribution: Double
}

extension ReadinessV2Why {
  static func calculateEWMA(
    context: ReadinessV2Context, components: [ReadinessV2Component], status: ScoreStatus,
    config: ReadinessV2Config, previousReason: ReadinessV2WhyReasonCode?, previousReasonStreak: Int
  ) -> Self {
    // Reuse frozen blocking wording; available v2.2 reasons are selected by family below.
    let control = calculate(context: context, components: components, status: status, config: .v2_1)
    let hrv = components.first { $0.kind == .hrvTrend }
    let acute = components.first { $0.kind == .hrvAcute }
    let heart = components.first { $0.kind == .restingHeartRate }
    let heartTrend = heart?.subterms.first { $0.kind == .trend }
    let references = context.ewmaEvidence
    var evidence = ReadinessV2WhyEvidence(
      hrvTrendDeviation: hrv?.deviation.rawValue,
      rhrTrendDeviation: heartTrend?.deviation.rawValue,
      hrvAcuteDeviation: acute?.deviation.rawValue,
      hrvTrendMilliseconds: context.hrvTrend.value,
      rhrTrendBPM: context.restingHeartRateTrend.value,
      hrvReferenceLogMean: references?.hrvTrendReference.mean,
      hrvReferenceLogSampleSD: references?.hrvTrendReference.sampleSD,
      rhrReferenceMeanBPM: references?.rhrTrendReference.mean,
      rhrReferenceSampleSDBPM: references?.rhrTrendReference.sampleSD,
      hrvTrendSampleCount: context.hrvTrend.ewma?.recentSampleCount ?? 0,
      rhrTrendSampleCount: context.restingHeartRateTrend.ewma?.recentSampleCount ?? 0,
      directionalGate: config.directionalGate, extremeHighHRV: control.evidence.extremeHighHRV,
      favorableTrendComparisonContribution: control.evidence.favorableTrendComparisonContribution,
      adverseAcuteOrSleepContribution: control.evidence.adverseAcuteOrSleepContribution,
      largerAdverseAcuteOrSleep: control.evidence.largerAdverseAcuteOrSleep,
      completeTrendWindows: context.hrvTrend.ewma?.recentSampleCount == config.trendWindowDays
        && context.restingHeartRateTrend.ewma?.recentSampleCount == config.trendWindowDays
        && context.hrvTrend.reason == nil && context.restingHeartRateTrend.reason == nil,
      weightedContributions: components.map(\.weightedContribution),
      blockingIssue: control.evidence.blockingIssue,
      pointContributions: components.map(\.pointContribution),
      previousReasonStreak: previousReasonStreak)
    let kinds: [[ReadinessV2ComponentKind]] = [
      [.hrvTrend, .hrvAcute], [.restingHeartRate], [.sleepAcute, .sleepHistory],
    ]
    let families = zip(ReadinessV2Family.allCases, kinds).map { family, members in
      let points = members.map { kind in components.first { $0.kind == kind }?.pointContribution }
      return ReadinessV2FamilyContribution(
        family: family,
        pointContribution: points.allSatisfy { $0 != nil }
          ? points.compactMap { $0 }.reduce(0, +) : nil)
    }
    evidence.familyContributions = families
    if status == .unavailable {
      return make(control.rule, control.reasonCode, control.line, control.contributor, evidence)
    }
    // Point contributions are pre-clamp offsets from the fixed center. A reason explains
    // the direction of that offset, even when an opposing family has a larger magnitude.
    let offset = components.compactMap(\.pointContribution).reduce(0, +)
    let direction = offset > 0 ? 1.0 : offset < 0 ? -1.0 : 0
    func matchesDirection(_ points: Double) -> Bool { direction == 0 || points * direction > 0 }
    let ranked = families.enumerated().filter {
      $0.element.pointContribution.map(matchesDirection) == true
    }.sorted {
      let lhs = abs($0.element.pointContribution ?? 0)
      let rhs = abs($1.element.pointContribution ?? 0)
      return lhs == rhs ? $0.offset < $1.offset : lhs > rhs
    }
    func strongest(_ familyIndex: Int) -> ReadinessV2SelectedPart? {
      let parts = kinds[familyIndex].compactMap { kind in components.first { $0.kind == kind } }
        .flatMap { component -> [ReadinessV2SelectedPart] in
          if component.kind == .restingHeartRate, !component.subterms.isEmpty {
            return component.subterms.compactMap { subterm in
              subterm.deviation.value.map {
                ReadinessV2SelectedPart(
                  component: component.kind, subterm: subterm.kind,
                  pointContribution: config.gain * component.weight * subterm.share * $0
                    / config.normalizer)
              }
            }
          }
          return component.pointContribution.map {
            [
              ReadinessV2SelectedPart(
                component: component.kind, subterm: nil, pointContribution: $0)
            ]
          } ?? []
        }
      return parts.filter { matchesDirection($0.pointContribution) }.reduce(
        nil as ReadinessV2SelectedPart?
      ) { best, next in
        guard let best else { return next }
        return abs(next.pointContribution) > abs(best.pointContribution) ? next : best
      }
    }
    func explanation(_ part: ReadinessV2SelectedPart) -> (ReadinessV2WhyReasonCode, String) {
      let direction = part.pointContribution > 0 ? 1 : part.pointContribution < 0 ? -1 : 0
      if part.component == .restingHeartRate {
        if part.subterm == .trend {
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
      }
      let component = components.first { $0.kind == part.component }!
      return contributorExplanation(component, direction: direction)
    }
    guard let first = ranked.first, var selected = strongest(first.offset) else {
      return make(.blockingEvidence, .missingEvidence, "Missing Readiness evidence", nil, evidence)
    }
    var family = first.element.family
    if previousReasonStreak >= 3, explanation(selected).0 == previousReason, ranked.count > 1 {
      let second = ranked[1]
      if abs(first.element.pointContribution ?? 0) - abs(second.element.pointContribution ?? 0)
        <= 2,
        let alternate = strongest(second.offset)
      {
        selected = alternate
        family = second.element.family
        evidence.usedSecondContributor = true
      }
    }
    evidence.selectedFamily = family
    evidence.selectedPart = selected
    let reason = explanation(selected)
    return make(.largestContributor, reason.0, reason.1, selected.component, evidence)
  }
}
