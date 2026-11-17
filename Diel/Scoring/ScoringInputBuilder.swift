import Foundation
import ScoringKit

/// Pure normalization. Calendar labels never pass through a UTC date parser.
nonisolated enum ScoringInputBuilder {
  static func build(
    _ snapshot: GarminScoringSnapshot, in dates: ClosedRange<DateKey>, now: Date,
    calendar: Calendar
  ) throws -> [ScoringDayInput] {
    var gregorian = Calendar(identifier: .gregorian)
    gregorian.timeZone = calendar.timeZone
    var result: [ScoringDayInput] = []
    var date = dates.lowerBound
    while date <= dates.upperBound {
      let day = snapshot.days.first { $0.date == date }
      let sleep = latest(day, families: [.sleep, .sleepSummaries])
      let hrv = latest(day, families: [.hrv, .hrvSummaries])
      let heart = latest(day, families: [.heartRate, .dailySummaries])
      let skipped = snapshot.skippedSleep.first { $0.candidateDate == date }
      let sleepDTO: SleepDTO?
      switch sleep?.projection {
      case .sleep(let value), .sleepSummary(let value): sleepDTO = value
      default: sleepDTO = nil
      }
      let nightly: Int64?
      switch hrv?.projection {
      case .hrv(let value): nightly = value.hrvSummary?.lastNightAvg
      case .hrvSummary(let value): nightly = value.lastNightAvg
      default: nightly = nil
      }
      let resting: Int64?
      switch heart?.projection {
      case .heartRate(let value): resting = value.restingHeartRate
      case .dailySummary(let value): resting = value.heartRate?.restingValue
      default: resting = nil
      }
      let heartCoverage: ScoringCoverage =
        heart.map { date < label(min(now, $0.fetchedAt), calendar: gregorian) } == true
        ? .complete : .partial
      let sleepSources = source(sleep)
      let provenance: ScoringDateProvenance =
        sleep != nil
        ? (sleepDTO?.calendarDate == nil ? .inferredSleepNeed : .recorded)
        : (skipped?.provenance ?? .unknown)
      let absence: ScoringMissingReason = skipped == nil ? .missing : .skipped
      let need = sleepDTO?.sleepNeed
      // Swagger names the matching baseline field in minutes. Fixtures cross-check the two
      // baseline fields. actual's minutes unit is inferred from this shared SleepNeedDTO contract.
      let needReason: ScoringMissingReason? =
        need?.calendarDate != date ? .dateMismatch : nil
      let needSeconds = need?.actual.map { Double($0) * 60 }
      result.append(
        ScoringDayInput(
          date: date,
          nightlyHRVMilliseconds: metric(
            nightly.map(Double.init), positive: true, sources: source(hrv)),
          restingHeartRateBPM: metric(
            resting.map(Double.init), positive: true, coverage: heartCoverage,
            sources: source(heart)),
          sleepSeconds: metric(
            sleepDTO?.sleepTimeSeconds.map(Double.init), absence: absence,
            provenance: provenance,
            sources: sleepSources.isEmpty ? skipped.map { [$0.source] } ?? [] : sleepSources),
          awakeSeconds: metric(
            sleepDTO?.awakeSleepSeconds.map(Double.init), absence: absence,
            provenance: provenance,
            sources: sleepSources.isEmpty ? skipped.map { [$0.source] } ?? [] : sleepSources),
          sleepNeedSeconds: metric(
            needReason == nil ? needSeconds : nil, positive: true,
            absence: need == nil ? absence : needReason ?? .missing,
            provenance: provenance, sources: sleepSources),
          activityLoad: load(snapshot, date: date, now: now, calendar: gregorian),
          garminSleepScore: metric(
            sleepDTO?.resolvedDate == date
              ? sleepDTO?.sleepScores?.overall?.value.map(Double.init) : nil,
            absence: sleepDTO != nil && sleepDTO?.resolvedDate != date ? .dateMismatch : absence,
            provenance: provenance,
            sources: sleepSources.isEmpty ? skipped.map { [$0.source] } ?? [] : sleepSources),
          heartRateDay: heartRateDay(day, date: date, now: now, calendar: gregorian)))
      if date == dates.upperBound { break }
      let parts = date.rawValue.split(separator: "-").compactMap { Int($0) }
      guard parts.count == 3,
        let instant = gregorian.date(
          from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)),
        let next = gregorian.date(byAdding: .day, value: 1, to: instant)
      else { throw DateKey.ValidationError.invalidCalendarDate }
      date = label(next, calendar: gregorian)
    }
    return result
  }

  private static func heartRateDay(
    _ day: GarminDaySnapshot?, date: DateKey, now: Date, calendar: Calendar
  ) -> LoadHeartRateDay? {
    guard let selected = latest(day, families: [.heartRate]),
      case .heartRate(let dto) = selected.projection, dto.calendarDate == date
    else { return nil }
    let descriptors = dto.heartRateValueDescriptors
    let declaredHeartIndex = descriptors?.first(where: { $0.key == "heartrate" })?.index
    let rawHeartIndex = declaredHeartIndex.flatMap { $0 >= 0 ? Int(exactly: $0) : nil } ?? 1
    let rawReadings = (dto.heartRateValues ?? []).filter { row in
      row.indices.contains(rawHeartIndex) && (row[rawHeartIndex] ?? 0) > 0
    }
    guard !rawReadings.isEmpty else { return nil }
    var restValue = dto.restingHeartRate.flatMap { $0 > 0 ? Double($0) : nil }
    var restSources = source(selected)
    if restValue == nil, let summary = latest(day, families: [.dailySummaries]),
      case .dailySummary(let summaryDTO) = summary.projection,
      summaryDTO.calendarDate == date, let resting = summaryDTO.heartRate?.restingValue, resting > 0
    {
      restValue = Double(resting)
      restSources = source(summary)
    }
    let parser = ISO8601DateFormatter()
    func timestamp(_ text: String?) -> Date? {
      guard let text else { return nil }
      let zoned = text.hasSuffix("Z") ? text : text + "Z"
      parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      if let value = parser.date(from: zoned) { return value }
      parser.formatOptions = [.withInternetDateTime]
      return parser.date(from: zoned)
    }
    guard let descriptors,
      let timeIndex = descriptors.first(where: { $0.key == "timestamp" })?.index,
      let heartIndex = descriptors.first(where: { $0.key == "heartrate" })?.index,
      timeIndex >= 0, heartIndex >= 0,
      let start = timestamp(dto.startTimestampGMT)
    else {
      // Recorded HR exists, but optional timing metadata cannot establish intervals.
      // Publish calibration-pending zero without synthesizing timestamps or a TRIMP value.
      let evidence = metric(
        Double(rawReadings.count), coverage: .partial,
        sources: source(selected), coverageSources: source(selected)
      ).scoringMetric
      return LoadHeartRateDay(
        samples: [],
        restingHeartRate: metric(
          restValue, positive: true,
          coverage: .partial, sources: restSources
        ).scoringMetric,
        evidence: evidence, elapsedSeconds: 0)
    }
    // Garmin's UTC start is midnight on its recorded local day. The phone's current timezone
    // must not reinterpret historical samples or move them onto another calendar date.
    let captured = min(now, selected.fetchedAt)
    let elapsed = min(max(captured.timeIntervalSince(start), 0), 86_400)
    var byTimestamp: [Int64: Double] = [:]
    for row in dto.heartRateValues ?? [] {
      guard row.indices.contains(Int(timeIndex)), row.indices.contains(Int(heartIndex)),
        let stamp = row[Int(timeIndex)], let bpm = row[Int(heartIndex)], bpm > 0,
        stamp >= Int64(start.timeIntervalSince1970 * 1000),
        Double(stamp) / 1000 < start.timeIntervalSince1970 + 86_400,
        Double(stamp) / 1000 <= captured.timeIntervalSince1970
      else { continue }
      // Conflicting duplicates retain the lower recorded reading, independent of array order.
      byTimestamp[stamp] = min(byTimestamp[stamp] ?? Double(bpm), Double(bpm))
    }
    let samples = byTimestamp.sorted { $0.key < $1.key }.map {
      LoadHeartRateSample(
        seconds: Double($0.key) / 1000 - start.timeIntervalSince1970, bpm: $0.value)
    }
    guard !samples.isEmpty else { return nil }
    let coverage: ScoringCoverage = elapsed >= 86_400 ? .complete : .partial
    let evidence = metric(
      Double(samples.count), coverage: coverage, sources: source(selected),
      coverageSources: source(selected)
    ).scoringMetric
    let resting = metric(
      restValue, positive: true,
      coverage: coverage, sources: restSources
    ).scoringMetric
    return LoadHeartRateDay(
      samples: samples, restingHeartRate: resting,
      evidence: evidence, elapsedSeconds: elapsed)
  }

  private static func latest(_ day: GarminDaySnapshot?, families: [GarminPayload.Family])
    -> GarminDayValue?
  {
    day?.values.filter { families.contains($0.family) }.max { lhs, rhs in
      if lhs.fetchedAt == rhs.fetchedAt {
        return (families.firstIndex(of: lhs.family) ?? 0)
          > (families.firstIndex(of: rhs.family) ?? 0)
      }
      return lhs.fetchedAt < rhs.fetchedAt
    }
  }

  private static func source(_ value: GarminDayValue?) -> [ScoringSource] {
    value.map {
      [ScoringSource(family: $0.family, responseID: $0.sourceResponseID, fetchedAt: $0.fetchedAt)]
    } ?? []
  }

  private static func metric(
    _ value: Double?, positive: Bool = false, coverage: ScoringCoverage = .complete,
    absence: ScoringMissingReason = .missing,
    provenance: ScoringDateProvenance = .recorded, sources: [ScoringSource],
    coverageSources: [ScoringSource] = []
  ) -> ScoringMetric {
    guard let value else {
      return ScoringMetric(
        value: nil, reason: absence, coverage: absence == .partial ? .partial : .unknown,
        dateProvenance: sources.isEmpty ? .unknown : provenance, sources: sources,
        coverageSources: coverageSources)
    }
    guard value.isFinite, positive ? value > 0 : value >= 0 else {
      return ScoringMetric(
        value: nil, reason: .invalidValue, coverage: .unknown,
        dateProvenance: provenance, sources: sources, coverageSources: coverageSources)
    }
    return ScoringMetric(
      value: value, reason: coverage == .partial ? .partial : nil, coverage: coverage,
      dateProvenance: provenance, sources: sources, coverageSources: coverageSources)
  }

  private static func load(
    _ snapshot: GarminScoringSnapshot, date: DateKey, now: Date, calendar: Calendar
  ) -> ScoringMetric {
    let evidence = snapshot.activityCoverage.filter { $0.dates.contains(date) }.max {
      $0.fetchedAt < $1.fetchedAt
    }
    let coverageSources = evidence?.sources ?? []
    guard let evidence, evidence.completePagination else {
      return metric(
        nil, absence: evidence?.reason ?? .missing, sources: [], coverageSources: coverageSources)
    }
    let capturedDay = label(min(now, evidence.fetchedAt), calendar: calendar)
    guard date <= capturedDay else {
      return metric(nil, sources: [], coverageSources: coverageSources)
    }
    var sources: [ScoringSource] = []
    var total = 0.0
    // Membership comes from this accepted page chain. Older cached/deleted activities cannot
    // reappear merely because persistence retains their history.
    for id in evidence.activityIDsByDate[date, default: []].sorted() {
      guard let activity = snapshot.activities.first(where: { $0.activityID == id }),
        activity.date == date
      else {
        return metric(
          nil, absence: .dateMismatch, sources: sources, coverageSources: coverageSources)
      }
      let value: Double?
      let family: GarminPayload.Family
      if let detail = activity.detail, !activity.needsDetailRefresh {
        value = detail.summaryDTO?.activityTrainingLoad
        family = .activity
      } else {
        value = activity.summary?.activityTrainingLoad
        family = .activities
      }
      guard let responseID = activity.sourceResponseIDs[family],
        let source = snapshot.sourceMetadata[responseID], source.family == family
      else {
        return metric(nil, sources: sources, coverageSources: coverageSources)
      }
      if !sources.contains(source) { sources.append(source) }
      guard let value, value.isFinite, value >= 0 else {
        return metric(
          nil, absence: value == nil ? .missing : .invalidValue, sources: sources,
          coverageSources: coverageSources)
      }
      total += value
    }
    return metric(
      total, coverage: date < capturedDay ? .complete : .partial, sources: sources,
      coverageSources: coverageSources)
  }

  private static func label(_ instant: Date, calendar: Calendar) -> DateKey {
    let components = calendar.dateComponents([.year, .month, .day], from: instant)
    // Calendar date components for a valid Date in a Gregorian calendar are always present.
    return DateKey(
      rawValue: String(
        format: "%04d-%02d-%02d", components.year!, components.month!, components.day!))!
  }
}
