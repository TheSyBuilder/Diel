#if DEBUG
  import Foundation

  /// Original bundled responses only. Never discovers files outside the app bundle.
  nonisolated enum FixtureDataProvider {
    struct Loaded: Sendable {
      let revision: CredentialRevision
      let referenceDate: Date
      let dayCount: Int
    }

    static func load(into store: GarminStore, bundle: Bundle = .main) async throws -> Loaded {
      let revision = CredentialRevision()
      let names: [(String, GarminEndpoint)] = try inventory()
      var responses: [(GarminEndpoint, Data, GarminPayload)] = []
      var dates: [DateKey] = []
      for (name, endpoint) in names {
        guard let url = bundle.url(forResource: name, withExtension: nil, subdirectory: "fixtures")
        else { throw GarminStoreError.openFailed }
        let bytes = try Data(contentsOf: url)
        let payload = try GarminPayload.decode(bytes, as: endpoint.family)
        responses.append((endpoint, bytes, payload))
        if case .dailySummaries(let summary) = payload {
          guard let days = summary.data else { throw GarminStoreError.invalidResponse }
          dates += days.compactMap(\.calendarDate)
        }
      }
      guard let first = dates.min(), let last = dates.max() else {
        throw GarminStoreError.invalidResponse
      }
      let formatter = DateFormatter()
      formatter.calendar = Calendar(identifier: .gregorian)
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.timeZone = TimeZone(secondsFromGMT: 0)
      formatter.dateFormat = "yyyy-MM-dd"
      guard let lastDate = formatter.date(from: last.rawValue) else {
        throw GarminStoreError.invalidResponse
      }
      // Chosen fixture-bound instant after the last sample, matching unit-test chronology.
      let capturedAt = lastDate.addingTimeInterval(12 * 60 * 60 + 10 * 60)
      // Keep the default Home on the latest night with sleep and HRV fixtures.
      guard let referenceDate = formatter.date(from: "2026-11-04") else {
        throw GarminStoreError.invalidResponse
      }
      try await store.setActiveRevision(revision)
      for (endpoint, bytes, payload) in responses {
        try await store.ingest(
          GarminResponse(
            endpoint: endpoint, revision: revision, fetchedAt: capturedAt,
            rawData: bytes, payload: payload))
      }
      let count = try await store.days(in: first...last, revision: revision).count
      return Loaded(revision: revision, referenceDate: referenceDate, dayCount: count)
    }

    private static func inventory() throws -> [(String, GarminEndpoint)] {
      let first = try DateKey("2026-10-05")
      let last = try DateKey("2026-11-05")
      let originalFirst = try DateKey("2026-10-08")
      let originalLast = try DateKey("2026-11-04")
      var values: [(String, GarminEndpoint)] = [
        (
          "sleep-summaries.json",
          .sleepSummaries(start: originalFirst, end: originalLast)
        ),
        ("hrv-summaries.json", .hrvSummaries(start: originalFirst, end: originalLast)),
        ("body-battery.json", .bodyBattery(start: originalFirst, end: originalLast)),
        ("stress.json", .stress(start: originalFirst, end: originalLast)),
        ("daily-summaries-2026-10-05-to-2026-11-05.json", .dailySummaries(start: first, end: last)),
        (
          "activities-2026-10-05-to-2026-11-05.json",
          .activities(start: first, end: last, offset: 0, limit: 99)
        ),
        ("activity-1000000001.json", .activity(1_000_000_001)),
        ("activity-1000000001-workouts.json", .workouts(1_000_000_001)),
        ("activity-1000000001.zip", .archive(1_000_000_001)),
        ("steps.json", .steps(start: originalFirst, end: originalLast)),
      ]
      for label in ["2026-11-02", "2026-11-03", "2026-11-04"] {
        let date = try DateKey(label)
        values += [
          ("sleep-\(label).json", .sleep(date)), ("hrv-\(label).json", .hrv(date)),
          ("spo2-\(label).json", .spo2(date)),
        ]
      }
      let heartDates =
        (5...31).map { String(format: "2026-10-%02d", $0) }
        + (1...5).map { String(format: "2026-11-%02d", $0) }
      for label in heartDates {
        values.append(("heart-rate-\(label).json", .heartRate(try DateKey(label))))
      }
      return values
    }
  }

  actor SampleCredentials: CredentialStore {
    func read() -> StoredCredential? { nil }
    func save(_ key: Data) throws -> CredentialRevision { throw CredentialStoreError.invalidData }
    func remove() throws { throw CredentialStoreError.invalidData }
  }

  nonisolated struct OfflineTransport: GarminTransport {
    func send(_ request: URLRequest) async throws -> GarminHTTPResponse {
      throw GarminError.transport
    }
  }
#endif
