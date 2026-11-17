import Foundation
import ScoringKit

nonisolated enum TodayMetric: String, CaseIterable, Identifiable {
  case readiness, load, sleep
  var id: String { rawValue }
  var title: String {
    switch self {
    case .readiness: "Readiness"
    case .load: "Load"
    case .sleep: "Sleep"
    }
  }
}

nonisolated struct TodayDial: Equatable {
  let metric: TodayMetric
  let value: Double?
  let progress: Double?
  let colour: DialColour
  let status: String
  let reason: String
  var number: String { DialPresentation.number(value) }
  var accessibilityLabel: String {
    reason.isEmpty
      ? "\(metric.title), \(number), \(status)" : "\(metric.title), \(number), \(status). \(reason)"
  }

  static func unavailable(_ metric: TodayMetric) -> Self {
    Self(
      metric: metric, value: nil, progress: nil,
      colour: metric == .load ? .load : .unavailable,
      status: "Unavailable", reason: "No reading")
  }

  /// Launch has not settled yet: a track and "–", with no claim that a reading is missing.
  static func loading(_ metric: TodayMetric) -> Self {
    Self(
      metric: metric, value: nil, progress: nil,
      colour: metric == .load ? .load : .unavailable,
      status: "Loading", reason: "")
  }
}

/// What Home shows when no snapshot is on screen. Launch and the credential check must finish
/// before Home may claim there is no data or no key.
nonisolated enum HomeLaunchState: Equatable {
  case content
  case loading
  case noData
  case needsKey

  init(hasContent: Bool, launchFinished: Bool, syncing: Bool, keyMayExist: Bool) {
    if hasContent {
      self = .content
    } else if !launchFinished || syncing {
      self = .loading
    } else {
      self = keyMayExist ? .noData : .needsKey
    }
  }

  /// The status line under the dials, or nil when nothing is updating. Yesterday's launch
  /// fallback always says so, because its values must never read as today's.
  static func caption(hasContent: Bool, loading: Bool, syncing: Bool, showingYesterday: Bool)
    -> String?
  {
    if hasContent && showingYesterday { return "Showing yesterday · updating…" }
    guard syncing || loading else { return nil }
    return hasContent ? "Syncing…" : "Loading your day…"
  }
}

nonisolated struct TodayEvidenceRow: Identifiable, Equatable {
  let id: String
  let label: String
  let value: String
  let detail: String
}

