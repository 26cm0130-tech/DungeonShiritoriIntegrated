//
//  ShiritoriGameView.swift
//  shiritori
//
//  Phase18-2：CPU・PLAYERキャラクター表示
//  Phase21：キャラクター拡大・画面レイアウト再配置
//

import SwiftUI

// ゲーム画面全体を担当する
struct ShiritoriGameView: View {

    /// 勝敗と最終演出が確定したあと、統合アプリへ結果を通知する。
    let onGameFinished: (Bool) -> Void

    /// 試練ステージだけCPU2専用画像・演出を使用する。
    private let isTrialStage: Bool

    /// ランダムステージだけCPU3専用画像・演出を使用する。
    private let isRandomStage: Bool

    // ゲーム進行を管理する
    @State private var gameManager: ShiritoriGameManager

    /// 通常版・試練版でカードデータを差し替えられるようにする。
    private let stage: ShiritoriStageType

    init(
        cards: [Card] = CardData.cards,
        stage: ShiritoriStageType = .normal,
        isRandomStage: Bool = false,
        initialPlayerTimeBonusSeconds: Int = 0,
        playerTimePenaltySeconds: Int = 0,
        playerTimeHPBonusSeconds: Int = 0,
        onGameFinished: @escaping (Bool) -> Void
    ) {
        self.onGameFinished = onGameFinished
        self.isTrialStage = stage == .trial
        self.isRandomStage = isRandomStage && stage != .trial
        self.stage = stage
        _gameManager = State(initialValue: ShiritoriGameManager(
            cards: cards,
            stage: stage,
            isRandomStage: isRandomStage && stage != .trial,
            initialPlayerTimeBonusSeconds: initialPlayerTimeBonusSeconds,
            playerTimePenaltySeconds: playerTimePenaltySeconds,
            playerTimeHPBonusSeconds: playerTimeHPBonusSeconds
        ))
    }

    // 結果通知と遷移タイマーの重複を防ぐ
    @State private var hasScheduledGameFinish = false
    @State private var finishTransitionTimer: Timer?

    // ゲーム開始済みかどうか
    @State private var hasStarted = false

    // プロローグ直後のCPU導入会話を表示しているか
    @State private var isShowingOpeningDialogue = true

    // 導入会話の現在位置（0から2まで）
    @State private var openingDialogueIndex = 0

    // PLAYER敗北用BGMが同じ対局内で重複再生されないようにする
    @State private var defeatBGMPlayed = false

    // プロローグ直後にCPUが表示する3段階の導入メッセージ
    private var openingDialogueMessages: [String] {
        if stage == .trial {
            return [
                "ほっほっほ・・・おみごとザンス。\nよく ミーのところまで たどりつけたと\nほめてあげたいところザマス。",
                "では、おフランスりゅうがく がえりの\nこの ミーが きょうようというものを\nたたきこんでやるザマス。よごザンスね！？",
                "What's gathered? Run!\nワギャラン"
            ]
        }
        if isRandomStage {
            return [
                "カモがネギしょってやってきたぜェグヘヘヘヘヘ…\nバキッバキッ",
                "我が名は姫龍。いつしか\"怪物を超えた怪物”と\n呼ばれるようになった。それがアタイさ。\nジャッジOK！？アーユーレディ・・・",
                "What's gathered? Run!\nワギャラン"
            ]
        }
        return [
            "よくぞ　あのダンジョンをくぐりぬけた。\nほめてやろう。",
            "ふっふっふ・・・このカードのいみは、いうまでもあるまい。\nでは、いざ。",
            "What's gathered? Run!\nワギャラン"
        ]
    }

    // 通常アニメーションを基本画像から開始するための基準時刻
    @State private var characterAnimationEpoch = Date()

    // 対戦中ヒントはCPUメッセージとは独立して5秒ごとに切り替える
    @State private var upperHintIndex = 0
    @State private var lowerHintIndex = 0
    @State private var hintRotationTimer: Timer?

