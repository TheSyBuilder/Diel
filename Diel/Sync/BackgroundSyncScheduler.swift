import BackgroundTasks
import Foundation
import UIKit

nonisolated enum BackgroundSyncRequest: Sendable, Equatable {
  case refresh(Date)
  case overnight(Date)

  var earliest: Date {
    switch self {
    case .refresh(let date), .overnight(let date): date
    }
  }
}

nonisolated protocol BackgroundSyncSubmitting: Sendable {
  func submit(_ request: BackgroundSyncRequest) async throws
}

nonisolated struct SystemBackgroundSyncSubmitter: BackgroundSyncSubmitting {
  @concurrent
  func submit(_ request: BackgroundSyncRequest) async throws {
    switch request {
    case .refresh(let date):
      let task = BGAppRefreshTaskRequest(identifier: BackgroundSyncScheduler.refreshIdentifier)
      task.earliestBeginDate = date
      try await BGTaskScheduler.shared.submitTaskRequest(task)
    case .overnight(let date):
      let task = BGProcessingTaskRequest(identifier: BackgroundSyncScheduler.overnightIdentifier)
      task.earliestBeginDate = date
      task.requiresExternalPower = true
      task.requiresNetworkConnectivity = true
      try await BGTaskScheduler.shared.submitTaskRequest(task)
    }
  }
}

@MainActor
final class BackgroundSyncScheduler {
  nonisolated static let refreshIdentifier = "com.TheSyBuilder.Diel.refresh"
  nonisolated static let overnightIdentifier = "com.TheSyBuilder.Diel.overnight"
  private var sync: SyncCoordinator?
  private let prepare: (@MainActor () async -> SyncCoordinator?)?
  private let enabled: Bool
  private let submitter: any BackgroundSyncSubmitting
  private let now: @Sendable () -> Date
  private let calendar: Calendar
  private var registered = false
  private var scheduling: Task<Void, Never>?

  init(
    sync: SyncCoordinator?, enabled: Bool,
    submitter: any BackgroundSyncSubmitting = SystemBackgroundSyncSubmitter(),
    now: @escaping @Sendable () -> Date = { Date() }, calendar: Calendar = .current,
    prepare: (@MainActor () async -> SyncCoordinator?)? = nil
  ) {
    self.sync = sync
    self.prepare = prepare
    self.enabled = enabled
    self.submitter = submitter
    self.now = now
    self.calendar = calendar
  }

  func connect(_ sync: SyncCoordinator?) { self.sync = sync }

  /// Called synchronously from didFinishLaunching, once for each permitted identifier.
  func register() {
    guard enabled, !registered else { return }
    registered = true
    BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.refreshIdentifier, using: .main) {
      [weak self] task in
      MainActor.assumeIsolated { self?.handle(task, fuller: false) }
    }
    BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.overnightIdentifier, using: .main) {
      [weak self] task in
      MainActor.assumeIsolated { self?.handle(task, fuller: true) }
    }
  }

  func schedule() async {
    guard enabled else {
      sync?.setAcceptedBackgroundCheck(nil)
      return
    }
    if let scheduling {
      await scheduling.value
      return
    }
    let task = Task {
      var accepted: [Date] = []
      let instant = now()
      let requests: [BackgroundSyncRequest] = [
        .refresh(instant.addingTimeInterval(30 * 60)),
        .overnight(Self.nextOvernight(after: instant, calendar: calendar)),
      ]
      for request in requests {
        do {
          try await submitter.submit(request)
          accepted.append(request.earliest)
        } catch {}
      }
      sync?.setAcceptedBackgroundCheck(accepted.min())
    }
    scheduling = task
    await task.value
    scheduling = nil
  }

  nonisolated static func nextOvernight(after date: Date, calendar: Calendar) -> Date {
    // A 02:00 local earliest time requests an overnight opportunity; iOS picks delivery.
    calendar.nextDate(
      after: date, matching: DateComponents(hour: 2), matchingPolicy: .nextTime) ?? date
  }

  private func handle(_ task: BGTask, fuller: Bool) {
    let execution = BackgroundSyncExecution(
      sync: sync, fuller: fuller, prepare: prepare,
      completed: { task.setTaskCompleted(success: $0) },
      reschedule: { [weak self] in await self?.schedule() })
    task.expirationHandler = { Task { @MainActor in execution.expire() } }
    execution.start()
  }
}

/// Owns cancellation and exactly-once completion independently of the native task object.
@MainActor
final class BackgroundSyncExecution {
  private var sync: SyncCoordinator?
  private let prepare: (@MainActor () async -> SyncCoordinator?)?
  private let fuller: Bool
  private let completed: (Bool) -> Void
  private let reschedule: () async -> Void
  private var work: Task<Void, Never>?
  private var lease: SyncCoordinator.BackgroundWork?
  private var finished = false

  init(
    sync: SyncCoordinator?, fuller: Bool,
    prepare: (@MainActor () async -> SyncCoordinator?)? = nil, completed: @escaping (Bool) -> Void,
    reschedule: @escaping () async -> Void
  ) {
    self.sync = sync
    self.prepare = prepare
    self.fuller = fuller
    self.completed = completed
    self.reschedule = reschedule
  }

  func start() {
    guard work == nil, !finished else { return }
    if let sync {
      run(sync)
    } else {
      work = Task {
        let ready = await prepare?()
        guard !finished, !Task.isCancelled else { return }
        guard let ready else {
          _ = finish(false)
          return
        }
        sync = ready
        run(ready)
      }
    }
  }

  private func run(_ sync: SyncCoordinator) {
    let lease = sync.backgroundWork(fuller: fuller)
    self.lease = lease
    work = Task {
      await lease.task.value
      if finish(!Task.isCancelled && sync.state == .completed && !sync.scoring.calculationFailed) {
        await reschedule()
      }
    }
  }

  func expire() {
    guard !finished else { return }
    work?.cancel()
    guard finish(false) else { return }
    Task {
      if let lease, let sync { await sync.cancelBackgroundWork(lease) }
      await reschedule()
    }
  }

  @discardableResult private func finish(_ success: Bool) -> Bool {
    guard !finished else { return false }
    finished = true
    completed(success)
    return true
  }
}

@MainActor
final class DielApplicationDelegate: NSObject, UIApplicationDelegate {
  static let dependencies = AppDependencies()

  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    Self.dependencies.reminders.registerDelegate()
    Self.dependencies.backgroundScheduler.register()
    return true
  }
}