/// Display-only projection. Scores, trend eligibility and ring references come from ScoringKit.
nonisolated struct TodayPresentation: Equatable {
  let date: ScoringDate
  let dials: [TodayDial]
  let readinessRows: [TodayEvidenceRow]
  let sleepRows: [TodayEvidenceRow]
  let loadRows: [TodayEvidenceRow]

  /// `awaitingNight` marks today's morning before Garmin has received last night from the band.
  init(day: ScoredDay, history: [ScoredDay] = [], awaitingNight: Bool = false) {
    date = day.input.date
    let source = DialPresentation(day: day)
    let context = source.readiness.context
    dials = [
      TodayDial(
        metric: .readiness, value: source.readiness.value,
        progress: source.readiness.ringFraction, colour: source.readiness.colour,
        status: Self.band(day.readiness.band, status: day.readiness.status),
        reason: awaitingNight && source.readiness.value == nil
          ? Self.awaitingNightReason : Self.readinessReason(day, history: history)),
      TodayDial(
        metric: .load, value: source.load.value, progress: source.load.ringFraction,
        colour: .load,
        status: source.load.statusText ?? (source.load.value == nil ? "Unavailable" : "Complete"),
        reason: source.load.value == nil
          ? "No heart rate data" : Self.loadReason(day, history: history)),
      TodayDial(
        metric: .sleep, value: source.sleep.value, progress: source.sleep.ringFraction,
        colour: source.sleep.colour,
        status: Self.band(day.sleep.band, status: day.sleep.status),
        reason: source.sleep.value == nil
          ? (awaitingNight ? Self.awaitingNightReason : "No sleep score")
          : Self.sleepComparison(duration: day.input.sleepSeconds, need: day.input.sleepNeedSeconds)
      ),
    ]
    readinessRows = [
      Self.reading("latest-hrv", "Last night's HRV", context.latestHRV, unit: "ms"),
      Self.trend(
        "hrv-trend", "HRV trend", context.hrvTrend,
        reference: context.ewmaEvidence?.hrvTrendReference, unit: "ms"),
      Self.reading("daily-rhr", "Daily resting heart rate", context.restingHeartRate, unit: "bpm"),
      Self.trend(
        "rhr-trend", "Resting heart rate trend", context.restingHeartRateTrend,
        reference: context.ewmaEvidence?.rhrTrendReference, unit: "bpm"),
    ]
    let latest = context.ewmaEvidence?.acuteSleep.latestNight ?? context.sleep.latestNight
    sleepRows = [
      TodayEvidenceRow(
        id: "last-night", label: "Last night", value: Self.duration(latest?.duration),
        detail: Self.sleepComparison(duration: latest?.duration, need: latest?.need)),
      TodayEvidenceRow(
        id: "sleep-need", label: "Your sleep need", value: Self.duration(latest?.need), detail: ""),
      TodayEvidenceRow(
        id: "three-night", label: "Recent sleep",
        value: context.sleep.adequacy.map {
          "\(Int(($0 * 100).rounded()))% of need"
        } ?? "Unavailable", detail: "Sleep across the last three nights"),
      TodayEvidenceRow(
        id: "awake", label: "Awake", value: Self.duration(day.input.awakeSeconds), detail: ""),
    ]
    loadRows = [
      TodayEvidenceRow(
        id: "recorded-load", label: "All-day Load", value: source.load.valueText,
        detail: day.load.status == .provisional
          ? "Accumulated so far" : "From your all-day heart rate"),
      TodayEvidenceRow(
        id: "load-reference",
        label: day.load.allDay?.comparisonIsSameTime == true
          ? "Usual by this time" : "Usual full day",
        value: DialPresentation.number(day.load.allDay?.comparisonMedian),
        detail: day.load.allDay?.comparisonMedian == nil
          ? "Learning your usual load" : "Median of the previous 28 days"),
      TodayEvidenceRow(
        id: "load-max", label: "Reliable maximum heart rate",
        value: day.load.allDay?.maximumHeartRate.map { "\(DialPresentation.number($0)) bpm" }
          ?? "Not enough evidence",
        detail: "Supported readings in the last 90 days"),
      TodayEvidenceRow(
        id: "load-calibration", label: "Calculation",
        value: day.load.allDay?.trimp.map { "\(DialPresentation.number($0)) TRIMP" }
          ?? "Waiting for enough heart rate evidence",
        detail: day.load.allDay?.retainedMinimum == nil
          ? "" : "Earlier accumulated Load retained after revised readings"),
    ]
  }

  static let awaitingNightReason = "Waiting for last night"

  /// Garmin has nothing from last night yet: no sleep, no HRV and no Sleep Score, not even partial.
  static func awaitsLastNight(_ day: ScoredDay) -> Bool {
    func absent(_ metric: ScoringKit.ScoringMetric) -> Bool {
      metric.value == nil && metric.coverage != .partial && metric.reason != .partial
    }
    return absent(day.input.sleepSeconds) && absent(day.input.nightlyHRVMilliseconds)
      && day.sleep.value == nil
  }

  /// From the morning day's 4 AM start until noon, an absent night is still expected to arrive.
  /// Just after midnight that night has not happened yet.
  static func isMorning(_ date: Date, calendar: Calendar) -> Bool {
    let day = MorningDay(containing: date, calendar: calendar)
    var local = Calendar(identifier: .gregorian)
    local.timeZone = calendar.timeZone
    guard
      let noon = local.date(
        bySettingHour: 12, minute: 0, second: 0, of: day.start, matchingPolicy: .nextTime,
        repeatedTimePolicy: .first)
    else { return false }
    return date >= day.start && date < noon
  }

  static func sleepComparison(duration: ScoringKit.ScoringMetric?, need: ScoringKit.ScoringMetric?)
    -> String
  {
    guard let duration, duration.coverage == .complete, duration.reason == nil,
      let actual = duration.value
    else {
      return duration?.coverage == .partial || duration?.reason == .partial
        ? "Sleep duration partial" : "Sleep duration missing"
    }
    guard let need, need.coverage == .complete, need.reason == nil,
      let target = need.value
    else {
      return need?.coverage == .partial || need?.reason == .partial
        ? "Sleep need partial" : "Sleep need missing"
    }
    let difference = Int(((actual - target) / 60).rounded())
    if difference == 0 { return "Met sleep need" }
    return difference > 0
      ? "\(Self.duration(minutes: difference)) above need"
      : "\(Self.duration(minutes: -difference)) short of need"
  }

  static func comparison(value: Double?, normal: Double?, name: String) -> String {
    guard let value else { return "\(name) unavailable" }
    guard let normal, normal > 0 else { return "Learning usual \(name.lowercased())" }
    let percent = Int(((value / normal - 1) * 100).rounded())
    if percent == 0 { return "\(name) at normal" }
    return "\(name) \(abs(percent))% \(percent > 0 ? "above" : "below") normal"
  }

  /// Reselect cached v2.2 explanations from their persisted contributions. Score values and
  /// running Load remain untouched, including on an offline launch after an app update.
  static func readinessWhy(_ day: ScoredDay, history: [ScoredDay] = []) -> ReadinessV2Why {
    guard day.readiness.config.isEWMARevision else { return day.readiness.why }
    let causal = (history.filter { $0.input.date < day.input.date } + [day])
      .sorted { $0.input.date < $1.input.date }
    var previousDate: ScoringDate?
    var previousReason: ReadinessV2WhyReasonCode?
    var streak = 0
    var selected = day.readiness.why
    for candidate in causal {
      if previousDate?.adding(days: 1) != candidate.input.date {
        previousReason = nil
        streak = 0
      }
      let score = candidate.readiness
      selected = ReadinessV2Why.calculate(
        context: score.context, components: score.components, status: score.status,
        config: score.config, previousReason: previousReason, previousReasonStreak: streak)
      previousDate = candidate.input.date
      if score.status == .unavailable {
        previousReason = nil
        streak = 0
      } else {
        streak = previousReason == selected.reasonCode ? streak + 1 : 1
        previousReason = selected.reasonCode
      }
    }
    return selected
  }

  static func readinessReason(_ day: ScoredDay, history: [ScoredDay] = []) -> String {
    let context = day.readinessContext
    let why = readinessWhy(day, history: history)
    guard day.readiness.value != nil else {
      if context.latestHRV.value == nil { return "No HRV last night" }
      if day.input.sleepSeconds.coverage != .complete || day.input.sleepSeconds.reason != nil {
        return day.input.sleepSeconds.coverage == .partial
          ? "Sleep data partial" : "Sleep data missing"
      }
      if context.restingHeartRate.value == nil { return "Daily resting HR missing" }
      if let issue = why.evidence.blockingIssue {
        if issue.reason == .insufficientHistory { return "Learning your normal" }
        switch issue.metric {
        case .sleepNeedSeconds: return "Sleep need missing"
        case .sleepSeconds, .awakeSeconds: return "Recent sleep incomplete"
        case .nightlyHRVMilliseconds: return "HRV comparison missing"
        case .restingHeartRateBPM: return "No resting HR comparison"
        default: return "Readiness unavailable"
        }
      }
      if context.sleep.adequacy == nil { return "Recent sleep incomplete" }
      return "Learning your normal"
    }
    switch why.reasonCode {
    case .hrvTrendAboveReference, .hrvTrendBelowReference, .hrvTrendAtReference:
      return comparison(
        value: context.hrvTrend.value,
        normal: context.ewmaEvidence?.hrvTrendReference.displayMean, name: "HRV")
    case .latestHRVAboveReference, .latestHRVBelowReference, .latestHRVAtReference:
      return comparison(
        value: context.latestHRV.value,
        normal: context.latestHRV.reference.displayMean, name: "HRV")
    case .rhrTrendAboveReference, .rhrTrendBelowReference, .rhrTrendAtReference:
      return comparison(
        value: context.restingHeartRateTrend.value,
        normal: context.ewmaEvidence?.rhrTrendReference.displayMean,
        name: "Resting HR")
    case .rhrAboveReference, .rhrBelowReference, .rhrAtReference:
      return comparison(
        value: context.restingHeartRate.value,
        normal: context.restingHeartRate.reference.displayMean, name: "Resting HR")
    case .sleepAcuteBelowNeed, .sleepHistoryBelowNeed:
      return "Short sleep pulled it down"
    case .sleepAcuteAboveNeed, .sleepHistoryAboveNeed:
      return "Extra sleep lifted it up"
    case .sleepAcuteAtNeed, .sleepHistoryAtNeed:
      return "Sleep met your need"
    default:
      return sleepComparison(duration: day.input.sleepSeconds, need: day.input.sleepNeedSeconds)
    }
  }

  private static func loadReason(_ day: ScoredDay, history: [ScoredDay]) -> String {
    guard let value = day.load.value else { return "No heart rate data" }
    if value < 10 { return "No training yet" }
    guard let usual = day.load.allDay?.comparisonMedian else { return "Light so far" }
    return value > usual ? "Heavier than usual so far" : "Light so far"
  }

  static func selectedDate(
    now: Date, calendar sourceCalendar: Calendar, sampleReference: Date?,
    override: String?, available: Set<ScoringDate>
  ) -> ScoringDate? {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = sourceCalendar.timeZone
    if let sampleReference {
      calendar.timeZone = TimeZone(secondsFromGMT: 0)!
      if let override, let date = ScoringDate(rawValue: override), available.contains(date) {
        return date
      }
      return dateKey(sampleReference, calendar: calendar)
    }
    return dateKey(now, calendar: calendar)
  }

  static func dateKey(_ date: Date, calendar: Calendar) -> ScoringDate? {
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }
    return ScoringDate(rawValue: String(format: "%04d-%02d-%02d", year, month, day))
  }

  static func displayDate(_ date: ScoringDate) -> Date? {
    let parts = date.rawValue.split(separator: "-").compactMap { Int($0) }
    return Calendar.current.date(
      from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
  }

  static func duration(minutes: Int) -> String {
    let value = max(minutes, 0)
    return value < 60 ? "\(value) min" : "\(value / 60)h \(value % 60)m"
  }

  static func duration(_ metric: ScoringKit.ScoringMetric?) -> String {
    guard let metric, metric.coverage == .complete, metric.reason == nil,
      let seconds = metric.value, seconds.isFinite, seconds >= 0
    else {
      return metric?.coverage == .partial || metric?.reason == .partial
        ? "– · partial" : "– · missing"
    }
    let minutes = Int(seconds / 60)
    return duration(minutes: minutes)
  }

  static func missing(_ reason: ScoringKit.ScoringMissingReason?) -> String {
    switch reason {
    case .insufficientHistory: "short of history"
    case .partial: "partial"
    case .zeroDispersion: "without a usable reference spread"
    case .skipped: "missing"
    case .none, .missing: "missing"
    default: "unavailable"
    }
  }

  private static func band(_ band: ScoreBand?, status: ScoreStatus) -> String {
    guard let band else { return "Unavailable" }
    let label =
      switch band {
      case .lower: "Low"
      case .middle: "Fair"
      case .upper: "Good"
      }
    return status == .provisional ? "\(label), partial" : label
  }

  private static func reading(
    _ id: String, _ label: String, _ reading: ReadinessV2Reading,
    unit: String
  ) -> TodayEvidenceRow {
    let normal = reading.reference.displayMean
    return TodayEvidenceRow(
      id: id, label: label,
      value: reading.value.map { "\(DialPresentation.number($0)) \(unit)" }
        ?? (reading.input.coverage == .partial ? "Partial" : "Unavailable"),
      detail: (reading.status == .provisional ? "Partial today. " : "")
        + (normal.map { "Your normal is \(DialPresentation.number($0)) \(unit)" }
          ?? "Learning your normal"))
  }

  private static func trend(
    _ id: String, _ label: String, _ trend: ReadinessV2Trend,
    reference: ReadinessV2EWMAReference?, unit: String
  ) -> TodayEvidenceRow {
    return TodayEvidenceRow(
      id: id, label: label,
      value: trend.value.map { "\(DialPresentation.number($0)) \(unit)" } ?? "Unavailable",
      detail: reference?.displayMean.map { "Your normal is \(DialPresentation.number($0)) \(unit)" }
        ?? "Learning your normal")
  }

}

/// Calendar boundaries update labels and date selection, independently of animation frames.
nonisolated enum TodayClock {
  static func nextBoundary(after date: Date, calendar: Calendar) -> Date? {
    calendar.dateInterval(of: .hour, for: date)?.end
  }
}