    // ボスの独り言として表示する連想ヒント
    private var bossHintMessages: [String] {
        if stage == .trial {
            return [
                "るびー、ぴじょんぶらっど、こうぎょく・・・ほうせきは きらきらザマス。",
                "ぱん・・・は だめザマス。そうだ、いーすと とか ぶれっど っていうザンス。",
                "とろふぃー は、ええと かっぷ とか ちゃんぴおんかっぷ とも いうザマスね。",
                "すけーと は・・・は の ぶぶんを ぶれーど、えっじ なんて いうザンスね。",
                "おやつ、じぇらーと、すいーつ、そるべ・・・あいすは だいこうぶつザマス。",
                "ぷれぜんと、ぎふと・・・おくりものっていみで、おなじザンスよね・・・？",
                "へー、とらんぷは、でっきとか、ぷれいんぐかーど というザマスか・・・。",
                "しーる？すてっかー？てーぷ？らべる？なにが ちがうザンスかしら・・・。",
                "・・・はっ！？なんザンスか、かんにんぐ なんて してないザマスよ！？",
                "おとしすぎて、せんすの もじが  きえてきたザンス・・・まずいザマス！",
                "ふっふっふ・・・この せんす が あれば ミーは むてきザマス！おほほほほ！",
                "ねーぶる、ぶらっどおれんじ、だいだい・・・いろいろあるザンスねえ。",
                "え？ずっと せんすを みていて あやしい？・・・き・・・きのせいザマス！",
                "きのう いっぱい かきこんで きて よかったザンス。このこ、つよいザマス。",
                "あの ぷらもでる、ゆーふぉー・・・みかくにんひこうぶったいザマスか。",
                "くちべに は なんだったザマスかしら？えーと、るーじゅ りっぷぐろす・・・",
                "ぺだる ふらっとぺだる。へえ、あしかけ や とうめん なんて いうザマスか？",
                "とんねる は せんろ も みえるザマス。てつどうとんねる、こうどうザマスね。",
                "びすけっと くっきー さぶれ がれっと・・・？みわけが つかないザマスねえ。",
                "え？せんすで ぜんぜん あおいで いないって？きょうは すずしいザマスから。"
            ]
        }
        if isRandomStage {
            return [
                "やめろっ　裏読みが出てくるとややこしいことになるから",
                "おとな、あだると、すーつ、ねくたい、びじねすまん・・・ぬっ、いかんいかん。",
                "めいろ、まよいみち、るーと、すたーと・・・はた に いけがき も みえるな。",
                "りんご は あかりんごか。ふるーつ、きのみ、くだもの と いっても いいだろう。",
                "まど ういんどう がらす・・・かーてん も あるな。なら なかまど とも いえるか。",
                "どあ、のぶ・・・いりぐち、でぐち・・・げんかん・・・おっと、いかんな。",
                "これは こども か。ひとり とも よめるな。きっず、おとこのこ・・・ぶつぶつ。",
                "こま、すぴん、おもちゃ、いと、ひも・・・くるくる、かいてんか。",
                "まくら、ぴろー、しんぐ、すいみん・・・おやすみもあるか、ふむ。",
                "なす、えっぐぷらんと、やさい、むらさき・・・つけものもあるか。",
                "だるま、ごうかく、おきもの、えんぎもの・・・がんかけもあるか、ふむ。",
                "ろうそく、あかり、ともしび、しょくだい・・・ほのお、ひ・・・なるほど。",
                "くつ、しゅーず、はきもの、すにーかー・・・どれもおなじものか、ふむ。",
                "りす、きのみ、しっぽ、どうぶつ・・・ぬいぐるみもありか、ぶつぶつ。",
                "りょうり、ちょうり、しょくじ、ごちそう・・・めだまやきにふらいぱんか。",
                "つき、まんげつ、おつきみ、じゅうごや・・・よぞらもみえるな、なるほど。",
                "らじお、でんぱ、ほうそう、おんがく、にゅーす・・・ばんぐみもあるか。",
                "裏読みは欺瞞だ、すべてが欺瞞に満ちている・・・。",
                "裏読みを言ったら殺されても文句は言えねぇぞ！",
                "その読みはやめろーっ！裏読みはルールで禁止ㇲよね。",
                "やっぱ怖いㇲね裏読みは。でもしりとりはルール無用だろ。",
                "でも…ひとつだけ言いたいことがあるんです。裏読みはクソだ。",
                "えっ なにっ なにこれ? ねーっなんなのこの読み！",
                "裏読み（それ）はだめだろ。忌憚の無い意見ってやつっス。"
            ]
        }
        return [
        "・・・こぶた、どうぶつ・・・ぬいぐるみ、ちょきんばこもありか・・ぶつぶつ。",
        "おとな、あだると、すーつ、ねくたい、びじねすまん・・・ぬっ、いかんいかん。",
        "めいろ、まよいみち、るーと、すたーと・・・はた に いけがき も みえるな。",
        "りんご は あかりんごか。ふるーつ、きのみ、くだもの と いっても いいだろう。",
        "まど ういんどう がらす・・・かーてん も あるな。なら なかまど とも いえるか。",
        "どあ、のぶ・・・いりぐち、でぐち・・・げんかん・・・おっと、いかんな。",
        "これは こども か。ひとり とも よめるな。きっず、おとこのこ・・・ぶつぶつ。",
        "こま、すぴん、おもちゃ、いと、ひも・・・くるくる、かいてんか。",
        "まくら、ぴろー、しんぐ、すいみん・・・おやすみもあるか、ふむ。",
        "なす、えっぐぷらんと、やさい、むらさき・・・つけものもあるか。",
        "だるま、ごうかく、おきもの、えんぎもの・・・がんかけもあるか、ふむ。",
        "ろうそく、あかり、ともしび、しょくだい・・・ほのお、ひ・・・なるほど。",
        "くつ、しゅーず、はきもの、すにーかー・・・どれもおなじものか、ふむ。",
        "りす、きのみ、しっぽ、どうぶつ・・・ぬいぐるみもありか、ぶつぶつ。",
        "りょうり、ちょうり、しょくじ、ごちそう・・・めだまやきにふらいぱんか。",
        "つき、まんげつ、おつきみ、じゅうごや・・・よぞらもみえるな、なるほど。",
        "らじお、でんぱ、ほうそう、おんがく、にゅーす・・・ばんぐみもあるか。"
        ]

    }

    // 操作方法やゲームルールを案内するシステムヒント
    private let systemHintMessages = [
        "1回目のタップでオレンジ枠の狙いを定めて、2回目のタップで決定だ。",
        "カードにはいろんな読み方がたくさんあるぞ。色々ためしてみよう。",
        "お手つきすると、きみの持ち時間が５秒も減っちゃうぞ、気をつけよう。",
        "カードを１枚取ると、きみの持ち時間が５秒増えるぞ、あせらないで。",
        "よめるカードが見つからないときは、手当たり次第にためしてみよう。",
        "驚きのよみかたをするとすぐに勝負が決まるかも？でもそのせいで負けるかも？"
    ]

