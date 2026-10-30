import Foundation

@main
struct CoreLogicTests {
    private static var assertionCount = 0

    @MainActor
    static func main() async throws {
        if CommandLine.arguments.contains("--determinism-probe") {
            for seed in 0..<256 {
                print(mapSignature(RandomMazeGenerator.generate(seed: UInt64(seed))))
            }
            return
        }

        try testNewEnemyEncounters()

        try testEnemyBalanceDesign()
        print("PASS: 敵バランス(1戦で約半分・戦闘だけでは死なない)")

        try testTrapSelection()
        print("PASS: 罠抽選の境界値・除外・発生率補正")

        try testStageTimingPolicy()
        print("PASS: 初回タイム計測ポリシー")

        try testGeneratedMazesAcrossSeeds()
        print("PASS: 500 seed の迷宮構造・到達可能性")

        try testLeaderboardOrderingAndModeIsolation()
        print("PASS: ランキング順とモード分離")

        try testLeaderboardLimit()
        print("PASS: ランキング上限100件")

        try testLeaderboardNameUpdate()
        print("PASS: 名前更新時の記録情報維持")

        try testAudioVolumeSettings()
        print("PASS: 音量設定の初期値・範囲補正・保存")

        assertionCount += try ShiritoriLogicTests.run()
        assertionCount += try ShiritoriGameManagerTests.run()
        assertionCount += try await GameManagerTests.run()

        print("完了: \(assertionCount) assertions")
    }

    private static func testNewEnemyEncounters() throws {
        var seen: [EnemyKind] = []
        for seed in 0..<500 {
            let map = RandomMazeGenerator.generate(seed: UInt64(seed))
            for kind in map.enemyKinds.values where !seen.contains(kind) { seen.append(kind) }
        }
        for kind in EnemyKind.randomEncounterKinds {
            try expect(seen.contains(kind), "ランダム迷宮で \(kind.name) が出現する")
            try expect(kind.maxHP > 0 && kind.attackDamage > 0, "\(kind.name) の能力値が有効")
            for text in [kind.encounterDialogue, kind.defeatDialogue] {
                try expect(!text.isEmpty && text.split(separator: "\n").count <= 3, "\(kind.name) のセリフが3行以内")
            }
        }
        try expect(!seen.contains(.dragon), "ランダム迷宮にラスボスが混ざらない")
        print("PASS: 新敵の出現・能力値・セリフ")
    }

    /// 「全員クリアできるが、仕組みを知らないと危なく見える」バランスを数値で守る。
    /// 戦闘はプレイヤーが先に攻撃するので、受ける反撃は「倒すまでの攻撃回数 - 1」回。
    private static func testEnemyBalanceDesign() throws {
        let playerMaxHP = GameState.playerMaxHP
        let swordlessDamage = 5
        let swordDamage = 10

        func damageTaken(from kind: EnemyKind, playerDamage: Int) -> Int {
            let hitsToDefeat = (kind.maxHP + playerDamage - 1) / playerDamage
            return (hitsToDefeat - 1) * kind.attackDamage
        }

        // 剣なしで戦う最初のテーマ敵は、どのテーマでもHPの4割〜5割を削る。
        var worstFirstFight = 0
        for theme in DungeonTheme.allCases {
            let kind = EnemyKind.themeEnemy(for: theme)
            let firstFight = damageTaken(from: kind, playerDamage: swordlessDamage)
            try expect((playerMaxHP * 4 / 10...playerMaxHP / 2).contains(firstFight),
                       "\(kind.name) との初戦はHPの約半分(4〜5割)を削る")
            worstFirstFight = max(worstFirstFight, firstFight)
        }

        // 剣を取った後の戦い。ランダム迷宮の通常敵はスライムかスケルトン。
        let gargoyleFight = damageTaken(from: .gargoyle, playerDamage: swordDamage)
        let normalFight = EnemyKind.randomEncounterKinds
            .map { damageTaken(from: $0, playerDamage: swordDamage) }
            .max() ?? 0

        // 回復なし・逃走なしで3戦連続しても、戦闘だけでは死なず2以上残る。
        try expect(worstFirstFight + gargoyleFight + normalFight <= playerMaxHP - 2,
                   "3戦連続でもHPが2以上残る")
        // 戦闘後に毒の罠(最大5ダメージ)を踏んでも、通常は1戦目後に耐えられる余裕がある。
        try expect(playerMaxHP - worstFirstFight > 5, "初戦後に毒の罠を1つ踏んでも倒れない")

        // 能力値がHP・ダメージの前提(1回の反撃でHPの半分を超えない)を壊していない。
        for kind in EnemyKind.allCases {
            try expect(kind.attackDamage * 2 <= playerMaxHP, "\(kind.name) の1回の反撃がHPの半分以内")
        }
    }

