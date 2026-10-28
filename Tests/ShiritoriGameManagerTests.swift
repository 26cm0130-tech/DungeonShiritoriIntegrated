import Foundation

/// 実際のShiritoriGameManagerで、開始・カード選択・判定・時間切れ・CPUの取得を検証する。
/// CPUのスキャン演出はタイマー駆動のため待たず、DEBUG専用の入口で状態を直接指定する（-D DEBUGでコンパイル）。
/// 音声・触覚だけをスタブにし、各テストは進行中のタイマーが発火する前に同期で完了する。
@MainActor
enum ShiritoriGameManagerTests {
    private static var count = 0

    static func run() throws -> Int {
        try testStartGame()
        try testSelectCard()
        try testPlayerSuccess()
        try testPlayerConnectionFailureAndTimeout()
        try testPlayerLosesByN()
        try testConfirmGuards()
        try testCPUTurn()
        try testStageDifferences()
        try testRandomStageSelection()
        print("PASS: ShiritoriGameManagerの開始・選択・判定・時間切れ・CPU取得 (\(count) assertions)")
        return count
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        count += 1
        if !condition() { throw Failure(message: message) }
    }

    private struct Failure: Error, CustomStringConvertible {
        let message: String
        var description: String { "ShiritoriGameManagerテスト失敗: \(message)" }
    }

    // MARK: - 準備

    private static func vocab(_ word: String, _ type: WordType = .normal) -> Vocabulary {
        Vocabulary(word: word, displayWord: word, type: type)
    }

    private static func card(_ vocabularies: [Vocabulary]) -> Card {
        Card(id: UUID(), imageName: "test", vocabularies: vocabularies, isCleared: false)
    }

    /// 導入会話を待つ設定で開始し、3秒のスキャン開始タイマーを作らない。
    private static func started(
        _ cards: [Card],
        stage: ShiritoriStageType = .normal,
        isRandomStage: Bool = false,
        bonus: Int = 0
    ) -> ShiritoriGameManager {
        let manager = ShiritoriGameManager(
            cards: cards,
            stage: stage,
            isRandomStage: isRandomStage,
            initialPlayerTimeBonusSeconds: bonus
        )
        manager.startGame(waitForOpeningDialogue: true)
        return manager
    }

    private static func enterPlayerTurn(_ manager: ShiritoriGameManager, prompt: Character?) {
        manager.prepareStateForTesting(gameState: .playerTurn, turn: .player, currentPrompt: prompt)
    }

    /// 同じカードを2回タップして確定し、判定まで進める。
    private static func play(_ manager: ShiritoriGameManager, _ target: Card) {
        manager.selectCard(id: target.id)
        manager.selectCard(id: target.id)
        manager.confirmSelectedCard()
    }

    private static func runCPUTurn(_ manager: ShiritoriGameManager, prompt: Character?) {
        manager.prepareStateForTesting(gameState: .cpuTurn, turn: .cpu, currentPrompt: prompt)
        manager.runCPUTurnWithoutScanForTesting()
    }

    private static func isCleared(_ manager: ShiritoriGameManager, _ target: Card) -> Bool {
        manager.cards.first { $0.id == target.id }?.isCleared == true
    }

    // MARK: - 開始

