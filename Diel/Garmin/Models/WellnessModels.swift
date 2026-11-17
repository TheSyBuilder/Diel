// Presence follows Garmin Swagger required lists; fixtures preserve observed wire units and types.

nonisolated struct HeartRateDTO: Codable, Sendable, Equatable {
  let calendarDate: DateKey?
  let endTimestampGMT: String?
  let endTimestampLocal: String?
  let heartRateValueDescriptors: [HeartRateValueDescriptorsElement]?
  let heartRateValues: [[Int64?]]?
  let lastSevenDaysAvgRestingHeartRate: Int64?
  let maxHeartRate: Int64?
  let minHeartRate: Int64?
  let restingHeartRate: Int64?
  let startTimestampGMT: String?
  let startTimestampLocal: String?
  let userProfileID: Int64?

  private enum CodingKeys: String, CodingKey {
    case calendarDate
    case endTimestampGMT
    case endTimestampLocal
    case heartRateValueDescriptors
    case heartRateValues
    case lastSevenDaysAvgRestingHeartRate
    case maxHeartRate
    case minHeartRate
    case restingHeartRate
    case startTimestampGMT
    case startTimestampLocal
    case userProfileID = "userProfilePK"
  }

  nonisolated struct HeartRateValueDescriptorsElement: Codable, Sendable, Equatable {
    let index: Int64?
    let key: String?

    private enum CodingKeys: String, CodingKey {
      case index
      case key
    }
  }
}

nonisolated struct BodyBatteryDTO: Codable, Sendable, Equatable {
  let bodyBatteryActivityEvent: [BodyBatteryActivityEventElement]?
  let bodyBatteryDynamicFeedbackEvent: BodyBatteryDynamicFeedbackEvent?
  let bodyBatteryValueDescriptorDTOList: [BodyBatteryValueDescriptorDTOListElement]?
  let bodyBatteryValuesArray: [[Int64?]]?
  let charged: Int64?
  let date: DateKey?
  let drained: Int64?
  let endOfDayBodyBatteryDynamicFeedbackEvent: EndOfDayBodyBatteryDynamicFeedbackEvent?
  let endTimestampGMT: String?
  let endTimestampLocal: String?
  let startTimestampGMT: String?
  let startTimestampLocal: String?

  private enum CodingKeys: String, CodingKey {
    case bodyBatteryActivityEvent
    case bodyBatteryDynamicFeedbackEvent
    case bodyBatteryValueDescriptorDTOList
    case bodyBatteryValuesArray
    case charged
    case date
    case drained
    case endOfDayBodyBatteryDynamicFeedbackEvent
    case endTimestampGMT
    case endTimestampLocal
    case startTimestampGMT
    case startTimestampLocal
  }

  nonisolated struct BodyBatteryActivityEventElement: Codable, Sendable, Equatable {
    let bodyBatteryImpact: Int64?
    let durationInMilliseconds: Int64?
    let eventStartTimeGmt: String?
    let eventType: String?
    let feedbackType: String?
    let shortFeedback: String?
    let timezoneOffset: Int64?

    private enum CodingKeys: String, CodingKey {
      case bodyBatteryImpact
      case durationInMilliseconds
      case eventStartTimeGmt
      case eventType
      case feedbackType
      case shortFeedback
      case timezoneOffset
    }
  }
  nonisolated struct BodyBatteryDynamicFeedbackEvent: Codable, Sendable, Equatable {
    let bodyBatteryLevel: String?
    let eventTimestampGmt: String?
    let feedbackLongType: String?
    let feedbackShortType: String?

    private enum CodingKeys: String, CodingKey {
      case bodyBatteryLevel
      case eventTimestampGmt
      case feedbackLongType
      case feedbackShortType
    }
  }
  nonisolated struct BodyBatteryValueDescriptorDTOListElement: Codable, Sendable, Equatable {
    let bodyBatteryValueDescriptorIndex: Int64?
    let bodyBatteryValueDescriptorKey: String?

    private enum CodingKeys: String, CodingKey {
      case bodyBatteryValueDescriptorIndex
      case bodyBatteryValueDescriptorKey
    }
  }
  nonisolated struct EndOfDayBodyBatteryDynamicFeedbackEvent: Codable, Sendable, Equatable {
    let bodyBatteryLevel: String?
    let eventTimestampGmt: String?
    let feedbackLongType: String?
    let feedbackShortType: String?

    private enum CodingKeys: String, CodingKey {
      case bodyBatteryLevel
      case eventTimestampGmt
      case feedbackLongType
      case feedbackShortType
    }
  }
}

