import Foundation
import SwiftData

@Model nonisolated final class GarminDayRecord {
  #Index<GarminDayRecord>([\.revisionID, \.calendarDate])
  @Attribute(.unique) var identity: String
  var revisionID: UUID
  var family: String
  var calendarDate: String
  var sourceResponseID: UUID
  var fetchedAt: Date
  var encodedProjection: Data

  init(
    identity: String, revisionID: UUID, family: String, calendarDate: String,
    sourceResponseID: UUID, fetchedAt: Date, encodedProjection: Data
  ) {
    self.identity = identity
    self.revisionID = revisionID
    self.family = family
    self.calendarDate = calendarDate
    self.sourceResponseID = sourceResponseID
    self.fetchedAt = fetchedAt
    self.encodedProjection = encodedProjection
  }
}

nonisolated indirect enum GarminDayProjection: Codable, Sendable, Equatable {
  case sleep(SleepDTO)
  case sleepSummary(SleepDTO)
  case hrv(HRVDTO)
  case hrvSummary(HRVSummariesDTO.HrvSummariesElement)
  case heartRate(HeartRateDTO)
  case bodyBattery(BodyBatteryDTO)
  case stress(StressDTO)
  case dailySummary(DailySummariesDTO.DataElement)
  case steps(StepsDTO)
  case spo2(SpO2DTO)
}

nonisolated final class GarminDayValue: Sendable {
  let family: GarminPayload.Family
  let sourceResponseID: UUID
  let fetchedAt: Date
  let projection: GarminDayProjection

  init(
    family: GarminPayload.Family,
    sourceResponseID: UUID,
    fetchedAt: Date,
    projection: GarminDayProjection
  ) {
    self.family = family
    self.sourceResponseID = sourceResponseID
    self.fetchedAt = fetchedAt
    self.projection = projection
  }

}

nonisolated struct GarminDaySnapshot: Sendable {
  let revision: CredentialRevision
  let date: DateKey
  let values: [GarminDayValue]

  var sleep: SleepDTO? {
    let selected = values.filter { [.sleep, .sleepSummaries].contains($0.family) }.max {
      $0.fetchedAt == $1.fetchedAt
        ? $0.family == .sleepSummaries && $1.family == .sleep : $0.fetchedAt < $1.fetchedAt
    }
    switch selected?.projection {
    case .sleep(let dto), .sleepSummary(let dto): return dto
    default: return nil
    }
  }
  var sleepSummary: SleepDTO? {
    for value in values { if case .sleepSummary(let dto) = value.projection { return dto } }
    return nil
  }
  var hrv: HRVDTO? {
    for value in values { if case .hrv(let dto) = value.projection { return dto } }
    return nil
  }
  var hrvSummary: HRVSummariesDTO.HrvSummariesElement? {
    for value in values { if case .hrvSummary(let dto) = value.projection { return dto } }
    return nil
  }
  var heartRate: HeartRateDTO? {
    for value in values { if case .heartRate(let dto) = value.projection { return dto } }
    return nil
  }
  var bodyBattery: BodyBatteryDTO? {
    for value in values { if case .bodyBattery(let dto) = value.projection { return dto } }
    return nil
  }
  var stress: StressDTO? {
    for value in values { if case .stress(let dto) = value.projection { return dto } }
    return nil
  }
  var dailySummary: DailySummariesDTO.DataElement? {
    for value in values { if case .dailySummary(let dto) = value.projection { return dto } }
    return nil
  }
  var steps: StepsDTO? {
    for value in values { if case .steps(let dto) = value.projection { return dto } }
    return nil
  }
  var spo2: SpO2DTO? {
    for value in values { if case .spo2(let dto) = value.projection { return dto } }
    return nil
  }
}

