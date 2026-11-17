import Foundation

/// Endpoint-specific wire shapes. Archive data remains opaque ZIP bytes.
nonisolated indirect enum GarminPayload: Codable, Sendable, Equatable {
  case sleep(SleepDTO)
  case sleepSummaries([SleepDTO])
  case hrv(HRVDTO)
  case hrvSummaries(HRVSummariesDTO)
  case heartRate(HeartRateDTO)
  case bodyBattery([BodyBatteryDTO])
  case stress([StressDTO])
  case dailySummaries(DailySummariesDTO)
  case activities([ActivityDTO])
  case activity(ActivityDetailDTO)
  case workouts([JSONValue])
  case steps([StepsDTO])
  case spo2(SpO2DTO)
  case archive(Data)

  enum Family: String, Codable, Sendable, CaseIterable {
    case sleep, sleepSummaries, hrv, hrvSummaries, heartRate, bodyBattery, stress
    case dailySummaries, activities, activity, workouts, steps, spo2, archive
  }

  static func decode(_ data: Data, as family: Family) throws -> Self {
    let decoder = JSONDecoder()
    switch family {
    case .sleep: return .sleep(try decoder.decode(SleepDTO.self, from: data))
    case .sleepSummaries: return .sleepSummaries(try decoder.decode([SleepDTO].self, from: data))
    case .hrv: return .hrv(try decoder.decode(HRVDTO.self, from: data))
    case .hrvSummaries: return .hrvSummaries(try decoder.decode(HRVSummariesDTO.self, from: data))
    case .heartRate: return .heartRate(try decoder.decode(HeartRateDTO.self, from: data))
    case .bodyBattery: return .bodyBattery(try decoder.decode([BodyBatteryDTO].self, from: data))
    case .stress: return .stress(try decoder.decode([StressDTO].self, from: data))
    case .dailySummaries:
      return .dailySummaries(try decoder.decode(DailySummariesDTO.self, from: data))
    case .activities: return .activities(try decoder.decode([ActivityDTO].self, from: data))
    case .activity: return .activity(try decoder.decode(ActivityDetailDTO.self, from: data))
    case .workouts: return .workouts(try decoder.decode([JSONValue].self, from: data))
    case .steps: return .steps(try decoder.decode([StepsDTO].self, from: data))
    case .spo2: return .spo2(try decoder.decode(SpO2DTO.self, from: data))
    case .archive: return .archive(data)
    }
  }
}
