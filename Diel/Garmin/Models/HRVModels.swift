// Presence follows Garmin Swagger required lists; fixtures preserve observed wire units and types.

nonisolated struct HRVDTO: Codable, Sendable, Equatable {
  let endTimestampGMT: String
  let endTimestampLocal: String
  let hrvReadings: [HrvReadingsElement]?
  let hrvSummary: HrvSummary?
  let sleepEndTimestampGMT: String?
  let sleepEndTimestampLocal: String?
  let sleepStartTimestampGMT: String?
  let sleepStartTimestampLocal: String?
  let startTimestampGMT: String
  let startTimestampLocal: String
  let userProfileID: Int64?

  private enum CodingKeys: String, CodingKey {
    case endTimestampGMT
    case endTimestampLocal
    case hrvReadings
    case hrvSummary
    case sleepEndTimestampGMT
    case sleepEndTimestampLocal
    case sleepStartTimestampGMT
    case sleepStartTimestampLocal
    case startTimestampGMT
    case startTimestampLocal
    case userProfileID = "userProfilePk"
  }

  nonisolated struct HrvReadingsElement: Codable, Sendable, Equatable {
    let hrvValue: Int64?
    let readingTimeGMT: String
    let readingTimeLocal: String

    private enum CodingKeys: String, CodingKey {
      case hrvValue
      case readingTimeGMT
      case readingTimeLocal
    }
  }
  nonisolated struct HrvSummary: Codable, Sendable, Equatable {
    let baseline: Baseline?
    let calendarDate: DateKey?
    let createTimeStamp: String
    let feedbackPhrase: String?
    let lastNight5MinHigh: Int64?
    let lastNightAvg: Int64?
    let status: String?
    let weeklyAvg: Int64?

    private enum CodingKeys: String, CodingKey {
      case baseline
      case calendarDate
      case createTimeStamp
      case feedbackPhrase
      case lastNight5MinHigh
      case lastNightAvg
      case status
      case weeklyAvg
    }

    nonisolated struct Baseline: Codable, Sendable, Equatable {
      let balancedLow: Int64?
      let balancedUpper: Int64?
      let lowUpper: Int64?
      let markerValue: Double?

      private enum CodingKeys: String, CodingKey {
        case balancedLow
        case balancedUpper
        case lowUpper
        case markerValue
      }
    }
  }
}

nonisolated struct HRVSummariesDTO: Codable, Sendable, Equatable {
  let hrvSummaries: [HrvSummariesElement]?
  let userProfileID: Int64?

  private enum CodingKeys: String, CodingKey {
    case hrvSummaries
    case userProfileID = "userProfilePk"
  }

  nonisolated struct HrvSummariesElement: Codable, Sendable, Equatable {
    let baseline: Baseline?
    let calendarDate: DateKey?
    let createTimeStamp: String
    let feedbackPhrase: String?
    let lastNight5MinHigh: Int64?
    let lastNightAvg: Int64?
    let status: String?
    let weeklyAvg: Int64?

    private enum CodingKeys: String, CodingKey {
      case baseline
      case calendarDate
      case createTimeStamp
      case feedbackPhrase
      case lastNight5MinHigh
      case lastNightAvg
      case status
      case weeklyAvg
    }

    nonisolated struct Baseline: Codable, Sendable, Equatable {
      let balancedLow: Int64?
      let balancedUpper: Int64?
      let lowUpper: Int64?
      let markerValue: Double?

      private enum CodingKeys: String, CodingKey {
        case balancedLow
        case balancedUpper
        case lowUpper
        case markerValue
      }
    }
  }
}
