import Foundation
import Observation
import ScoringKit

nonisolated final class ScoredDay: Sendable, Equatable, Codable {
  let input: ScoringKit.ScoringDayInput
  let readiness: ReadinessV2Result
  let readinessV21: ReadinessV2Result
  let readinessOriginalV2: ReadinessV2Result
  let readinessV1: ScoreResult
  let readinessOriginalV1: ScoreResult
  let sleep: ScoreResult
  let load: LoadResult
  let readinessV1Context: ReadinessContext
  var readinessContext: ReadinessV2Context { readiness.context }

  init(
    input: ScoringKit.ScoringDayInput,
    readiness: ReadinessV2Result,
    readinessV21: ReadinessV2Result,
    readinessOriginalV2: ReadinessV2Result,
    readinessV1: ScoreResult,
    readinessOriginalV1: ScoreResult,
    sleep: ScoreResult,
    load: LoadResult,
    readinessV1Context: ReadinessContext
  ) {
    self.input = input
    self.readiness = readiness
    self.readinessV21 = readinessV21
    self.readinessOriginalV2 = readinessOriginalV2
    self.readinessV1 = readinessV1
    self.readinessOriginalV1 = readinessOriginalV1
    self.sleep = sleep
    self.load = load
    self.readinessV1Context = readinessV1Context
  }

  static func == (lhs: ScoredDay, rhs: ScoredDay) -> Bool {
    lhs === rhs
      || (lhs.input == rhs.input
        && lhs.readiness == rhs.readiness
        && lhs.readinessV21 == rhs.readinessV21
        && lhs.readinessOriginalV2 == rhs.readinessOriginalV2
        && lhs.readinessV1 == rhs.readinessV1
        && lhs.readinessOriginalV1 == rhs.readinessOriginalV1
        && lhs.sleep == rhs.sleep
        && lhs.load == rhs.load
        && lhs.readinessV1Context == rhs.readinessV1Context)
  }
}

/// Publish only revision-scoped score snapshots read back from the local store.
@Observable
@MainActor
final class ScoringService {
  private(set) var days: [ScoredDay] = []
  /// All local calendar history through the refresh end, independent of the display window.
  private(set) var history: [ScoredDay] = []
  /// Changes only when a score publication is replaced or cleared.
  private(set) var publicationGeneration: UInt64 = 0
  private(set) var revision: CredentialRevision?
  private(set) var isCalculating = false
  private(set) var calculationFailed = false
  let config: ScoringConfig
  private let snapshot:
    @Sendable (ClosedRange<DateKey>, CredentialRevision) async throws -> GarminScoringSnapshot
  private var generation = UUID()
  private let store: GarminStore?

  init(store: GarminStore, config: ScoringConfig = .v1) {
    self.config = config
    self.store = store
    snapshot = { dates, revision in try await store.scoringSnapshot(in: dates, revision: revision) }
  }

  /// Injectable actor boundary permits deterministic stale-publication checks without networking.
  init(
    config: ScoringConfig = .v1,
    snapshot:
      @escaping @Sendable (ClosedRange<DateKey>, CredentialRevision) async throws ->
      GarminScoringSnapshot
  ) {
    self.config = config
    store = nil
    self.snapshot = snapshot
  }

  func invalidate() {
    generation = UUID()
    days = []
    history = []
    publicationGeneration &+= 1
    revision = nil
    isCalculating = false
    calculationFailed = false
  }

  func bootstrap(
    in dates: ClosedRange<DateKey>, revision: CredentialRevision, now: Date, calendar: Calendar
  ) async {
    if self.revision != revision { invalidate() }
    let id = generation
    do {
      if let store {
        let cached = try await store.savedScores(revision: revision)
        guard generation == id, !Task.isCancelled else { return }
        let needsRecalculation = try await store.scoresNeedRecalculation(revision: revision)
        guard generation == id, !Task.isCancelled else { return }
        if !cached.isEmpty && !needsRecalculation {
          self.revision = revision
          history = cached.filter { $0.input.date.rawValue <= dates.upperBound.rawValue }
          days = history.filter { $0.input.date.rawValue >= dates.lowerBound.rawValue }
          publicationGeneration &+= 1
          return
        }
      }
      await refresh(in: dates, revision: revision, now: now, calendar: calendar)
    } catch {
      guard generation == id else { return }
      calculationFailed = true
    }
  }

