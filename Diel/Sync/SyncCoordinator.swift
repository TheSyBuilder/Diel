import Foundation
import Observation

nonisolated struct SyncPlan: Sendable {
  static let activityPageSize = 10
  let start: DateKey
  let end: DateKey
  /// Today's per-day routes, then the range chunks that contain today, then everything else.
  let endpoints: [GarminEndpoint]
  /// The leading endpoints that make today's scores publishable before the catch-up.
  let todayCount: Int
  /// The past days the one-request Body Battery backfill (today-29...today) refetches.
  let bodyBatteryBackfillDays: ClosedRange<DateKey>
  /// An incremental sync requires only pending retries touching its own start...end; nil, in
  /// initial and fuller syncs, requires them all.
  let retryWindow: ClosedRange<DateKey>?

  init(
    now: Date, initial: Bool, lastSuccessfulSync: Date? = nil, fuller: Bool = false,
    calendar sourceCalendar: Calendar = .current
  ) throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = sourceCalendar.timeZone
    let today = calendar.startOfDay(for: now)
    guard let recent = calendar.date(byAdding: .day, value: -3, to: today),
      let catchup = calendar.date(byAdding: .day, value: -89, to: today),
      let backfill = calendar.date(byAdding: .day, value: -29, to: today),
      let yesterday = calendar.date(byAdding: .day, value: -1, to: today)
    else { throw GarminError.invalidEndpoint }
    let first =
      initial || fuller
      ? min(catchup, lastSuccessfulSync.map { calendar.startOfDay(for: $0) } ?? catchup)
      : min(recent, lastSuccessfulSync.map { calendar.startOfDay(for: $0) } ?? recent)
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.timeZone = calendar.timeZone
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    func key(_ date: Date) throws -> DateKey { try DateKey(formatter.string(from: date)) }
    start = try key(first)
    end = try key(today)
    bodyBatteryBackfillDays = try key(backfill)...key(yesterday)
    retryWindow = initial || fuller ? nil : start...end
    var routes: [GarminEndpoint] = []
    var leading: [GarminEndpoint] = [.sleep(end), .hrv(end), .heartRate(end)]
    func ranges(_ maximum: Int, route: (DateKey, DateKey) -> GarminEndpoint) throws
      -> GarminEndpoint?
    {
      var lower = first
      var latest: GarminEndpoint?
      while lower <= today {
        guard let candidate = calendar.date(byAdding: .day, value: maximum - 1, to: lower)
        else { throw GarminError.invalidEndpoint }
        let upper = min(today, candidate)
        let endpoint = route(try key(lower), try key(upper))
        routes.append(endpoint)
        latest = endpoint
        guard let next = calendar.date(byAdding: .day, value: 1, to: upper) else {
          throw GarminError.invalidEndpoint
        }
        lower = next
      }
      return latest
    }
    if let chunk = try ranges(31, route: { .sleepSummaries(start: $0, end: $1) }) {
      leading.append(chunk)
    }
    routes.append(.hrvSummaries(start: start, end: end))
    leading.append(.hrvSummaries(start: start, end: end))
    if let chunk = try ranges(31, route: { .bodyBattery(start: $0, end: $1) }) {
      leading.append(chunk)
    }
    _ = try ranges(28) { .stress(start: $0, end: $1) }
    if let chunk = try ranges(365, route: { .dailySummaries(start: $0, end: $1) }) {
      leading.append(chunk)
    }
    var date = first
    while date <= today {
      routes.append(.sleep(try key(date)))
      routes.append(.hrv(try key(date)))
      routes.append(.heartRate(try key(date)))
      guard let next = calendar.date(byAdding: .day, value: 1, to: date) else {
        throw GarminError.invalidEndpoint
      }
      date = next
    }
    endpoints = leading + routes.filter { !leading.contains($0) }
    todayCount = leading.count
  }

  private init(
    start: DateKey, end: DateKey, endpoints: [GarminEndpoint], todayCount: Int,
    bodyBatteryBackfillDays: ClosedRange<DateKey>, retryWindow: ClosedRange<DateKey>?
  ) {
    self.start = start
    self.end = end
    self.endpoints = endpoints
    self.todayCount = todayCount
    self.bodyBatteryBackfillDays = bodyBatteryBackfillDays
    self.retryWindow = retryWindow
  }

  /// Removes routes from the plan; they are then neither fetched nor required for completion.
  func excluding(_ dropped: [GarminEndpoint]) -> Self {
    guard !dropped.isEmpty else { return self }
    let today = endpoints.prefix(todayCount).filter { !dropped.contains($0) }
    let rest = endpoints.dropFirst(todayCount).filter { !dropped.contains($0) }
    return Self(
      start: start, end: end, endpoints: today + rest, todayCount: today.count,
      bodyBatteryBackfillDays: bodyBatteryBackfillDays, retryWindow: retryWindow)
  }

  /// Whether this sync requires a pending retry. Older ones are left to initial and fuller
  /// syncs, or fetched best effort by a manual or overdue incremental one; undated routes are
  /// always required.
  func retries(_ endpoint: GarminEndpoint) -> Bool {
    guard let retryWindow, let dates = endpoint.dates else { return true }
    return dates.overlaps(retryWindow)
  }

  /// A separate today-29...today Body Battery request, fetched after the catch-up and never
  /// required for completion. Nil when the plan's own requests already start that early.
  var bodyBatteryBackfill: GarminEndpoint? {
    let lower = bodyBatteryBackfillDays.lowerBound
    return start > lower ? .bodyBattery(start: lower, end: end) : nil
  }

  /// Past per-day routes whose stored copy was accepted after the day ended. Heart rate keeps
  /// receiving late uploads, so yesterday's is always refetched and an older day's only counts
  /// once a copy was accepted two days after it began.
  @concurrent
  static func finalizedPastDays(
    in plan: Self, days: [GarminDaySnapshot], calendar sourceCalendar: Calendar
  ) async -> [GarminEndpoint] {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = sourceCalendar.timeZone
    func start(of key: DateKey) -> Date? {
      let parts = key.rawValue.split(separator: "-").compactMap { Int($0) }
      guard parts.count == 3,
        let date = calendar.date(
          from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
      else { return nil }
      return calendar.startOfDay(for: date)
    }
    guard let today = start(of: plan.end) else { return [] }
    var finalized: [GarminEndpoint] = []
    for day in days where day.date < plan.end && day.date >= plan.start {
      guard let date = start(of: day.date),
        let nextDay = calendar.date(byAdding: .day, value: 1, to: date),
        let secondDay = calendar.date(byAdding: .day, value: 2, to: date)
      else { continue }
      func fetched(_ family: GarminPayload.Family, since date: Date) -> Bool {
        day.values.contains { $0.family == family && $0.fetchedAt >= date }
      }
      if fetched(.sleep, since: nextDay) { finalized.append(.sleep(day.date)) }
      if fetched(.hrv, since: nextDay) { finalized.append(.hrv(day.date)) }
      if nextDay < today, fetched(.heartRate, since: secondDay) {
        finalized.append(.heartRate(day.date))
      }
    }
    return finalized
  }

  @concurrent
  static func make(
    now: Date, initial: Bool, lastSuccessfulSync: Date? = nil, fuller: Bool = false,
    calendar: Calendar = .current
  ) async throws -> Self {
    try Self(
      now: now, initial: initial, lastSuccessfulSync: lastSuccessfulSync,
      fuller: fuller, calendar: calendar)
  }

  func activities(offset: Int) -> GarminEndpoint {
    .activities(start: start, end: end, offset: offset, limit: Self.activityPageSize)
  }
}

