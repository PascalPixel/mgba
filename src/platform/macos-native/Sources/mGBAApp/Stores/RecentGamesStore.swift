import Foundation

struct RecentGame: Codable, Hashable, Identifiable {
    let path: String
    let lastOpened: Date

    var id: String { path }
    var url: URL { URL(fileURLWithPath: path) }
    var displayName: String { url.deletingPathExtension().lastPathComponent }
    var folderName: String { url.deletingLastPathComponent().lastPathComponent }
}

@MainActor
final class RecentGamesStore: ObservableObject {
    @Published private(set) var games: [RecentGame] = []

    private let defaultsKey = "library.recentGames"
    private let maximumCount = 8

    init() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([RecentGame].self, from: data) else {
            return
        }
        games = decoded.filter { FileManager.default.fileExists(atPath: $0.path) }
        persist()
    }

    func record(_ url: URL) {
        let path = url.standardizedFileURL.path
        games.removeAll { $0.path == path }
        games.insert(RecentGame(path: path, lastOpened: Date()), at: 0)
        games = Array(games.prefix(maximumCount))
        persist()
    }

    func remove(_ game: RecentGame) {
        games.removeAll { $0.id == game.id }
        persist()
    }

    func clear() {
        games.removeAll()
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(games) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}
