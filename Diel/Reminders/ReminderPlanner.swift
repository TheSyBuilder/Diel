import Foundation

nonisolated struct MorningReminderRequest: Equatable, Sendable {
  enum Kind: String, Sendable {
    case first, missed
    var message: String {
      switch self {
      case .first: "How do you feel this morning?"
      case .missed: "Still time for your check-in."
      }
    }
  }
  static let prefix = "diel.morning."
  let dayID: String
  let kind: Kind
  let fireDate: Date
  var identifier: String { "\(Self.prefix)\(dayID).\(kind.rawValue)" }

  static func parse(_ identifier: String) -> (dayID: String, kind: Kind)? {
    guard identifier.hasPrefix(prefix) else { return nil }
    let parts = identifier.dropFirst(prefix.count).split(separator: ".")
    guard parts.count == 2, DateKey(rawValue: String(parts[0])) != nil,
      let kind = Kind(rawValue: String(parts[1]))
    else { return nil }
    return (String(parts[0]), kind)
  }
}

nonisolated enum ReminderPlanner {
  /// Thirty logical days stay below iOS's pending-request limit, with at most sixty owned requests.
  static func requests(
    preferences: ReminderPreferencesSnapshot, completed: Set<String>, now: Date,
    calendar supplied: Calendar
  ) throws -> [MorningReminderRequest] {
    guard preferences.isValid else { throw ReminderError.invalidPreferences }
    guard preferences.enabled else { return [] }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = supplied.timeZone
    let current = MorningDay(containing: now, calendar: calendar)
    var requests: [MorningReminderRequest] = []
    for offset in 0..<30 {
      let anchor = calendar.date(byAdding: .day, value: offset, to: current.start)!
      let day = MorningDay(containing: anchor, calendar: calendar)
      for (kind, minute) in [
        (MorningReminderRequest.Kind.first, preferences.firstMinute),
        (.missed, preferences.missedMinute),
      ] {
        if kind == .missed && (!preferences.missedIsLater || completed.contains(day.id)) {
          continue
        }
        let civilDay =
          minute < 4 * 60
          ? calendar.date(byAdding: .day, value: 1, to: day.start)! : day.start
        // Nonexistent times move to the next valid wall time; repeated times use the first occurrence.
        let date = calendar.date(
          bySettingHour: minute / 60, minute: minute % 60, second: 0,
          of: calendar.startOfDay(for: civilDay), matchingPolicy: .nextTime,
          repeatedTimePolicy: .first)!
        if date > now, date >= day.start, date < day.end {
          requests.append(.init(dayID: day.id, kind: kind, fireDate: date))
        }
      }
    }
    return requests
  }
}
