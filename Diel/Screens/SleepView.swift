import Combine
import ScoringKit
import SwiftUI
import UIKit

struct SleepView: View {
  @Environment(\.dielTheme) private var theme
  let dependencies: AppDependencies
  let isSelected: Bool
  @Environment(\.scenePhase) private var scenePhase
  @State private var home = HomePresentationModel()
  @State private var currentTime = Date()
  @State private var exposed = false
  @State private var clockAdjustment = 0

  private var selectedDate: ScoringDate? {
    TodayPresentation.selectedDate(
      now: currentTime, calendar: .current,
      sampleReference: sampleReference, override: nil, available: [])
  }
  private var current: TodaySnapshot? {
    guard !dependencies.settings.isSaving, let snapshot = home.snapshot,
      snapshot.presentation.date == selectedDate,
      snapshot.revision == dependencies.scoring?.revision
    else { return nil }
    return snapshot
  }
  private var active: Bool { isSelected && exposed && scenePhase == .active }
  private var sampleReference: Date? {
    #if DEBUG
      dependencies.isSample ? dependencies.sampleReferenceDate : nil
    #else
      nil
    #endif
  }
  var body: some View {
    NavigationStack {
      if let current {
        TodayDetailView(
          metric: .sleep, snapshot: current,
          active: active)
      } else {
        ScrollView {
          Text("No sleep data for last night yet.").dielBodyStyle()
            .padding(DesignTokens.Spacing.screenMargin)
        }.dielTabScrollClearance()
          .background(theme.colors.canvas).navigationTitle("Sleep")
          .toolbar { SampleDataToolbar() }
      }
    }
    .onAppear { exposed = true }
    .onDisappear { exposed = false }
    .task(
      id: TodaySnapshotRequest(
        revision: dependencies.scoring?.revision,
        generation: dependencies.scoring?.publicationGeneration ?? 0, date: selectedDate,
        enabled: !dependencies.settings.isSaving)
    ) {
      await home.updateSnapshot(
        request: TodaySnapshotRequest(
          revision: dependencies.scoring?.revision,
          generation: dependencies.scoring?.publicationGeneration ?? 0, date: selectedDate,
          enabled: !dependencies.settings.isSaving),
        days: dependencies.scoring?.days ?? [], history: dependencies.scoring?.history ?? [],
        store: dependencies.store)
    }
    .task(id: SleepClockRequest(active: active, adjustment: clockAdjustment)) {
      guard active else { return }
      currentTime = Date()
      while !Task.isCancelled {
        guard let next = TodayClock.nextBoundary(after: currentTime, calendar: .current) else {
          return
        }
        do { try await Task.sleep(for: .seconds(max(0, next.timeIntervalSinceNow))) } catch {
          return
        }
        guard !Task.isCancelled else { return }
        currentTime = Date()
      }
    }
    .onReceive(
      NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)
    ) { _ in
      if active {
        currentTime = Date()
        clockAdjustment += 1
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
      if active {
        currentTime = Date()
        clockAdjustment += 1
      }
    }
  }
}

private struct SleepClockRequest: Equatable {
  let active: Bool
  let adjustment: Int
}
