import SwiftUI

struct SettingsView: View {
  @Environment(\.dielTheme) private var theme
  let model: SettingsModel
  let startupError: LocalizedStringResource?
  var reminders: ReminderModel? = nil
  var dependencies: AppDependencies? = nil
  @State private var isEntryPresented = false
  @State private var isRemovalPresented = false

  var body: some View {
    NavigationStack {
      Form {
        CredentialSection(
          model: model,
          editKey: { isEntryPresented = true },
          removeKey: {
            if model.requestRemoval() { isRemovalPresented = true }
          })
        SyncStatusSection(model: model)
        AppearanceSection()
        #if DEBUG
          Section {
            LabeledContent("Build", value: BuildMetadata.current.displayValue)
              .accessibilityIdentifier("settings-build-commit")
            if let dependencies {
              DebugBriefSourceRow(dependencies: dependencies)
              DebugSyncTimingRow(dependencies: dependencies)
            }
          }
          .listRowBackground(theme.colors.surface)
        #endif
        if let reminders {
          Section {
            NavigationLink("Reminders") { ReminderSettingsView(model: reminders) }
              .accessibilityIdentifier("settings-reminders")
          }.listRowBackground(theme.colors.surface)
        }
        Section {
          if let error = model.errorMessage ?? startupError ?? model.sync?.errorMessage {
            Text(error)
              .font(DesignTokens.Typography.body)
              .foregroundStyle(theme.colors.error)
              .accessibilityIdentifier("settings-error")
          }
        } footer: {
          WellnessDisclaimer()
        }
        .listRowBackground(theme.colors.surface)
      }
      .dielTabScrollClearance()
      .tint(theme.colors.brand)
      .formStyle(.grouped)
      .scrollContentBackground(.hidden)
      .background(theme.colors.canvas)
      .navigationTitle("Settings")
      .navigationBarTitleDisplayMode(.large)
      .toolbar { SampleDataToolbar() }
    }
    .sheet(isPresented: $isEntryPresented, onDismiss: { model.clearEntry() }) {
      CredentialEntrySheet(model: model)
    }
    .confirmationDialog(
      "Remove saved key?", isPresented: $isRemovalPresented, titleVisibility: .visible
    ) {
      Button("Remove key", role: .destructive) { model.confirmRemoval() }
        .foregroundStyle(theme.colors.error)
        .accessibilityIdentifier("confirm-remove-key")
      Button("Cancel", role: .cancel) { model.cancelRemoval() }
    } message: {
      Text("You will need to enter your key again to sync.")
    }
    .onChange(of: isRemovalPresented) { _, presented in
      if !presented { model.cancelRemoval() }
    }
    .onDisappear {
      guard !isEntryPresented else { return }
      isRemovalPresented = false
      model.clearEntry()
    }
  }
}

private struct CredentialSection: View {
  @Environment(\.dielTheme) private var theme
  let model: SettingsModel
  let editKey: () -> Void
  let removeKey: () -> Void

  var body: some View {
    Section {
      HStack {
        if model.sync?.hasSavedKey == true {
          Text("Connected")
            .accessibilityIdentifier("credential-status")
          Spacer()
          Image(systemName: "checkmark")
            .foregroundStyle(theme.colors.textSecondary)
            .accessibilityHidden(true)
        } else {
          Text("Not connected")
            .accessibilityIdentifier("credential-status")
        }
      }
      Button(action: editKey) {
        if model.sync?.hasSavedKey == true {
          Text("Replace key")
        } else {
          Text("Add key")
        }
      }
      .accessibilityIdentifier("edit-key")
      .disabled(!model.credentialsEnabled || model.isSaving || model.sync == nil)
      if model.sync?.hasSavedKey == true {
        Button("Remove key", role: .destructive, action: removeKey)
          .foregroundStyle(theme.colors.error)
          .accessibilityIdentifier("remove-key")
          .disabled(!model.credentialsEnabled || model.isSaving)
      }
    } header: {
      Text("Garmin").font(DesignTokens.Typography.body)
    }
    .listRowBackground(theme.colors.surface)
  }
}

private struct CredentialEntrySheet: View {
  @Environment(\.dielTheme) private var theme
  @Environment(\.dismiss) private var dismiss
  @Bindable var model: SettingsModel

  var body: some View {
    NavigationStack {
      Form {
        Section {
          SecureField("Garmin key", text: $model.entry)
            .textContentType(.password)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .accessibilityIdentifier("garmin-key")
            .disabled(model.isSaving)
        }
        .listRowBackground(theme.colors.surface)
        if let error = model.errorMessage {
          Text(error)
            .font(DesignTokens.Typography.body)
            .foregroundStyle(theme.colors.error)
            .accessibilityIdentifier("key-entry-error")
            .listRowBackground(theme.colors.surface)
        }
      }
      .scrollContentBackground(.hidden)
      .background(theme.colors.canvas)
      .navigationTitle(model.sync?.hasSavedKey == true ? "Replace key" : "Add key")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
            .accessibilityIdentifier("cancel-key-entry")
        }
        ToolbarItem(placement: .confirmationAction) {
          Button {
            Task {
              await model.save()
              if model.errorMessage == nil { dismiss() }
            }
          } label: {
            if model.isSaving {
              Text("Saving…")
            } else {
              Text("Save key")
            }
          }
          .accessibilityIdentifier("save-key")
          .disabled(
            !model.credentialsEnabled || model.isSaving || model.sync == nil
              || model.entry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
    }
    .onDisappear { model.clearEntry() }
  }
}

private struct SyncStatusSection: View {
  @Environment(\.dielTheme) private var theme
  let model: SettingsModel

