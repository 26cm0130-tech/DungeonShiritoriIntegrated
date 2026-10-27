import Foundation
import Combine

/// ゲーム進行の管理。UIはここを通してのみ状態を変更する(UI仕様書§8)
final class GameManager: ObservableObject {
    /// 現在の面(マップ、鍵の要否などの定義)
    let stage: Stage
    @Published private(set) var state: GameState
    @Published private(set) var isInputLocked = false
    /// スケルトンの撃破からドロップ取得完了まで、移動入力を止める。
    @Published private(set) var isSkeletonDropPickupInputLocked = false
    /// 鍵・剣の取得イベントから取得演出の終了まで、移動入力を止める。
    @Published private(set) var isItemPickupInputLocked = false
    @Published private(set) var wallCollisionID = 0
    @Published private(set) var surpriseReactionID = 0
    @Published private(set) var trapActivationID = 0
    @Published private(set) var enemyEncounterID = 0
    @Published private(set) var playerDamageAnimationID = 0
    @Published private(set) var playerDamageAmount = 0
    @Published private(set) var encounterEnemySpeech: EnemyEncounterSpeech?
    @Published private(set) var defeatedEnemySpeech: EnemyDefeatSpeech?
    /// 撃破セリフの表示中に限り、大きい敗北画像を表示するための敵種。
    @Published private(set) var defeatedEnemyLargeGraphicKind: EnemyKind?
    /// 大きい敗北画像を表示している敵のマップ上の位置。
    @Published private(set) var defeatedEnemyLargeGraphicPosition: GridPos?
    @Published private(set) var pendingSkeletonDrop: SkeletonDropItem?
    /// 剣を落とす敵を倒した直後、撃破セリフが終わるまで取得を待っている状態。
    @Published private(set) var pendingSwordDrop: EnemyKind?

    private var wallCollisionTask: Task<Void, Never>?
    private var encounterEnemySpeechTask: Task<Void, Never>?
    private var defeatedEnemySpeechTask: Task<Void, Never>?
    private var encounterEnemySpeechID = 0
    private var defeatedEnemySpeechID = 0
    private var pendingDefeatedEnemyKind: EnemyKind?
    private let wallCollisionDamageEnabled: Bool
    private var wallCollisionCount = 0
    private let soundEffects = SoundEffectController()

    /// 現在の面のマップ
    var map: MapData { stage.map }

    /// クリアしたときに呼ばれる(画面の切り替えに使う)
    var onCleared: (() -> Void)?
    /// HPが0になったときに呼ばれる(スタート画面へ戻る)
    var onGameOver: (() -> Void)?
    /// 戦闘の開始・終了に合わせたBGM切替通知
    var onBattleStateChanged: ((EnemyKind?) -> Void)?

    init(stage: Stage, wallCollisionDamageEnabled: Bool = true) {
        self.stage = stage
        self.wallCollisionDamageEnabled = wallCollisionDamageEnabled
        self.state = GameState(
            start: stage.map.startPosition,
            direction: stage.map.initialDirection,
            requiresKey: stage.requiresKey,
            requiresSwordForKey: stage.requiresSwordForKey,
            isStepByStepTutorial: stage.isStepByStepTutorial
        )
    }

    deinit {
        encounterEnemySpeechTask?.cancel()
        defeatedEnemySpeechTask?.cancel()
    }

    // MARK: 操作

    func turnLeft() {
        turn(to: state.player.direction.turnedLeft, tutorialAction: .turnLeft)
    }

    func turnRight() {
        turn(to: state.player.direction.turnedRight, tutorialAction: .turnRight)
    }

    func moveForward() {
        moveOneTile(
            in: state.player.direction,
            action: .moveForward,
            blockedMessage: "前方は壁です。左右に向きを変えて進路を探そう！"
        )
    }

    func turnAround() {
        turn(to: state.player.direction.reversed)
    }

    /// チュートリアルで探索マップを拡大した操作を記録する。
    func recordTutorialMapZoom() {
        guard stage.isStepByStepTutorial else { return }
        var newState = state
        newState.recordTutorialAction(.zoomMap)
        state = newState
    }

    private func turn(to direction: Direction, tutorialAction: TutorialAction? = nil) {
        guard !state.isCleared, !state.isGameOver, state.enemyBattle == nil,
              !isInputLocked, !isSkeletonDropPickupInputLocked,
              !isItemPickupInputLocked else { return }
        var newState = state
        newState.player.direction = direction
        newState.message = ""
        if let tutorialAction {
            newState.recordTutorialAction(tutorialAction)
        }
        state = newState
    }

