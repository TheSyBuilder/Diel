import Foundation
import ScoringKit

/// A display projection of accepted stored values. It never supplies scoring inputs.
nonisolated struct TodayHighlights: Equatable, Sendable {
  let sleepSeconds: Double?
  let sleepWindow: SleepWindow?
  let sleepDuration: String
  let sleepComparison: String
  let stages: [SleepStageTotal]
  let steps: Int64?
  let activeMinutes: Int64?
  let activeCalories: Int64?
  let activities: [TodayActivity]
  let battery: [BatterySample]
  let batteryLatest: Int?
  /// Today's morning, before Garmin has received last night from the band.
  let awaitingNight: Bool

  init(
    day: ScoredDay, projection: GarminDaySnapshot?, activities: [GarminActivitySnapshot],
    awaitingNight: Bool = false
  ) {
    self.awaitingNight = awaitingNight
    sleepSeconds =
      day.input.sleepSeconds.coverage == .complete && day.input.sleepSeconds.reason == nil
      ? day.input.sleepSeconds.value : nil
    sleepDuration = TodayPresentation.duration(day.input.sleepSeconds)
    sleepComparison = TodayPresentation.sleepComparison(
      duration: day.input.sleepSeconds, need: day.input.sleepNeedSeconds)
    let sleep = projection?.sleep
    sleepWindow = SleepWindow(day: day, projection: projection)
    stages = [
      SleepStageTotal(stage: .deep, seconds: sleep?.deepSleepSeconds),
      SleepStageTotal(stage: .light, seconds: sleep?.lightSleepSeconds),
      SleepStageTotal(stage: .rem, seconds: sleep?.remSleepSeconds),
      SleepStageTotal(stage: .awake, seconds: sleep?.awakeSleepSeconds),
    ].compactMap { $0 }
    let summary = projection?.dailySummary
    activeCalories = Self.nonnegative(summary?.calories?.burnedActive)
    steps = Self.nonnegative(projection?.steps?.totalSteps ?? summary?.movement?.steps?.value)
    if let moderate = summary?.intensityMinutes?.moderate,
      let vigorous = summary?.intensityMinutes?.vigorous,
      moderate >= 0, vigorous >= 0
    {
      activeMinutes = moderate + vigorous
    } else {
      activeMinutes = nil
    }
    self.activities = activities.map(TodayActivity.init)
    battery = BatterySample.traced(BatterySample.samples(projection?.bodyBattery))
    batteryLatest = battery.last?.value
  }

  private static func nonnegative(_ value: Int64?) -> Int64? {
    value.flatMap { $0 >= 0 ? $0 : nil }
  }
}

/// Recorded sleep bounds. A sleep window alone does not supply stage timing.
nonisolated struct SleepWindow: Equatable {
  let start: Date
  let end: Date
  let localStart: Date?
  let localEnd: Date?

  init?(day: ScoredDay, projection: GarminDaySnapshot?) {
    self.init(duration: day.input.sleepSeconds, date: day.input.date, projection: projection)
  }

  init?(duration: ScoringKit.ScoringMetric, date: ScoringDate, projection: GarminDaySnapshot?) {
    guard duration.coverage == .complete, duration.reason == nil,
      let seconds = duration.value, seconds.isFinite, seconds > 0,
      projection?.date.rawValue == date.rawValue,
      let sleep = projection?.sleep, sleep.calendarDate?.rawValue == date.rawValue,
      let start = sleep.sleepStartTimestampGMT, let end = sleep.sleepEndTimestampGMT,
      start > 0, end > start,
      (Double(end) - Double(start)) / 1000 >= seconds
    else { return nil }
    self.start = Date(timeIntervalSince1970: Double(start) / 1000)
    self.end = Date(timeIntervalSince1970: Double(end) / 1000)
    if let start = sleep.sleepStartTimestampLocal, let end = sleep.sleepEndTimestampLocal,
      start > 0, end > start,
      abs(Double(start) - self.start.timeIntervalSince1970 * 1000) <= 14 * 60 * 60 * 1000,
      abs(Double(end) - self.end.timeIntervalSince1970 * 1000) <= 14 * 60 * 60 * 1000
    {
      localStart = Date(timeIntervalSince1970: Double(start) / 1000)
      localEnd = Date(timeIntervalSince1970: Double(end) / 1000)
    } else {
      localStart = nil
      localEnd = nil
    }
  }

  var startText: String { timeText(localStart ?? start, local: localStart != nil) }
  var endText: String { timeText(localEnd ?? end, local: localEnd != nil) }

  private func timeText(_ date: Date, local: Bool) -> String {
    date.formatted(
      Date.FormatStyle(
        date: .omitted, time: .shortened,
        timeZone: local ? TimeZone(secondsFromGMT: 0)! : .current))
  }
}

