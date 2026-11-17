import Foundation
import SwiftData

/// Latest source per scoped endpoint/date. Referenced retired sources retain metadata only.
/// Empty retired bytes mean the original payload is no longer available, not an empty HTTP body.
@Model nonisolated final class RawGarminResponse {
  @Attribute(.unique) var identity: String
  var id: UUID
  var revisionID: UUID
  var family: String
  var route: String
  var startDate: String?
  var endDate: String?
  var firstFetchedAt: Date
  var lastFetchedAt: Date
  @Attribute(.externalStorage) var bytes: Data

  init(
    identity: String, revisionID: UUID, family: String, route: String,
    startDate: String?, endDate: String?, fetchedAt: Date, bytes: Data
  ) {
    self.identity = identity
    id = UUID()
    self.revisionID = revisionID
    self.family = family
    self.route = route
    self.startDate = startDate
    self.endDate = endDate
    firstFetchedAt = fetchedAt
    lastFetchedAt = fetchedAt
    self.bytes = bytes
  }
}

nonisolated struct GarminRawSnapshot: Sendable {
  let id: UUID
  let revision: CredentialRevision
  let family: GarminPayload.Family
  /// Credential-free path and query from GarminEndpoint.request(), never request headers.
  let route: String
  let dates: ClosedRange<DateKey>?
  let firstFetchedAt: Date
  let lastFetchedAt: Date
  let bytes: Data
  /// False for retired source metadata. Parsed projections still preserve their original values.
  var payloadRetained: Bool = true
}

/// Date members retain every wire field, including fields not projected by the app.
/// Range envelopes are rebuilt around one member so overlapping sync windows do not duplicate bodies.
nonisolated struct GarminRawPiece {
  let key: String
  let date: DateKey?
  let bytes: Data

  static func split(_ bytes: Data, endpoint: GarminEndpoint) throws -> [Self] {
    try split(bytes, family: endpoint.family, dates: endpoint.dates)
  }

  static func split(
    _ bytes: Data, family: GarminPayload.Family, dates: ClosedRange<DateKey>?
  ) throws -> [Self] {
    guard
      [
        GarminPayload.Family.sleepSummaries, .hrvSummaries, .bodyBattery, .stress,
        .dailySummaries, .steps,
      ].contains(family)
    else {
      if family == .activities || dates == nil {
        return [Self(key: "route", date: nil, bytes: bytes)]
      }
      return [Self(key: dates!.lowerBound.rawValue, date: dates!.lowerBound, bytes: bytes)]
    }
    let json = try JSONDecoder().decode(JSONValue.self, from: bytes)
    let envelopeKey =
      family == .hrvSummaries ? "hrvSummaries" : family == .dailySummaries ? "data" : nil
    let members: [JSONValue]
    var envelope: [String: JSONValue] = [:]
    if let envelopeKey, case .object(let fields) = json,
      case .array(let array) = fields[envelopeKey]
    {
      envelope = fields
      members = array
    } else if case .array(let array) = json {
      members = array
    } else {
      return [Self(key: "unlocated", date: nil, bytes: bytes)]
    }
    guard !members.isEmpty else { return [Self(key: "empty", date: nil, bytes: bytes)] }
    var grouped: [String: [JSONValue]] = [:]
    for member in members {
      let date: DateKey?
      if case .object(let fields) = member {
        let candidate = fields[family == .bodyBattery ? "date" : "calendarDate"]
        if case .string(let label) = candidate {
          date = DateKey(rawValue: label)
        } else if family == .sleepSummaries,
          case .object(let need) = fields["sleepNeed"],
          case .string(let label) = need["calendarDate"]
        {
          date = DateKey(rawValue: label)
        } else {
          date = nil
        }
      } else {
        date = nil
      }
      grouped[date?.rawValue ?? "unlocated", default: []].append(member)
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try grouped.keys.sorted().map { key in
      let values = JSONValue.array(grouped[key]!)
      let body: JSONValue
      if let envelopeKey {
        var fields = envelope
        fields[envelopeKey] = values
        body = .object(fields)
      } else {
        body = values
      }
      return Self(key: key, date: DateKey(rawValue: key), bytes: try encoder.encode(body))
    }
  }
}
