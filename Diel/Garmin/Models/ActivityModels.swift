// Presence follows Garmin Swagger required lists; fixtures preserve observed wire units and types.

nonisolated final class ActivityDTO: Codable, Sendable, Equatable {
  let activityId: Int64?
  let activityName: String?
  let activityTrainingLoad: Double?
  let activityType: ActivityType?
  let activityUUID: String?
  let aerobicTrainingEffect: Double?
  let aerobicTrainingEffectMessage: String?
  let anaerobicTrainingEffect: Double?
  let anaerobicTrainingEffectMessage: String?
  let autoCalcCalories: Bool?
  let averageHR: Double?
  let averageSpeed: Double?
  let avgElevation: Double?
  let avgStrideLength: Double?
  let beginTimestamp: Int64?
  let bmrCalories: Double?
  let calories: Double?
  let decoDive: Bool?
  let differenceBodyBattery: Int64?
  let distance: Double?
  let duration: Double?
  let elapsedDuration: Double?
  let elevationCorrected: Bool?
  let elevationGain: Double?
  let elevationLoss: Double?
  let endLatitude: Double?
  let endLongitude: Double?
  let endTimeGMT: String?
  let eventType: EventType?
  let favorite: Bool?
  let hasImages: Bool?
  let hasVideo: Bool?
  let hrTimeInZone1: Double?
  let hrTimeInZone2: Double?
  let hrTimeInZone3: Double?
  let hrTimeInZone4: Double?
  let hrTimeInZone5: Double?
  let isAutoCalcCalories: Bool?
  let isDecoDive: Bool?
  let isElevationCorrected: Bool?
  let isFavorite: Bool?
  let isManualActivity: Bool?
  let isPR: Bool?
  let isParent: Bool?
  let lapCount: Int64?
  let locationName: String?
  let manualActivity: Bool?
  let manufacturer: String?
  let maxDoubleCadence: Double?
  let maxElevation: Double?
  let maxHR: Double?
  let maxSpeed: Double?
  let maxVerticalSpeed: Double?
  let minActivityLapDuration: Double?
  let minElevation: Double?
  let moderateIntensityMinutes: Int64?
  let movingDuration: Double?
  let ownerDisplayName: String?
  let ownerFullName: String?
  let ownerId: Int64?
  let ownerProfileImageUrlLarge: String?
  let ownerProfileImageUrlMedium: String?
  let ownerProfileImageUrlSmall: String?
  let parent: Bool?
  let pr: Bool?
  let privacy: Privacy?
  let qualifyingDive: Bool?
  let splitSummaries: [SplitSummariesElement]?
  let sportTypeId: Int64?
  let startLatitude: Double?
  let startLongitude: Double?
  let startTimeGMT: String?
  let startTimeLocal: String?
  let steps: Int64?
  let summarizedDiveInfo: SummarizedDiveInfo?
  let trainingEffectLabel: String?
  let vigorousIntensityMinutes: Int64?
  let waterEstimated: Double?

  private enum CodingKeys: String, CodingKey {
    case activityId
    case activityName
    case activityTrainingLoad
    case activityType
    case activityUUID
    case aerobicTrainingEffect
    case aerobicTrainingEffectMessage
    case anaerobicTrainingEffect
    case anaerobicTrainingEffectMessage
    case autoCalcCalories
    case averageHR
    case averageSpeed
    case avgElevation
    case avgStrideLength
    case beginTimestamp
    case bmrCalories
    case calories
    case decoDive
    case differenceBodyBattery
    case distance
    case duration
    case elapsedDuration
    case elevationCorrected
    case elevationGain
    case elevationLoss
    case endLatitude
    case endLongitude
    case endTimeGMT
    case eventType
    case favorite
    case hasImages
    case hasVideo
    case hrTimeInZone1 = "hrTimeInZone_1"
    case hrTimeInZone2 = "hrTimeInZone_2"
    case hrTimeInZone3 = "hrTimeInZone_3"
    case hrTimeInZone4 = "hrTimeInZone_4"
    case hrTimeInZone5 = "hrTimeInZone_5"
    case isAutoCalcCalories
    case isDecoDive
    case isElevationCorrected
    case isFavorite
    case isManualActivity
    case isPR
    case isParent
    case lapCount
    case locationName
    case manualActivity
    case manufacturer
    case maxDoubleCadence
    case maxElevation
    case maxHR
    case maxSpeed
    case maxVerticalSpeed
    case minActivityLapDuration
    case minElevation
    case moderateIntensityMinutes
    case movingDuration
    case ownerDisplayName
    case ownerFullName
    case ownerId
    case ownerProfileImageUrlLarge
    case ownerProfileImageUrlMedium
    case ownerProfileImageUrlSmall
    case parent
    case pr
    case privacy
    case qualifyingDive
    case splitSummaries
    case sportTypeId
    case startLatitude
    case startLongitude
    case startTimeGMT
    case startTimeLocal
    case steps
    case summarizedDiveInfo
    case trainingEffectLabel
    case vigorousIntensityMinutes
    case waterEstimated
  }

  nonisolated struct ActivityType: Codable, Sendable, Equatable {
    let parentTypeId: Int64?
    let typeId: Int64?
    let typeKey: String?

    private enum CodingKeys: String, CodingKey {
      case parentTypeId
      case typeId
      case typeKey
    }
  }
  nonisolated struct EventType: Codable, Sendable, Equatable {
    let typeId: Int64?
    let typeKey: String?

    private enum CodingKeys: String, CodingKey {
      case typeId
      case typeKey
    }
  }
  nonisolated struct Privacy: Codable, Sendable, Equatable {
    let typeId: Int64?
    let typeKey: String?

    private enum CodingKeys: String, CodingKey {
      case typeId
      case typeKey
    }
  }
  nonisolated struct SplitSummariesElement: Codable, Sendable, Equatable {
    let averageElevationGain: Double?
    let duration: Double?
    let maxElevationGain: Double?
    let noOfSplits: Int64?
    let numClimbSends: Int64?
    let numFalls: Int64?
    let splitType: String?
    let totalAscent: Double?

    private enum CodingKeys: String, CodingKey {
      case averageElevationGain
      case duration
      case maxElevationGain
      case noOfSplits
      case numClimbSends
      case numFalls
      case splitType
      case totalAscent
    }
  }
  nonisolated struct SummarizedDiveInfo: Codable, Sendable, Equatable {
    let summarizedDiveGases: [JSONValue]?

    private enum CodingKeys: String, CodingKey {
      case summarizedDiveGases
    }
  }

  init(
    activityId: Int64? = nil,
    activityName: String? = nil,
    activityTrainingLoad: Double? = nil,
    activityType: ActivityType? = nil,
    activityUUID: String? = nil,
    aerobicTrainingEffect: Double? = nil,
    aerobicTrainingEffectMessage: String? = nil,
    anaerobicTrainingEffect: Double? = nil,
    anaerobicTrainingEffectMessage: String? = nil,
    autoCalcCalories: Bool? = nil,
    averageHR: Double? = nil,
    averageSpeed: Double? = nil,
    avgElevation: Double? = nil,
    avgStrideLength: Double? = nil,
    beginTimestamp: Int64? = nil,
    bmrCalories: Double? = nil,
    calories: Double? = nil,
    decoDive: Bool? = nil,
    differenceBodyBattery: Int64? = nil,
    distance: Double? = nil,
    duration: Double? = nil,
    elapsedDuration: Double? = nil,
    elevationCorrected: Bool? = nil,
    elevationGain: Double? = nil,
    elevationLoss: Double? = nil,
    endLatitude: Double? = nil,
    endLongitude: Double? = nil,
    endTimeGMT: String? = nil,
    eventType: EventType? = nil,
    favorite: Bool? = nil,
    hasImages: Bool? = nil,
    hasVideo: Bool? = nil,
    hrTimeInZone1: Double? = nil,
    hrTimeInZone2: Double? = nil,
    hrTimeInZone3: Double? = nil,
    hrTimeInZone4: Double? = nil,
    hrTimeInZone5: Double? = nil,
    isAutoCalcCalories: Bool? = nil,
    isDecoDive: Bool? = nil,
    isElevationCorrected: Bool? = nil,
    isFavorite: Bool? = nil,
    isManualActivity: Bool? = nil,
    isPR: Bool? = nil,
    isParent: Bool? = nil,
    lapCount: Int64? = nil,
    locationName: String? = nil,
    manualActivity: Bool? = nil,
    manufacturer: String? = nil,
    maxDoubleCadence: Double? = nil,
    maxElevation: Double? = nil,
    maxHR: Double? = nil,
    maxSpeed: Double? = nil,
    maxVerticalSpeed: Double? = nil,
    minActivityLapDuration: Double? = nil,
    minElevation: Double? = nil,
    moderateIntensityMinutes: Int64? = nil,
    movingDuration: Double? = nil,
    ownerDisplayName: String? = nil,
    ownerFullName: String? = nil,
    ownerId: Int64? = nil,
    ownerProfileImageUrlLarge: String? = nil,
    ownerProfileImageUrlMedium: String? = nil,
    ownerProfileImageUrlSmall: String? = nil,
    parent: Bool? = nil,
    pr: Bool? = nil,
    privacy: Privacy? = nil,
    qualifyingDive: Bool? = nil,
    splitSummaries: [SplitSummariesElement]? = nil,
    sportTypeId: Int64? = nil,
    startLatitude: Double? = nil,
    startLongitude: Double? = nil,
    startTimeGMT: String? = nil,
    startTimeLocal: String? = nil,
    steps: Int64? = nil,
    summarizedDiveInfo: SummarizedDiveInfo? = nil,
    trainingEffectLabel: String? = nil,
    vigorousIntensityMinutes: Int64? = nil,
    waterEstimated: Double? = nil
  ) {
    self.activityId = activityId
    self.activityName = activityName
    self.activityTrainingLoad = activityTrainingLoad
    self.activityType = activityType
    self.activityUUID = activityUUID
    self.aerobicTrainingEffect = aerobicTrainingEffect
    self.aerobicTrainingEffectMessage = aerobicTrainingEffectMessage
    self.anaerobicTrainingEffect = anaerobicTrainingEffect
    self.anaerobicTrainingEffectMessage = anaerobicTrainingEffectMessage
    self.autoCalcCalories = autoCalcCalories
    self.averageHR = averageHR
    self.averageSpeed = averageSpeed
    self.avgElevation = avgElevation
    self.avgStrideLength = avgStrideLength
    self.beginTimestamp = beginTimestamp
    self.bmrCalories = bmrCalories
    self.calories = calories
    self.decoDive = decoDive
    self.differenceBodyBattery = differenceBodyBattery
    self.distance = distance
    self.duration = duration
    self.elapsedDuration = elapsedDuration
    self.elevationCorrected = elevationCorrected
    self.elevationGain = elevationGain
    self.elevationLoss = elevationLoss
    self.endLatitude = endLatitude
    self.endLongitude = endLongitude
    self.endTimeGMT = endTimeGMT
    self.eventType = eventType
    self.favorite = favorite
    self.hasImages = hasImages
    self.hasVideo = hasVideo
    self.hrTimeInZone1 = hrTimeInZone1
    self.hrTimeInZone2 = hrTimeInZone2
    self.hrTimeInZone3 = hrTimeInZone3
    self.hrTimeInZone4 = hrTimeInZone4
    self.hrTimeInZone5 = hrTimeInZone5
    self.isAutoCalcCalories = isAutoCalcCalories
    self.isDecoDive = isDecoDive
    self.isElevationCorrected = isElevationCorrected
    self.isFavorite = isFavorite
    self.isManualActivity = isManualActivity
    self.isPR = isPR
    self.isParent = isParent
    self.lapCount = lapCount
    self.locationName = locationName
    self.manualActivity = manualActivity
    self.manufacturer = manufacturer
    self.maxDoubleCadence = maxDoubleCadence
    self.maxElevation = maxElevation
    self.maxHR = maxHR
    self.maxSpeed = maxSpeed
    self.maxVerticalSpeed = maxVerticalSpeed
    self.minActivityLapDuration = minActivityLapDuration
    self.minElevation = minElevation
    self.moderateIntensityMinutes = moderateIntensityMinutes
    self.movingDuration = movingDuration
    self.ownerDisplayName = ownerDisplayName
    self.ownerFullName = ownerFullName
    self.ownerId = ownerId
    self.ownerProfileImageUrlLarge = ownerProfileImageUrlLarge
    self.ownerProfileImageUrlMedium = ownerProfileImageUrlMedium
    self.ownerProfileImageUrlSmall = ownerProfileImageUrlSmall
    self.parent = parent
    self.pr = pr
    self.privacy = privacy
    self.qualifyingDive = qualifyingDive
    self.splitSummaries = splitSummaries
    self.sportTypeId = sportTypeId
    self.startLatitude = startLatitude
    self.startLongitude = startLongitude
    self.startTimeGMT = startTimeGMT
    self.startTimeLocal = startTimeLocal
    self.steps = steps
    self.summarizedDiveInfo = summarizedDiveInfo
    self.trainingEffectLabel = trainingEffectLabel
    self.vigorousIntensityMinutes = vigorousIntensityMinutes
    self.waterEstimated = waterEstimated
  }

  static func == (lhs: ActivityDTO, rhs: ActivityDTO) -> Bool {
    lhs === rhs
      || (lhs.activityId == rhs.activityId
        && lhs.activityName == rhs.activityName
        && lhs.activityTrainingLoad == rhs.activityTrainingLoad
        && lhs.activityType == rhs.activityType
        && lhs.activityUUID == rhs.activityUUID
        && lhs.aerobicTrainingEffect == rhs.aerobicTrainingEffect
        && lhs.aerobicTrainingEffectMessage == rhs.aerobicTrainingEffectMessage
        && lhs.anaerobicTrainingEffect == rhs.anaerobicTrainingEffect
        && lhs.anaerobicTrainingEffectMessage == rhs.anaerobicTrainingEffectMessage
        && lhs.autoCalcCalories == rhs.autoCalcCalories
        && lhs.averageHR == rhs.averageHR
        && lhs.averageSpeed == rhs.averageSpeed
        && lhs.avgElevation == rhs.avgElevation
        && lhs.avgStrideLength == rhs.avgStrideLength
        && lhs.beginTimestamp == rhs.beginTimestamp
        && lhs.bmrCalories == rhs.bmrCalories
        && lhs.calories == rhs.calories
        && lhs.decoDive == rhs.decoDive
        && lhs.differenceBodyBattery == rhs.differenceBodyBattery
        && lhs.distance == rhs.distance
        && lhs.duration == rhs.duration
        && lhs.elapsedDuration == rhs.elapsedDuration
        && lhs.elevationCorrected == rhs.elevationCorrected
        && lhs.elevationGain == rhs.elevationGain
        && lhs.elevationLoss == rhs.elevationLoss
        && lhs.endLatitude == rhs.endLatitude
        && lhs.endLongitude == rhs.endLongitude
        && lhs.endTimeGMT == rhs.endTimeGMT
        && lhs.eventType == rhs.eventType
        && lhs.favorite == rhs.favorite
        && lhs.hasImages == rhs.hasImages
        && lhs.hasVideo == rhs.hasVideo
        && lhs.hrTimeInZone1 == rhs.hrTimeInZone1
        && lhs.hrTimeInZone2 == rhs.hrTimeInZone2
        && lhs.hrTimeInZone3 == rhs.hrTimeInZone3
        && lhs.hrTimeInZone4 == rhs.hrTimeInZone4
        && lhs.hrTimeInZone5 == rhs.hrTimeInZone5
        && lhs.isAutoCalcCalories == rhs.isAutoCalcCalories
        && lhs.isDecoDive == rhs.isDecoDive
        && lhs.isElevationCorrected == rhs.isElevationCorrected
        && lhs.isFavorite == rhs.isFavorite
        && lhs.isManualActivity == rhs.isManualActivity
        && lhs.isPR == rhs.isPR
        && lhs.isParent == rhs.isParent
        && lhs.lapCount == rhs.lapCount
        && lhs.locationName == rhs.locationName
        && lhs.manualActivity == rhs.manualActivity
        && lhs.manufacturer == rhs.manufacturer
        && lhs.maxDoubleCadence == rhs.maxDoubleCadence
        && lhs.maxElevation == rhs.maxElevation
        && lhs.maxHR == rhs.maxHR
        && lhs.maxSpeed == rhs.maxSpeed
        && lhs.maxVerticalSpeed == rhs.maxVerticalSpeed
        && lhs.minActivityLapDuration == rhs.minActivityLapDuration
        && lhs.minElevation == rhs.minElevation
        && lhs.moderateIntensityMinutes == rhs.moderateIntensityMinutes
        && lhs.movingDuration == rhs.movingDuration
        && lhs.ownerDisplayName == rhs.ownerDisplayName
        && lhs.ownerFullName == rhs.ownerFullName
        && lhs.ownerId == rhs.ownerId
        && lhs.ownerProfileImageUrlLarge == rhs.ownerProfileImageUrlLarge
        && lhs.ownerProfileImageUrlMedium == rhs.ownerProfileImageUrlMedium
        && lhs.ownerProfileImageUrlSmall == rhs.ownerProfileImageUrlSmall
        && lhs.parent == rhs.parent
        && lhs.pr == rhs.pr
        && lhs.privacy == rhs.privacy
        && lhs.qualifyingDive == rhs.qualifyingDive
        && lhs.splitSummaries == rhs.splitSummaries
        && lhs.sportTypeId == rhs.sportTypeId
        && lhs.startLatitude == rhs.startLatitude
        && lhs.startLongitude == rhs.startLongitude
        && lhs.startTimeGMT == rhs.startTimeGMT
        && lhs.startTimeLocal == rhs.startTimeLocal
        && lhs.steps == rhs.steps
        && lhs.summarizedDiveInfo == rhs.summarizedDiveInfo
        && lhs.trainingEffectLabel == rhs.trainingEffectLabel
        && lhs.vigorousIntensityMinutes == rhs.vigorousIntensityMinutes
        && lhs.waterEstimated == rhs.waterEstimated)
  }
}

