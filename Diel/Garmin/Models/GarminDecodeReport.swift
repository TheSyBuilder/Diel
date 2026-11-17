import Foundation

/// Closed rejection metadata; source values and decoding errors never leave this boundary.
nonisolated struct GarminRecordRejection: Sendable, Equatable {
  let stage: SyncFailure.Stage
  let reason: SyncFailure.Reason
  let date: DateKey?
  let fieldPath: String?

  init(
    stage: SyncFailure.Stage, reason: SyncFailure.Reason, date: DateKey? = nil,
    fieldPath: String? = nil
  ) {
    self.stage = stage
    self.reason = reason
    self.date = date
    self.fieldPath = fieldPath
  }

  static func knownDate(in value: JSONValue) -> DateKey? {
    guard case .object(let fields) = value else { return nil }
    for key in ["calendarDate", "date"] {
      if case .string(let label) = fields[key], let date = DateKey(rawValue: label) { return date }
    }
    if case .object(let need) = fields["sleepNeed"],
      case .string(let label) = need["calendarDate"]
    {
      return DateKey(rawValue: label)
    }
    return nil
  }

  static func location(_ error: any Error, prefix: String = "") -> String? {
    let path: [any CodingKey]
    let missing: String?
    switch error {
    case DecodingError.keyNotFound(let key, let context):
      path = context.codingPath
      missing = key.stringValue
    case DecodingError.typeMismatch(_, let context), DecodingError.valueNotFound(_, let context),
      DecodingError.dataCorrupted(let context):
      path = context.codingPath
      missing = nil
    default: return nil
    }
    let fields =
      path.map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }
      + (missing.map { [$0] } ?? [])
    return ([prefix].filter { !$0.isEmpty } + fields).joined(separator: ".")
  }

  // UI-only diagnostic context does not change the closed rejection or wire validation.
  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.stage == rhs.stage && lhs.reason == rhs.reason
  }

  #if DEBUG
    private(set) var missingDay: GarminMissingDayDiagnostic?

    func withMissingDay(_ diagnostic: GarminMissingDayDiagnostic) -> Self {
      var result = self
      result.missingDay = diagnostic
      return result
    }
  #endif
}

#if DEBUG
  /// Local UI only. Never add this value to SyncFailure or public logging.
  nonisolated struct GarminMissingDayDiagnostic: Sendable, Equatable {
    let memberIndex: Int
    let date: DateKey?
    let provenance: ScoringDateProvenance
    /// The member's non-null field paths from `presentFieldPaths(in:)`. Names only, never values.
    var presentFields: [String] = []

    var summary: String {
      let label = date?.rawValue ?? "unknown"
      return "Skipped member \(memberIndex): \(label) · \(provenance.rawValue) · no measured day"
    }

    /// Sorted non-null field paths of a raw member, one object level deep: `key` for a scalar,
    /// `key.sub` per non-null sub-key (`key{}` when none), `key[count]` for an array.
    static func presentFieldPaths(in member: JSONValue) -> [String] {
      guard case .object(let fields) = member else { return [] }
      return fields.flatMap { key, value -> [String] in
        switch value {
        case .null: return []
        case .array(let values): return ["\(key)[\(values.count)]"]
        case .object(let subfields):
          let present = subfields.filter { $0.value != .null }.map { "\(key).\($0.key)" }
          return present.isEmpty ? ["\(key){}"] : present
        case .bool, .integer, .number, .string: return [key]
        }
      }.sorted()
    }
  }
#endif

nonisolated struct GarminDecodeReport: Sendable, Equatable {
  let payload: GarminPayload?
  let rejections: [GarminRecordRejection]
  let memberCount: Int
}

nonisolated struct GarminImportReport: Sendable {
  let sourceID: UUID
  let importedCount: Int
  let rejections: [GarminRecordRejection]
}