  func refresh(
    in dates: ClosedRange<DateKey>, revision: CredentialRevision, now: Date,
    calendar: Calendar
  ) async {
    if self.revision != revision { invalidate() }
    generation = UUID()
    let id = generation
    self.revision = revision
    calculationFailed = false
    isCalculating = true
    defer {
      if generation == id {
        isCalculating = false
        if Task.isCancelled && history.isEmpty { self.revision = nil }
      }
    }
    do {
      let start = ScoringKit.ScoringDate(rawValue: dates.lowerBound.rawValue)!
      // Why rotation is derived from all locally stored past days, independent of the
      // displayed range. The broad query does not synthesize dates before stored evidence.
      let source: GarminScoringSnapshot
      let ticket: UUID?
      let sourceDates = DateKey(rawValue: "0001-01-01")!...dates.upperBound
      if let store {
        let captured = try await store.scoringCalculationSnapshot(
          in: sourceDates, revision: revision)
        source = captured.source
        ticket = captured.generation
      } else {
        source = try await snapshot(sourceDates, revision)
        ticket = nil
      }
      guard generation == id, !Task.isCancelled else { return }
      guard source.revision == revision else { throw GarminStoreError.staleRevision }
      let saved = try await store?.savedScores(revision: revision) ?? []
      let previousLoadResults = store == nil ? history : saved
      let savedLoadMinimums = try await store?.savedLoadMinimums(revision: revision) ?? [:]
      guard generation == id, !Task.isCancelled else { return }
      let config = config
      let originalV1 = try ScoringConfig(readinessDeviationScale: 20)
      let calculated = try await Task.detached {
        let storedDates =
          source.days.map(\.date)
          + source.activities.compactMap(\.date)
          + source.skippedSleep.compactMap(\.candidateDate)
        // A sync plan is a fetch bound, not evidence that earlier empty calendar days exist.
        guard let first = storedDates.min() else { return [ScoredDay]() }
        let previous = Dictionary(uniqueKeysWithValues: saved.map { ($0.input.date, $0.input) })
        let previousLoad = Dictionary(
          uniqueKeysWithValues: previousLoadResults.map { ($0.input.date, $0.load) })
        let today = TodayPresentation.dateKey(now, calendar: calendar)
        let inputs = try ScoringInputBuilder.build(
          source, in: first...dates.upperBound, now: now, calendar: calendar
        ).map { source in
          let input = source.scoringInput
          return Self.preservingValidMetrics(input, previous: previous[input.date])
        }
        let revised = ReadinessV2Score.calculateChronologically(
          days: inputs, history: inputs, config: .v2_2)
        let frozenV21 = ReadinessV2Score.calculateChronologically(
          days: inputs, history: inputs, config: .v2_1)
        return try inputs.indices.map { index in
          let day = inputs[index]
          let readiness = revised[index]
          return ScoredDay(
            input: day,
            readiness: readiness,
            readinessV21: frozenV21[index],
            readinessOriginalV2: ReadinessV2Score.calculate(day: day, history: inputs, config: .v2),
            readinessV1: ReadinessScore.calculate(day: day, history: inputs, config: config),
            readinessOriginalV1: ReadinessScore.calculate(
              day: day, history: inputs, config: originalV1),
            sleep: SleepScore.calculate(day: day, config: config),
            load: try Self.load(
              day: day, history: inputs, config: config,
              previous: day.date == today ? previousLoad[day.date] : nil,
              minimum: day.date == today ? savedLoadMinimums[day.date] : nil),
            readinessV1Context: ReadinessContext.calculate(
              day: day, history: inputs, config: config))
        }
      }.value
      guard generation == id, !Task.isCancelled else { return }
      let committed: [ScoredDay]
      if let store, let ticket {
        committed = try await store.saveScores(
          calculated, revision: revision, generation: ticket, at: now)
      } else {
        committed = calculated
      }
      guard generation == id, !Task.isCancelled else { return }
      history = committed.filter { $0.input.date.rawValue <= dates.upperBound.rawValue }
      days = history.filter { $0.input.date >= start }
      publicationGeneration &+= 1
      isCalculating = false
    } catch {
      guard generation == id else { return }
      if error as? GarminStoreError == .staleRevision {
        days = []
        history = []
        publicationGeneration &+= 1
        self.revision = nil
      }
      calculationFailed = !(error is CancellationError)
      isCalculating = false
    }
  }

