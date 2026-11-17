import Foundation
import Observation

@Observable
@MainActor
final class AppDependencies {
  private(set) var settings: SettingsModel
  private(set) var sync: SyncCoordinator?
  private(set) var store: GarminStore?
  private(set) var morningCheckIn: MorningCheckInCoordinator
  private(set) var morningBrief: MorningBriefCoordinator
  private(set) var morningBriefSync: MorningBriefSyncGate
  private(set) var reminders: ReminderServices
  var scoring: ScoringService? { sync?.scoring }
  private(set) var startupError: LocalizedStringResource?
  private var started = false
  @ObservationIgnored private var configuration: Task<Void, Never>?
  @ObservationIgnored private var background: BackgroundSyncScheduler?
  var backgroundScheduler: BackgroundSyncScheduler {
    if let background { return background }
    let enabled: Bool
    #if targetEnvironment(simulator)
      enabled = false
    #elseif DEBUG
      enabled = !isSample
    #else
      enabled = true
    #endif
    let scheduler = BackgroundSyncScheduler(
      sync: sync, enabled: enabled,
      prepare: { [weak self] in
        await self?.initialize()
        return self?.sync
      })
    background = scheduler
    return scheduler
  }
  #if DEBUG
    private(set) var isSample = false
    private(set) var sampleDayCount = 0
    private(set) var sampleReferenceDate: Date?
    private(set) var sampleRevision: CredentialRevision?
    private var settingsVerification: SettingsVerificationDependencies?

    static var isUnitTestHost: Bool {
      ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        || ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil
        || NSClassFromString("XCTestCase") != nil
    }
  #endif

  init() {
    #if DEBUG
      let sample =
        Self.isUnitTestHost
        || ProcessInfo.processInfo.arguments.contains("--offline-verification")
        || ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
      isSample = sample
    #endif
    settings = SettingsModel(
      credentials: SampleStartupCredentials(), sync: nil, credentialsEnabled: false)
    store = nil
    sync = nil
    morningCheckIn = MorningCheckInCoordinator(store: nil)
    morningBriefSync = MorningBriefSyncGate(attempt: {})
    morningBrief = MorningBriefCoordinator(store: nil, generator: TemplateBriefGenerator())
    #if DEBUG
      let systemReminders =
        !sample
        || ProcessInfo.processInfo.arguments.contains("--reminder-notification-verification")
    #else
      let systemReminders = true
    #endif
    reminders = ReminderServices(store: nil, systemEnabled: systemReminders, ready: false)
  }

