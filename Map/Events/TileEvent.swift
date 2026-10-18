import Foundation

/// マスに入るときの特殊処理の入口(A担当)。
/// B・C は、この入口に従って Trap.swift / Key.swift を実装する。
protocol TileEvent {
    /// このマスに入れない場合、その理由(画面に出すメッセージ)を返す。入れるなら nil
    func blockReason(state: GameState) -> String?

    /// このマスに入った直後の処理。ゲームの状態を変更してよい
    func onEnter(state: inout GameState, from previousPosition: GridPos)
}

extension TileEvent {
    func blockReason(state: GameState) -> String? { nil }
    func onEnter(state: inout GameState, from previousPosition: GridPos) {}
}

/// マスの種類と処理の対応表
enum TileEvents {
    static func event(for cell: MapCell, map: MapData, position: GridPos) -> (any TileEvent)? {
        switch cell {
        case .trap:
            return TrapEvent(kind: map.trapKinds[position] ?? .turnRight, map: map)
        case .doubleFlickTrap:
            return TrapEvent(kind: .doubleFlick, map: map)
        case .hpDrainTrap:
            return TrapEvent(kind: .hpDrain, map: map)
        case .warpToStartTrap:
            return TrapEvent(kind: .warpToStart, map: map)
        case .randomWarpTrap:
            return TrapEvent(kind: .randomWarp, map: map)
        case .keyFrontWarpTrap:
            return TrapEvent(kind: .warpBeforeKey, map: map)
        case .gameOverTrap:
            return TrapEvent(kind: .forceGameOver, map: map)
        case .unexplodedTrap:
            return TrapEvent(kind: .unexploded, map: map)
        case .sword: return SwordEvent()
        case .key:  return KeyEvent()
        case .enemy: return nil // 敵種はseedと座標からGameManagerが決める
        case .goal: return GoalEvent()
        case .wall, .floor, .start: return nil
        }
    }
}
