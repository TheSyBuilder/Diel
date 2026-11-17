import Combine
import SwiftUI
import UIKit

/// Keeps the boundary clock independent of covered Home content and dial animation activity.
struct MorningCheckInHost: ViewModifier {
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.dielTheme) private var theme
  @Bindable var coordinator: MorningCheckInCoordinator
  @State private var clockRevision = 0

  func body(content: Content) -> some View {
    content
      .sensoryFeedback(.selection, trigger: coordinator.selectionFeedback)
      .accessibilityHidden(!coordinator.canRevealScores)
      .overlay {
        if !coordinator.canRevealScores && !coordinator.isPresented {
          theme.colors.canvas.ignoresSafeArea()
            .overlay { ProgressView() }
            .accessibilityIdentifier("check-in-loading")
        }
      }
      .fullScreenCover(isPresented: $coordinator.isPresented) {
        MorningCheckInView(coordinator: coordinator)
      }
      .task(id: ClockRequest(active: scenePhase == .active, revision: clockRevision)) {
        guard scenePhase == .active else { return }
        while !Task.isCancelled {
          let end = MorningDay(containing: Date()).end
          do { try await Task.sleep(for: .seconds(max(0, end.timeIntervalSinceNow))) } catch {
            return
          }
          guard !Task.isCancelled else { return }
          await coordinator.evaluate()
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
    if scenePhase == .active { Task { await coordinator.evaluate() } }
  }

  private struct ClockRequest: Equatable {
    let active: Bool
    let revision: Int
  }
}