    private static func testStartGame() throws {
        let deck = [card([vocab("あめ")]), card([vocab("めだか")]), card([vocab("かさ")])]
        let manager = started(deck)
        try expect(manager.gameState == .cpuReaction && manager.turn == .cpu, "開始直後はCPU先攻")
        try expect(manager.cards.count == 3 && manager.cards.allSatisfy { !$0.isCleared }, "全カードが未取得で配置される")
        try expect(Set(manager.cards.map(\.id)) == Set(deck.map(\.id)), "配置されるのは渡したカード")
        try expect(
            manager.playerTime == 90 && manager.currentMessage == nil
                && manager.gameResult == nil && manager.currentPrompt == nil,
            "持ち時間90秒・要求文字なし・結果なし"
        )
        try expect(manager.cpuTargetVocabulary?.type == .normal, "通常版のCPU先攻は通常読みを選ぶ")
        try expect(deck.contains { $0.id == manager.cpuTargetCardID }, "CPUの対象は盤面のカード")

        try expect(started(deck, bonus: 30).playerTime == 120, "持ち時間ボーナスを加算")
        try expect(started(deck, bonus: -30).playerTime == 90, "負のボーナスは0として扱う")
        try expect(!manager.isTrialStage && ShiritoriGameManager(cards: deck, stage: .trial).isTrialStage, "試練ステージの判定")

        // プレイヤーのターンでない間の操作は無視される。
        manager.selectCard(id: deck[0].id)
        manager.confirmSelectedCard()
        manager.decreasePlayerTime(by: 10)
        try expect(
            manager.selectedCardID == nil && manager.playerTime == 90 && manager.gameState == .cpuReaction,
            "CPUターン中のタップ・確定・時間減少は無視"
        )

        // 勝利後に開始し直すと、状態が初期化される。
        let only = card([vocab("あめ")])
        let finished = started([only])
        enterPlayerTurn(finished, prompt: "あ")
        play(finished, only)
        try expect(finished.gameResult == .playerWinAllCards, "全取得で勝利")
        finished.startGame(waitForOpeningDialogue: true)
        try expect(
            finished.gameState == .cpuReaction && finished.gameResult == nil
                && finished.currentPrompt == nil && !isCleared(finished, only),
            "開始し直すと勝敗・要求文字・取得状態が初期化される"
        )
    }

    // MARK: - カード選択

    private static func testSelectCard() throws {
        let first = card([vocab("あめ")])
        let second = card([vocab("あさ")])
        let manager = started([first, second, card([vocab("いぬ")])])
        enterPlayerTurn(manager, prompt: "あ")

        manager.selectCard(id: first.id)
        try expect(manager.selectedCardID == first.id && manager.confirmedCardID == nil, "1回目のタップは選択だけ")
        manager.selectCard(id: second.id)
        try expect(manager.selectedCardID == second.id && manager.confirmedCardID == nil, "別カードへ選択が移る")
        manager.selectCard(id: second.id)
        try expect(manager.selectedCardID == second.id && manager.confirmedCardID == second.id, "同じカードの2回目で確定")
        manager.selectCard(id: first.id)
        try expect(manager.selectedCardID == first.id && manager.confirmedCardID == nil, "別カードへ移ると確定を解除")
        manager.selectCard(id: UUID())
        try expect(manager.selectedCardID == first.id, "存在しないIDは無視")
    }

    // MARK: - プレイヤーの成功

