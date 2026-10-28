import Foundation

/// 端末内ランキングを試練とランダムで分けて保存する。
enum LeaderboardMode: String, Codable, Hashable {
    case trial
    case random

    var title: String {
        switch self {
        case .trial: "試練の迷宮"
        case .random: "ランダムステージ"
        }
    }
}

struct LeaderboardEntry: Codable, Identifiable {
    let id: UUID
    var playerName: String
    let clearTime: TimeInterval
    let recordedAt: Date
    let seed: UInt64?

    init(
        id: UUID = UUID(),
        playerName: String,
        clearTime: TimeInterval,
        recordedAt: Date = Date(),
        seed: UInt64?
    ) {
        self.id = id
        self.playerName = playerName
        self.clearTime = clearTime
        self.recordedAt = recordedAt
        self.seed = seed
    }

    static func cleanedPlayerName(_ name: String) -> String? {
        let value = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(16))
        return value.isEmpty ? nil : value
    }

    var isValidForSubmission: Bool {
        guard Self.cleanedPlayerName(playerName) == playerName,
              clearTime.isFinite, clearTime >= 0, clearTime < 86_400 else { return false }
        return true
    }
}

enum LocalLeaderboard {
    private static let limit = 100

    static func load(
        _ mode: LeaderboardMode,
        defaults: UserDefaults = .standard
    ) -> [LeaderboardEntry] {
        guard let data = defaults.data(forKey: storageKey(for: mode)),
              let entries = try? JSONDecoder().decode([LeaderboardEntry].self, from: data) else {
            return []
        }
        return Array(sortedEntries(entries).prefix(limit))
    }

    @discardableResult
    static func add(
        _ entry: LeaderboardEntry,
        to mode: LeaderboardMode,
        defaults: UserDefaults = .standard
    ) -> [LeaderboardEntry] {
        let entries = Array(sortedEntries(load(mode, defaults: defaults) + [entry]).prefix(limit))
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: storageKey(for: mode))
        }
        return entries
    }

    /// 既存のランキング記録の名前だけを変更する。
    @discardableResult
    static func updateName(
        for entryID: UUID,
        to playerName: String,
        in mode: LeaderboardMode,
        defaults: UserDefaults = .standard
    ) -> Bool {
        var entries = load(mode, defaults: defaults)
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return false }
        entries[index].playerName = playerName
        guard let data = try? JSONEncoder().encode(entries) else { return false }
        defaults.set(data, forKey: storageKey(for: mode))
        return true
    }

    static func sortedEntries(_ entries: [LeaderboardEntry]) -> [LeaderboardEntry] {
        entries.sorted {
            if $0.clearTime == $1.clearTime {
                if $0.recordedAt == $1.recordedAt {
                    return $0.id.uuidString < $1.id.uuidString
                }
                return $0.recordedAt < $1.recordedAt
            }
            return $0.clearTime < $1.clearTime
        }
    }

    private static func storageKey(for mode: LeaderboardMode) -> String {
        "dungeon.leaderboard.\(mode.rawValue)"
    }
}