nonisolated final class ActivityDetailDTO: Codable, Sendable, Equatable {
  let accessControlRuleDTO: AccessControlRuleDTO?
  let activityId: Int64?
  let activityName: String?
  let description: String?
  let splitSummaries: [SplitSummary]?
  let activityTypeDTO: ActivityTypeDTO?
  let activityUUID: ActivityUUID?
  let eventTypeDTO: EventTypeDTO?
  let isMultiSportParent: Bool?
  let locationName: String?
  let metadataDTO: MetadataDTO?
  let summaryDTO: SummaryDTO?
  let timeZoneUnitDTO: TimeZoneUnitDTO?
  let userProfileID: Int64?

  private enum CodingKeys: String, CodingKey {
    case accessControlRuleDTO
    case activityId
    case activityName
    case description
    case splitSummaries
    case activityTypeDTO
    case activityUUID
    case eventTypeDTO
    case isMultiSportParent
    case locationName
    case metadataDTO
    case summaryDTO
    case timeZoneUnitDTO
    case userProfileID = "userProfileId"
  }

  nonisolated struct SplitSummary: Codable, Sendable, Equatable {
    let averageElevationGain: Double?
    let duration: Double?
    let elevationGain: Double?
    let maxElevationGain: Double?
    let noOfSplits: Int64?
    let numClimbSends: Int64?
    let numClimbsAttempted: Int64?
    let numClimbsCompleted: Int64?
    let numFalls: Int64?
    let splitType: String?
    let totalExerciseReps: Int64?
  }

  nonisolated struct AccessControlRuleDTO: Codable, Sendable, Equatable {
    let typeId: Int64?
    let typeKey: String?

    private enum CodingKeys: String, CodingKey {
      case typeId
      case typeKey
    }
  }
  nonisolated struct ActivityTypeDTO: Codable, Sendable, Equatable {
    let parentTypeId: Int64?
    let typeId: Int64?
    let typeKey: String?

    private enum CodingKeys: String, CodingKey {
      case parentTypeId
      case typeId
      case typeKey
    }
  }
  nonisolated struct ActivityUUID: Codable, Sendable, Equatable {
    let uuid: String?

    private enum CodingKeys: String, CodingKey {
      case uuid
    }
  }
  nonisolated struct EventTypeDTO: Codable, Sendable, Equatable {
    let typeId: Int64?
    let typeKey: String?

    private enum CodingKeys: String, CodingKey {
      case typeId
      case typeKey
    }
  }
  nonisolated struct MetadataDTO: Codable, Sendable, Equatable {
    let activityImages: [JSONValue]?
    let autoCalcCalories: Bool?
    let calendarEventInfo: JSONValue?
    let childActivityTypes: [JSONValue]?
    let childIds: [JSONValue]?
    let elevationCorrected: Bool?
    let favorite: Bool?
    let fileFormat: FileFormat?
    let gcj02: Bool?
    let hasMultiDayActivities: Bool?
    let hasRunPowerWindData: Bool?
    let isOriginal: Bool?
    let lapCount: Int64?
    let lastUpdateDate: String?
    let manualActivity: Bool?
    let manufacturer: String?
    let personalRecord: Bool?
    let runPowerWindDataEnabled: Bool?
    let sensors: JSONValue?
    let trimmed: Bool?
    let uploadedDate: String?
    let userInfoDto: UserInfoDto?
    let videoUrl: String?

    private enum CodingKeys: String, CodingKey {
      case activityImages
      case autoCalcCalories
      case calendarEventInfo
      case childActivityTypes
      case childIds
      case elevationCorrected
      case favorite
      case fileFormat
      case gcj02
      case hasMultiDayActivities
      case hasRunPowerWindData
      case isOriginal
      case lapCount
      case lastUpdateDate
      case manualActivity
      case manufacturer
      case personalRecord
      case runPowerWindDataEnabled
      case sensors
      case trimmed
      case uploadedDate
      case userInfoDto
      case videoUrl
    }

    nonisolated struct FileFormat: Codable, Sendable, Equatable {
      let formatId: Int64?
      let formatKey: String?

      private enum CodingKeys: String, CodingKey {
        case formatId
        case formatKey
      }
    }
    nonisolated struct UserInfoDto: Codable, Sendable, Equatable {
      let displayname: String?
      let fullname: String?
      let profileImageUrlLarge: String?
      let profileImageUrlMedium: String?
      let profileImageUrlSmall: String?
      let userPro: Bool?
      let userProfileID: Int64?

      private enum CodingKeys: String, CodingKey {
        case displayname
        case fullname
        case profileImageUrlLarge
        case profileImageUrlMedium
        case profileImageUrlSmall
        case userPro
        case userProfileID = "userProfilePk"
      }
    }
  }
  nonisolated struct SummaryDTO: Codable, Sendable, Equatable {
    let activityTrainingLoad: Double?
    let aerobicTrainingEffectMessage: String?
    let anaerobicTrainingEffect: Double?
    let anaerobicTrainingEffectMessage: String?
    let averageHR: Double?
    let averageMovingSpeed: Double?
    let averageRunCadence: Double?
    let averageSpeed: Double?
    let avgElevation: Double?
    let bmrCalories: Double?
    let calories: Double?
    let differenceBodyBattery: Int64?
    let distance: Double?
    let duration: Double?
    let elapsedDuration: Double?
    let elevationGain: Double?
    let elevationLoss: Double?
    let endLatitude: Double?
    let endLongitude: Double?
    let maxElevation: Double?
    let maxHR: Double?
    let maxRunCadence: Double?
    let maxSpeed: Double?
    let maxVerticalSpeed: Double?
    let minActivityLapDuration: Double?
    let minElevation: Double?
    let minHR: Double?
    let moderateIntensityMinutes: Int64?
    let movingDuration: Double?
    let startLatitude: Double?
    let startLongitude: Double?
    let startTimeGMT: String?
    let startTimeLocal: String?
    let steps: Int64?
    let trainingEffect: Double?
    let trainingEffectLabel: String?
    let vigorousIntensityMinutes: Int64?
    let waterEstimated: Double?

    private enum CodingKeys: String, CodingKey {
      case activityTrainingLoad
      case aerobicTrainingEffectMessage
      case anaerobicTrainingEffect
      case anaerobicTrainingEffectMessage
      case averageHR
      case averageMovingSpeed
      case averageRunCadence
      case averageSpeed
      case avgElevation
      case bmrCalories
      case calories
      case differenceBodyBattery
      case distance
      case duration
      case elapsedDuration
      case elevationGain
      case elevationLoss
      case endLatitude
      case endLongitude
      case maxElevation
      case maxHR
      case maxRunCadence
      case maxSpeed
      case maxVerticalSpeed
      case minActivityLapDuration
      case minElevation
      case minHR
      case moderateIntensityMinutes
      case movingDuration
      case startLatitude
      case startLongitude
      case startTimeGMT
      case startTimeLocal
      case steps
      case trainingEffect
      case trainingEffectLabel
      case vigorousIntensityMinutes
      case waterEstimated
    }
  }
  nonisolated struct TimeZoneUnitDTO: Codable, Sendable, Equatable {
    let timeZone: String?

    private enum CodingKeys: String, CodingKey {
      case timeZone
    }
  }

  init(
    accessControlRuleDTO: AccessControlRuleDTO? = nil,
    activityId: Int64? = nil,
    activityName: String? = nil,
    description: String? = nil,
    splitSummaries: [SplitSummary]? = nil,
    activityTypeDTO: ActivityTypeDTO? = nil,
    activityUUID: ActivityUUID? = nil,
    eventTypeDTO: EventTypeDTO? = nil,
    isMultiSportParent: Bool? = nil,
    locationName: String? = nil,
    metadataDTO: MetadataDTO? = nil,
    summaryDTO: SummaryDTO? = nil,
    timeZoneUnitDTO: TimeZoneUnitDTO? = nil,
    userProfileID: Int64? = nil
  ) {
    self.accessControlRuleDTO = accessControlRuleDTO
    self.activityId = activityId
    self.activityName = activityName
    self.description = description
    self.splitSummaries = splitSummaries
    self.activityTypeDTO = activityTypeDTO
    self.activityUUID = activityUUID
    self.eventTypeDTO = eventTypeDTO
    self.isMultiSportParent = isMultiSportParent
    self.locationName = locationName
    self.metadataDTO = metadataDTO
    self.summaryDTO = summaryDTO
    self.timeZoneUnitDTO = timeZoneUnitDTO
    self.userProfileID = userProfileID
  }

  static func == (lhs: ActivityDetailDTO, rhs: ActivityDetailDTO) -> Bool {
    lhs === rhs
      || (lhs.accessControlRuleDTO == rhs.accessControlRuleDTO
        && lhs.activityId == rhs.activityId
        && lhs.activityName == rhs.activityName
        && lhs.description == rhs.description
        && lhs.splitSummaries == rhs.splitSummaries
        && lhs.activityTypeDTO == rhs.activityTypeDTO
        && lhs.activityUUID == rhs.activityUUID
        && lhs.eventTypeDTO == rhs.eventTypeDTO
        && lhs.isMultiSportParent == rhs.isMultiSportParent
        && lhs.locationName == rhs.locationName
        && lhs.metadataDTO == rhs.metadataDTO
        && lhs.summaryDTO == rhs.summaryDTO
        && lhs.timeZoneUnitDTO == rhs.timeZoneUnitDTO
        && lhs.userProfileID == rhs.userProfileID)
  }
}
