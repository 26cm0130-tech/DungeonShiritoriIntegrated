import SwiftUI
import UIKit
import AVFoundation

/// プレイ画面。表示と入力の受け渡しだけを行い、ゲームの状態は GameManager が持つ
struct PlayView: View {
    /// 現在のプレイ(AppFlow が作って渡す)
    @ObservedObject var game: GameManager

    /// 画面遷移中・結果表示中は移動入力を受け付けない。
    let isInputEnabled: Bool

    /// 計時対象の面で計測中なら単調増加時計の開始時刻
    let timerStartedAt: TimeInterval?

    /// ギブアップが確定したときの処理(スタート画面へ戻る)
    let onGiveUp: () -> Void

    /// ギブアップの確認を表示中か
    @State private var isConfirmingGiveUp = false
    /// 鍵取得演出を表示中か
    @State private var isShowingKeyAcquisition = false
    @State private var isShowingSwordPickup = false
    @State private var itemPickupUnlockTask: Task<Void, Never>?
    @State private var isShowingDropPickup = false
    @State private var dropPickupTask: Task<Void, Never>?
    @State private var swordDropTask: Task<Void, Never>?
    @State private var dropItemAudioPlayer: AVAudioPlayer?
    @State private var dropItemAudioErrorDelegate: AudioPlaybackErrorDelegate?
    @State private var isMapExpanded = false
    @State private var isMapPinchGestureActive = false
    @State private var pinchSuppressionTask: Task<Void, Never>?
    /// 直近のフリック方向を矢印ガイドに表示する
    @State private var activeFlickDirection: MovementFlickDirection?
    /// プレイヤーの位置・向きが変わるたびに、メッセージ横のモンスターを動かす
    @State private var monsterReactionID = 0
    @State private var dungeonShakeOffset: CGFloat = 0
    @State private var collisionFlashOpacity = 0.0
    @State private var wallCollisionAnimationTask: Task<Void, Never>?
    @State private var isShowingEventCutIn = false
    @State private var eventCutInTitle = ""
    @State private var eventCutInMessage = ""
    @State private var eventCutInStyle: PlayerCutInStyle = .wall
    @State private var eventCutInTask: Task<Void, Never>?
    /// トラップ時はカットインと状況欄の反応を同時に開始・終了する。
    @State private var isTrapReactionActive = false
    @State private var trapAnimationFrame = "PlayerIdle"
    @State private var trapAnimationOffset: CGFloat = 0
    @State private var trapAnimationTilt = 0.0
    @State private var trapAnimationTask: Task<Void, Never>?
    @State private var isBattleActionLocked = false
    @State private var battleActionTask: Task<Void, Never>?
    @State private var playerAttackAnimationID = 0
    @State private var enemyCounterAttackAnimationID = 0
    /// 撃破確定前に、敵の最後ののけぞり演出を再生する。
    @State private var enemyDefeatRecoilAnimationID = 0
    @State private var battleScreenFlashColor: Color = .blue
    @State private var battleScreenFlashOpacity = 0.0
    @State private var battleScreenFlashScale: CGFloat = 1
    @State private var battleScreenWhiteFlashOpacity = 0.0
    @State private var battleScreenFlashTask: Task<Void, Never>?

    private let battleSoundEffects = SoundEffectController()

    /// プレイヤーが鍵のあるマスにいるか
    private var isStandingAtKey: Bool {
        game.map.cell(at: game.state.player.position) == .key
    }

    /// 鍵・剣の取得演出と、撃破直後からドロップ取得完了まで移動入力を止める。
    private var isAcquisitionAnimationActive: Bool {
        isShowingKeyAcquisition || isShowingSwordPickup || isShowingDropPickup
            || game.isSkeletonDropPickupInputLocked || game.isItemPickupInputLocked
    }

    /// イベントの状況メッセージを優先し、なければチュートリアル案内を表示する
    private var displayedMessage: String {
        game.state.message.isEmpty
            ? game.state.tutorialStep?.instruction ?? "迷宮を探索しよう"
            : game.state.message
    }

    private var playerMotionKey: String {
        "\(game.state.player.position.x),\(game.state.player.position.y),\(game.state.player.direction.rawValue)"
    }

    private func finishFlick(in direction: MovementFlickDirection) {
        activeFlickDirection = direction
        Haptics.impact(.light, intensity: 0.55)
    }

