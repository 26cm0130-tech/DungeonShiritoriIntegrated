import SwiftUI

/// 状況メッセージの横にPlayerを表示し、HPを常時確認できるようにする。
struct MonsterMessageView: View {
    let message: String
    let reactionID: Int
    let surpriseReactionID: Int
    let isTrapReactionActive: Bool
    let trapAnimationFrame: String
    let trapAnimationOffset: CGFloat
    let trapAnimationTilt: Double
    let wallCollisionID: Int
    let playerAttackAnimationID: Int
    let playerDamageAnimationID: Int
    let playerDamageAmount: Int
    let battle: EnemyBattle?
    let playerHP: Int
    let isTutorial: Bool
    /// iPadの中央列で状況欄の上に置く表示(ステージ名)
    var iPadHeader: AnyView? = nil
    /// iPadの中央列で状況欄の下に置く表示(フリック案内)。戦闘中は渡さず、状況欄が広がる。
    var iPadFooter: AnyView? = nil

    @State private var isBreathing = false
    @State private var actionFrame: String?
    @State private var reactionTask: Task<Void, Never>?
    @State private var collisionShakeOffset: CGFloat = 0
    @State private var collisionTilt: Double = 0
    @State private var isSurprised = false
    @State private var isCrying = false
    @State private var attackOffset: CGFloat = 0
    @State private var damageShakeOffset: CGFloat = 0
    @State private var damageTilt: Double = 0
    @State private var damageFlashOpacity = 0.0
    @State private var damageNumberAmount = 0
    @State private var damageNumberOffset: CGFloat = 0
    @State private var damageNumberOpacity = 0.0
    /// HP減少前の幅を残像として保持し、残像だけを滑らかに縮める。
    @State private var playerHPBeforeDecrease: Int?
    @State private var enemyHPBeforeDecrease: Int?
    @State private var playerHPResidualProgress: CGFloat = 0
    @State private var enemyHPResidualProgress: CGFloat = 0
    @State private var playerHPDecreaseTask: Task<Void, Never>?
    @State private var enemyHPDecreaseTask: Task<Void, Never>?

    private var imageName: String {
        if battle != nil {
            return "PlayerIdle"
        }
        if isTrapReactionActive { return trapAnimationFrame }
        if isSurprised || isCrying { return "PlayerBlink" }
        return actionFrame ?? (isBreathing ? "PlayerBreath" : "PlayerIdle")
    }

    private var currentMessage: String {
        battle?.message ?? message
    }

    private var isPad: Bool { IPadLayoutMetrics.isPad }
    /// iPhone基準(幅70pt)に対する拡大率。涙・ダメージ数の位置を合わせるのに使う。
    private var characterScale: CGFloat { characterSize.width / 70 }
    /// Playerドラゴンの表示サイズ。iPadでは動きが見やすいよう左の列いっぱいに大きくする。
    private var characterSize: CGSize { isPad ? CGSize(width: 160, height: 174) : CGSize(width: 70, height: 76) }

    private var messageLineLimit: Int {
        guard battle == nil else { return 2 }
        return isTutorial || currentMessage.contains("\n") ? 3 : 2
    }

    /// iPhoneは従来の1枚の枠、iPadは3列の構成にする。
    @ViewBuilder
    private var layout: some View {
        if isPad {
            iPadLayout
        } else {
            phoneLayout
        }
    }

