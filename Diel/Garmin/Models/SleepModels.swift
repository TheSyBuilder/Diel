// Presence follows Garmin Swagger required lists; fixtures preserve observed wire units and types.

nonisolated final class SleepDTO: Codable, Sendable, Equatable {
  let ageGroup: String?
  let autoSleepEndTimestampGMT: JSONValue?
  let autoSleepStartTimestampGMT: JSONValue?
  let averageRespirationValue: Double?
  let averageSpO2HRSleep: Double?
  let averageSpO2Value: Double?
  let avgHeartRate: Double?
  let avgSleepStress: Double?
  let awakeCount: Int64?
  let awakeSleepSeconds: Int64?
  let breathingDisruptionSeverity: String?
  let calendarDate: DateKey?
  let dailyNapDTOS: JSONValue?
  let deepSleepSeconds: Int64?
  let deviceRemCapable: Bool?
  let highestRespirationValue: Double?
  let highestSpO2Value: Int64?
  let id: Int64?
  let kidSleepNote: String?
  let lightSleepSeconds: Int64?
  let lowestRespirationValue: Double?
  let lowestSpO2Value: Int64?
  let napTimeSeconds: Int64?
  let nextSleepNeed: NextSleepNeed?
  let numberOfEventsBelowThreshold: Int64?
  let remSleepSeconds: Int64?
  let retro: Bool?
  let sleepAlignment: SleepAlignment?
  let sleepEndTimestampGMT: Int64?
  let sleepEndTimestampLocal: Int64?
  let sleepFromDevice: Bool?
  let sleepNeed: SleepNeed?
  let sleepQualityTypeID: String?
  let sleepResultTypeID: String?
  let sleepScoreFeedback: String?
  let sleepScoreInsight: String?
  let sleepScorePersonalizedInsight: String?
  let sleepScores: SleepScores?
  let sleepStartTimestampGMT: Int64?
  let sleepStartTimestampLocal: Int64?
  let sleepTimeSeconds: Int64?
  let sleepVersion: Int64?
  let sleepWindowConfirmationType: String?
  let sleepWindowConfirmed: Bool?
  let spo2Threshold: Int64?
  let unmeasurableSleepSeconds: Int64?
  let userNote: String?
  let userProfileID: Int64?

  /// An optional parent date can be absent on legitimate sleep-need-only records.
  /// Keep the wire field unchanged so callers can distinguish inferred provenance.
  var resolvedDate: DateKey? { calendarDate ?? sleepNeed?.calendarDate }

  private enum CodingKeys: String, CodingKey {
    case ageGroup
    case autoSleepEndTimestampGMT
    case autoSleepStartTimestampGMT
    case averageRespirationValue
    case averageSpO2HRSleep
    case averageSpO2Value
    case avgHeartRate
    case avgSleepStress
    case awakeCount
    case awakeSleepSeconds
    case breathingDisruptionSeverity
    case calendarDate
    case dailyNapDTOS
    case deepSleepSeconds
    case deviceRemCapable
    case highestRespirationValue
    case highestSpO2Value
    case id
    case kidSleepNote
    case lightSleepSeconds
    case lowestRespirationValue
    case lowestSpO2Value
    case napTimeSeconds
    case nextSleepNeed
    case numberOfEventsBelowThreshold
    case remSleepSeconds
    case retro
    case sleepAlignment
    case sleepEndTimestampGMT
    case sleepEndTimestampLocal
    case sleepFromDevice
    case sleepNeed
    case sleepQualityTypeID = "sleepQualityTypePK"
    case sleepResultTypeID = "sleepResultTypePK"
    case sleepScoreFeedback
    case sleepScoreInsight
    case sleepScorePersonalizedInsight
    case sleepScores
    case sleepStartTimestampGMT
    case sleepStartTimestampLocal
    case sleepTimeSeconds
    case sleepVersion
    case sleepWindowConfirmationType
    case sleepWindowConfirmed
    case spo2Threshold
    case unmeasurableSleepSeconds
    case userNote
    case userProfileID = "userProfilePK"
  }

  nonisolated struct NextSleepNeed: Codable, Sendable, Equatable {
    let actual: Int64?
    let baseline: Int64?
    let calendarDate: DateKey?
    let deviceId: Int64?
    let displayedForTheDay: Bool?
    let feedback: String?
    let hrvAdjustment: String?
    let napAdjustment: String?
    let preferredActivityTracker: Bool?
    let recommendedBedtimeEndMins: Int64?
    let recommendedBedtimeStartMins: Int64?
    let sleepHistoryAdjustment: String?
    let timestampGmt: String?
    let trainingFeedback: String?
    let userProfileID: Int64?

    private enum CodingKeys: String, CodingKey {
      case actual
      case baseline
      case calendarDate
      case deviceId
      case displayedForTheDay
      case feedback
      case hrvAdjustment
      case napAdjustment
      case preferredActivityTracker
      case recommendedBedtimeEndMins
      case recommendedBedtimeStartMins
      case sleepHistoryAdjustment
      case timestampGmt
      case trainingFeedback
      case userProfileID = "userProfilePk"
    }
  }
  nonisolated struct SleepAlignment: Codable, Sendable, Equatable {
    let calendarDate: DateKey?
    let deviceId: Int64?
    let isPreferredActivityTracker: Bool?
    let lastSleepMidpointMins: Int64?
    let optimalSleepWindowEndMins: Int64?
    let optimalSleepWindowMidpointMins: Int64?
    let optimalSleepWindowStartMins: Int64?
    let sleepNeedBaselineMins: Int64?
    let status: String?
    let userId: Int64?

    private enum CodingKeys: String, CodingKey {
      case calendarDate
      case deviceId
      case isPreferredActivityTracker
      case lastSleepMidpointMins
      case optimalSleepWindowEndMins
      case optimalSleepWindowMidpointMins
      case optimalSleepWindowStartMins
      case sleepNeedBaselineMins
      case status
      case userId
    }
  }
  nonisolated struct SleepNeed: Codable, Sendable, Equatable {
    let actual: Int64?
    let baseline: Int64?
    let calendarDate: DateKey?
    let deviceId: Int64?
    let displayedForTheDay: Bool?
    let feedback: String?
    let hrvAdjustment: String?
    let napAdjustment: String?
    let preferredActivityTracker: Bool?
    let recommendedBedtimeEndMins: Int64?
    let recommendedBedtimeStartMins: Int64?
    let sleepHistoryAdjustment: String?
    let timestampGmt: String?
    let trainingFeedback: String?
    let userProfileID: Int64?

    private enum CodingKeys: String, CodingKey {
      case actual
      case baseline
      case calendarDate
      case deviceId
      case displayedForTheDay
      case feedback
      case hrvAdjustment
      case napAdjustment
      case preferredActivityTracker
      case recommendedBedtimeEndMins
      case recommendedBedtimeStartMins
      case sleepHistoryAdjustment
      case timestampGmt
      case trainingFeedback
      case userProfileID = "userProfilePk"
    }
  }
  nonisolated struct SleepScores: Codable, Sendable, Equatable {
    let awakeCount: AwakeCount?
    let deepPercentage: DeepPercentage?
    let lightPercentage: LightPercentage?
    let overall: Overall?
    let remPercentage: RemPercentage?
    let restlessness: Restlessness?
    let stress: Stress?
    let totalDuration: TotalDuration?

    private enum CodingKeys: String, CodingKey {
      case awakeCount
      case deepPercentage
      case lightPercentage
      case overall
      case remPercentage
      case restlessness
      case stress
      case totalDuration
    }

    nonisolated struct AwakeCount: Codable, Sendable, Equatable {
      let optimalEnd: Double?
      let optimalStart: Double?
      let qualifierKey: String?

      private enum CodingKeys: String, CodingKey {
        case optimalEnd
        case optimalStart
        case qualifierKey
      }
    }
    nonisolated struct DeepPercentage: Codable, Sendable, Equatable {
      let idealEndInSeconds: Double?
      let idealStartInSeconds: Double?
      let optimalEnd: Double?
      let optimalStart: Double?
      let qualifierKey: String?
      let value: Int64?

      private enum CodingKeys: String, CodingKey {
        case idealEndInSeconds
        case idealStartInSeconds
        case optimalEnd
        case optimalStart
        case qualifierKey
        case value
      }
    }
    nonisolated struct LightPercentage: Codable, Sendable, Equatable {
      let idealEndInSeconds: Double?
      let idealStartInSeconds: Double?
      let optimalEnd: Double?
      let optimalStart: Double?
      let qualifierKey: String?
      let value: Int64?

      private enum CodingKeys: String, CodingKey {
        case idealEndInSeconds
        case idealStartInSeconds
        case optimalEnd
        case optimalStart
        case qualifierKey
        case value
      }
    }
    nonisolated struct Overall: Codable, Sendable, Equatable {
      let qualifierKey: String?
      let value: Int64?

      private enum CodingKeys: String, CodingKey {
        case qualifierKey
        case value
      }
    }
    nonisolated struct RemPercentage: Codable, Sendable, Equatable {
      let idealEndInSeconds: Double?
      let idealStartInSeconds: Double?
      let optimalEnd: Double?
      let optimalStart: Double?
      let qualifierKey: String?
      let value: Int64?

      private enum CodingKeys: String, CodingKey {
        case idealEndInSeconds
        case idealStartInSeconds
        case optimalEnd
        case optimalStart
        case qualifierKey
        case value
      }
    }
    nonisolated struct Restlessness: Codable, Sendable, Equatable {
      let optimalEnd: Double?
      let optimalStart: Double?
      let qualifierKey: String?

      private enum CodingKeys: String, CodingKey {
        case optimalEnd
        case optimalStart
        case qualifierKey
      }
    }
    nonisolated struct Stress: Codable, Sendable, Equatable {
      let optimalEnd: Double?
      let optimalStart: Double?
      let qualifierKey: String?

      private enum CodingKeys: String, CodingKey {
        case optimalEnd
        case optimalStart
        case qualifierKey
      }
    }
    nonisolated struct TotalDuration: Codable, Sendable, Equatable {
      let optimalEnd: Double?
      let optimalStart: Double?
      let qualifierKey: String?

      private enum CodingKeys: String, CodingKey {
        case optimalEnd
        case optimalStart
        case qualifierKey
      }
    }
  }

  init(
    ageGroup: String? = nil,
    autoSleepEndTimestampGMT: JSONValue? = nil,
    autoSleepStartTimestampGMT: JSONValue? = nil,
    averageRespirationValue: Double? = nil,
    averageSpO2HRSleep: Double? = nil,
    averageSpO2Value: Double? = nil,
    avgHeartRate: Double? = nil,
    avgSleepStress: Double? = nil,
    awakeCount: Int64? = nil,
    awakeSleepSeconds: Int64? = nil,
    breathingDisruptionSeverity: String? = nil,
    calendarDate: DateKey? = nil,
    dailyNapDTOS: JSONValue? = nil,
    deepSleepSeconds: Int64? = nil,
    deviceRemCapable: Bool? = nil,
    highestRespirationValue: Double? = nil,
    highestSpO2Value: Int64? = nil,
    id: Int64? = nil,
    kidSleepNote: String? = nil,
    lightSleepSeconds: Int64? = nil,
    lowestRespirationValue: Double? = nil,
    lowestSpO2Value: Int64? = nil,
    napTimeSeconds: Int64? = nil,
    nextSleepNeed: NextSleepNeed? = nil,
    numberOfEventsBelowThreshold: Int64? = nil,
    remSleepSeconds: Int64? = nil,
    retro: Bool? = nil,
    sleepAlignment: SleepAlignment? = nil,
    sleepEndTimestampGMT: Int64? = nil,
    sleepEndTimestampLocal: Int64? = nil,
    sleepFromDevice: Bool? = nil,
    sleepNeed: SleepNeed? = nil,
    sleepQualityTypeID: String? = nil,
    sleepResultTypeID: String? = nil,
    sleepScoreFeedback: String? = nil,
    sleepScoreInsight: String? = nil,
    sleepScorePersonalizedInsight: String? = nil,
    sleepScores: SleepScores? = nil,
    sleepStartTimestampGMT: Int64? = nil,
    sleepStartTimestampLocal: Int64? = nil,
    sleepTimeSeconds: Int64? = nil,
    sleepVersion: Int64? = nil,
    sleepWindowConfirmationType: String? = nil,
    sleepWindowConfirmed: Bool? = nil,
    spo2Threshold: Int64? = nil,
    unmeasurableSleepSeconds: Int64? = nil,
    userNote: String? = nil,
    userProfileID: Int64? = nil
  ) {
    self.ageGroup = ageGroup
    self.autoSleepEndTimestampGMT = autoSleepEndTimestampGMT
    self.autoSleepStartTimestampGMT = autoSleepStartTimestampGMT
    self.averageRespirationValue = averageRespirationValue
    self.averageSpO2HRSleep = averageSpO2HRSleep
    self.averageSpO2Value = averageSpO2Value
    self.avgHeartRate = avgHeartRate
    self.avgSleepStress = avgSleepStress
    self.awakeCount = awakeCount
    self.awakeSleepSeconds = awakeSleepSeconds
    self.breathingDisruptionSeverity = breathingDisruptionSeverity
    self.calendarDate = calendarDate
    self.dailyNapDTOS = dailyNapDTOS
    self.deepSleepSeconds = deepSleepSeconds
    self.deviceRemCapable = deviceRemCapable
    self.highestRespirationValue = highestRespirationValue
    self.highestSpO2Value = highestSpO2Value
    self.id = id
    self.kidSleepNote = kidSleepNote
    self.lightSleepSeconds = lightSleepSeconds
    self.lowestRespirationValue = lowestRespirationValue
    self.lowestSpO2Value = lowestSpO2Value
    self.napTimeSeconds = napTimeSeconds
    self.nextSleepNeed = nextSleepNeed
    self.numberOfEventsBelowThreshold = numberOfEventsBelowThreshold
    self.remSleepSeconds = remSleepSeconds
    self.retro = retro
    self.sleepAlignment = sleepAlignment
    self.sleepEndTimestampGMT = sleepEndTimestampGMT
    self.sleepEndTimestampLocal = sleepEndTimestampLocal
    self.sleepFromDevice = sleepFromDevice
    self.sleepNeed = sleepNeed
    self.sleepQualityTypeID = sleepQualityTypeID
    self.sleepResultTypeID = sleepResultTypeID
    self.sleepScoreFeedback = sleepScoreFeedback
    self.sleepScoreInsight = sleepScoreInsight
    self.sleepScorePersonalizedInsight = sleepScorePersonalizedInsight
    self.sleepScores = sleepScores
    self.sleepStartTimestampGMT = sleepStartTimestampGMT
    self.sleepStartTimestampLocal = sleepStartTimestampLocal
    self.sleepTimeSeconds = sleepTimeSeconds
    self.sleepVersion = sleepVersion
    self.sleepWindowConfirmationType = sleepWindowConfirmationType
    self.sleepWindowConfirmed = sleepWindowConfirmed
    self.spo2Threshold = spo2Threshold
    self.unmeasurableSleepSeconds = unmeasurableSleepSeconds
    self.userNote = userNote
    self.userProfileID = userProfileID
  }

  static func == (lhs: SleepDTO, rhs: SleepDTO) -> Bool {
    lhs === rhs
      || (lhs.ageGroup == rhs.ageGroup
        && lhs.autoSleepEndTimestampGMT == rhs.autoSleepEndTimestampGMT
        && lhs.autoSleepStartTimestampGMT == rhs.autoSleepStartTimestampGMT
        && lhs.averageRespirationValue == rhs.averageRespirationValue
        && lhs.averageSpO2HRSleep == rhs.averageSpO2HRSleep
        && lhs.averageSpO2Value == rhs.averageSpO2Value
        && lhs.avgHeartRate == rhs.avgHeartRate
        && lhs.avgSleepStress == rhs.avgSleepStress
        && lhs.awakeCount == rhs.awakeCount
        && lhs.awakeSleepSeconds == rhs.awakeSleepSeconds
        && lhs.breathingDisruptionSeverity == rhs.breathingDisruptionSeverity
        && lhs.calendarDate == rhs.calendarDate
        && lhs.dailyNapDTOS == rhs.dailyNapDTOS
        && lhs.deepSleepSeconds == rhs.deepSleepSeconds
        && lhs.deviceRemCapable == rhs.deviceRemCapable
        && lhs.highestRespirationValue == rhs.highestRespirationValue
        && lhs.highestSpO2Value == rhs.highestSpO2Value
        && lhs.id == rhs.id
        && lhs.kidSleepNote == rhs.kidSleepNote
        && lhs.lightSleepSeconds == rhs.lightSleepSeconds
        && lhs.lowestRespirationValue == rhs.lowestRespirationValue
        && lhs.lowestSpO2Value == rhs.lowestSpO2Value
        && lhs.napTimeSeconds == rhs.napTimeSeconds
        && lhs.nextSleepNeed == rhs.nextSleepNeed
        && lhs.numberOfEventsBelowThreshold == rhs.numberOfEventsBelowThreshold
        && lhs.remSleepSeconds == rhs.remSleepSeconds
        && lhs.retro == rhs.retro
        && lhs.sleepAlignment == rhs.sleepAlignment
        && lhs.sleepEndTimestampGMT == rhs.sleepEndTimestampGMT
        && lhs.sleepEndTimestampLocal == rhs.sleepEndTimestampLocal
        && lhs.sleepFromDevice == rhs.sleepFromDevice
        && lhs.sleepNeed == rhs.sleepNeed
        && lhs.sleepQualityTypeID == rhs.sleepQualityTypeID
        && lhs.sleepResultTypeID == rhs.sleepResultTypeID
        && lhs.sleepScoreFeedback == rhs.sleepScoreFeedback
        && lhs.sleepScoreInsight == rhs.sleepScoreInsight
        && lhs.sleepScorePersonalizedInsight == rhs.sleepScorePersonalizedInsight
        && lhs.sleepScores == rhs.sleepScores
        && lhs.sleepStartTimestampGMT == rhs.sleepStartTimestampGMT
        && lhs.sleepStartTimestampLocal == rhs.sleepStartTimestampLocal
        && lhs.sleepTimeSeconds == rhs.sleepTimeSeconds
        && lhs.sleepVersion == rhs.sleepVersion
        && lhs.sleepWindowConfirmationType == rhs.sleepWindowConfirmationType
        && lhs.sleepWindowConfirmed == rhs.sleepWindowConfirmed
        && lhs.spo2Threshold == rhs.spo2Threshold
        && lhs.unmeasurableSleepSeconds == rhs.unmeasurableSleepSeconds
        && lhs.userNote == rhs.userNote
        && lhs.userProfileID == rhs.userProfileID)
  }
}