    private static func testTrapSelection() throws {
        let groups: [(TrapGroup, [(Int, TrapKind)])] = [
            (.a, [(1, .turnRight), (30, .turnRight), (31, .doubleFlick), (60, .doubleFlick), (61, .hpDrain), (100, .hpDrain)]),
            (.b, [(1, .warpToStart), (30, .warpToStart), (31, .randomWarp), (60, .randomWarp), (61, .warpBeforeKey), (100, .warpBeforeKey)]),
            (.c, [(1, .forceGameOver), (10, .forceGameOver), (11, .unexploded), (100, .unexploded)])
        ]
        for (group, cases) in groups {
            for (roll, expected) in cases {
                var upper = 0
                let actual = selectTrap(in: group, excluding: [], drawRoll: { upper = $0; return roll })
                try expect(upper == 100 && actual == expected, "抽選境界 \(group): \(roll)")
            }
            for roll in [0, 101] {
                try expect(selectTrap(in: group, excluding: [], drawRoll: { _ in roll }) == nil, "範囲外ロールを拒否")
            }
            var drew = false
            let none = selectTrap(in: group, excluding: Set(TrapKind.allCases), drawRoll: { _ in drew = true; return 1 })
            try expect(none == nil && !drew, "全除外時は乱数を呼ばない")
        }
        for (roll, expected) in [(1, TrapKind.doubleFlick), (30, .doubleFlick), (31, .hpDrain), (70, .hpDrain)] {
            var upper = 0
            let actual = selectTrap(in: .a, excluding: [.turnRight, .randomWarp], drawRoll: { upper = $0; return roll })
            try expect(upper == 70 && actual == expected, "除外後の境界 \(roll)、他グループの除外は無影響")
        }
        let kinds: [TrapKind] = [.turnRight, .doubleFlick, .hpDrain]
        for (input, expected) in [([30,30,40], [30,30,40]), ([20,20,30], [20,20,60]), ([40,40,40], [20,40,40]), ([0,0,0], [100,0,0])] {
            let result = normalizedTrapRates(in: .a, rates: Array(zip(kinds, input)))
            try expect(result?.map(\.rate) == expected, "発生率補正 \(input)、同率時は先頭を補正")
        }
        for rates: [(kind: TrapKind, rate: Int)] in [
            [(.turnRight, 100)],
            [(.turnRight, 30), (.turnRight, 30), (.hpDrain, 40)],
            [(.turnRight, 30), (.randomWarp, 30), (.hpDrain, 40)],
            [(.turnRight, -1), (.doubleFlick, 61), (.hpDrain, 40)],
            [(.turnRight, 101), (.doubleFlick, 0), (.hpDrain, 0)],
            [(.turnRight, 100), (.doubleFlick, 100), (.hpDrain, 100)]
        ] {
            try expect(normalizedTrapRates(in: .a, rates: rates) == nil, "不正設定・補正不能を拒否")
        }
    }

    // 同距離の経路は北・東・南・西の順で選ぶという現在の生成規約を検証する。
    private static func shortestTestPath(from start: GridPos, to goal: GridPos, in map: MapData) -> [GridPos] {
        var queue = [start]
        var visited: Set<GridPos> = [start]
        var parent: [GridPos: GridPos] = [:]
        var index = 0
        while index < queue.count {
            let current = queue[index]
            index += 1
            if current == goal { break }
            for direction in [Direction.north, .east, .south, .west] {
                let next = current.moved(direction)
                if !map.cell(at: next).isWall && visited.insert(next).inserted {
                    parent[next] = current
                    queue.append(next)
                }
            }
        }
        guard visited.contains(goal) else { return [] }
        var path = [goal]
        while let previous = parent[path.last!] { path.append(previous) }
        return path.reversed()
    }