/// A calendar evidence window, independent of score and baseline eligibility.
nonisolated struct ReadinessLearningHistory: Equatable {
  nonisolated struct Tick: Identifiable, Equatable {
    let date: ScoringDate
    let complete: Bool
    var id: ScoringDate { date }
  }

  let ticks: [Tick]
  let isLearning: Bool
  let count: Int

  init(day: ScoredDay, history: [ScoredDay]) {
    let context = day.readinessContext
    isLearning = [
      context.latestHRV.reference.reason,
      context.restingHeartRate.reference.reason,
      context.ewmaEvidence?.hrvTrendReference.reason,
      context.ewmaEvidence?.rhrTrendReference.reason,
      context.hrvTrend.reason,
      context.restingHeartRateTrend.reason,
    ].contains(.insufficientHistory)
    let groups = Dictionary(grouping: history.filter { $0.input.date != day.input.date } + [day]) {
      $0.input.date
    }
    ticks = (0..<60).reversed().compactMap { offset in
      guard let date = day.input.date.adding(days: -offset) else { return nil }
      let days = groups[date] ?? []
      guard days.count == 1, let input = days.first?.input else {
        return Tick(date: date, complete: false)
      }
      let complete =
        Self.isComplete(input.nightlyHRVMilliseconds)
        && Self.isComplete(input.restingHeartRateBPM)
      return Tick(date: date, complete: complete)
    }
    count = ticks.filter(\.complete).count
  }

  private static func isComplete(_ metric: ScoringKit.ScoringMetric) -> Bool {
    guard metric.coverage == .complete, metric.reason == nil, let value = metric.value else {
      return false
    }
    return value.isFinite && value > 0
  }

  func pulses(on date: ScoringDate?) -> Bool {
    isLearning && ticks.last?.date == date && ticks.last?.complete == true
  }
}

/// The week chart needs three real scores; its learning count remains paired-reading history.
nonisolated struct TodayWeekSummary: Sendable {
  let points: [DayChartPoint]
  let learningCount: Int
  let showsChart: Bool
  var showsLearningCount: Bool { !showsChart || learningCount < 60 }

  init(day: ScoredDay, history: [ScoredDay]) {
    points = DayChartPoint.points(
      metric: .readiness, ending: day.input.date, count: 7, history: history)
    learningCount = ReadinessLearningHistory(day: day, history: history).count
    showsChart = points.compactMap(\.value).count >= 3
  }
}

nonisolated enum SleepStage: String, CaseIterable, Identifiable {
  case deep, light, rem, awake
  var id: String { rawValue }
  var title: String {
    switch self {
    case .deep: "Deep"
    case .light: "Light"
    case .rem: "REM"
    case .awake: "Awake"
    }
  }
  static let compositionOrder: [Self] = [.deep, .rem, .light, .awake]

  var level: Double {
    switch self {
    case .deep: 1
    case .light: 0.72
    case .rem: 0.48
    case .awake: 0.24
    }
  }
}

