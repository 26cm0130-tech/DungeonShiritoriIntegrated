import Foundation

/// seedから必ず連結した迷宮を作り、敵・鍵・ゴールを配置する。
enum RandomMazeGenerator {
    private static let mapSize = 17
    private static let directions = [(dx: 0, dy: -1), (dx: 1, dy: 0), (dx: 0, dy: 1), (dx: -1, dy: 0)]

    static func generate(seed: UInt64) -> MapData {
        var random = SeededRandomNumberGenerator(seed: seed)
        var cells = Array(repeating: Array(repeating: Character("#"), count: mapSize), count: mapSize)
        let nodes = stride(from: 1, to: mapSize - 1, by: 2).flatMap { y in
            stride(from: 1, to: mapSize - 1, by: 2).map { x in GridPos(x: x, y: y) }
        }

        // 深さ優先で未訪問の部屋をつなぎ、すべての通路が連結した迷路を作る。
        let start = nodes[random.nextInt(upperBound: nodes.count)]
        var visited: Set<GridPos> = [start]
        var stack = [start]
        cells[start.y][start.x] = "."

        while let current = stack.last {
            let neighbors = directions.compactMap { direction -> GridPos? in
                let next = GridPos(
                    x: current.x + direction.dx * 2,
                    y: current.y + direction.dy * 2
                )
                guard next.x > 0, next.x < mapSize - 1,
                      next.y > 0, next.y < mapSize - 1,
                      !visited.contains(next) else { return nil }
                return next
            }

            guard !neighbors.isEmpty else {
                stack.removeLast()
                continue
            }

            let next = neighbors[random.nextInt(upperBound: neighbors.count)]
            let passage = GridPos(x: (current.x + next.x) / 2, y: (current.y + next.y) / 2)
            cells[passage.y][passage.x] = "."
            cells[next.y][next.x] = "."
            visited.insert(next)
            stack.append(next)
        }

        // 迷路に1本だけループを作り、ゴールへの最短経路以外にも退避できる通路を確保する。
        let loopCandidates = cells.indices.flatMap { y in
            cells[y].indices.compactMap { x -> GridPos? in
                guard cells[y][x] == "#" else { return nil }
                let joinsHorizontalFloors = x > 0 && x < mapSize - 1
                    && cells[y][x - 1] == "." && cells[y][x + 1] == "."
                let joinsVerticalFloors = y > 0 && y < mapSize - 1
                    && cells[y - 1][x] == "." && cells[y + 1][x] == "."
                return joinsHorizontalFloors || joinsVerticalFloors ? GridPos(x: x, y: y) : nil
            }
        }
        if !loopCandidates.isEmpty {
            let loopPassage = loopCandidates[random.nextInt(upperBound: loopCandidates.count)]
            cells[loopPassage.y][loopPassage.x] = "."
        }

        // 迷宮全体を歩けることを生成時にも確認し、破損したマップは採用しない。
        let walkableCount = cells.reduce(0) { count, row in count + row.filter { $0 == "." }.count }
        let distances = distances(from: start, in: cells)
        assert(distances.count == walkableCount, "ランダム迷宮の通路が連結していません")

        let farthestDistance = distances.values.max() ?? 0
        let farthestCells = distances.compactMap { $0.value == farthestDistance ? $0.key : nil }
        let goal = farthestCells[random.nextInt(upperBound: farthestCells.count)]
        let path = shortestPath(from: start, to: goal, in: cells)
        precondition(path.count >= 6, "ランダム迷宮の経路が短すぎて剣・敵・鍵を配置できません")
        let keyIndex = min(path.count - 3, max(3, path.count / 2))
        let swordIndex = max(1, keyIndex / 3)
        let sword = path[swordIndex]
        let key = path[keyIndex]
        let preKeyEnemyCandidates = Array((swordIndex + 1)..<keyIndex).map { path[$0] }
        let postKeyEnemyCandidates = Array((keyIndex + 1)..<(path.count - 1)).map { path[$0] }
        precondition(!preKeyEnemyCandidates.isEmpty && !postKeyEnemyCandidates.isEmpty, "剣・鍵の前後に敵を配置できません")
        // 最初の敵は剣取得後・鍵の手前、2体目は鍵を取った後に配置する。
        let firstEnemy = preKeyEnemyCandidates[random.nextInt(upperBound: preKeyEnemyCandidates.count)]
        let secondEnemy = postKeyEnemyCandidates[random.nextInt(upperBound: postKeyEnemyCandidates.count)]
        let enemies = [firstEnemy, secondEnemy]
        let enemyKinds: [GridPos: EnemyKind] = [
            firstEnemy: .gargoyle,
            secondEnemy: EnemyKind.encounter(seed: seed ^ 0xA5A5A5A5, position: secondEnemy)
        ]

        let routeToGoal = Set(path)
        let trapCandidates = cells.indices.flatMap { y in
            cells[y].indices.compactMap { x -> GridPos? in
                guard cells[y][x] == "." else { return nil }
                let position = GridPos(x: x, y: y)
                return routeToGoal.contains(position) ? nil : position
            }
        }
        precondition(trapCandidates.count >= 3, "ゴールへの経路外にトラップを3個置く通路がありません")

        // 同じマスへの重複配置を防ぎ、最短経路外から3か所を選ぶ。
        var availableTrapCandidates = trapCandidates
        var traps: [GridPos: TrapKind] = [:]
        for _ in 0..<3 {
            let candidateIndex = random.nextInt(upperBound: availableTrapCandidates.count)
            let position = availableTrapCandidates.remove(at: candidateIndex)
            // ランダム迷宮ではPR13に合わせてグループA(状態変化)から抽選する。
            let kind = selectTrap(in: .a) {
                random.nextInt(upperBound: 100) + 1
            } ?? .unexploded
            traps[position] = kind
        }

        // 特殊マスの記号は通路の連結性に影響しない。
        cells[start.y][start.x] = "S"
        cells[sword.y][sword.x] = "W"
        cells[key.y][key.x] = "K"
        for enemy in enemies {
            cells[enemy.y][enemy.x] = "E"
        }
        for (position, kind) in traps {
            cells[position.y][position.x] = mapSymbol(for: kind)
        }
        cells[goal.y][goal.x] = "G"

        let mapCells = cells.map { row in row.map { MapCell($0) } }
        return MapData(
            cells: mapCells,
            startPosition: start,
            initialDirection: Direction(rawValue: random.nextInt(upperBound: 4)) ?? .north,
            enemyKinds: enemyKinds
        )
    }

