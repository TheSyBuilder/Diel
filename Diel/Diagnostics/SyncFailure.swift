import Foundation

/// Closed metadata only: never carries request values, server text, or an underlying error.
nonisolated struct SyncFailure: Error, Sendable, Equatable {
  enum Step: Sendable, Equatable {
    case tokenExchange
    case endpoint(GarminPayload.Family)
    case credentials, store, sync

    var code: String {
      switch self {
      case .tokenExchange: "tokenExchange"
      case .endpoint(let family): family.rawValue
      case .credentials: "credentials"
      case .store: "store"
      case .sync: "sync"
      }
    }
  }

  enum Stage: String, Sendable { case request, decode, ingest, completion, setup }
  enum Reason: String, Sendable {
    case credentialUnavailable, credentialRejected, permissionDenied, unauthorized
    case invalidRequest, invalidResponse, transport, httpStatus, retryExhausted
    case skippedRecord, decoding, storeRead, storeWrite, incomplete, localFailure
  }

  let step: Step
  let stage: Stage
  let httpStatus: Int?
  let reason: Reason

  var isKeyRejected: Bool {
    step == .tokenExchange && stage == .request && (httpStatus == 401 || httpStatus == 403)
  }

  /// Safe for a DEBUG diagnostic label; every string comes from a closed enum or an HTTP status.
  var summary: String {
    "\(step.code) · \(stage.rawValue) · \(httpStatus.map { "HTTP \($0)" } ?? "no HTTP status") · \(reason.rawValue)"
  }

  static func context(
    _ error: any Error, step: Step, stage: Stage, httpStatus: Int? = nil
  ) throws -> Self {
    if error is CancellationError { throw CancellationError() }
    if let error = error as? GarminError, error == .credentialChanged { throw error }
    if let error = error as? GarminStoreError, error == .staleRevision { throw error }
    if let failure = error as? Self { return failure }
    var status = httpStatus
    let reason: Reason
    switch error {
    case GarminError.noCredential, GarminError.invalidCredential: reason = .credentialUnavailable
    case GarminError.invalidEndpoint: reason = .invalidRequest
    case GarminError.invalidTokenResponse: reason = .invalidResponse
    case GarminError.unauthorized: reason = .unauthorized
    case GarminError.httpStatus(let value):
      status = value
      reason =
        step == .tokenExchange && (value == 401 || value == 403)
        ? .credentialRejected : (value == 403 ? .permissionDenied : .httpStatus)
    case GarminError.retryExhausted(_, let value):
      status = value
      reason = .retryExhausted
    case GarminError.retryAfter: reason = .retryExhausted
    case GarminError.transport: reason = .transport
    case GarminError.decoding, GarminStoreError.decoding: reason = .decoding
    case GarminStoreError.readFailed: reason = .storeRead
    case GarminStoreError.saveFailed: reason = .storeWrite
    case GarminStoreError.invalidResponse: reason = .invalidResponse
    case GarminStoreError.incompleteSync: reason = .incomplete
    default: reason = .localFailure
    }
    return Self(step: step, stage: stage, httpStatus: status, reason: reason)
  }
}