    var body: some View {
        GeometryReader { geometry in
            // 端末の縦幅に合わせて上下の余白とヒント行を詰め、5×5盤面の最大幅を優先する。
            let isCompactHeight = geometry.size.height < 760
            let isVeryCompactHeight = geometry.size.height < 700
            let verticalSpacing: CGFloat = isVeryCompactHeight ? 1 : (isCompactHeight ? 4 : 6)
            let verticalPadding: CGFloat = isVeryCompactHeight ? 0 : (isCompactHeight ? 4 : 8)
            let hintRowHeight: CGFloat = isVeryCompactHeight ? 14 : (isCompactHeight ? 16 : 20)
            let messageWindowHeight: CGFloat = 72
            let boardSize = max(0, geometry.size.width - 16)
            let preferredCPUCharacterSize = min(geometry.size.width * 0.36, geometry.size.height * 0.19)
            let preferredPlayerCharacterSize = min(geometry.size.width * 0.30, geometry.size.height * 0.15)
            let nonCharacterHeight = boardSize
                + hintRowHeight * 2
                + messageWindowHeight
                + verticalSpacing * 5
                + verticalPadding * 2
            let availableCharacterHeight = max(0, geometry.size.height - nonCharacterHeight)
            let preferredCharacterHeight = preferredCPUCharacterSize + preferredPlayerCharacterSize
            let characterLayoutScale = preferredCharacterHeight > 0
                ? min(1, availableCharacterHeight / preferredCharacterHeight)
                : 1
            let characterDisplayScale = characterLayoutScale > 0
                ? min(1.12, 1 / characterLayoutScale)
                : 1
            let cpuCharacterSize = preferredCPUCharacterSize * characterLayoutScale
            let characterSize = preferredPlayerCharacterSize * characterLayoutScale

            TimelineView(.periodic(from: Date(), by: 0.05)) { timeline in
                let now = timeline.date
                ZStack {
                    Color.black
                        .ignoresSafeArea()

                    VStack(spacing: verticalSpacing) {

                        // MARK: - 上部：CPU画像・残り枚数・次の文字

                        HStack(alignment: .center, spacing: 8) {
                            // CPU画像を大きく表示する
                            Image(sharedCharacterAssetName(for: characterImage(
                                prefix: isTrialStage ? "character_cpu2" : "character_cpu",
                                event: gameManager.cpuAnimationEvent,
                                at: now,
                                isPlayer: false
                            )))
                                .resizable()
                                .scaledToFit()
                                .frame(width: cpuCharacterSize, height: cpuCharacterSize)
                                .scaleEffect(characterDisplayScale)
                                // CPU2の元画像は画面端で見切れやすいため、試練ステージだけ表示を90%に縮小する。
                                .scaleEffect(isTrialStage ? 0.9 : 1.0)

                            // 上段に「残り枚数」「次の文字」、その下段中央にCPUを表示する
                            VStack(spacing: 8) {
                                HeaderView(
                                    remainingCardCount: remainingCardCount,
                                    currentPrompt: gameManager.currentPrompt
                                )
                                .frame(maxWidth: .infinity)

                                Text("CPU")
                                    .font(DungeonTypography.maruMonica(size: 14))
                                    .foregroundStyle(.white)
                                    .fixedSize()
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .frame(height: cpuCharacterSize)

                        // CPU向けヒントは1行分の高さで表示し、メッセージ枠へ重ねない。
                        HintLineView(text: bossHintMessages[upperHintIndex])
                            .frame(height: hintRowHeight)

                        // MARK: - メッセージウィンドウ

                        MessageWindowView(
                            message: isShowingOpeningDialogue
                                ? openingDialogueMessages[openingDialogueIndex]
                                : messageText,
                            typingDuration: isShowingOpeningDialogue && openingDialogueIndex < 2
                                ? 3.0
                                : nil,
                            displayImmediately: isShowingOpeningDialogue && openingDialogueIndex == 2,
                            // 導入会話と途中の特殊セリフは既存時間を維持し、最終セリフ後は統合用に3秒待機する
                            holdDuration: isShowingOpeningDialogue
                                ? (openingDialogueIndex < 2 ? 2.0 : 5.0)
                            : (playerLoseNMessageHoldDuration
                                ?? noCPUTargetVictoryMessageHoldDuration
                                ?? cpuFinalCardMessageHoldDuration
                                ?? timeoutMercyVictoryMessageHoldDuration),
                            // 最後の英語・署名メッセージだけ、2行とも中央揃えにする
                            centerText: isShowingOpeningDialogue && openingDialogueIndex == 2,
                            onCompleted: { completedMessage in
                                handleMessageDisplayCompleted(completedMessage)
                            }
                        )

                        // MARK: - 中央：25枚のカード

                        CardBoardView(
                            cards: gameManager.cards,
                            selectedCardID: gameManager.selectedCardID,
                            cpuScanIndex: gameManager.currentCPUScanIndex,
                            onCardTap: { id in
                                gameManager.selectCard(id: id)

                                // 同じカードを2回タップして確定した場合は判定する
                                if gameManager.confirmedCardID == id {
                                    gameManager.confirmSelectedCard()
                                }
                            }
                        )
                        .frame(width: boardSize, height: boardSize)
                        .frame(maxWidth: .infinity)

                        // PLAYER向けヒントも1行分の高さで表示し、情報表示と重ならないようにする。
                        HintLineView(text: systemHintMessages[lowerHintIndex])
                            .frame(height: hintRowHeight)

                        // MARK: - 下部：PLAYER情報・PLAYER画像

                        HStack(alignment: .center, spacing: 8) {
                            // PLAYERと残り時間を画像の左側に表示する
                            PlayerStatusView(
                                playerTime: gameManager.playerTime
                            )
                            .frame(maxWidth: .infinity)

                            // 画面右側に向く配置に合わせ、PLAYER画像を水平方向に反転する
                            Image(sharedCharacterAssetName(for: characterImage(
                                prefix: "character_player",
                                event: gameManager.playerAnimationEvent,
                                at: now,
                                isPlayer: true
                            )))
                                .resizable()
                                .scaledToFit()
                                .scaleEffect(x: -1, y: 1)
                                .frame(width: characterSize, height: characterSize)
                                .scaleEffect(characterDisplayScale)
                        }
                        .frame(height: characterSize)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, verticalPadding)
                }
            }
            .onAppear {
                // 画面に戻った場合も、補助ヒントの切り替えを再開する
                startHintRotation()

                // 画面表示時にゲームを一度だけ開始する
                guard !hasStarted else { return }

                hasStarted = true
                // 盤面とCPUの先攻対象を準備し、3段階の導入会話が終わるまでスキャンを待つ
                gameManager.startGame(waitForOpeningDialogue: true)
            }
            .onDisappear {
                finishTransitionTimer?.invalidate()
                finishTransitionTimer = nil
                hintRotationTimer?.invalidate()
                hintRotationTimer = nil
            }
        }
    }

    // 上段・下段のヒントを独立して5秒ごとに切り替える
    private func startHintRotation() {
        hintRotationTimer?.invalidate()
        hintRotationTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            let nextUpper = bossHintMessages.indices.filter { $0 != upperHintIndex }.randomElement()
            let nextLower = systemHintMessages.indices.filter { $0 != lowerHintIndex }.randomElement()
            if let nextUpper { upperHintIndex = nextUpper }
            if let nextLower { lowerHintIndex = nextLower }
        }
    }

    // メッセージの完了に応じて、導入会話を進めるか敗北BGMを再生する
    private func handleMessageDisplayCompleted(_ completedMessage: String) {
        if isShowingOpeningDialogue {
            // 古いメッセージの完了通知で導入会話が飛ばないように確認する
            guard completedMessage == openingDialogueMessages[openingDialogueIndex] else {
                return
            }

            if openingDialogueIndex < openingDialogueMessages.count - 1 {
                openingDialogueIndex += 1
            } else {
                // 3つ目は一気に表示したあと5秒保持し、その後CPU先攻を開始する
                isShowingOpeningDialogue = false
                gameManager.startInitialCPUScanAfterOpeningDialogue()
            }
            return
        }

        // 古いメッセージの完了通知では再生しない
        guard completedMessage == messageText else { return }

        // 「ん」敗北は、気づきのセリフから敗北宣告へ段階的に進める。
        if gameManager.isPlayerLoseNEndingActive {
            switch gameManager.playerLoseNEndingStage {
            case .recognitionMessage:
                gameManager.advancePlayerLoseNEnding(after: completedMessage)
                return
            case .defeatMessage:
                gameManager.advancePlayerLoseNEnding(after: completedMessage)
            case .inactive, .finished:
                break
            }
        }

        // CPU最終カードのエンディング。最後のセリフ全文表示後に統合用の待機を開始する。
        if gameManager.isCPUFinalCardEndingActive {
            if case .victoryAcknowledgement = gameManager.cpuFinalCardEndingStage {
                gameManager.advanceCPUFinalCardEnding(after: completedMessage)
                scheduleGameFinish(won: true)
            } else {
                gameManager.advanceCPUFinalCardEnding(after: completedMessage)
            }
            return
        }

        // 時間切れ特別勝利。最後のセリフ全文表示後に統合用の待機を開始する。
        if gameManager.isTimeoutMercyVictoryActive {
            if case .victoryConcession = gameManager.timeoutMercyVictoryStage {
                gameManager.advanceTimeoutMercyVictory(after: completedMessage)
                scheduleGameFinish(won: true)
            } else {
                gameManager.advanceTimeoutMercyVictory(after: completedMessage)
            }
            return
        }

        // CPUが選べるカードを失った場合の、最後の敗北承認メッセージ。
        if gameManager.isNoCPUTargetVictoryActive {
            if case .defeatAcknowledgement = gameManager.noCPUTargetVictoryStage {
                gameManager.advanceNoCPUTargetVictory(after: completedMessage)
                scheduleGameFinish(won: true)
            } else {
                gameManager.advanceNoCPUTargetVictory(after: completedMessage)
            }
            return
        }

        guard let result = gameManager.gameResult else { return }
        switch result {
        case .playerLoseTimeout, .playerLoseN:
            guard !defeatBGMPlayed else { return }
            // 既存の敗北BGMを開始してから、統合用の3秒待機を始める。
            defeatBGMPlayed = true
            SoundEffectManager.shared.playDefeatBGMOnce()
            scheduleGameFinish(won: false)

        case .playerWinAllCards, .playerWinNoCPUTarget, .playerWinCPUN, .playerWinTimeoutMercy:
            // 特殊エンディングは上の分岐で処理し、通常勝利はここで結果を通知する。
            scheduleGameFinish(won: true)
        }
    }

    // 最終メッセージの全文表示と必要な結果演出の後、3秒待って統合アプリへ結果を渡す。
    private func scheduleGameFinish(won: Bool) {
        guard !hasScheduledGameFinish else { return }
        hasScheduledGameFinish = true

        finishTransitionTimer?.invalidate()
        finishTransitionTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
            finishTransitionTimer = nil
            SoundEffectManager.shared.stopBGM()
            onGameFinished(won)
        }
    }

