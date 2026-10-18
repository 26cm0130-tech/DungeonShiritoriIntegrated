import Foundation

/// マップの1マス(仕様書§5.3 マス方式)
enum MapCell: Equatable {
    case wall
    case floor
    case start
    case trap
    case doubleFlickTrap
    case hpDrainTrap
    case warpToStartTrap
    case randomWarpTrap
    case keyFrontWarpTrap
    case gameOverTrap
    case unexplodedTrap
    case sword
    case key
    case enemy
    case goal

    /// マップ定義の1文字から作る。# = 壁、S/T/F/H/U/R/P/D/N/W/K/E/G = 特殊マス、それ以外 = 床
    init(_ character: Character) {
        switch character {
        case "#": self = .wall
        case "S": self = .start
        case "T": self = .trap
        case "F": self = .doubleFlickTrap
        case "H": self = .hpDrainTrap
        case "U": self = .warpToStartTrap
        case "R": self = .randomWarpTrap
        case "P": self = .keyFrontWarpTrap
        case "D": self = .gameOverTrap
        case "N": self = .unexplodedTrap
        case "W": self = .sword
        case "K": self = .key
        case "E": self = .enemy
        case "G": self = .goal
        default:  self = .floor
        }
    }

    var isWall: Bool { self == .wall }

    /// トラップマスかどうか
    var isTrap: Bool {
        switch self {
        case .trap,
             .doubleFlickTrap,
             .hpDrainTrap,
             .warpToStartTrap,
             .randomWarpTrap,
             .keyFrontWarpTrap,
             .gameOverTrap,
             .unexplodedTrap:
            return true
        default:
            return false
        }
    }

    /// オートマップに(到達後のみ)表示する記号
    var mapSymbol: String? {
        switch self {
        case .trap,
             .doubleFlickTrap,
             .hpDrainTrap,
             .warpToStartTrap,
             .randomWarpTrap,
             .keyFrontWarpTrap,
             .gameOverTrap,
             .unexplodedTrap:
            return "T"
        case .key, .sword: return nil
        case .enemy: return "E"
        case .goal: return "G"
        case .wall, .floor, .start: return nil
        }
    }
}
