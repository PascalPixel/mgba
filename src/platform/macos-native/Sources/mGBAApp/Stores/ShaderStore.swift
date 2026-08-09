import AppKit
import Foundation
import UniformTypeIdentifiers

struct ManagedShader: Identifiable, Hashable {
    var id: String { fileName }
    let fileName: String
    let url: URL

    var selectionID: String { "custom:\(fileName)" }

    var displayName: String {
        url.deletingPathExtension().lastPathComponent
    }
}

@MainActor
final class ShaderStore: ObservableObject {
    @Published private(set) var shaders: [ManagedShader] = []
    @Published private(set) var selectedID: String
    @Published var errorMessage: String?

    private let selectionKey = "video.shaderSelection"
    private let legacySelectionKey = "video.shaderFileName"
    private let fileManager = FileManager.default

    init() {
        let defaults = UserDefaults.standard
        if let selection = defaults.string(forKey: selectionKey) {
            selectedID = selection
        } else if let legacyFileName = defaults.string(forKey: legacySelectionKey) {
            selectedID = Self.customID(for: legacyFileName)
        } else {
            selectedID = ShaderPreset.native.id
        }
        refresh()
    }

    var selectedPreset: ShaderPreset {
        ShaderPreset(rawValue: selectedID) ?? .native
    }

    var selectedURL: URL? {
        guard let fileName = selectedCustomFileName else { return nil }
        return shaders.first(where: { $0.fileName == fileName })?.url
    }

    var selectedDescription: String {
        if let shader = selectedCustomShader {
            return "Custom Metal shader: \(shader.displayName)"
        }
        return selectedPreset.detail
    }

    var selectedCustomShader: ManagedShader? {
        guard let fileName = selectedCustomFileName else { return nil }
        return shaders.first(where: { $0.fileName == fileName })
    }

    func select(_ id: String) {
        guard ShaderPreset(rawValue: id) != nil || Self.customFileName(from: id) != nil else {
            return
        }
        selectedID = id
        UserDefaults.standard.set(id, forKey: selectionKey)
    }

    func chooseAndImportShader() {
        let panel = NSOpenPanel()
        panel.title = "Import Metal Shader"
        panel.prompt = "Import"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "metal")].compactMap { $0 }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importShader(at: url)
    }

    func importShader(at sourceURL: URL) {
        do {
            let directory = try shaderDirectory()
            let destination = uniqueDestination(
                for: sourceURL.lastPathComponent,
                in: directory
            )
            try fileManager.copyItem(at: sourceURL, to: destination)
            refresh()
            select(Self.customID(for: destination.lastPathComponent))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func revealShadersInFinder() {
        do {
            NSWorkspace.shared.activateFileViewerSelecting([try shaderDirectory()])
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeSelectedShader() {
        guard let shader = selectedCustomShader else { return }
        do {
            try fileManager.trashItem(at: shader.url, resultingItemURL: nil)
            select(ShaderPreset.native.id)
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refresh() {
        do {
            let directory = try shaderDirectory()
            shaders = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            .filter { $0.pathExtension.lowercased() == "metal" }
            .map { ManagedShader(fileName: $0.lastPathComponent, url: $0) }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }

            if let selectedCustomFileName,
               !shaders.contains(where: { $0.fileName == selectedCustomFileName }) {
                select(ShaderPreset.native.id)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func shaderDirectory() throws -> URL {
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = applicationSupport
            .appendingPathComponent("io.mgba.mGBANative", isDirectory: true)
            .appendingPathComponent("Shaders", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func uniqueDestination(for fileName: String, in directory: URL) -> URL {
        let source = URL(fileURLWithPath: fileName)
        let base = source.deletingPathExtension().lastPathComponent
        let ext = source.pathExtension
        var candidate = directory.appendingPathComponent(fileName)
        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base) \(suffix).\(ext)")
            suffix += 1
        }
        return candidate
    }

    private var selectedCustomFileName: String? {
        Self.customFileName(from: selectedID)
    }

    private static func customID(for fileName: String) -> String {
        "custom:\(fileName)"
    }

    private static func customFileName(from id: String) -> String? {
        guard id.hasPrefix("custom:") else { return nil }
        let fileName = String(id.dropFirst("custom:".count))
        return fileName.isEmpty ? nil : fileName
    }
}
