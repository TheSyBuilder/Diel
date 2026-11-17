import Foundation
@preconcurrency import UserNotifications

nonisolated enum ReminderAuthorization: Sendable, Equatable { case notDetermined, denied, allowed }

nonisolated protocol ReminderNotifying: Sendable {
  func authorization() async -> ReminderAuthorization
  func requestAuthorization() async throws -> Bool
  func pending() async -> [MorningReminderRequest]
  func add(_ request: MorningReminderRequest) async throws
  func remove(_ identifiers: [String]) async
}

actor SystemReminderNotifications: ReminderNotifying {
  func authorization() async -> ReminderAuthorization {
    let settings = await UNUserNotificationCenter.current().notificationSettings()
    switch settings.authorizationStatus {
    case .authorized, .provisional, .ephemeral: return .allowed
    case .notDetermined: return .notDetermined
    default: return .denied
    }
  }
  func requestAuthorization() async throws -> Bool {
    try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
  }
  func pending() async -> [MorningReminderRequest] {
    await UNUserNotificationCenter.current().pendingNotificationRequests().compactMap { request in
      guard let parts = MorningReminderRequest.parse(request.identifier) else { return nil }
      let date =
        (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()
        ?? (request.trigger as? UNTimeIntervalNotificationTrigger)?.nextTriggerDate()
        ?? .distantPast
      return MorningReminderRequest(dayID: parts.dayID, kind: parts.kind, fireDate: date)
    }
  }
  func add(_ request: MorningReminderRequest) async throws {
    let content = UNMutableNotificationContent()
    content.body = request.kind.message
    content.sound = .default
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    var components = calendar.dateComponents(
      [.year, .month, .day, .hour, .minute, .second], from: request.fireDate)
    components.calendar = calendar
    components.timeZone = calendar.timeZone
    let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
    try await UNUserNotificationCenter.current().add(
      UNNotificationRequest(identifier: request.identifier, content: content, trigger: trigger))
  }
  func remove(_ identifiers: [String]) {
    UNUserNotificationCenter.current().removePendingNotificationRequests(
      withIdentifiers: identifiers)
  }
}

/// Ordinary sample screens and unit-test hosts never touch the real notification center.
nonisolated struct DisabledReminderNotifications: ReminderNotifying {
  func authorization() async -> ReminderAuthorization { .denied }
  func requestAuthorization() async -> Bool { false }
  func pending() async -> [MorningReminderRequest] { [] }
  func add(_ request: MorningReminderRequest) async throws { throw ReminderError.unavailable }
  func remove(_ identifiers: [String]) async {}
}
