import SwiftUI

// MARK: - 3D描画ビュー(透視投影で石積みの壁・床・天井を描く)
struct DungeonView: View {
    /// 3D描画に必要なマップとプレイヤー状態を、値のまま直接受け取る。
    /// (関数ではなく値で受け取ることで、位置や向きが変わるたびに SwiftUI が再描画する)
    let map: MapData
    let player: Player
    let theme: DungeonTheme?
    let hasKey: Bool
    let isGoalReached: Bool
    let defeatedEnemyKinds: [GridPos: EnemyKind]
    /// 大きい敗北画像として別描画するため、床面への小さい描画を省略する位置。
    let largeDefeatGraphicPosition: GridPos?
    let activatedTrapPositions: Set<GridPos>

    /// 描画する最大の奥行き(マス数)。仕様書§12.5
    let maxDepth = 5

    /// 宝箱画像ごとの、透明な余白を除いた箱の範囲(画像ピクセル座標)。
    /// 画像を差し替えたら、この値も更新する。
    private static let chestVisibleBounds: [String: CGRect] = [
        "ChestClosedFront": CGRect(x: 112, y: 73, width: 576, height: 454),
        "ChestClosedBack": CGRect(x: 14, y: 13, width: 447, height: 316),
        "ChestClosedLeft": CGRect(x: 13, y: 13, width: 266, height: 328),
        "ChestClosedRight": CGRect(x: 13, y: 14, width: 276, height: 328),
        "ChestOpenFront": CGRect(x: 121, y: 59, width: 558, height: 482),
        "ChestOpenBack": CGRect(x: 13, y: 14, width: 444, height: 360),
        "ChestOpenLeft": CGRect(x: 13, y: 14, width: 282, height: 374),
        "ChestOpenRight": CGRect(x: 13, y: 14, width: 290, height: 375)
    ]

    /// 視点相対(前へd、右へi)のマスが壁か。
    /// プレイヤーの向きに合わせて、マップ上の絶対座標へ変換して調べる
    private func isWallRelative(_ d: Int, _ i: Int) -> Bool {
        map.cell(at: positionRelative(d, i)).isWall
    }

    /// 視点相対(前へd、右へi)のマスをマップ座標に変換する。
    private func positionRelative(_ d: Int, _ i: Int) -> GridPos {
        let forward = player.direction          // 前方向
        let right = forward.turnedRight         // 右方向

        let x = player.position.x
            + forward.dx * d
            + right.dx * i
        let y = player.position.y
            + forward.dy * d
            + right.dy * i

        return GridPos(x: x, y: y)
    }

    /// 深さ d のマスについて、左右どこまで調べるかと、描く順番を返す(外側 → 中央の順)。
    /// 奥へ行くほど、画面に映る横の範囲が広がる(横位置 i のマスが画面に入るのは |i| < d + 2 のとき)。
    /// そのため、奥のマスほど外側まで調べる。外側から先に描くのは、
    /// 奥の面を、手前の面で隠すため。
    private func lateralOrder(depth d: Int) -> [Int] {
        let limit = d + 1
        var order: [Int] = []
        for n in stride(from: limit, through: 1, by: -1) {
            order.append(-n)
            order.append(n)
        }
        order.append(0)
        return order
    }

