import Foundation

nonisolated enum GarminEndpoint: Sendable, Equatable {
  case sleep(DateKey)
  case sleepSummaries(start: DateKey, end: DateKey)
  case hrv(DateKey)
  case hrvSummaries(start: DateKey, end: DateKey)
  case heartRate(DateKey)
  case bodyBattery(start: DateKey, end: DateKey)
  case stress(start: DateKey, end: DateKey)
  case dailySummaries(start: DateKey, end: DateKey)
  case activities(start: DateKey, end: DateKey, offset: Int, limit: Int)
  case activity(Int64)
  case archive(Int64)
  case workouts(Int64)
  case steps(start: DateKey, end: DateKey)
  case spo2(DateKey)

  /// Body Battery intervals per day: 96 gives a lowest and highest reading every 15 minutes.
  static let bodyBatteryChunks = 96

  /// Routes saved before Body Battery requests carried `chunks` hold only each day's extremes.
  static func requestsChunks(_ route: String) -> Bool {
    URLComponents(string: route)?.queryItems?.contains { $0.name == "chunks" } == true
  }

  var family: GarminPayload.Family {
    switch self {
    case .sleep: .sleep
    case .sleepSummaries: .sleepSummaries
    case .hrv: .hrv
    case .hrvSummaries: .hrvSummaries
    case .heartRate: .heartRate
    case .bodyBattery: .bodyBattery
    case .stress: .stress
    case .dailySummaries: .dailySummaries
    case .activities: .activities
    case .activity: .activity
    case .archive: .archive
    case .workouts: .workouts
    case .steps: .steps
    case .spo2: .spo2
    }
  }

  var dates: ClosedRange<DateKey>? {
    switch self {
    case .sleep(let date), .hrv(let date), .heartRate(let date), .spo2(let date): date...date
    case .sleepSummaries(let start, let end), .hrvSummaries(let start, let end),
      .bodyBattery(let start, let end), .stress(let start, let end),
      .dailySummaries(let start, let end), .steps(let start, let end),
      .activities(let start, let end, _, _):
      start <= end ? start...end : nil
    case .activity, .archive, .workouts: nil
    }
  }

  func request() throws -> URLRequest {
    var path: String
    var items: [URLQueryItem] = []
    func range(_ start: DateKey, _ end: DateKey, limit: Int? = nil) throws {
      guard start <= end else { throw GarminError.invalidEndpoint }
      if let limit {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        guard let first = formatter.date(from: start.rawValue),
          let last = formatter.date(from: end.rawValue),
          last.timeIntervalSince(first) < Double(limit) * 86_400
        else { throw GarminError.invalidEndpoint }
      }
    }
    func queryRange(_ start: DateKey, _ end: DateKey) -> [URLQueryItem] {
      [
        URLQueryItem(name: "startDate", value: start.rawValue),
        URLQueryItem(name: "endDate", value: end.rawValue),
      ]
    }
    switch self {
    case .sleep(let date):
      path = "/sleep-service/sleep/dailySleep"
      items = [URLQueryItem(name: "date", value: date.rawValue)]
    case .sleepSummaries(let start, let end):
      try range(start, end, limit: 31)
      path = "/sleep-service/sleep/dailySleepSummariesByDate"
      items = queryRange(start, end)
    case .hrv(let date): path = "/hrv-service/hrv/\(date.rawValue)"
    case .hrvSummaries(let start, let end):
      try range(start, end)
      path = "/hrv-service/hrv/daily/\(start.rawValue)/\(end.rawValue)"
    case .heartRate(let date):
      path = "/wellness-service/wellness/dailyHeartRate"
      items = [URLQueryItem(name: "date", value: date.rawValue)]
    case .bodyBattery(let start, let end):
      try range(start, end, limit: 31)
      path = "/wellness-service/wellness/bodyBattery/reports/daily"
      // Without chunks Garmin returns only each day's high and low. Each interval adds its own.
      items =
        queryRange(start, end) + [
          URLQueryItem(name: "chunks", value: String(Self.bodyBatteryChunks))
        ]
    case .stress(let start, let end):
      try range(start, end, limit: 28)
      path = "/usersummary-service/stats/stress/daily/\(start.rawValue)/\(end.rawValue)"
    case .dailySummaries(let start, let end):
      try range(start, end)
      var calendar = Calendar(identifier: .gregorian)
      calendar.timeZone = TimeZone(secondsFromGMT: 0)!
      let components = start.rawValue.split(separator: "-").compactMap { Int($0) }
      guard
        let first = calendar.date(
          from: DateComponents(year: components[0], month: components[1], day: components[2])),
        let next = calendar.date(byAdding: .year, value: 1, to: first)
      else { throw GarminError.invalidEndpoint }
      let formatter = DateFormatter()
      formatter.calendar = calendar
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.timeZone = calendar.timeZone
      formatter.dateFormat = "yyyy-MM-dd"
      guard end.rawValue < formatter.string(from: next) else { throw GarminError.invalidEndpoint }
      path = "/usersummary-service/v2/dailysummaries"
      items = queryRange(start, end)
    case .activities(let start, let end, let offset, let limit):
      try range(start, end)
      guard offset >= 0, limit > 0 else { throw GarminError.invalidEndpoint }
      path = "/activitylist-service/activities/search/activities"
      items =
        [
          URLQueryItem(name: "start", value: String(offset)),
          URLQueryItem(name: "limit", value: String(limit)),
        ]
        + queryRange(start, end)
    case .activity(let id), .archive(let id), .workouts(let id):
      guard id > 0 else { throw GarminError.invalidEndpoint }
      switch self {
      case .archive: path = "/download-service/files/activity/\(id)"
      case .workouts: path = "/activity-service/activity/\(id)/workouts"
      default: path = "/activity-service/activity/\(id)"
      }
    case .steps(let start, let end):
      try range(start, end, limit: 28)
      path = "/usersummary-service/stats/steps/daily/\(start.rawValue)/\(end.rawValue)"
    case .spo2(let date): path = "/wellness-service/wellness/daily/spo2acclimation/\(date.rawValue)"
    }
    var components = URLComponents(url: GarminOrigin.url, resolvingAgainstBaseURL: false)!
    components.path = path
    components.queryItems = items.isEmpty ? nil : items
    guard let url = components.url else { throw GarminError.invalidEndpoint }
    var request = URLRequest(url: url)
    request.setValue(
      family == .archive ? "application/zip, application/octet-stream" : "application/json",
      forHTTPHeaderField: "Accept")
    return request
  }
}
