import Foundation
import SwiftData

@Model nonisolated final class GarminActivityRecord {
  @Attribute(.unique) var identity: String
  var revisionID: UUID
  var activityID: Int64
  var calendarDate: String?
  var summaryData: Data?
  var detailData: Data?
  var workoutsData: Data?
  var summaryResponseID: UUID?
  var detailResponseID: UUID?
  var workoutsResponseID: UUID?
  var archiveResponseID: UUID?
  var summaryFetchedAt: Date?
  var detailFetchedAt: Date?
  var workoutsFetchedAt: Date?
  var archiveFetchedAt: Date?
  var detailRefreshPendingSince: Date?
  // Existing unshipped stores conservatively refresh detail once after this field is added.
  var detailFreshnessKnown: Bool = false

  init(identity: String, revisionID: UUID, activityID: Int64) {
    self.identity = identity
    self.revisionID = revisionID
    self.activityID = activityID
  }
}

/// Per-activity metadata, independent of shared/deduplicated raw response timestamps.
nonisolated struct GarminActivityFreshness: Sendable, Equatable {
  private(set) var pendingSince: Date?
  private(set) var hasVerifiedDetail: Bool

  init(pendingSince: Date? = nil, hasVerifiedDetail: Bool = false) {
    self.pendingSince = pendingSince
    self.hasVerifiedDetail = hasVerifiedDetail
  }

  var needsDetailRefresh: Bool { !hasVerifiedDetail || pendingSince != nil }

  mutating func observeSummary<Value: Equatable>(
    previous: Value?, current: Value, at date: Date
  ) {
    guard previous != current else { return }
    pendingSince = max(pendingSince ?? date, date)
  }

  mutating func importedDetail(at date: Date) {
    hasVerifiedDetail = true
    if let pendingSince, date >= pendingSince { self.pendingSince = nil }
  }
}

nonisolated final class GarminActivitySnapshot: Sendable {
  let revision: CredentialRevision
  let activityID: Int64
  /// Source local calendar label; absent until a summary or detail supplies one.
  let date: DateKey?
  let summary: ActivityDTO?
  let detail: ActivityDetailDTO?
  let workouts: [JSONValue]?
  let archive: Data?
  let sourceResponseIDs: [GarminPayload.Family: UUID]
  let freshness: GarminActivityFreshness

  var needsDetailRefresh: Bool { detail == nil || freshness.needsDetailRefresh }

  init(
    revision: CredentialRevision,
    activityID: Int64,
    date: DateKey? = nil,
    summary: ActivityDTO? = nil,
    detail: ActivityDetailDTO? = nil,
    workouts: [JSONValue]? = nil,
    archive: Data? = nil,
    sourceResponseIDs: [GarminPayload.Family: UUID],
    freshness: GarminActivityFreshness
  ) {
    self.revision = revision
    self.activityID = activityID
    self.date = date
    self.summary = summary
    self.detail = detail
    self.workouts = workouts
    self.archive = archive
    self.sourceResponseIDs = sourceResponseIDs
    self.freshness = freshness
  }

}
