import Foundation

@MainActor
final class ReminderScheduler {
  private let center: any ReminderNotifying
  private var tail: Task<Void, Never>?
  private var generation = UUID()
  private var completed: Set<String> = []
  private var latest: Plan?

  private struct Plan {
    let preferences: ReminderPreferencesSnapshot
    let completed: Set<String>
    let now: Date
    let calendar: Calendar
  }

  init(center: any ReminderNotifying) { self.center = center }

  func reconcile(
    preferences: ReminderPreferencesSnapshot, completed: Set<String>, now: Date,
    calendar: Calendar
  ) async throws {
    self.completed.formUnion(completed)
    let plan = Plan(
      preferences: preferences, completed: self.completed, now: now, calendar: calendar)
    latest = plan
    let ticket = UUID()
    generation = ticket
    try await enqueue {
      guard self.generation == ticket else { return }
      let allowed = await self.center.authorization() == .allowed
      guard self.generation == ticket else { return }
      let desired = try ReminderPlanner.requests(
        preferences: allowed ? plan.preferences : .defaults, completed: plan.completed,
        now: plan.now, calendar: plan.calendar)
      let pending = await self.center.pending()
      guard self.generation == ticket else { return }
      let byID = Dictionary(
        pending.map { ($0.identifier, $0) }, uniquingKeysWith: { first, _ in first })
      let desiredIDs = Set(desired.map(\.identifier))
      let obsolete = pending.filter { !desiredIDs.contains($0.identifier) }
        .map(\.identifier).filter { MorningReminderRequest.parse($0) != nil }
      if !obsolete.isEmpty { await self.center.remove(obsolete) }
      for request in desired {
        guard self.generation == ticket else { return }
        if byID[request.identifier] != request { try await self.center.add(request) }
      }
    }
  }

  func checkInCompleted(dayID: String, now: Date, calendar: Calendar) async throws {
    completed.insert(dayID)
    if let latest {
      try await reconcile(
        preferences: latest.preferences, completed: completed, now: now, calendar: calendar)
    } else {
      generation = UUID()
      let identifier = MorningReminderRequest(dayID: dayID, kind: .missed, fireDate: now).identifier
      try await enqueue { await self.center.remove([identifier]) }
    }
  }

  #if DEBUG
    func verificationReminder(now: Date, calendar: Calendar) async throws {
      let request = MorningReminderRequest(
        dayID: MorningDay(containing: now, calendar: calendar).id,
        kind: .first, fireDate: now.addingTimeInterval(8))
      try await enqueue { try await self.center.add(request) }
    }
  #endif

  private func enqueue(_ operation: @escaping @MainActor () async throws -> Void) async throws {
    let previous = tail
    let work = Task {
      await previous?.value
      try await operation()
    }
    tail = Task { _ = try? await work.value }
    try await work.value
  }
}
