#if DEBUG
  import Foundation
  import ScoringKit

  /// A separate fixture-only disk location. Reopening never loads or imports fixture bytes.
  nonisolated enum OfflinePersistenceVerification {
    static func open() throws -> GarminStore {
      let arguments = ProcessInfo.processInfo.arguments
      var name = "local-first-verification"
      if let index = arguments.firstIndex(of: "--offline-store-id"),
        arguments.indices.contains(index + 1)
      {
        let candidate = arguments[index + 1]
        guard !candidate.isEmpty,
          candidate.unicodeScalars.allSatisfy({
            CharacterSet.alphanumerics.contains($0) || $0 == "-"
          })
        else { throw GarminStoreError.openFailed }
        name = candidate
      }
      let directory = try FileManager.default.url(
        for: .applicationSupportDirectory, in: .userDomainMask,
        appropriateFor: nil, create: true
      ).appending(path: "DielOfflineVerification/\(name)", directoryHint: .isDirectory)
      if arguments.contains("--offline-persistence-seed"),
        FileManager.default.fileExists(atPath: directory.path)
      {
        try FileManager.default.removeItem(at: directory)
      }
      return try GarminStore.persistent(at: directory.appending(path: "Diel.store"))
    }

    static func reopen(_ store: GarminStore) async throws -> FixtureDataProvider.Loaded {
      guard let revision = try await store.activeRevision() else {
        throw GarminStoreError.openFailed
      }
      let saved = try await store.savedScores(revision: revision)
      // Raw fixtures can extend beyond the last scored sample morning.
      guard let last = saved.map(\.input.date).max() else { throw GarminStoreError.openFailed }
      let days = try await store.days(
        in: DateKey("0001-01-01")...DateKey("9999-12-31"), revision: revision)
      let components = last.rawValue.split(separator: "-").compactMap { Int($0) }
      var calendar = Calendar(identifier: .gregorian)
      calendar.timeZone = TimeZone(secondsFromGMT: 0)!
      guard
        let reference = calendar.date(
          from: DateComponents(year: components[0], month: components[1], day: components[2]))
      else { throw GarminStoreError.openFailed }
      return FixtureDataProvider.Loaded(
        revision: revision, referenceDate: reference, dayCount: days.count)
    }
  }
#endif
