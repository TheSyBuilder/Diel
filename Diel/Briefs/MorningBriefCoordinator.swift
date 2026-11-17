import Foundation
import Observation

@Observable
@MainActor
final class MorningBriefCoordinator {
  private(set) var brief: Brief?
  private(set) var publishedContext: BriefCacheContext?
  @ObservationIgnored private let store: (any BriefCaching)?
  @ObservationIgnored private let generator: any BriefGenerator
  @ObservationIgnored private let generationTimeout: Duration
  nonisolated private struct Outcome: Sendable {
    let brief: Brief
    var retryAt: Date? = nil
    var superseded = false
  }
  nonisolated private struct Job: Sendable {
    let reservation: UUID
    let task: Task<Outcome, Never>
  }
  @ObservationIgnored private var jobs: [BriefCacheContext: Job] = [:]
  @ObservationIgnored private let now: @Sendable () -> Date
  @ObservationIgnored private let sleepUntil: @Sendable (Date) async throws -> Void
  @ObservationIgnored private var retry: Task<Void, Never>?
  @ObservationIgnored private var requestedInput: BriefInput?
  @ObservationIgnored private var requestedSettled = false
  @ObservationIgnored private var requestGeneration = UUID()
  /// Day and scope whose stored brief was already looked up, so cold launch reads it once.
  @ObservationIgnored private var storedLookup: String?
  @ObservationIgnored private var prewarmedDay: String?
  private var requestedContext: BriefCacheContext?

