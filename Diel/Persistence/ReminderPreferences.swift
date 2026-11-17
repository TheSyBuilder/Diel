import Foundation
import SwiftData

@Model nonisolated final class ReminderPreferences {
  @Attribute(.unique) var identity: String
  var enabled: Bool
  var firstMinute: Int
  var missedMinute: Int

  init(_ value: ReminderPreferencesSnapshot) {
    identity = "morning"
    enabled = value.enabled
    firstMinute = value.firstMinute
    missedMinute = value.missedMinute
  }
}

nonisolated struct ReminderPreferencesSnapshot: Equatable, Sendable {
  var enabled: Bool
  var firstMinute: Int
  var missedMinute: Int
  static let defaults = Self(enabled: false, firstMinute: 8 * 60, missedMinute: 10 * 60 + 30)
  var isValid: Bool { (0..<1440).contains(firstMinute) && (0..<1440).contains(missedMinute) }
  var missedIsLater: Bool {
    Self.offset(missedMinute) > Self.offset(firstMinute)
  }
  private static func offset(_ minute: Int) -> Int { (minute - 4 * 60 + 1440) % 1440 }
}

nonisolated enum ReminderError: Error, Equatable {
  case invalidPreferences, unavailable, permissionDenied
}

nonisolated protocol ReminderStoring: Sendable {
  func reminderPreferences() async throws -> ReminderPreferencesSnapshot
  func saveReminderPreferences(_ value: ReminderPreferencesSnapshot) async throws
    -> ReminderPreferencesSnapshot
  func checkInHistory() async throws -> [CheckInSnapshot]
}