  private func configure() async {
    #if DEBUG
      isSample =
        Self.isUnitTestHost
        || ProcessInfo.processInfo.arguments.contains("--offline-verification")
        || ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
      if isSample {
        if ProcessInfo.processInfo.arguments.contains("--offline-verification"),
          ProcessInfo.processInfo.arguments.contains("--settings-verification")
        {
          let sampleStore = await Task.detached { try? GarminStore.inMemory() }.value
          let verification = SettingsVerificationDependencies(store: sampleStore)
          settingsVerification = verification
          store = verification.store
          sync = verification.sync
          settings = verification.settings
          morningCheckIn = MorningCheckInCoordinator(
            store: verification.store,
            bypass: ProcessInfo.processInfo.arguments.contains("--skip-check-in"))
          morningBriefSync = MorningBriefSyncGate(attempt: {})
          morningBrief = MorningBriefCoordinator(
            store: verification.store, generator: BriefGeneratorFactory.make(offline: true))
          reminders.connect(store: verification.store, systemEnabled: false)
          reminders.bind(to: morningCheckIn)
          if store == nil { startupError = "Sample data could not be loaded." }
          return
        }
        let credentials = SampleCredentials()
        let scheduler = GarminRequestScheduler(transport: OfflineTransport())
        let auth = GarminAuthenticator(
          credentials: credentials, exchange: GarminTokenExchange(scheduler: scheduler))
        let sampleStore: GarminStore?
        if ProcessInfo.processInfo.arguments.contains("--offline-persistence-seed")
          || ProcessInfo.processInfo.arguments.contains("--offline-persistence-reopen")
        {
          sampleStore = await Task.detached { try? OfflinePersistenceVerification.open() }.value
        } else {
          sampleStore = await Task.detached { try? GarminStore.inMemory() }.value
        }
        store = sampleStore
        morningCheckIn = MorningCheckInCoordinator(
          store: sampleStore, bypass: ProcessInfo.processInfo.arguments.contains("--skip-check-in"))
        sync = sampleStore.map {
          SyncCoordinator(
            credentials: credentials, client: GarminClient(tokens: auth, scheduler: scheduler),
            store: $0, authenticator: auth)
        }
        settings = SettingsModel(credentials: credentials, sync: sync, credentialsEnabled: false)
        morningBriefSync = MorningBriefSyncGate(attempt: {})
        morningBrief = MorningBriefCoordinator(
          store: sampleStore, generator: BriefGeneratorFactory.make(offline: true))
        let reminderVerification =
          ProcessInfo.processInfo.arguments.contains("--offline-verification")
          && ProcessInfo.processInfo.arguments.contains("--reminder-notification-verification")
        reminders.connect(
          store: sampleStore, systemEnabled: reminderVerification,
          verificationEnabled: reminderVerification)
        reminders.bind(to: morningCheckIn)
        if sampleStore == nil { startupError = "Sample data could not be loaded." }
        return
      }
    #endif
    let credentials = KeychainCredentialStore()
    let scheduler = GarminRequestScheduler()
    let authenticator = GarminAuthenticator(
      credentials: credentials, exchange: GarminTokenExchange(scheduler: scheduler),
      tokenCache: KeychainGarminTokenCache())
    let persistentStore = await Task.detached { try? GarminStore.persistent() }.value
    store = persistentStore
    morningCheckIn = MorningCheckInCoordinator(store: persistentStore)
    sync = persistentStore.map {
      SyncCoordinator(
        credentials: credentials,
        client: GarminClient(tokens: authenticator, scheduler: scheduler),
        store: $0, authenticator: authenticator)
    }
    settings = SettingsModel(credentials: credentials, sync: sync)
    morningBriefSync = MorningBriefSyncGate { [sync] in await sync?.syncToday(manual: false) }
    morningBrief = MorningBriefCoordinator(
      store: persistentStore, generator: BriefGeneratorFactory.make(offline: false))
    reminders.connect(store: persistentStore, systemEnabled: true)
    reminders.bind(to: morningCheckIn)
    if persistentStore == nil { startupError = "Saved data could not be opened." }
  }

  private func initialize() async {
    if let configuration {
      await configuration.value
      return
    }
    let task = Task {
      await configure()
      background?.connect(sync)
      reminders.registerDelegate()
    }
    configuration = task
    await task.value
  }

  func start() async {
    await initialize()
    guard !started else { return }
    started = true
    let launchDay = MorningDay(containing: Date())
    defer {
      morningBriefSync.finishLaunch(for: launchDay)
    }
    await reminders.model.refresh()
    await morningCheckIn.evaluate()
    #if DEBUG
      if isSample {
        guard let store else { return }
        do {
          let reopening = ProcessInfo.processInfo.arguments.contains("--offline-persistence-reopen")
          let loaded =
            try await Task.detached {
              try await reopening
                ? OfflinePersistenceVerification.reopen(store)
                : FixtureDataProvider.load(into: store)
            }.value
          sampleDayCount = loaded.dayCount
          sampleReferenceDate = loaded.referenceDate
          sampleRevision = loaded.revision
          let plan = try await SyncPlan.make(now: loaded.referenceDate, initial: true)
          if reopening {
            await scoring?.bootstrap(
              in: plan.start...plan.end, revision: loaded.revision,
              now: loaded.referenceDate, calendar: .current)
          } else {
            await scoring?.refresh(
              in: plan.start...plan.end, revision: loaded.revision,
              now: loaded.referenceDate, calendar: .current)
          }
          try await settingsVerification?.start(revision: loaded.revision)
        } catch { startupError = "Sample data could not be loaded." }
        return
      }
    #endif
    await sync?.launch()
    await backgroundScheduler.schedule()
  }

  func sceneChanged(active: Bool, background: Bool) async {
    await initialize()
    if active { await morningCheckIn.evaluate() }
    #if DEBUG
      guard !isSample else { return }
    #endif
    await sync?.setForegroundActive(active)
    if active {
      await morningBriefSync.settle(MorningDay(containing: Date()))
      await sync?.waitForCurrentSync()
    }
    if background { await backgroundScheduler.schedule() }
  }
}

/// The initial loading shell never discovers credentials or opens a store.
private actor SampleStartupCredentials: CredentialStore {
  func read() -> StoredCredential? { nil }
  func save(_ key: Data) throws -> CredentialRevision { throw CredentialStoreError.invalidData }
  func remove() throws { throw CredentialStoreError.invalidData }
}
