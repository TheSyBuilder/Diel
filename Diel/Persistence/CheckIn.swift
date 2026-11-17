import Foundation
import SwiftData

/// Personal answers are independent of every Garmin credential scope.
@Model nonisolated final class CheckIn {
  @Attribute(.unique) var dayID: String
  var rating: Int?
  var skipped: Bool
  var recordedAt: Date

  init(dayID: String, rating: Int?, skipped: Bool, recordedAt: Date) {
    self.dayID = dayID
    self.rating = rating
    self.skipped = skipped
    self.recordedAt = recordedAt
  }
}

nonisolated struct CheckInSnapshot: Equatable, Sendable {
  let dayID: String
  let rating: Int?
  let skipped: Bool
  let recordedAt: Date
}

nonisolated enum CheckInError: Error, Equatable { case invalidAnswer, unavailableStore }

nonisolated protocol CheckInStoring: Sendable {
  func checkIn(for dayID: String) async throws -> CheckInSnapshot?
  func checkInHistory() async throws -> [CheckInSnapshot]
  func saveCheckIn(dayID: String, rating: Int?, skipped: Bool, at date: Date) async throws
    -> CheckInSnapshot
}