    // ゲーム結果のイベントを優先し、終了後は基本画像から通常ループを再開する
    private func characterImage(
        prefix: String,
        event: CharacterAnimationEvent?,
        at date: Date,
        isPlayer: Bool
    ) -> String {
        if isTrialStage && !isPlayer {
            return trialCPUCharacterImage(prefix: "character_cpu2", event: event, at: date)
        }

        // ランダムステージは導入1段階目だけ従来CPUを使い、2段階目からCPU3専用演出へ切り替える。
        if isRandomStage && !isPlayer && !(isShowingOpeningDialogue && openingDialogueIndex == 0) {
            return randomStageCPUCharacterImage(at: date)
        }

        // 時間切れ特別勝利の健闘セリフ以降は、CPUを通常画像、PLAYERをWrong画像に固定する。
        switch gameManager.timeoutMercyVictoryStage {
        case .hardFoughtMessage, .victoryConcession, .finished:
            return isPlayer ? "\(prefix)_wrong" : prefix
        case .inactive, .defeatMessage:
            break
        }

        // カードを使い切ったセリフ以降は、CPUを通常画像、PLAYERを勝利ジャンプに固定する。
        switch gameManager.cpuFinalCardEndingStage {
        case .cardsExhaustedMessage, .victoryAcknowledgement, .finished:
            // CPUは通常ポーズのままにし、PLAYERは勝利ジャンプ3フレームを繰り返す。
            guard isPlayer else { return prefix }
            let startDate = gameManager.playerAnimationEvent?.startedAt ?? characterAnimationEpoch
            let elapsed = max(0, date.timeIntervalSince(startDate))
            let frame = Int(elapsed / 0.5) % 3
            switch frame {
            case 0: return "\(prefix)_jump_01"
            case 1: return "\(prefix)_jump_02"
            default: return "\(prefix)_jump_03"
            }

        case .inactive, .normalCPUMessage:
            break
        }

        // 最後の通常CPUメッセージ中だけは、結果確定より通常の取得アニメーションを優先する。
        if case .normalCPUMessage = gameManager.cpuFinalCardEndingStage {
            // この段階は次の特殊メッセージへ移るまで通常のアニメーションを続ける。
        } else if let result = gameManager.gameResult {
            // それ以外の終了時は勝者がジャンプを繰り返し、敗者はwrongを維持する。
            let playerWon: Bool
            switch result {
            case .playerWinAllCards, .playerWinNoCPUTarget, .playerWinCPUN:
                playerWon = true
            case .playerLoseTimeout, .playerLoseN, .playerWinTimeoutMercy:
                // 特別勝利の最初の「時間切れ」セリフ中だけ、従来の時間切れポーズを保つ。
                playerWon = false
            }

            if isPlayer == playerWon {
                let startDate = event?.startedAt ?? characterAnimationEpoch
                let elapsed = max(0, date.timeIntervalSince(startDate))
                let frame = Int(elapsed / 0.5) % 3
                switch frame {
                case 0: return "\(prefix)_jump_01"
                case 1: return "\(prefix)_jump_02"
                default: return "\(prefix)_jump_03"
                }
            } else {
                return "\(prefix)_wrong"
            }
        }

        var normalElapsed = date.timeIntervalSince(characterAnimationEpoch)

        if let event {
            let elapsed = date.timeIntervalSince(event.startedAt)

            if elapsed >= 0 {
                let eventDuration: TimeInterval

                switch event.kind {
                case .success:
                    eventDuration = 3.0

                    // 3フレームを各0.5秒で表示し、合計3秒（2ループ）で通常へ戻す
                    if elapsed < eventDuration {
                        let frame = Int(elapsed / 0.5) % 3
                        switch frame {
                        case 0: return "\(prefix)_jump_01"
                        case 1: return "\(prefix)_jump_02"
                        default: return "\(prefix)_jump_03"
                        }
                    }

                case .failure:
                    eventDuration = 1.5

                    // wrong画像は1.5秒だけ表示して通常へ戻す
                    if elapsed < eventDuration {
                        return "\(prefix)_wrong"
                    }
                }

                // イベント終了時点を通常ループの起点にするため、基本画像から再開する。
                normalElapsed = elapsed - eventDuration
            }
        }

        // 通常時は基本1秒→瞬き0.5秒→呼吸0.5秒→羽0.5秒の2.5秒周期で繰り返す。
        // 羽の表示が終わると基本画像へ戻り、基本画像を1秒表示してから次の瞬きへ進む。
        let phase = normalElapsed.truncatingRemainder(dividingBy: 2.5)

        if phase < 1.0 {
            return prefix
        } else if phase < 1.5 {
            return "\(prefix)_blink"
        } else if phase < 2.0 {
            return "\(prefix)_breath"
        } else {
            return "\(prefix)_wing"
        }
    }

