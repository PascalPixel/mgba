import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var session: EmulatorSession
    @EnvironmentObject private var shaderStore: ShaderStore
    @EnvironmentObject private var recentGames: RecentGamesStore
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("video.filtering") private var filtering = false
    @AppStorage("emulation.pauseWhenInactive") private var pauseWhenInactive = true
    @State private var pausedForInactivity = false
    @State private var showsOverlayToolbar = true
    @State private var toolbarHideWorkItem: DispatchWorkItem?

    var body: some View {
        ZStack {
            if session.hasROM {
                Color.black
            } else {
                Color(nsColor: .windowBackgroundColor)
            }

            if session.hasROM {
                MetalGameView(
                    frameMailbox: session.frameMailbox,
                    filtering: filtering,
                    shaderPreset: shaderStore.selectedPreset,
                    shaderURL: shaderStore.selectedURL,
                    onKey: session.setKey(bit:pressed:),
                    onFastForward: session.setFastForwarding,
                    onPointerActivity: { isActive in
                        if isActive {
                            registerPointerActivity()
                        } else {
                            scheduleToolbarHide(after: 0.45)
                        }
                    },
                    onShaderError: { message in
                        shaderStore.errorMessage = message
                        shaderStore.select(ShaderPreset.native.id)
                    }
                )

                if session.isPaused {
                    Text("Paused")
                        .font(.headline)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule())
                }

                if session.isFastForwarding {
                    VStack {
                        HStack {
                            Label("Fast Forward 4×", systemImage: "forward.fill")
                                .font(.callout.weight(.medium))
                                .padding(.horizontal, 13)
                                .padding(.vertical, 8)
                                .background(.regularMaterial, in: Capsule())
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(18)
                }

                if let status = session.statusMessage {
                    VStack {
                        Spacer()
                        Text(status)
                            .font(.callout.weight(.medium))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            .background(.regularMaterial, in: Capsule())
                            .padding(.bottom, 22)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

            } else {
                WelcomeView(
                    recentGames: recentGames.games,
                    openROM: session.chooseAndOpenROM,
                    openRecent: session.openROM,
                    removeRecent: recentGames.remove
                )
            }

        }
        .frame(minWidth: 480, minHeight: 320)
        .contentShape(Rectangle())
        .navigationTitle(session.gameTitle.isEmpty ? "mGBA" : session.gameTitle)
        .overlay(alignment: .top) {
            if showsOverlayToolbar {
                GameOverlayToolbar(onHoverChanged: toolbarHoverChanged)
                    .padding(.top, 12)
                    .padding(.horizontal, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(50)
            }
        }
        .animation(.easeOut(duration: 0.22), value: showsOverlayToolbar)
        .onHover { isInside in
            if isInside {
                registerPointerActivity()
            } else {
                scheduleToolbarHide(after: 0.45)
            }
        }
        .onContinuousHover { phase in
            switch phase {
            case .active:
                registerPointerActivity()
            case .ended:
                scheduleToolbarHide(after: 0.45)
            }
        }
        .onOpenURL(perform: session.openROM)
        .onAppear {
            showToolbar()
            scheduleToolbarHide(after: 2.0)
        }
        .onDisappear {
            toolbarHideWorkItem?.cancel()
            toolbarHideWorkItem = nil
        }
        .onChange(of: session.romURL) { _, url in
            if let url { recentGames.record(url) }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active where pausedForInactivity:
                session.setPaused(false)
                pausedForInactivity = false
            case .inactive where pauseWhenInactive && session.hasROM && !session.isPaused,
                 .background where pauseWhenInactive && session.hasROM && !session.isPaused:
                session.setFastForwarding(false)
                pausedForInactivity = true
                session.setPaused(true)
            default:
                break
            }
        }
        .onDrop(of: [UTType.fileURL], isTargeted: nil, perform: handleDrop)
        .alert(
            "Couldn’t Complete Action",
            isPresented: Binding(
                get: { session.errorMessage != nil },
                set: { if !$0 { session.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(session.errorMessage ?? "Unknown error")
        }
        .alert(
            "Shader Error",
            isPresented: Binding(
                get: { shaderStore.errorMessage != nil },
                set: { if !$0 { shaderStore.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(shaderStore.errorMessage ?? "Unknown error")
        }
    }

    private func registerPointerActivity() {
        showToolbar()
        scheduleToolbarHide(after: 1.4)
    }

    private func toolbarHoverChanged(_ isHovering: Bool) {
        if isHovering {
            showToolbar()
        } else {
            scheduleToolbarHide(after: 1.4)
        }
    }

    private func showToolbar() {
        toolbarHideWorkItem?.cancel()
        toolbarHideWorkItem = nil
        showsOverlayToolbar = true
    }

    private func scheduleToolbarHide(after delay: TimeInterval) {
        toolbarHideWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            showsOverlayToolbar = false
            toolbarHideWorkItem = nil
        }
        toolbarHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }) else {
            return false
        }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let url: URL?
            if let itemURL = item as? URL {
                url = itemURL
            } else if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else {
                url = nil
            }
            if let url {
                DispatchQueue.main.async {
                    session.openROM(url)
                }
            }
        }
        return true
    }
}

private struct WelcomeView: View {
    let recentGames: [RecentGame]
    let openROM: () -> Void
    let openRecent: (URL) -> Void
    let removeRecent: (RecentGame) -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: WelcomeArtwork.image)
                .resizable()
                .scaledToFill()
                .frame(width: 220, height: 145)
                .clipped()
                .accessibilityLabel("mGBA")

            VStack(spacing: 5) {
                Text("Ready to Play")
                    .font(.title2.weight(.semibold))
                Text("Open a Game Boy, Game Boy Color, or Game Boy Advance ROM.")
                    .foregroundStyle(.secondary)
            }

            Button("Open ROM…", action: openROM)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

            Text("You can also drag a ROM into this window.")
                .font(.callout)
                .foregroundStyle(.tertiary)

            if !recentGames.isEmpty {
                Divider()
                    .frame(width: 420)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Recent Games")
                        .font(.headline)

                    ForEach(recentGames.prefix(5)) { game in
                        Button {
                            openRecent(game.url)
                        } label: {
                            HStack(spacing: 11) {
                                Image(systemName: "gamecontroller")
                                    .frame(width: 20)
                                    .foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(game.displayName)
                                        .foregroundStyle(.primary)
                                    Text(game.folderName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Remove from Recents") {
                                removeRecent(game)
                            }
                        }
                    }
                }
                .frame(width: 420)
            }
        }
        .padding(24)
    }
}

private enum WelcomeArtwork {
    private static let bundle: Bundle = {
        if let resourceURL = Bundle.main.resourceURL,
           let packagedBundle = Bundle(
               url: resourceURL.appendingPathComponent("mGBANative_mGBAApp.bundle")
           ) {
            return packagedBundle
        }
        return .module
    }()

    static let image: NSImage = {
        guard let url = bundle.url(
            forResource: "mgba-welcome",
            withExtension: "png"
        ), let image = NSImage(contentsOf: url) else {
            return NSImage(named: NSImage.applicationIconName) ?? NSImage()
        }
        return image
    }()
}
