import Foundation
import SwiftData

/// A pending reservation prevents another real-model call after a failed result write or restart.
@Model nonisolated final class BriefRecord {
  @Attribute(.unique) var identity: String
  var dayID: String
  var scopeID: String
  var scoreFingerprint: String
  var reservationID: UUID
  var encodedInput: Data
  var encodedBrief: Data?
  /// Reservation start time. Completion leaves it unchanged for the durable cooldown.
  var generatedAt: Date

  init(context: BriefCacheContext, reservationID: UUID, input: Data, at date: Date) {
    identity = context.identity
    dayID = context.dayID
    scopeID = context.scopeID
    scoreFingerprint = context.scoreFingerprint
    self.reservationID = reservationID
    encodedInput = input
    generatedAt = date
  }
}

/// Cache routing metadata stays outside BriefInput and is never sent to a generator.
nonisolated struct BriefCacheContext: Equatable, Hashable, Sendable {
  let dayID: String
  let scopeID: String
  let scoreFingerprint: String
  var identity: String { "\(dayID)|\(scopeID)|\(scoreFingerprint)" }
}

/// The latest completed brief of a day and scope, shown on cold launch before sync settles.
nonisolated struct StoredBrief: Equatable, Sendable {
  let context: BriefCacheContext
  let brief: Brief
}

nonisolated enum BriefReservation: Sendable {
  case acquired(UUID)
  case completed(Brief)
  case pending(BriefInput)
  case deferred(until: Date, previous: Brief?, currentReservation: UUID?)
}

nonisolated enum BriefError: Error, Equatable { case invalidOutput, invalidReservation }

nonisolated protocol BriefCaching: Sendable {
  func reserveBrief(context: BriefCacheContext, input: BriefInput, at date: Date) async throws
    -> BriefReservation
  func finishBrief(_ brief: Brief, context: BriefCacheContext, reservation: UUID, at date: Date)
    async throws
  /// Read-only. Never reserves, so it cannot start or defer a generation.
  func latestCompletedBrief(dayID: String, scopeID: String) async throws -> StoredBrief?
}
