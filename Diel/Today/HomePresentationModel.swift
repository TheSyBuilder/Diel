import Foundation
import Observation
import ScoringKit

/// Immutable, ready-to-render values shared by Home and its dial destinations.
nonisolated final class TodaySnapshot: Sendable {
  let revision: CredentialRevision
  let generation: UInt64
  let day: ScoredDay
  let history: [ScoredDay]
  let presentation: TodayPresentation
  let highlights: TodayHighlights
  let week: TodayWeekSummary
  let learning: ReadinessLearningHistory
  let readinessRows: [TodayEvidenceRow]
  let month: [TodayMetric: [DayChartPoint]]
  let recentSleep: [RecentSleepPoint]
  let recentSleepScale: RecentSleepScale
  let batteryDays: [BodyBatteryDay]

  init(
    revision: CredentialRevision, generation: UInt64 = 0, day: ScoredDay, history: [ScoredDay],
    projection: GarminDaySnapshot?, activities: [GarminActivitySnapshot],
    batteryProjections: [GarminDaySnapshot] = [], calendar: Calendar = .current,
    awaitingNight: Bool = false
  ) {
    self.revision = revision
    self.generation = generation
    self.day = day
    self.history = history
    presentation = TodayPresentation(day: day, history: history, awaitingNight: awaitingNight)
    highlights = TodayHighlights(
      day: day, projection: projection, activities: activities, awaitingNight: awaitingNight)
    week = TodayWeekSummary(day: day, history: history)
    learning = ReadinessLearningHistory(day: day, history: history)
    readinessRows = presentation.readinessRows + Array(presentation.sleepRows.prefix(3))
    month = Dictionary(
      uniqueKeysWithValues: [TodayMetric.readiness, .load].map { metric in
        (
          metric,
          DayChartPoint.points(metric: metric, ending: day.input.date, count: 30, history: history)
        )
      })
    recentSleep = RecentSleepPoint.points(day: day, history: history)
    recentSleepScale = RecentSleepScale(points: recentSleep)
    batteryDays = BodyBatteryDay.week(
      ending: day.input.date,
      projections: batteryProjections.isEmpty ? projection.map { [$0] } ?? [] : batteryProjections,
      calendar: calendar)
  }
}

nonisolated struct TodaySnapshotRequest: Equatable, Sendable {
  let revision: CredentialRevision?
  let generation: UInt64
  let date: ScoringDate?
  var sampleOverride: String? = nil
  var enabled = true
  var timeZone = TimeZone.current.identifier
  /// Before launch settles, a missing requested day shows yesterday's cached day instead.
  /// Older days are never shown in today's place.
  var fallsBackToYesterday = false
  /// Local time is before noon, so an absent last night may still arrive from the band.
  var morning = false
}

nonisolated struct HomeBriefInputRequest: Equatable, Sendable {
  let revision: CredentialRevision?
  let generation: UInt64
  let date: ScoringDate?
  let day: MorningDay
  let answer: CheckInSnapshot?
  let enabled: Bool
}

nonisolated final class PreparedMorningBrief: Sendable {
  let context: BriefCacheContext
  let input: BriefInput
  let request: HomeBriefInputRequest

  init(context: BriefCacheContext, input: BriefInput, request: HomeBriefInputRequest) {
    self.context = context
    self.input = input
    self.request = request
  }
}

/// These boundaries are synchronous so their complete work can also be exercised on a device-sized stack.
nonisolated enum HomePresentationBuilder {
  static func selectedDate(request: TodaySnapshotRequest, days: [ScoredDay]) -> ScoringDate? {
    assert(!Thread.isMainThread)
    if let override = request.sampleOverride, let date = ScoringDate(rawValue: override),
      days.contains(where: { day in
        day.input.date == date
          && ScoringMetricKind.allCases.contains { !day.input[$0].sources.isEmpty }
      })
    {
      return date
    }
    if request.fallsBackToYesterday, let requested = request.date,
      !days.contains(where: { $0.input.date == requested }),
      let yesterday = requested.adding(days: -1),
      days.contains(where: { $0.input.date == yesterday })
    {
      return yesterday
    }
    return request.date
  }

  static func snapshot(
    request: TodaySnapshotRequest, day: ScoredDay, history: [ScoredDay],
    projection: GarminDaySnapshot?, activities: [GarminActivitySnapshot],
    batteryProjections: [GarminDaySnapshot] = []
  ) -> TodaySnapshot? {
    assert(!Thread.isMainThread)
    guard request.enabled, let revision = request.revision else { return nil }
    return TodaySnapshot(
      revision: revision, generation: request.generation, day: day, history: history,
      projection: projection,
      activities: activities.filter { $0.date?.rawValue == day.input.date.rawValue },
      batteryProjections: batteryProjections,
      calendar: {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: request.timeZone) ?? .current
        return calendar
      }(),
      awaitingNight: request.morning && day.input.date == request.date
        && TodayPresentation.awaitsLastNight(day))
  }

  static func brief(request: HomeBriefInputRequest, days: [ScoredDay], history: [ScoredDay])
    -> PreparedMorningBrief?
  {
    assert(!Thread.isMainThread)
    guard request.enabled, let answer = request.answer, answer.dayID == request.day.id else {
      return nil
    }
    let day = days.first { $0.input.date == request.date }
    let input = BriefInputBuilder.make(day: day, history: history, checkIn: answer)
    return PreparedMorningBrief(
      context: BriefCacheContext(
        dayID: request.day.id, scopeID: request.revision?.id.uuidString ?? "unscoped",
        scoreFingerprint: input.scoreFingerprint), input: input, request: request)
  }
}

