import CryptoKit
import Foundation

struct GameStorage {
    let identifier: String
    let saveURL: URL
    let statesDirectory: URL

    func stateURL(slot: Int) -> URL {
        statesDirectory.appendingPathComponent("slot-\(slot).mgba-state")
    }
}

enum AppStoragePaths {
    static func prepare(for romURL: URL) throws -> GameStorage {
        let root = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("io.mgba.mGBANative", isDirectory: true)

        let identifier = try gameIdentifier(for: romURL)
        let saves = root.appendingPathComponent("Saves", isDirectory: true)
        let states = root
            .appendingPathComponent("States", isDirectory: true)
            .appendingPathComponent(identifier, isDirectory: true)

        try FileManager.default.createDirectory(at: saves, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: states, withIntermediateDirectories: true)

        let saveURL = saves.appendingPathComponent("\(identifier).sav")
        let legacySaveURL = romURL.deletingPathExtension().appendingPathExtension("sav")
        if !FileManager.default.fileExists(atPath: saveURL.path),
           FileManager.default.fileExists(atPath: legacySaveURL.path) {
            try FileManager.default.copyItem(at: legacySaveURL, to: saveURL)
        }

        return GameStorage(
            identifier: identifier,
            saveURL: saveURL,
            statesDirectory: states
        )
    }

    private static func gameIdentifier(for romURL: URL) throws -> String {
        let romData = try Data(contentsOf: romURL, options: .mappedIfSafe)
        let digest = SHA256.hash(data: romData)
            .prefix(8)
            .map { String(format: "%02x", $0) }
            .joined()
        let stem = romURL.deletingPathExtension().lastPathComponent
            .lowercased()
            .replacingOccurrences(
                of: "[^a-z0-9_-]+",
                with: "-",
                options: .regularExpression
            )
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return "\(stem.isEmpty ? "game" : stem)-\(digest)"
    }
}
