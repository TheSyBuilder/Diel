#if DEBUG
  import Foundation

  /// Isolated UI regression dependencies. No Keychain, token exchange or transport is created.
  @MainActor
  final class SettingsVerificationDependencies {
    let store: GarminStore?
    let sync: SyncCoordinator?
    let settings: SettingsModel
    private let credentials: SettingsVerificationCredentials

    init(store memoryStore: GarminStore?) {
      let credentials = SettingsVerificationCredentials()
      self.credentials = credentials
      store = memoryStore
      sync = memoryStore.map {
        SyncCoordinator(
          credentials: credentials, client: SettingsVerificationClient(credentials: credentials),
          store: $0,
          authenticator: SettingsVerificationAuthenticator())
      }
      settings = SettingsModel(credentials: credentials, sync: sync)
    }

    func start(revision: CredentialRevision) async throws {
      guard
        let url = Bundle.main.url(
          forResource: "activity-1000000001-workouts", withExtension: "json",
          subdirectory: "fixtures")
      else { throw GarminStoreError.openFailed }
      let bytes = try Data(contentsOf: url)
      await credentials.seed(bytes, revision: revision)
      try await sync?.selectCredential(revision)
      await sync?.sync()
      await sync?.setForegroundActive(true)
      settings.entry = String(data: bytes, encoding: .utf8) ?? ""
    }
  }

  private actor SettingsVerificationCredentials: CredentialStore {
    private var stored: StoredCredential?

    func seed(_ bytes: Data, revision: CredentialRevision) {
      stored = StoredCredential(revision: revision, key: bytes)
    }
    func read() -> StoredCredential? { stored }
    func save(_ key: Data) -> CredentialRevision {
      let revision = CredentialRevision()
      stored = StoredCredential(revision: revision, key: key)
      return revision
    }
    func remove() { stored = nil }
  }

  private nonisolated struct SettingsVerificationClient: GarminFetching {
    let credentials: SettingsVerificationCredentials

    func fetch(_ endpoint: GarminEndpoint) async throws -> GarminResponse? {
      let name: String
      let verifySleepSkip = ProcessInfo.processInfo.arguments.contains("--sleep-skip-verification")
      switch endpoint {
      case .sleepSummaries where verifySleepSkip: name = "sleep-summaries"
      case .heartRate where !verifySleepSkip: name = "activity-1000000001-workouts"
      default: return nil
      }
      guard let revision = await credentials.read()?.revision,
        let url = Bundle.main.url(
          forResource: name, withExtension: "json", subdirectory: "fixtures")
      else { throw GarminStoreError.openFailed }
      let bytes = try Data(contentsOf: url)
      let report = try GarminPayload.decodeRecords(bytes, as: endpoint.family)
      return GarminResponse(
        endpoint: endpoint, revision: revision, fetchedAt: Date(), rawData: bytes,
        payload: report.payload, httpStatus: 200, rejections: report.rejections,
        memberCount: report.memberCount)
    }
  }

  private nonisolated struct SettingsVerificationAuthenticator: GarminTokenProviding {
    func token(deadline: Date) async throws -> GarminAccessToken { throw GarminError.noCredential }
    func reject(_ token: GarminAccessToken) async {}
    func validate(_ revision: CredentialRevision) async throws {}
    func invalidate() async {}
  }
#endif