#if DEBUG
  /// Wall-clock summary of the last finished sync, shown only in debug Settings.
  nonisolated struct SyncTiming: Sendable, Equatable {
    let totalSeconds: Double
    let todaySeconds: Double?
    let requestCount: Int
    let medianSeconds: Double
    let slowestFamily: GarminPayload.Family?
    let slowestSeconds: Double

    init(
      total: Duration, today: Duration?,
      requests: [(family: GarminPayload.Family, duration: Duration)]
    ) {
      func seconds(_ value: Duration) -> Double {
        Double(value.components.seconds) + Double(value.components.attoseconds) / 1e18
      }
      totalSeconds = seconds(total)
      todaySeconds = today.map(seconds)
      requestCount = requests.count
      let sorted = requests.map { seconds($0.duration) }.sorted()
      if sorted.isEmpty {
        medianSeconds = 0
      } else if sorted.count.isMultiple(of: 2) {
        medianSeconds = (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
      } else {
        medianSeconds = sorted[sorted.count / 2]
      }
      let slowest = requests.max { $0.duration < $1.duration }
      slowestFamily = slowest?.family
      slowestSeconds = slowest.map { seconds($0.duration) } ?? 0
    }

    /// For example "14 requests · 11.2s · today 4.1s · slowest heartRate 2.3s".
    var summary: String {
      func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
      }
      var parts = [
        "\(requestCount) \(requestCount == 1 ? "request" : "requests")",
        "\(format(totalSeconds))s",
      ]
      if let todaySeconds { parts.append("today \(format(todaySeconds))s") }
      if let slowestFamily {
        parts.append("slowest \(slowestFamily.rawValue) \(format(slowestSeconds))s")
      }
      return parts.joined(separator: " · ")
    }
  }
#endif

/// Typed transition boundary also supports fixture-derived metadata regression tests.
nonisolated enum ActivityDetailRefreshDecision {
  case fetch, skip, deferCompletion

  static func resolve<Summary: Equatable>(
    previous: Summary?, current: Summary, needsRefresh: Bool, alreadyAttempted: Bool
  ) -> Self {
    let changed = previous != current
    if alreadyAttempted { return changed ? .deferCompletion : .skip }
    return needsRefresh || changed ? .fetch : .skip
  }
}