    /// ダンジョン側と共通する画像は1つのAsset Catalogから読み込む。
    private func sharedCharacterAssetName(for sourceName: String) -> String {
        switch sourceName {
        case "character_cpu": return "MessageMonsterIdle"
        case "character_cpu_breath", "character_cpu_jump_01": return "MessageMonsterMove1"
        case "character_cpu_jump_02": return "MessageMonsterMove2"
        case "character_cpu_jump_03": return "MessageMonsterMove3"
        case "character_player": return "PlayerIdle"
        case "character_player_blink": return "PlayerBlink"
        case "character_player_breath": return "PlayerBreath"
        case "character_player_jump_01": return "PlayerMove1"
        case "character_player_jump_02": return "PlayerMove2"
        case "character_player_jump_03": return "PlayerMove3"
        default: return sourceName
        }
    }

    /// ランダムステージCPU3専用の画像・アニメーションを選択する。
    private func randomStageCPUCharacterImage(at date: Date) -> String {
        let prefix = "character_cpu3"

        // 残り7枚以下の時間切れ特殊勝利は、CPUが勝ちを譲る演出のため通常待機を続ける。
        // 勝敗結果より先に判定し、失敗アニメーションへ入らないようにする。
        if gameManager.gameResult == .playerWinTimeoutMercy {
            return randomStageCPUIdleImage(at: date.timeIntervalSince(characterAnimationEpoch))
        }

        // 勝敗を最優先する。アニメーションはメッセージ進行・画面遷移を変更しない。
        if let result = gameManager.gameResult {
            switch result {
            case .playerLoseTimeout, .playerLoseN:
                return randomStageCPUWinAnimation(at: date)
            case .playerWinAllCards, .playerWinNoCPUTarget, .playerWinCPUN:
                return randomStageCPULowCardFailureAnimation(at: date)
            case .playerWinTimeoutMercy:
                // 上で通常待機へ振り分け済み。
                return randomStageCPUIdleImage(at: date.timeIntervalSince(characterAnimationEpoch))
            }
        }

        // 結果確定前の専用メッセージ中は既存の専用ポーズを優先する。
        switch gameManager.timeoutMercyVictoryStage {
        case .hardFoughtMessage, .victoryConcession, .finished:
            return prefix
        case .inactive, .defeatMessage:
            break
        }

        switch gameManager.cpuFinalCardEndingStage {
        case .cardsExhaustedMessage, .victoryAcknowledgement, .finished:
            return prefix
        case .inactive, .normalCPUMessage:
            break
        }

        guard let event = gameManager.cpuAnimationEvent else {
            return randomStageCPUIdleImage(at: date.timeIntervalSince(characterAnimationEpoch))
        }

        let elapsed = max(0, date.timeIntervalSince(event.startedAt))
        switch event.kind {
        case .success:
            // win1（1秒）→win2（0.5秒）→win3（0.5秒）を2周し、4秒後に通常待機へ戻す。
            if elapsed < 4.0 {
                return randomStageCPUWinAnimation(at: date)
            }
            return randomStageCPUIdleImage(at: elapsed - 4.0)
        case .failure:
            // イベント開始時点の残り枚数を固定して画像を選ぶ（13枚以上／12枚以下）。
            if event.remainingCardCountAtStart >= 13 {
                // wrong1・wrong2・wrong4は各0.5秒で2周（合計3秒）。
                if elapsed < 3.0 {
                    let frames = ["wrong1", "wrong2", "wrong4"]
                    return "\(prefix)_\(frames[Int(elapsed / 0.5) % frames.count])"
                }
                return randomStageCPUIdleImage(at: elapsed - 3.0)
            } else {
                // wrong3・wrong6は各1秒、wrong5は0.5秒。2周後に通常待機へ戻す。
                if elapsed < 5.0 {
                    let phase = elapsed.truncatingRemainder(dividingBy: 2.5)
                    if phase < 1.0 { return "\(prefix)_wrong3" }
                    if phase < 1.5 { return "\(prefix)_wrong5" }
                    return "\(prefix)_wrong6"
                }
                return randomStageCPUIdleImage(at: elapsed - 5.0)
            }
        }
    }

