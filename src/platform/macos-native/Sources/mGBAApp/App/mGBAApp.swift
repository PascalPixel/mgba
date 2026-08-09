import AppKit
import SwiftUI

@main
struct mGBAApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var session = EmulatorSession()
    @StateObject private var shaderStore = ShaderStore()
    @StateObject private var recentGames = RecentGamesStore()

    var body: some Scene {
        Window("mGBA", id: "game") {
            ContentView()
                .environmentObject(session)
                .environmentObject(shaderStore)
                .environmentObject(recentGames)
        }
        .defaultSize(width: 960, height: 680)
        .windowStyle(.hiddenTitleBar)
        .commands {
            AppCommands(session: session, recentGames: recentGames)
        }

        Settings {
            SettingsView()
                .environmentObject(session)
                .environmentObject(shaderStore)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        UserDefaults.standard.register(defaults: [
            "audio.volume": 0.8,
            "audio.muted": false,
        ])
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

private struct AppCommands: Commands {
    @ObservedObject var session: EmulatorSession
    @ObservedObject var recentGames: RecentGamesStore
    @AppStorage("video.filtering") private var filtering = false

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open ROM…") {
                session.chooseAndOpenROM()
            }
            .keyboardShortcut("o")

            Menu("Open Recent") {
                if recentGames.games.isEmpty {
                    Text("No Recent Games")
                } else {
                    ForEach(recentGames.games) { game in
                        Button(game.displayName) {
                            session.openROM(game.url)
                        }
                    }
                    Divider()
                    Button("Clear Menu") {
                        recentGames.clear()
                    }
                }
            }
        }

        CommandMenu("Emulation") {
            Button(session.isPaused ? "Resume" : "Pause") {
                session.togglePause()
            }
            .keyboardShortcut("p")
            .disabled(!session.hasROM)

            Button("Reset") {
                session.reset()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(!session.hasROM)

            Divider()

            Button(session.isFastForwarding ? "Stop Fast Forward" : "Fast Forward") {
                session.setFastForwarding(!session.isFastForwarding)
            }
            .disabled(!session.hasROM || session.isPaused)
        }

        CommandMenu("State") {
            Button("Quick Save — Slot 1") {
                session.saveState(slot: 1)
            }
            .keyboardShortcut("s")
            .disabled(!session.hasROM)

            Button("Quick Load — Slot 1") {
                session.loadState(slot: 1)
            }
            .keyboardShortcut("l")
            .disabled(!session.availableStateSlots.contains(1))

            Divider()

            Menu("Save State") {
                ForEach(1...9, id: \.self) { slot in
                    Button("Slot \(slot)") {
                        session.saveState(slot: slot)
                    }
                }
            }
            .disabled(!session.hasROM)

            Menu("Load State") {
                ForEach(1...9, id: \.self) { slot in
                    Button("Slot \(slot)") {
                        session.loadState(slot: slot)
                    }
                    .disabled(!session.availableStateSlots.contains(slot))
                }
            }
        }

        CommandGroup(after: .toolbar) {
            Button("Toggle Full Screen") {
                GameWindowActions.toggleFullScreen()
            }
            .keyboardShortcut("f", modifiers: [.command, .control])

            Divider()

            Toggle("Smooth Filtering", isOn: $filtering)
        }
    }
}
