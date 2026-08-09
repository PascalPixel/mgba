import AppKit
import UniformTypeIdentifiers

@MainActor
enum ROMOpenPanel {
    static func chooseROM() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Open Game Boy ROM"
        panel.prompt = "Open"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = ["gba", "gb", "gbc", "zip"]
            .compactMap { UTType(filenameExtension: $0) }
        return panel.runModal() == .OK ? panel.url : nil
    }
}