    /// プレイヤー勝利時のCPU反応。wrong3・wrong6を各1秒、wrong5を0.5秒で連続ループする。
    private func randomStageCPULowCardFailureAnimation(at date: Date) -> String {
        let startDate = gameManager.cpuAnimationEvent?.startedAt ?? characterAnimationEpoch
        let elapsed = max(0, date.timeIntervalSince(startDate))
        let phase = elapsed.truncatingRemainder(dividingBy: 2.5)
        if phase < 1.0 { return "character_cpu3_wrong3" }
        if phase < 1.5 { return "character_cpu3_wrong5" }
        return "character_cpu3_wrong6"
    }

    /// CPU3の通常待機ループ。基本画像1秒、各差分0.5秒の2.5秒周期。
    private func randomStageCPUIdleImage(at elapsed: TimeInterval) -> String {
        let phase = max(0, elapsed).truncatingRemainder(dividingBy: 2.5)
        if phase < 1.0 { return "character_cpu3" }
        if phase < 1.5 { return "character_cpu3_blink" }
        if phase < 2.0 { return "character_cpu3_breath1" }
        return "character_cpu3_breath2"
    }

    /// CPUの勝利アニメーション。終了後もループし、画面遷移はメッセージ側に任せる。
    private func randomStageCPUWinAnimation(at date: Date) -> String {
        let startDate = gameManager.cpuAnimationEvent?.startedAt ?? characterAnimationEpoch
        let frame = Int(max(0, date.timeIntervalSince(startDate)) / 0.5) % 4
        switch frame {
        case 0, 1: return "character_cpu3_win1"
        case 2: return "character_cpu3_win2"
        default: return "character_cpu3_win3"
        }
    }

