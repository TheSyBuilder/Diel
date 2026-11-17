import Foundation
import Observation
import UIKit

@Observable
@MainActor
final class ReminderModel {
  private(set) var preferences = ReminderPreferencesSnapshot.defaults
  private(set) var hasLoaded = false
  private(set) var isWorking = false
  private(set) var errorMessage: LocalizedStringResource?
  let verificationEnabled: Bool
  @ObservationIgnored private let store: (any ReminderStoring)?
  @ObservationIgnored private let center: any ReminderNotifying
  @ObservationIgnored private let scheduler: ReminderScheduler
  @ObservationIgnored private let now: () -> Date
  @ObservationIgnored private let calendar: () -> Calendar
  @ObservationIgnored private var persistenceTail: Task<Void, Never>?
  private var intended = ReminderPreferencesSnapshot.defaults
  private var mutation = UUID()
  #if DEBUG
    @ObservationIgnored private var verificationBackgroundTask = UIBackgroundTaskIdentifier.invalid
  #endif

  init(
    store: (any ReminderStoring)?, center: any ReminderNotifying,
    verificationEnabled: Bool = false, now: @escaping () -> Date = Date.init,
    calendar: @escaping () -> Calendar = { .current }
  ) {
    self.store = store
    self.center = center
    scheduler = ReminderScheduler(center: center)
    self.now = now
    self.calendar = calendar
    #if DEBUG
      self.verificationEnabled = verificationEnabled
    #else
      self.verificationEnabled = false
    #endif
  }

  // Command bindings keep controls on the committed value until a save succeeds.
  var enabled: Bool {
    get { preferences.enabled }
    set { Task { await setEnabled(newValue) } }
  }
  var firstTime: Date {
    get { Self.time(preferences.firstMinute, calendar: calendar()) }
    set { Task { await setFirstMinute(Self.minute(newValue, calendar: calendar())) } }
  }
  var missedTime: Date {
    get { Self.time(preferences.missedMinute, calendar: calendar()) }
    set { Task { await setMissedMinute(Self.minute(newValue, calendar: calendar())) } }
  }

  func refresh() async {
    guard !isWorking else { return }
    let ticket = mutation
    do {
      guard let store else { throw ReminderError.unavailable }
      let saved = try await store.reminderPreferences()
      let completed = Set(try await store.checkInHistory().map(\.dayID))
      guard ticket == mutation, !isWorking else { return }
      preferences = saved
      intended = saved
      hasLoaded = true
      try await scheduler.reconcile(
        preferences: saved, completed: completed, now: now(), calendar: calendar())
      guard ticket == mutation else { return }
      await showPermissionOrTimeIssue(saved, ticket: ticket)
    } catch {
      guard ticket == mutation else { return }
      errorMessage =
        hasLoaded
        ? "Reminders couldn't be scheduled. Try again." : "Reminders couldn't be opened. Try again."
    }
  }

  /// This is the only code path that may request system authorization, following a toggle-on action.
  func setEnabled(_ enabled: Bool) async {
    guard hasLoaded else { return }
    let ticket = beginMutation()
    defer { finishMutation(ticket) }
    #if DEBUG
      if !enabled { endVerificationLease() }
    #endif
    if enabled {
      do {
        let status = await center.authorization()
        let allowed: Bool
        switch status {
        case .allowed: allowed = true
        case .denied: allowed = false
        case .notDetermined: allowed = try await center.requestAuthorization()
        }
        guard mutation == ticket else { return }
        guard allowed else {
          errorMessage = "Notifications are off in iPhone Settings."
          return
        }
      } catch {
        guard mutation == ticket else { return }
        errorMessage = "Notification permission couldn't be checked. Try again."
        return
      }
    }
    guard mutation == ticket else { return }
    intended.enabled = enabled
    await commit(intended, ticket: ticket)
  }

  func setFirstMinute(_ minute: Int) async {
    guard hasLoaded else { return }
    let ticket = beginMutation()
    defer { finishMutation(ticket) }
    intended.firstMinute = minute
    await commit(intended, ticket: ticket)
  }