nonisolated struct SleepStageTotal: Identifiable, Equatable {
  let stage: SleepStage
  let seconds: Int64
  var id: SleepStage { stage }
  var duration: String {
    let minutes = seconds / 60
    return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
  }
  init?(stage: SleepStage, seconds: Int64?) {
    guard let seconds, seconds >= 0 else { return nil }
    self.stage = stage
    self.seconds = seconds
  }

  static func selected(at fraction: Double, in stages: [Self]) -> SleepStage? {
    let total = stages.reduce(Int64.zero) { $0 + $1.seconds }
    guard total > 0 else { return nil }
    let position = min(max(fraction, 0), 1) * Double(total)
    var end = 0.0
    for stage in stages where stage.seconds > 0 {
      end += Double(stage.seconds)
      if position < end { return stage.stage }
    }
    return stages.last(where: { $0.seconds > 0 })?.stage
  }
}

nonisolated struct TodayActivity: Identifiable, Equatable {
  let id: Int64
  let title: String
  let icon: String
  let duration: String
  let load: Double?

  init(_ activity: GarminActivitySnapshot) {
    id = activity.activityID
    let type = activity.detail?.activityTypeDTO?.typeKey ?? activity.summary?.activityType?.typeKey
    (title, icon) = Self.kind(type)
    let seconds = activity.detail?.summaryDTO?.duration ?? activity.summary?.duration
    if let seconds, seconds.isFinite, seconds >= 0 {
      let minutes = Int(seconds / 60)
      duration = TodayPresentation.duration(minutes: minutes)
    } else {
      duration = "Duration unavailable"
    }
    let value =
      activity.detail?.summaryDTO?.activityTrainingLoad
      ?? activity.summary?.activityTrainingLoad
    load = value.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
  }

  static func kind(_ key: String?) -> (String, String) {
    switch key {
    case "running", "trail_running", "treadmill_running", "indoor_running": ("Run", "figure.run")
    case "cycling", "road_biking", "mountain_biking", "indoor_cycling", "virtual_ride":
      ("Ride", "figure.outdoor.cycle")
    case "walking", "casual_walking", "indoor_walking": ("Walk", "figure.walk")
    case "hiking", "mountaineering": ("Hike", "figure.hiking")
    case "swimming", "lap_swimming", "open_water_swimming": ("Swim", "figure.pool.swim")
    case "strength_training":
      ("Strength", "figure.strengthtraining.traditional")
    case "fitness_equipment":
      ("Gym", "figure.mixed.cardio")
    case "bouldering":
      ("Bouldering", "figure.climbing")
    case "yoga": ("Yoga", "figure.yoga")
    case "pilates": ("Pilates", "figure.pilates")
    case "elliptical": ("Elliptical", "figure.elliptical")
    case "rowing", "indoor_rowing": ("Row", "figure.rower")
    case "cardio", "hiit": ("Cardio", "figure.mixed.cardio")
    default: ("Activity", "figure.mixed.cardio")
    }
  }
}