    /// 試練CPU専用の表示だけを切り替える。イベント発生条件・勝敗判定・メッセージ進行は共通処理を使う。
    private func trialCPUCharacterImage(
        prefix: String,
        event: CharacterAnimationEvent?,
        at date: Date
    ) -> String {
        // 時間切れ特別勝利ではCPUは譲る側なので、全段階で通常待機ループを維持する。
        if gameManager.gameResult == .playerWinTimeoutMercy {
            return trialIdleImage(prefix: prefix, at: date)
        }

        // CPUが「ん」で自滅、またはCPUが取れるカードなし：バラを掲げる反応を無期限で繰り返す。
        if gameManager.gameResult == .playerWinCPUN || gameManager.gameResult == .playerWinNoCPUTarget {
            let elapsed = max(0, date.timeIntervalSince(event?.startedAt ?? characterAnimationEpoch))
            return Int(elapsed / 0.5) % 2 == 0 ? "\(prefix)_rose1" : "\(prefix)_rose2"
        }

        // プレイヤー時間切れによるCPU特殊勝利：既存の勝利アニメーションをループする。
        // メッセージ完了と画面遷移のタイミングには干渉しない。
        if gameManager.gameResult == .playerLoseTimeout {
            let sequence: [(String, TimeInterval)] = [
                ("jump1", 0.7), ("jump2", 1.0), ("jump3", 0.5),
                ("jump4", 0.5), ("jump5", 0.5), ("jump6", 0.5)
            ]
            let elapsed = max(0, date.timeIntervalSince(event?.startedAt ?? characterAnimationEpoch))
            let cycleDuration = sequence.reduce(0) { $0 + $1.1 }
            var cursor = elapsed.truncatingRemainder(dividingBy: cycleDuration)
            for (frame, duration) in sequence {
                if cursor < duration { return "\(prefix)_\(frame)" }
                cursor -= duration
            }
        }

        // プレイヤーが「ん」で敗北した場合は既存の勝利演出を維持する。
        if gameManager.gameResult == .playerLoseN {
            let elapsed = max(0, date.timeIntervalSince(event?.startedAt ?? characterAnimationEpoch))
            let sequence: [(String, TimeInterval)] = [
                ("jump1", 0.7), ("jump2", 1.0), ("jump3", 0.5),
                ("jump4", 0.5), ("jump5", 0.5), ("jump6", 0.5),
                ("jump1", 0.7), ("jump2", 1.0), ("jump3", 0.5),
                ("jump4", 0.5), ("jump5", 0.5), ("jump6", 0.5),
                ("jump1", 0.5)
            ]
            var cursor: TimeInterval = 0
            for (frame, duration) in sequence {
                if elapsed < cursor + duration { return "\(prefix)_\(frame)" }
                cursor += duration
            }
            return trialIdleImage(prefix: prefix, elapsed: elapsed - cursor)
        }

        if let event {
            let elapsed = max(0, date.timeIntervalSince(event.startedAt))
            switch event.kind {
            case .success:
                // CPUが正しくカードを取ったときのジャンプは既存イベントに同期して7.5秒で終了。
                let sequence: [(String, TimeInterval)] = [
                    ("jump1", 0.7), ("jump2", 1.0), ("jump3", 0.5),
                    ("jump4", 0.5), ("jump5", 0.5), ("jump6", 0.5),
                    ("jump1", 0.7), ("jump2", 1.0), ("jump3", 0.5),
                    ("jump4", 0.5), ("jump5", 0.5), ("jump6", 0.5),
                    ("jump1", 0.5)
                ]
                var cursor: TimeInterval = 0
                for (frame, duration) in sequence {
                    if elapsed < cursor + duration { return "\(prefix)_\(frame)" }
                    cursor += duration
                }
                return trialIdleImage(prefix: prefix, elapsed: elapsed - cursor)

            case .failure:
                // プレイヤーが正しくカードを取った際の悔しがり。判定は取得後の残り枚数で行う。
                let framePrefix = remainingCardCount >= 13 ? "wrong1" : "wrong3"
                let secondFrame = remainingCardCount >= 13 ? "wrong2" : "wrong4"
                let firstFrameDuration: TimeInterval = 0.5
                let secondFrameDuration: TimeInterval = remainingCardCount >= 13 ? 0.5 : 1.0
                let firstCycleDuration = firstFrameDuration + secondFrameDuration
                let secondCycleDuration = firstCycleDuration * 2.0
                if elapsed < firstFrameDuration { return "\(prefix)_\(framePrefix)" }
                if elapsed < firstFrameDuration + secondFrameDuration { return "\(prefix)_\(secondFrame)" }
                if elapsed < firstCycleDuration + firstFrameDuration { return "\(prefix)_\(framePrefix)" }
                if elapsed < secondCycleDuration { return "\(prefix)_\(secondFrame)" }
                return trialIdleImage(prefix: prefix, elapsed: elapsed - secondCycleDuration)
            }
        }

        return trialIdleImage(prefix: prefix, at: date)
    }

    /// 試練CPUの通常待機：基本→瞬き→呼吸1→呼吸2を繰り返す。
    private func trialIdleImage(prefix: String, at date: Date) -> String {
        let elapsed = max(0, date.timeIntervalSince(characterAnimationEpoch))
        return trialIdleImage(prefix: prefix, elapsed: elapsed)
    }

    private func trialIdleImage(prefix: String, elapsed: TimeInterval) -> String {
        let phase = max(0, elapsed).truncatingRemainder(dividingBy: 2.5)
        if phase < 1.0 { return prefix }
        if phase < 1.5 { return "\(prefix)_blink" }
        if phase < 2.0 { return "\(prefix)_breath1" }
        return "\(prefix)_breath2"
    }

