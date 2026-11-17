import Foundation

extension ReadinessV2Score {
  /// Scores all supplied chronology once, then returns requested days in their original order.
  /// Supply the full available local history, including earlier unavailable days. Missing calendar
  /// days and unavailable scores reset the selected-reason streak. No date after a score is used.
  /// A single-day calculate with the same history produces the identical selected explanation.
  public static func calculateChronologically(
    days: [ScoringDayInput], history: [ScoringDayInput], config: ReadinessV2Config = .v2_1
  ) -> [ReadinessV2Result] {
    if config.isEWMARevision {
      return ReadinessV2EWMAScore.calculate(days: days, history: history, config: config)
    }
    guard config.isScaleRevision else {
      return days.map { calculate(day: $0, history: history, config: config) }
    }
    guard let last = days.map(\.date).max() else { return [] }
    var groups = Dictionary(grouping: history.filter { $0.date <= last }, by: \.date)
    // A requested day already present identically is one observation. Conflicting or duplicate
    // history remains ambiguous, matching the frozen single-day candidate rule.
    for day in days where !(groups[day.date] ?? []).contains(day) {
      groups[day.date, default: []].append(day)
    }
    let requestedDates = Set(days.map(\.date))
    var results: [ScoringDate: ReadinessV2Result] = [:]
    var previousDate: ScoringDate?
    var previousReason: ReadinessV2WhyReasonCode?
    var streak = 0
    for date in groups.keys.sorted() {
      guard let day = groups[date]?.first else { continue }
      if previousDate?.adding(days: 1) != date {
        previousReason = nil
        streak = 0
      }
      // Lookup only the bounded 60-day reference plus today, never rescan whole history.
      let bounded = (0...config.referenceWindowDays).flatMap { offset in
        date.adding(days: -offset).flatMap { groups[$0] } ?? []
      }
      let result = calculateScaleDay(
        day: day, history: bounded, config: config,
        previousReason: previousReason, previousReasonStreak: streak)
      if requestedDates.contains(date) { results[date] = result }
      previousDate = date
      if result.status == .unavailable {
        previousReason = nil
        streak = 0
      } else {
        streak = result.why.reasonCode == previousReason ? streak + 1 : 1
        previousReason = result.why.reasonCode
      }
    }
    return days.compactMap { results[$0.date] }
  }

