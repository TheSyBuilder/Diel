import Combine
import ScoringKit
import SwiftUI
import UIKit

struct TodayView: View {
  @Environment(\.dielTheme) private var theme
  let dependencies: AppDependencies
  let isSelected: Bool
  let showSettings: () -> Void
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.timeZone) private var timeZone
  @Environment(\.dynamicTypeSize) private var typeSize
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var home = HomePresentationModel()
  @State private var destination: TodayDestination?
  @Namespace private var dialTransition
  @State private var exposed = false
  @State private var refreshing = false
  @State private var sampleRefreshFailed = false
  @State private var refreshSuccess = 0
  @State private var dialTapCount = 0
  @State private var currentTime = Date()
  @State private var clockAdjustment = 0
  @State private var greetingHasScrolledAway = false
  @State private var glowTopExtension = DesignTokens.Today.glowTopExtension

  private var isSample: Bool {
    #if DEBUG
      dependencies.isSample
    #else
      false
    #endif
  }

  private var sampleReference: Date? {
    #if DEBUG
      dependencies.isSample ? dependencies.sampleReferenceDate : nil
    #else
      nil
    #endif
  }

  private var sampleOverride: String? {
    #if DEBUG
      if isSample,
        let index = ProcessInfo.processInfo.arguments.firstIndex(of: "--today-sample-date"),
        ProcessInfo.processInfo.arguments.indices.contains(index + 1)
      {
        return ProcessInfo.processInfo.arguments[index + 1]
      }
    #endif
    return nil
  }

  private var calendarDate: ScoringDate? {
    TodayPresentation.selectedDate(
      now: currentTime, calendar: .current, sampleReference: sampleReference,
      override: nil, available: [])
  }

  /// The displayed day: today, or before launch settles, the latest cached day.
  private var selectedDate: ScoringDate? { home.selectedDate ?? calendarDate }

  /// The brief always describes the morning's own day, never a launch fallback. Sample mode
  /// waits for the override day to resolve rather than briefly describing the reference day.
  private var briefDate: ScoringDate? {
    isSample ? home.resolvedDate : calendarDate
  }

  private var launchFinished: Bool { dependencies.morningBriefSync.launchFinished }

  private var snapshotRequest: TodaySnapshotRequest {
    TodaySnapshotRequest(
      revision: dependencies.scoring?.revision,
      generation: dependencies.scoring?.publicationGeneration ?? 0, date: calendarDate,
      sampleOverride: sampleOverride,
      enabled: !dependencies.settings.isSaving
        && (isSample || dependencies.sync?.hasSavedKey == true
          || dependencies.sync?.hasCachedScope == true),
      timeZone: timeZone.identifier,
      fallsBackToYesterday: !isSample && !launchFinished,
      morning: !isSample && TodayPresentation.isMorning(currentTime, calendar: .current)
    )
  }

  private var current: TodaySnapshot? {
    guard !dependencies.settings.isSaving,
      isSample || dependencies.sync?.hasSavedKey == true
        || dependencies.sync?.hasCachedScope == true,
      let snapshot = home.snapshot, snapshot.presentation.date == selectedDate
    else { return nil }
    if let revision = dependencies.scoring?.revision, revision != snapshot.revision { return nil }
    return snapshot
  }

  /// Only today's fetch, or a first calculation with nothing on screen, counts as syncing.
  /// Background catch-up of older days and activities stays quiet and never gates the brief.
  private var syncing: Bool {
    refreshing || dependencies.sync?.phase == .today
      || (dependencies.scoring?.isCalculating == true && current == nil)
  }

  private var active: Bool {
    isSelected && exposed && scenePhase == .active && destination == nil
      && dependencies.morningCheckIn.canRevealScores
  }
  private var launchState: HomeLaunchState {
    HomeLaunchState(
      hasContent: current != nil, launchFinished: launchFinished, syncing: syncing,
      keyMayExist: isSample || dependencies.sync?.canSync == true)
  }
  /// Yesterday's cached day stands in until today's scores publish. Never in sample mode.
  private var showingYesterday: Bool {
    guard !isSample, let shown = current?.presentation.date, let calendarDate else { return false }
    return shown != calendarDate
  }
  private var dials: [TodayDial] {
    current?.presentation.dials
      ?? TodayMetric.allCases.map(
        launchState == .loading ? TodayDial.loading : TodayDial.unavailable)
  }
  private var failed: Bool {
    dependencies.startupError != nil || dependencies.sync?.state == .failed
      || dependencies.scoring?.calculationFailed == true || sampleRefreshFailed
  }

  private var briefInputRequest: HomeBriefInputRequest {
    let morning = dependencies.morningCheckIn
    return HomeBriefInputRequest(
      revision: dependencies.scoring?.revision,
      generation: dependencies.scoring?.publicationGeneration ?? 0, date: briefDate,
      day: morning.day, answer: morning.answer,
      enabled: !dependencies.settings.isSaving
        && morning.day == MorningDay(containing: currentTime))
  }

  private var briefRequest: MorningBriefRequest {
    let morning = dependencies.morningCheckIn
    let prepared = dependencies.settings.isSaving ? nil : home.preparedBrief
    let valid =
      prepared?.context.dayID == morning.day.id
      && prepared?.context.scopeID == (dependencies.scoring?.revision?.id.uuidString ?? "unscoped")
      && morning.day == MorningDay(containing: currentTime)
    return MorningBriefRequest(
      context: valid ? prepared?.context : nil, input: valid ? prepared?.input : nil,
      settled: prepared?.request == briefInputRequest && briefDate != nil
        && dependencies.morningBriefSync.isSettled(for: morning.day)
        && !syncing && morning.canRevealScores && scenePhase == .active)
  }

  private var prewarmRequest: BriefPrewarmRequest {
    // Scoped like briefRequest; an unknown scope waits so the completed-brief check is exact.
    let day = dependencies.morningCheckIn.day
    let scopeID = dependencies.scoring?.revision?.id.uuidString
    return BriefPrewarmRequest(
      dayID: day.id, scopeID: scopeID ?? "unscoped",
      active: isSelected && scenePhase == .active && !dependencies.settings.isSaving
        && scopeID != nil && day == MorningDay(containing: currentTime))
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.s24) {
          VStack(alignment: .leading, spacing: DesignTokens.Spacing.s24) {
            header
            if failed { errorCard }
            if dependencies.morningCheckIn.canRevealScores {
              dialSection { metric in
                guard current != nil else { return }
                destination = .metric(metric)
                dialTapCount += 1
              }
              syncStatus
            }
          }
          .background {
            TodayGlow(
              readiness: dependencies.morningCheckIn.canRevealScores ? dials.first?.value : nil,
              band: dials.first?.colour.scoreBand
            )
            .padding(.horizontal, -DesignTokens.Spacing.screenMargin)
            .padding(.top, -glowTopExtension)
          }
          if dependencies.morningCheckIn.canRevealScores,
            let brief = dependencies.morningBrief.visibleBrief(for: briefRequest.context)
          {
            MorningBriefCard(brief: brief) { destination = .metric(.readiness) }
          }
          if dependencies.morningCheckIn.canRevealScores, let current {
            TodayHighlightsSection(
              snapshot: current, active: active, showsToday: !showingYesterday,
              now: sampleReference.map { $0.addingTimeInterval(12 * 60 * 60 + 10 * 60) }
                ?? currentTime
            ) {
              destination = $0
            }
          } else if dependencies.morningCheckIn.canRevealScores,
            launchState == .noData || launchState == .needsKey
          {
            emptyState
          }
        }
        .padding(.horizontal, DesignTokens.Spacing.screenMargin)
        .padding(.top, DesignTokens.Spacing.s16)
        .padding(.bottom, DesignTokens.Spacing.s32)
      }
      .dielTabScrollClearance()
      // The glow reaches the screen's top edge behind the status bar; content keeps its insets.
      .onScrollGeometryChange(for: CGFloat.self) { geometry in
        geometry.contentInsets.top + DesignTokens.Spacing.s16
      } action: { _, extent in
        glowTopExtension = max(DesignTokens.Today.glowTopExtension, extent)
      }
      .accessibilityIdentifier("today-scroll")
      .refreshable { await refresh() }
      .background(theme.colors.canvas)
      .navigationTitle("Home")
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(.hidden, for: .navigationBar)
      .toolbar {
        ToolbarItem(placement: .principal) {
          Text("Home")
            .font(.headline)
            .opacity(greetingHasScrolledAway ? 1 : 0)
            .accessibilityHidden(!greetingHasScrolledAway)
            .accessibilityIdentifier("today-navigation-title")
        }
        SampleDataToolbar()
      }
      .navigationDestination(item: $destination) { destination in
        if let current {
          switch destination {
          case .metric(let metric):
            TodayDetailView(
              metric: metric, snapshot: current,
              active: isSelected && exposed && scenePhase == .active
            )
            .navigationTransition(
              reduceMotion
                ? AnyNavigationTransition(.crossFade)
                : AnyNavigationTransition(.zoom(sourceID: metric, in: dialTransition)))
          case .bodyBattery:
            BodyBatteryDetailView(
              days: current.batteryDays, initialDate: current.presentation.date,
              now: sampleReference.map { $0.addingTimeInterval(12 * 60 * 60 + 10 * 60) }
                ?? currentTime,
              active: isSelected && exposed && scenePhase == .active)
          case .trends:
            TrendsView(
              history: current.history, ending: current.presentation.date,
              generation: current.generation)
          }
        } else if destination == .metric(.readiness) {
          UnavailableBriefReadinessDetail()
        }
      }
    }
    .task(
      id: MorningSyncRequest(
        day: dependencies.morningCheckIn.day,
        launchFinished: dependencies.morningBriefSync.launchFinished)
    ) {
      await dependencies.morningBriefSync.settle(dependencies.morningCheckIn.day)
    }
    .task(id: briefRequest.id) {
      let request = briefRequest
      // Leave SwiftUI's task-ID reconciliation before publishing the cached brief.
      await Task.yield()
      guard !Task.isCancelled else { return }
      await dependencies.morningBrief.update(
        context: request.context, input: request.input, settled: request.settled)
    }
    .task(id: prewarmRequest) {
      let request = prewarmRequest
      guard request.active else { return }
      await dependencies.morningBrief.prewarm(dayID: request.dayID, scopeID: request.scopeID)
    }
    .onAppear { exposed = true }
    .onDisappear { exposed = false }
    .onChange(of: dependencies.settings.isSaving) { _, saving in
      if saving {
        home.clear()
        destination = nil
      }
    }
    .onChange(of: dependencies.sync?.hasSavedKey) { _, saved in
      if saved != true && !isSample {
        home.clear()
        destination = nil
      }
    }
    .task(id: snapshotRequest) { await updateSnapshot() }
    .task(id: briefInputRequest) {
      await home.updateBrief(
        request: briefInputRequest, days: dependencies.scoring?.days ?? [],
        history: dependencies.scoring?.history ?? [])
    }
    .task(id: TodayClockRequest(active: active, adjustment: clockAdjustment)) {
      guard active else { return }
      currentTime = Date()
      while !Task.isCancelled {
        guard let next = TodayClock.nextBoundary(after: currentTime, calendar: .current) else {
          return
        }
        do {
          try await Task.sleep(for: .seconds(max(0, next.timeIntervalSinceNow)))
        } catch { return }
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
    .sensoryFeedback(.selection, trigger: dialTapCount)
    .sensoryFeedback(.success, trigger: refreshSuccess)
  }

  private var greeting: String {
    let hour = Calendar.current.component(.hour, from: currentTime)
    if hour < 12 { return "Good morning" }
    if hour < 18 { return "Good afternoon" }
    return "Good evening"
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: DesignTokens.Spacing.s8) {
      if let date = selectedDate, let displayDate = TodayPresentation.displayDate(date) {
        Text(displayDate, format: .dateTime.weekday(.wide).month(.wide).day())
          .dielSectionLabelStyle()
          .accessibilityIdentifier("today-date")
      }
      Text(greeting).dielScreenTitleStyle()
        .accessibilityIdentifier("today-greeting")
        .onGeometryChange(for: Bool.self) { geometry in
          geometry.frame(in: .scrollView(axis: .vertical)).maxY <= 0
        } action: {
          greetingHasScrolledAway = $0
        }
      MorningCheckInChip(coordinator: dependencies.morningCheckIn)
    }
  }

  private func dialSection(select: @escaping (TodayMetric) -> Void) -> some View {
    let layout =
      typeSize >= .xxLarge
      ? AnyLayout(VStackLayout(alignment: .center, spacing: DesignTokens.Spacing.s24))
      : AnyLayout(HStackLayout(alignment: .top, spacing: DesignTokens.Spacing.s8))
    return layout {
      ForEach(dials, id: \.metric) { dial in
        ScoreDial(
          dial: dial, active: active, syncing: syncing,
          selected: false
        ) { select(dial.metric) }
        .disabled(current == nil)
        .matchedTransitionSource(id: dial.metric, in: dialTransition)
      }
    }
  }

  private var syncStatus: some View {
    VStack(alignment: .leading, spacing: DesignTokens.Spacing.s4) {
      if let caption = HomeLaunchState.caption(
        hasContent: current != nil, loading: launchState == .loading, syncing: syncing,
        showingYesterday: showingYesterday)
      {
        Text(caption)
          .font(DesignTokens.Typography.caption).foregroundStyle(theme.colors.brand)
          .accessibilityIdentifier("today-sync-status")
      } else if let date = dependencies.sync?.lastSuccessfulSync,
        currentTime.timeIntervalSince(date) > DesignTokens.Today.staleInterval
      {
        Text("Updated \(date, format: .relative(presentation: .numeric, unitsStyle: .abbreviated))")
          .dielCaptionStyle().accessibilityIdentifier("today-stale")
      }
    }
  }

  private var errorCard: some View {
    VStack(alignment: .leading, spacing: DesignTokens.Spacing.s12) {
      Text("Sync couldn't finish. Your saved data is still here.")
        .dielBodyStyle()
      Button("Retry") { Task { await refresh() } }
        .buttonStyle(.bordered).tint(theme.colors.brand).disabled(syncing)
        .accessibilityIdentifier("today-retry")
    }
    .padding(DesignTokens.Spacing.cardPadding)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(theme.colors.surface, in: .rect(cornerRadius: DesignTokens.Shape.cardRadius))
    .accessibilityIdentifier("today-error")
  }

  private var emptyState: some View {
    VStack(alignment: .leading, spacing: DesignTokens.Spacing.s12) {
      Text("No data for today yet.")
        .dielBodyStyle()
      Button(launchState == .needsKey ? "Add your key" : "Sync now") {
        if launchState == .needsKey {
          showSettings()
        } else {
          Task { await refresh() }
        }
      }
      .buttonStyle(.bordered).tint(theme.colors.brand)
      .accessibilityIdentifier("today-empty-action")
    }
    .padding(DesignTokens.Spacing.cardPadding)
  }

  private func updateSnapshot() async {
    await home.updateSnapshot(
      request: snapshotRequest, days: dependencies.scoring?.days ?? [],
      history: dependencies.scoring?.history ?? [], store: dependencies.store)
  }

  private func refresh() async {
    guard !refreshing else { return }
    refreshing = true
    sampleRefreshFailed = false
    defer { refreshing = false }
    #if DEBUG
      if isSample {
        guard let reference = dependencies.sampleReferenceDate,
          let revision = dependencies.sampleRevision,
          let plan = try? SyncPlan(now: reference, initial: true)
        else {
          sampleRefreshFailed = true
          return
        }
        await dependencies.scoring?.refresh(
          in: plan.start...plan.end, revision: revision,
          now: reference, calendar: .current)
        await updateSnapshot()
        if dependencies.scoring?.calculationFailed == false { refreshSuccess += 1 }
        return
      }
    #endif
    // Catch-up may still be running; success means today's fetch and scores both succeeded.
    let todaySucceeded = await dependencies.sync?.syncToday(manual: true) ?? false
    await updateSnapshot()
    if todaySucceeded { refreshSuccess += 1 }
  }
}