  func setMissedMinute(_ minute: Int) async {
    guard hasLoaded else { return }
    let ticket = beginMutation()
    defer { finishMutation(ticket) }
    intended.missedMinute = minute
    await commit(intended, ticket: ticket)
  }

  func checkInCompleted(_ answer: CheckInSnapshot) async {
    #if DEBUG
      endVerificationLease()
    #endif
    do {
      try await scheduler.checkInCompleted(dayID: answer.dayID, now: now(), calendar: calendar())
    } catch { errorMessage = "Reminders couldn't be scheduled. Try again." }
  }

  #if DEBUG
    func sendVerificationReminder() async {
      guard verificationEnabled, preferences.enabled, !isWorking else { return }
      isWorking = true
      endVerificationLease()
      verificationBackgroundTask = UIApplication.shared.beginBackgroundTask(
        withName: "Offline reminder verification"
      ) { [weak self] in
        Task { @MainActor in self?.endVerificationLease() }
      }
      defer { isWorking = false }
      do {
        guard await center.authorization() == .allowed else { throw ReminderError.permissionDenied }
        try await scheduler.verificationReminder(now: now(), calendar: calendar())
      } catch {
        endVerificationLease()
        errorMessage = "Reminders couldn't be scheduled. Try again."
      }
    }

    private func endVerificationLease() {
      let task = verificationBackgroundTask
      verificationBackgroundTask = .invalid
      if task != .invalid { UIApplication.shared.endBackgroundTask(task) }
    }
  #endif

  private func beginMutation() -> UUID {
    let ticket = UUID()
    mutation = ticket
    isWorking = true
    errorMessage = nil
    return ticket
  }

  private func finishMutation(_ ticket: UUID) {
    if mutation == ticket { isWorking = false }
  }

  private func commit(_ value: ReminderPreferencesSnapshot, ticket: UUID) async {
    let previous = persistenceTail
    let work = Task {
      await previous?.value
      guard self.mutation == ticket else { return }
      guard value.isValid, let store = self.store else {
        self.intended = self.preferences
        self.errorMessage = "Reminder changes couldn't be saved. Try again."
        return
      }
      let saved: ReminderPreferencesSnapshot
      do { saved = try await store.saveReminderPreferences(value) } catch {
        guard self.mutation == ticket else { return }
        if let actual = try? await store.reminderPreferences() { self.preferences = actual }
        self.intended = self.preferences
        self.errorMessage = "Reminder changes couldn't be saved. Try again."
        return
      }
      guard self.mutation == ticket else { return }
      self.preferences = saved
      self.intended = saved
      do {
        let completed = Set(try await store.checkInHistory().map(\.dayID))
        guard self.mutation == ticket else { return }
        try await self.scheduler.reconcile(
          preferences: saved, completed: completed, now: self.now(), calendar: self.calendar())
        guard self.mutation == ticket else { return }
        await self.showPermissionOrTimeIssue(saved, ticket: ticket)
      } catch {
        guard self.mutation == ticket else { return }
        self.errorMessage = "Reminders couldn't be scheduled. Try again."
      }
    }
    persistenceTail = work
    await work.value
  }

  private func showPermissionOrTimeIssue(_ value: ReminderPreferencesSnapshot, ticket: UUID) async {
    let authorization = value.enabled ? await center.authorization() : nil
    guard mutation == ticket else { return }
    if value.enabled, authorization != .allowed {
      errorMessage = "Notifications are off in iPhone Settings."
    } else if !value.missedIsLater {
      errorMessage = "Choose a later time for If missed."
    } else {
      errorMessage = nil
    }
  }

  private static func time(_ minute: Int, calendar: Calendar) -> Date {
    // A stable date avoids today's DST gap changing the hour displayed by the native time control.
    calendar.date(
      from: DateComponents(year: 2001, month: 1, day: 15, hour: minute / 60, minute: minute % 60))!
  }
  private static func minute(_ date: Date, calendar: Calendar) -> Int {
    calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
  }
}