    // 「ん」敗北の段階セリフとCPUの特殊エンディングは、勝敗の既定メッセージより優先する
    private var messageText: String {
        if gameManager.isPlayerLoseNEndingActive {
            switch gameManager.playerLoseNEndingStage {
            case .recognitionMessage:
                return gameManager.currentMessage ?? "なんと・・・ん？"
            case .defeatMessage, .finished:
                if isRandomStage {
                    return gameManager.currentMessage ?? ""
                }
                return gameManager.isTrialStage
                    ? "ん がついてるザマス！やーい、ミーの かちザマス！"
                    : "ん がついているではないか、お前の負けだ"
            case .inactive:
                break
            }
        }

        if gameManager.isCPUFinalCardEndingActive || gameManager.isTimeoutMercyVictoryActive || gameManager.isNoCPUTargetVictoryActive {
            return gameManager.currentMessage ?? ""
        }

        // ゲーム終了時は勝敗結果を優先して表示する
        if let gameResult = gameManager.gameResult {
            switch gameResult {
            case .playerWinAllCards:
                return gameManager.isTrialStage
                    ? "おみごと・・・ミーのまけザマス・・・。"
                    : "見事だ…私の負けだ"

            case .playerWinNoCPUTarget:
                return gameManager.currentMessage
                    ?? (gameManager.isTrialStage
                        ? "なんてことザンス、ミーが えらべるカードがないザマス・・・。"
                        : "なんと、選べるカードがないではないか")

            case .playerWinCPUN:
                return gameManager.currentMessage
                    ?? "・・・しまったいかん！ 私の負けだ"

            case .playerWinTimeoutMercy:
                return gameManager.currentMessage ?? (gameManager.isTrialStage
                    ? "いいザンス、ユーの がんばりをみとめて、しょうりを ゆずってあげるザマス。"
                    : "よかろう、おまえの けんとうを たたえ、しょうりを ゆずってやろう。")

            case .playerLoseTimeout:
                if isRandomStage {
                    return gameManager.currentMessage ?? ""
                }
                return gameManager.isTrialStage
                    ? "おほほほほ！たいむあっぷザンス！ミーの かちザマス！"
                    : "フハハハ！時間切れだ！貴様の負けだ！"

            case .playerLoseN:
                return isRandomStage
                    ? (gameManager.currentMessage ?? "")
                    : "ちょっと待て、’ん’ で終わりではないか。貴様の負けだ"
            }
        }

        // ランダムステージのCPU初手案内だけ、姫龍専用セリフに差し替える。
        if isRandomStage,
           gameManager.currentMessage == "よし、まずは私から選ばせてもらうぞ" {
            return "今から一方的にお前は殺されるんだ。\n悔しいだろうが仕方ないんだ。"
        }

        // ゲーム中はShiritoriGameManagerが設定したメッセージを表示する
        return gameManager.currentMessage
            ?? "「さあ、始めるとしよう」"
    }

    // 「ん」敗北の気づきのセリフだけ、全文表示後に2秒保持する。
    private var playerLoseNMessageHoldDuration: TimeInterval? {
        gameManager.playerLoseNEndingStage == .recognitionMessage ? 2.0 : nil
    }

    // 時間切れ特別勝利の途中メッセージは2秒保持し、最後は統合用の3秒待機に委ねる
    private var timeoutMercyVictoryMessageHoldDuration: TimeInterval? {
        switch gameManager.timeoutMercyVictoryStage {
        case .defeatMessage, .hardFoughtMessage:
            return 2.0
        case .victoryConcession:
            return nil
        case .inactive, .finished:
            return nil
        }
    }

    // CPU最終カードの途中メッセージは2秒保持し、最後は統合用の3秒待機に委ねる
    private var cpuFinalCardMessageHoldDuration: TimeInterval? {
        switch gameManager.cpuFinalCardEndingStage {
        case .normalCPUMessage:
            // 次の特殊セリフへ切り替える前に、通常セリフの最後まで読める短い間を設ける
            return 0.5
        case .cardsExhaustedMessage:
            return 2.0
        case .victoryAcknowledgement:
            return nil
        case .inactive, .finished:
            return nil
        }
    }
    
    
    // CPU対象なしの勝利メッセージは、最初のセリフを全文表示後に2秒保持する
    private var noCPUTargetVictoryMessageHoldDuration: TimeInterval? {
        switch gameManager.noCPUTargetVictoryStage {
        case .noCardsMessage:
            return 2.0
        case .defeatAcknowledgement, .inactive, .finished:
            return nil
        }
    }


    
    
    // まだ取得されていないカードの枚数を数える
    // カード取得のたびにShiritoriGameManager.cardsのisClearedを参照して表示を更新する
    private var remainingCardCount: Int {
        gameManager.cards.filter { !$0.isCleared }.count
    }
}

#Preview {
    ShiritoriGameView(onGameFinished: { _ in })
}

// ヒントは常に1行で表示し、長い文は端末幅に合わせて文字を縮小する。
private struct HintLineView: View {
    let text: String

    var body: some View {
        GeometryReader { geometry in
            let availableWidth = max(1, geometry.size.width - 8)
            let characterCount = CGFloat(max(1, text.count))
            let fontSize = min(11, max(7, availableWidth / characterCount))

            Text(text)
                .font(DungeonTypography.maruMonica(size: fontSize))
                .foregroundStyle(.white)
                .lineLimit(1)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.65)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(.horizontal, 4)
                .background(Color.black)
                .accessibilityLabel(text)
        }
    }
}