    private var phoneLayout: some View {
        HStack(spacing: 8) {
            messageColumn
            characterStack
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .frame(height: 100)
        .dungeonPanel()
    }

    /// iPad: 左にキャラクター、中央にステージ名・状況とHP・フリック案内を縦に並べる(右のマップ列はPlayView側)。
    private var iPadLayout: some View {
        HStack(alignment: .top, spacing: 8) {
            characterStack
                .frame(width: IPadLayoutMetrics.characterColumnWidth, height: IPadLayoutMetrics.infoPanelHeight)
                .dungeonPanel()

            VStack(spacing: 8) {
                if let iPadHeader {
                    iPadHeader
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: IPadLayoutMetrics.stageTitleHeight)
                        .dungeonPanel(cornerRadius: 6)
                }

                messageColumn
                    .padding(10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .dungeonPanel()

                if let iPadFooter {
                    iPadFooter
                        .frame(maxWidth: .infinity)
                        .frame(height: IPadLayoutMetrics.flickPanelHeight)
                }
            }
            .frame(height: IPadLayoutMetrics.infoPanelHeight)
        }
    }


    /// 状況メッセージとHPバー。iPadの戦闘中は敵HP・メッセージ・味方HPを縦に分散する。
    private var messageColumn: some View {
        Group {
            if isPad, let battle {
                VStack(alignment: .leading, spacing: 8) {
                    hpBar(
                        name: battle.kind.name,
                        current: battle.enemyHP,
                        previousHP: enemyHPBeforeDecrease,
                        residualProgress: enemyHPResidualProgress,
                        maximum: battle.kind.maxHP,
                        color: Color(red: 0.95, green: 0.31, blue: 0.24)
                    )

                    Spacer(minLength: 8)

                    Text(currentMessage)
                        .font(DungeonTypography.maruMonica(size: 19))
                        .foregroundStyle(.white)
                        .lineLimit(messageLineLimit + 1)
                        .lineSpacing(2)
                        .multilineTextAlignment(.leading)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer(minLength: 8)

                    hpBar(
                        name: "YOU",
                        current: playerHP,
                        previousHP: playerHPBeforeDecrease,
                        residualProgress: playerHPResidualProgress,
                        maximum: GameState.playerMaxHP,
                        color: Color(red: 0.28, green: 0.82, blue: 0.48)
                    )
                }
            } else {
                VStack(alignment: .leading, spacing: isPad ? 8 : 5) {
                    Text(currentMessage)
                        .font(DungeonTypography.maruMonica(size: ((battle == nil || isPad) ? 15 : 13) + (isPad ? 4 : 0)))
                        .foregroundStyle(.white)
                        .lineLimit(messageLineLimit + (isPad ? 1 : 0))
                        .lineSpacing(2)
                        .multilineTextAlignment(.leading)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // iPadでは文字を上、HPバーを下に寄せて、状況欄の高さを使い切る。
                    if isPad {
                        Spacer(minLength: 0)
                    }

                    hpBarContainer {
                        hpBar(
                            name: battle == nil ? "HP" : "YOU",
                            current: playerHP,
                            previousHP: playerHPBeforeDecrease,
                            residualProgress: playerHPResidualProgress,
                            maximum: GameState.playerMaxHP,
                            color: Color(red: 0.28, green: 0.82, blue: 0.48)
                        )
                        if let battle {
                            hpBar(
                                name: battle.kind.name,
                                current: battle.enemyHP,
                                previousHP: enemyHPBeforeDecrease,
                                residualProgress: enemyHPResidualProgress,
                                maximum: battle.kind.maxHP,
                                color: Color(red: 0.95, green: 0.31, blue: 0.24)
                            )
                        }
                    }
                }
            }
        }
    }

    /// Playerドラゴン(動き・反応・ダメージ表示を含む)
    private var characterStack: some View {
        ZStack(alignment: .topTrailing) {
            Image(imageName)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: characterSize.width, height: characterSize.height)
                .offset(x: isTrapReactionActive ? trapAnimationOffset : collisionShakeOffset + attackOffset + damageShakeOffset)
                .scaleEffect(battle != nil ? (attackOffset == 0 ? (isBreathing ? 1.04 : 1) : 1.12) : 1)
                .rotationEffect(.degrees(isTrapReactionActive ? trapAnimationTilt : collisionTilt + damageTilt))
                .overlay {
                    Image(imageName)
                        .resizable()
                        .scaledToFit()
                        .colorMultiply(Color(red: 1.0, green: 0.10, blue: 0.08))
                        .opacity(damageFlashOpacity)
                        .accessibilityHidden(true)
                }
                .accessibilityHidden(true)
                .animation(.easeInOut(duration: 0.08), value: imageName)

            Text("-\(damageNumberAmount)")
                .font(DungeonTypography.maruMonica(size: 19))
                .foregroundStyle(Color(red: 1.0, green: 0.30, blue: 0.25))
                .shadow(color: .black, radius: 2, y: 1)
                .opacity(damageNumberOpacity)
                .offset(x: -21 * characterScale, y: damageNumberOffset)
                .accessibilityLabel("HPが\(damageNumberAmount)減少")
                .accessibilityHidden(damageNumberOpacity == 0)

            if isTrapReactionActive {
                Text("！？")
                    .font(DungeonTypography.maruMonica(size: 21))
                    .foregroundStyle(Color(red: 1.0, green: 0.72, blue: 0.24))
                    .shadow(color: .black, radius: 2, y: 1)
                    .offset(x: -1, y: 0)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityHidden(true)
            } else if battle != nil {
                Text("!")
                    .font(DungeonTypography.maruMonica(size: 23))
                    .foregroundStyle(Color(red: 1.0, green: 0.79, blue: 0.22))
                    .shadow(color: .black, radius: 2, y: 1)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityHidden(true)
            } else if isSurprised {
                Text("!")
                    .font(DungeonTypography.maruMonica(size: 22))
                    .foregroundStyle(Color(red: 1.0, green: 0.72, blue: 0.24))
                    .shadow(color: .black, radius: 2, y: 1)
                    .offset(x: -3, y: 1)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityHidden(true)
            }
            if isCrying {
                HStack(spacing: 22) {
                    tearDrop.rotationEffect(.degrees(18)).offset(y: 3)
                    tearDrop.rotationEffect(.degrees(-18)).offset(y: 1)
                }
                .offset(x: -18 * characterScale, y: 44 * characterScale)
                .transition(.scale.combined(with: .opacity))
                .accessibilityHidden(true)
            }
            if isTrapReactionActive {
                HStack(spacing: 26) {
                    tearDrop.rotationEffect(.degrees(18)).offset(y: 7)
                    tearDrop.rotationEffect(.degrees(-18)).offset(y: 2)
                }
                .offset(x: -18 * characterScale, y: 43 * characterScale)
                .transition(.scale.combined(with: .opacity))
                .accessibilityHidden(true)
            }
        }
        .frame(width: characterSize.width, height: characterSize.height + 2)
    }

