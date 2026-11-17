import Foundation

/// Non-secret, persistent identity for one saved credential revision.
nonisolated struct CredentialRevision: Codable, Sendable, Hashable {
  let id: UUID

  init(id: UUID = UUID()) { self.id = id }
}

/// Transient credential material; never persist outside the Keychain or send to diagnostics.
nonisolated struct StoredCredential: Sendable {
  let revision: CredentialRevision
  let key: Data
}

nonisolated enum CredentialStoreError: Error, Equatable {
  case locked
  case failure(Int32)
  case invalidData
}

nonisolated protocol CredentialStore: Sendable {
  func read() async throws -> StoredCredential?
  @discardableResult func save(_ key: Data) async throws -> CredentialRevision
  func remove() async throws
}
