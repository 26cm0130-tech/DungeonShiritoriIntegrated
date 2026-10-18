import Foundation
import Combine

/// ゲーム進行の管理。UIはここを通してのみ状態を変更する(UI仕様書§8)
final class GameManager: ObservableObject {
    /// 現在の面(マップ、鍵の要否などの定義)
    let stage: Stage
    @Published private(set) var state: GameState
    @Published private(set) var isInputLocked = false
    @Published private(set) var wallCollisionID = 0
    @Published private(set) var surpriseReactionID = 0
    @Published private(set) var trapActivationID = 0
    @Published private(set) var enemyEncounterID = 0
    @Published private(set) var encounterEnemySpeech: EnemyEncounterSpeech?
    @Published private(set) var defeatedEnemySpeech: EnemyDefeatSpeech?
    @Published private(set) var pendingSkeletonDrop: SkeletonDropItem?

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
        guard !state.isCleared, !state.isGameOver, state.enemyBattle == nil, !isInputLocked else { return }
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
        guard !state.isCleared, !state.isGameOver, state.enemyBattle == nil, !isInputLocked else { return }

        if state.doubleFlickTrapActive {
            var newState = state
            if !newState.hasPendingDoubleFlick {
                newState.hasPendingDoubleFlick = true
                newState.message = "前進トラップ！\nもう一度フリックすると進める。"
                state = newState
                return
            }
            newState.hasPendingDoubleFlick = false
            state = newState
        }

        let next = state.player.position.moved(direction)
        let cell = map.cell(at: next)
        if cell.isWall {
            var newState = state
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
            soundEffects.play(named: "壁衝突音")
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
            event = nil
        } else {
            event = TileEvents.event(for: cell, map: map, position: next)
        }
        if let reason = event?.blockReason(state: state) {
            var newState = state
            newState.message = reason
            state = newState
            return
        }

        var newState = state
        newState.player.position = next
        newState.explored.insert(next)
        newState.message = ""
        newState.trapActivationMessage = nil
        newState.recordTutorialAction(action)
        if cell != .key && cell != .goal && cell != .sword {
            soundEffects.play(named: "移動音")
        }
        event?.onEnter(state: &newState, from: state.player.position)
        if newState.hpDrainTrapActive && !newState.isGameOver {
            newState.playerHP = max(0, newState.playerHP - 1)
            if newState.playerHP == 0 {
                newState.isGameOver = true
                newState.isCleared = false
                newState.message = "毒の罠でHPが0になった……"
            }
        }
        state = newState
        if let battle = newState.enemyBattle {
            showEncounterEnemySpeech(battle.kind)
            onBattleStateChanged?(battle.kind)
            enemyEncounterID += 1
        }
        if cell.isTrap {
            trapActivationID += 1
        }
        if newState.enemyBattle != nil {
            surpriseReactionID += 1
        }

        if newState.isGameOver {
            onGameOver?()
            return
        }

        // クリア状態になったら、画面を切り替えるために知らせる
        if newState.isCleared {
            onCleared?()
        }
    }

    /// プレイヤーの攻撃後、生存していれば敵が反撃する。
    func attackEnemy() {
        guard var battle = state.enemyBattle, !state.isCleared, !state.isGameOver else { return }

        let gargoyleNeedsSword = state.requiresSwordForKey
            && battle.kind == .gargoyle
            && !state.hasSword
        let playerDamage = gargoyleNeedsSword ? 0 : (state.hasSword ? 10 : 5)
        battle.enemyHP = max(0, battle.enemyHP - playerDamage)
        var newState = state

        if battle.enemyHP == 0 {
            newState.defeatedEnemies.insert(battle.enemyPosition)
            newState.enemyBattle = nil
            newState.message = "敵を倒した！探索を続けよう。"
            state = newState
            if battle.kind == .skeleton {
                pendingSkeletonDrop = SkeletonDropItem.allCases.randomElement()
            }
            soundEffects.play(named: "敵撃破")
            showDefeatedEnemySpeech(battle.kind)
            onBattleStateChanged?(nil)
            return
        }

        let enemyDamage = battle.kind.attackDamage
        newState.playerHP = max(0, newState.playerHP - enemyDamage)
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

        if gargoyleNeedsSword {
            battle.message = "剣がないと攻撃が通じない！\n反撃で\(enemyDamage)ダメージを受けた。"
        } else {
            battle.message = "攻撃！敵に\(playerDamage)ダメージ。\n反撃で\(enemyDamage)ダメージを受けた。"
        }
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

    private func showDefeatedEnemySpeech(_ kind: EnemyKind) {
        guard encounterEnemySpeech == nil else {
            pendingDefeatedEnemyKind = kind
            return
        }
        presentDefeatedEnemySpeech(kind)
    }

    private func showEncounterEnemySpeech(_ kind: EnemyKind) {
        encounterEnemySpeechTask?.cancel()
        defeatedEnemySpeechTask?.cancel()
        defeatedEnemySpeechTask = nil
        defeatedEnemySpeech = nil
        pendingDefeatedEnemyKind = nil
        encounterEnemySpeechID += 1
        let presentation = EnemyEncounterSpeech(
            id: encounterEnemySpeechID,
            kind: kind,
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