    /// 指定した方向へ1マス進み、壁・イベント・探索済み状態をまとめて処理する。
    private func moveOneTile(in direction: Direction, action: TutorialAction, blockedMessage: String) {
        guard !state.isCleared, !state.isGameOver, state.enemyBattle == nil,
              !isInputLocked, !isSkeletonDropPickupInputLocked,
              !isItemPickupInputLocked else { return }

        // 遅行中は設定された回数の前進フリックがそろうまで、マス移動しない。
        if action == .moveForward, state.doubleFlickTrapActive {
            var flickState = state
            flickState.slowForwardFlickProgress += 1
            let requiredFlicks = max(1, TrapEvent.slowForwardFlicksPerMove)
            if flickState.slowForwardFlickProgress < requiredFlicks {
                let remainingFlicks = requiredFlicks - flickState.slowForwardFlickProgress
                flickState.message = "足止めの罠!\nあと\(remainingFlicks)回フリックすると1マス進みます。"
                state = flickState
                return
            }
            flickState.slowForwardFlickProgress = 0
            state = flickState
        }

        let next = state.player.position.moved(direction)
        let cell = map.cell(at: next)
        if cell.isWall {
            var newState = state
            // 壁への衝突は連続前進を中断する。
            newState.consecutiveSafeForwardSteps = 0
            var isGameOverFromWallDamage = false
            if wallCollisionDamageEnabled {
                wallCollisionCount += 1
                if wallCollisionCount.isMultiple(of: 3) {
                    newState.playerHP = max(0, newState.playerHP - 3)
                    if newState.playerHP == 0 {
                        newState.isGameOver = true
                        newState.message = "壁に3回ぶつかった！\nHPが3減り、力尽きた……"
                        isGameOverFromWallDamage = true
                    } else {
                        newState.message = "壁に3回ぶつかった！\nHPが3減った。\n2秒間は動けません。"
                    }
                } else {
                    let remainingHits = 3 - wallCollisionCount % 3
                    newState.message = "\(blockedMessage)\nあと\(remainingHits)回でHPが3減ります。\n2秒間は動けません。"
                }
            } else {
                newState.message = "\(blockedMessage)\n2秒間は動けません。"
            }
            state = newState
            wallCollisionID += 1
            surpriseReactionID += 1
            soundEffects.play(.wallCollision)
            if isGameOverFromWallDamage {
                onGameOver?()
            } else {
                lockInputAfterWallCollision()
            }
            return
        }

        // 敵を倒したマスへ戻った場合は、再戦せず通過できる。
        let event: (any TileEvent)?
        if cell == .enemy && !state.defeatedEnemies.contains(next) {
            let kind = map.enemyKinds[next] ?? EnemyKind.encounter(seed: stage.seed, position: next)
            event = EnemyEvent(kind: kind)
        } else if cell == .enemy {
            // 倒したスライムの死体は、踏むたびに「1歩ごとにHPが減る」罠(毒)として働く。
            // 探索マップ・ダンジョン画面での死体の表示は変えない(罠の発見済み表示にも加えない)。
            // ほかの敵の死体は、これまでどおり通過するだけ。
            if state.defeatedEnemyKinds[next] == .slime {
                event = TrapEvent(kind: .hpDrain, map: map)
            } else {
                event = nil
            }
        } else {
            event = TileEvents.event(for: cell, map: map, position: next)
        }
        if let reason = event?.blockReason(state: state) {
            var newState = state
            // イベントにより進行できなかった場合も、連続前進を中断する。
            newState.consecutiveSafeForwardSteps = 0
            newState.message = reason
            state = newState
            return
        }

        let hpDrainWasActive = state.hpDrainTrapActive
        let slowWasActive = action == .moveForward && state.doubleFlickTrapActive
        var newState = state
        newState.player.position = next
        newState.mapStepCount += 1
        // 実際に1マス移動した時点で、大きい敗北画像を解除する。
        defeatedEnemyLargeGraphicKind = nil
        defeatedEnemyLargeGraphicPosition = nil
        newState.explored.insert(next)
        if cell.isTrap {
            newState.activatedTrapPositions.insert(next)
        }
        newState.message = ""
        newState.trapActivationMessage = nil
        newState.recordTutorialAction(action)
        if cell != .key && cell != .goal && cell != .sword {
            soundEffects.play(.movement)
        }
        if slowWasActive {
            newState.doubleFlickTrapMovesRemaining = max(0, newState.doubleFlickTrapMovesRemaining - 1)
            if newState.doubleFlickTrapMovesRemaining == 0 {
                newState.doubleFlickTrapActive = false
                newState.slowForwardFlickProgress = 0
            }
        }
        event?.onEnter(state: &newState, from: state.player.position)
        // グループAの罠を踏んだ時の効果音(罠マス・スライムの死体のどちらも同じ)
        let activatedTrap = event as? TrapEvent
        if let activatedTrap {
            playGroupATrapSound(for: activatedTrap.kind)
        }
        // スライムの死体が原因の毒は、罠マスと区別できるメッセージにする(Trap.swiftは変更しない)。
        if cell == .enemy, activatedTrap != nil {
            let message = "スライムの死体にふれた！ 1歩ごとにHPが\(max(0, TrapEvent.poisonDamagePerStep))減る。\(max(1, TrapEvent.poisonDurationSteps))歩で解除"
            newState.message = message
            newState.trapActivationMessage = message
        }
        if newState.hpDrainTrapActive && !newState.isGameOver {
            let poisonDamage = max(0, TrapEvent.poisonDamagePerStep)
            newState.playerHP = max(0, newState.playerHP - poisonDamage)
            if hpDrainWasActive {
                let hpDrainMessage = "トラップの影響でHPが\(poisonDamage)減った。"
                if newState.message.isEmpty {
                    newState.message = hpDrainMessage
                } else {
                    newState.message += "\n\(hpDrainMessage)"
                }
            } else {
                newState.message += "\n1歩進んだためHPが\(poisonDamage)減った。"
            }
            newState.hpDrainTrapStepsRemaining = max(0, newState.hpDrainTrapStepsRemaining - 1)
            if newState.hpDrainTrapStepsRemaining == 0 {
                newState.hpDrainTrapActive = false
            }
            if newState.playerHP == 0 {
                newState.isCleared = false
                newState.isGameOver = true
                newState.enemyBattle = nil
                newState.message = "トラップの影響でHPが0になり、力尽きた……"
            }
        }
        // 何事もなく前進した場合だけ連続歩数を数える。旋回は別処理なのでカウントを維持する。
        let isUneventfulForwardStep = action == .moveForward
            && event == nil
            && !cell.isTrap
            && cell != .key
            && cell != .goal
            && cell != .sword
            && cell != .enemy
            && newState.message.isEmpty
            && !hpDrainWasActive
            && !newState.hpDrainTrapActive
            && !newState.isGameOver

        if isUneventfulForwardStep {
            newState.consecutiveSafeForwardSteps += 1
            if newState.consecutiveSafeForwardSteps >= 5 {
                newState.consecutiveSafeForwardSteps = 0
                if newState.playerHP < GameState.playerMaxHP {
                    newState.playerHP += 1
                    newState.message = "５歩歩いたので、HPが１回復した"
                }
            }
        } else {
            // 罠・敵・アイテムなどのイベントが起きた歩行では、HPを回復せず連続数をリセットする。
            newState.consecutiveSafeForwardSteps = 0
        }

        // UI側のonChangeが動く前から移動を止め、取得演出の開始漏れを防ぐ。
        let acquiredKey = !state.hasKey && newState.hasKey
        let acquiredSword = !state.hasSword && newState.hasSword
        if acquiredKey || acquiredSword {
            isItemPickupInputLocked = true
        }
        state = newState
        if let battle = newState.enemyBattle {
            showEncounterEnemySpeech(battle.kind, at: battle.enemyPosition)
            onBattleStateChanged?(battle.kind)
            enemyEncounterID += 1
        }
        // 罠マスと、罠として働くスライムの死体のどちらも、罠の発動演出を出す。
        if cell.isTrap || activatedTrap != nil {
            trapActivationID += 1
        }
        if newState.isGameOver {
            onGameOver?()
            return
        }
        if newState.enemyBattle != nil {
            surpriseReactionID += 1
        }

        // クリア状態になったら、画面を切り替えるために知らせる
        if newState.isCleared {
            onCleared?()
        }
    }

