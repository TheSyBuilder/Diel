import Foundation
import Observation

@Observable
@MainActor
final class MorningCheckInCoordinator {
  private(set) var day: MorningDay
  private(set) var answer: CheckInSnapshot?
  private(set) var hasLoaded = false
  private(set) var isChecking = false
  private(set) var isSaving = false
  private(set) var errorMessage: LocalizedStringResource?
  private(set) var selectionFeedback = 0
  var isPresented = false
  /// Later morning work can observe a committed answer without handling persistent models.
  @ObservationIgnored var onSaved: (@MainActor (CheckInSnapshot) -> Void)?
  @ObservationIgnored private let store: (any CheckInStoring)?
  @ObservationIgnored private let now: () -> Date
  @ObservationIgnored private let calendar: () -> Calendar
  @ObservationIgnored private let bypass: Bool
  private var evaluation = UUID()
  private var reminderPresentationRequested = false

  init(
    store: (any CheckInStoring)?, now: @escaping () -> Date = Date.init,
    calendar: @escaping () -> Calendar = { .current }, bypass: Bool = false
  ) {
    self.store = store
    self.now = now
    self.calendar = calendar
    day = MorningDay(containing: now(), calendar: calendar())
    #if DEBUG
      self.bypass = bypass
      hasLoaded = bypass
    #else
      self.bypass = false
    #endif
  }

  var canRevealScores: Bool {
    bypass
      || hasLoaded && answer != nil && !isPresented
        && day == MorningDay(containing: now(), calendar: calendar())
  }

  func evaluate() async {
    let current = MorningDay(containing: now(), calendar: calendar())
    let changedDay = current != day
    day = current
    if bypass {
      hasLoaded = true
      isPresented = false
      return
    }
    if changedDay {
      answer = nil
      hasLoaded = false
    }
    let ticket = UUID()
    evaluation = ticket
    isChecking = true
    errorMessage = nil
    do {
      guard let store else { throw CheckInError.unavailableStore }
      let saved = try await store.checkIn(for: current.id)
      guard evaluation == ticket else { return }
      answer = saved
      hasLoaded = true
      isChecking = false
      if saved == nil || reminderPresentationRequested {
        isPresented = true
        reminderPresentationRequested = false
      }
    } catch {
      guard evaluation == ticket else { return }
      isChecking = false
      hasLoaded = false
      isPresented = true
      errorMessage = "Your check-in couldn't be opened. Try again."
    }
  }

  func openFromReminder() async {
    reminderPresentationRequested = true
    await evaluate()
  }

  func editToday() {
    guard hasLoaded, !isSaving else { return }
    errorMessage = nil
    isPresented = true
  }

  /// A nil rating is an explicit skip, never an invented rating.
  func complete(rating: Int?) async {
    guard hasLoaded, !isChecking, !isSaving else { return }
    let current = MorningDay(containing: now(), calendar: calendar())
    guard current == day else {
      await evaluate()
      return
    }
    isSaving = true
    errorMessage = nil
    defer { isSaving = false }
    do {
      guard let store else { throw CheckInError.unavailableStore }
      let saved = try await store.saveCheckIn(
        dayID: current.id, rating: rating, skipped: rating == nil, at: now())
      guard current == MorningDay(containing: now(), calendar: calendar()) else {
        onSaved?(saved)
        await evaluate()
        return
      }
      guard current == day else {
        onSaved?(saved)
        return
      }
      // Invalidate any earlier read that could otherwise restore an unsaved presentation.
      evaluation = UUID()
      answer = saved
      hasLoaded = true
      isChecking = false
      if rating != nil { selectionFeedback += 1 }
      isPresented = false
      onSaved?(saved)
    } catch {
      errorMessage = "Your check-in couldn't be saved. Try again."
    }
  }
}
