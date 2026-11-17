import Foundation

nonisolated struct GarminAccessToken: Sendable, Codable {
  let value: String
  let expiresAt: Date
  let revision: CredentialRevision
  let id: UUID

  init(value: String, expiresAt: Date, revision: CredentialRevision, id: UUID = UUID()) {
    self.value = value
    self.expiresAt = expiresAt
    self.revision = revision
    self.id = id
  }
}

/// Typed exchange boundary lets tests cover caching without inventing a JWT response fixture.
nonisolated protocol GarminTokenExchanging: Sendable {
  func exchange(_ credential: StoredCredential, deadline: Date) async throws -> GarminAccessToken
}

nonisolated protocol GarminTokenProviding: Sendable {
  func token(deadline: Date) async throws -> GarminAccessToken
  func reject(_ token: GarminAccessToken) async
  func validate(_ revision: CredentialRevision) async throws
  func invalidate() async
}

nonisolated struct GarminTokenExchange: GarminTokenExchanging {
  let scheduler: GarminRequestScheduler
  let timing: GarminTiming

  init(scheduler: GarminRequestScheduler, timing: GarminTiming = .continuous) {
    self.scheduler = scheduler
    self.timing = timing
  }

  func exchange(_ credential: StoredCredential, deadline: Date) async throws -> GarminAccessToken {
    var stage = SyncFailure.Stage.request
    var status: Int?
    do {
      guard let key = String(data: credential.key, encoding: .utf8), !key.isEmpty,
        !key.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
      else { throw GarminError.invalidCredential }
      var request = URLRequest(
        url: GarminOrigin.url.appending(
          path: "personalapitoken-service/personal-api/personal-api-key/token"))
      request.httpMethod = "POST"
      request.setValue("ApiKey \(key)", forHTTPHeaderField: "Authorization")
      request.setValue("*/*", forHTTPHeaderField: "Accept")
      let response = try await scheduler.send(request, operation: .token, deadline: deadline)
      status = response.status
      guard (200...299).contains(response.status) else {
        throw GarminError.httpStatus(response.status)
      }
      stage = .decode
      return try Self.parse(response.data, revision: credential.revision, now: timing.now())
    } catch {
      throw try SyncFailure.context(error, step: .tokenExchange, stage: stage, httpStatus: status)
    }
  }

  static func parse(_ data: Data, revision: CredentialRevision, now: Date) throws
    -> GarminAccessToken
  {
    guard
      let text = String(data: data, encoding: .utf8)?.trimmingCharacters(
        in: .whitespacesAndNewlines),
      !text.isEmpty
    else { throw GarminError.invalidTokenResponse }
    let parts = text.split(separator: ".", omittingEmptySubsequences: false)
    let allowed = CharacterSet(
      charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
    guard parts.count == 3,
      parts.allSatisfy({ !$0.isEmpty && $0.unicodeScalars.allSatisfy { allowed.contains($0) } })
    else { throw GarminError.invalidTokenResponse }
    var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(
      of: "_", with: "/")
    payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
    struct Claims: Decodable { let exp: Double }
    guard let bytes = Data(base64Encoded: payload),
      let claims = try? JSONDecoder().decode(Claims.self, from: bytes), claims.exp.isFinite,
      claims.exp > now.timeIntervalSince1970
    else { throw GarminError.invalidTokenResponse }
    return GarminAccessToken(
      value: text, expiresAt: Date(timeIntervalSince1970: claims.exp), revision: revision)
  }
}

actor GarminAuthenticator: GarminTokenProviding {
  private struct Pending {
    let id: UUID
    let revision: CredentialRevision
    let task: Task<GarminAccessToken, any Error>
  }

  private let credentials: any CredentialStore
  private let exchange: any GarminTokenExchanging
  private let timing: GarminTiming
  private let tokenCache: any GarminTokenCaching
  private var rejectedIDs: Set<UUID> = []
  private var cached: GarminAccessToken?
  private var pending: Pending?
  private var generation = UUID()

  init(
    credentials: any CredentialStore, exchange: any GarminTokenExchanging,
    timing: GarminTiming = .continuous,
    tokenCache: any GarminTokenCaching = MemoryGarminTokenCache()
  ) {
    self.credentials = credentials
    self.exchange = exchange
    self.timing = timing
    self.tokenCache = tokenCache
  }

  func token(deadline: Date) async throws -> GarminAccessToken {
    do { return try await obtainToken(deadline: deadline) } catch {
      throw try SyncFailure.context(error, step: .credentials, stage: .setup)
    }
  }

  private func obtainToken(deadline: Date) async throws -> GarminAccessToken {
    try Task.checkCancellation()
    let started = generation
    guard let credential = try await credentials.read() else {
      await invalidate()
      throw GarminError.noCredential
    }
    guard generation == started else { throw GarminError.credentialChanged }
    if let cached, cached.revision == credential.revision,
      !rejectedIDs.contains(cached.id),
      cached.expiresAt > timing.now().addingTimeInterval(60 * 60)
    {
      return cached
    }
    if cached == nil {
      let saved = try await tokenCache.read()
      guard generation == started else { throw GarminError.credentialChanged }
      if let saved, saved.revision == credential.revision, !rejectedIDs.contains(saved.id),
        saved.expiresAt > timing.now().addingTimeInterval(60 * 60)
      {
        try await validate(credential.revision)
        guard generation == started, !rejectedIDs.contains(saved.id) else {
          throw GarminError.credentialChanged
        }
        cached = saved
        return saved
      }
      if let saved { try await tokenCache.remove(id: saved.id) }
    }
    if pending?.revision != credential.revision {
      pending?.task.cancel()
      pending = nil
      cached = nil
    }
    let work: Pending
    if let pending {
      work = pending
    } else {
      let exchange = exchange
      let task = Task { try await exchange.exchange(credential, deadline: deadline) }
      work = Pending(id: UUID(), revision: credential.revision, task: task)
      pending = work
    }
    do {
      let token = try await TokenWaiter().value(of: work.task)
      try Task.checkCancellation()
      guard generation == started, token.revision == credential.revision else {
        throw GarminError.credentialChanged
      }
      try await validate(credential.revision)
      guard generation == started, !rejectedIDs.contains(token.id) else {
        throw GarminError.credentialChanged
      }
      guard token.expiresAt > timing.now().addingTimeInterval(60 * 60) else {
        throw SyncFailure(
          step: .tokenExchange, stage: .decode, httpStatus: nil, reason: .invalidResponse)
      }
      // Another waiter can have accepted this task already. A newer task must never be overwritten.
      if pending?.id == work.id {
        try await tokenCache.save(token)
        guard generation == started, !rejectedIDs.contains(token.id) else {
          try await tokenCache.remove(id: token.id)
          throw GarminError.credentialChanged
        }
        cached = token
        pending = nil
      }
      guard !rejectedIDs.contains(token.id) else { throw GarminError.credentialChanged }
      guard token.expiresAt > timing.now() else {
        throw SyncFailure(
          step: .tokenExchange, stage: .decode, httpStatus: nil, reason: .invalidResponse)
      }
      return token
    } catch {
      if !(error is CancellationError), pending?.id == work.id { pending = nil }
      try Task.checkCancellation()
      guard generation == started else { throw GarminError.credentialChanged }
      try await validate(credential.revision)
      guard generation == started else { throw GarminError.credentialChanged }
      throw error
    }
  }

  func validate(_ revision: CredentialRevision) async throws {
    do {
      guard let current = try await credentials.read(), current.revision == revision else {
        throw GarminError.credentialChanged
      }
    } catch {
      throw try SyncFailure.context(error, step: .credentials, stage: .setup)
    }
  }

  func reject(_ token: GarminAccessToken) async {
    rejectedIDs.insert(token.id)
    if cached?.id == token.id { cached = nil }
    try? await tokenCache.remove(id: token.id)
  }

  /// Settings must call immediately after saving/removing a key, also cancelling the active sync.
  func invalidate() async {
    generation = UUID()
    cached = nil
    pending?.task.cancel()
    pending = nil
    try? await tokenCache.remove(id: nil)
  }
}

/// Cancelling one caller must not cancel a shared exchange needed by another caller.
private actor TokenWaiter {
  private var continuation: CheckedContinuation<GarminAccessToken, any Error>?
  private var cancelled = false

  func value(of task: Task<GarminAccessToken, any Error>) async throws -> GarminAccessToken {
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        if cancelled || Task.isCancelled {
          continuation.resume(throwing: CancellationError())
        } else {
          self.continuation = continuation
          Task { self.finish(await task.result) }
        }
      }
    } onCancel: {
      Task { await self.cancel() }
    }
  }

  private func finish(_ result: Result<GarminAccessToken, any Error>) {
    continuation?.resume(with: result)
    continuation = nil
  }

  private func cancel() {
    cancelled = true
    continuation?.resume(throwing: CancellationError())
    continuation = nil
  }
}