nonisolated struct BatterySample: Identifiable, Equatable {
  let date: Date
  let value: Int
  let segment: Int
  var id: Date { date }

  static func samples(_ battery: BodyBatteryDTO?) -> [Self] {
    guard let descriptors = battery?.bodyBatteryValueDescriptorDTOList,
      let timeIndex = descriptors.first(where: { $0.bodyBatteryValueDescriptorKey == "timestamp" })?
        .bodyBatteryValueDescriptorIndex.flatMap(Int.init(exactly:)),
      let valueIndex = descriptors.first(where: {
        $0.bodyBatteryValueDescriptorKey == "bodyBatteryLevel"
      })?
      .bodyBatteryValueDescriptorIndex.flatMap(Int.init(exactly:))
    else { return [] }
    // Rows may arrive out of order. The last valid row at a timestamp wins.
    // A missing row is not a reading and does not break a short collection interval.
    var readings: [Int64: Int] = [:]
    for row in battery?.bodyBatteryValuesArray ?? [] {
      guard row.indices.contains(timeIndex), row.indices.contains(valueIndex),
        let time = row[timeIndex], time > 0, let value = row[valueIndex],
        (0...100).contains(value)
      else { continue }
      readings[time] = Int(value)
    }
    var result: [Self] = []
    var segment = 0
    var previous: Date?
    for time in readings.keys.sorted() {
      let date = Date(timeIntervalSince1970: Double(time) / 1000)
      if let previous, date.timeIntervalSince(previous) > 4 * 60 * 60 {
        segment += 1
      }
      result.append(Self(date: date, value: readings[time]!, segment: segment))
      previous = date
    }
    return result
  }

  static func canShowCurve(_ samples: [Self]) -> Bool { samples.count >= 3 }

  /// Consecutive readings further apart than this were off-wrist or not yet uploaded.
  static let traceGap: TimeInterval = 45 * 60

  /// Renumbers sections so a day's trace breaks wherever consecutive readings are over 45 minutes
  /// apart. Values and times are unchanged.
  static func traced(_ samples: [Self]) -> [Self] {
    var segment = 0
    var previous: Date?
    return samples.map { sample in
      if let previous, sample.date.timeIntervalSince(previous) > traceGap { segment += 1 }
      previous = sample.date
      return Self(date: sample.date, value: sample.value, segment: segment)
    }
  }

  /// Readings alone in their section. They are drawn as points, never as a line or area sliver.
  static func isolated(_ samples: [Self]) -> [Self] {
    let counts = Dictionary(grouping: samples, by: \.segment).mapValues(\.count)
    return samples.filter { counts[$0.segment] == 1 }
  }

  /// The Now label sits between gridlines, on the side away from the latest reading.
  static func nowLabelLevel(latest: Self?) -> Int {
    (latest?.value ?? 0) >= 50 ? 25 : 75
  }

  static func nearest(to date: Date, in samples: [Self]) -> Self? {
    samples.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
  }
}

/// A source-dated day of Garmin measurements, with no synthetic wake value or totals.
nonisolated struct BodyBatteryDay: Identifiable, Equatable, Sendable {
  let date: ScoringDate
  let start: Date
  let end: Date
  let midday: Date
  let samples: [BatterySample]
  let charged: Int64?
  let drained: Int64?
  let high: Int?
  let low: Int?
  private let dailyHigh: Int?
  private let dailyLow: Int?
  let wake: BatterySample?
  private let wakeAt: Date?
  var id: ScoringDate { date }

  init(date: ScoringDate, projection: GarminDaySnapshot?, calendar: Calendar = .current) {
    self.date = date
    let parts = date.rawValue.split(separator: "-").compactMap { Int($0) }
    let midnight = calendar.date(
      from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))!
    let dayStart = calendar.startOfDay(for: midnight)
    let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
    start = dayStart
    end = dayEnd
    midday = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: dayStart)!
    let source = projection?.date.rawValue == date.rawValue ? projection : nil
    let battery = source?.bodyBattery
    let summary = source?.dailySummary?.bodyBattery
    samples = BatterySample.traced(
      BatterySample.samples(battery).filter { $0.date >= dayStart && $0.date < dayEnd })
    charged = (battery?.charged ?? summary?.chargedValue).flatMap { $0 >= 0 ? $0 : nil }
    drained = (battery?.drained ?? summary?.drainedValue).flatMap { $0 >= 0 ? $0 : nil }
    dailyHigh = summary?.maxValue.flatMap { (0...100).contains($0) ? Int($0) : nil }
    dailyLow = summary?.minValue.flatMap { (0...100).contains($0) ? Int($0) : nil }
    wakeAt = source?.sleep?.sleepEndTimestampGMT.map {
      Date(timeIntervalSince1970: Double($0) / 1000)
    }
    high = dailyHigh ?? samples.map(\.value).max()
    low = dailyLow ?? samples.map(\.value).min()
    if let sleep = source?.sleep, sleep.calendarDate?.rawValue == date.rawValue,
      let wakeTime = sleep.sleepEndTimestampGMT, let bedtime = sleep.sleepStartTimestampGMT,
      bedtime > 0, wakeTime > bedtime
    {
      let time = Date(timeIntervalSince1970: Double(wakeTime) / 1000)
      if time >= start, time < end, let nearest = BatterySample.nearest(to: time, in: samples),
        abs(nearest.date.timeIntervalSince(time)) <= 15 * 60
      {
        wake = nearest
      } else {
        wake = nil
      }
    } else {
      wake = nil
    }
  }

  /// Future timestamps cannot supply a plotted point, hero value or observed extrema.
  func samples(through now: Date) -> [BatterySample] {
    guard now >= start else { return [] }
    return samples.filter { $0.date <= now }
  }

  func high(through now: Date) -> Int? {
    guard now >= start else { return nil }
    return dailyHigh ?? samples(through: now).map(\.value).max()
  }

  func low(through now: Date) -> Int? {
    guard now >= start else { return nil }
    return dailyLow ?? samples(through: now).map(\.value).min()
  }

  func wake(through now: Date) -> BatterySample? {
    guard let wakeAt, wakeAt <= now else { return nil }
    return wake.flatMap { $0.date <= now ? $0 : nil }
  }

  static func week(ending date: ScoringDate, projections: [GarminDaySnapshot], calendar: Calendar)
    -> [Self]
  {
    let byDate = Dictionary(
      projections.map { ($0.date.rawValue, $0) }, uniquingKeysWith: { first, _ in first })
    return (0..<7).reversed().compactMap { offset in
      guard let date = date.adding(days: -offset) else { return nil }
      return Self(date: date, projection: byDate[date.rawValue], calendar: calendar)
    }
  }
}

