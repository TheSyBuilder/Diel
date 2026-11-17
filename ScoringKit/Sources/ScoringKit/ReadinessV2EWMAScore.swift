import Foundation

enum ReadinessV2EWMAScore {
  static func context(
    day: ScoringDayInput, history: [ScoringDayInput], config: ReadinessV2Config
  ) -> ReadinessV2Context {
    calculate(days: [day], history: history, config: config)[0].context
  }

  static func calculate(
    days: [ScoringDayInput], history: [ScoringDayInput], config: ReadinessV2Config
  ) -> [ReadinessV2Result] {
    guard let last = days.map(\.date).max() else { return [] }
    var groups = Dictionary(grouping: history.filter { $0.date <= last }, by: \.date)
    for day in days where !(groups[day.date] ?? []).contains(day) {
      groups[day.date, default: []].append(day)
    }
    let hrv = ReadinessV2EWMASeries(
      metric: .nightlyHRVMilliseconds, groups: groups, end: last, config: config)
    let rhr = ReadinessV2EWMASeries(
      metric: .restingHeartRateBPM, groups: groups, end: last, config: config)
    var previousDate: ScoringDate?
    var previousReason: ReadinessV2WhyReasonCode?
    var streak = 0
    var results: [ScoringDate: ReadinessV2Result] = [:]
    let requested = Set(days.map(\.date))
    for date in groups.keys.sorted() {
      guard let day = groups[date]?.first else { continue }
      if previousDate?.adding(days: 1) != date {
        previousReason = nil
        streak = 0
      }
      let bounded = (0...config.referenceWindowDays).flatMap {
        date.adding(days: -$0).flatMap { groups[$0] } ?? []
      }
      let context = preparedContext(day: day, history: bounded, hrv: hrv, rhr: rhr, config: config)
      let result = score(
        context: context, config: config, previousReason: previousReason,
        previousReasonStreak: streak)
      if requested.contains(date) { results[date] = result }
      previousDate = date
      if result.status == .unavailable {
        previousReason = nil
        streak = 0
      } else {
        streak = previousReason == result.why.reasonCode ? streak + 1 : 1
        previousReason = result.why.reasonCode
      }
    }
    return days.compactMap { results[$0.date] }
  }

  private static func preparedContext(
    day: ScoringDayInput, history: [ScoringDayInput], hrv: ReadinessV2EWMASeries,
    rhr: ReadinessV2EWMASeries, config: ReadinessV2Config
  ) -> ReadinessV2Context {
    let hrvDaily = ReadinessBaseline.calculate(
      metric: .nightlyHRVMilliseconds, before: day.date, history: history, config: config)
    let rhrDaily = ReadinessBaseline.calculate(
      metric: .restingHeartRateBPM, before: day.date, history: history, config: config)
    let hrvReference = hrv.reference(
      date: day.date, metric: .nightlyHRVMilliseconds, config: config)
    let rhrReference = rhr.reference(date: day.date, metric: .restingHeartRateBPM, config: config)
    let ambiguous = history.filter { $0.date == day.date }.count > 1
    func trend(
      _ series: ReadinessV2EWMASeries, _ daily: ReadinessBaseline,
      _ reference: ReadinessV2EWMAReference
    ) -> ReadinessV2Trend {
      let point = series.points[day.date]!
      return ReadinessV2Trend(
        metric: daily.metric, windowStart: point.observations.first?.observation.date,
        endInclusive: day.date, requiredSampleCount: config.minimumTrendSamples,
        observations: point.observations.map(\.observation), exclusions: point.exclusions,
        transformedMean: point.transformedMean, value: point.value, reason: point.reason,
        reference: daily,
        difference: point.value.flatMap { value in reference.displayMean.map { value - $0 } },
        ewma: point)
    }
    return ReadinessV2Context(
      date: day.date,
      latestHRV: ReadinessV2Context.reading(
        day: day, reference: hrvDaily, allowPartial: false, ambiguous: ambiguous),
      hrvTrend: trend(hrv, hrvDaily, hrvReference),
      restingHeartRate: ReadinessV2Context.reading(
        day: day, reference: rhrDaily, allowPartial: true, ambiguous: ambiguous),
      restingHeartRateTrend: trend(rhr, rhrDaily, rhrReference),
      sleep: ReadinessV2Context.sleep(date: day.date, candidates: history, config: config),
      ewmaEvidence: ReadinessV2EWMAEvidence(
        hrvTrendReference: hrvReference, rhrTrendReference: rhrReference,
        acuteSleep: ReadinessV2Context.sleep(
          date: day.date, candidates: history, config: config, nightCount: 1),
        sleepDeviationUnit: config.sleepDeficitPerDeviation))
  }

  private static func score(
    context: ReadinessV2Context, config: ReadinessV2Config,
    previousReason: ReadinessV2WhyReasonCode?, previousReasonStreak: Int
  ) -> ReadinessV2Result {
    let evidence = context.ewmaEvidence!
    func trend(_ current: ReadinessV2Trend, _ reference: ReadinessV2EWMAReference, reverse: Bool)
      -> ReadinessV2Deviation
    {
      // Reuse the frozen daily standardization including its exact zero-SD rule.
      let baseline = ReadinessBaseline(
        metric: reference.metric, windowStart: reference.windowStart,
        endExclusive: reference.endExclusive, requiredSampleCount: reference.requiredSampleCount,
        transform: reference.metric == .nightlyHRVMilliseconds ? .naturalLog : .identity,
        observations: [], exclusions: [], mean: reference.mean, sampleSD: reference.sampleSD,
        reason: reference.reason)
      return ReadinessV2Score.deviation(
        current.transformedMean, reason: current.reason, reference: baseline,
        reverse: reverse, config: config)
    }
    let hrvTrend = trend(context.hrvTrend, evidence.hrvTrendReference, reverse: false)
    let hrvAcute = ReadinessV2Score.deviation(
      context.latestHRV.transformedValue, reason: context.latestHRV.reason,
      reference: context.latestHRV.reference, reverse: false, config: config)
    let heartTrend = trend(context.restingHeartRateTrend, evidence.rhrTrendReference, reverse: true)
    let heartAcute = ReadinessV2Score.deviation(
      context.restingHeartRate.transformedValue, reason: context.restingHeartRate.reason,
      reference: context.restingHeartRate.reference, reverse: true, config: config)
    let heart = ReadinessV2Deviation(
      rawValue: ReadinessV2Score.combine(heartTrend.rawValue, heartAcute.rawValue, config: config),
      value: ReadinessV2Score.combine(heartTrend.value, heartAcute.value, config: config),
      issues: heartTrend.issues + heartAcute.issues)
    func sleep(_ current: ReadinessV2Sleep) -> ReadinessV2Deviation {
      let raw = current.adequacy.map { ($0 - 1) / config.sleepDeficitPerDeviation }
      return ReadinessV2Deviation(
        rawValue: raw, value: raw.map { min(1, max(-3, $0)) }, issues: current.issues)
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
        deviation: sleep(evidence.acuteSleep)),
      component(
        .sleepHistory, weight: config.sleepHistoryWeight,
        deviation: sleep(context.sleep)),
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
      date: context.date, value: value, status: status, band: band, components: components,
      context: context, issues: issues, config: config,
      why: ReadinessV2Why.calculate(
        context: context, components: components, status: status, config: config,
        previousReason: previousReason, previousReasonStreak: previousReasonStreak))
  }

}