nonisolated struct StressDTO: Codable, Sendable, Equatable {
  let calendarDate: DateKey?
  let values: Values?

  private enum CodingKeys: String, CodingKey {
    case calendarDate
    case values
  }

  nonisolated struct Values: Codable, Sendable, Equatable {
    let highStressDuration: Int64?
    let lowStressDuration: Int64?
    let mediumStressDuration: Int64?
    let overallStressLevel: Int64?
    let restStressDuration: Int64?

    private enum CodingKeys: String, CodingKey {
      case highStressDuration
      case lowStressDuration
      case mediumStressDuration
      case overallStressLevel
      case restStressDuration
    }
  }
}

nonisolated struct StepsDTO: Codable, Sendable, Equatable {
  let calendarDate: DateKey?
  let stepGoal: Int64?
  let totalDistance: Int64?
  let totalSteps: Int64?

  private enum CodingKeys: String, CodingKey {
    case calendarDate
    case stepGoal
    case totalDistance
    case totalSteps
  }
}

nonisolated struct SpO2DTO: Codable, Sendable, Equatable {
  let averageSpO2: Double?
  let avgSleepSpO2: Double?
  let avgTomorrowSleepSpO2: Double?
  let calendarDate: DateKey?
  let endTimestampGMT: String?
  let endTimestampLocal: String?
  let lastSevenDaysAvgSpO2: Double?
  let latestSpO2: Double?
  let latestSpO2TimestampGMT: String?
  let latestSpO2TimestampLocal: String?
  let lowestSpO2: Double?
  let monitoringEnvironmentValues: JSONValue?
  let monitoringEnvironmentValuesDescriptorList: JSONValue?
  let sleepEndTimestampGMT: String?
  let sleepEndTimestampLocal: String?
  let sleepStartTimestampGMT: String?
  let sleepStartTimestampLocal: String?
  let spO2HourlyAverages: JSONValue?
  let spO2HourlyAveragesDescriptorList: JSONValue?
  let spO2SingleValues: JSONValue?
  let spO2SingleValuesDescriptorList: JSONValue?
  let startTimestampGMT: String?
  let startTimestampLocal: String?
  let tomorrowSleepEndTimestampGMT: String?
  let tomorrowSleepEndTimestampLocal: String?
  let tomorrowSleepStartTimestampGMT: String?
  let tomorrowSleepStartTimestampLocal: String?
  let userProfileID: Int64?

  private enum CodingKeys: String, CodingKey {
    case averageSpO2
    case avgSleepSpO2
    case avgTomorrowSleepSpO2
    case calendarDate
    case endTimestampGMT
    case endTimestampLocal
    case lastSevenDaysAvgSpO2
    case latestSpO2
    case latestSpO2TimestampGMT
    case latestSpO2TimestampLocal
    case lowestSpO2
    case monitoringEnvironmentValues
    case monitoringEnvironmentValuesDescriptorList
    case sleepEndTimestampGMT
    case sleepEndTimestampLocal
    case sleepStartTimestampGMT
    case sleepStartTimestampLocal
    case spO2HourlyAverages
    case spO2HourlyAveragesDescriptorList
    case spO2SingleValues
    case spO2SingleValuesDescriptorList
    case startTimestampGMT
    case startTimestampLocal
    case tomorrowSleepEndTimestampGMT
    case tomorrowSleepEndTimestampLocal
    case tomorrowSleepStartTimestampGMT
    case tomorrowSleepStartTimestampLocal
    case userProfileID = "userProfilePK"
  }
}
