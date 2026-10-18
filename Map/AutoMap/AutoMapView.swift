import SwiftUI

// MARK: - オートマップ(探索済みのマスだけを表示)
struct AutoMapView: View {
    let map: MapData
    let explored: Set<GridPos>
    let player: Player
    let defeatedEnemies: Set<GridPos>

    var body: some View {
        Canvas { ctx, size in
            let cols = map.cols
            let rows = map.rows
            let cell = min(size.width / CGFloat(cols), size.height / CGFloat(rows))
            let ox = (size.width - cell * CGFloat(cols)) / 2
            let oy = (size.height - cell * CGFloat(rows)) / 2

            func origin(_ x: Int, _ y: Int) -> CGPoint {
                CGPoint(x: ox + cell * CGFloat(x), y: oy + cell * CGFloat(y))
            }
            let sides: [(dx: Int, dy: Int)] = [(0, -1), (1, 0), (0, 1), (-1, 0)]

            for pos in explored {
                let o = origin(pos.x, pos.y)
                let r = CGRect(x: o.x, y: o.y, width: cell, height: cell)

                // 到達したマスだけ緑に色づけし、特殊地点は控えめな色で区別する
                let floorColor: Color
                switch map.cell(at: pos) {
                case .sword:
                    floorColor = Color(red: 0.08, green: 0.24, blue: 0.38)
                case .trap, .doubleFlickTrap, .hpDrainTrap, .warpToStartTrap,
                     .randomWarpTrap, .keyFrontWarpTrap, .gameOverTrap, .unexplodedTrap:
                    floorColor = Color(red: 0.42, green: 0.15, blue: 0.10)
                case .key:
                    floorColor = Color(red: 0.48, green: 0.34, blue: 0.08)
                case .enemy:
                    floorColor = defeatedEnemies.contains(pos)
                        ? Color(red: 0.055, green: 0.47, blue: 0.12)
                        : Color(red: 0.40, green: 0.10, blue: 0.16)
                case .goal:
                    floorColor = Color(red: 0.48, green: 0.19, blue: 0.12)
                default:
                    floorColor = Color(red: 0.055, green: 0.47, blue: 0.12)
                }
                ctx.fill(Path(r), with: .color(floorColor))

                if map.cell(at: pos) == .key {
                    let iconRect = r.insetBy(dx: cell * 0.14, dy: cell * 0.14)
                    drawPixelIcon(chestPixels, in: iconRect, context: &ctx, palette: chestPalette)
                } else if map.cell(at: pos) == .sword {
                    let iconRect = r.insetBy(dx: cell * 0.20, dy: cell * 0.10)
                    drawPixelIcon(swordPixels, in: iconRect, context: &ctx, palette: swordPalette)
                } else if map.cell(at: pos).isTrap {
                    let iconRect = r.insetBy(dx: cell * 0.14, dy: cell * 0.14)
                    drawPixelIcon(trapPixels, in: iconRect, context: &ctx, palette: trapPalette)
                }

                // 確認済みの壁(そのマスの四辺のうち、隣が壁の辺)
                for k in 0..<4 {
                    let n = sides[k]
                    guard map.isWall(x: pos.x + n.dx, y: pos.y + n.dy) else { continue }
                    var p = Path()
                    switch k {
                    case 0:
                        p.move(to: CGPoint(x: r.minX, y: r.minY))
                        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
                    case 1:
                        p.move(to: CGPoint(x: r.maxX, y: r.minY))
                        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
                    case 2:
                        p.move(to: CGPoint(x: r.minX, y: r.maxY))
                        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
                    default:
                        p.move(to: CGPoint(x: r.minX, y: r.minY))
                        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
                    }
                    ctx.stroke(
                        p,
                        with: .color(Color(red: 0.72, green: 0.67, blue: 0.54)),
                        lineWidth: max(1.2, min(2.5, cell * 0.07))
                    )
                }

                // 到達済みの特殊マスだけ記号を表示(未到達のT/K/Gは出さない)
                if let symbol = map.cell(at: pos).mapSymbol,
                   pos != player.position,
                   map.cell(at: pos) != .key,
                   !map.cell(at: pos).isTrap,
                   map.cell(at: pos) != .enemy || !defeatedEnemies.contains(pos) {
                    let symbolColor: Color
                    switch map.cell(at: pos) {
                    case .trap, .doubleFlickTrap, .hpDrainTrap, .warpToStartTrap,
                         .randomWarpTrap, .keyFrontWarpTrap, .gameOverTrap, .unexplodedTrap:
                        symbolColor = Color(red: 1.0, green: 0.66, blue: 0.46)
                    case .key:
                        symbolColor = Color(red: 1.0, green: 0.86, blue: 0.42)
                    case .enemy:
                        symbolColor = Color(red: 1.0, green: 0.48, blue: 0.48)
                    case .goal:
                        symbolColor = Color(red: 1.0, green: 0.88, blue: 0.69)
                    default:
                        symbolColor = .white
                    }
                    ctx.draw(
                        Text(symbol)
                            .font(DungeonTypography.maruMonica(size: cell * 0.6))
                            .foregroundColor(symbolColor),
                        at: CGPoint(x: r.midX, y: r.midY)
                    )
                }
            }

            // プレイヤーの現在位置を青いミニドラゴンで表示する。
            let po = origin(player.position.x, player.position.y)
            let dragonRect = CGRect(
                x: po.x + cell * 0.10,
                y: po.y + cell * 0.10,
                width: cell * 0.80,
                height: cell * 0.80
            )
            drawPixelIcon(dragonPixels, in: dragonRect, context: &ctx, palette: dragonPalette)
        }
        .background(Color(red: 0.025, green: 0.024, blue: 0.022))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(red: 0.48, green: 0.44, blue: 0.36).opacity(0.8), lineWidth: 1.5)
        }
    }

    // MARK: - ドット絵アイコン

    private var chestPixels: [String] {
        ["..OOOOOO..", ".OCCCCCCO.", "OCCCCCCCCO", "OBBBBBBBBO", "OGGGGGGGGO",
         "OBBBOBBBBO", "OBBBOBBBBO", "OGGGGGGGGO", ".OBBBBBBO.", "..OOOOOO.."]
    }

    private var trapPixels: [String] {
        ["....II....", "...IIII...", "..I....I..", ".I......I.", "IIIIIIIIII",
         ".ODDDDDDO.", ".ODRDRDDO.", "..ODDDDO..", "...OOOO...", ".........."]
    }

    private var swordPixels: [String] {
        ["....BB....", "...BB.....", "..BB......", ".BB.......", "BB........",
         ".GGGG.....", "...GG.....", "...HH.....", "..HHHH....", "..HHHH...."]
    }

    private var dragonPixels: [String] {
        ["....OO....", "...OBBO...", ".OOBBBBOO.", "OOBBBBBBBO", "OBBBYBBBBB",
         ".OBBBBBBO.", "..OBBBBO..", ".OBB..BBO.", "OBB....BBO", "OO......OO"]
    }

    private var chestPalette: [Character: Color] {
        ["O": Color(red: 0.16, green: 0.075, blue: 0.035),
         "C": Color(red: 0.72, green: 0.39, blue: 0.13),
         "B": Color(red: 0.48, green: 0.22, blue: 0.075),
         "G": Color(red: 1.0, green: 0.78, blue: 0.24)]
    }

    private var trapPalette: [Character: Color] {
        ["I": Color(red: 0.83, green: 0.82, blue: 0.72),
         "O": Color(red: 0.12, green: 0.08, blue: 0.07),
         "D": Color(red: 0.45, green: 0.19, blue: 0.12),
         "R": Color(red: 0.96, green: 0.28, blue: 0.16)]
    }

    private var swordPalette: [Character: Color] {
        ["B": Color(red: 0.72, green: 0.88, blue: 1.0),
         "G": Color(red: 1.0, green: 0.79, blue: 0.25),
         "H": Color(red: 0.43, green: 0.20, blue: 0.08)]
    }

    private var dragonPalette: [Character: Color] {
        ["O": Color(red: 0.02, green: 0.08, blue: 0.24),
         "B": Color(red: 0.08, green: 0.46, blue: 0.92),
         "Y": Color(red: 1.0, green: 0.86, blue: 0.32)]
    }

    private func drawPixelIcon(
        _ pixels: [String],
        in rect: CGRect,
        context: inout GraphicsContext,
        palette: [Character: Color]
    ) {
        guard let columns = pixels.first?.count, columns > 0 else { return }
        let pixelWidth = rect.width / CGFloat(columns)
        let pixelHeight = rect.height / CGFloat(pixels.count)

        for (row, line) in pixels.enumerated() {
            for (column, pixel) in line.enumerated() {
                guard let color = palette[pixel] else { continue }
                let pixelRect = CGRect(
                    x: rect.minX + CGFloat(column) * pixelWidth,
                    y: rect.minY + CGFloat(row) * pixelHeight,
                    width: pixelWidth,
                    height: pixelHeight
                )
                context.fill(Path(pixelRect), with: .color(color))
            }
        }
    }
}
