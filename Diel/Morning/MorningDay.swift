import Foundation

/// A check-in day uses local wall time. Garmin score dates remain unchanged.
nonisolated struct MorningDay: Equatable, Sendable {
  let id: String
  let start: Date
  let end: Date

  init(containing now: Date, calendar supplied: Calendar = .current) {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = supplied.timeZone
    let midnight = calendar.startOfDay(for: now)
    let boundary = Self.boundary(on: midnight, calendar: calendar)
    let day = now < boundary ? calendar.date(byAdding: .day, value: -1, to: midnight)! : midnight
    start = Self.boundary(on: day, calendar: calendar)
    end = Self.boundary(
      on: calendar.date(byAdding: .day, value: 1, to: day)!, calendar: calendar)
    let parts = calendar.dateComponents([.year, .month, .day], from: day)
    id = String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
  }

  private static func boundary(on day: Date, calendar: Calendar) -> Date {
    calendar.date(
      bySettingHour: 4, minute: 0, second: 0, of: day,
      matchingPolicy: .nextTime, repeatedTimePolicy: .first)!
  }
}