nonisolated struct DayChartPoint: Identifiable, Equatable {
  let date: ScoringDate
  let plotDate: Date
  let value: Double?
  let normal: ClosedRange<Double>?
  let reason: String
  let colour: DialColour
  let segment: Int
  var id: ScoringDate { date }

  static func points(metric: TodayMetric, ending end: ScoringDate, count: Int, history: [ScoredDay])
    -> [Self]
  {
    let byDate = Dictionary(
      history.map { ($0.input.date, $0) }, uniquingKeysWith: { first, _ in first })
    var segment = 0
    return (0..<count).reversed().compactMap { offset in
      guard let date = end.adding(days: -offset), let plotDate = TodayPresentation.displayDate(date)
      else { return nil }
      let day = byDate[date]
      let dial = day.map {
        TodayPresentation(day: $0, history: history).dials.first { $0.metric == metric }!
      }
      if dial?.value == nil { segment += 1 }
      return Self(
        date: date, plotDate: plotDate, value: dial?.value,
        normal: normalBand(metric: metric, before: date, history: history),
        reason: dial?.reason ?? "No reading for this day", colour: dial?.colour ?? .unavailable,
        segment: segment)
    }
  }

  /// The shared chart draws one band across its complete calendar viewport, or none.
  static func fullWidthNormalBand(in points: [Self]) -> [Self] {
    guard points.count >= 2,
      points.allSatisfy({ point in
        guard let normal = point.normal else { return false }
        return normal.lowerBound.isFinite && normal.upperBound.isFinite
      }),
      zip(points, points.dropFirst()).allSatisfy({ previous, next in
        previous.date.adding(days: 1) == next.date
      })
    else { return [] }
    return points
  }

  static func normalBand(metric: TodayMetric, before date: ScoringDate, history: [ScoredDay])
    -> ClosedRange<Double>?
  {
    guard let start = date.adding(days: metric == .load ? -28 : -60) else { return nil }
    let values = history.filter { $0.input.date >= start && $0.input.date < date }.compactMap {
      day -> Double? in
      switch metric {
      case .readiness: return day.readiness.value
      case .sleep: return day.sleep.value
      case .load:
        guard day.load.status == .available, day.load.input.coverage == .complete,
          day.load.input.reason == nil, day.load.allDay?.calibrationReason == nil
        else { return nil }
        return day.load.value
      }
    }
    guard values.count >= 14 else { return nil }
    let mean = values.reduce(0, +) / Double(values.count)
    let sd = sqrt(values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count - 1))
    return max(0, mean - sd)...min(100, mean + sd)
  }
}
