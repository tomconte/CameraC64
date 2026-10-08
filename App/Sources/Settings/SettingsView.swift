import SwiftUI
import UIKit

/// The names settings are saved under, in the app's user defaults.
enum SettingName {
    /// Whether every shot is saved to Photos, as on TV.
    static let saveEveryShot = "saveEveryShot"
    /// The address of the Ultimate that Send to C64 sends pictures to, or
    /// empty for none.
    static let ultimateAddress = "ultimateAddress"
    /// The name of the keychain item that holds the Ultimate's network
    /// password, if it has one.
    static let ultimatePassword = "ultimatePassword"
    /// In development builds, the CRT layer's look as tuned (`CRT.text`).
    static let crtLook = "crtLook"
    /// In development builds, whether the camera screen shows the CRT tuning
    /// panel.
    static let crtTuning = "crtTuning"
}

/// Settings, in standard iOS styling (docs/UX.md, section 5): saving every
/// shot to Photos, and the Ultimate that Send to C64 sends pictures to.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingName.saveEveryShot) private var savesEveryShot = false
    @AppStorage(SettingName.ultimateAddress) private var ultimateAddress = ""
    @AppStorage(SettingName.crtTuning) private var showsCRTTuning = false
    @State private var ultimatePassword = ""
    /// Whether the app was kept from adding photos when the switch was
    /// turned on.
    @State private var photosNotAllowed = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Save Every Shot to Photos", isOn: $savesEveryShot)
                } header: {
                    Text("Saving")
                } footer: {
                    if photosNotAllowed {
                        Text("Camera C64 may not add photos. Allow it in the Settings app, under Privacy & Security.")
                    } else {
                        Text("Each picture goes to Photos as on TV as soon as it is taken.")
                    }
                }
                Section {
                    TextField("Address, such as 192.168.1.64", text: $ultimateAddress)
                        .keyboardType(.numbersAndPunctuation)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password, if it has one", text: $ultimatePassword)
                } header: {
                    Text("Send to C64")
                } footer: {
                    Text(
                        "An Ultimate 64, C64 Ultimate or Ultimate-II+ on the same network, with its web remote "
                            + "control on. Send to C64 then shows the picture on its C64.")
                }
                if BuildKind.isDevelopment {
                    Section {
                        NavigationLink("Speed Benchmark") {
                            SpeedBenchmarkView()
                        }
                        Toggle("CRT Tuning", isOn: $showsCRTTuning)
                    } header: {
                        Text("Development")
                    } footer: {
                        Text(
                            "Only in development and TestFlight builds. CRT Tuning shows sliders for the CRT effect "
                                + "on the camera screen, below the TV.")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                ultimatePassword = Keychain.password(SettingName.ultimatePassword)
            }
            .onChange(of: ultimatePassword) {
                Keychain.setPassword(ultimatePassword, for: SettingName.ultimatePassword)
            }
            // Asks for permission to add photos when the switch is turned on,
            // rather than after the next shot.
            .onChange(of: savesEveryShot) {
                guard savesEveryShot else { return }
                photosNotAllowed = false
                Task {
                    let allowed = await PhotoLibrary.canAdd()
                    if !allowed {
                        savesEveryShot = false
                        photosNotAllowed = true
                    }
                }
            }
        }
    }
}

#Preview {
    SettingsView()
}