    private static func testPlayerSuccess() throws {
        let first = card([vocab("あめ")])
        let second = card([vocab("めだか")])
        let third = card([vocab("かさ")])
        let manager = started([first, second, third])
        enterPlayerTurn(manager, prompt: "あ")
        manager.decreasePlayerTime(by: 2)
        play(manager, first)

        try expect(isCleared(manager, first) && manager.cards.filter(\.isCleared).count == 1, "接続できたカードだけ取得")
        try expect(manager.currentPrompt == "め", "次の要求文字は取得した読みの末尾")
        try expect(manager.playerTime == 93, "88秒から5秒回復して93秒になる（90秒上限なし）")
        try expect(manager.gameState == .cpuReaction && manager.gameResult == nil, "成功後はCPUのターンへ")
        try expect(manager.selectedCardID == nil && manager.confirmedCardID == nil, "選択状態は解除される")
        try expect(manager.cpuTargetCardID == nil, "CPUの対象は取得後に初期化")
        try expect(manager.currentMessage?.contains("あめ") == true, "取得メッセージに語を含む")

        enterPlayerTurn(manager, prompt: manager.currentPrompt)
        manager.selectCard(id: first.id)
        try expect(manager.selectedCardID == nil, "取得済みカードは選べない")

        // 回復は5秒で、上限に達していなければそのまま加算される。
        let c1 = card([vocab("あめ")])
        let recovering = started([c1, card([vocab("めだか")])])
        enterPlayerTurn(recovering, prompt: "あ")
        recovering.decreasePlayerTime(by: 20)
        play(recovering, c1)
        try expect(recovering.playerTime == 75, "70秒から5秒回復")

        // 90秒を超えていても、成功時の5秒回復に上限を設けない。
        let overCapCard = card([vocab("あめ")])
        let overCap = started([overCapCard, card([vocab("めだか")])], bonus: 20)
        enterPlayerTurn(overCap, prompt: "あ")
        play(overCap, overCapCard)
        try expect(overCap.playerTime == 115, "110秒から成功で5秒回復して115秒になる")

        // 末尾の濁音は清音として次の要求文字になる。
        let x = card([vocab("かば")])
        let y = card([vocab("はな")])
        let chain = started([x, y, card([vocab("なか")])])
        enterPlayerTurn(chain, prompt: "か")
        play(chain, x)
        try expect(chain.currentPrompt == "は", "「かば」の次は「は」（濁音を清音へ）")
        enterPlayerTurn(chain, prompt: chain.currentPrompt)
        play(chain, y)
        try expect(isCleared(chain, y) && chain.currentPrompt == "な", "続けて接続できる")

        // 「ん」で終わらない読みがあれば、それを使って自滅を避ける。
        let p = card([vocab("みかん", .rare), vocab("みどり")])
        let safe = started([p, card([vocab("りす")])])
        enterPlayerTurn(safe, prompt: "み")
        play(safe, p)
        try expect(isCleared(safe, p) && safe.currentPrompt == "り" && safe.gameResult == nil, "「ん」終わりの読みを避けて取得")

        // 最後の1枚を取ると勝利。
        let last = card([vocab("あめ")])
        let win = started([last])
        enterPlayerTurn(win, prompt: "あ")
        play(win, last)
        try expect(win.gameResult == .playerWinAllCards && win.gameState == .gameOver, "全カード取得でプレイヤー勝利")
    }

    // MARK: - 接続失敗と時間切れ

    private static func testPlayerConnectionFailureAndTimeout() throws {
        let target = card([vocab("あめ")])
        let wrong = started([target, card([vocab("いぬ")]), card([vocab("うし")])])
        enterPlayerTurn(wrong, prompt: "か")
        play(wrong, target)
        try expect(!isCleared(wrong, target) && wrong.currentPrompt == "か", "接続できなければ取得も要求文字の変更もしない")
        try expect(wrong.playerTime == 85 && wrong.gameState == .playerTurn, "5秒減ってプレイヤーのターン継続")
        try expect(wrong.selectedCardID == nil && wrong.confirmedCardID == nil, "失敗で選択状態を解除")
        try expect(wrong.playerAnimationEvent?.kind == .failure, "失敗の演出を開始")

        let empty = card([])
        let noReading = started([empty, card([vocab("いぬ")])])
        enterPlayerTurn(noReading, prompt: "あ")
        play(noReading, empty)
        try expect(noReading.playerTime == 85 && !isCleared(noReading, empty), "読みがないカードは接続失敗")

        // 残り枚数が7枚以下なら、時間切れでも特別勝利。8枚以上は通常の敗北。
        let boundaries: [(remaining: Int, result: GameResult, stage: TimeoutMercyVictoryStage)] = [
            (7, .playerWinTimeoutMercy, .defeatMessage),
            (8, .playerLoseTimeout, .inactive)
        ]
        for boundary in boundaries {
            let deck = (0..<boundary.remaining).map { _ in card([vocab("あめ")]) }
            let manager = started(deck)
            enterPlayerTurn(manager, prompt: "か")
            manager.decreasePlayerTime(by: 85)
            try expect(manager.playerTime == 5 && manager.gameState == .playerTurn, "残り5秒")
            play(manager, deck[0])
            try expect(manager.playerTime == 0 && manager.gameState == .gameOver, "接続失敗で0秒になるとゲーム終了 (残り\(boundary.remaining)枚)")
            try expect(
                manager.gameResult == boundary.result && manager.timeoutMercyVictoryStage == boundary.stage,
                "残り\(boundary.remaining)枚の時間切れ結果"
            )
        }

        // 通常のタイマー経由でも同じ基準で判定する。
        let timer = started([card([vocab("あめ")]), card([vocab("いぬ")])])
        enterPlayerTurn(timer, prompt: "あ")
        timer.decreasePlayerTime(by: 0)
        timer.decreasePlayerTime(by: -5)
        try expect(timer.playerTime == 90, "0以下の減少は無視")
        timer.decreasePlayerTime(by: 89)
        try expect(timer.playerTime == 1 && timer.gameState == .playerTurn, "1秒残して継続")
        timer.decreasePlayerTime(by: 1)
        try expect(
            timer.playerTime == 0 && timer.gameState == .gameOver && timer.gameResult == .playerWinTimeoutMercy,
            "残り2枚の時間切れは特別勝利"
        )
        try expect(timer.cpuTargetCardID == nil && timer.cpuScanState.isScanning == false, "時間切れでCPU処理を残さない")

        let overflow = started([card([vocab("あめ")])])
        enterPlayerTurn(overflow, prompt: "あ")
        overflow.decreasePlayerTime(by: 1000)
        try expect(overflow.playerTime == 0, "持ち時間は負にならない")
    }

