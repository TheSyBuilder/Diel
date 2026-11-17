//
//  ContentView.swift
//  Diel
//
//  Created by Taleb Alhajji on 05/11/2026.
//

import SwiftUI

struct ContentView: View {
  @Environment(ThemeStore.self) private var themeStore
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  #if DEBUG
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  #endif
  let dependencies: AppDependencies
  @State private var selection = Destination.today

  var body: some View {
    TabView(selection: $selection) {
      Tab("Home", systemImage: "house.fill", value: Destination.today) {
        TodayView(dependencies: dependencies, isSelected: selection == .today) {
          selection = .settings
        }
      }

      Tab("Trends", systemImage: "chart.xyaxis.line", value: Destination.trends) {
        TrendsTabView(dependencies: dependencies)
      }

      Tab("Settings", systemImage: "gearshape", value: Destination.settings) {
        SettingsView(
          model: dependencies.settings, startupError: dependencies.startupError,
          reminders: dependencies.reminders.model, dependencies: dependencies)
      }
    }
    .modifier(MorningCheckInHost(coordinator: dependencies.morningCheckIn))
    .modifier(
      ReminderHost(services: dependencies.reminders, checkIn: dependencies.morningCheckIn) {
        selection = .today
      }
    )
    #if DEBUG
      .environment(\._accessibilityReduceMotion, effectiveReduceMotion)
      .environment(\._accessibilityReduceTransparency, effectiveReduceTransparency)
    #endif
    .environment(\.isShowingSampleData, isSample)
    .environment(\.dielSampleReferenceDate, sampleReferenceDate)
    .tint(themeStore.selectedTheme.colors.textPrimary)
    .foregroundStyle(
      themeStore.selectedTheme.colors.textPrimary, themeStore.selectedTheme.colors.textSecondary
    )
    .environment(\.dielTheme, themeStore.selectedTheme)
    .animation(
      effectiveReduceMotion
        ? nil : .easeInOut(duration: DesignTokens.Appearance.transitionDuration),
      value: themeStore.selectedTheme
    )
    .accessibilityIdentifier("content-root")
    .accessibilityValue(themeStore.selectedTheme.rawValue)
  }

  private var effectiveReduceMotion: Bool {
    #if DEBUG
      reduceMotion
        || isSample && ProcessInfo.processInfo.arguments.contains("--verify-reduce-motion")
    #else
      reduceMotion
    #endif
  }

  #if DEBUG
    private var effectiveReduceTransparency: Bool {
      reduceTransparency
        || isSample && ProcessInfo.processInfo.arguments.contains("--verify-reduce-transparency")
    }
  #endif

  private var isSample: Bool {
    #if DEBUG
      dependencies.isSample
    #else
      false
    #endif
  }

  private var sampleReferenceDate: Date? {
    #if DEBUG
      dependencies.isSample ? dependencies.sampleReferenceDate : nil
    #else
      nil
    #endif
  }

  private enum Destination: Hashable {
    case today
    case trends
    case settings
  }
}

extension EnvironmentValues {
  @Entry var isShowingSampleData = false
  @Entry var dielSampleReferenceDate: Date?
}

struct SampleDataToolbar: ToolbarContent {
  var body: some ToolbarContent {
    ToolbarItem(placement: .topBarTrailing) { SampleDataIndicator() }
  }
}

private struct SampleDataIndicator: View {
  @Environment(\.isShowingSampleData) private var isShowingSampleData
  var body: some View {
    #if DEBUG
      if isShowingSampleData { SampleDataBanner(dayCount: 0) }
    #endif
  }
}

#Preview {
  @Previewable @State var dependencies = AppDependencies()
  ContentView(dependencies: dependencies)
    .environment(ThemeStore())
    .task { await dependencies.start() }
    .preferredColorScheme(.dark)
}

// Native floating tabs overlay scroll content; reserve the same clearance in every tab.
extension View {
  func dielTabScrollClearance() -> some View {
    safeAreaPadding(.bottom, DesignTokens.Spacing.s48)
  }
}
