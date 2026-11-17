import Foundation
import ScoringKit
import SwiftData
import Synchronization

/// All contexts and persistent models stay inside this actor. Only value snapshots leave it.
actor GarminStore: CheckInStoring, BriefCaching, ReminderStoring {
  #if DEBUG
    nonisolated let openedOnMainThread: Bool
  #endif
  private let container: ModelContainer
  private nonisolated let checkIns: CheckInPersistence
  private nonisolated let executor: StoreSerialModelExecutor
  private var context: ModelContext { executor.modelContext }
  private let beforeSave: @Sendable () throws -> Void
  private let storeURL: URL?
  private var scoreGeneration = UUID()
  private var sessions: [UUID: Progress] = [:]

  // Run actor jobs on the context's own serial executor without exposing its models/context.
  nonisolated var unownedExecutor: UnownedSerialExecutor { executor.asUnownedSerialExecutor() }

  private struct Progress {
    let revision: CredentialRevision
    var required: Set<String>
    var imported: Set<String> = []
    var noData: Set<String> = []
    var skipped: Set<String> = []

    var completed: Set<String> { imported.union(noData).union(skipped) }
  }

  private struct PreparedDay {
    let date: DateKey
    let data: Data
  }

  private enum PreparedActivity {
    case summary(Int64, DateKey, Data)
    case detail(Int64, DateKey, Data)
    case workouts(Int64, Data)
    case archive(Int64)

    var id: Int64 {
      switch self {
      case .summary(let id, _, _), .detail(let id, _, _), .workouts(let id, _), .archive(let id): id
      }
    }
  }

  private init(
    container: ModelContainer, storeURL: URL?, beforeSave: @escaping @Sendable () throws -> Void
  ) {
    precondition(!Thread.isMainThread)
    #if DEBUG
      openedOnMainThread = Thread.isMainThread
    #endif
    self.container = container
    checkIns = CheckInPersistence(container: container, storeURL: storeURL, beforeSave: beforeSave)
    executor = StoreSerialModelExecutor(container: container, label: "Diel.store.records")
    self.beforeSave = beforeSave
    self.storeURL = storeURL
  }

  /// No CloudKit, app groups, migration guesses or destructive fallback.
  nonisolated static func persistent(
    at url: URL? = nil, beforeSave: @escaping @Sendable () throws -> Void = {}
  ) throws -> GarminStore {
    try open(inMemory: false, url: url, beforeSave: beforeSave)
  }

  nonisolated static func inMemory(
    beforeSave: @escaping @Sendable () throws -> Void = {}
  ) throws -> GarminStore {
    try open(inMemory: true, url: nil, beforeSave: beforeSave)
  }

  private nonisolated static let openingQueue = DispatchQueue(
    label: "Diel.store.open", qos: .userInitiated)

  /// Factories retain their synchronous API for fixtures/tests. App startup calls them detached.
  /// async dispatch is required: DispatchQueue.sync may execute inline on the calling thread.
  private nonisolated static func open(
    inMemory: Bool, url: URL?, beforeSave: @escaping @Sendable () throws -> Void
  ) throws -> GarminStore {
    let result = Mutex<Result<GarminStore, any Error>?>(nil)
    let completed = DispatchSemaphore(value: 0)
    openingQueue.async {
      let opened = Result { try make(inMemory: inMemory, url: url, beforeSave: beforeSave) }
      result.withLock { $0 = opened }
      completed.signal()
    }
    completed.wait()
    return try result.withLock { try $0!.get() }
  }

  private nonisolated static func make(
    inMemory: Bool, url: URL?, beforeSave: @escaping @Sendable () throws -> Void
  ) throws -> GarminStore {
    let schema = Schema(versionedSchema: DielSchemaV5.self)
    let configuration: ModelConfiguration
    if let url {
      configuration = ModelConfiguration(
        "Diel", schema: schema, url: url, cloudKitDatabase: .none)
    } else {
      configuration = ModelConfiguration(
        "Diel", schema: schema, isStoredInMemoryOnly: inMemory,
        groupContainer: .none, cloudKitDatabase: .none)
    }
    do {
      let storeURL = inMemory ? nil : configuration.url
      if let storeURL { try protectStore(at: storeURL, createDirectory: true) }
      let container = try ModelContainer(
        for: schema, migrationPlan: DielMigrationPlan.self, configurations: [configuration])
      if let storeURL { try protectStore(at: storeURL) }
      return GarminStore(container: container, storeURL: storeURL, beforeSave: beforeSave)
    } catch {
      throw GarminStoreError.openFailed
    }
  }

  /// Protect the existing location, including SQLite sidecars and external score/raw blobs.
  fileprivate nonisolated static func protectStore(at url: URL, createDirectory: Bool = false)
    throws
  {
    let manager = FileManager.default
    let directory = url.deletingLastPathComponent()
    let attributes: [FileAttributeKey: Any] = [
      .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
    ]
    if createDirectory {
      try manager.createDirectory(
        at: directory, withIntermediateDirectories: true, attributes: attributes)
    }
    try manager.setAttributes(attributes, ofItemAtPath: directory.path)
    if let items = manager.enumerator(at: directory, includingPropertiesForKeys: nil) {
      for case let item as URL in items {
        // The default Application Support directory can contain unrelated app settings.
        if item.lastPathComponent.hasPrefix(url.lastPathComponent)
          || item.path.contains(".\(url.deletingPathExtension().lastPathComponent)_SUPPORT/")
          || item.lastPathComponent == ".\(url.deletingPathExtension().lastPathComponent)_SUPPORT"
        {
          try manager.setAttributes(attributes, ofItemAtPath: item.path)
        }
      }
    }
  }

  func reminderPreferences() throws -> ReminderPreferencesSnapshot {
    let identity = "morning"
    guard
      let record = try fetch(
        FetchDescriptor<ReminderPreferences>(predicate: #Predicate { $0.identity == identity })
      ).first
    else { return .defaults }
    let value = ReminderPreferencesSnapshot(
      enabled: record.enabled, firstMinute: record.firstMinute, missedMinute: record.missedMinute)
    guard value.isValid else { throw ReminderError.invalidPreferences }
    return value
  }

  @discardableResult
  func saveReminderPreferences(_ value: ReminderPreferencesSnapshot) throws
    -> ReminderPreferencesSnapshot
  {
    guard value.isValid else { throw ReminderError.invalidPreferences }
    let identity = "morning"
    return try transaction {
      if let record = try fetch(
        FetchDescriptor<ReminderPreferences>(predicate: #Predicate { $0.identity == identity })
      ).first {
        record.enabled = value.enabled
        record.firstMinute = value.firstMinute
        record.missedMinute = value.missedMinute
      } else {
        context.insert(ReminderPreferences(value))
      }
      return value
    }
  }

  func reserveBrief(context route: BriefCacheContext, input: BriefInput, at date: Date) throws
    -> BriefReservation
  {
    let identity = route.identity
    let scope = route.scopeID
    let records = try fetch(
      FetchDescriptor<BriefRecord>(predicate: #Predicate { $0.scopeID == scope }))
    let existing = records.first { $0.identity == identity }
    let latest = records.max { $0.generatedAt < $1.generatedAt }
    // A completed row is current only while it remains the latest actual attempt.
    // Deferred score changes do not create attempts, so A can still be reused after
    // an ungenerated B request; a genuinely started B makes an older A stale.
    if let record = existing, latest?.identity == identity, let bytes = record.encodedBrief {
      let original = try decode(BriefInput.self, record.encodedInput)
      let brief = try decode(Brief.self, bytes)
      guard BriefValidator.isValid(brief, for: original) else { throw BriefError.invalidOutput }
      return .completed(brief)
    }
    // A score that was missing in the latest same-day attempt and now has a value starts a
    // brief at once; every other score change waits out the cooldown. A strictly later start
    // keeps the older generation superseded.
    let resolvesMissing =
      latest.map { latest in
        latest.dayID == route.dayID && date > latest.generatedAt
          && (try? decode(BriefInput.self, latest.encodedInput)).map {
            input.resolvesMissingScore(of: $0)
          } == true
      } ?? false
    if let latest, !resolvesMissing {
      let next = latest.generatedAt.addingTimeInterval(30 * 60)
      if date < next {
        let previous: Brief?
        if let completed = records.filter({ $0.dayID == route.dayID && $0.encodedBrief != nil })
          .max(by: { $0.generatedAt < $1.generatedAt }), let bytes = completed.encodedBrief
        {
          let priorInput = try decode(BriefInput.self, completed.encodedInput)
          let cached = try decode(Brief.self, bytes)
          previous =
            BriefValidator.isValid(cached, for: priorInput)
            ? cached : TemplateBriefGenerator.make(priorInput)
        } else if latest.dayID == route.dayID {
          previous = TemplateBriefGenerator.make(try decode(BriefInput.self, latest.encodedInput))
        } else {
          previous = nil
        }
        let currentReservation =
          latest.identity == identity && latest.encodedBrief == nil
          ? latest.reservationID : nil
        return .deferred(until: next, previous: previous, currentReservation: currentReservation)
      }
    }
    let reservation = UUID()
    let bytes = try encode(input)
    try transaction {
      if let existing {
        existing.reservationID = reservation
        existing.encodedInput = bytes
        existing.encodedBrief = nil
        existing.generatedAt = date
      } else {
        context.insert(
          BriefRecord(context: route, reservationID: reservation, input: bytes, at: date))
      }
    }
    return .acquired(reservation)
  }

  /// The newest completed brief for a day and scope that still passes the validator, as
  /// `reserveBrief` requires before reuse. It reads only; reservations are unchanged.
  func latestCompletedBrief(dayID: String, scopeID: String) throws -> StoredBrief? {
    let day = dayID
    let scope = scopeID
    let records = try fetch(
      FetchDescriptor<BriefRecord>(
        predicate: #Predicate { $0.scopeID == scope && $0.dayID == day },
        sortBy: [SortDescriptor(\.generatedAt, order: .reverse)]))
    for record in records {
      guard let bytes = record.encodedBrief,
        let input = try? decode(BriefInput.self, record.encodedInput),
        let brief = try? decode(Brief.self, bytes), BriefValidator.isValid(brief, for: input)
      else { continue }
      return StoredBrief(
        context: BriefCacheContext(
          dayID: record.dayID, scopeID: record.scopeID,
          scoreFingerprint: record.scoreFingerprint), brief: brief)
    }
    return nil
  }

  func finishBrief(
    _ brief: Brief, context route: BriefCacheContext, reservation: UUID, at date: Date
  ) throws {
    let identity = route.identity
    let scope = route.scopeID
    let records = try fetch(
      FetchDescriptor<BriefRecord>(predicate: #Predicate { $0.scopeID == scope }))
    guard let record = records.first(where: { $0.identity == identity }),
      record.reservationID == reservation, record.encodedBrief == nil,
      !records.contains(where: {
        $0.generatedAt > record.generatedAt
      })
    else { throw BriefError.invalidReservation }
    let original = try decode(BriefInput.self, record.encodedInput)
    guard BriefValidator.isValid(brief, for: original) else { throw BriefError.invalidOutput }
    let bytes = try encode(brief)
    try transaction {
      record.encodedBrief = bytes
    }
  }

  nonisolated func checkIn(for dayID: String) async throws -> CheckInSnapshot? {
    try await checkIns.checkIn(for: dayID)
  }

  nonisolated func checkInHistory() async throws -> [CheckInSnapshot] {
    try await checkIns.checkInHistory()
  }

  @discardableResult
  nonisolated func saveCheckIn(dayID: String, rating: Int?, skipped: Bool, at date: Date)
    async throws
    -> CheckInSnapshot
  {
    try await checkIns.saveCheckIn(dayID: dayID, rating: rating, skipped: skipped, at: date)
  }

  func beginScoreCalculation(revision: CredentialRevision) throws -> UUID {
    try validate(revision)
    scoreGeneration = UUID()
    return scoreGeneration
  }

  func scoringCalculationSnapshot(in dates: ClosedRange<DateKey>, revision: CredentialRevision)
    throws -> (source: GarminScoringSnapshot, generation: UUID)
  {
    let source = try scoringSnapshot(in: dates, revision: revision)
    return (source, try beginScoreCalculation(revision: revision))
  }

  func savedScores(revision: CredentialRevision) throws -> [ScoredDay] {
    try validate(revision)
    let scope = revision.id
    let version = "diel-day-2/readiness-v2.2/all-day-load-v1"
    return try fetch(
      FetchDescriptor<ComputedDayRecord>(
        predicate: #Predicate { $0.revisionID == scope && $0.version == version })
    ).sorted { $0.calendarDate < $1.calendarDate }.map {
      try decode(ScoredDay.self, $0.encodedScores)
    }
  }

  func scoresNeedRecalculation(revision: CredentialRevision) throws -> Bool {
    try validate(revision)
    return try state(identity: "scores-dirty|\(revision.id.uuidString)") != nil
  }

  /// Invalidated score bundles leave only a numeric running-load floor, never stale source IDs.
  func savedLoadMinimums(revision: CredentialRevision) throws -> [ScoringDate: Double] {
    try validate(revision)
    let scope = revision.id
    let version = "diel-load-minimum-v1"
    var result: [ScoringDate: Double] = [:]
    for record in try fetch(
      FetchDescriptor<ComputedDayRecord>(
        predicate: #Predicate { $0.revisionID == scope && $0.version == version }))
    {
      guard let date = ScoringDate(rawValue: record.calendarDate) else { continue }
      result[date] = try decode(Double.self, record.encodedScores)
    }
    return result
  }

  /// The actor validates both scope and calculation ownership inside the save transaction.
  func saveScores(
    _ scores: [ScoredDay], revision: CredentialRevision, generation: UUID, at date: Date
  ) throws -> [ScoredDay] {
    try Task.checkCancellation()
    try validate(revision)
    guard scoreGeneration == generation else { throw CancellationError() }
    if scores.isEmpty { return try savedScores(revision: revision) }
    let version = "diel-day-2/readiness-v2.2/all-day-load-v1"
    let encoded = try scores.map { ($0.input.date.rawValue, try encode($0)) }
    try transaction {
      if let dirty = try state(identity: "scores-dirty|\(revision.id.uuidString)") {
        context.delete(dirty)
      }
      for (label, bytes) in encoded {
        let identity = "\(revision.id.uuidString)|\(label)|\(version)"
        if let record = try fetch(
          FetchDescriptor<ComputedDayRecord>(predicate: #Predicate { $0.identity == identity })
        ).first {
          record.encodedScores = bytes
          record.computedAt = date
        } else {
          context.insert(
            ComputedDayRecord(
              revisionID: revision.id, calendarDate: label, version: version, at: date, bytes: bytes
            ))
        }
      }
    }
    return try savedScores(revision: revision)
  }

  func activeRevision() throws -> CredentialRevision? {
    try state(identity: "active")?.revisionID.map { CredentialRevision(id: $0) }
  }

  /// Removal selects no scope; it never deletes the user's historical records.
  func setActiveRevision(_ revision: CredentialRevision?) throws {
    try transaction {
      let active = try state(identity: "active") ?? insertState(identity: "active", revision: nil)
      active.revisionID = revision?.id
    }
    sessions.removeAll()
    scoreGeneration = UUID()
  }

  func status(revision: CredentialRevision) throws -> GarminSyncStatus {
    let record = try state(identity: revision.id.uuidString)
    return GarminSyncStatus(
      revision: revision, lastAttemptAt: record?.lastAttemptAt,
      lastCompleteSyncAt: record?.lastCompleteSyncAt)
  }

  /// A completion requires every declared endpoint to commit (or explicitly return no data).
  func beginSync(
    revision: CredentialRevision, requiredEndpoints: [GarminEndpoint], at date: Date
  ) throws -> GarminSyncSession {
    try validate(revision)
    let required = try Set(requiredEndpoints.map(route))
    let session = GarminSyncSession(id: UUID(), revision: revision)
    try transaction {
      let record =
        try state(identity: revision.id.uuidString)
        ?? insertState(identity: revision.id.uuidString, revision: revision)
      record.lastAttemptAt = date
    }
    sessions[session.id] = Progress(revision: revision, required: required)
    return session
  }

  /// Pagination can extend the required set before a subsequent page is fetched.
  func require(_ endpoints: [GarminEndpoint], for session: GarminSyncSession) throws {
    try validate(session)
    let routes = try endpoints.map(route)
    sessions[session.id]?.required.formUnion(routes)
  }

  func completeSync(_ session: GarminSyncSession, at date: Date) throws {
    try validate(session)
    guard let progress = sessions[session.id], progress.required.isSubset(of: progress.completed)
    else { throw GarminStoreError.incompleteSync }
    try transaction {
      let record =
        try state(identity: session.revision.id.uuidString)
        ?? insertState(identity: session.revision.id.uuidString, revision: session.revision)
      record.lastCompleteSyncAt = max(record.lastCompleteSyncAt ?? date, date)
    }
    sessions.removeValue(forKey: session.id)
  }

  func cancelSync(_ session: GarminSyncSession) {
    sessions.removeValue(forKey: session.id)
  }

  /// The client returns nil for 204/empty/null. No source bytes exist at this boundary.
  /// This records successful required work without erasing any cached projection.
  func recordNoData(
    endpoint: GarminEndpoint, revision: CredentialRevision, session: GarminSyncSession? = nil
  ) throws {
    try validate(revision)
    try validateOptional(session, revision: revision)
    let route = try route(endpoint)
    for identity in retryIdentities(revision: revision, route: route) {
      if let retry = try state(identity: identity) {
        try transaction {
          // A successful empty retry resolves the work without replacing cached values.
          retry.lastCompleteSyncAt = retry.lastAttemptAt
        }
      }
    }
    if let session { sessions[session.id]?.noData.insert(route) }
  }

  /// Re-decode the immutable source before touching SwiftData, including typed family matching.
  /// The supplied typed payload must describe these exact source bytes.
  @discardableResult
  func ingest(_ response: GarminResponse, session: GarminSyncSession? = nil) throws -> UUID {
    try ingestReport(response, session: session).sourceID
  }

  /// `retriesRejections: false` keeps accepted records but does not make the route a required
  /// retry, for best-effort requests whose rejected members later syncs need not chase.
  func ingestReport(
    _ response: GarminResponse, session: GarminSyncSession? = nil, retriesRejections: Bool = true
  ) throws -> GarminImportReport {
    try validate(response.revision)
    try validateOptional(session, revision: response.revision)
    let route = try route(response.endpoint)
    let report: GarminDecodeReport
    do {
      report = try GarminPayload.decodeRecords(response.rawData, as: response.endpoint.family)
    } catch { throw GarminStoreError.decoding }
    guard report.payload == response.payload, report.rejections == response.rejections,
      response.memberCount == nil || response.memberCount == report.memberCount
    else { throw GarminStoreError.invalidResponse }
    var rejections = report.rejections
    let emptyNights = try Self.emptyNights(response.rawData, family: response.endpoint.family)
    let days =
      try report.payload.map {
        try prepareDays(
          $0, endpoint: response.endpoint, emptyNights: emptyNights, rejections: &rejections)
      } ?? []
    #if DEBUG
      let sleepMembers = try Self.sleepMembers(response.rawData, family: response.endpoint.family)
      rejections = rejections.map { rejection in
        guard var missingDay = rejection.missingDay,
          sleepMembers.indices.contains(missingDay.memberIndex)
        else { return rejection }
        missingDay.presentFields = GarminMissingDayDiagnostic.presentFieldPaths(
          in: sleepMembers[missingDay.memberIndex])
        return rejection.withMissingDay(missingDay)
      }
    #endif
    let activities =
      try report.payload.map {
        try prepareActivities($0, endpoint: response.endpoint, rejections: &rejections)
      } ?? []
    let pieces = try GarminRawPiece.split(response.rawData, endpoint: response.endpoint)
    let id = try transaction {
      try consolidateRawStorage(revision: response.revision)
      var sources: [String: UUID] = [:]
      var stalePieces: Set<String> = []
      var lastID: UUID?
      for piece in pieces {
        let raw = try retainRaw(piece, response: response, route: route)
        sources[piece.key] = raw.id
        if response.fetchedAt < raw.lastFetchedAt { stalePieces.insert(piece.key) }
        lastID = raw.id
      }
      let retryID = retryIdentity(revision: response.revision, route: route)
      if !rejections.isEmpty, retriesRejections {
        let retry =
          try state(identity: retryID)
          ?? insertState(identity: retryID, revision: response.revision)
        if response.fetchedAt >= (retry.lastCompleteSyncAt ?? .distantPast) {
          retry.lastAttemptAt = max(retry.lastAttemptAt ?? .distantPast, response.fetchedAt)
          retry.lastCompleteSyncAt = nil
        }
      } else if rejections.isEmpty, let retry = try state(identity: retryID) {
        retry.lastCompleteSyncAt = max(retry.lastCompleteSyncAt ?? .distantPast, response.fetchedAt)
      }
      // A marker saved under the route before `chunks` is answered by this request's route,
      // whose own marker above carries any work that is still outstanding.
      for identity in retryIdentities(revision: response.revision, route: route).dropFirst() {
        if let retry = try state(identity: identity) {
          retry.lastCompleteSyncAt = max(
            retry.lastCompleteSyncAt ?? .distantPast, response.fetchedAt)
        }
      }
      for day in days where !stalePieces.contains(day.date.rawValue) {
        try upsert(
          day, response: response, sourceID: sources[day.date.rawValue] ?? lastID!)
      }
      for activity in activities where stalePieces.isEmpty {
        try upsert(activity, response: response, sourceID: lastID!)
      }
      try removeUnreferencedRawEvidence(revision: response.revision)
      let piece = pieces.last!
      let retainedIdentity = rawIdentity(
        revision: response.revision.id, family: response.endpoint.family.rawValue,
        key: piece.key == "route" ? route : piece.key)
      return try rawRecord(identity: retainedIdentity)?.id ?? lastID!
    }
    if let session {
      if !rejections.isEmpty { sessions[session.id]?.skipped.insert(route) }
      if !days.isEmpty || !activities.isEmpty { sessions[session.id]?.imported.insert(route) }
      if rejections.isEmpty && days.isEmpty && activities.isEmpty {
        sessions[session.id]?.noData.insert(route)
      }
    }
    scoreGeneration = UUID()
    return GarminImportReport(
      sourceID: id, importedCount: days.count + activities.count, rejections: rejections)
  }

  /// Retry markers use the existing state schema; skipped older routes survive incremental syncs
  /// and reopening the store. Original route bounds/page size are preserved.
  func retryEndpoints(revision: CredentialRevision) throws -> [GarminEndpoint] {
    try validate(revision)
    let scope = revision.id
    let records = try fetch(
      FetchDescriptor<GarminSyncState>(predicate: #Predicate { $0.revisionID == scope }))
    let pending = Set(
      records.compactMap { record -> String? in
        let prefix = retryIdentity(revision: revision, route: "")
        guard record.identity.hasPrefix(prefix), let attempt = record.lastAttemptAt,
          attempt > (record.lastCompleteSyncAt ?? .distantPast)
        else { return nil }
        return String(record.identity.dropFirst(prefix.count))
      })
    let raws = try rawResponses(revision: revision)
    return try pending.sorted().map { route in
      if let raw = raws.filter({ $0.route == route }).max(by: {
        $0.lastFetchedAt < $1.lastFetchedAt
      }) {
        return try retryEndpoint(raw)
      }
      // A later overlapping range can replace every dated shard from this request.
      // Retry routing is carried by the state identity, so it must not depend on old bodies.
      let family: GarminPayload.Family
      let path = URLComponents(string: route)?.path ?? ""
      if path.contains("dailySleepSummariesByDate") {
        family = .sleepSummaries
      } else if path.contains("dailySleep") {
        family = .sleep
      } else if path.contains("/hrv/daily/") {
        family = .hrvSummaries
      } else if path.contains("/hrv/") {
        family = .hrv
      } else if path.contains("dailyHeartRate") {
        family = .heartRate
      } else if path.contains("bodyBattery") {
        family = .bodyBattery
      } else if path.contains("/stress/daily/") {
        family = .stress
      } else if path.contains("dailysummaries") {
        family = .dailySummaries
      } else if path.contains("/steps/daily/") {
        family = .steps
      } else if path.contains("/spo2acclimation/") {
        family = .spo2
      } else if path.contains("/activities/search/") {
        family = .activities
      } else if path.contains("/activity-service/activity/") {
        family = .activity
      } else {
        throw GarminStoreError.invalidResponse
      }
      return try retryEndpoint(
        GarminRawSnapshot(
          id: UUID(), revision: revision, family: family, route: route, dates: nil,
          firstFetchedAt: .distantPast, lastFetchedAt: .distantPast, bytes: Data()))
    }
  }

  private func retryIdentity(revision: CredentialRevision, route: String) -> String {
    "retry|\(revision.id.uuidString)|\(route)"
  }

  /// The route's own marker, then the marker of the same request saved before `chunks` existed.
  private func retryIdentities(revision: CredentialRevision, route: String) -> [String] {
    var identities = [retryIdentity(revision: revision, route: route)]
    if GarminEndpoint.requestsChunks(route), var components = URLComponents(string: route) {
      components.queryItems = components.queryItems?.filter { $0.name != "chunks" }
      if let legacy = components.string {
        identities.append(retryIdentity(revision: revision, route: legacy))
      }
    }
    return identities
  }

  /// True when a stored Body Battery day in `dates` came from a request without `chunks`, no
  /// chunked response for that date has been retained since, and no backfill request has been
  /// answered for this revision. Any answered backfill ends it, even one that omitted a day.
  func bodyBatteryNeedsChunkedRefetch(
    in dates: ClosedRange<DateKey>, revision: CredentialRevision
  ) throws -> Bool {
    guard try state(identity: bodyBatteryBackfillIdentity(revision)) == nil else { return false }
    let scope = revision.id
    let family = GarminPayload.Family.bodyBattery.rawValue
    let lower = dates.lowerBound.rawValue
    let upper = dates.upperBound.rawValue
    let records = try fetch(
      FetchDescriptor<GarminDayRecord>(
        predicate: #Predicate {
          $0.revisionID == scope && $0.family == family && $0.calendarDate >= lower
            && $0.calendarDate <= upper
        }))
    guard !records.isEmpty else { return false }
    let raws = try fetch(
      FetchDescriptor<RawGarminResponse>(
        predicate: #Predicate { $0.revisionID == scope && $0.family == family }))
    let routes = Dictionary(raws.map { ($0.id, $0.route) }, uniquingKeysWith: { first, _ in first })
    let latest = Dictionary(
      raws.map { ($0.identity, $0.route) }, uniquingKeysWith: { first, _ in first })
    return records.contains { record in
      guard let source = routes[record.sourceResponseID],
        !GarminEndpoint.requestsChunks(source)
      else { return false }
      let key = rawIdentity(revision: scope, family: family, key: record.calendarDate)
      return latest[key].map { !GarminEndpoint.requestsChunks($0) } ?? true
    }
  }

  /// Records that Garmin answered the chunked Body Battery backfill, with data or without.
  func recordBodyBatteryBackfill(revision: CredentialRevision, at date: Date) throws {
    try validate(revision)
    let identity = bodyBatteryBackfillIdentity(revision)
    try transaction {
      let record =
        try state(identity: identity) ?? insertState(identity: identity, revision: revision)
      record.lastCompleteSyncAt = date
    }
  }

  private func bodyBatteryBackfillIdentity(_ revision: CredentialRevision) -> String {
    "bb-chunked-backfill|\(revision.id.uuidString)"
  }

  /// When an initial or fuller sync, which requires every pending retry, last completed.
  func lastFullerSync(revision: CredentialRevision) throws -> Date? {
    try validate(revision)
    return try state(identity: fullerSyncIdentity(revision))?.lastCompleteSyncAt
  }

  func recordFullerSync(revision: CredentialRevision, at date: Date) throws {
    try validate(revision)
    let identity = fullerSyncIdentity(revision)
    try transaction {
      let record =
        try state(identity: identity) ?? insertState(identity: identity, revision: revision)
      record.lastCompleteSyncAt = max(record.lastCompleteSyncAt ?? date, date)
    }
  }

  private func fullerSyncIdentity(_ revision: CredentialRevision) -> String {
    "fuller-sync|\(revision.id.uuidString)"
  }

  private func retryEndpoint(_ raw: GarminRawSnapshot) throws -> GarminEndpoint {
    let query = URLComponents(string: raw.route)?.queryItems ?? []
    let pathDates = raw.route.split(separator: "/").compactMap { DateKey(rawValue: String($0)) }
    let queryStart = query.first(where: { $0.name == "startDate" })?.value.flatMap(
      DateKey.init(rawValue:))
    let queryEnd = query.first(where: { $0.name == "endDate" })?.value.flatMap(
      DateKey.init(rawValue:))
    let day = query.first(where: { $0.name == "date" })?.value.flatMap(DateKey.init(rawValue:))
    let lower = queryStart ?? day ?? pathDates.first ?? raw.dates?.lowerBound
    let upper = queryEnd ?? day ?? pathDates.last ?? raw.dates?.upperBound
    if let start = lower, let end = upper {
      switch raw.family {
      case .sleep: return .sleep(start)
      case .sleepSummaries: return .sleepSummaries(start: start, end: end)
      case .hrv: return .hrv(start)
      case .hrvSummaries: return .hrvSummaries(start: start, end: end)
      case .heartRate: return .heartRate(start)
      case .bodyBattery: return .bodyBattery(start: start, end: end)
      case .stress: return .stress(start: start, end: end)
      case .dailySummaries: return .dailySummaries(start: start, end: end)
      case .steps: return .steps(start: start, end: end)
      case .spo2: return .spo2(start)
      case .activities:
        let components = URLComponents(string: raw.route)
        let query = components?.queryItems ?? []
        guard let offset = query.first(where: { $0.name == "start" })?.value.flatMap(Int.init),
          let limit = query.first(where: { $0.name == "limit" })?.value.flatMap(Int.init)
        else { throw GarminStoreError.invalidResponse }
        return .activities(start: start, end: end, offset: offset, limit: limit)
      default: break
      }
    }
    if raw.family == .activity,
      let component = raw.route.split(separator: "/").last, let id = Int64(component), id > 0
    {
      return .activity(id)
    }
    throw GarminStoreError.invalidResponse
  }

  func day(_ date: DateKey, revision: CredentialRevision) throws -> GarminDaySnapshot? {
    let scope = revision.id
    let label = date.rawValue
    let records = try fetch(
      FetchDescriptor<GarminDayRecord>(
        predicate: #Predicate { $0.revisionID == scope && $0.calendarDate == label }))
    guard !records.isEmpty else { return nil }
    let values = try records.sorted { $0.family < $1.family }.map { record in
      guard let family = GarminPayload.Family(rawValue: record.family) else {
        throw GarminStoreError.decoding
      }
      return GarminDayValue(
        family: family, sourceResponseID: record.sourceResponseID, fetchedAt: record.fetchedAt,
        projection: try decode(GarminDayProjection.self, record.encodedProjection))
    }
    return GarminDaySnapshot(revision: revision, date: date, values: values)
  }

  func days(in dates: ClosedRange<DateKey>, revision: CredentialRevision) throws
    -> [GarminDaySnapshot]
  {
    let scope = revision.id
    let lower = dates.lowerBound.rawValue
    let upper = dates.upperBound.rawValue
    let records = try fetch(
      FetchDescriptor<GarminDayRecord>(
        predicate: #Predicate {
          $0.revisionID == scope && $0.calendarDate >= lower && $0.calendarDate <= upper
        }))
    return try Set(records.map(\.calendarDate)).sorted().map { label in
      guard let date = DateKey(rawValue: label), let snapshot = try day(date, revision: revision)
      else {
        throw GarminStoreError.decoding
      }
      return snapshot
    }
  }

  /// Builds coverage from accepted source pages inside the actor, without exporting raw bodies.
  func scoringSnapshot(in dates: ClosedRange<DateKey>, revision: CredentialRevision) throws
    -> GarminScoringSnapshot
  {
    try validate(revision)
    let raws = try rawResponses(revision: revision)
    // An older successful body cannot hide a newer rejected observation of the same route.
    let latest = Dictionary(
      grouping: raws.filter(\.payloadRetained),
      by: { raw in
        raw.family == .activities
          ? raw.route : "\(raw.family.rawValue)|\(raw.dates?.lowerBound.rawValue ?? raw.route)"
      }
    ).compactMap { _, values in
      values.max { $0.lastFetchedAt < $1.lastFetchedAt }
    }
    var skipped: [GarminSkippedSleep] = []
    for raw in latest where raw.family == .sleepSummaries || raw.family == .sleep {
      let report = try GarminPayload.decodeRecords(raw.bytes, as: raw.family)
      let sleep: [SleepDTO]
      switch report.payload {
      case .sleepSummaries(let values): sleep = values
      case .sleep(let value): sleep = [value]
      default: continue
      }
      let empty = try Self.emptyNights(raw.bytes, family: raw.family)
      for (index, value) in sleep.enumerated()
      where value.resolvedDate == nil && !(empty.indices.contains(index) && empty[index]) {
        let candidate = value.sleepNeed?.calendarDate
        skipped.append(
          GarminSkippedSleep(
            candidateDate: candidate, provenance: candidate == nil ? .unknown : .inferredSleepNeed,
            source: ScoringSource(
              family: raw.family, responseID: raw.id, fetchedAt: raw.lastFetchedAt)))
      }
    }
    let pages = latest.filter { $0.family == .activities }
    var coverage: [GarminActivityCoverage] = []
    for root in pages {
      guard let window = root.dates, window.overlaps(dates),
        let query = URLComponents(string: root.route)?.queryItems,
        query.first(where: { $0.name == "start" })?.value == "0",
        let limit = query.first(where: { $0.name == "limit" })?.value.flatMap(Int.init), limit > 0
      else { continue }
      var offset = 0
      var complete = false
      var coverageReason: ScoringMissingReason? = .partial
      var sources: [ScoringSource] = []
      var seenIDs: Set<Int64> = []
      var idsByDate: [DateKey: Set<Int64>] = [:]
      while let page = pages.first(where: { candidate in
        guard candidate.dates == window, candidate.lastFetchedAt >= root.lastFetchedAt,
          let items = URLComponents(string: candidate.route)?.queryItems
        else { return false }
        return items.first(where: { $0.name == "start" })?.value == String(offset)
          && items.first(where: { $0.name == "limit" })?.value == String(limit)
      }) {
        sources.append(
          ScoringSource(family: .activities, responseID: page.id, fetchedAt: page.lastFetchedAt))
        let report = try GarminPayload.decodeRecords(page.bytes, as: .activities)
        guard report.rejections.isEmpty, case .activities(let values) = report.payload,
          values.allSatisfy({ value in
            guard let id = value.activityId, id > 0, let start = value.startTimeLocal else {
              return false
            }
            return DateKey(rawValue: String(start.prefix(10))) != nil
          })
        else {
          coverageReason = .skipped
          break
        }
        for value in values {
          if let id = value.activityId, let start = value.startTimeLocal,
            let date = DateKey(rawValue: String(start.prefix(10)))
          {
            idsByDate[date, default: []].insert(id)
          }
        }
        if report.memberCount < limit {
          complete = true
          coverageReason = nil
          break
        }
        let ids = Set(values.compactMap(\.activityId))
        guard !ids.subtracting(seenIDs).isEmpty else { break }
        seenIDs.formUnion(ids)
        offset += report.memberCount
      }
      coverage.append(
        GarminActivityCoverage(
          dates: window, fetchedAt: root.lastFetchedAt, completePagination: complete,
          reason: coverageReason, activityIDsByDate: idsByDate, sources: sources))
    }
    return GarminScoringSnapshot(
      revision: revision, days: try days(in: dates, revision: revision),
      activities: try activities(revision: revision), activityCoverage: coverage,
      skippedSleep: skipped,
      sourceMetadata: Dictionary(
        uniqueKeysWithValues: raws.map {
          ($0.id, ScoringSource(family: $0.family, responseID: $0.id, fetchedAt: $0.lastFetchedAt))
        }))
  }

  func rawResponse(id: UUID, revision: CredentialRevision) throws -> GarminRawSnapshot? {
    let scope = revision.id
    let records = try fetch(
      FetchDescriptor<RawGarminResponse>(
        predicate: #Predicate { $0.id == id && $0.revisionID == scope }))
    return try records.first.map(rawSnapshot)
  }

  func rawResponses(revision: CredentialRevision) throws -> [GarminRawSnapshot] {
    let scope = revision.id
    if try fetch(
      FetchDescriptor<RawGarminResponse>(
        predicate: #Predicate { $0.revisionID == scope })
    ).contains(where: {
      !$0.identity.hasPrefix("latest2|") && !$0.identity.hasPrefix("evidence2|")
    }) {
      try transaction { try consolidateRawStorage(revision: revision) }
    }
    return try fetch(
      FetchDescriptor<RawGarminResponse>(predicate: #Predicate { $0.revisionID == scope })
    ).sorted { $0.firstFetchedAt < $1.firstFetchedAt }.map(rawSnapshot)
  }

  func activity(_ id: Int64, revision: CredentialRevision) throws -> GarminActivitySnapshot? {
    let identity = "\(revision.id.uuidString)|\(id)"
    return try activityRecord(identity: identity).map {
      try activitySnapshot($0, revision: revision)
    }
  }

  func activities(revision: CredentialRevision) throws -> [GarminActivitySnapshot] {
    let scope = revision.id
    return try fetch(
      FetchDescriptor<GarminActivityRecord>(predicate: #Predicate { $0.revisionID == scope })
    ).sorted { $0.activityID < $1.activityID }.map { try activitySnapshot($0, revision: revision) }
  }

  /// `emptyNights` lines up with the decoded sleep members; other families pass it empty.
  private func prepareDays(
    _ payload: GarminPayload, endpoint: GarminEndpoint, emptyNights: [Bool],
    rejections: inout [GarminRecordRejection]
  ) throws -> [PreparedDay] {
    var values: [(DateKey?, GarminDayProjection)] = []
    switch payload {
    case .sleep(let dto): values = [(dto.resolvedDate, .sleep(dto))]
    case .sleepSummaries(let dtos):
      values = dtos.map { ($0.resolvedDate, .sleepSummary($0)) }
    case .hrv(let dto): values = [(dto.hrvSummary?.calendarDate, .hrv(dto))]
    case .hrvSummaries(let dto):
      guard let summaries = dto.hrvSummaries else { throw GarminStoreError.invalidResponse }
      values = summaries.map { ($0.calendarDate, .hrvSummary($0)) }
    case .heartRate(let dto): values = [(dto.calendarDate, .heartRate(dto))]
    case .bodyBattery(let dtos): values = dtos.map { ($0.date, .bodyBattery($0)) }
    case .stress(let dtos): values = dtos.map { ($0.calendarDate, .stress($0)) }
    case .dailySummaries(let dto):
      guard let summaries = dto.data else { throw GarminStoreError.invalidResponse }
      values = summaries.map { ($0.calendarDate, .dailySummary($0)) }
    case .steps(let dtos): values = dtos.map { ($0.calendarDate, .steps($0)) }
    case .spo2(let dto): values = [(dto.calendarDate, .spo2(dto))]
    case .activities, .activity, .workouts, .archive: break
    }
    return try values.enumerated().compactMap { index, entry in
      let (date, value) = entry
      let inferredSleepDate: Bool
      switch value {
      case .sleep(let dto), .sleepSummary(let dto):
        // A night with no recorded sleep is no data, not a rejection, and never a projection.
        if emptyNights.indices.contains(index), emptyNights[index] { return nil }
        inferredSleepDate = dto.calendarDate == nil
      default: inferredSleepDate = false
      }
      guard let date, !inferredSleepDate || endpoint.dates?.contains(date) != false else {
        let field = date == nil ? "calendarDate" : "sleepNeed.calendarDate"
        let fieldPath: String
        switch endpoint.family {
        case .sleep, .heartRate, .spo2: fieldPath = field
        case .hrv: fieldPath = "hrvSummary.calendarDate"
        case .hrvSummaries: fieldPath = "hrvSummaries[\(index)].calendarDate"
        case .dailySummaries: fieldPath = "data[\(index)].calendarDate"
        case .bodyBattery: fieldPath = "[\(index)].date"
        default: fieldPath = "[\(index)].\(field)"
        }
        let rejection: GarminRecordRejection
        #if DEBUG
          let candidate: DateKey?
          switch value {
          case .sleep(let dto), .sleepSummary(let dto): candidate = dto.sleepNeed?.calendarDate
          default: candidate = nil
          }
          rejection = GarminRecordRejection(
            stage: .ingest, reason: .invalidResponse, date: date ?? candidate,
            fieldPath: fieldPath
          )
          .withMissingDay(
            GarminMissingDayDiagnostic(
              memberIndex: index, date: candidate,
              provenance: candidate == nil ? .unknown : .inferredSleepNeed))
        #else
          rejection = GarminRecordRejection(
            stage: .ingest, reason: .invalidResponse, date: date,
            fieldPath: fieldPath)
        #endif
        rejections.append(rejection)
        return nil
      }
      return PreparedDay(date: date, data: try encode(value))
    }
  }

  private func prepareActivities(
    _ payload: GarminPayload, endpoint: GarminEndpoint,
    rejections: inout [GarminRecordRejection]
  ) throws -> [PreparedActivity] {
    func localDate(_ value: String?) throws -> DateKey {
      guard let value, let date = DateKey(rawValue: String(value.prefix(10))) else {
        throw GarminStoreError.invalidResponse
      }
      return date
    }
    switch payload {
    case .activities(let dtos):
      return try dtos.compactMap {
        guard let id = $0.activityId, id > 0, let date = try? localDate($0.startTimeLocal) else {
          rejections.append(.init(stage: .ingest, reason: .invalidResponse))
          return nil
        }
        return .summary(id, date, try encode($0))
      }
    case .activity(let dto):
      guard case .activity(let id) = endpoint else { throw GarminStoreError.invalidResponse }
      guard id > 0, id == dto.activityId,
        let date = try? localDate(dto.summaryDTO?.startTimeLocal)
      else {
        rejections.append(.init(stage: .ingest, reason: .invalidResponse))
        return []
      }
      return [.detail(id, date, try encode(dto))]
    case .workouts(let dtos):
      guard case .workouts(let id) = endpoint else { throw GarminStoreError.invalidResponse }
      return [.workouts(id, try encode(dtos))]
    case .archive:
      guard case .archive(let id) = endpoint else { throw GarminStoreError.invalidResponse }
      return [.archive(id)]
    default: return []
    }
  }

  private func upsert(_ day: PreparedDay, response: GarminResponse, sourceID: UUID) throws {
    let incoming = try decode(GarminDayProjection.self, day.data)
    if let prior = try self.day(day.date, revision: response.revision),
      prior.values.contains(where: { incoming.losesValidReading(comparedWith: $0.projection) })
    {
      return
    }
    let identity =
      "\(response.revision.id.uuidString)|\(response.endpoint.family.rawValue)|\(day.date.rawValue)"
    let records = try fetch(
      FetchDescriptor<GarminDayRecord>(predicate: #Predicate { $0.identity == identity }))
    if let record = records.first {
      guard response.fetchedAt >= record.fetchedAt else { return }
      record.encodedProjection = day.data
      record.sourceResponseID = sourceID
      record.fetchedAt = response.fetchedAt
    } else {
      context.insert(
        GarminDayRecord(
          identity: identity, revisionID: response.revision.id,
          family: response.endpoint.family.rawValue,
          calendarDate: day.date.rawValue, sourceResponseID: sourceID,
          fetchedAt: response.fetchedAt,
          encodedProjection: day.data))
    }
  }

  private func upsert(
    _ activity: PreparedActivity, response: GarminResponse, sourceID: UUID
  ) throws {
    let identity = "\(response.revision.id.uuidString)|\(activity.id)"
    let record: GarminActivityRecord
    if let existing = try activityRecord(identity: identity) {
      record = existing
    } else {
      record = GarminActivityRecord(
        identity: identity, revisionID: response.revision.id, activityID: activity.id)
      context.insert(record)
    }
    switch activity {
    case .summary(_, let date, let data):
      guard response.fetchedAt >= (record.summaryFetchedAt ?? .distantPast) else { return }
      let previous = try record.summaryData.map { try decode(ActivityDTO.self, $0) }
      let current = try decode(ActivityDTO.self, data)
      var freshness = GarminActivityFreshness(
        pendingSince: record.detailRefreshPendingSince,
        hasVerifiedDetail: record.detailFreshnessKnown)
      freshness.observeSummary(previous: previous, current: current, at: response.fetchedAt)
      record.detailRefreshPendingSince = freshness.pendingSince
      record.summaryData = data
      record.summaryResponseID = sourceID
      record.summaryFetchedAt = response.fetchedAt
      if response.fetchedAt >= (record.detailFetchedAt ?? .distantPast) {
        record.calendarDate = date.rawValue
      }
    case .detail(_, let date, let data):
      guard response.fetchedAt >= (record.detailFetchedAt ?? .distantPast) else { return }
      var freshness = GarminActivityFreshness(
        pendingSince: record.detailRefreshPendingSince,
        hasVerifiedDetail: record.detailFreshnessKnown)
      freshness.importedDetail(at: response.fetchedAt)
      record.detailRefreshPendingSince = freshness.pendingSince
      record.detailFreshnessKnown = freshness.hasVerifiedDetail
      record.detailData = data
      record.detailResponseID = sourceID
      record.detailFetchedAt = response.fetchedAt
      if response.fetchedAt >= (record.summaryFetchedAt ?? .distantPast) {
        record.calendarDate = date.rawValue
      }
    case .workouts(_, let data):
      guard response.fetchedAt >= (record.workoutsFetchedAt ?? .distantPast) else { return }
      // An empty workout list has provenance but cannot erase previously populated data.
      let values = try decode([JSONValue].self, data)
      if !values.isEmpty || record.workoutsData == nil {
        record.workoutsData = data
        record.workoutsResponseID = sourceID
        record.workoutsFetchedAt = response.fetchedAt
      }
    case .archive:
      guard response.fetchedAt >= (record.archiveFetchedAt ?? .distantPast) else { return }
      record.archiveResponseID = sourceID
      record.archiveFetchedAt = response.fetchedAt
    }
  }

  private func activitySnapshot(
    _ record: GarminActivityRecord, revision: CredentialRevision
  ) throws -> GarminActivitySnapshot {
    var sources: [GarminPayload.Family: UUID] = [:]
    sources[.activities] = record.summaryResponseID
    sources[.activity] = record.detailResponseID
    sources[.workouts] = record.workoutsResponseID
    sources[.archive] = record.archiveResponseID
    let archive = try record.archiveResponseID.flatMap {
      try rawResponse(id: $0, revision: revision)?.bytes
    }
    return GarminActivitySnapshot(
      revision: revision, activityID: record.activityID,
      date: try record.calendarDate.map {
        guard let date = DateKey(rawValue: $0) else { throw GarminStoreError.decoding }
        return date
      },
      summary: try record.summaryData.map { try decode(ActivityDTO.self, $0) },
      detail: try record.detailData.map { try decode(ActivityDetailDTO.self, $0) },
      workouts: try record.workoutsData.map { try decode([JSONValue].self, $0) },
      archive: archive, sourceResponseIDs: sources,
      freshness: GarminActivityFreshness(
        pendingSince: record.detailRefreshPendingSince,
        hasVerifiedDetail: record.detailFreshnessKnown))
  }

  private func rawSnapshot(_ raw: RawGarminResponse) throws -> GarminRawSnapshot {
    guard let family = GarminPayload.Family(rawValue: raw.family) else {
      throw GarminStoreError.decoding
    }
    var dates: ClosedRange<DateKey>?
    if let start = raw.startDate, let end = raw.endDate {
      guard let lower = DateKey(rawValue: start), let upper = DateKey(rawValue: end), lower <= upper
      else { throw GarminStoreError.decoding }
      dates = lower...upper
    }
    return GarminRawSnapshot(
      id: raw.id, revision: CredentialRevision(id: raw.revisionID), family: family,
      route: raw.route, dates: dates, firstFetchedAt: raw.firstFetchedAt,
      lastFetchedAt: raw.lastFetchedAt, bytes: raw.bytes,
      payloadRetained: !raw.identity.hasPrefix("evidence2|"))
  }

  private func validate(_ revision: CredentialRevision) throws {
    guard try activeRevision() == revision else { throw GarminStoreError.staleRevision }
  }

  private func validate(_ session: GarminSyncSession) throws {
    try validate(session.revision)
    guard sessions[session.id]?.revision == session.revision else {
      throw GarminStoreError.unknownSync
    }
  }

  private func validateOptional(_ session: GarminSyncSession?, revision: CredentialRevision) throws
  {
    if let session {
      guard session.revision == revision else { throw GarminStoreError.staleRevision }
      try validate(session)
    }
  }

  private func route(_ endpoint: GarminEndpoint) throws -> String {
    guard let url = try? endpoint.request().url,
      let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    else { throw GarminStoreError.invalidResponse }
    return components.percentEncodedPath
      + (components.percentEncodedQuery.map { "?" + $0 } ?? "")
  }

  private func state(identity: String) throws -> GarminSyncState? {
    try fetch(FetchDescriptor<GarminSyncState>(predicate: #Predicate { $0.identity == identity }))
      .first
  }

  private func insertState(identity: String, revision: CredentialRevision?) -> GarminSyncState {
    let record = GarminSyncState(identity: identity, revisionID: revision?.id)
    context.insert(record)
    return record
  }

  private func rawIdentity(revision: UUID, family: String, key: String) -> String {
    "latest2|\(revision.uuidString)|\(family)|\(key)"
  }

  private func retainRaw(
    _ piece: GarminRawPiece, response: GarminResponse, route: String
  ) throws -> RawGarminResponse {
    let key = piece.key == "route" ? route : piece.key
    let identity = rawIdentity(
      revision: response.revision.id, family: response.endpoint.family.rawValue, key: key)
    let prior = try rawRecord(identity: identity)
    if let existing = prior {
      guard response.fetchedAt >= existing.lastFetchedAt else { return existing }
      if existing.bytes == piece.bytes {
        existing.firstFetchedAt = min(existing.firstFetchedAt, response.fetchedAt)
        existing.lastFetchedAt = response.fetchedAt
        existing.route = route
        return existing
      }
      // The latest response owns the only raw payload. A retained older projection keeps
      // its original source UUID, timestamps and parsed values through metadata only.
      existing.identity = "evidence2|\(existing.id.uuidString)"
      existing.bytes = Data()
    }
    let record = RawGarminResponse(
      identity: identity, revisionID: response.revision.id,
      family: response.endpoint.family.rawValue, route: route,
      startDate: piece.date?.rawValue ?? response.endpoint.dates?.lowerBound.rawValue,
      endDate: piece.date?.rawValue ?? response.endpoint.dates?.upperBound.rawValue,
      fetchedAt: response.fetchedAt, bytes: piece.bytes)
    record.firstFetchedAt = prior?.firstFetchedAt ?? response.fetchedAt
    context.insert(record)
    return record
  }

  /// Upgrade old hash identities in place. Only ranged daily bodies need splitting.
  /// Projection links are moved to their exact member; single-day source UUIDs survive.
  private func consolidateRawStorage(revision: CredentialRevision) throws {
    let scope = revision.id
    let old = try fetch(
      FetchDescriptor<RawGarminResponse>(
        predicate: #Predicate { $0.revisionID == scope })
    ).filter {
      !$0.identity.hasPrefix("latest2|") && !$0.identity.hasPrefix("evidence2|")
    }.sorted { $0.lastFetchedAt < $1.lastFetchedAt }
    for raw in old {
      guard let family = GarminPayload.Family(rawValue: raw.family) else { continue }
      let snapshot = try rawSnapshot(raw)
      let pieces = try GarminRawPiece.split(raw.bytes, family: family, dates: snapshot.dates)
      let projections = try fetch(
        FetchDescriptor<GarminDayRecord>(
          predicate: #Predicate { $0.revisionID == scope })
      ).filter { $0.sourceResponseID == raw.id }
      if pieces.count == 1, let piece = pieces.first {
        if let date = piece.date {
          raw.startDate = date.rawValue
          raw.endDate = date.rawValue
        }
        let identity = rawIdentity(
          revision: scope, family: raw.family, key: piece.key == "route" ? raw.route : piece.key)
        if let current = try rawRecord(identity: identity) {
          if current.bytes == piece.bytes {
            for projection in projections { projection.sourceResponseID = current.id }
            try remapActivitySources(from: raw.id, to: current.id, revision: scope)
            current.firstFetchedAt = min(current.firstFetchedAt, raw.firstFetchedAt)
            current.lastFetchedAt = max(current.lastFetchedAt, raw.lastFetchedAt)
            if let date = piece.date {
              current.startDate = date.rawValue
              current.endDate = date.rawValue
            }
            try invalidateScores(referencing: raw.id, revision: scope)
            context.delete(raw)
          } else {
            current.identity = "evidence2|\(current.id.uuidString)"
            current.bytes = Data()
            raw.firstFetchedAt = min(current.firstFetchedAt, raw.firstFetchedAt)
            raw.identity = identity
            raw.bytes = piece.bytes
          }
        } else {
          raw.identity = identity
          raw.bytes = piece.bytes
        }
        continue
      }
      for piece in pieces {
        let identity = rawIdentity(revision: scope, family: raw.family, key: piece.key)
        let record: RawGarminResponse
        if let current = try rawRecord(identity: identity),
          current.lastFetchedAt >= raw.lastFetchedAt
        {
          record = current
        } else {
          if let current = try rawRecord(identity: identity) {
            current.identity = "evidence2|\(current.id.uuidString)"
            current.bytes = Data()
          }
          record = RawGarminResponse(
            identity: identity, revisionID: scope, family: raw.family, route: raw.route,
            startDate: piece.date?.rawValue ?? raw.startDate,
            endDate: piece.date?.rawValue ?? raw.endDate, fetchedAt: raw.lastFetchedAt,
            bytes: piece.bytes)
          record.firstFetchedAt = raw.firstFetchedAt
          context.insert(record)
        }
        for projection in projections where projection.calendarDate == piece.key {
          // If another version of this date already exists, this old projection still needs
          // its own exact evidence rather than a link to the newer body.
          if record.bytes == piece.bytes {
            projection.sourceResponseID = record.id
          } else {
            let evidence = RawGarminResponse(
              identity: "evidence2|\(UUID().uuidString)", revisionID: scope, family: raw.family,
              route: raw.route, startDate: piece.date?.rawValue, endDate: piece.date?.rawValue,
              fetchedAt: raw.lastFetchedAt, bytes: Data())
            evidence.firstFetchedAt = raw.firstFetchedAt
            context.insert(evidence)
            projection.sourceResponseID = evidence.id
          }
        }
      }
      try invalidateScores(referencing: raw.id, revision: scope)
      context.delete(raw)
    }
    try removeUnreferencedRawEvidence(revision: revision)
  }

  private func remapActivitySources(from old: UUID, to new: UUID, revision: UUID) throws {
    for record in try fetch(
      FetchDescriptor<GarminActivityRecord>(
        predicate: #Predicate { $0.revisionID == revision }))
    {
      if record.summaryResponseID == old { record.summaryResponseID = new }
      if record.detailResponseID == old { record.detailResponseID = new }
      if record.workoutsResponseID == old { record.workoutsResponseID = new }
      if record.archiveResponseID == old { record.archiveResponseID = new }
    }
  }

  private func removeUnreferencedRawEvidence(revision: CredentialRevision) throws {
    let scope = revision.id
    var linked = Set(
      try fetch(
        FetchDescriptor<GarminDayRecord>(
          predicate: #Predicate { $0.revisionID == scope })
      ).map(\.sourceResponseID))
    for record in try fetch(
      FetchDescriptor<GarminActivityRecord>(
        predicate: #Predicate { $0.revisionID == scope }))
    {
      linked.formUnion(
        [
          record.summaryResponseID, record.detailResponseID,
          record.workoutsResponseID, record.archiveResponseID,
        ].compactMap { $0 })
    }
    let raws = try fetch(
      FetchDescriptor<RawGarminResponse>(
        predicate: #Predicate { $0.revisionID == scope }))
    for raw in raws where raw.identity.hasPrefix("evidence2|") {
      if linked.contains(raw.id) {
        raw.bytes = Data()
      } else {
        try invalidateScores(referencing: raw.id, revision: scope)
        context.delete(raw)
      }
    }
  }

  private func invalidateScores(referencing source: UUID, revision: UUID) throws {
    let records = try fetch(
      FetchDescriptor<ComputedDayRecord>(
        predicate: #Predicate { $0.revisionID == revision }))
    let sourceText = source.uuidString
    for record in records where record.version != "diel-load-minimum-v1" {
      // Encoded source UUIDs are opaque identities; changing their destination would alter
      // the provenance of cached measurements. Recompute the affected bundle instead.
      guard String(data: record.encodedScores, encoding: .utf8)?.contains(sourceText) == true else {
        continue
      }
      if let score = try? decode(ScoredDay.self, record.encodedScores),
        score.load.allDay != nil, let minimum = score.load.value
      {
        let version = "diel-load-minimum-v1"
        let identity = "\(revision.uuidString)|\(record.calendarDate)|\(version)"
        if let floor = try fetch(
          FetchDescriptor<ComputedDayRecord>(
            predicate: #Predicate { $0.identity == identity })
        ).first {
          let old = try decode(Double.self, floor.encodedScores)
          floor.encodedScores = try encode(max(old, minimum))
        } else {
          context.insert(
            ComputedDayRecord(
              revisionID: revision, calendarDate: record.calendarDate, version: version,
              at: record.computedAt, bytes: try encode(minimum)))
        }
      }
      let dirtyID = "scores-dirty|\(revision.uuidString)"
      if try state(identity: dirtyID) == nil {
        context.insert(GarminSyncState(identity: dirtyID, revisionID: revision))
      }
      context.delete(record)
    }
  }

  private func rawRecord(identity: String) throws -> RawGarminResponse? {
    try fetch(FetchDescriptor<RawGarminResponse>(predicate: #Predicate { $0.identity == identity }))
      .first
  }

  private func activityRecord(identity: String) throws -> GarminActivityRecord? {
    try fetch(
      FetchDescriptor<GarminActivityRecord>(predicate: #Predicate { $0.identity == identity })
    )
    .first
  }

  private func fetch<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) throws -> [T] {
    do { return try context.fetch(descriptor) } catch { throw GarminStoreError.readFailed }
  }

  private func encode<T: Encodable>(_ value: T) throws -> Data {
    do { return try JSONEncoder().encode(value) } catch { throw GarminStoreError.encoding }
  }

  private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
    do { return try JSONDecoder().decode(type, from: data) } catch {
      throw GarminStoreError.decoding
    }
  }

  private func transaction<T>(_ changes: () throws -> T) throws -> T {
    do {
      let value = try changes()
      do {
        try beforeSave()
        try context.save()
        if let storeURL { try Self.protectStore(at: storeURL) }
      } catch {
        throw GarminStoreError.saveFailed
      }
      return value
    } catch {
      context.rollback()
      throw error
    }
  }
}

/// An independent context lets a durable check-in bypass long import jobs on GarminStore.
private actor CheckInPersistence {
  private nonisolated let executor: StoreSerialModelExecutor
  private let container: ModelContainer
  private var context: ModelContext { executor.modelContext }
  private let beforeSave: @Sendable () throws -> Void
  private let storeURL: URL?
  nonisolated var unownedExecutor: UnownedSerialExecutor { executor.asUnownedSerialExecutor() }

  init(container: ModelContainer, storeURL: URL?, beforeSave: @escaping @Sendable () throws -> Void)
  {
    precondition(!Thread.isMainThread)
    self.container = container
    executor = StoreSerialModelExecutor(container: container, label: "Diel.store.check-ins")
    self.beforeSave = beforeSave
    self.storeURL = storeURL
  }

  func checkIn(for dayID: String) throws -> CheckInSnapshot? {
    guard
      let record = try fetch(
        FetchDescriptor<CheckIn>(predicate: #Predicate { $0.dayID == dayID })
      ).first
    else { return nil }
    return try checkInSnapshot(record)
  }

  func checkInHistory() throws -> [CheckInSnapshot] {
    try fetch(FetchDescriptor<CheckIn>(sortBy: [SortDescriptor(\.dayID)]))
      .map(checkInSnapshot)
  }

  @discardableResult
  func saveCheckIn(dayID: String, rating: Int?, skipped: Bool, at date: Date) throws
    -> CheckInSnapshot
  {
    guard DateKey(rawValue: dayID) != nil,
      skipped ? rating == nil : rating.map({ (1...5).contains($0) }) == true
    else { throw CheckInError.invalidAnswer }
    return try transaction {
      let record: CheckIn
      if let existing = try fetch(
        FetchDescriptor<CheckIn>(predicate: #Predicate { $0.dayID == dayID })
      ).first {
        record = existing
        record.rating = rating
        record.skipped = skipped
        record.recordedAt = date
      } else {
        record = CheckIn(dayID: dayID, rating: rating, skipped: skipped, recordedAt: date)
        context.insert(record)
      }
      return try checkInSnapshot(record)
    }
  }

  private func checkInSnapshot(_ record: CheckIn) throws -> CheckInSnapshot {
    guard
      record.skipped ? record.rating == nil : record.rating.map({ (1...5).contains($0) }) == true
    else { throw CheckInError.invalidAnswer }
    return CheckInSnapshot(
      dayID: record.dayID, rating: record.rating, skipped: record.skipped,
      recordedAt: record.recordedAt)
  }

  private func fetch<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) throws -> [T] {
    do { return try context.fetch(descriptor) } catch { throw GarminStoreError.readFailed }
  }

  private func transaction<T>(_ changes: () throws -> T) throws -> T {
    do {
      let result = try changes()
      do {
        try beforeSave()
        try context.save()
        if let storeURL { try GarminStore.protectStore(at: storeURL) }
      } catch { throw GarminStoreError.saveFailed }
      return result
    } catch {
      context.rollback()
      throw error
    }
  }
}

/// Unlike the default model executor, every job has an explicit physical background dispatch.
/// Context/model access is confined to its owning actor, whose executor is this serial queue.
nonisolated private final class StoreSerialModelExecutor: SerialModelExecutor, @unchecked Sendable {
  let modelContext: ModelContext
  private let queue: DispatchQueue

  init(container: ModelContainer, label: String) {
    precondition(!Thread.isMainThread)
    modelContext = ModelContext(container)
    modelContext.autosaveEnabled = false
    queue = DispatchQueue(label: label, qos: .userInitiated)
  }

  func enqueue(_ job: consuming ExecutorJob) {
    let job = UnownedJob(job)
    let executor = asUnownedSerialExecutor()
    queue.async {
      precondition(!Thread.isMainThread)
      job.runSynchronously(on: executor)
    }
  }

  func asUnownedSerialExecutor() -> UnownedSerialExecutor { UnownedSerialExecutor(ordinary: self) }

  func checkIsolated() { dispatchPrecondition(condition: .onQueue(queue)) }
}

extension GarminStore {
  /// Keys Garmin keeps on a night without recorded sleep, plus the night's date,
  /// `nextSleepNeed`, the forecast need for the following night, and `sleepAlignment`, the
  /// preferred tracker's circadian alignment status. Neither is a measurement of this night.
  /// Any other non-null key, even one the model does not decode, could be a measurement and
  /// keeps the member non-empty.
  private nonisolated static let emptyNightKeys: Set<String> = [
    "ageGroup", "calendarDate", "deviceRemCapable", "nextSleepNeed", "retro", "sleepAlignment",
    "sleepFromDevice", "sleepVersion", "sleepWindowConfirmationType", "sleepWindowConfirmed",
    "spo2Threshold", "userProfilePK",
  ]

  /// Whether each sleep member that decodes is an empty night, judged from its raw JSON so keys
  /// the model drops still count. Aligned with the decoded members; empty for other families.
  fileprivate nonisolated static func emptyNights(_ data: Data, family: GarminPayload.Family)
    throws -> [Bool]
  {
    func isEmpty(_ member: JSONValue) -> Bool {
      guard case .object(let fields) = member else { return false }
      return fields.allSatisfy { key, value in value == .null || emptyNightKeys.contains(key) }
    }
    switch family {
    case .sleep:
      guard let json = try? JSONDecoder().decode(JSONValue.self, from: data) else { return [] }
      return [isEmpty(json)]
    case .sleepSummaries:
      guard case .array(let members) = try? JSONDecoder().decode(JSONValue.self, from: data)
      else { return [] }
      return try GarminPayload.decodeMembers(members, as: Bool.self) { bytes in
        _ = try JSONDecoder().decode(SleepDTO.self, from: bytes)
        return isEmpty(try JSONDecoder().decode(JSONValue.self, from: bytes))
      }.values
    default: return []
    }
  }

  #if DEBUG
    /// The raw JSON of each sleep member that decodes, aligned like `emptyNights`; empty for
    /// other families. Local diagnostics read only its field names.
    fileprivate nonisolated static func sleepMembers(_ data: Data, family: GarminPayload.Family)
      throws -> [JSONValue]
    {
      switch family {
      case .sleep:
        guard let json = try? JSONDecoder().decode(JSONValue.self, from: data) else { return [] }
        return [json]
      case .sleepSummaries:
        guard case .array(let members) = try? JSONDecoder().decode(JSONValue.self, from: data)
        else { return [] }
        return try GarminPayload.decodeMembers(members, as: JSONValue.self) { bytes in
          _ = try JSONDecoder().decode(SleepDTO.self, from: bytes)
          return try JSONDecoder().decode(JSONValue.self, from: bytes)
        }.values
      default: return []
      }
    }
  #endif
}