  private nonisolated static func load(
    day: ScoringKit.ScoringDayInput, history: [ScoringKit.ScoringDayInput], config: ScoringConfig,
    previous: LoadResult?, minimum: Double?
  ) throws -> LoadResult {
    // A reloaded numeric floor is not evidence that the latest raw source supplied that
    // higher value. Reapplying an already-retained result would incorrectly collect its
    // new lower measurement's sources as provenance for the old numeric minimum.
    let measuredPrevious: LoadResult?
    if let minimum, let previous, previous.allDay?.retainedMinimum != nil,
      minimum >= (previous.value ?? -1)
    {
      measuredPrevious = nil
    } else {
      measuredPrevious = previous
    }
    let current = AllDayLoadScore.calculate(
      day: day, history: history, config: config, previous: measuredPrevious)
    guard let minimum, minimum > (current.value ?? -1),
      day.heartRateDay?.evidence.coverage == .partial, current.allDay != nil
    else { return current }
    // Reuse the scorer's existing retention rule. The numeric persisted floor has no
    // surviving raw source, so it must not claim the new source supplied the old minimum.
    guard
      var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(current))
        as? [String: Any],
      var input = json["input"] as? [String: Any],
      var evidence = json["allDay"] as? [String: Any]
    else { throw GarminStoreError.encoding }
    json["value"] = minimum
    input["sources"] = []
    input["coverageSources"] = []
    json["input"] = input
    evidence["maximumSources"] = []
    evidence["retainedSources"] = []
    json["allDay"] = evidence
    let floor = try JSONDecoder().decode(
      LoadResult.self, from: JSONSerialization.data(withJSONObject: json))
    return AllDayLoadScore.calculate(day: day, history: history, config: config, previous: floor)
  }

  private nonisolated static func preservingValidMetrics(
    _ current: ScoringKit.ScoringDayInput, previous: ScoringKit.ScoringDayInput?
  ) -> ScoringKit.ScoringDayInput {
    guard let previous else { return current }
    func keep(_ new: ScoringKit.ScoringMetric, _ old: ScoringKit.ScoringMetric)
      -> ScoringKit.ScoringMetric
    {
      let oldValid = old.value != nil && old.reason == nil && old.coverage == .complete
      let newValid = new.value != nil && new.reason == nil && new.coverage == .complete
      return oldValid && !newValid ? old : new
    }
    return ScoringKit.ScoringDayInput(
      date: current.date,
      nightlyHRVMilliseconds: keep(current.nightlyHRVMilliseconds, previous.nightlyHRVMilliseconds),
      restingHeartRateBPM: keep(current.restingHeartRateBPM, previous.restingHeartRateBPM),
      sleepSeconds: keep(current.sleepSeconds, previous.sleepSeconds),
      awakeSeconds: keep(current.awakeSeconds, previous.awakeSeconds),
      sleepNeedSeconds: keep(current.sleepNeedSeconds, previous.sleepNeedSeconds),
      activityLoad: keep(current.activityLoad, previous.activityLoad),
      garminSleepScore: keep(current.garminSleepScore, previous.garminSleepScore),
      heartRateDay: current.heartRateDay)
  }
}
