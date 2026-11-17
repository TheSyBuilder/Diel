import Foundation

nonisolated struct GarminResponse: Sendable {
  let endpoint: GarminEndpoint
  let revision: CredentialRevision
  let fetchedAt: Date
  let rawData: Data
  let payload: GarminPayload?
  let rejections: [GarminRecordRejection]
  let memberCount: Int?
  let httpStatus: Int?

  init(
    endpoint: GarminEndpoint, revision: CredentialRevision, fetchedAt: Date, rawData: Data,
    payload: GarminPayload?, httpStatus: Int? = nil,
    rejections: [GarminRecordRejection] = [], memberCount: Int? = nil
  ) {
    self.endpoint = endpoint
    self.revision = revision
    self.fetchedAt = fetchedAt
    self.rawData = rawData
    self.payload = payload
    self.httpStatus = httpStatus
    self.rejections = rejections
    self.memberCount = memberCount
  }
}

nonisolated protocol GarminFetching: Sendable {
  func fetch(_ endpoint: GarminEndpoint) async throws -> GarminResponse?
}

/// No initializer performs credential discovery or network access.
nonisolated struct GarminClient: GarminFetching {
  private let tokens: any GarminTokenProviding
  private let scheduler: GarminRequestScheduler
  private let timing: GarminTiming
  private let operationBudget: TimeInterval

  init(
    tokens: any GarminTokenProviding, scheduler: GarminRequestScheduler,
    timing: GarminTiming = .continuous, operationBudget: TimeInterval = 30
  ) {
    self.tokens = tokens
    self.scheduler = scheduler
    self.timing = timing
    self.operationBudget = operationBudget
  }

  /// On-demand opaque ZIP download. No extraction or automatic archive requests.
  func archive(activityID: Int64) async throws -> Data? {
    try await fetch(.archive(activityID))?.rawData
  }

  /// Nil means an empty successful response. Rejected records retain their bytes and metadata;
  /// unreadable batch envelopes and transport/authentication errors throw.
  @concurrent
  func fetch(_ endpoint: GarminEndpoint) async throws -> GarminResponse? {
    var stage = SyncFailure.Stage.request
    var status: Int?
    do {
      let base = try endpoint.request()
      let deadline = timing.now().addingTimeInterval(operationBudget)
      var token = try await tokens.token(deadline: deadline)
      for attempt in 0...1 {
        try Task.checkCancellation()
        try await tokens.validate(token.revision)
        status = nil
        var request = base
        request.setValue("Bearer \(token.value)", forHTTPHeaderField: "Authorization")
        let response = try await scheduler.send(
          request, operation: .data(endpoint.family), deadline: deadline)
        status = response.status
        try await tokens.validate(token.revision)
        if response.status == 401 {
          guard attempt == 0 else { throw GarminError.httpStatus(response.status) }
          await tokens.reject(token)
          let replacement = try await tokens.token(deadline: deadline)
          guard replacement.revision == token.revision else { throw GarminError.credentialChanged }
          token = replacement
          continue
        }
        guard (200...299).contains(response.status) else {
          throw GarminError.httpStatus(response.status)
        }
        if response.status == 204 || response.data.isEmpty { return nil }
        if endpoint.family != .archive,
          let text = String(data: response.data, encoding: .utf8)?.trimmingCharacters(
            in: .whitespacesAndNewlines),
          text.isEmpty || text == "null"
        {
          return nil
        }
        stage = .decode
        let report: GarminDecodeReport
        do { report = try GarminPayload.decodeRecords(response.data, as: endpoint.family) } catch {
          throw GarminError.decoding(endpoint.family)
        }
        try Task.checkCancellation()
        try await tokens.validate(token.revision)
        return GarminResponse(
          endpoint: endpoint, revision: token.revision, fetchedAt: timing.now(),
          rawData: response.data, payload: report.payload, httpStatus: response.status,
          rejections: report.rejections, memberCount: report.memberCount)
      }
      throw GarminError.unauthorized
    } catch {
      throw try SyncFailure.context(
        error, step: .endpoint(endpoint.family), stage: stage, httpStatus: status)
    }
  }
}