    var body: some View {
        Canvas { ctx, size in
            let f = Double(size.width) / 2          // 画面の半幅。近い横壁が画面端に届く値
            let cx = Double(size.width) / 2         // 画面中央のx
            let cy = Double(size.height) / 2        // 画面中央のy

            // 3D点(X:横, Y:高さ, Z:奥行き) → 画面座標
            func project(_ x: Double, _ y: Double, _ z: Double) -> CGPoint {
                CGPoint(x: cx + f * x / z, y: cy - f * y / z)
            }

            let doorImage = ctx.resolve(Image(isGoalReached ? "DungeonDoorOpen" : "door"))
            let chestImageName: String = {
                switch (hasKey, player.direction) {
                case (false, .north): "ChestClosedFront"
                case (false, .south): "ChestClosedBack"
                case (false, .west): "ChestClosedLeft"
                case (false, .east): "ChestClosedRight"
                case (true, .north): "ChestOpenFront"
                case (true, .south): "ChestOpenBack"
                case (true, .west): "ChestOpenLeft"
                case (true, .east): "ChestOpenRight"
                }
            }()
            let chestImage = ctx.resolve(Image(chestImageName))
            // ミミックは遭遇前、閉じた宝箱に化けている。プレイヤーの向きや鍵の取得状態に関係なく、常に正面向きの閉じた箱を使う。
            let closedChestImageName = "ChestClosedFront"
            let closedChestImage = ctx.resolve(Image(closedChestImageName))

            func polygon(_ points: [CGPoint]) -> Path {
                var path = Path()
                guard let first = points.first else { return path }
                path.move(to: first)
                for point in points.dropFirst() { path.addLine(to: point) }
                path.closeSubpath()
                return path
            }

            func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
                hypot(Double(a.x - b.x), Double(a.y - b.y))
            }

            func interpolate(_ a: CGPoint, _ b: CGPoint, _ amount: Double) -> CGPoint {
                CGPoint(
                    x: a.x + CGFloat(amount) * (b.x - a.x),
                    y: a.y + CGFloat(amount) * (b.y - a.y)
                )
            }

            /// 四隅で定義した面の中の(u, v)位置を返す。石の目地も投影面に沿わせる。
            func surfacePoint(_ u: Double, _ v: Double, corners: [CGPoint]) -> CGPoint {
                let upper = interpolate(corners[0], corners[1], u)
                let lower = interpolate(corners[3], corners[2], u)
                return interpolate(upper, lower, v)
            }

            /// 撃破した敵を、そのマスの床に倒れた姿で残す。
            func drawDefeatedEnemy(_ kind: EnemyKind, on corners: [CGPoint]) {
                let defeatedImage = ctx.resolve(Image(kind.defeatedImageName))
                let imageSize = defeatedImage.size
                guard imageSize.width > 0, imageSize.height > 0 else { return }

                let farWidth = distance(corners[0], corners[1])
                let nearWidth = distance(corners[3], corners[2])
                let tileDepth = distance(
                    interpolate(corners[0], corners[1], 0.5),
                    interpolate(corners[3], corners[2], 0.5)
                )
                let aspectRatio = Double(imageSize.width / imageSize.height)
                let imageWidth = min(min(farWidth, nearWidth) * 0.72, tileDepth * aspectRatio * 0.72)
                let imageHeight = imageWidth / aspectRatio
                let center = surfacePoint(0.5, 0.52, corners: corners)
                let rect = CGRect(x: center.x - CGFloat(imageWidth / 2),
                                  y: center.y - CGFloat(imageHeight / 2),
                                  width: CGFloat(imageWidth), height: CGFloat(imageHeight))
                ctx.draw(defeatedImage, in: rect)
            }

            /// 発動済みトラップの既存ドット絵を、床面の透視投影に沿って残す。
            func drawTrapMark(_ kind: TrapKind, on corners: [CGPoint]) {
                let pixels = TrapPixelArt.pixels(for: kind)
                let palette = TrapPixelArt.palette(for: kind)
                guard let columns = pixels.first?.count, columns > 0 else { return }

                let inset = 0.16
                let usable = 1.0 - inset * 2
                for (row, line) in pixels.enumerated() {
                    for (column, marker) in line.enumerated() {
                        guard let color = palette[marker] else { continue }
                        let u0 = inset + usable * Double(column) / Double(columns)
                        let u1 = inset + usable * Double(column + 1) / Double(columns)
                        let v0 = inset + usable * Double(row) / Double(pixels.count)
                        let v1 = inset + usable * Double(row + 1) / Double(pixels.count)
                        let pixel = polygon([
                            surfacePoint(u0, v0, corners: corners),
                            surfacePoint(u1, v0, corners: corners),
                            surfacePoint(u1, v1, corners: corners),
                            surfacePoint(u0, v1, corners: corners)
                        ])
                        ctx.fill(pixel, with: .color(color))
                    }
                }
            }

            /// 透視投影した面を、目地と明暗差のある石ブロックで塗る。
            /// kind は壁=0、床=1、天井=2。
            func stoneSurface(_ corners: [CGPoint], depth: Int, seed: Int, kind: Int) {
                let outline = polygon(corners)
                let mortar = Color(red: 0.055, green: 0.052, blue: 0.047)
                ctx.fill(outline, with: .color(mortar))

                let averageHeight = (distance(corners[0], corners[3]) + distance(corners[1], corners[2])) / 2
                let averageWidth = (distance(corners[0], corners[1]) + distance(corners[3], corners[2])) / 2
                let activeTheme = theme ?? .temple
                let isCave: Bool
                let isForestMansion: Bool
                switch activeTheme {
                case .cave:
                    isCave = true
                    isForestMansion = false
                case .forestMansion:
                    isCave = false
                    isForestMansion = true
                case .temple, .hell:
                    isCave = false
                    isForestMansion = false
                }
                let rowSpacing = isForestMansion ? 16.0 : 25.0
                let rowCount = max(1, min(12, Int(averageHeight / rowSpacing)))
                let rowHeight = max(1, averageHeight / Double(rowCount))
                let brickRatio = isForestMansion ? 4.8 : (kind == 0 ? 1.8 : 2.25)
                let columnCount = max(1, min(14, Int(averageWidth / max(18, rowHeight * brickRatio))))
                let step = 1.0 / Double(columnCount)
                let depthShade = max(0.48, 1.0 - Double(depth) * 0.082)
                let strokeWidth = max(0.7, min(1.5, rowHeight * 0.055))

                let base = activeTheme.stoneColor(surfaceKind: kind)
                let accent = activeTheme.accentColor
                func shaded(_ component: Double, _ tint: Double) -> Double {
                    max(0, min(1, (component + tint) * depthShade))
                }

                for row in 0..<rowCount {
                    let v0 = Double(row) / Double(rowCount)
                    let v1 = Double(row + 1) / Double(rowCount)
                    // 洋館の壁と床はまっすぐな板張り、ほかは石組みにする。
                    let stagger = isForestMansion || row.isMultiple(of: 2) ? 0 : step * 0.5
                    var boundaries = [0.0]
                    var next = step + stagger
                    while next < 1 {
                        boundaries.append(next)
                        next += step
                    }
                    boundaries.append(1)

                    for column in 0..<(boundaries.count - 1) {
                        let u0 = boundaries[column]
                        let u1 = boundaries[column + 1]
                        let points = [
                            surfacePoint(u0, v0, corners: corners),
                            surfacePoint(u1, v0, corners: corners),
                            surfacePoint(u1, v1, corners: corners),
                            surfacePoint(u0, v1, corners: corners)
                        ]
                        let brick = polygon(points)
                        let tone = (row * 7 + column * 11 + seed * 13 + depth * 5) % 7
                        let variation = Double(tone - 3) * 0.014
                        let planeShade = kind == 0 ? 1.0 : (kind == 1 ? 0.76 : 0.58)
                        let shade = depthShade * planeShade
                        let color = Color(
                            red: max(0, min(1, (base.red + variation) * shade)),
                            green: max(0, min(1, (base.green + variation) * shade)),
                            blue: max(0, min(1, (base.blue + variation) * shade))
                        )
                        if isCave {
                            // 水晶洞窟はレンガ目地を使わず、透ける結晶面の集合として描く。
                            let center = surfacePoint((u0 + u1) / 2, (v0 + v1) / 2, corners: corners)
                            let facets = [
                                [points[0], points[1], center],
                                [points[1], points[2], center],
                                [points[2], points[3], center],
                                [points[3], points[0], center]
                            ]
                            for (facetIndex, facet) in facets.enumerated() {
                                let facetPath = polygon(facet)
                                let tint = Double((tone + facetIndex * 3) % 5 - 2) * 0.035
                                let facetColor = Color(
                                    red: max(0, min(1, shaded(base.red, variation + tint))),
                                    green: max(0, min(1, shaded(base.green, variation + tint))),
                                    blue: max(0, min(1, shaded(base.blue + 0.06, variation + tint)))
                                )
                                ctx.fill(facetPath, with: .color(facetColor))
                                ctx.stroke(facetPath, with: .color(Color(red: accent.red, green: accent.green, blue: accent.blue).opacity(depthShade * 0.28)), lineWidth: 0.8)
                            }
                            if kind == 0 && abs(row * 7 + column * 11 + seed * 3 + depth).isMultiple(of: 3) {
                                var vein = Path()
                                vein.move(to: surfacePoint(u0 + (u1 - u0) * 0.25, v0 + (v1 - v0) * 0.9, corners: corners))
                                vein.addLine(to: center)
                                vein.addLine(to: surfacePoint(u0 + (u1 - u0) * 0.75, v0 + (v1 - v0) * 0.1, corners: corners))
                                ctx.stroke(vein, with: .color(Color(red: accent.red, green: accent.green, blue: accent.blue).opacity(depthShade * 0.9)), lineWidth: max(1.1, min(2.2, rowHeight * 0.09)))
                            }
                        } else {
                            ctx.fill(brick, with: .color(color))
                            ctx.stroke(brick, with: .color(mortar), lineWidth: strokeWidth)
                        }

                        var highlight = Path()
                        highlight.move(to: points[0])
                        highlight.addLine(to: points[1])
                        let highlightOpacity = max(0.025, 0.09 - Double(depth) * 0.009)
                        ctx.stroke(
                            highlight,
                            with: .color(Color.white.opacity(highlightOpacity)),
                            lineWidth: 0.7
                        )

                        // 壁の一部にテーマ固有の意匠を刻み、単なる色替えに見えないようにする。
                        let detailSeed = abs(row * 7 + column * 11 + seed * 3 + depth)
                        let shouldDrawWallDetail = isForestMansion
                            ? detailSeed.isMultiple(of: 2)
                            : detailSeed.isMultiple(of: 5)
                        if kind == 0 && shouldDrawWallDetail {
                            var detail = Path()
                            switch activeTheme {
                            case .temple:
                                detail.move(to: surfacePoint(u0 + (u1 - u0) * 0.18, v0 + (v1 - v0) * 0.28, corners: corners))
                                detail.addLine(to: surfacePoint(u1 - (u1 - u0) * 0.18, v0 + (v1 - v0) * 0.28, corners: corners))
                            case .cave:
                                detail.move(to: surfacePoint(u0 + (u1 - u0) * 0.28, v0 + (v1 - v0) * 0.82, corners: corners))
                                detail.addLine(to: surfacePoint(u0 + (u1 - u0) * 0.52, v0 + (v1 - v0) * 0.34, corners: corners))
                                detail.addLine(to: surfacePoint(u0 + (u1 - u0) * 0.78, v0 + (v1 - v0) * 0.18, corners: corners))
                            case .hell:
                                detail.move(to: surfacePoint(u0 + (u1 - u0) * 0.45, v0 + (v1 - v0) * 0.05, corners: corners))
                                detail.addLine(to: surfacePoint(u0 + (u1 - u0) * 0.38, v0 + (v1 - v0) * 0.45, corners: corners))
                                detail.addLine(to: surfacePoint(u0 + (u1 - u0) * 0.62, v0 + (v1 - v0) * 0.7, corners: corners))
                                detail.addLine(to: surfacePoint(u0 + (u1 - u0) * 0.54, v0 + (v1 - v0) * 0.96, corners: corners))
                            case .forestMansion:
                                detail.move(to: surfacePoint(u0 + (u1 - u0) * 0.18, v0 + (v1 - v0) * 0.92, corners: corners))
                                detail.addCurve(
                                    to: surfacePoint(u0 + (u1 - u0) * 0.78, v0 + (v1 - v0) * 0.10, corners: corners),
                                    control1: surfacePoint(u0 + (u1 - u0) * 0.42, v0 + (v1 - v0) * 0.72, corners: corners),
                                    control2: surfacePoint(u0 + (u1 - u0) * 0.56, v0 + (v1 - v0) * 0.22, corners: corners)
                                )
                            }
                            ctx.stroke(
                                detail,
                                with: .color(Color(red: accent.red, green: accent.green, blue: accent.blue).opacity(depthShade * 0.65)),
                                lineWidth: max(0.8, min(1.8, rowHeight * 0.08))
                            )
                        }
                    }
                }
            }

            // 正面が壁に当たる深さまでを描画対象にする
            var depth = 0
            while depth < maxDepth && !isWallRelative(depth + 1, 0) {
                depth += 1
            }

            // 奥から手前へ描く。各マスの床・天井を敷いてから壁を重ね、奥の面を隠す。
            for d in stride(from: depth, through: 0, by: -1) {
                for i in lateralOrder(depth: d) {
                    if isWallRelative(d, i) { continue }

                    let z0 = Double(d) + 0.5    // このマスの手前側の奥行き
                    let z1 = Double(d) + 1.5    // このマスの奥側の奥行き
                    let xl = Double(i) - 0.5    // このマスの左端の横位置
                    let xr = Double(i) + 0.5    // このマスの右端の横位置
                    let showsGoalDoor = i == 0
                        && (1...2).contains(d)
                        && map.cell(at: positionRelative(d, i)) == .goal
                    let showsKeyChest = i == 0
                        && (1...2).contains(d)
                        && map.cell(at: positionRelative(d, i)) == .key
                    let showsMimicChest = i == 0
                        && (1...2).contains(d)
                        && map.cell(at: positionRelative(d, i)) == .enemy
                        && map.enemyKinds[positionRelative(d, i)] == .mimic
                        && defeatedEnemyKinds[positionRelative(d, i)] == nil

                    stoneSurface([
                        project(xl, 0.5, z0), project(xr, 0.5, z0),
                        project(xr, 0.5, z1), project(xl, 0.5, z1)
                    ], depth: d, seed: i + d * 3, kind: 2)
                    let floorCorners = [
                        project(xl, -0.5, z1), project(xr, -0.5, z1),
                        project(xr, -0.5, z0), project(xl, -0.5, z0)
                    ]
                    stoneSurface(floorCorners, depth: d, seed: i + d * 5, kind: 1)

                    let tilePosition = positionRelative(d, i)
                    if activatedTrapPositions.contains(tilePosition),
                       let trapKind = TrapPixelArt.kind(at: tilePosition, in: map) {
                        drawTrapMark(trapKind, on: floorCorners)
                    }

                    if tilePosition != largeDefeatGraphicPosition,
                       let defeatedKind = defeatedEnemyKinds[tilePosition] {
                        drawDefeatedEnemy(defeatedKind, on: floorCorners)
                    }

                    // ドア画像の透過部分から奥が見えないよう、ゴール面に石壁を敷く。
                    if showsGoalDoor {
                        stoneSurface([
                            project(xl, 0.5, z0), project(xr, 0.5, z0),
                            project(xr, -0.5, z0), project(xl, -0.5, z0)
                        ], depth: d, seed: i + d * 17, kind: 0)
                    }

                    // 正面の壁
                    if isWallRelative(d + 1, i) {
                        stoneSurface([
                            project(xl, 0.5, z1), project(xr, 0.5, z1),
                            project(xr, -0.5, z1), project(xl, -0.5, z1)
                        ], depth: d, seed: i + d * 7, kind: 0)
                    }

                    // 左の壁
                    if isWallRelative(d, i - 1) {
                        stoneSurface([
                            project(xl, 0.5, z0), project(xl, 0.5, z1),
                            project(xl, -0.5, z1), project(xl, -0.5, z0)
                        ], depth: d, seed: i + d * 11 + 1, kind: 0)
                    }

                    // 右の壁
                    if isWallRelative(d, i + 1) {
                        stoneSurface([
                            project(xr, 0.5, z0), project(xr, 0.5, z1),
                            project(xr, -0.5, z1), project(xr, -0.5, z0)
                        ], depth: d, seed: i + d * 13 + 2, kind: 0)
                    }

                    // 周囲の石壁を描いた後にドアを置き、レンガ面との重なりを防ぐ。
                    if showsGoalDoor {
                        let topLeft = project(xl, 0.5, z0)
                        let bottomRight = project(xr, -0.5, z0)
                        ctx.draw(
                            doorImage,
                            in: CGRect(
                                x: topLeft.x,
                                y: topLeft.y,
                                width: bottomRight.x - topLeft.x,
                                height: bottomRight.y - topLeft.y
                            )
                        )
                    }

                    // Kマスが前方2マス以内に見える場合、向きと開閉状態に合う宝箱を置く。
                    if showsKeyChest || showsMimicChest {
                        let drawnChestImage = showsMimicChest ? closedChestImage : chestImage
                        let drawnChestImageName = showsMimicChest ? closedChestImageName : chestImageName
                        let chestDepth = Double(d) + 1.0
                        let topLeft = project(-0.38, 0.05, chestDepth)
                        let bottomRight = project(0.38, -0.5, chestDepth)
                        let chestBounds = CGRect(
                            x: topLeft.x,
                            y: topLeft.y,
                            width: bottomRight.x - topLeft.x,
                            height: bottomRight.y - topLeft.y
                        )
                        // 宝箱画像は向きごとに透明な余白の量が違う(正面だけ800x600の中に小さく描かれている)。
                        // 余白を除いた「箱の見えている範囲」を基準に、高さと足元の位置を向きに関わらずそろえる。
                        let imageSize = drawnChestImage.size
                        let visible = Self.chestVisibleBounds[drawnChestImageName]
                            ?? CGRect(origin: .zero, size: imageSize)
                        // 箱の見えている範囲(画面上の矩形)。傾きの軸にも使う。
                        var visibleRect = chestBounds
                        // 画像全体を描く矩形。
                        var chestRect = chestBounds
                        if imageSize.width > 0, imageSize.height > 0, visible.width > 0, visible.height > 0 {
                            let fitScale = min(
                                chestBounds.width / visible.width,
                                chestBounds.height / visible.height
                            )
                            let visibleSize = CGSize(
                                width: visible.width * fitScale,
                                height: visible.height * fitScale
                            )
                            visibleRect = CGRect(
                                x: chestBounds.midX - visibleSize.width / 2,
                                y: chestBounds.maxY - visibleSize.height,
                                width: visibleSize.width,
                                height: visibleSize.height
                            )
                            chestRect = CGRect(
                                x: visibleRect.minX - visible.minX * fitScale,
                                y: visibleRect.minY - visible.minY * fitScale,
                                width: imageSize.width * fitScale,
                                height: imageSize.height * fitScale
                            )
                        }
                        if showsMimicChest {
                            // ミミックは鍵の宝箱と見分けられるよう、箱の足元を軸に少し傾け、紫がかった色味にする。
                            ctx.drawLayer { layer in
                                layer.translateBy(x: visibleRect.midX, y: visibleRect.maxY)
                                layer.rotate(by: .degrees(-5))
                                layer.translateBy(x: -visibleRect.midX, y: -visibleRect.maxY)
                                layer.addFilter(.colorMultiply(Color(red: 0.88, green: 0.70, blue: 1.0)))
                                layer.draw(drawnChestImage, in: chestRect)
                            }
                        } else {
                            ctx.draw(
                                drawnChestImage,
                                in: chestRect
                            )
                        }
                    }
                }
            }
        }

        .aspectRatio(1, contentMode: .fit)          // 3D表示領域は正方形(仕様書§12.6)
        .background(Color(red: 0.025, green: 0.024, blue: 0.022))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(red: 0.48, green: 0.44, blue: 0.36).opacity(0.8), lineWidth: 1.5)
        }
    }
}