    private static func testStageTimingPolicy() throws {
        let tutorial = Stages.tutorial
        let trial = Stages.trial
        let random = Stages.random(seed: 42)
        let seededTutorial = Stage(
            title: tutorial.title,
            map: tutorial.map,
            requiresKey: tutorial.requiresKey,
            isStepByStepTutorial: true,
            seed: 43,
            shiritoriStageKind: tutorial.shiritoriStageKind,
            dungeonTheme: tutorial.dungeonTheme,
            requiresSwordForKey: tutorial.requiresSwordForKey
        )

        try expect(!StageTimingPolicy.startsTimer(for: tutorial), "チュートリアルは計時しない")
        try expect(StageTimingPolicy.recordKey(for: tutorial) == nil, "チュートリアルの記録キーがない")
        try expect(StageTimingPolicy.leaderboardMode(for: tutorial) == nil, "チュートリアルはランキング対象外")
        try expect(!StageTimingPolicy.startsTimer(for: seededTutorial), "seedがあってもチュートリアルは計時しない")
        try expect(StageTimingPolicy.leaderboardMode(for: seededTutorial) == nil, "seedがあってもチュートリアルはランキング対象外")

        try expect(StageTimingPolicy.startsTimer(for: trial), "試練は初回から計時する")
        try expect(StageTimingPolicy.recordKey(for: trial) == "dungeon.bestClearTime.trial", "試練の最短タイムキー")
        try expect(StageTimingPolicy.leaderboardMode(for: trial) == .trial, "試練ランキング")

        try expect(StageTimingPolicy.startsTimer(for: random), "ランダムは初回から計時する")
        try expect(StageTimingPolicy.recordKey(for: random) == "dungeon.bestClearTime.random", "ランダムの最短タイムキー")
        try expect(StageTimingPolicy.leaderboardMode(for: random) == .random, "ランダムランキング")
    }

    private static func testGeneratedMazesAcrossSeeds() throws {
        var trapTypeCounts: [TrapKind: Int] = [:]
        var hasDuplicateTrapTypes = false
        for seed in 0..<500 {
            let map = RandomMazeGenerator.generate(seed: UInt64(seed))
            let cells = map.cells.flatMap { $0 }
            try expect(map.rows == 17 && map.cols == 17, "seed \(seed): 17x17")
            try expect(cells.filter { $0 == .start }.count == 1, "seed \(seed): start が1つ")
            try expect(cells.filter { $0 == .goal }.count == 1, "seed \(seed): goal が1つ")
            try expect(cells.filter { $0 == .sword }.count == 0, "seed \(seed): 剣はマスに置かずテーマ敵がドロップ")
            try expect(cells.filter { $0 == .key }.count == 1, "seed \(seed): key が1つ")
            try expect(cells.filter { $0 == .enemy }.count == 3, "seed \(seed): enemy が3つ")
            try expect(cells.filter { $0.isTrap }.count == 2, "seed \(seed): trap が2つ")
            try expect(map.enemyKinds.count == 3, "seed \(seed): 敵の種類定義が3つ")
            try expect(map.enemyKinds.values.filter { $0 == .gargoyle }.count == 1, "seed \(seed): gargoyle は必ず1体")
            try expect(map.enemyKinds.values.filter { EnemyKind.randomEncounterKinds.contains($0) }.count == 1, "seed \(seed): 通常敵はスライムかスケルトンが1体")
            let themeKind = EnemyKind.themeEnemy(for: DungeonTheme.forSeed(UInt64(seed)))
            try expect(map.enemyKinds.values.filter { $0 == themeKind }.count == 1, "seed \(seed): テーマ敵が1体")
            try expect(themeKind.dropsSword && themeKind.counterattackAudioResource != nil, "seed \(seed): テーマ敵は剣をドロップし反撃音を持つ")
            try expect(map.trapKinds.count == 2, "seed \(seed): trap の種類定義が2つ")
            try expect(map.trapKinds.values.allSatisfy { $0.group == .a }, "seed \(seed): trap はグループA")
            if Set(map.trapKinds.values).count == 1 {
                hasDuplicateTrapTypes = true
            }
            for kind in map.trapKinds.values {
                trapTypeCounts[kind, default: 0] += 1
            }

            let reachable = reachablePositions(from: map.startPosition, in: map)
            let walkable = Set(map.cells.indices.flatMap { y in
                map.cells[y].indices.compactMap { x -> GridPos? in
                    map.cells[y][x].isWall ? nil : GridPos(x: x, y: y)
                }
            })
            try expect(reachable == walkable, "seed \(seed): 通路が全て連結")
            try expect(map.trapKinds.keys.allSatisfy { reachable.contains($0) }, "seed \(seed): trap に到達可能")

            let goal = try unwrap(walkable.first { map.cell(at: $0) == .goal }, "ゴールが存在")
            let path = shortestTestPath(from: map.startPosition, to: goal, in: map)
            let events = path.map { map.cell(at: $0) }.filter { $0 != .floor }
            try expect(events == [.start, .enemy, .enemy, .key, .enemy, .goal], "seed \(seed): S→テーマ敵→ガーゴイル→鍵→通常敵→G、選択経路に罠なし")
            try expect(Set(path).isDisjoint(with: map.trapKinds.keys), "seed \(seed): 罠は選択された最短経路外")
            let pathEnemies = path.filter { map.cell(at: $0) == .enemy }
            try expect(pathEnemies.count == 3, "seed \(seed): 経路上に敵が3体")
            try expect(map.enemyKinds[pathEnemies[0]] == themeKind, "seed \(seed): 最初の敵はテーマ敵(剣ドロップ)")
            try expect(map.enemyKinds[pathEnemies[1]] == .gargoyle, "seed \(seed): 剣の後の敵はガーゴイル")
            let repeated = RandomMazeGenerator.generate(seed: UInt64(seed))
            try expect(mapSignature(map) == mapSignature(repeated), "seed \(seed): 同じseedで同じマップ")
        }
        try expect(hasDuplicateTrapTypes, "異なる2マスに同じグループA罠が生成されるseedがある")
        try expect(trapTypeCounts.count == 3, "500 seedでグループAの全種類が抽選される")
    }