    /// HPバーの並べ方。iPhoneは横並び、iPadは文字を読みやすくするため縦に積む。
    @ViewBuilder
    private func hpBarContainer<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if isPad {
            VStack(spacing: 8) { content() }
        } else {
            HStack(spacing: 9) { content() }
        }
    }

    var body: some View {
        layout
        .onChangeCompat(of: reactionID) { _, _ in
            playMovementAnimation()
        }
        .onChangeCompat(of: surpriseReactionID) { _, _ in
            playSurpriseAnimation()
        }
        .onChangeCompat(of: playerAttackAnimationID) { _, _ in
            playBattleAttackAnimation()
        }
        .onChangeCompat(of: playerDamageAnimationID) { _, _ in
            playPlayerDamageAnimation()
        }
        .onChangeCompat(of: playerHP) { oldHP, newHP in
            updateHPDecreaseDisplay(oldHP: oldHP, newHP: newHP, isPlayer: true)
        }
        .onChangeCompat(of: battle?.enemyHP) { oldHP, newHP in
            guard let oldHP, let newHP else {
                enemyHPDecreaseTask?.cancel()
                enemyHPBeforeDecrease = nil
                enemyHPResidualProgress = 0
                return
            }
            updateHPDecreaseDisplay(oldHP: oldHP, newHP: newHP, isPlayer: false)
        }
        .onChangeCompat(of: wallCollisionID) { _, _ in
            playWallCollisionReaction()
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 750_000_000)
                guard !Task.isCancelled else { break }
                isBreathing.toggle()
            }
        }
        .onDisappear {
            reactionTask?.cancel()
            playerHPDecreaseTask?.cancel()
            enemyHPDecreaseTask?.cancel()
        }
    }

    private var tearDrop: some View {
        Image(systemName: "drop.fill")
            .font(DungeonTypography.maruMonica(size: 10))
            .foregroundStyle(Color(red: 0.35, green: 0.78, blue: 1.0))
            .shadow(color: .black.opacity(0.8), radius: 2, y: 1)
    }

    private func hpBar(
        name: String?,
        current: Int,
        previousHP: Int?,
        residualProgress: CGFloat,
        maximum: Int,
        color: Color
    ) -> some View {
        let isLowHP = current > 0 && current <= 13
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 3) {
                if let name {
                    Text(name).lineLimit(1).minimumScaleFactor(0.65)
                }
                Spacer(minLength: 1)
                Text("\(current)/\(maximum)").monospacedDigit()
            }
            .font(DungeonTypography.maruMonica(size: isPad ? 14 : 10))
            .foregroundStyle(isLowHP ? Color.yellow : Color.white.opacity(0.92))
            GeometryReader { geometry in
                let safeMaximum = max(1, maximum)
                let currentWidth = geometry.size.width * CGFloat(max(0, min(current, safeMaximum))) / CGFloat(safeMaximum)
                let previousWidth = geometry.size.width * CGFloat(max(0, min(previousHP ?? current, safeMaximum))) / CGFloat(safeMaximum)
                let residualWidth = currentWidth + max(0, previousWidth - currentWidth) * residualProgress
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.white.opacity(0.18))
                    if let previousHP, previousHP > current, residualProgress > 0 {
                        Rectangle()
                            .fill(Color(red: 1.0, green: 0.82, blue: 0.20))
                            .frame(width: max(0, residualWidth - currentWidth))
                            .offset(x: currentWidth)
                    }
                    Rectangle()
                        .fill(color)
                        .frame(width: currentWidth)
                }
            }
            .frame(height: isPad ? (battle == nil ? 11 : 20) : 6)
        }
        .padding(4)
        .frame(maxWidth: .infinity)
        .overlay {
            if isLowHP {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.red, lineWidth: 2)
            }
        }
    }

    /// HP減少時は残像の幅を1.2秒かけて縮め、回復時は残像を解除する。
    private func updateHPDecreaseDisplay(oldHP: Int, newHP: Int, isPlayer: Bool) {
        let task = isPlayer ? playerHPDecreaseTask : enemyHPDecreaseTask
        task?.cancel()

        if newHP >= oldHP {
            if isPlayer {
                playerHPBeforeDecrease = nil
                playerHPResidualProgress = 0
                playerHPDecreaseTask = nil
            } else {
                enemyHPBeforeDecrease = nil
                enemyHPResidualProgress = 0
                enemyHPDecreaseTask = nil
            }
            return
        }

        // 連続被弾時は、残っている残像位置より後退しないよう最大値を保持する。
        let previousDisplayedHP = isPlayer
            ? max(playerHPBeforeDecrease ?? oldHP, oldHP)
            : max(enemyHPBeforeDecrease ?? oldHP, oldHP)
        var noAnimation = Transaction()
        noAnimation.animation = nil
        withTransaction(noAnimation) {
            if isPlayer {
                playerHPBeforeDecrease = previousDisplayedHP
                playerHPResidualProgress = 1
            } else {
                enemyHPBeforeDecrease = previousDisplayedHP
                enemyHPResidualProgress = 1
            }
        }

        let clearTask = Task { @MainActor in
            // いったん減少前の幅を描画してから、残像だけを滑らかに縮める。
            await Task.yield()
            guard !Task.isCancelled else { return }
            withAnimation(.linear(duration: 1.2)) {
                if isPlayer {
                    playerHPResidualProgress = 0
                } else {
                    enemyHPResidualProgress = 0
                }
            }
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            if isPlayer {
                playerHPBeforeDecrease = nil
                playerHPDecreaseTask = nil
            } else {
                enemyHPBeforeDecrease = nil
                enemyHPDecreaseTask = nil
            }
        }

        if isPlayer {
            playerHPDecreaseTask = clearTask
        } else {
            enemyHPDecreaseTask = clearTask
        }
    }

    private func playMovementAnimation() {
        guard !isTrapReactionActive else { return }
        reactionTask?.cancel()
        isSurprised = false
        isCrying = false
        collisionShakeOffset = 0
        collisionTilt = 0
        reactionTask = Task { @MainActor in
            for frame in ["PlayerMove1", "PlayerMove2", "PlayerMove3"] {
                guard !Task.isCancelled else { return }
                actionFrame = frame
                try? await Task.sleep(nanoseconds: 110_000_000)
            }
            guard !Task.isCancelled else { return }
            actionFrame = nil
        }
    }

    private func playSurpriseAnimation() {
        reactionTask?.cancel()
        isCrying = false
        reactionTask = Task { @MainActor in
            isSurprised = true
            let reactions: [(CGFloat, Double, String)] = [
                (-6, -11, "PlayerBlink"),
                (7, 9, "PlayerIdle"),
                (-4, -6, "PlayerBlink"),
                (2, 3, "PlayerIdle"),
                (0, 0, "PlayerBlink")
            ]

            for (offset, tilt, frame) in reactions {
                guard !Task.isCancelled else { return }
                actionFrame = frame
                withAnimation(.spring(response: 0.075, dampingFraction: 0.48)) {
                    collisionShakeOffset = offset
                    collisionTilt = tilt
                }
                try? await Task.sleep(nanoseconds: 85_000_000)
            }

            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.18, dampingFraction: 0.62)) {
                collisionShakeOffset = 0
                collisionTilt = 0
                isSurprised = false
            }
            actionFrame = nil
        }
    }

    private func playBattleAttackAnimation() {
        guard battle != nil else { return }
        reactionTask?.cancel()
        reactionTask = Task { @MainActor in
            withAnimation(.spring(response: 0.12, dampingFraction: 0.48)) {
                attackOffset = -19
            }
            try? await Task.sleep(nanoseconds: 345_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.17, dampingFraction: 0.58)) { attackOffset = 0 }
            reactionTask = nil
        }
    }

    private func playPlayerDamageAnimation() {
        guard battle != nil else { return }
        reactionTask?.cancel()
        isCrying = false
        isSurprised = false
        damageNumberAmount = playerDamageAmount
        damageNumberOffset = 8
        reactionTask = Task { @MainActor in
            withAnimation(.easeOut(duration: 0.08)) {
                damageFlashOpacity = 0.9
                damageShakeOffset = -11
                damageTilt = -13
                damageNumberOpacity = 1
            }
            try? await Task.sleep(nanoseconds: 90_000_000)
            guard !Task.isCancelled else { return }

            for (offset, tilt) in [(CGFloat(10), 12.0), (CGFloat(-6), -8.0), (CGFloat(0), 0.0)] {
                withAnimation(.spring(response: 0.09, dampingFraction: 0.48)) {
                    damageShakeOffset = offset
                    damageTilt = tilt
                    damageFlashOpacity = offset == 0 ? 0 : 0.78
                    damageNumberOffset -= 10
                }
                try? await Task.sleep(nanoseconds: 105_000_000)
                guard !Task.isCancelled else { return }
            }

            withAnimation(.easeOut(duration: 0.2)) {
                damageFlashOpacity = 0
                damageShakeOffset = 0
                damageTilt = 0
                damageNumberOpacity = 0
            }
            reactionTask = nil
        }
    }

    private func playWallCollisionReaction() {
        reactionTask?.cancel()
        reactionTask = Task { @MainActor in
            isCrying = true
            isSurprised = false
            actionFrame = "PlayerBlink"
            for offset in [CGFloat(-5), 5, -3, 0] {
                guard !Task.isCancelled else { return }
                withAnimation(.spring(response: 0.08, dampingFraction: 0.5)) {
                    collisionShakeOffset = offset
                    collisionTilt = offset == 0 ? 0 : Double(offset) * 1.4
                }
                try? await Task.sleep(nanoseconds: 90_000_000)
            }
            guard !Task.isCancelled else { return }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                isCrying = false
                collisionShakeOffset = 0
                collisionTilt = 0
            }
            actionFrame = nil
        }
    }
}

extension View {
    /// 暗い地に細い縁を引いた、探索・戦闘画面の情報枠。
    func dungeonPanel(cornerRadius: CGFloat = 8) -> some View {
        self
            .background(Color(red: 0.075, green: 0.07, blue: 0.06))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color(red: 0.42, green: 0.39, blue: 0.32), lineWidth: 1)
            }
    }
}