    /// 取得演出を閉じるフェードが終わるまでモデル側の移動ロックを保つ。
    private func closeItemPickupPresentation(
        animationDuration: TimeInterval,
        hide: () -> Void
    ) {
        withAnimation(.easeOut(duration: animationDuration)) {
            hide()
        }
        itemPickupUnlockTask?.cancel()
        let delay = UInt64(animationDuration * 1_000_000_000)
        itemPickupUnlockTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            game.finishItemPickupPresentation()
            itemPickupUnlockTask = nil
        }
    }

    /// ダンジョン画面、ステータス、メッセージ、探索マップからフリック操作を受け付ける。
    private var movementFlickGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                guard isInputEnabled, !isMapPinchGestureActive, !isMapExpanded else { return }
                if let direction = MovementFlickDirection.classify(
                    horizontal: value.translation.width,
                    vertical: value.translation.height,
                    threshold: 16
                ) {
                    activeFlickDirection = direction
                }
            }
            .onEnded { value in
                guard isInputEnabled,
                      !isAcquisitionAnimationActive,
                      !isMapPinchGestureActive,
                      !isMapExpanded else { return }
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard let direction = MovementFlickDirection.classify(
                    horizontal: horizontal,
                    vertical: vertical,
                    threshold: 16
                ) else { return }

                finishFlick(in: direction)
                switch direction {
                case .left: game.turnLeft()
                case .forward: game.moveForward()
                case .right: game.turnRight()
                case .backward: game.turnAround()
                }
            }
    }

    var body: some View {
        GeometryReader { geometry in
            let isPad = IPadLayoutMetrics.isPad
            let isCompact = geometry.size.height < 700
            // iPadでは、ダンジョン画面(正方形)を横幅いっぱいに近い大きさまで広げ、残りの縦幅をほかの段に割り当てる。
            let dungeonHeight = isPad
                ? max(300, min(geometry.size.width - 24, geometry.size.height - IPadLayoutMetrics.playViewNonDungeonHeight))
                : min(geometry.size.height * (isCompact ? 0.38 : 0.41), geometry.size.width * 0.98)
            let explorationMapHeight = max(geometry.size.height * (isCompact ? 0.14 : 0.18), isCompact ? 100 : 135)

            VStack(spacing: isPad ? 8 : (isCompact ? 6 : 10)) {
            // ① ダンジョン画面
            DungeonView(
                map: game.map,
                player: game.state.player,
                theme: game.stage.dungeonTheme,
                hasKey: game.state.hasKey,
                isGoalReached: game.state.isCleared,
                defeatedEnemyKinds: game.state.defeatedEnemyKinds,
                largeDefeatGraphicPosition: game.defeatedEnemyLargeGraphicPosition,
                activatedTrapPositions: game.state.activatedTrapPositions
            )
            .overlay {
                if let battle = game.state.enemyBattle {
                    EnemyBattleView(
                        battle: battle,
                        playerHP: game.state.playerHP,
                        playerAttackAnimationID: playerAttackAnimationID,
                        counterAttackAnimationID: enemyCounterAttackAnimationID,
                        defeatRecoilAnimationID: enemyDefeatRecoilAnimationID
                    )
                    .transition(.opacity)
                    .zIndex(3)
                }
            }
            .overlay {
                if let speech = game.encounterEnemySpeech {
                    EnemyEncounterSpeechOverlay(
                        speech: speech,
                        showEnemySprite: game.state.enemyBattle == nil
                            && !game.state.defeatedEnemies.contains(speech.position)
                    )
                    .id(speech.id)
                    .zIndex(4)
                }
            }
            .overlay {
                if let speech = game.defeatedEnemySpeech,
                   game.defeatedEnemyLargeGraphicKind == speech.kind {
                    GeometryReader { geometry in
                        Image(speech.kind.defeatedImageName)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(
                                width: min(geometry.size.width * 0.62, IPadLayoutMetrics.isPad ? 340 : 190),
                                height: min(geometry.size.height * (IPadLayoutMetrics.isPad ? 0.60 : 0.76), IPadLayoutMetrics.isPad ? 340 : 190)
                            )
                            .shadow(color: .black.opacity(0.72), radius: 12, y: 6)
                            .position(
                                x: geometry.size.width * 0.5,
                                y: geometry.size.height * (IPadLayoutMetrics.isPad ? 0.52 : 0.57)
                            )
                    }
                    .allowsHitTesting(false)
                    .zIndex(2)
                }
            }
            .overlay {
                if let speech = game.defeatedEnemySpeech {
                    EnemyDefeatSpeechOverlay(speech: speech)
                        .id(speech.id)
                        .zIndex(3)
                }
            }
            .overlay {
                if isStandingAtKey && isShowingKeyAcquisition {
                    KeyAcquisitionView(
                        onFinished: {
                            closeItemPickupPresentation(animationDuration: 0.2) {
                                isShowingKeyAcquisition = false
                            }
                        }
                    )
                    .padding(2)
                    .transition(.opacity)
                }
            }
            .overlay {
                if game.state.isCleared {
                    ZStack {
                        Color.black.opacity(0.50)
                        Image("DungeonDoorOpen")
                            .resizable()
                            .scaledToFit()
                            .frame(width: dungeonHeight * 0.76, height: dungeonHeight * 0.76)
                            .shadow(color: .black.opacity(0.8), radius: 16)
                        Text("扉が開いた！")
                            .font(DungeonTypography.maruMonica(size: 18))
                            .foregroundStyle(Color(red: 1.0, green: 0.84, blue: 0.45))
                            .shadow(color: .black, radius: 4)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                            .padding(.bottom, 18)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .transition(.opacity)
                    .zIndex(5)
                }
            }
            .overlay {
                if isShowingSwordPickup {
                    SwordPickupView {
                        closeItemPickupPresentation(animationDuration: 0.22) {
                            isShowingSwordPickup = false
                        }
                    }
                    .padding(2)
                    .transition(.opacity)
                    .zIndex(4)
                }
            }
            .overlay {
                if isShowingDropPickup, let item = game.pendingSkeletonDrop {
                    VStack(spacing: 16) {
                        PixelDropItemIcon(item: item)
                            .frame(width: 92, height: 92)
                        Text("\(item.title)を手に入れた！")
                            .font(DungeonTypography.maruMonica(size: 24))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(item.effect)
                            .font(DungeonTypography.maruMonica(size: 20))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineSpacing(5)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.76))
                    .padding(.horizontal, 28)
                    .transition(.scale.combined(with: .opacity))
                    .zIndex(6)
                }
            }
            .overlay {
                Rectangle()
                    .fill(Color(red: 0.75, green: 0.12, blue: 0.16).opacity(collisionFlashOpacity))
                    .allowsHitTesting(false)
            }
            .offset(x: dungeonShakeOffset)
            .contentShape(Rectangle())
            .simultaneousGesture(movementFlickGesture)
            .frame(height: dungeonHeight)
            .overlay {
                ZStack {
                    BattleShockwaveShape()
                        .fill(battleScreenFlashColor)
                        .opacity(battleScreenFlashOpacity)
                        .scaleEffect(battleScreenFlashScale)

                    // 衝撃の瞬間だけ、中心に短い白い閃光を重ねる。
                    BattleShockwaveShape()
                        .fill(Color.white)
                        .opacity(battleScreenWhiteFlashOpacity)
                        .scaleEffect(0.22)
                }
                .allowsHitTesting(false)
                .clipped()
            }

            .overlay(alignment: .bottom) {
                // iPadの戦闘中だけ、こうげき・にげる・ギブアップをダンジョン画面の下端に置く。
                if isPad, game.state.enemyBattle != nil {
                    iPadBattleCommandBar
                        .frame(width: dungeonHeight)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                        .transition(.opacity)
                        .zIndex(8)
                }
            }

            if isPad {
                // iPad: ダンジョン画面の下を3列にする。戦闘中も同じ構成のまま使う。
                //   左  = キャラクター
                //   中央 = ステージ名 / 状況とHP / フリック案内
                //   右  = 鍵の状態 / 探索マップ
                HStack(alignment: .top, spacing: 8) {
                    monsterMessageView

                    VStack(spacing: 8) {
                        keyStatusLabel
                            .padding(.horizontal, 8)
                            .frame(maxWidth: .infinity)
                            .frame(height: IPadLayoutMetrics.stageTitleHeight)
                            .dungeonPanel(cornerRadius: 6)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(statusAccessibilityLabel)
                            .contentShape(Rectangle())
                            .simultaneousGesture(movementFlickGesture)

                        explorationMapView
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(width: IPadLayoutMetrics.mapColumnWidth)
                    .frame(height: IPadLayoutMetrics.infoPanelHeight)
                }
                .frame(height: IPadLayoutMetrics.infoPanelHeight)

                // タイマーとギブアップ(戦闘中のボタンはダンジョン画面の下端にある)
                commandView(style: .iPadFooter)
            } else {
                // ステージと鍵の状態は、イベントメッセージが変わっても常に確認できる
                statusBar
                    .contentShape(Rectangle())
                    .simultaneousGesture(movementFlickGesture)

                // ② メッセージ(段階案内と状況メッセージを固定の高さに表示する)
                monsterMessageView

                // ③ 探索マップ
                explorationMapView
                    .frame(maxWidth: .infinity)
                    .frame(height: explorationMapHeight)

                // ④ コマンド
                commandView(style: .standard)
            }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DungeonBackground())
        }
        .overlay {
            if isMapExpanded {
                ZStack(alignment: .topTrailing) {
                    Color.black.opacity(0.94).ignoresSafeArea()
                    AutoMapView(
                        map: game.map,
                        explored: game.state.explored,
                        player: game.state.player,
                        defeatedEnemies: game.state.defeatedEnemies,
                        defeatedEnemyKinds: game.state.defeatedEnemyKinds,
                        activatedTrapPositions: game.state.activatedTrapPositions
                    )
                    .padding(22)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .simultaneousGesture(
                        MagnificationGesture()
                            .onChanged { scale in
                                suppressMovementDuringMapPinch()
                                if scale <= 0.82 { withAnimation(.easeOut(duration: 0.18)) { isMapExpanded = false } }
                            }
                    )
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) { isMapExpanded = false }
                    } label: {
                        Label("閉じる", systemImage: "xmark.circle.fill")
                            .font(DungeonTypography.maruMonica(size: 16))
                            .padding(10)
                            .background(.black.opacity(0.7), in: Capsule())
                    }
                    .foregroundStyle(.white)
                    .padding(.top, 14)
                    .padding(.trailing, 14)
                }
                .transition(.opacity)
                .zIndex(20)
            }
        }
        // ギブアップの確認(表示中は、後ろの操作を受け付けない)
        .overlay {
            if isConfirmingGiveUp {
                GiveUpConfirmView(
                    onYes: onGiveUp,
                    onNo: { isConfirmingGiveUp = false }
                )
            }
        }
        .overlay(alignment: .top) {
            if isShowingEventCutIn {
                PlayerEventCutIn(
                    title: eventCutInTitle,
                    message: eventCutInMessage,
                    style: eventCutInStyle,
                    animationFrame: eventCutInStyle == .trap ? trapAnimationFrame : nil,
                    animationOffset: eventCutInStyle == .trap ? trapAnimationOffset : 0,
                    animationTilt: eventCutInStyle == .trap ? trapAnimationTilt : 0
                )
                    .padding(.horizontal, 14)
                    .padding(.top, 58)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                    .zIndex(2)
            }
        }
        .onChangeCompat(of: game.state.hasKey) { hadKey, hasKey in
            // hasKey が初めて false から true になったときだけ演出する
            if !hadKey && hasKey {
                withAnimation(.easeIn(duration: 0.12)) {
                    isShowingKeyAcquisition = true
                }
            }
        }
        .onChangeCompat(of: game.state.hasSword) { hadSword, hasSword in
            // 剣を初めて取得した瞬間、ダンジョン表示にアイテムを重ねる。
            if !hadSword && hasSword {
                withAnimation(.easeIn(duration: 0.12)) {
                    isShowingSwordPickup = true
                }
            }
        }
        .onChangeCompat(of: isStandingAtKey) { _, isAtKey in
            // 鍵のあるマスを離れたら取得演出を終了する
            if !isAtKey {
                isShowingKeyAcquisition = false
            }
        }
        .onChangeCompat(of: playerMotionKey) { _, _ in
            monsterReactionID += 1
        }
        .onChangeCompat(of: game.wallCollisionID) { _, _ in
            Haptics.impact(.heavy, intensity: 1.0)
            playWallCollisionAnimation()
        }
        .onChangeCompat(of: game.trapActivationID) { _, _ in
            Haptics.impact(.heavy, intensity: 1.0)
            showEventCutIn(
                title: "TRAP!",
                message: game.state.trapActivationMessage ?? "滑った、、",
                style: .trap,
                startsTrapReaction: true
            )
        }
        .onChangeCompat(of: game.enemyEncounterID) { _, _ in
            Haptics.notification(.warning)
            showEventCutIn(title: "ENCOUNTER", message: "敵が現れた！", style: .encounter)
        }
        .onChangeCompat(of: game.defeatedEnemySpeech) { oldSpeech, newSpeech in
            guard oldSpeech != nil, newSpeech == nil else { return }
            beginPendingDropPickup()
            beginPendingSwordDrop()
        }
        .onDisappear {
            battleActionTask?.cancel()
            battleScreenFlashTask?.cancel()
            wallCollisionAnimationTask?.cancel()
            wallCollisionAnimationTask = nil
            dungeonShakeOffset = 0
            collisionFlashOpacity = 0
            dropPickupTask?.cancel()
            swordDropTask?.cancel()
            itemPickupUnlockTask?.cancel()
            itemPickupUnlockTask = nil
            game.cancelItemPickupPresentation()
            isShowingDropPickup = false
            game.cancelSkeletonDropPickupPresentation()
            eventCutInTask?.cancel()
            trapAnimationTask?.cancel()
            pinchSuppressionTask?.cancel()
            isTrapReactionActive = false
            trapAnimationFrame = "PlayerIdle"
            trapAnimationOffset = 0
            trapAnimationTilt = 0
        }
    }

    /// 3D描写画面内だけで、不規則な衝撃波を収縮または拡散させる。
    private func triggerBattleScreenFlash(color: Color, expands: Bool) {
        battleScreenFlashTask?.cancel()
        battleScreenFlashColor = color
        battleScreenFlashScale = expands ? 0.04 : 1
        battleScreenFlashOpacity = 0.42
        battleScreenWhiteFlashOpacity = 0.78

        battleScreenFlashTask = Task { @MainActor in
            // 白い閃光は衝撃の瞬間だけ表示し、すぐに消す。
            try? await Task.sleep(nanoseconds: 55_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.05)) {
                battleScreenWhiteFlashOpacity = 0
            }

            for _ in 0..<2 {
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.14)) {
                    battleScreenFlashScale = expands ? 1 : 0.04
                }
                try? await Task.sleep(nanoseconds: 145_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.045)) {
                    battleScreenFlashOpacity = 0
                }
                try? await Task.sleep(nanoseconds: 55_000_000)
                guard !Task.isCancelled else { return }
                battleScreenFlashScale = expands ? 0.04 : 1
                withAnimation(.easeIn(duration: 0.035)) {
                    battleScreenFlashOpacity = 0.42
                }
            }
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.08)) {
                battleScreenFlashOpacity = 0
            }
            battleScreenFlashTask = nil
        }
    }

    private func performBattleAttack() {
        guard !isBattleActionLocked,
              let battleBeforeAttack = game.state.enemyBattle else { return }
        Haptics.impact(.medium, intensity: 0.8)
        isBattleActionLocked = true
        battleActionTask?.cancel()
        battleActionTask = Task { @MainActor in
            // GameManager.attackEnemy() と同じ条件で撃破可能かを判定する。
            let gargoyleNeedsSword = game.state.requiresSwordForKey
                && battleBeforeAttack.kind == .gargoyle
                && !game.state.hasSword
            let playerDamage = gargoyleNeedsSword ? 0 : (game.state.hasSword ? 10 : 5)
            let willDefeatEnemy = playerDamage > 0
                && battleBeforeAttack.enemyHP <= playerDamage

            // プレイヤーの踏み込み後、青い画面フラッシュと敵の被弾を同時に見せる。
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }
            playerAttackAnimationID += 1
            // 剣を持っている間は、プレイヤーの攻撃音を剣の斬撃音に変える。
            battleSoundEffects.play(game.state.hasSword ? .swordAttack : .battleAttack)
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            triggerBattleScreenFlash(color: .blue, expands: false)

            if willDefeatEnemy {
                // 青い閃光のあと、赤い閃光とのけぞりを見せてから撃破処理を行う。
                try? await Task.sleep(nanoseconds: 480_000_000)
                guard !Task.isCancelled, game.state.enemyBattle != nil else {
                    isBattleActionLocked = false
                    battleActionTask = nil
                    return
                }
                triggerBattleScreenFlash(color: .red, expands: true)
                enemyDefeatRecoilAnimationID += 1

                // のけぞりが終わるまで撃破処理を保留し、死体表示への切り替えを遅らせる。
                try? await Task.sleep(nanoseconds: 330_000_000)
                guard !Task.isCancelled, game.state.enemyBattle != nil else {
                    isBattleActionLocked = false
                    battleActionTask = nil
                    return
                }
                game.attackEnemy()
                isBattleActionLocked = false
                battleActionTask = nil
                return
            }

            game.attackEnemy()

            // 敵が倒れた場合は反撃せず、攻撃演出の後に入力を解放する。
            guard game.state.enemyBattle != nil, !Task.isCancelled else {
                isBattleActionLocked = false
                battleActionTask = nil
                return
            }

            // 敵の被弾・HP減少を約1秒見せてから、敵の反撃モーションへ移る。
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled,
                  let counterattackingEnemy = game.state.enemyBattle else { return }
            enemyCounterAttackAnimationID += 1
            if let counterattackAudioResource = counterattackingEnemy.kind.counterattackAudioResource {
                battleSoundEffects.play(counterattackAudioResource)
            }
            try? await Task.sleep(nanoseconds: EnemyCounterattackTiming.impactNanoseconds)
            guard !Task.isCancelled, game.state.enemyBattle != nil else { return }
            triggerBattleScreenFlash(color: .red, expands: true)
            Haptics.impact(.heavy, intensity: 1.0)
            game.counterattackEnemy()

            try? await Task.sleep(nanoseconds: EnemyCounterattackTiming.recoveryNanoseconds)
            guard !Task.isCancelled else { return }
            isBattleActionLocked = false
            battleActionTask = nil
        }
    }

    /// 撃破セリフが終わってから、少し間を置いて敵が落とした剣を取得する。
    private func beginPendingSwordDrop() {
        guard game.pendingSwordDrop != nil,
              game.encounterEnemySpeech == nil,
              game.defeatedEnemySpeech == nil else { return }
        swordDropTask?.cancel()
        swordDropTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            game.collectPendingSwordDrop()
            swordDropTask = nil
        }
    }

    /// 撃破セリフと倒れる動作が終わってから、ドロップを回収する。
    private func beginPendingDropPickup() {
        guard game.pendingSkeletonDrop != nil,
              game.encounterEnemySpeech == nil,
              game.defeatedEnemySpeech == nil,
              !isShowingDropPickup else { return }
        dropPickupTask?.cancel()
        withAnimation(.easeIn(duration: 0.18)) { isShowingDropPickup = true }
        playDropItemFoundSound()
        dropPickupTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.18)) { isShowingDropPickup = false }
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }
            game.collectPendingSkeletonDrop()
            game.finishSkeletonDropPickupPresentation()
            dropPickupTask = nil
        }
    }

    /// ピンチ操作の直後までフリックを抑止し、二本指の拡大縮小を誤移動にしない。
    private func suppressMovementDuringMapPinch() {
        isMapPinchGestureActive = true
        pinchSuppressionTask?.cancel()
        pinchSuppressionTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            isMapPinchGestureActive = false
            pinchSuppressionTask = nil
        }
    }

    /// MP3形式のアイテム発見音を再生し、再生中のプレイヤーとdelegateを保持する。
    private func playDropItemFoundSound() {
        AudioPlayback.stop(dropItemAudioPlayer)
        guard let player = AudioPlayback.makePlayer(for: .itemFound) else { return }
        let delegate = AudioPlaybackErrorDelegate(resource: .itemFound)
        player.delegate = delegate
        AudioPlayback.play(player, for: .itemFound)
        dropItemAudioPlayer = player
        dropItemAudioErrorDelegate = delegate
    }

    private func performBattleFlee() {
        guard !isBattleActionLocked, game.state.enemyBattle != nil else { return }
        isBattleActionLocked = true
        battleActionTask?.cancel()
        battleActionTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }
            battleSoundEffects.play(.battleEscape)
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            game.fleeBattle()
            isBattleActionLocked = false
            battleActionTask = nil
        }
    }

    private func playWallCollisionAnimation() {
        wallCollisionAnimationTask?.cancel()
        wallCollisionAnimationTask = Task { @MainActor in
            showEventCutIn(title: "WALL IMPACT", message: "痛い・・・", style: .wall)
            withAnimation(.easeOut(duration: 0.07)) { collisionFlashOpacity = 0.24 }
            for offset in [CGFloat(-8), 7, -4, 0] {
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.05)) { dungeonShakeOffset = offset }
                do {
                    try await Task.sleep(nanoseconds: 55_000_000)
                } catch {
                    return
                }
            }
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.18)) { collisionFlashOpacity = 0 }
            wallCollisionAnimationTask = nil
        }
    }

    private func showEventCutIn(
        title: String,
        message: String,
        style: PlayerCutInStyle,
        startsTrapReaction: Bool = false
    ) {
        eventCutInTask?.cancel()
        trapAnimationTask?.cancel()
        trapAnimationTask = nil
        isTrapReactionActive = startsTrapReaction
        trapAnimationFrame = startsTrapReaction ? "PlayerMove1" : "PlayerIdle"
        trapAnimationOffset = 0
        trapAnimationTilt = 0
        eventCutInTitle = title
        eventCutInMessage = message
        eventCutInStyle = style
        if startsTrapReaction {
            startTrapReactionAnimation()
        }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
            isShowingEventCutIn = true
        }
        eventCutInTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_250_000_000)
            guard !Task.isCancelled else { return }
            trapAnimationTask?.cancel()
            trapAnimationTask = nil
            withAnimation(.easeIn(duration: 0.2)) {
                isShowingEventCutIn = false
                isTrapReactionActive = false
                trapAnimationFrame = "PlayerIdle"
                trapAnimationOffset = 0
                trapAnimationTilt = 0
            }
            eventCutInTask = nil
        }
    }

    /// 状況欄とカットインに同じ目を開けたフレーム・揺れ・傾きを配る。
    private func startTrapReactionAnimation() {
        let frames: [(String, CGFloat, Double)] = [
            ("PlayerMove1", -8, -12),
            ("PlayerMove2", 9, 11),
            ("PlayerMove3", -6, -8),
            ("PlayerIdle", 5, 7),
            ("PlayerMove1", -2, -3)
        ]
        var frameIndex = 0
        trapAnimationTask = Task { @MainActor in
            while !Task.isCancelled {
                let (frame, offset, tilt) = frames[frameIndex % frames.count]
                withAnimation(.spring(response: 0.07, dampingFraction: 0.4)) {
                    trapAnimationFrame = frame
                    trapAnimationOffset = offset
                    trapAnimationTilt = tilt
                }
                try? await Task.sleep(nanoseconds: 105_000_000)
                guard !Task.isCancelled else { return }
                frameIndex += 1
            }
        }
    }

    private var monsterMessageView: some View {
        MonsterMessageView(
            message: displayedMessage,
            reactionID: monsterReactionID,
            surpriseReactionID: game.surpriseReactionID,
            isTrapReactionActive: isTrapReactionActive,
            trapAnimationFrame: trapAnimationFrame,
            trapAnimationOffset: trapAnimationOffset,
            trapAnimationTilt: trapAnimationTilt,
            wallCollisionID: game.wallCollisionID,
            playerAttackAnimationID: playerAttackAnimationID,
            playerDamageAnimationID: game.playerDamageAnimationID,
            playerDamageAmount: game.playerDamageAmount,
            battle: game.state.enemyBattle,
            playerHP: game.state.playerHP,
            isTutorial: game.stage.isStepByStepTutorial,
            iPadHeader: IPadLayoutMetrics.isPad ? AnyView(stageTitleLabel) : nil,
            // 戦闘中はフリックを使わないため案内を出さず、状況欄を広げてHPバーを読みやすくする。
            iPadFooter: (IPadLayoutMetrics.isPad && game.state.enemyBattle == nil)
                ? AnyView(commandView(style: .iPadFlickPanel))
                : nil
        )
            .contentShape(Rectangle())
            .simultaneousGesture(movementFlickGesture)
    }

    private var explorationMapView: some View {
        AutoMapView(
            map: game.map,
            explored: game.state.explored,
            player: game.state.player,
            defeatedEnemies: game.state.defeatedEnemies,
            defeatedEnemyKinds: game.state.defeatedEnemyKinds,
            activatedTrapPositions: game.state.activatedTrapPositions
        )
        .highPriorityGesture(
            MagnificationGesture()
                .onChanged { scale in
                    suppressMovementDuringMapPinch()
                    if scale >= 1.12 {
                        let wasExpanded = isMapExpanded
                        withAnimation(.spring(response: 0.32)) { isMapExpanded = true }
                        if !wasExpanded { game.recordTutorialMapZoom() }
                    }
                }
        )
        .contentShape(Rectangle())
        .simultaneousGesture(movementFlickGesture)
        .overlay {
            // チュートリアルのステップ4だけ、2本指で広げる動きを指のアニメーションで示す。
            if game.stage.isStepByStepTutorial,
               game.state.tutorialStep == .zoomMap,
               !isMapExpanded {
                PinchOutHintView()
                    .transition(.opacity)
            }
        }
    }

    /// iPadの戦闘中に、ダンジョン画面の下端へ重ねる操作ボタン。
    /// 画面下端のボタンは親指が届きにくいため、視線の先の戦闘画面に置く。
    private var iPadBattleCommandBar: some View {
        HStack(spacing: 8) {
            iPadBattleButton(title: "こうげき", isDisabled: isBattleActionLocked || game.state.isGameOver) {
                performBattleAttack()
            }
            iPadBattleButton(title: "にげる", isDisabled: isBattleActionLocked || game.state.isGameOver) {
                performBattleFlee()
            }
            iPadBattleButton(title: "ギブアップ", isDisabled: false) {
                isConfirmingGiveUp = true   // まず確認を表示する
            }
        }
    }

    private func iPadBattleButton(title: String, isDisabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(DungeonTypography.maruMonica(size: 17))
                .frame(maxWidth: .infinity, minHeight: 58)
        }
        .buttonStyle(DungeonPressButtonStyle())
        .disabled(isDisabled)
    }

    private var keyText: String {
        if !game.state.requiresKey { return "不要" }
        return game.state.hasKey ? "所持" : "未取得"
    }

    private var statusAccessibilityLabel: String {
        "\(game.stage.title)\(game.stage.seed.map { "。seed \($0)" } ?? "")。\(game.stage.requiresSwordForKey ? "剣：\(game.state.hasSword ? "所持" : "未所持")。" : "")鍵：\(keyText)"
    }

    /// ステージ名(とシード値)。iPadでは中央列の最上段に置く。
    private var stageTitleLabel: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(game.stage.title)
                .font(DungeonTypography.maruMonica(size: IPadLayoutMetrics.isPad ? 17 : 13))
                .foregroundColor(Color(red: 0.88, green: 0.84, blue: 0.73))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let seed = game.stage.seed {
                Text("SEED \(String(format: "%016llX", seed))")
                    .font(DungeonTypography.maruMonica(size: IPadLayoutMetrics.isPad ? 11 : 9))
                    .foregroundColor(.white.opacity(0.6))
                    .accessibilityLabel("seed \(seed)")
            }
        }
    }

    /// 剣・鍵の所持状況。iPadでは右列の最上段に置く。
    private var keyStatusLabel: some View {
        let isPad = IPadLayoutMetrics.isPad
        return HStack(spacing: 5) {
            if game.stage.requiresSwordForKey {
                Text("⚔")
                    .font(DungeonTypography.maruMonica(size: isPad ? 17 : 14))
                    .foregroundStyle(game.state.hasSword ? Color(red: 1.0, green: 0.79, blue: 0.25) : .white.opacity(0.35))
                Text(game.state.hasSword ? "剣：所持" : "剣：未所持")
                    .font(DungeonTypography.maruMonica(size: isPad ? 13 : 10))
                    .foregroundStyle(game.state.hasSword ? Color(red: 1.0, green: 0.79, blue: 0.25) : .white.opacity(0.68))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Image("key")
                .resizable()
                .scaledToFit()
                .frame(width: isPad ? 24 : 19, height: isPad ? 24 : 19)
                .opacity(game.state.hasKey ? 1 : 0.34)

            Text("鍵：\(keyText)")
                .font(DungeonTypography.maruMonica(size: isPad ? 17 : 13))
                .foregroundColor(
                    game.state.hasKey
                        ? Color(red: 1.0, green: 0.83, blue: 0.36)
                        : Color.white.opacity(0.84)
                )
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }

    /// iPhone用: ステージ名と鍵の状態を1行にまとめた欄。
    private var statusBar: some View {
        HStack(spacing: 8) {
            stageTitleLabel

            Spacer(minLength: 8)

            keyStatusLabel
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 34)
        .dungeonPanel(cornerRadius: 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(statusAccessibilityLabel)
    }

    private func commandView(style: CommandView.Style) -> some View {
        CommandView(
            onTurnLeft: game.turnLeft,
            onForward: game.moveForward,
            onTurnRight: game.turnRight,
            onTurnAround: game.turnAround,
            activeFlickDirection: $activeFlickDirection,
            onFlickEnded: { finishFlick(in: $0) },
            onGiveUp: { isConfirmingGiveUp = true },   // まず確認を表示する
            isBattling: game.state.enemyBattle != nil,
            isMovementDisabled: !isInputEnabled || isAcquisitionAnimationActive || game.isInputLocked || game.state.isGameOver,
            isBattleActionDisabled: isBattleActionLocked || game.state.isGameOver,
            onBattleAttack: performBattleAttack,
            onBattleFlee: performBattleFlee,
            timerStartedAt: timerStartedAt,
            timerReductionSeconds: game.state.runTimeReductionSeconds,
            style: style
        )
    }
}

/// 戦闘時のフラッシュに使う、不規則な尖りを持つ衝撃波。
private struct BattleShockwaveShape: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radii: [CGFloat] = [
            0.48, 0.36, 0.49, 0.39, 0.44, 0.33, 0.50, 0.38,
            0.46, 0.35, 0.49, 0.40, 0.43, 0.34, 0.50, 0.37,
            0.47, 0.35, 0.49, 0.39, 0.44, 0.32, 0.50, 0.38,
            0.45, 0.34, 0.49, 0.40, 0.43, 0.33, 0.50, 0.37
        ]
        var path = Path()

        for index in radii.indices {
            let angle = CGFloat(index) * 2 * .pi / CGFloat(radii.count) - .pi / 2
            let radius = radii[index]
            let point = CGPoint(
                x: center.x + cos(angle) * rect.width * radius,
                y: center.y + sin(angle) * rect.height * radius
            )
            if index == radii.startIndex {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}

/// ドロップアイテムをMaruMonicaに合う小さなドット絵で表示する。
private struct PixelDropItemIcon: View {
    let item: SkeletonDropItem

    private var rows: [String] {
        switch item {
        case .shiritoriTime:
            [
                "..oooooooo..",
                ".oyyyyyyyyyo.",
                ".oywwwwwwyyo.",
                "..oywwwwyo..",
                "...oyyyyyo...",
                "....oyyyo....",
                ".....oyo.....",
                ".....oo......",
                ".....oo......",
                "....osso.....",
                "...osssso....",
                "..oyssssyo...",
                ".oyssssssyo..",
                ".oyyyyyyyyyo.",
                "..oooooooo.."
            ]
        case .runTimeReduction:
            [
                "..oooooooo....>>",
                ".obbbbbbbbbo..>>>",
                ".obccccccbcbo.>>>",
                "..obccccbcbo..>>",
                "...obbbbbbo...>>",
                "....obbbbo....>>",
                ".....obo......>>",
                ".....oo.......>>",
                ".....oo.......>>",
                "....obbo......>>",
                "...obssbo.....>>",
                "..obssssbo....>>",
                ".obbbbbbbbbo..>>",
                "..oooooooo....>>"
            ]
        case .bandage:
            [
                "....oooooooo....",
                "..oottttttttoo..",
                ".otttthhthhhhtto.",
                "otttthhrrhhhtttto",
                "otttthhrrhhhtttto",
                "ottttrrrrrtttttto",
                "otttthhrrhhhtttto",
                "otttthhrrhhhtttto",
                ".otttthhthhhhtto.",
                "..oottttttttoo..",
                "....oooooooo...."
            ]
        }
    }

    private func color(for pixel: Character) -> Color? {
        switch pixel {
        case "o": Color(red: 0.16, green: 0.08, blue: 0.12)
        case "y": Color(red: 1.0, green: 0.83, blue: 0.35)
        case "s": Color(red: 0.74, green: 0.42, blue: 0.16)
        case "w": Color(red: 1.0, green: 0.93, blue: 0.67)
        case "b": Color(red: 0.20, green: 0.52, blue: 0.88)
        case "c": Color(red: 0.64, green: 0.86, blue: 1.0)
        case "p": Color(red: 0.94, green: 0.51, blue: 0.57)
        case "t": Color(red: 1.0, green: 0.90, blue: 0.68)
        case "h": Color(red: 0.55, green: 0.37, blue: 0.28)
        case "r": Color(red: 0.84, green: 0.16, blue: 0.20)
        case ">": Color(red: 1.0, green: 0.82, blue: 0.35)
        default: nil
        }
    }

    var body: some View {
        Canvas { context, size in
            let pixelRows = rows.map(Array.init)
            let columnCount = pixelRows.map(\.count).max() ?? 1
            let pixelSize = min(size.width / CGFloat(columnCount), size.height / CGFloat(pixelRows.count))
            let left = (size.width - CGFloat(columnCount) * pixelSize) / 2
            let top = (size.height - CGFloat(pixelRows.count) * pixelSize) / 2

            for (rowIndex, row) in pixelRows.enumerated() {
                let rowOffset = CGFloat(columnCount - row.count) / 2
                for (columnIndex, pixel) in row.enumerated() {
                    guard let pixelColor = color(for: pixel) else { continue }
                    let rect = CGRect(
                        x: left + (rowOffset + CGFloat(columnIndex)) * pixelSize,
                        y: top + CGFloat(rowIndex) * pixelSize,
                        width: pixelSize,
                        height: pixelSize
                    )
                    context.fill(Path(rect), with: .color(pixelColor))
                }
            }
        }
        .accessibilityHidden(true)
    }
}