    /// グループAの罠(A1 向きの変化・A2 前進フリック入力・A3 1歩ごとのHP減少)を踏んだ時の効果音。
    /// グループB・Cの罠は、今のところ専用の効果音を持たない。
    private func playGroupATrapSound(for kind: TrapKind) {
        switch kind {
        case .turnRight: soundEffects.play(.trapTurn)
        case .doubleFlick: soundEffects.play(.trapSlowFlick)
        case .hpDrain: soundEffects.play(.trapPoison)
        default: break
        }
    }

    /// プレイヤーの攻撃ダメージだけを先に適用し、反撃は演出後に別処理で行う。
    func attackEnemy() {
        guard var battle = state.enemyBattle, !state.isCleared, !state.isGameOver else { return }

        let gargoyleNeedsSword = state.requiresSwordForKey
            && battle.kind == .gargoyle
            && !state.hasSword
        let playerDamage = gargoyleNeedsSword ? 0 : (state.hasSword ? 10 : 5)
        battle.enemyHP = max(0, battle.enemyHP - playerDamage)
        var newState = state

        if battle.enemyHP == 0 {
            newState.enemyHPByPosition.removeValue(forKey: battle.enemyPosition)
            newState.defeatedEnemies.insert(battle.enemyPosition)
            newState.defeatedEnemyKinds[battle.enemyPosition] = battle.kind
            defeatedEnemyLargeGraphicKind = battle.kind
            defeatedEnemyLargeGraphicPosition = battle.enemyPosition
            newState.enemyBattle = nil
            newState.message = "敵を倒した！探索を続けよう。"
            if battle.kind == .skeleton,
               let drop = SkeletonDropItem.allCases.randomElement() {
                pendingSkeletonDrop = drop
                isSkeletonDropPickupInputLocked = true
            }
            if battle.kind.dropsSword && !newState.hasSword {
                // 撃破セリフと倒れる動作が終わってから剣を取得させる。それまで移動は止める。
                pendingSwordDrop = battle.kind
                isSkeletonDropPickupInputLocked = true
            }
            state = newState
            soundEffects.play(.enemyDefeat)
            showDefeatedEnemySpeech(battle.kind)
            onBattleStateChanged?(nil)
            return
        }

        battle.message = gargoyleNeedsSword
            ? "剣がないと攻撃が通じない！"
            : "攻撃！敵に\(playerDamage)ダメージ。"
        newState.enemyHPByPosition[battle.enemyPosition] = battle.enemyHP
        newState.enemyBattle = battle
        state = newState
    }

