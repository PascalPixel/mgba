import AppKit

enum GameWindowActions {
    @MainActor
    static func toggleFullScreen() {
        NSApp.keyWindow?.toggleFullScreen(nil)
    }
}