    /// トラップの種類をマップ定義用の記号に変換する。
    private static func mapSymbol(for kind: TrapKind) -> Character {
        switch kind {
        case .turnRight: return "T"
        case .doubleFlick: return "F"
        case .hpDrain: return "H"
        case .warpToStart: return "U"
        case .randomWarp: return "R"
        case .warpBeforeKey: return "P"
        case .forceGameOver: return "D"
        case .unexploded: return "N"
        }
    }

    private static func distances(from start: GridPos, in cells: [[Character]]) -> [GridPos: Int] {
        var result = [start: 0]
        var queue = [start]
        var queueIndex = 0

        while queueIndex < queue.count {
            let current = queue[queueIndex]
            queueIndex += 1
            for direction in directions {
                let next = GridPos(x: current.x + direction.dx, y: current.y + direction.dy)
                guard cells[next.y][next.x] == ".", result[next] == nil else { continue }
                result[next] = (result[current] ?? 0) + 1
                queue.append(next)
            }
        }
        return result
    }

    private static func shortestPath(from start: GridPos, to goal: GridPos, in cells: [[Character]]) -> [GridPos] {
        var previous: [GridPos: GridPos] = [:]
        var visited: Set<GridPos> = [start]
        var queue = [start]
        var queueIndex = 0

        while queueIndex < queue.count, !visited.contains(goal) {
            let current = queue[queueIndex]
            queueIndex += 1
            for direction in directions {
                let next = GridPos(x: current.x + direction.dx, y: current.y + direction.dy)
                guard cells[next.y][next.x] == ".", visited.insert(next).inserted else { continue }
                previous[next] = current
                queue.append(next)
            }
        }

        var path = [goal]
        while let parent = previous[path[path.count - 1]] {
            path.append(parent)
        }
        return path.reversed()
    }
}

/// OSや実行ごとに変わる乱数実装に依存せず、同じseedから同じ数列を返す。
private struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }

    mutating func nextInt(upperBound: Int) -> Int {
        precondition(upperBound > 0)
        return Int(next() % UInt64(upperBound))
    }
}