  private static func calculateScaleDay(
    day: ScoringDayInput, history: [ScoringDayInput], config: ReadinessV2Config,
    previousReason: ReadinessV2WhyReasonCode?, previousReasonStreak: Int
  ) -> ReadinessV2Result {
    let context = ReadinessV2Context.calculate(day: day, history: history, config: config)
    // Revised context construction always supplies its versioned evidence.
    let evidence = context.scaleEvidence!
    func trend(_ current: ReadinessV2Trend, _ reference: ReadinessV2RollingReference, reverse: Bool)
      -> ReadinessV2Deviation
    {
      standardized(
        current.transformedMean, center: reference.mean, sd: reference.sampleSD,
        issues: [current.reason, reference.reason].compactMap { reason in
          reason.map { ScoreIssue(metric: reference.metric, reason: $0) }
        }, metric: reference.metric, reverse: reverse, upper: config.maximumDeviation,
        config: config)
    }
    let hrvTrend = trend(context.hrvTrend, evidence.hrvTrendReference, reverse: false)
    let hrvAcute = deviation(
      context.latestHRV.transformedValue, reason: context.latestHRV.reason,
      reference: context.latestHRV.reference, reverse: false, config: config)
    let heartTrend = trend(context.restingHeartRateTrend, evidence.rhrTrendReference, reverse: true)
    let heartAcute = deviation(
      context.restingHeartRate.transformedValue, reason: context.restingHeartRate.reason,
      reference: context.restingHeartRate.reference, reverse: true, config: config)
    let heart = ReadinessV2Deviation(
      rawValue: combine(heartTrend.rawValue, heartAcute.rawValue, config: config),
      value: combine(heartTrend.value, heartAcute.value, config: config),
      issues: heartTrend.issues + heartAcute.issues)
    func sleep(_ current: ReadinessV2Sleep, _ reference: ReadinessV2SleepReference)
      -> ReadinessV2Deviation
    {
      standardized(
        current.adequacy, center: 1, sd: reference.sampleSD,
        issues: current.issues
          + (reference.reason.map {
            [ScoreIssue(metric: .sleepSeconds, reason: $0)]
          } ?? []), metric: .sleepSeconds, reverse: false, upper: 1, config: config)
    }
    func component(
      _ kind: ReadinessV2ComponentKind, weight: Double, deviation: ReadinessV2Deviation,
      subterms: [ReadinessV2Subterm] = []
    ) -> ReadinessV2Component {
      ReadinessV2Component(
        kind: kind, weight: weight, deviation: deviation, subterms: subterms,
        pointContribution: deviation.value.map { config.gain * weight * $0 / config.normalizer })
    }
    let components = [
      component(.hrvTrend, weight: config.hrvTrendWeight, deviation: hrvTrend),
      component(.hrvAcute, weight: config.hrvAcuteWeight, deviation: hrvAcute),
      component(
        .restingHeartRate, weight: config.restingHeartRateWeight, deviation: heart,
        subterms: [
          ReadinessV2Subterm(
            kind: .trend, share: config.restingHeartRateTrendShare, deviation: heartTrend),
          ReadinessV2Subterm(
            kind: .acute, share: config.restingHeartRateAcuteShare, deviation: heartAcute),
        ]),
      component(
        .sleepAcute, weight: config.sleepAcuteWeight,
        deviation: sleep(evidence.acuteSleep, evidence.acuteSleepReference)),
      component(
        .sleepHistory, weight: config.sleepHistoryWeight,
        deviation: sleep(context.sleep, evidence.historySleepReference)),
    ]
    var issues = components.flatMap { $0.deviation.issues }
    var value: Double?
    if issues.isEmpty, components.allSatisfy({ $0.weightedContribution != nil }) {
      let q = components.compactMap(\.weightedContribution).reduce(0, +)
      let candidate = config.center + config.gain * q / config.normalizer
      if candidate.isFinite {
        value = min(config.conservativeMaximum, max(config.conservativeMinimum, candidate))
      } else {
        issues.append(ScoreIssue(metric: nil, reason: .invalidValue))
      }
    }
    let status: ScoreStatus =
      value == nil
      ? .unavailable
      : context.restingHeartRate.status == .provisional ? .provisional : .available
    let band: ScoreBand? = value.map {
      $0 >= config.bands.upperStartsAt
        ? .upper
        : $0 >= config.bands.middleStartsAt ? .middle : .lower
    }
    return ReadinessV2Result(
      date: day.date, value: value, status: status, band: band, components: components,
      context: context, issues: issues, config: config,
      why: ReadinessV2Why.calculate(
        context: context, components: components, status: status, config: config,
        previousReason: previousReason, previousReasonStreak: previousReasonStreak))
  }

  private static func standardized(
    _ current: Double?, center: Double?, sd: Double?, issues: [ScoreIssue],
    metric: ScoringMetricKind, reverse: Bool, upper: Double, config: ReadinessV2Config
  ) -> ReadinessV2Deviation {
    var issues = issues
    var raw: Double?
    if issues.isEmpty, let current, let center, let sd {
      let numerator = reverse ? center - current : current - center
      if sd == 0 {
        if numerator == 0 {
          raw = 0
        } else {
          issues.append(ScoreIssue(metric: metric, reason: .zeroDispersion))
        }
      } else if numerator.isFinite {
        let ratio = numerator / sd
        if !ratio.isNaN {
          raw = ratio
        } else {
          issues.append(ScoreIssue(metric: metric, reason: .invalidValue))
        }
      } else {
        issues.append(ScoreIssue(metric: metric, reason: .invalidValue))
      }
    }
    return ReadinessV2Deviation(
      rawValue: raw, value: raw.map { min(upper, max(-config.maximumDeviation, $0)) },
      issues: issues)
  }
}
