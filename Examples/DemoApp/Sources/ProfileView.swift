import SwiftUI

/// SwiftUI demo surface: identified controls, an identified+labelled control,
/// and an un-identified control (the automation-debt showcase).
struct ProfileView: View {
    @State private var notificationsOn = true
    @State private var displayName = "Agent"
    @State private var volume = 0.5

    var body: some View {
        Form {
            Section("Preferences") {
                Toggle("Notifications", isOn: $notificationsOn)
                    .accessibilityLabel("Allow notifications")
                    .accessibilityIdentifier("profile.notifications")
                TextField("Display name", text: $displayName)
                    .accessibilityIdentifier("profile.displayName")
                Slider(value: $volume)
                    .accessibilityIdentifier("profile.volume")
                Button("Save profile") {
                    displayName = displayName.trimmingCharacters(in: .whitespaces)
                }
                .accessibilityIdentifier("profile.save")
                // Debt: a switch-like control nobody can automate.
                Button("Regenerate avatar") {}
            }
        }
    }
}

// dirty change for affected-tests demo: Save button label tweak