    // MARK: - 「ん」で終わる読みによる敗北

    private static func testPlayerLosesByN() throws {
        for stage in [ShiritoriStageType.normal, .trial] {
            let target = card([vocab("みかん")])
            let manager = started([target, card([vocab("いぬ")])], stage: stage)
            enterPlayerTurn(manager, prompt: "み")
            play(manager, target)
            try expect(manager.gameResult == .playerLoseN && manager.gameState == .gameOver, "「ん」で終わる読みしかなければ敗北 (\(stage))")
            try expect(manager.playerLoseNEndingStage == .recognitionMessage, "気づきのセリフから始まる (\(stage))")
            try expect(!isCleared(manager, target), "敗北したカードは取得されない (\(stage))")
            try expect(manager.currentMessage?.contains("みかん") == true, "セリフに語を含む (\(stage))")
        }
    }

    // MARK: - 確定の前提条件

    private static func testConfirmGuards() throws {
        let target = card([vocab("あめ")])
        let manager = started([target, card([vocab("いぬ")])])

        manager.confirmSelectedCard()
        try expect(!isCleared(manager, target) && manager.playerTime == 90, "プレイヤーのターン以外では確定しない")

        enterPlayerTurn(manager, prompt: "あ")
        manager.selectCard(id: target.id)
        manager.confirmSelectedCard()
        try expect(
            !isCleared(manager, target) && manager.selectedCardID == target.id && manager.gameState == .playerTurn,
            "1回タップしただけでは確定しない"
        )

        enterPlayerTurn(manager, prompt: nil)
        play(manager, target)
        try expect(
            !isCleared(manager, target) && manager.playerTime == 90
                && manager.selectedCardID == nil && manager.gameState == .playerTurn,
            "要求文字がなければ選択を解除するだけ"
        )
    }

    // MARK: - CPUのターン