  var body: some View {
    Section {
      if let lastSync = model.sync?.lastSuccessfulSync {
        HStack {
          Text("Last synced")
          Spacer()
          TimelineView(.periodic(from: lastSync, by: 60)) { context in
            if context.date.timeIntervalSince(lastSync) < 60 {
              Text("Just now")
                .accessibilityIdentifier("last-synced")
            } else {
              Text(lastSync, format: .relative(presentation: .named, unitsStyle: .abbreviated))
                .accessibilityIdentifier("last-synced")
            }
          }
        }
      } else {
        Text("Not synced yet")
          .accessibilityIdentifier("last-synced")
      }
      if let next = model.sync?.nextPlannedCheck {
        Text(
          "Next planned check \(next, format: .relative(presentation: .numeric, unitsStyle: .abbreviated))"
        )
        .accessibilityIdentifier("next-planned-check")
      } else {
        Text("No check planned")
          .accessibilityIdentifier("next-planned-check")
      }
      Button {
        model.sync?.requestSync()
      } label: {
        if model.sync?.state == .running {
          Text("Syncing…")
        } else {
          Text("Sync now")
        }
      }
      .tint(theme.colors.brand)
      .foregroundStyle(theme.colors.brand)
      .accessibilityIdentifier("sync-now")
      .disabled(
        !model.credentialsEnabled || model.sync?.canSync != true || model.isSaving
          || model.sync?.state == .running)
    } header: {
      Text("Sync").font(DesignTokens.Typography.body)
    } footer: {
      Text("iOS chooses when background checks run.")
        .dielBodyStyle()
    }
    .listRowBackground(theme.colors.surface)
  }
}

private struct WellnessDisclaimer: View {
  var body: some View {
    Text("Diel scores are wellness estimates for personal use.")
      .dielBodyStyle()
      .accessibilityIdentifier("wellness-disclaimer")
  }
}

private struct AppearanceSection: View {
  @Environment(ThemeStore.self) private var store
  @Environment(\.dielTheme) private var theme

  var body: some View {
    Section {
      ForEach(DielTheme.allCases) { option in
        Button {
          store.select(option)
        } label: {
          HStack(spacing: DesignTokens.Spacing.s16) {
            Image(option.previewAssetName)
              .renderingMode(.original)
              .resizable()
              .scaledToFit()
              .frame(
                width: DesignTokens.Appearance.iconSize,
                height: DesignTokens.Appearance.iconSize
              )
              .clipShape(.rect(cornerRadius: DesignTokens.Appearance.iconRadius))
              .transaction { $0.animation = nil }
              .accessibilityHidden(true)
            Text(option.name)
              .foregroundStyle(theme.colors.textPrimary)
            Spacer()
            if option == store.selectedTheme {
              Image(systemName: "checkmark")
                .foregroundStyle(theme.colors.textPrimary)
                .accessibilityHidden(true)
            }
          }
          .contentShape(.rect)
        }
        .accessibilityIdentifier("appearance-\(option.rawValue)")
        .accessibilityAddTraits(option == store.selectedTheme ? .isSelected : [])
      }
      if let error = store.iconError {
        Text(error)
          .font(DesignTokens.Typography.body)
          .foregroundStyle(theme.colors.error)
          .accessibilityIdentifier("appearance-icon-error")
        Button("Try again") { store.retryIconChange() }
          .accessibilityIdentifier("retry-app-icon")
      }
    } header: {
      Text("Appearance").font(DesignTokens.Typography.body)
    }
    .listRowBackground(theme.colors.surface)
  }
}

#if DEBUG
  private struct DebugBriefSourceRow: View {
    let dependencies: AppDependencies

    var body: some View {
      TimelineView(.periodic(from: .now, by: 60)) { context in
        LabeledContent("Today's brief") { Text(source(at: context.date)) }
          .accessibilityIdentifier("settings-brief-source")
      }
    }

    private func source(at date: Date) -> LocalizedStringResource {
      let scope = dependencies.scoring?.revision?.id.uuidString ?? "unscoped"
      guard !dependencies.settings.isSaving,
        let brief = dependencies.morningBrief.currentBrief(
          day: dependencies.morningCheckIn.day, scopeID: scope, now: date)
      else { return "Not generated" }
      switch brief.source {
      case .onDevice: return "On-device model"
      case .template: return "Template"
      case nil: return "Source unavailable"
      }
    }
  }

  private struct DebugSyncTimingRow: View {
    let dependencies: AppDependencies

    var body: some View {
      LabeledContent("Last sync") {
        if let timing = dependencies.sync?.lastSyncTiming {
          Text(verbatim: timing.summary)
        } else {
          Text("Not yet")
        }
      }
      .accessibilityIdentifier("settings-last-sync-timing")
    }
  }
#endif
