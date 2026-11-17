import Foundation
import Security

actor KeychainCredentialStore: CredentialStore {
  private let service: String
  private let account = "garmin-personal-api-key"

  init(service: String = "app.diel.garmin-personal-api") {
    self.service = service
  }

  private var query: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecAttrSynchronizable as String: false,
    ]
  }

  func read() throws -> StoredCredential? {
    var request = query
    request[kSecReturnAttributes as String] = true
    request[kSecReturnData as String] = true
    request[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(request as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    try check(status)
    guard let item = result as? [String: Any],
      let key = item[kSecValueData as String] as? Data,
      let metadata = item[kSecAttrGeneric as String] as? Data,
      let revision = try? JSONDecoder().decode(CredentialRevision.self, from: metadata)
    else { throw CredentialStoreError.invalidData }
    return StoredCredential(revision: revision, key: key)
  }

  @discardableResult func save(_ key: Data) throws -> CredentialRevision {
    guard !key.isEmpty else { throw CredentialStoreError.invalidData }
    try clearToken()
    let revision = CredentialRevision()
    let attributes: [String: Any] = [
      kSecValueData as String: key,
      kSecAttrGeneric as String: try JSONEncoder().encode(revision),
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
      kSecAttrSynchronizable as String: false,
    ]
    let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    if status == errSecItemNotFound {
      try check(SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil))
    } else {
      try check(status)
    }
    return revision
  }

  func remove() throws {
    try clearToken()
    let status = SecItemDelete(query as CFDictionary)
    if status != errSecItemNotFound { try check(status) }
  }

  private func clearToken() throws {
    var tokenQuery = query
    tokenQuery[kSecAttrAccount as String] = KeychainGarminTokenCache.account
    let status = SecItemDelete(tokenQuery as CFDictionary)
    if status != errSecItemNotFound { try check(status) }
  }

  private func check(_ status: OSStatus) throws {
    if status == errSecInteractionNotAllowed || status == errSecNotAvailable {
      throw CredentialStoreError.locked
    }
    guard status == errSecSuccess else { throw CredentialStoreError.failure(status) }
  }
}
