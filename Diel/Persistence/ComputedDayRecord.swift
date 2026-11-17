import Foundation
import SwiftData

/// One atomic versioned bundle includes all controls, inputs, evidence and source identities.
@Model nonisolated final class ComputedDayRecord {
  #Index<ComputedDayRecord>([\.revisionID, \.calendarDate])
  @Attribute(.unique) var identity: String
  var revisionID: UUID
  var calendarDate: String
  var version: String
  var computedAt: Date
  var encodedScores: Data

  init(revisionID: UUID, calendarDate: String, version: String, at date: Date, bytes: Data) {
    identity = "\(revisionID.uuidString)|\(calendarDate)|\(version)"
    self.revisionID = revisionID
    self.calendarDate = calendarDate
    self.version = version
    computedAt = date
    encodedScores = bytes
  }
}
