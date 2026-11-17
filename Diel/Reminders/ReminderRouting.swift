import Foundation
import Observation
@preconcurrency import UserNotifications

@Observable
@MainActor
final class ReminderRouter {
  private(set) var sequence = 0
  private var consumedSequence = 0
  func route(identifier: String) {
    guard MorningReminderRequest.parse(identifier) != nil else { return }
    sequence += 1
  }

  func consumePendingRoute() -> Bool {
    guard sequence > consumedSequence else { return false }
    consumedSequence = sequence
    return true
  }
}

nonisolated final class ReminderNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
  private let router: ReminderRouter
  init(router: ReminderRouter) { self.router = router }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    // Only Sendable strings leave the native callback; no notification object crosses actor hops.
    let identifier = response.notification.request.identifier
    let action = response.actionIdentifier
    let router = router
    if action == UNNotificationDefaultActionIdentifier,
      MorningReminderRequest.parse(identifier) != nil
    {
      Task { @MainActor in router.route(identifier: identifier) }
    }
    completionHandler()
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler(
      MorningReminderRequest.parse(notification.request.identifier) != nil
        ? [.banner, .list, .sound] : [])
  }
}

@MainActor
struct ReminderServices {
  private(set) var model: ReminderModel
  let router: ReminderRouter
  private let delegate: ReminderNotificationDelegate
  private var systemEnabled: Bool
  private(set) var isReady: Bool

  init(
    store: GarminStore?, systemEnabled: Bool, verificationEnabled: Bool = false, ready: Bool = true
  ) {
    let center: any ReminderNotifying =
      systemEnabled ? SystemReminderNotifications() : DisabledReminderNotifications()
    model = ReminderModel(store: store, center: center, verificationEnabled: verificationEnabled)
    router = ReminderRouter()
    delegate = ReminderNotificationDelegate(router: router)
    self.systemEnabled = systemEnabled
    isReady = ready
  }

  /// Keep the launch delegate/router alive while the store opens, including pending tap routes.
  mutating func connect(
    store: GarminStore?, systemEnabled: Bool, verificationEnabled: Bool = false
  ) {
    let center: any ReminderNotifying =
      systemEnabled ? SystemReminderNotifications() : DisabledReminderNotifications()
    model = ReminderModel(store: store, center: center, verificationEnabled: verificationEnabled)
    self.systemEnabled = systemEnabled
    isReady = true
  }

  func consumePendingRoute() -> Bool { isReady && router.consumePendingRoute() }

  func registerDelegate() {
    guard systemEnabled else { return }
    let center = UNUserNotificationCenter.current()
    guard center.delegate !== delegate else { return }
    center.delegate = delegate
  }

  func bind(to checkIn: MorningCheckInCoordinator) {
    checkIn.onSaved = { [weak model] answer in
      Task { await model?.checkInCompleted(answer) }
    }
  }
}
