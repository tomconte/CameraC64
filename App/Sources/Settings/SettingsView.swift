import SwiftUI
import UIKit

/// The names settings are saved under, in the app's user defaults.
enum SettingName {
    /// Whether PETSCII pictures use only the graphics characters.
    static let petsciiGraphicsOnly = "petsciiGraphicsOnly"
}

/// Settings, in standard iOS styling (docs/UX.md, section 5).
///
/// Mostly a placeholder: apart from PETSCII's characters, the choices are
/// neither saved nor used yet.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingName.petsciiGraphicsOnly) private var petsciiGraphicsOnly = false
    @State private var palette = "Colodore"
    @State private var brightnessLevels = 9
    @State private var saveEveryShot = false
    @State private var ultimateAddress = ""
    @State private var cameraControl = "mode"

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Palette", selection: $palette) {
                        Text("Colodore").tag("Colodore")
                        Text("Pepto 2001").tag("Pepto 2001")
                    }
                    Picker("Chip", selection: $brightnessLevels) {
                        Text("9 brightness levels").tag(9)
                        Text("5 (earliest chips)").tag(5)
                    }
                } header: {
                    Text("Picture")
                } footer: {
                    Text("Pictures are PAL: 320 × 200 pixels at 50 Hz.")
                }
                Section {
                    Toggle("Graphics characters only", isOn: $petsciiGraphicsOnly)
                } header: {
                    Text("PETSCII")
                } footer: {
                    Text("Only blocks, lines and shapes, for the classic look: no letters, digits or punctuation.")
                }
                Section("Saving") {
                    Toggle("Save every shot to Photos", isOn: $saveEveryShot)
                }
                Section {
                    TextField("Address, such as 192.168.1.64", text: $ultimateAddress)
                        .keyboardType(.numbersAndPunctuation)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Send to C64")
                } footer: {
                    Text("An Ultimate 64, C64 Ultimate or Ultimate-II+ on the same Wi-Fi network.")
                }
                Section("Camera Control") {
                    Picker("Slide to change", selection: $cameraControl) {
                        Text("Mode").tag("mode")
                        Text("Monitor").tag("monitor")
                    }
                }
                Section {
                    Button("Restore Purchase") {}
                        .disabled(true)
                } footer: {
                    Text("Apart from PETSCII's characters, nothing here is saved or used yet.")
                }
                if BuildKind.isDevelopment {
                    Section {
                        NavigationLink("Speed Benchmark") {
                            SpeedBenchmarkView()
                        }
                    } header: {
                        Text("Development")
                    } footer: {
                        Text("Only in development and TestFlight builds.")
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
        }
    }
}

#Preview {
    SettingsView()
}