    /// 敵の攻撃モーション後に反撃ダメージを適用する。
    func counterattackEnemy() {
        guard var battle = state.enemyBattle, !state.isCleared, !state.isGameOver else { return }

        let enemyDamage = battle.kind.attackDamage
        var newState = state
        newState.playerHP = max(0, newState.playerHP - enemyDamage)
        playerDamageAmount = enemyDamage
        playerDamageAnimationID += 1

        if newState.playerHP == 0 {
            battle.message = "力尽きた……"
            newState.enemyBattle = battle
            newState.isGameOver = true
            newState.message = "力尽きた……"
            state = newState
            onBattleStateChanged?(nil)
            onGameOver?()
            return
        }

        battle.message = "\(battle.kind.name)の\(battle.kind.counterattackName)！\n\(enemyDamage)ダメージを受けた。"
        newState.enemyBattle = battle
        state = newState
    }

    /// 逃走した場合は、敵マスへ入る直前の位置に戻る。敵はその場に残る。
    func fleeBattle() {
        guard let battle = state.enemyBattle else { return }
        encounterEnemySpeechTask?.cancel()
        encounterEnemySpeechTask = nil
        encounterEnemySpeech = nil
        var newState = state
        if battle.enemyHP < battle.kind.maxHP {
            newState.enemyHPByPosition[battle.enemyPosition] = battle.enemyHP
        } else {
            newState.enemyHPByPosition.removeValue(forKey: battle.enemyPosition)
        }
        newState.player.position = battle.retreatPosition
        newState.enemyBattle = nil
        newState.message = "戦闘から逃げ出した。"
        state = newState
        onBattleStateChanged?(nil)
    }

    /// 撃破セリフの表示後に、ドロップアイテムの効果を適用する。
    func collectPendingSkeletonDrop() {
        guard let item = pendingSkeletonDrop else { return }
        var newState = state
        switch item {
        case .shiritoriTime:
            newState.shiritoriTimeBonusSeconds += 5
            newState.message = "砂時計を手に入れた！\nしりとりの持ち時間が5秒増えた。"
        case .runTimeReduction:
            newState.runTimeReductionSeconds += 10
            newState.message = "時短の砂時計を手に入れた！\n今回のクリアタイムが\n10秒短縮された。"
        case .bandage:
            let recovered = min(5, GameState.playerMaxHP - newState.playerHP)
            newState.playerHP += recovered
            newState.message = recovered > 0
                ? "絆創膏を手に入れた！\nHPが\(recovered)回復。"
                : "絆創膏を手に入れた！\nHPは満タンだ。"
        }
        state = newState
        pendingSkeletonDrop = nil
    }