@Observable
@MainActor
final class SyncCoordinator {
  enum State: Equatable { case idle, running, completed, failed }
  /// Within a running sync: today's routes first, then the older catch-up.
  enum Phase: Equatable { case idle, today, catchingUp }
  private(set) var state = State.idle
  private(set) var phase = Phase.idle
  private(set) var hasSavedKey = false
  private(set) var lastSuccessfulSync: Date?
  private(set) var errorMessage: LocalizedStringResource?
  private var failureMetadata: SyncFailure?
  var isKeyRejected: Bool { failureMetadata?.isKeyRejected == true }
  #if DEBUG
    var lastFailure: SyncFailure? { failureMetadata }
    private(set) var skippedDayDiagnostics: [GarminMissingDayDiagnostic] = []
    private(set) var lastSyncTiming: SyncTiming?
    @ObservationIgnored private var requestDurations:
      [(family: GarminPayload.Family, duration: Duration)] = []
  #endif
  let store: GarminStore
  let scoring: ScoringService
  private let credentials: any CredentialStore
  private let client: any GarminFetching
  private let authenticator: any GarminTokenProviding
  private let now: @Sendable () -> Date
  private let calendar: Calendar
  private let log: any DielEventLogging
  private let detailRefreshDecision:
    @Sendable (GarminActivitySnapshot?, ActivityDTO, GarminEndpoint, Bool) ->
      ActivityDetailRefreshDecision
  private var work: Task<Void, Never>?
  private var workID: UUID?
  private var workIsFuller = false
  private struct TodayWaiter {
    let id: UUID
    let work: UUID
    let continuation: CheckedContinuation<Bool, Never>
  }
  @ObservationIgnored private var todayWaiters: [TodayWaiter] = []
  @ObservationIgnored private var todayPublished: (work: UUID, succeeded: Bool)?
  private var lastSyncAttempt: Date?
  private let beforeBootstrap: @Sendable () async -> Void
  private var credentialDiscoveryFailed = false
  var hasCachedScope: Bool { scoring.revision != nil }
  var canSync: Bool { hasSavedKey || hasCachedScope || credentialDiscoveryFailed }
  private var generation = UUID()
  private var launched = false
  private var selectedRevision: CredentialRevision?
  private var bootstrapping: Task<Void, Never>?
  private var launching: Task<Void, Never>?
  private var launchID: UUID?
  private var activeTimer: Task<Void, Never>?
  private var foregroundActive = false
  private var foregroundPlan: Date?
  private var backgroundPlan: Date?
  var nextPlannedCheck: Date? {
    foregroundActive ? foregroundPlan ?? backgroundPlan : backgroundPlan
  }
  var hasActiveTimer: Bool { activeTimer != nil }
  private let sleep: @Sendable (TimeInterval) async throws -> Void

  init(
    credentials: any CredentialStore, client: any GarminFetching, store: GarminStore,
    authenticator: any GarminTokenProviding, now: @escaping @Sendable () -> Date = { Date() },
    calendar: Calendar = .current, log: any DielEventLogging = DielLog(),
    sleep: @escaping @Sendable (TimeInterval) async throws -> Void = {
      try await Task.sleep(for: .seconds($0))
    },
    beforeBootstrap: @escaping @Sendable () async -> Void = {},
    detailRefreshDecision:
      @escaping @Sendable (
        GarminActivitySnapshot?, ActivityDTO, GarminEndpoint, Bool
      ) -> ActivityDetailRefreshDecision = { prior, summary, _, attempted in
        ActivityDetailRefreshDecision.resolve(
          previous: prior?.summary, current: summary,
          needsRefresh: prior?.needsDetailRefresh ?? true, alreadyAttempted: attempted)
      }
  ) {
    self.credentials = credentials
    self.client = client
    self.store = store
    scoring = ScoringService(store: store)
    self.authenticator = authenticator
    self.now = now
    self.calendar = calendar
    self.log = log
    self.sleep = sleep
    self.beforeBootstrap = beforeBootstrap
    self.detailRefreshDecision = detailRefreshDecision
  }

  /// Disk publication finishes before any launch, foreground or background request.
  func bootstrap() async {
    if let bootstrapping {
      await bootstrapping.value
      return
    }
    guard !launched else { return }
    let id = generation
    let task = Task {
      do {
        await beforeBootstrap()
        try check(id)
        // The selected disk scope is non-secret. Publish it even before first unlock permits
        // reading the credential, then reconcile the real credential before networking.
        if let revision = try await store.activeRevision() {
          try check(id)
          selectedRevision = revision
          lastSuccessfulSync = try await store.status(revision: revision).lastCompleteSyncAt
          let window = try await SyncPlan.make(now: now(), initial: true, calendar: calendar)
          await scoring.bootstrap(
            in: window.start...window.end, revision: revision, now: now(), calendar: calendar)
        }
      } catch {
        guard generation == id else { return }
        recordFailure(error, step: .store, stage: .setup, generation: id)
        fail()
      }
      if generation == id { launched = true }
    }
    bootstrapping = task
    await task.value
    bootstrapping = nil
  }

  /// Overlapping launches share bootstrap and credential discovery, even when no key is saved.
  func launch() async {
    if let launching {
      await launching.value
      return
    }
    let generationID = generation
    let id = UUID()
    let task = Task {
      await bootstrap()
      guard generation == generationID, !Task.isCancelled else { return }
      // Launch returns once today's scores publish; the catch-up keeps running.
      await syncToday(manual: false)
    }
    launching = task
    launchID = id
    await task.value
    if launchID == id {
      launching = nil
      launchID = nil
    }
  }

  /// Automatic by default; `manual` marks a sync the user started.
  func sync(fuller: Bool = false, manual: Bool = false) async {
    await bootstrap()
    guard !Task.isCancelled else { return }
    requestSync(fuller: fuller, manual: manual)
    await work?.value
  }