@Observable
@MainActor
final class HomePresentationModel {
  private(set) var snapshot: TodaySnapshot?
  private(set) var selectedDate: ScoringDate?
  /// The day the latest request resolved to, published as soon as it is chosen. Unlike
  /// `selectedDate`, it does not wait for the snapshot, so a sample brief never describes
  /// the reference day while the chosen day's snapshot is still building.
  private(set) var resolvedDate: ScoringDate?
  private(set) var preparedBrief: PreparedMorningBrief?
  @ObservationIgnored private var snapshotRequest: TodaySnapshotRequest?
  @ObservationIgnored private var snapshotJob: Task<Void, Never>?
  @ObservationIgnored private var briefRequest: HomeBriefInputRequest?
  @ObservationIgnored private var briefJob: Task<Void, Never>?

  func clear() {
    snapshotJob?.cancel()
    briefJob?.cancel()
    snapshotRequest = nil
    briefRequest = nil
    snapshot = nil
    selectedDate = nil
    resolvedDate = nil
    preparedBrief = nil
  }

  func updateSnapshot(
    request: TodaySnapshotRequest, days: [ScoredDay], history: [ScoredDay], store: GarminStore?
  ) async {
    if snapshotRequest == request {
      await snapshotJob?.value
      return
    }
    snapshotJob?.cancel()
    snapshotRequest = request
    guard request.enabled, let revision = request.revision else {
      snapshot = nil
      selectedDate = request.date
      resolvedDate = request.date
      return
    }
    // Keep the previous valid presentation during a refresh in this same scope and day.
    if snapshot?.revision != revision { snapshot = nil }
    let job = Task {
      let selection = await Task.detached {
        let date = HomePresentationBuilder.selectedDate(request: request, days: days)
        return (date, days.first { $0.input.date == date })
      }.value
      guard !Task.isCancelled, snapshotRequest == request else { return }
      resolvedDate = selection.0
      guard let day = selection.1, let date = selection.0 else {
        selectedDate = selection.0
        snapshot = nil
        return
      }
      let projection = try? await store?.day(DateKey(rawValue: date.rawValue)!, revision: revision)
      let activities = try? await store?.activities(revision: revision)
      let batteryStart = date.adding(days: -6).flatMap { DateKey(rawValue: $0.rawValue) }
      let batteryProjections: [GarminDaySnapshot]
      if let batteryStart, let batteryEnd = DateKey(rawValue: date.rawValue) {
        batteryProjections =
          (try? await store?.days(in: batteryStart...batteryEnd, revision: revision)) ?? []
      } else {
        batteryProjections = []
      }
      guard !Task.isCancelled, snapshotRequest == request else { return }
      let result = await Task.detached {
        HomePresentationBuilder.snapshot(
          request: request, day: day, history: history, projection: projection,
          activities: activities ?? [], batteryProjections: batteryProjections)
      }.value
      guard !Task.isCancelled, snapshotRequest == request else { return }
      // The date and its snapshot change together, so the previous day stays until this one is ready.
      selectedDate = date
      snapshot = result
    }
    snapshotJob = job
    await job.value
  }

  func updateBrief(request: HomeBriefInputRequest, days: [ScoredDay], history: [ScoredDay]) async {
    if briefRequest == request {
      await briefJob?.value
      return
    }
    briefJob?.cancel()
    briefRequest = request
    guard request.enabled, request.answer != nil else {
      preparedBrief = nil
      return
    }
    if preparedBrief?.context.scopeID != (request.revision?.id.uuidString ?? "unscoped")
      || preparedBrief?.context.dayID != request.day.id
    {
      preparedBrief = nil
    }
    let job = Task {
      let result = await Task.detached {
        HomePresentationBuilder.brief(request: request, days: days, history: history)
      }.value
      guard !Task.isCancelled, briefRequest == request else { return }
      preparedBrief = result
    }
    briefJob = job
    await job.value
  }
}
