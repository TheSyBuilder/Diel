import Foundation
import Observation

/// Launch and each new 4AM day must settle an actual sync attempt before a brief can be generated.
@Observable
@MainActor
final class MorningBriefSyncGate {
  private(set) var launchFinished = false
  private(set) var settledDay: MorningDay?
  @ObservationIgnored private let attempt: @MainActor () async -> Void
  @ObservationIgnored private var jobs: [String: Task<Void, Never>] = [:]
  private var requestedDay: MorningDay?

  init(attempt: @escaping @MainActor () async -> Void) { self.attempt = attempt }

  func finishLaunch(for day: MorningDay) {
    launchFinished = true
    settledDay = day
  }

  func isSettled(for day: MorningDay) -> Bool { launchFinished && settledDay == day }

  func settle(_ day: MorningDay) async {
    guard launchFinished, settledDay != day else { return }
    requestedDay = day
    let identity = "\(day.id)|\(day.start.timeIntervalSince1970)"
    let job: Task<Void, Never>
    if let existing = jobs[identity] {
      job = existing
    } else {
      let attempt = attempt
      job = Task { await attempt() }
      jobs[identity] = job
    }
    await job.value
    jobs[identity] = nil
    if requestedDay == day { settledDay = day }
  }
}