private struct TodayHighlightsSection: View {
  let snapshot: TodaySnapshot
  let active: Bool
  /// False while yesterday stands in: cards that mean today stay hidden rather than mislabelled.
  let showsToday: Bool
  let now: Date
  let open: (TodayDestination) -> Void
  var body: some View {
    VStack(spacing: DesignTokens.Spacing.cardGap) {
      if showsToday {
        TodayCard(title: "Last night", symbol: .stages) {
          LastNightCardContent(highlights: snapshot.highlights)
        }.accessibilityIdentifier("today-card-sleep")
        TodayCard(title: "Today so far", symbol: .load) {
          ActivityCardContent(highlights: snapshot.highlights, load: snapshot.presentation.dials[1])
        }.accessibilityIdentifier("today-card-load")
        TodayCard(title: "Body Battery", symbol: .battery, open: { open(.bodyBattery) }) {
          BodyBatteryCardContent(
            samples: snapshot.batteryDays.last?.samples ?? snapshot.highlights.battery,
            active: active,
            day: snapshot.batteryDays.last, now: now)
        }.accessibilityIdentifier("today-card-body-battery")
      }
      TodayCard(title: "This week", symbol: .readiness, open: { open(.trends) }) {
        let week = snapshot.week
        if week.showsChart {
          MetricHistoryChart(
            metric: .readiness, points: week.points, compact: true, showsLatestSummary: false)
        }
        if week.showsLearningCount {
          Text("Learning your baseline · \(week.learningCount) of 60")
            .dielBodyStyle()
            .accessibilityIdentifier("today-week-learning")
        }
      }.accessibilityIdentifier("today-card-week")
    }
  }
}

private struct TodayClockRequest: Equatable {
  let active: Bool
  let adjustment: Int
}

private struct BriefPrewarmRequest: Equatable {
  let dayID: String
  let scopeID: String
  let active: Bool
}

private struct MorningSyncRequest: Equatable {
  let day: MorningDay
  let launchFinished: Bool
}