    /// 撃破セリフの後に、敵が落とした剣を取得する。取得演出はhasSwordの変化で始まる。
    func collectPendingSwordDrop() {
        guard let kind = pendingSwordDrop else { return }
        pendingSwordDrop = nil
        isSkeletonDropPickupInputLocked = pendingSkeletonDrop != nil
        guard !state.hasSword else { return }
        var newState = state
        newState.hasSword = true
        newState.message = "\(kind.name)が剣を落とした！攻撃力が上がった！"
        isItemPickupInputLocked = true
        state = newState
    }

    /// ドロップの効果適用後に、撃破時から保持していた移動ロックを解除する。
    func finishSkeletonDropPickupPresentation() {
        guard pendingSkeletonDrop == nil else { return }
        isSkeletonDropPickupInputLocked = false
    }

    /// 鍵・剣の取得演出を閉じ終えた後に移動ロックを解除する。
    func finishItemPickupPresentation() {
        isItemPickupInputLocked = false
    }

    /// プレイ画面を離れる場合は、取得演出に対応する移動ロックを破棄する。
    func cancelItemPickupPresentation() {
        isItemPickupInputLocked = false
    }

    /// プレイ画面を離れる場合は、未回収ドロップと対応する入力ロックを破棄する。
    func cancelSkeletonDropPickupPresentation() {
        pendingSkeletonDrop = nil
        pendingSwordDrop = nil
        isSkeletonDropPickupInputLocked = false
    }

    private func showDefeatedEnemySpeech(_ kind: EnemyKind) {
        guard encounterEnemySpeech == nil else {
            pendingDefeatedEnemyKind = kind
            return
        }
        presentDefeatedEnemySpeech(kind)
    }

    private func showEncounterEnemySpeech(_ kind: EnemyKind, at position: GridPos) {
        encounterEnemySpeechTask?.cancel()
        defeatedEnemySpeechTask?.cancel()
        defeatedEnemySpeechTask = nil
        defeatedEnemySpeech = nil
        defeatedEnemyLargeGraphicKind = nil
        defeatedEnemyLargeGraphicPosition = nil
        pendingDefeatedEnemyKind = nil
        encounterEnemySpeechID += 1
        let presentation = EnemyEncounterSpeech(
            id: encounterEnemySpeechID,
            kind: kind,
            position: position,
            message: kind.encounterDialogue(isTrialStage: stage.shiritoriStageKind == .trial)
        )
        encounterEnemySpeech = presentation
        encounterEnemySpeechTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled, let self,
                  self.encounterEnemySpeech?.id == presentation.id else { return }
            self.encounterEnemySpeech = nil
            self.encounterEnemySpeechTask = nil
            if let defeatedKind = self.pendingDefeatedEnemyKind {
                self.pendingDefeatedEnemyKind = nil
                self.presentDefeatedEnemySpeech(defeatedKind)
            }
        }
    }

    private func presentDefeatedEnemySpeech(_ kind: EnemyKind) {
        defeatedEnemySpeechTask?.cancel()
        defeatedEnemySpeechID += 1
        let presentation = EnemyDefeatSpeech(
            id: defeatedEnemySpeechID,
            kind: kind,
            message: kind.defeatDialogue(isTrialStage: stage.shiritoriStageKind == .trial)
        )
        defeatedEnemySpeech = presentation
        defeatedEnemySpeechTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled, let self,
                  self.defeatedEnemySpeech?.id == presentation.id else { return }
            self.defeatedEnemySpeech = nil
            self.defeatedEnemyLargeGraphicKind = nil
            self.defeatedEnemyLargeGraphicPosition = nil
            self.defeatedEnemySpeechTask = nil
        }
    }

    /// 壁にぶつかった後、移動と方向転換を2秒間受け付けない。
    private func lockInputAfterWallCollision() {
        wallCollisionTask?.cancel()
        isInputLocked = true
        wallCollisionTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled, let self else { return }
            self.isInputLocked = false

            var newState = self.state
            newState.message = ""
            self.state = newState
            self.wallCollisionTask = nil
        }
    }
}