extension GarminDayProjection {
  /// Reject a weaker replacement while retaining its original raw response separately.
  nonisolated func losesValidReading(comparedWith previous: GarminDayProjection) -> Bool {
    // Within one route, a thinner object cannot erase an already saved display fact.
    // Keep that projection's original source identity; the thinner raw body is still retained.
    // A response that covers more of the same day is the newer snapshot of a growing series,
    // so only its intraday sample count and the explicit scalar facts below can block it.
    let extends = extendsCoverage(of: previous)
    if extends, losesIntradaySamples(comparedWith: previous) { return true }
    // A chunked Body Battery day reports each interval's lowest and highest readings at their own
    // times, so a refreshed copy can omit a saved row's exact timestamp. Copies the rule below
    // does not cover take the timestamp-by-timestamp checks that follow.
    if !extends, case (.bodyBattery(let new), .bodyBattery(let old)) = (self, previous),
      new.date == old.date, let accepted = Self.chunkedBodyBatteryReplacement(new, previous: old)
    {
      return !accepted
    }
    if !extends,
      let current = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(self))
        as? [String: Any],
      let prior = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(previous))
        as? [String: Any],
      current.keys.first == prior.keys.first,
      Self.losesPopulatedField(current, previous: prior)
    {
      return true
    }
    func lost(_ new: Double?, _ old: Double?, positive: Bool = false) -> Bool {
      let oldValid = old.map { $0.isFinite && (positive ? $0 > 0 : $0 >= 0) } ?? false
      let newValid = new.map { $0.isFinite && (positive ? $0 > 0 : $0 >= 0) } ?? false
      return oldValid && !newValid
    }
    switch (self, previous) {
    case (.sleep(let new), .sleep(let old)), (.sleep(let new), .sleepSummary(let old)),
      (.sleepSummary(let new), .sleep(let old)), (.sleepSummary(let new), .sleepSummary(let old)):
      let displayFields: Set<String> = [
        "sleepTimeSeconds", "awakeSleepSeconds", "deepSleepSeconds", "remSleepSeconds",
        "lightSleepSeconds", "sleepStartTimestampLocal", "sleepEndTimestampLocal",
        "sleepStartTimestampGMT", "sleepEndTimestampGMT", "sleepScores", "sleepNeed",
        "averageRespirationValue", "avgHeartRate", "avgSleepStress", "breathingDisruptionSeverity",
      ]
      if let current = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(new))
        as? [String: Any],
        let prior = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(old))
          as? [String: Any],
        Self.losesPopulatedField(
          current.filter { displayFields.contains($0.key) },
          previous: prior.filter { displayFields.contains($0.key) })
      {
        return true
      }
      return lost(new.sleepTimeSeconds.map(Double.init), old.sleepTimeSeconds.map(Double.init))
        || lost(new.awakeSleepSeconds.map(Double.init), old.awakeSleepSeconds.map(Double.init))
        || lost(new.deepSleepSeconds.map(Double.init), old.deepSleepSeconds.map(Double.init))
        || lost(new.lightSleepSeconds.map(Double.init), old.lightSleepSeconds.map(Double.init))
        || lost(new.remSleepSeconds.map(Double.init), old.remSleepSeconds.map(Double.init))
        || lost(
          new.sleepStartTimestampLocal.map(Double.init),
          old.sleepStartTimestampLocal.map(Double.init))
        || lost(
          new.sleepEndTimestampLocal.map(Double.init), old.sleepEndTimestampLocal.map(Double.init))
        || lost(
          new.sleepNeed?.actual.map(Double.init), old.sleepNeed?.actual.map(Double.init),
          positive: true)
        || lost(
          new.sleepScores?.overall?.value.map(Double.init),
          old.sleepScores?.overall?.value.map(Double.init))
    case (.hrv(let new), .hrv(let old)):
      return lost(
        new.hrvSummary?.lastNightAvg.map(Double.init),
        old.hrvSummary?.lastNightAvg.map(Double.init), positive: true)
    case (.hrv(let new), .hrvSummary(let old)):
      return lost(
        new.hrvSummary?.lastNightAvg.map(Double.init), old.lastNightAvg.map(Double.init),
        positive: true)
    case (.hrvSummary(let new), .hrv(let old)):
      return lost(
        new.lastNightAvg.map(Double.init), old.hrvSummary?.lastNightAvg.map(Double.init),
        positive: true)
    case (.hrvSummary(let new), .hrvSummary(let old)):
      return lost(
        new.lastNightAvg.map(Double.init), old.lastNightAvg.map(Double.init), positive: true)
    case (.heartRate(let new), .heartRate(let old)):
      return lost(
        new.restingHeartRate.map(Double.init), old.restingHeartRate.map(Double.init), positive: true
      )
    case (.dailySummary(let new), .dailySummary(let old)):
      return lost(
        new.heartRate?.restingValue.map(Double.init), old.heartRate?.restingValue.map(Double.init),
        positive: true)
    default: return false
    }
  }

  /// Same-day intraday series whose coverage ends strictly later than the saved partial one.
  nonisolated func extendsCoverage(of previous: GarminDayProjection) -> Bool {
    func later(
      _ newStart: String?, _ newEnd: String?, _ oldStart: String?, _ oldEnd: String?
    ) -> Bool {
      guard let newStart, let newEnd, let oldStart, let oldEnd,
        newStart == oldStart, newEnd.count == oldEnd.count
      else { return false }
      return newEnd > oldEnd
    }
    switch (self, previous) {
    case (.heartRate(let new), .heartRate(let old)):
      return new.calendarDate == old.calendarDate
        && later(
          new.startTimestampGMT, new.endTimestampGMT, old.startTimestampGMT, old.endTimestampGMT)
    case (.bodyBattery(let new), .bodyBattery(let old)):
      return new.date == old.date
        && later(
          new.startTimestampGMT, new.endTimestampGMT, old.startTimestampGMT, old.endTimestampGMT)
    default: return false
    }
  }

  /// A longer copy of a growing series must still carry at least the saved non-null samples.
  nonisolated func losesIntradaySamples(comparedWith previous: GarminDayProjection) -> Bool {
    let rows: (new: [[Int64?]]?, old: [[Int64?]]?)
    switch (self, previous) {
    case (.heartRate(let new), .heartRate(let old)):
      rows = (new.heartRateValues, old.heartRateValues)
    case (.bodyBattery(let new), .bodyBattery(let old)):
      rows = (new.bodyBatteryValuesArray, old.bodyBatteryValuesArray)
    default: return false
    }
    guard let old = rows.old, !old.isEmpty else { return false }
    guard let new = rows.new, !new.isEmpty else { return true }
    return Self.sampleCount(new) < Self.sampleCount(old)
  }

  /// Rows that carry at least one non-null reading after their timestamp.
  private nonisolated static func sampleCount(_ series: [[Int64?]]?) -> Int {
    (series ?? []).count { row in row.dropFirst().contains { $0 != nil } }
  }

  /// Decides a same-date Body Battery copy that is denser than the saved one, or as dense when
  /// both are chunked (more than two samples). It applies only when the new samples span the saved
  /// ones to within one 15-minute interval at each end and keep a reading in every 15-minute
  /// interval the saved copy had one; otherwise it returns nil. A spanning copy
  /// is accepted when charged/drained stay populated and no other populated field goes missing.
  private nonisolated static func chunkedBodyBatteryReplacement(
    _ new: BodyBatteryDTO, previous old: BodyBatteryDTO
  ) -> Bool? {
    let newCount = sampleCount(new.bodyBatteryValuesArray)
    let oldCount = sampleCount(old.bodyBatteryValuesArray)
    guard newCount > oldCount || (oldCount > 2 && newCount == oldCount) else { return nil }
    func times(_ series: [[Int64?]]?) -> [Int64] {
      (series ?? []).compactMap { row in
        row.dropFirst().contains { $0 != nil } ? row.first ?? nil : nil
      }
    }
    let interval: Int64 = 15 * 60 * 1000
    let saved = times(old.bodyBatteryValuesArray)
    let current = times(new.bodyBatteryValuesArray)
    if let first = saved.min(), let last = saved.max() {
      guard let newFirst = current.min(), let newLast = current.max(),
        newFirst <= first + interval, newLast >= last - interval
      else { return nil }
    }
    // Every 15-minute interval that held a saved reading still holds one, so a copy cannot trade
    // a mid-day stretch for later rows. Every UTC offset is a whole number of quarter hours, so
    // epoch-aligned intervals are also aligned to the local day start.
    let covered = Set(current.map { $0 / interval })
    guard saved.allSatisfy({ covered.contains($0 / interval) }) else { return nil }
    func valid(_ value: Int64?) -> Bool { value.map { $0 >= 0 } ?? false }
    if valid(old.charged) && !valid(new.charged) { return false }
    if valid(old.drained) && !valid(new.drained) { return false }
    guard
      var fields = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(new))
        as? [String: Any],
      var prior = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(old))
        as? [String: Any]
    else { return false }
    fields.removeValue(forKey: "bodyBatteryValuesArray")
    prior.removeValue(forKey: "bodyBatteryValuesArray")
    return !losesPopulatedField(fields, previous: prior)
  }

  /// Rows shaped like `[timestamp, value...]`; nil for any other array.
  private nonisolated static func timestampedRows(_ rows: [Any]) -> [Int64: [Any]]? {
    guard !rows.isEmpty else { return nil }
    var keyed: [Int64: [Any]] = [:]
    for row in rows {
      guard let values = row as? [Any], values.count > 1,
        let time = values.first as? NSNumber, !(values.first is NSNull)
      else { return nil }
      keyed[time.int64Value] = values
    }
    return keyed
  }

  private nonisolated static func losesPopulatedField(_ current: Any?, previous: Any) -> Bool {
    if previous is NSNull { return false }
    guard let current, !(current is NSNull) else { return true }
    if let old = previous as? [String: Any] {
      guard let new = current as? [String: Any] else { return true }
      return old.contains { key, value in losesPopulatedField(new[key], previous: value) }
    }
    if let old = previous as? [Any], let new = current as? [Any],
      let oldRows = timestampedRows(old), let newRows = timestampedRows(new)
    {
      // Garmin can backfill a gap earlier in the day, shifting positions; match samples by time.
      return oldRows.contains { time, row in
        guard row.dropFirst().contains(where: { !($0 is NSNull) }) else { return false }
        guard let replacement = newRows[time] else { return true }
        return losesPopulatedField(replacement, previous: row)
      }
    }
    if let old = previous as? [Any] {
      guard let new = current as? [Any] else { return true }
      if new.count < old.count { return true }
      return zip(new, old).contains { losesPopulatedField($0.0, previous: $0.1) }
    }
    if let old = previous as? String, !old.isEmpty, let new = current as? String {
      return new.isEmpty
    }
    return false
  }
}