extension GarminPayload {
  /// Batch containers must be readable. Individual typed members may be rejected.
  nonisolated static func decodeRecords(_ data: Data, as family: Family) throws
    -> GarminDecodeReport
  {
    if family == .archive {
      return GarminDecodeReport(payload: .archive(data), rejections: [], memberCount: 1)
    }
    if ![
      Family.activities, .sleepSummaries, .bodyBattery, .stress, .steps,
      .dailySummaries, .hrvSummaries, .workouts,
    ].contains(family) {
      do {
        return GarminDecodeReport(
          payload: try decode(data, as: family), rejections: [], memberCount: 1)
      } catch {
        return GarminDecodeReport(
          payload: nil,
          rejections: [
            .init(
              stage: .decode, reason: .decoding,
              date: (try? JSONDecoder().decode(JSONValue.self, from: data)).flatMap(
                GarminRecordRejection.knownDate),
              fieldPath: GarminRecordRejection.location(error))
          ], memberCount: 1)
      }
    }
    let json = try JSONDecoder().decode(JSONValue.self, from: data)
    var rejections: [GarminRecordRejection] = []
    var memberCount = 1
    func members<T: Decodable>(_ value: JSONValue, as type: T.Type) throws -> [T] {
      guard case .array(let values) = value else { throw GarminStoreError.invalidResponse }
      memberCount = values.count
      let result = try decodeMembers(values, as: type)
      rejections = result.rejections
      return result.values
    }
    let payload: GarminPayload
    switch family {
    case .activities: payload = .activities(try members(json, as: ActivityDTO.self))
    case .sleepSummaries: payload = .sleepSummaries(try members(json, as: SleepDTO.self))
    case .bodyBattery: payload = .bodyBattery(try members(json, as: BodyBatteryDTO.self))
    case .stress: payload = .stress(try members(json, as: StressDTO.self))
    case .steps: payload = .steps(try members(json, as: StepsDTO.self))
    case .workouts: payload = .workouts(try members(json, as: JSONValue.self))
    case .dailySummaries:
      guard case .object(let fields) = json, let values = fields["data"] else {
        throw GarminStoreError.invalidResponse
      }
      payload = .dailySummaries(
        DailySummariesDTO(data: try members(values, as: DailySummariesDTO.DataElement.self)))
    case .hrvSummaries:
      guard case .object(let fields) = json, let values = fields["hrvSummaries"] else {
        throw GarminStoreError.invalidResponse
      }
      // Decode envelope metadata strictly after replacing only its independently decoded members.
      let accepted = try members(values, as: HRVSummariesDTO.HrvSummariesElement.self)
      var envelope = fields
      envelope["hrvSummaries"] = .array([])
      let header = try JSONDecoder().decode(
        HRVSummariesDTO.self, from: JSONEncoder().encode(JSONValue.object(envelope)))
      payload = .hrvSummaries(
        HRVSummariesDTO(hrvSummaries: accepted, userProfileID: header.userProfileID))
    case .archive:
      return GarminDecodeReport(payload: .archive(data), rejections: [], memberCount: 1)
    default:
      do { payload = try decode(data, as: family) } catch {
        return GarminDecodeReport(
          payload: nil,
          rejections: [
            .init(
              stage: .decode, reason: .decoding,
              date: (try? JSONDecoder().decode(JSONValue.self, from: data)).flatMap(
                GarminRecordRejection.knownDate),
              fieldPath: GarminRecordRejection.location(error))
          ], memberCount: 1)
      }
    }
    return GarminDecodeReport(payload: payload, rejections: rejections, memberCount: memberCount)
  }

  /// The injectable typed decoder lets tests reject real fixture members without fake wire bodies.
  nonisolated static func decodeMembers<T: Decodable>(
    _ values: [JSONValue], as type: T.Type,
    decode: (Data) throws -> T = { try JSONDecoder().decode(T.self, from: $0) }
  ) throws -> (values: [T], rejections: [GarminRecordRejection]) {
    var accepted: [T] = []
    var rejections: [GarminRecordRejection] = []
    for (index, value) in values.enumerated() {
      let bytes = try JSONEncoder().encode(value)
      do { accepted.append(try decode(bytes)) } catch {
        let date = GarminRecordRejection.knownDate(in: value)
        rejections.append(
          .init(
            stage: .decode, reason: .decoding, date: date,
            fieldPath: GarminRecordRejection.location(error, prefix: "[\(index)]")))
      }
    }
    return (accepted, rejections)
  }
}
