import Combine
import SwiftUI
import UIKit

struct ReminderHost: ViewModifier {
  @Environment(\.scenePhase) private var scenePhase
  let services: ReminderServices
  let checkIn: MorningCheckInCoordinator
  let selectHome: () -> Void
  @State private var clockRevision = 0

  func body(content: Content) -> some View {
    content
      .onChange(
        of: RouteRequest(sequence: services.router.sequence, ready: services.isReady), initial: true
      ) { _, _ in
        guard services.consumePendingRoute() else { return }
        selectHome()
        Task { await checkIn.openFromReminder() }
      }
      .task(
        id: ClockRequest(
          active: scenePhase == .active, ready: services.isReady, revision: clockRevision)
      ) {
        guard scenePhase == .active, services.isReady else { return }
        await services.model.refresh()
        while !Task.isCancelled {
          let end = MorningDay(containing: Date()).end
          do { try await Task.sleep(for: .seconds(max(0, end.timeIntervalSinceNow))) } catch {
            return
          }
          guard !Task.isCancelled else { return }
          await services.model.refresh()
        }
      }
      .onReceive(
        NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)
      ) { _ in refreshClock() }
      .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
        refreshClock()
      }
  }

  private func refreshClock() {
    clockRevision += 1
    if scenePhase == .active, services.isReady { Task { await services.model.refresh() } }
  }
  private struct RouteRequest: Equatable {
    let sequence: Int
    let ready: Bool
  }
  private struct ClockRequest: Equatable {
    let active: Bool
    let ready: Bool
    let revision: Int
  }
}