    private static func testCPUTurn() throws {
        let a = card([vocab("あめ")])
        let b = card([vocab("めだか")])
        let success = started([a, b])
        runCPUTurn(success, prompt: "あ")
        try expect(isCleared(success, a) && !isCleared(success, b), "CPUは接続できるカードを取得")
        try expect(success.currentPrompt == "め" && success.cpuTargetCardID == nil, "要求文字を更新しCPUの対象を初期化")
        try expect(success.gameState == .playerTurn && success.turn == .player && success.gameResult == nil, "取得後はプレイヤーのターン")
        try expect(success.currentMessage?.contains("あめ") == true, "CPUの取得メッセージに語を含む")

        let danger = card([vocab("あん")])
        let selfDestruct = started([danger, card([vocab("いぬ")])])
        runCPUTurn(selfDestruct, prompt: "あ")
        try expect(
            selfDestruct.gameResult == .playerWinCPUN && selfDestruct.gameState == .gameOver && !isCleared(selfDestruct, danger),
            "CPUが「ん」で終わる読みしか選べなければプレイヤー勝利"
        )
        try expect(selfDestruct.currentMessage?.contains("あん") == true, "CPUの自滅セリフに語を含む")

        let lastCard = card([vocab("あめ")])
        let exhausted = started([lastCard])
        runCPUTurn(exhausted, prompt: "あ")
        try expect(
            exhausted.gameResult == .playerWinAllCards && exhausted.cpuFinalCardEndingStage == .normalCPUMessage
                && exhausted.gameState == .gameOver && exhausted.turn == .player,
            "CPUが最後のカードを取ると専用エンディングへ"
        )

        let noTarget = started([card([vocab("いぬ")])])
        runCPUTurn(noTarget, prompt: "あ")
        try expect(
            noTarget.gameResult == .playerWinNoCPUTarget && noTarget.noCPUTargetVictoryStage == .noCardsMessage
                && noTarget.gameState == .gameOver,
            "CPUが選べるカードがなければプレイヤー勝利"
        )

        let ending = started([card([vocab("あめ")])])
        ending.finishGame()
        try expect(ending.gameState == .gameOver, "finishGameでゲーム終了")
    }

    // MARK: - 通常ステージと試練ステージの違い

    private static func testStageDifferences() throws {
        // 通常は種類の優先順位 normal > english、試練は「ん」を避けたうえで英語読みを最優先する。
        let x = card([vocab("あん"), vocab("あさ", .rare)])
        let y = card([vocab("あめ", .english)])
        let z = card([vocab("あお")])

        let normalStage = started([x, y, z])
        runCPUTurn(normalStage, prompt: "あ")
        try expect(isCleared(normalStage, z) && normalStage.currentPrompt == "お", "通常ステージのCPUは通常読みを選ぶ")

        let trialStage = started([x, y, z], stage: .trial)
        runCPUTurn(trialStage, prompt: "あ")
        try expect(isCleared(trialStage, y) && trialStage.currentPrompt == "め", "試練ステージのCPUは英語読みを選ぶ")

        // 初手も同様。試練は「ん」終わりを避けて英語読みを選ぶ。
        let deck = [
            card([vocab("あん"), vocab("あっぷる", .english)]),
            card([vocab("かさ", .rare), vocab("くま")])
        ]
        try expect(started(deck, stage: .trial).cpuTargetVocabulary?.word == "あっぷる", "試練の初手は英語読み")
        try expect(started(deck).cpuTargetVocabulary?.type == .normal, "通常の初手は通常読み")
    }

    // MARK: - ランダムステージのCPU選択

    private static func testRandomStageSelection() throws {
        // ランダムの初手もチュートリアルと同じく、通常読みがないカードは選ばない。
        let rareOnly = card([vocab("あさ", .rare)])
        let initial = started([rareOnly], isRandomStage: true)
        try expect(initial.cpuTargetCardID == nil, "ランダムステージの初手は従来ロジックを使う")
        try expect(initial.cpuTargetVocabulary == nil, "ランダムステージの初手は通常読みが必要")

        // 通常ターンもチュートリアルと同じ従来ロジックで、通常読みの候補を選ぶ。
        let x = card([vocab("あん"), vocab("あさ", .rare)])
        let y = card([vocab("あめ", .english)])
        let z = card([vocab("あお")])
        let randomStage = started([x, y, z], isRandomStage: true)
        runCPUTurn(randomStage, prompt: "あ")
        try expect(
            isCleared(randomStage, z) && randomStage.currentPrompt == "お",
            "ランダムCPUはチュートリアルと同じ従来ロジックを使う"
        )
    }
}