  /// Starts or joins the shared sync and returns once today's scores are published or the work
  /// ends. Cancelling the caller only stops waiting; the shared work continues.
  /// - Returns: true only when every today endpoint succeeded or had no data and today's scores
  ///   published without a calculation failure; false on failure, cancellation or key rejection.
  /// Callers outside the coordinator are the user's refresh, so `manual` defaults to true.
  @discardableResult
  func syncToday(fuller: Bool = false, manual: Bool = true) async -> Bool {
    await bootstrap()
    guard !Task.isCancelled else { return false }
    requestSync(fuller: fuller, manual: manual)
    guard work != nil, let current = workID else { return false }
    if let todayPublished, todayPublished.work == current { return todayPublished.succeeded }
    let waiter = UUID()
    return await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        if Task.isCancelled {
          continuation.resume(returning: false)
        } else {
          todayWaiters.append(TodayWaiter(id: waiter, work: current, continuation: continuation))
        }
      }
    } onCancel: {
      Task { @MainActor in self.releaseTodayWaiters(returning: false) { $0.id == waiter } }
    }
  }

  private func releaseTodayWaiters(returning result: Bool, where matches: (TodayWaiter) -> Bool) {
    let ready = todayWaiters.filter(matches)
    todayWaiters.removeAll(where: matches)
    for waiter in ready { waiter.continuation.resume(returning: result) }
  }

  func waitForCurrentSync() async { await work?.value }

  /// A manual sync, the default for callers outside the coordinator, also fetches older pending
  /// retries best effort. A request that joins running work keeps that work's choice.
  func requestSync(fuller: Bool = false, manual: Bool = true) {
    guard work == nil else { return }
    lastSyncAttempt = now()
    clearFailure()
    let id = generation
    let current = UUID()
    workID = current
    workIsFuller = fuller
    work = Task {
      defer { releaseTodayWaiters(returning: false) { $0.work == current } }
      await bootstrap()
      guard generation == id, !Task.isCancelled else { return }
      await discoverAndSync(generation: id, fuller: fuller, manual: manual, work: current)
      if generation == id {
        work = nil
        workID = nil
      }
    }
  }

  func setForegroundActive(_ active: Bool) async {
    guard foregroundActive != active else { return }
    foregroundActive = active
    activeTimer?.cancel()
    activeTimer = nil
    foregroundPlan = nil
    guard active else { return }
    await bootstrap()
    if canSync, !isKeyRejected,
      lastSyncAttempt.map({ now().timeIntervalSince($0) > 5 * 60 }) ?? true,
      lastSuccessfulSync.map({ now().timeIntervalSince($0) > 5 * 60 }) ?? true
    {
      requestSync(manual: false)
    }
    scheduleForegroundCheck()
  }

  private func scheduleForegroundCheck() {
    activeTimer?.cancel()
    activeTimer = nil
    foregroundPlan = nil
    guard foregroundActive, hasSavedKey, !isKeyRejected else { return }
    let planned = now().addingTimeInterval(15 * 60)
    foregroundPlan = planned
    activeTimer = Task {
      do { try await sleep(max(0, planned.timeIntervalSince(now()))) } catch { return }
      guard !Task.isCancelled, foregroundActive else { return }
      activeTimer = nil
      foregroundPlan = nil
      await sync()
      guard !Task.isCancelled else { return }
      scheduleForegroundCheck()
    }
  }

  func setAcceptedBackgroundCheck(_ date: Date?) { backgroundPlan = date }

  func cancelSync() async {
    let pendingLaunch = launching
    launching = nil
    launchID = nil
    pendingLaunch?.cancel()
    let pending = work
    generation = UUID()
    work = nil
    workID = nil
    pending?.cancel()
    await pending?.value
    await pendingLaunch?.value
    // A sync requested during the awaits owns state and phase now.
    if work == nil {
      state = .idle
      phase = .idle
    }
  }

  final class BackgroundWork {
    var id: UUID?
    let owned: Bool
    var task: Task<Void, Never>!
    init(id: UUID?, owned: Bool, task: Task<Void, Never>? = nil) {
      self.id = id
      self.owned = owned
      self.task = task
    }
  }

  func backgroundWork(fuller: Bool) -> BackgroundWork {
    if fuller, let current = work, !workIsFuller {
      let lease = BackgroundWork(id: nil, owned: true)
      lease.task = Task {
        await current.value
        while let competing = work {
          guard !Task.isCancelled else { return }
          let joinsFuller = workIsFuller
          await competing.value
          if joinsFuller { return }
        }
        guard !Task.isCancelled else { return }
        requestSync(fuller: true, manual: false)
        lease.id = workID
        await work?.value
      }
      return lease
    }
    let owned = work == nil
    requestSync(fuller: fuller, manual: false)
    return BackgroundWork(id: workID, owned: owned, task: work!)
  }

  func cancelBackgroundWork(_ lease: BackgroundWork) async {
    guard lease.owned else { return }
    lease.task.cancel()
    if let id = lease.id, workID == id { await cancelSync() }
  }

  /// Finish old work before changing credentials or the selected persistence scope.
  func prepareForCredentialChange() async {
    generation = UUID()
    let pendingLaunch = launching
    launching = nil
    launchID = nil
    pendingLaunch?.cancel()
    let pending = work
    work = nil
    pending?.cancel()
    await authenticator.invalidate()
    await pending?.value
    await pendingLaunch?.value
    if work == nil {
      state = .idle
      phase = .idle
    }
    clearFailure()
  }

  func selectCredential(_ revision: CredentialRevision?) async throws {
    if selectedRevision != revision { scoring.invalidate() }
    try await store.setActiveRevision(revision)
    clearFailure()
    selectedRevision = revision
    hasSavedKey = revision != nil
    if let revision {
      lastSuccessfulSync = try await store.status(revision: revision).lastCompleteSyncAt
    } else {
      lastSuccessfulSync = nil
    }
    log.record(.credentialChanged)
    if let revision { await calculateScores(revision: revision, bootstrap: true) }
    scheduleForegroundCheck()
  }

  private func check(_ id: UUID) throws {
    try Task.checkCancellation()
    guard generation == id else { throw CancellationError() }
  }

  private func discoverAndSync(generation id: UUID, fuller: Bool, manual: Bool, work: UUID) async {
    var step = SyncFailure.Step.credentials
    do {
      let credential = try await credentials.read()
      credentialDiscoveryFailed = false
      step = .store
      try check(id)
      guard let credential else {
        let active = try await store.activeRevision()
        try check(id)
        if selectedRevision != nil || active != nil {
          try await selectCredential(nil)
        }
        hasSavedKey = false
        return
      }
      if selectedRevision != credential.revision { try await selectCredential(credential.revision) }
      hasSavedKey = true
      scheduleForegroundCheck()
      try check(id)
      let status = try await store.status(revision: credential.revision)
      try check(id)
      let initial = status.lastCompleteSyncAt == nil
      var plan = try await SyncPlan.make(
        now: now(), initial: initial,
        lastSuccessfulSync: status.lastCompleteSyncAt, fuller: fuller, calendar: calendar)
      var backfill: GarminEndpoint?
      var olderRetries = false
      if !initial, !fuller {
        // Without a recent fuller sync, for example when the overnight task never runs, an
        // incremental sync also tries older pending retries.
        let lastFuller = try await store.lastFullerSync(revision: credential.revision)
        olderRetries =
          manual || lastFuller.map { now().timeIntervalSince($0) > 48 * 60 * 60 } ?? true
        try check(id)
        let days = try await store.days(in: plan.start...plan.end, revision: credential.revision)
        try check(id)
        plan = plan.excluding(
          await SyncPlan.finalizedPastDays(in: plan, days: days, calendar: calendar))
        // Days stored before Body Battery requests carried `chunks` hold only their extremes.
        if try await store.bodyBatteryNeedsChunkedRefetch(
          in: plan.bodyBatteryBackfillDays, revision: credential.revision)
        {
          backfill = plan.bodyBatteryBackfill
        }
        try check(id)
      }
      let completed = await pull(
        plan, backfill: backfill, revision: credential.revision, generation: id, work: work)
      try check(id)
      await calculateScores(revision: credential.revision)
      if completed, olderRetries {
        try await fetchOlderRetries(plan, revision: credential.revision, generation: id)
      }
    } catch is CancellationError {
    } catch {
      guard (try? rejectStale(error, generation: id)) != nil else { return }
      recordFailure(error, step: step, stage: .setup, generation: id)
      credentialDiscoveryFailed = step == .credentials
      fail()
    }
  }

  /// Returns true only when the sync completed.
  private func pull(
    _ plan: SyncPlan, backfill: GarminEndpoint? = nil, revision: CredentialRevision,
    generation id: UUID, work: UUID
  ) async -> Bool {
    var session: GarminSyncSession?
    var stage = SyncFailure.Stage.setup
    #if DEBUG
      let started = ContinuousClock.now
      var todayElapsed: Duration?
      requestDurations = []
      defer {
        if generation == id, !Task.isCancelled, state != .running {
          lastSyncTiming = SyncTiming(
            total: ContinuousClock.now - started, today: todayElapsed,
            requests: requestDurations)
        }
      }
    #endif
    defer { if generation == id { phase = .idle } }
    do {
      try check(id)
      state = .running
      errorMessage = nil
      log.record(.syncStarted)
      let retries = try await pendingRetries(plan, revision: revision).filter(plan.retries)
      try check(id)
      let current = try await store.beginSync(
        revision: revision,
        requiredEndpoints: plan.endpoints + retries + [plan.activities(offset: 0)],
        at: now())
      session = current
      var failed = false
      phase = .today
      for endpoint in plan.endpoints.prefix(plan.todayCount) {
        let fetched = try await fetchRecordingFailure(endpoint, session: current, generation: id)
        if !fetched { failed = true }
      }
      try check(id)
      phase = .catchingUp
      await calculateScores(revision: revision)
      try check(id)
      #if DEBUG
        todayElapsed = ContinuousClock.now - started
      #endif
      let todaySucceeded = !failed && !scoring.calculationFailed
      todayPublished = (work, todaySucceeded)
      releaseTodayWaiters(returning: todaySucceeded) { $0.work == work }
      for endpoint in plan.endpoints.dropFirst(plan.todayCount) + retries {
        let fetched = try await fetchRecordingFailure(endpoint, session: current, generation: id)
        if !fetched { failed = true }
      }
      do { try await activities(plan, session: current, generation: id) } catch is CancellationError
      { throw CancellationError() } catch {
        if error as? GarminStoreError != .incompleteSync,
          !(isKeyRejected && error as? SyncFailure == failureMetadata)
        {
          recordFailure(error, step: .endpoint(.activities), stage: .ingest, generation: id)
        }
        if isKeyRejected { throw error }
        failed = true
      }
      if let backfill {
        try await fetchBackfill(backfill, session: current, revision: revision, generation: id)
      }
      try check(id)
      stage = .completion
      if failed { throw GarminStoreError.incompleteSync }
      try await store.completeSync(current, at: now())
      try check(id)
      if plan.retryWindow == nil {
        // Advisory: a lost marker only lets a later incremental sync try older retries again.
        try? await store.recordFullerSync(revision: revision, at: now())
        try check(id)
      }
      lastSuccessfulSync = try await store.status(revision: revision).lastCompleteSyncAt
      if failureMetadata?.reason != .skippedRecord { clearFailure() }
      state = .completed
      scheduleForegroundCheck()
      log.record(.syncCompleted)
      return true
    } catch {
      if let session { await store.cancelSync(session) }
      guard !(error is CancellationError), (try? rejectStale(error, generation: id)) != nil else {
        return false
      }
      if failureMetadata == nil || failureMetadata?.reason == .skippedRecord {
        recordFailure(error, step: stage == .setup ? .store : .sync, stage: stage, generation: id)
      }
      fail()
      return false
    }
  }

  /// Pending retries this plan does not fetch as its own routes.
  private func pendingRetries(_ plan: SyncPlan, revision: CredentialRevision) async throws
    -> [GarminEndpoint]
  {
    try await store.retryEndpoints(revision: revision).filter {
      !plan.endpoints.contains($0) && $0.family != .activity && $0 != plan.activities(offset: 0)
    }
  }

  /// Best effort: an answer, with data or without, ends the backfill for this revision. A failure
  /// leaves the sync's outcome unchanged and the backfill is tried again on a later sync.
  private func fetchBackfill(
    _ endpoint: GarminEndpoint, session: GarminSyncSession, revision: CredentialRevision,
    generation id: UUID
  ) async throws {
    do {
      _ = try await fetch(endpoint, session: session, generation: id, retriesRejections: false)
      try await store.recordBodyBatteryBackfill(revision: revision, at: now())
    } catch is CancellationError { throw CancellationError() } catch {
      try check(id)
    }
  }

  /// Older pending retries one sync fetches, oldest first, so a backlog drains over several.
  static let olderRetryLimit = 12

  /// Best effort, after the sync completed, so running out of time here never discards it. Each
  /// answer is ingested outside the finished session; a failure leaves its route pending, and
  /// only a rejected key stops the rest and is reported.
  private func fetchOlderRetries(
    _ plan: SyncPlan, revision: CredentialRevision, generation id: UUID
  ) async throws {
    guard let pending = try? await pendingRetries(plan, revision: revision) else { return }
    let older = pending.compactMap { endpoint in
      plan.retries(endpoint) ? nil : endpoint.dates.map { (endpoint, $0.lowerBound) }
    }
    .sorted { $0.1 < $1.1 }.prefix(Self.olderRetryLimit).map(\.0)
    try check(id)
    var imported = false
    for endpoint in older {
      do {
        let response = try await request(endpoint, generation: id)
        do {
          if let response {
            guard response.revision == revision else { throw GarminError.credentialChanged }
            let report = try await store.ingestReport(response)
            try check(id)
            recordSkips(report, response: response, generation: id)
            imported = true
          } else {
            try await store.recordNoData(endpoint: endpoint, revision: revision)
          }
        } catch {
          try rejectStale(error, generation: id)
          continue
        }
      } catch is CancellationError { throw CancellationError() } catch {
        try check(id)
        guard (error as? SyncFailure)?.isKeyRejected == true else { continue }
        recordFailure(error, step: .endpoint(endpoint.family), stage: .request, generation: id)
        fail()
        return
      }
    }
    try check(id)
    if imported { await calculateScores(revision: revision) }
  }

  /// Returns false when the endpoint failed in a way that leaves the sync incomplete.
  private func fetchRecordingFailure(
    _ endpoint: GarminEndpoint, session: GarminSyncSession, generation id: UUID
  ) async throws -> Bool {
    do {
      _ = try await fetch(endpoint, session: session, generation: id)
      return true
    } catch is CancellationError { throw CancellationError() } catch {
      recordFailure(error, step: .endpoint(endpoint.family), stage: .request, generation: id)
      if isKeyRejected { throw error }
      return false
    }
  }

  private func calculateScores(revision: CredentialRevision, bootstrap: Bool = false) async {
    guard selectedRevision == revision, !Task.isCancelled else { return }
    do {
      let instant = now()
      let window = try await SyncPlan.make(now: instant, initial: true, calendar: calendar)
      if bootstrap {
        await scoring.bootstrap(
          in: window.start...window.end, revision: revision, now: instant, calendar: calendar)
      } else {
        await scoring.refresh(
          in: window.start...window.end, revision: revision, now: instant, calendar: calendar)
      }
    } catch {}

  }

  private func clearFailure() {
    #if DEBUG
      skippedDayDiagnostics = []
    #endif
    failureMetadata = nil
    errorMessage = nil
  }

  private func recordFailure(
    _ error: any Error, step: SyncFailure.Step, stage: SyncFailure.Stage, generation id: UUID
  ) {
    guard generation == id, !Task.isCancelled,
      let failure = try? SyncFailure.context(error, step: step, stage: stage)
    else { return }
    log.record(.failure(failure))
    // Keep the first causal failure through later incomplete-sync aggregation.
    if failureMetadata == nil || failureMetadata?.reason == .skippedRecord || failure.isKeyRejected
    {
      failureMetadata = failure
    }
  }

  private func recordSkips(
    _ report: GarminImportReport, response: GarminResponse, generation id: UUID
  ) {
    #if DEBUG
      if generation == id, !Task.isCancelled {
        skippedDayDiagnostics.append(contentsOf: report.rejections.compactMap(\.missingDay))
      }
    #endif
    for rejection in report.rejections {
      if let fieldPath = rejection.fieldPath {
        log.record(.rejectedRecord(date: rejection.date, fieldPath: fieldPath))
        #if DEBUG
          if let missingDay = rejection.missingDay {
            log.record(
              .rejectedRecordFields(
                memberIndex: missingDay.memberIndex, fields: missingDay.presentFields))
          }
        #endif
      }
    }
    guard let rejection = report.rejections.first else { return }
    let warning = SyncFailure(
      step: .endpoint(response.endpoint.family), stage: rejection.stage,
      httpStatus: response.httpStatus, reason: .skippedRecord)
    recordFailure(warning, step: warning.step, stage: warning.stage, generation: id)
  }

  private func fail() {
    state = .failed
    errorMessage = "Sync couldn't finish. Your saved data is still here."
    if isKeyRejected {
      activeTimer?.cancel()
      activeTimer = nil
      foregroundPlan = nil
    }
    log.record(.syncFailed)
  }

  @discardableResult
  private func fetch(
    _ endpoint: GarminEndpoint, session: GarminSyncSession, generation id: UUID,
    retriesRejections: Bool = true
  ) async throws -> GarminResponse? {
    try check(id)
    let response = try await request(endpoint, generation: id)
    do {
      if let response {
        guard response.revision == session.revision else { throw GarminError.credentialChanged }
        let report = try await store.ingestReport(
          response, session: session, retriesRejections: retriesRejections)
        try check(id)
        recordSkips(report, response: response, generation: id)
      } else {
        try await store.recordNoData(
          endpoint: endpoint, revision: session.revision, session: session)
      }
      try check(id)
      return response
    } catch {
      try rejectStale(error, generation: id)
      throw try SyncFailure.context(
        error, step: .endpoint(endpoint.family), stage: .ingest,
        httpStatus: response?.httpStatus)
    }
  }

  private func request(_ endpoint: GarminEndpoint, generation id: UUID) async throws
    -> GarminResponse?
  {
    try check(id)
    do {
      #if DEBUG
        let started = ContinuousClock.now
        defer { requestDurations.append((endpoint.family, ContinuousClock.now - started)) }
      #endif
      let response = try await client.fetch(endpoint)
      try check(id)
      return response
    } catch {
      try rejectStale(error, generation: id)
      throw try SyncFailure.context(error, step: .endpoint(endpoint.family), stage: .request)
    }
  }

  private func rejectStale(_ error: any Error, generation id: UUID) throws {
    try check(id)
    if error as? GarminError == .credentialChanged || error as? GarminStoreError == .staleRevision {
      throw CancellationError()
    }
  }

  private func activities(_ plan: SyncPlan, session: GarminSyncSession, generation id: UUID)
    async throws
  {
    let planner = ActivitySyncPlanner()
    var failed = false
    do {
      try await activityPages(
        plan, session: session, generation: id, planner: planner)
    } catch is CancellationError { throw CancellationError() } catch {
      if error as? GarminStoreError != .incompleteSync,
        !(isKeyRejected && error as? SyncFailure == failureMetadata)
      {
        recordFailure(error, step: .endpoint(.activities), stage: .ingest, generation: id)
      }
      if isKeyRejected { throw error }
      failed = true
    }

    // Pending work remains required after an activity leaves the latest date window/page.
    let pendingIDs = try await planner.pendingDetails(store: store, revision: session.revision)
    try check(id)
    for activityID in pendingIDs {
      guard await planner.attempt(activityID) else { continue }
      let endpoint = GarminEndpoint.activity(activityID)
      do {
        try await store.require([endpoint], for: session)
      } catch {
        try rejectStale(error, generation: id)
        throw try SyncFailure.context(error, step: .endpoint(endpoint.family), stage: .ingest)
      }
      do { try await fetch(endpoint, session: session, generation: id) } catch is CancellationError
      { throw CancellationError() } catch {
        recordFailure(error, step: .endpoint(endpoint.family), stage: .request, generation: id)
        if isKeyRejected { throw error }
        failed = true
      }
    }
    if failed { throw GarminStoreError.incompleteSync }
  }

  private func activityPages(
    _ plan: SyncPlan, session: GarminSyncSession, generation id: UUID,
    planner: ActivitySyncPlanner
  ) async throws {
    var offset = 0
    var failed = false
    var status: Int?
    do {
      while true {
        status = nil
        try check(id)
        let endpoint = plan.activities(offset: offset)
        if offset > 0 { try await store.require([endpoint], for: session) }
        let response = try await request(endpoint, generation: id)
        status = response?.httpStatus
        try check(id)
        guard let response else {
          try await store.recordNoData(
            endpoint: endpoint, revision: session.revision, session: session)
          break
        }
        guard response.revision == session.revision else { throw CancellationError() }
        // Planning, page hashing and prior-value lookup run on a worker actor.
        let page = try await planner.prepare(response, store: store, revision: session.revision)
        try check(id)
        let report = try await store.ingestReport(response, session: session)
        try check(id)
        recordSkips(report, response: response, generation: id)
        let detailPlan = await planner.details(
          for: page, endpoint: endpoint, decision: detailRefreshDecision)
        let details = detailPlan.endpoints
        if detailPlan.deferred { failed = true }
        try check(id)
        try await store.require(details, for: session)
        for detail in details {
          guard case .activity(let activityID) = detail,
            await planner.attempt(activityID)
          else { continue }
          do {
            try await fetch(detail, session: session, generation: id)
          } catch is CancellationError { throw CancellationError() } catch {
            recordFailure(error, step: .endpoint(detail.family), stage: .request, generation: id)
            if isKeyRejected { throw error }
            failed = true
          }
        }
        let pagination = await planner.pagination(page: page.values, response: response)
        if pagination.memberCount < SyncPlan.activityPageSize { break }
        guard pagination.hasNewIDs || !report.rejections.isEmpty else {
          throw SyncFailure(
            step: .endpoint(.activities), stage: .completion, httpStatus: nil, reason: .incomplete)
        }
        let memberCount = pagination.memberCount
        offset += memberCount
      }
      if failed {
        if failureMetadata != nil { throw GarminStoreError.incompleteSync }
        throw SyncFailure(
          step: .endpoint(.activities), stage: .completion, httpStatus: nil, reason: .incomplete)
      }
    } catch {
      if error as? GarminStoreError == .incompleteSync, failureMetadata != nil { throw error }
      throw try SyncFailure.context(
        error, step: .endpoint(.activities), stage: .ingest, httpStatus: status)
    }
  }
}

