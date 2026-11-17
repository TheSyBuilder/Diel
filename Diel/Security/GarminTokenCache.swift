import Foundation
import Security

nonisolated protocol GarminTokenCaching: Sendable {
  func read() async throws -> GarminAccessToken?
  func save(_ token: GarminAccessToken) async throws
  func remove(id: UUID?) async throws
}

actor MemoryGarminTokenCache: GarminTokenCaching {
  private var token: GarminAccessToken?
  func read() -> GarminAccessToken? { token }
  func save(_ token: GarminAccessToken) { self.token = token }
  func remove(id: UUID?) {
    if id == nil || token?.id == id { token = nil }
  }
}

/// This item is separate from the API key and never leaves this device's Keychain.
actor KeychainGarminTokenCache: GarminTokenCaching {
  static let account = "garmin-access-token"
  private let service: String

  init(service: String = "app.diel.garmin-personal-api") { self.service = service }

  private var query: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: Self.account,
      kSecAttrSynchronizable as String: false,
    ]
  }

  func read() throws -> GarminAccessToken? {
    var request = query
    request[kSecReturnData as String] = true
    request[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(request as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    try check(status)
    guard let data = result as? Data,
      let token = try? JSONDecoder().decode(GarminAccessToken.self, from: data)
    else { throw CredentialStoreError.invalidData }
    return token
  }

  func save(_ token: GarminAccessToken) throws {
    let attributes: [String: Any] = [
      kSecValueData as String: try JSONEncoder().encode(token),
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
      kSecAttrSynchronizable as String: false,
    ]
    let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    if status == errSecItemNotFound {
      try check(SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil))
    } else {
      try check(status)
    }
  }

  func remove(id: UUID?) throws {
    if let id, try read()?.id != id { return }
    let status = SecItemDelete(query as CFDictionary)
    if status != errSecItemNotFound { try check(status) }
  }

  private func check(_ status: OSStatus) throws {
    if status == errSecInteractionNotAllowed || status == errSecNotAvailable {
      throw CredentialStoreError.locked
    }
    guard status == errSecSuccess else { throw CredentialStoreError.failure(status) }
  }
}
