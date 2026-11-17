import SwiftUI

struct ReminderSettingsView: View {
  @Environment(\.dielTheme) private var theme
  @Bindable var model: ReminderModel

  var body: some View {
    Form {
      Section {
        Toggle("Reminders", isOn: $model.enabled)
          .accessibilityIdentifier("reminders-enabled")
        DatePicker(
          "First reminder", selection: $model.firstTime, displayedComponents: .hourAndMinute
        )
        .accessibilityIdentifier("reminders-first-time")
        DatePicker("If missed", selection: $model.missedTime, displayedComponents: .hourAndMinute)
          .accessibilityIdentifier("reminders-missed-time")
      }
      .disabled(!model.hasLoaded || model.isWorking)
      .listRowBackground(theme.colors.surface)
      if let error = model.errorMessage {
        Section {
          Text(error).dielBodyStyle().foregroundStyle(theme.colors.error)
            .accessibilityIdentifier("reminders-error")
          Button("Try again") { Task { await model.refresh() } }
            .disabled(model.isWorking)
        }.listRowBackground(theme.colors.surface)
      }
      #if DEBUG
        if model.verificationEnabled {
          Section {
            Button("Send test reminder") { Task { await model.sendVerificationReminder() } }
              .accessibilityIdentifier("reminders-send-test")
              .disabled(!model.enabled || model.isWorking)
          }.listRowBackground(theme.colors.surface)
        }
      #endif
    }
    .dielTabScrollClearance()
    .tint(theme.colors.brand)
    .formStyle(.grouped)
    .scrollContentBackground(.hidden)
    .background(theme.colors.canvas)
    .navigationTitle("Reminders")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar { SampleDataToolbar() }
    .task { await model.refresh() }
  }
}