/// The observable coordinator only publishes state; collection planning stays off its executor.
private actor ActivitySyncPlanner {
  struct Page: Sendable {
    let values: [ActivityDTO]
    let previous: [Int64: GarminActivitySnapshot]
  }
  struct DetailPlan: Sendable {
    let endpoints: [GarminEndpoint]
    let deferred: Bool
  }
  private var attempted: Set<Int64> = []
  private var seen: Set<Int64> = []
  private var seenPages: Set<Data> = []

  func attempt(_ id: Int64) -> Bool { attempted.insert(id).inserted }

  func pendingDetails(store: GarminStore, revision: CredentialRevision) async throws -> [Int64] {
    let cached = try await store.activities(revision: revision)
    let retry = try await store.retryEndpoints(revision: revision)
    return cached.filter(\.needsDetailRefresh).map(\.activityID)
      + retry.compactMap {
        if case .activity(let id) = $0 { return id }
        return nil
      }
  }

  func prepare(_ response: GarminResponse, store: GarminStore, revision: CredentialRevision)
    async throws -> Page
  {
    guard seenPages.insert(response.rawData).inserted else {
      throw SyncFailure(
        step: .endpoint(.activities), stage: .completion, httpStatus: nil, reason: .incomplete)
    }
    guard case .activities(let values) = response.payload else {
      throw GarminStoreError.invalidResponse
    }
    var previous: [Int64: GarminActivitySnapshot] = [:]
    for summary in values {
      guard let id = summary.activityId, id > 0 else { continue }
      previous[id] = try await store.activity(id, revision: revision)
    }
    return Page(values: values, previous: previous)
  }

  func details(
    for page: Page, endpoint: GarminEndpoint,
    decision:
      @Sendable (GarminActivitySnapshot?, ActivityDTO, GarminEndpoint, Bool) ->
      ActivityDetailRefreshDecision
  ) -> DetailPlan {
    var endpoints: [GarminEndpoint] = []
    var deferred = false
    for summary in page.values {
      guard let id = summary.activityId, id > 0,
        let start = summary.startTimeLocal, DateKey(rawValue: String(start.prefix(10))) != nil
      else { continue }
      switch decision(page.previous[id], summary, endpoint, attempted.contains(id)) {
      case .fetch:
        let detail = GarminEndpoint.activity(id)
        if !endpoints.contains(detail) { endpoints.append(detail) }
      case .deferCompletion: deferred = true
      case .skip: break
      }
    }
    return DetailPlan(endpoints: endpoints, deferred: deferred)
  }

  func pagination(page: [ActivityDTO], response: GarminResponse) -> (
    memberCount: Int, hasNewIDs: Bool
  ) {
    let ids = page.compactMap(\.activityId)
    let hasNewIDs = !Set(ids).subtracting(seen).isEmpty
    seen.formUnion(ids)
    return (response.memberCount ?? (page.count + response.rejections.count), hasNewIDs)
  }
}
