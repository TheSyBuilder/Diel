import Foundation
import SwiftData

@Model nonisolated final class GarminSyncState {
  @Attribute(.unique) var identity: String
  var revisionID: UUID?
  var lastAttemptAt: Date?
  var lastCompleteSyncAt: Date?

  init(identity: String, revisionID: UUID?) {
    self.identity = identity
    self.revisionID = revisionID
  }
}

nonisolated struct GarminSyncStatus: Sendable {
  let revision: CredentialRevision
  let lastAttemptAt: Date?
  let lastCompleteSyncAt: Date?
}

nonisolated struct GarminSyncSession: Sendable, Hashable {
  let id: UUID
  let revision: CredentialRevision
}

nonisolated enum GarminStoreError: Error, Equatable {
  case openFailed
  case staleRevision
  case invalidResponse
  case decoding
  case encoding
  case readFailed
  case saveFailed
  case incompleteSync
  case unknownSync
}