    private static func testLeaderboardOrderingAndModeIsolation() throws {
        try withIsolatedDefaults { defaults in
            let earlier = LeaderboardEntry(
                id: stableID(1),
                playerName: "先の登録",
                clearTime: 12.0,
                recordedAt: Date(timeIntervalSince1970: 100),
                seed: nil
            )
            let later = LeaderboardEntry(
                id: stableID(2),
                playerName: "後の登録",
                clearTime: 12.0,
                recordedAt: Date(timeIntervalSince1970: 200),
                seed: nil
            )
            let faster = LeaderboardEntry(
                id: stableID(3),
                playerName: "最速",
                clearTime: 11.9,
                recordedAt: Date(timeIntervalSince1970: 300),
                seed: nil
            )

            _ = LocalLeaderboard.add(later, to: .trial, defaults: defaults)
            _ = LocalLeaderboard.add(earlier, to: .trial, defaults: defaults)
            _ = LocalLeaderboard.add(faster, to: .trial, defaults: defaults)

            let trial = LocalLeaderboard.load(.trial, defaults: defaults)
            try expect(trial.map(\.id) == [faster.id, earlier.id, later.id], "タイム昇順、同タイムは登録日時昇順")
            try expect(LocalLeaderboard.load(.random, defaults: defaults).isEmpty, "試練とランダムのランキングを分離")
        }
    }

    private static func testLeaderboardLimit() throws {
        try withIsolatedDefaults { defaults in
            for index in 0..<105 {
                let entry = LeaderboardEntry(
                    id: stableID(index + 100),
                    playerName: "Player\(index)",
                    clearTime: TimeInterval(index),
                    recordedAt: Date(timeIntervalSince1970: TimeInterval(index)),
                    seed: UInt64(index)
                )
                _ = LocalLeaderboard.add(entry, to: .random, defaults: defaults)
            }

            let entries = LocalLeaderboard.load(.random, defaults: defaults)
            try expect(entries.count == 100, "保存・読込件数を100件に制限")
            try expect(entries.first?.clearTime == 0, "最速記録を保持")
            try expect(entries.last?.clearTime == 99, "101位以降を除外")
        }
    }

