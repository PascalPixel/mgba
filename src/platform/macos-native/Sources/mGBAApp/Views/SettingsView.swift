import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var session: EmulatorSession
    @EnvironmentObject private var shaderStore: ShaderStore
    @AppStorage("video.filtering") private var filtering = false
    @AppStorage("emulation.pauseWhenInactive") private var pauseWhenInactive = true
    @AppStorage("audio.volume") private var audioVolume = 0.8
    @AppStorage("audio.muted") private var audioMuted = false

    var body: some View {
        TabView {
            Form {
                Section("Behavior") {
                    Toggle("Pause when mGBA is in the background", isOn: $pauseWhenInactive)
                }

                Section("Keyboard") {
                    LabeledContent("A / B", value: "X / Z")
                    LabeledContent("L / R", value: "A / S")
                    LabeledContent("Start / Select", value: "Return / Delete")
                    LabeledContent("D-pad", value: "Arrow keys")
                    LabeledContent("Fast forward", value: "Hold Space")
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("General", systemImage: "gearshape") }

            Form {
                Section("Scaling") {
                    Text("Games scale to fit while preserving their original aspect ratio.")
                        .foregroundStyle(.secondary)
                    Toggle("Smooth filtering", isOn: $filtering)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Video", systemImage: "display") }

            Form {
                Section("Output") {
                    Toggle("Mute audio", isOn: $audioMuted)
                    LabeledContent("Volume") {
                        Slider(value: $audioVolume, in: 0...1)
                            .frame(width: 240)
                            .disabled(audioMuted)
                    }
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Audio", systemImage: "speaker.wave.2") }

            Form {
                Section("Controllers") {
                    if session.controllerNames.isEmpty {
                        LabeledContent("Status", value: "No controller connected")
                    } else {
                        ForEach(session.controllerNames, id: \.self) { name in
                            Label(name, systemImage: "gamecontroller.fill")
                        }
                    }
                }

                Section("Default Mapping") {
                    LabeledContent("A / B", value: "A / B")
                    LabeledContent("L / R", value: "Left / Right shoulder")
                    LabeledContent("Start / Select", value: "Menu / Options")
                    LabeledContent("D-pad", value: "D-pad or left stick")
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Input", systemImage: "gamecontroller") }

            ShaderSettingsView(shaderStore: shaderStore)
                .tabItem { Label("Shaders", systemImage: "wand.and.stars") }
        }
        .frame(width: 540, height: 390)
        .scenePadding()
    }
}

private struct ShaderSettingsView: View {
    @ObservedObject var shaderStore: ShaderStore
    @State private var confirmsRemoval = false

    var body: some View {
        Form {
            Section("Display Look") {
                Picker(
                    "Look",
                    selection: Binding(
                        get: { shaderStore.selectedID },
                        set: shaderStore.select
                    )
                ) {
                    Section("Built-In Metal") {
                        ForEach(ShaderPreset.allCases) { preset in
                            Label(preset.displayName, systemImage: preset.systemImage)
                                .tag(preset.id)
                        }
                    }
                    if !shaderStore.shaders.isEmpty {
                        Section("Imported") {
                            ForEach(shaderStore.shaders) { shader in
                                Text(shader.displayName).tag(shader.selectionID)
                            }
                        }
                    }
                }

                Text(shaderStore.selectedDescription)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Custom Metal Shaders") {
                HStack {
                    Button("Import Metal Shader…") {
                        shaderStore.chooseAndImportShader()
                    }
                    Button("Show in Finder") {
                        shaderStore.revealShadersInFinder()
                    }
                    Button("Remove", role: .destructive) {
                        confirmsRemoval = true
                    }
                    .disabled(shaderStore.selectedCustomShader == nil)
                }

                Text("Import a .metal file that exports a fragment function named mgba_fragment. It is copied into mGBA’s library and can be selected immediately.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "Move this shader to the Trash?",
            isPresented: $confirmsRemoval
        ) {
            Button("Move to Trash", role: .destructive) {
                shaderStore.removeSelectedShader()
            }
        }
    }
}
