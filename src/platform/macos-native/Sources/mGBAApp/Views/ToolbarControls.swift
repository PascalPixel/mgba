import SwiftUI

struct GameOverlayToolbar: View {
    @EnvironmentObject private var session: EmulatorSession
    let onHoverChanged: (Bool) -> Void
    let onPresentationChanged: (Bool) -> Void

    var body: some View {
        HStack(spacing: 9) {
            Button(action: session.chooseAndOpenROM) {
                Label("Open ROM", systemImage: "folder")
            }

            Button(action: session.togglePause) {
                Label(
                    session.isPaused ? "Resume" : "Pause",
                    systemImage: session.isPaused ? "play.fill" : "pause.fill"
                )
            }
            .disabled(!session.hasROM)

            Menu {
                Button("Save to Slot 1") {
                    session.saveState(slot: 1)
                }
                Button("Load Slot 1") {
                    session.loadState(slot: 1)
                }
                .disabled(!session.availableStateSlots.contains(1))
            } label: {
                Label("State", systemImage: "clock.arrow.circlepath")
            }
            .disabled(!session.hasROM)

            Divider()
                .frame(height: 20)

            DisplayToolbarMenu()
            AudioToolbarControl(onPresentationChanged: onPresentationChanged)

            SettingsLink {
                Label("Settings", systemImage: "gearshape")
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .controlSize(.large)
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background(.thickMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(.white.opacity(0.22), lineWidth: 0.75)
        }
        .shadow(color: .black.opacity(0.34), radius: 14, y: 6)
        .onHover(perform: onHoverChanged)
    }
}

struct DisplayToolbarMenu: View {
    @EnvironmentObject private var shaderStore: ShaderStore
    @AppStorage("video.filtering") private var filtering = false

    var body: some View {
        Menu {
            Picker(
                "Display Look",
                selection: Binding(
                    get: { shaderStore.selectedID },
                    set: shaderStore.select
                )
            ) {
                ForEach(ShaderPreset.allCases) { preset in
                    Label(preset.displayName, systemImage: preset.systemImage)
                        .tag(preset.id)
                }
                if !shaderStore.shaders.isEmpty {
                    Divider()
                    ForEach(shaderStore.shaders) { shader in
                        Text(shader.displayName).tag(shader.selectionID)
                    }
                }
            }

            Divider()
            Toggle("Smooth Filtering", isOn: $filtering)

            Divider()
            Button("Import Metal Shader…") {
                shaderStore.chooseAndImportShader()
            }
        } label: {
            Label("Display", systemImage: "display")
        }
        .help("Display and shader options")
    }
}

struct AudioToolbarControl: View {
    @AppStorage("audio.volume") private var volume = 0.8
    @AppStorage("audio.muted") private var muted = false
    @State private var showsPopover = false
    let onPresentationChanged: (Bool) -> Void

    var body: some View {
        Button {
            showsPopover.toggle()
        } label: {
            Label("Audio", systemImage: speakerSymbol)
        }
        .help("Audio options")
        .popover(isPresented: $showsPopover, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 14) {
                Toggle("Mute", isOn: $muted)

                HStack(spacing: 10) {
                    Image(systemName: "speaker.fill")
                        .foregroundStyle(.secondary)
                    Slider(value: $volume, in: 0...1)
                        .frame(width: 190)
                        .disabled(muted)
                    Image(systemName: "speaker.wave.3.fill")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(18)
        }
        .onChange(of: showsPopover) { _, isPresented in
            onPresentationChanged(isPresented)
        }
    }

    private var speakerSymbol: String {
        if muted || volume == 0 { return "speaker.slash.fill" }
        if volume < 0.34 { return "speaker.fill" }
        if volume < 0.67 { return "speaker.wave.1.fill" }
        return "speaker.wave.2.fill"
    }
}