  init(
    store: (any BriefCaching)?, generator: any BriefGenerator,
    generationTimeout: Duration = .seconds(10),
    now: @escaping @Sendable () -> Date = { Date() },
    sleepUntil: @escaping @Sendable (Date) async throws -> Void = { deadline in
      try await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow)))
    }
  ) {
    self.store = store
    self.generator = generator
    self.generationTimeout = generationTimeout
    self.now = now
    self.sleepUntil = sleepUntil
  }

  /// A newer score context of the same day and scope keeps the last published brief on screen
  /// until its own brief publishes. Another day or scope never shows it.
  func visibleBrief(for context: BriefCacheContext?) -> Brief? {
    guard let context, let publishedContext, Self.sameDay(context, publishedContext) else {
      return nil
    }
    return brief
  }

  /// Warms the model once per launch and day, only while the day has no completed brief.
  func prewarm(dayID: String, scopeID: String) async {
    guard prewarmedDay != dayID else { return }
    prewarmedDay = dayID
    if let store, (try? await store.latestCompletedBrief(dayID: dayID, scopeID: scopeID)) != nil {
      return
    }
    let generator = generator
    // Model work never runs on the main actor, and a view cancelling must not stop the warm-up.
    Task.detached { await generator.prewarm() }
  }

  private static func sameDay(_ lhs: BriefCacheContext, _ rhs: BriefCacheContext) -> Bool {
    lhs.dayID == rhs.dayID && lhs.scopeID == rhs.scopeID
  }

  /// Settings must never describe an older morning or a different credential scope as today's brief.
  func currentBrief(day: MorningDay, scopeID: String, now: Date) -> Brief? {
    guard day == MorningDay(containing: now), let context = publishedContext,
      context.dayID == day.id, context.scopeID == scopeID
    else { return nil }
    return visibleBrief(for: context)
  }

  func update(context: BriefCacheContext?, input: BriefInput?, settled: Bool) async {
    guard !Task.isCancelled else { return }
    if requestedContext != context || !settled {
      retry?.cancel()
      retry = nil
      requestGeneration = UUID()
    }
    requestedContext = context
    requestedInput = input
    requestedSettled = settled
    if let published = publishedContext, context.map({ Self.sameDay($0, published) }) != true {
      brief = nil
      publishedContext = nil
      storedLookup = nil
    }
    guard let context else { return }
    let requestGeneration = requestGeneration
    if publishedContext == nil, let store {
      await showStoredBrief(for: context, from: store)
    }
    guard settled, let input, !Task.isCancelled else { return }
    let fallback = TemplateBriefGenerator.make(input)
    let result: Outcome
    if let store {
      do {
        var startedAt = now()
        // The store's latest actual attempt decides every request, including a return to an
        // older fingerprint. Neither completed memory nor an old waiter may bypass that gate.
        var reservation = try await store.reserveBrief(
          context: context, input: input, at: startedAt)
        if case .deferred(_, _, let currentReservation) = reservation,
          let currentReservation, jobs[context]?.reservation != currentReservation
        {
          // The task may have completed and been cleaned up while this pending snapshot
          // crossed actors. Re-read once; an orphaned pending reservation stays deferred.
          startedAt = now()
          reservation = try await store.reserveBrief(context: context, input: input, at: startedAt)
        }
        switch reservation {
        case .completed(let cached): result = Outcome(brief: cached)
        case .pending: result = Outcome(brief: fallback)
        case .deferred(let deadline, let previous, let currentReservation):
          if let currentReservation, let existing = jobs[context],
            existing.reservation == currentReservation
          {
            guard let outcome = await BriefGenerationDeadline.wait(for: existing.task) else {
              return
            }
            result = outcome
          } else {
            result = Outcome(brief: previous ?? fallback, retryAt: deadline)
          }
        case .acquired(let reservation):
          let job = startJob(
            context: context, input: input, store: store, reservation: reservation, at: startedAt)
          guard let outcome = await BriefGenerationDeadline.wait(for: job.task) else { return }
          result = outcome
        }
      } catch { result = Outcome(brief: fallback, retryAt: now().addingTimeInterval(30 * 60)) }
    } else {
      result = Outcome(brief: fallback)
    }
    guard !Task.isCancelled, self.requestGeneration == requestGeneration,
      requestedContext == context, requestedSettled
    else { return }
    if result.superseded {
      // A later durable reservation rejected this result. Re-read the current attempt rather
      // than publishing a stale generation after a full A -> B -> A cycle.
      await update(context: context, input: requestedInput, settled: requestedSettled)
      return
    }
    publishedContext = context
    brief = result.brief
    if let deadline = result.retryAt { scheduleRetry(at: deadline, context: context) }
  }

  /// Cold launch: show the day's last completed brief while sync and generation are pending.
  private func showStoredBrief(for context: BriefCacheContext, from store: any BriefCaching) async {
    let lookup = "\(context.dayID)|\(context.scopeID)"
    guard storedLookup != lookup else { return }
    storedLookup = lookup
    guard
      let stored = try? await store.latestCompletedBrief(
        dayID: context.dayID, scopeID: context.scopeID),
      publishedContext == nil, let requestedContext, Self.sameDay(requestedContext, context)
    else { return }
    publishedContext = stored.context
    brief = stored.brief
  }

  private func startJob(
    context: BriefCacheContext, input: BriefInput, store: any BriefCaching,
    reservation: UUID, at startedAt: Date
  ) -> Job {
    let generator = generator
    let timeout = generationTimeout
    let now = now
    let task = Task.detached {
      let valid = await BriefGenerationDeadline.generate(input, using: generator, timeout: timeout)
      do {
        try await store.finishBrief(valid, context: context, reservation: reservation, at: now())
        return Outcome(brief: valid)
      } catch BriefError.invalidReservation {
        return Outcome(brief: valid, superseded: true)
      } catch {
        // The committed pending reservation survives a failed result write.
        return Outcome(brief: valid, retryAt: startedAt.addingTimeInterval(30 * 60))
      }
    }
    let job = Job(reservation: reservation, task: task)
    jobs[context] = job
    Task { [weak self] in
      _ = await task.value
      // Cleanup runs even if every view waiter was cancelled, and an older completion must
      // never remove a newer job for the same fingerprint.
      if self?.jobs[context]?.reservation == reservation { self?.jobs[context] = nil }
    }
    return job
  }

  private func scheduleRetry(at deadline: Date, context: BriefCacheContext) {
    retry?.cancel()
    let sleepUntil = sleepUntil
    retry = Task { [weak self] in
      do { try await sleepUntil(deadline) } catch { return }
      guard !Task.isCancelled, let self, self.requestedContext == context,
        self.requestedSettled, let input = self.requestedInput
      else { return }
      self.retry = nil
      await self.update(context: context, input: input, settled: true)
    }
  }
}
