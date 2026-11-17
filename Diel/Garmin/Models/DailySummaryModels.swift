// Presence follows Garmin Swagger required lists; fixtures preserve observed wire units and types.

nonisolated struct DailySummariesDTO: Codable, Sendable, Equatable {
  let data: [DataElement]?

  private enum CodingKeys: String, CodingKey {
    case data
  }

  nonisolated final class DataElement: Codable, Sendable, Equatable {
    let bodyBattery: BodyBattery?
    let calendarDate: DateKey?
    let calories: Calories?
    let heartRate: HeartRate?
    let hydration: Hydration?
    let includesActivityData: Bool?
    let includesWellnessData: Bool?
    let intensityMinutes: IntensityMinutes?
    let jetLag: [String: JSONValue]?
    let movement: Movement?
    let pulseOx: [String: JSONValue]?
    let respiration: Respiration?
    let source: String?
    let stress: Stress?
    let userProfileID: Int64?
    let uuid: String?
    let wellnessChronology: WellnessChronology?

    private enum CodingKeys: String, CodingKey {
      case bodyBattery
      case calendarDate
      case calories
      case heartRate
      case hydration
      case includesActivityData
      case includesWellnessData
      case intensityMinutes
      case jetLag
      case movement
      case pulseOx
      case respiration
      case source
      case stress
      case userProfileID = "userProfilePk"
      case uuid
      case wellnessChronology
    }

    nonisolated struct BodyBattery: Codable, Sendable, Equatable {
      let activityEvents: [ActivityEventsElement]?
      let chargedValue: Int64?
      let drainedValue: Int64?
      let endOfDayValue: Int64?
      let dynamicFeedbackEvent: DynamicFeedbackEvent?
      let endOfDayDynamicFeedbackEvent: EndOfDayDynamicFeedbackEvent?
      let featureVersion: String?
      let latestValue: Int64?
      let maxValue: Int64?
      let minValue: Int64?

      private enum CodingKeys: String, CodingKey {
        case activityEvents
        case chargedValue
        case drainedValue
        case endOfDayValue
        case dynamicFeedbackEvent
        case endOfDayDynamicFeedbackEvent
        case featureVersion
        case latestValue
        case maxValue
        case minValue
      }

      nonisolated struct ActivityEventsElement: Codable, Sendable, Equatable {
        let bodyBatteryImpact: Int64?
        let deviceId: Int64?
        let durationInMillis: Int64?
        let eventStartTimeGmt: String?
        let eventStartTimeLocal: String?
        let eventType: String?
        let feedbackType: String?
        let shortFeedback: String?

        private enum CodingKeys: String, CodingKey {
          case bodyBatteryImpact
          case deviceId
          case durationInMillis
          case eventStartTimeGmt
          case eventStartTimeLocal
          case eventType
          case feedbackType
          case shortFeedback
        }
      }
      nonisolated struct DynamicFeedbackEvent: Codable, Sendable, Equatable {
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
      nonisolated struct EndOfDayDynamicFeedbackEvent: Codable, Sendable, Equatable {
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
    nonisolated struct Calories: Codable, Sendable, Equatable {
      let burnedActive: Int64?
      let burnedResting: Int64?
      let burnedTotal: Int64?

      private enum CodingKeys: String, CodingKey {
        case burnedActive
        case burnedResting
        case burnedTotal
      }
    }
    nonisolated struct HeartRate: Codable, Sendable, Equatable {
      let maxValue: Int64?
      let minValue: Int64?
      let restingValue: Int64?

      private enum CodingKeys: String, CodingKey {
        case maxValue
        case minValue
        case restingValue
      }
    }
    nonisolated struct Hydration: Codable, Sendable, Equatable {
      let consumedInFractionalMl: Double?
      let consumedInMl: Int64?
      let goalInFractionalMl: Double?
      let goalInMl: Int64?

      private enum CodingKeys: String, CodingKey {
        case consumedInFractionalMl
        case consumedInMl
        case goalInFractionalMl
        case goalInMl
      }
    }
    nonisolated struct IntensityMinutes: Codable, Sendable, Equatable {
      let goal: Int64?
      let moderate: Int64?
      let vigorous: Int64?

      private enum CodingKeys: String, CodingKey {
        case goal
        case moderate
        case vigorous
      }
    }
    nonisolated struct Movement: Codable, Sendable, Equatable {
      let floorsAscended: FloorsAscended?
      let floorsDescended: [String: JSONValue]?
      let pushes: [String: JSONValue]?
      let steps: Steps?

      private enum CodingKeys: String, CodingKey {
        case floorsAscended
        case floorsDescended
        case pushes
        case steps
      }

      nonisolated struct FloorsAscended: Codable, Sendable, Equatable {
        let goal: Int64?

        private enum CodingKeys: String, CodingKey {
          case goal
        }
      }
      nonisolated struct Steps: Codable, Sendable, Equatable {
        let distanceInMeters: Double?
        let goal: Int64?
        let value: Int64?

        private enum CodingKeys: String, CodingKey {
          case distanceInMeters
          case goal
          case value
        }
      }
    }
    nonisolated struct Respiration: Codable, Sendable, Equatable {
      let algorithmVersion: Int64?
      let avgValue: Int64?
      let latestTimestampGmt: String?
      let latestValue: Int64?
      let maxValue: Int64?
      let minValue: Int64?

      private enum CodingKeys: String, CodingKey {
        case algorithmVersion
        case avgValue
        case latestTimestampGmt
        case latestValue
        case maxValue
        case minValue
      }
    }
    nonisolated struct Stress: Codable, Sendable, Equatable {
      let activityDurationInMillis: Int64?
      let activityProportion: Double?
      let avgLevel: Int64?
      let highStressDurationInMillis: Int64?
      let highStressProportion: Double?
      let lowStressDurationInMillis: Int64?
      let lowStressProportion: Double?
      let maxLevel: Int64?
      let mediumStressDurationInMillis: Int64?
      let mediumStressProportion: Double?
      let qualifier: String?
      let restDurationInMillis: Int64?
      let restProportion: Double?
      let totalDurationInMillis: Int64?
      let uncategorizedDurationInMillis: Int64?
      let uncategorizedProportion: Double?

      private enum CodingKeys: String, CodingKey {
        case activityDurationInMillis
        case activityProportion
        case avgLevel
        case highStressDurationInMillis
        case highStressProportion
        case lowStressDurationInMillis
        case lowStressProportion
        case maxLevel
        case mediumStressDurationInMillis
        case mediumStressProportion
        case qualifier
        case restDurationInMillis
        case restProportion
        case totalDurationInMillis
        case uncategorizedDurationInMillis
        case uncategorizedProportion
      }
    }
    nonisolated struct WellnessChronology: Codable, Sendable, Equatable {
      let endTimestampGmt: String?
      let endTimestampLocal: String?
      let startTimestampGmt: String?
      let startTimestampLocal: String?
      let totalDurationInMillis: Int64?

      private enum CodingKeys: String, CodingKey {
        case endTimestampGmt
        case endTimestampLocal
        case startTimestampGmt
        case startTimestampLocal
        case totalDurationInMillis
      }
    }

    init(
      bodyBattery: BodyBattery? = nil,
      calendarDate: DateKey? = nil,
      calories: Calories? = nil,
      heartRate: HeartRate? = nil,
      hydration: Hydration? = nil,
      includesActivityData: Bool? = nil,
      includesWellnessData: Bool? = nil,
      intensityMinutes: IntensityMinutes? = nil,
      jetLag: [String: JSONValue]? = nil,
      movement: Movement? = nil,
      pulseOx: [String: JSONValue]? = nil,
      respiration: Respiration? = nil,
      source: String? = nil,
      stress: Stress? = nil,
      userProfileID: Int64? = nil,
      uuid: String? = nil,
      wellnessChronology: WellnessChronology? = nil
    ) {
      self.bodyBattery = bodyBattery
      self.calendarDate = calendarDate
      self.calories = calories
      self.heartRate = heartRate
      self.hydration = hydration
      self.includesActivityData = includesActivityData
      self.includesWellnessData = includesWellnessData
      self.intensityMinutes = intensityMinutes
      self.jetLag = jetLag
      self.movement = movement
      self.pulseOx = pulseOx
      self.respiration = respiration
      self.source = source
      self.stress = stress
      self.userProfileID = userProfileID
      self.uuid = uuid
      self.wellnessChronology = wellnessChronology
    }

    static func == (lhs: DataElement, rhs: DataElement) -> Bool {
      lhs === rhs
        || (lhs.bodyBattery == rhs.bodyBattery
          && lhs.calendarDate == rhs.calendarDate
          && lhs.calories == rhs.calories
          && lhs.heartRate == rhs.heartRate
          && lhs.hydration == rhs.hydration
          && lhs.includesActivityData == rhs.includesActivityData
          && lhs.includesWellnessData == rhs.includesWellnessData
          && lhs.intensityMinutes == rhs.intensityMinutes
          && lhs.jetLag == rhs.jetLag
          && lhs.movement == rhs.movement
          && lhs.pulseOx == rhs.pulseOx
          && lhs.respiration == rhs.respiration
          && lhs.source == rhs.source
          && lhs.stress == rhs.stress
          && lhs.userProfileID == rhs.userProfileID
          && lhs.uuid == rhs.uuid
          && lhs.wellnessChronology == rhs.wellnessChronology)
    }
  }
}