    private static func testLeaderboardNameUpdate() throws {
        try withIsolatedDefaults { defaults in
            let original = LeaderboardEntry(
                id: stableID(500),
                playerName: "修正前",
                clearTime: 34.5,
                recordedAt: Date(timeIntervalSince1970: 1234),
                seed: 9876
            )
            _ = LocalLeaderboard.add(original, to: .trial, defaults: defaults)

            try expect(
                LocalLeaderboard.updateName(for: original.id, to: "修正後", in: .trial, defaults: defaults),
                "保存済みの名前を更新"
            )
            let updated = try unwrap(
                LocalLeaderboard.load(.trial, defaults: defaults).first,
                "更新後の記録を再読込"
            )
            try expect(updated.playerName == "修正後", "新しい名前を保存")
            try expect(updated.id == original.id, "記録IDを維持")
            try expect(updated.clearTime == original.clearTime, "タイムを維持")
            try expect(updated.recordedAt == original.recordedAt, "登録日時を維持")
            try expect(updated.seed == original.seed, "seedを維持")
        }
    }

    private static func testAudioVolumeSettings() throws {
        try withIsolatedDefaults { defaults in
            let key = AudioVolumeSettings.backgroundMusicKey
            try expect(AudioVolumeSettings.load(forKey: key, defaults: defaults) == 0.5, "未設定時は従来の音量0.5")
            AudioVolumeSettings.save(0.8, forKey: key, defaults: defaults)
            try expect(AudioVolumeSettings.load(forKey: key, defaults: defaults) == 0.8, "保存した音量を読み込む")
            AudioVolumeSettings.save(0, forKey: key, defaults: defaults)
            try expect(AudioVolumeSettings.load(forKey: key, defaults: defaults) == 0, "0(消音)を保存できる")
            AudioVolumeSettings.save(5, forKey: key, defaults: defaults)
            try expect(AudioVolumeSettings.load(forKey: key, defaults: defaults) == 1, "上限1に補正")
            AudioVolumeSettings.save(-1, forKey: key, defaults: defaults)
            try expect(AudioVolumeSettings.load(forKey: key, defaults: defaults) == 0, "下限0に補正")
            try expect(AudioVolumeSettings.clamped(.nan) == 0.5, "数値でない値は初期値に戻す")
        }
        try expect(abs(AudioVolumeSettings.defaultVolume * AudioVolumeSettings.encounterMusicRatio - 0.3) < 0.0001, "戦闘BGMの初期音量は従来の0.3")
    }

    private static func withIsolatedDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suiteName = "Wagyaran.CoreLogicTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw TestError.failed("テスト用UserDefaultsを作成できません")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(defaults)
    }

    private static func reachablePositions(from start: GridPos, in map: MapData) -> Set<GridPos> {
        let offsets = [(x: 0, y: -1), (x: 1, y: 0), (x: 0, y: 1), (x: -1, y: 0)]
        var visited: Set<GridPos> = [start]
        var queue = [start]
        var index = 0

        while index < queue.count {
            let current = queue[index]
            index += 1
            for offset in offsets {
                let next = GridPos(x: current.x + offset.x, y: current.y + offset.y)
                guard !map.cell(at: next).isWall, visited.insert(next).inserted else { continue }
                queue.append(next)
            }
        }
        return visited
    }

    private static func mapSignature(_ map: MapData) -> String {
        let cells = map.cells.map { row in row.map(cellCode).joined() }.joined(separator: "/")
        let enemies = map.enemyKinds.map { "\($0.key.x),\($0.key.y):\($0.value)" }.sorted().joined(separator: ";")
        let traps = map.trapKinds.map { "\($0.key.x),\($0.key.y):\($0.value)" }.sorted().joined(separator: ";")
        return "\(cells)|S:\(map.startPosition.x),\(map.startPosition.y)|D:\(map.initialDirection.rawValue)|E:\(enemies)|T:\(traps)"
    }

    private static func cellCode(_ cell: MapCell) -> String {
        switch cell {
        case .wall: "#"
        case .floor: "."
        case .start: "S"
        case .trap: "T"
        case .doubleFlickTrap: "F"
        case .hpDrainTrap: "H"
        case .warpToStartTrap: "U"
        case .randomWarpTrap: "R"
        case .keyFrontWarpTrap: "P"
        case .gameOverTrap: "D"
        case .unexplodedTrap: "N"
        case .sword: "W"
        case .key: "K"
        case .enemy: "E"
        case .goal: "G"
        }
    }

    private static func stableID(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
    }

    private static func unwrap<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else { throw TestError.failed(message) }
        return value
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        assertionCount += 1
        guard condition() else { throw TestError.failed(message) }
    }
}

private enum TestError: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message): "テスト失敗: \(message)"
        }
    }
}
