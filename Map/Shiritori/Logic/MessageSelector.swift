//
//  MessageSelector.swift
//  shiritori
//  
//  Phase 15：メッセージ・リアクション
//

import Foundation

// プレイヤー取得時・CPU取得時に表示するメッセージを選択する
struct MessageSelector {

    // プレイヤーがカードを取得したときのリアクション
    static func playerMessage(
        for vocabulary: Vocabulary,
        stage: ShiritoriStageType = .normal,
        isRandomStage: Bool = false
    ) -> String {
        if stage == .trial {
            switch vocabulary.type {
            case .normal:
                return "ふ・・・ふふん、\(vocabulary.displayWord) ザマスか。\nそうくるとおもってたザンス。"
            case .english:
                return "あ・・・あ〜ら、\(vocabulary.displayWord) ザンスね。\nなかなか やるザマス。"
            case .surprise:
                return "は・・・はあ！？ \(vocabulary.displayWord)・・・ザンスか・・・？\nそんなんありザマス・・・。"
            case .rare:
                return "ちょっ・・・\(vocabulary.displayWord)って・・・ありザマス？\nミーの じしょ には ないザンス・・・。"
            }
        }

        if isRandomStage {
            let messages: [String]
            switch vocabulary.type {
            case .normal:
                messages = [
                    "なにっ、\(vocabulary.displayWord)！？\nふうん、そういうことか。\nまぁこれくらい屁でもないとは\nいわんけどなブヘヘヘヘ。",
                    "はうっ、\(vocabulary.displayWord)！？\nしゃあけど、こんなん\nあたりまえの読みやんけ、\nたんしたことないのん。"
                ]
            case .english:
                messages = [
                    "あががっ、\(vocabulary.displayWord)！？\n・・・あいつ、おそらく\n英語が読めると考えられる。",
                    "なにいっ、\(vocabulary.displayWord)！？\n許せなかった…お前が本当は\n英語を読めるだなんて・・・"
                ]
            case .surprise:
                messages = [
                    "\(vocabulary.displayWord)！？あーー、\n何言ってるかわかんねえよ！\nお…お前変なクスリでも\nやってるのか！？",
                    "なにいっ、\(vocabulary.displayWord)！？\nいやちょっとまてよ、\nううんどういうことだ。"
                ]
            case .rare:
                messages = [
                    "はうっ、\(vocabulary.displayWord)！？\nそれジョークか？\n面白いことを言うなあ\nこの蛆虫は。",
                    "あががっ、\(vocabulary.displayWord)！？\n貴様ーっ、\n姫龍を愚弄する気かぁっ！"
                ]
            }
            return messages.randomElement() ?? ""
        }

        switch vocabulary.type {
        case .normal:
            return "ふむ、\(vocabulary.displayWord) か"
        case .english:
            return "ほほう、\(vocabulary.displayWord) か"
        case .surprise:
            return "むむむ！？ \(vocabulary.displayWord)・・・だと・・・？"
        case .rare:
            return "なんと、\(vocabulary.displayWord) と来たか。"
        }
    }

    // CPUがカードを取得したときのメッセージ候補
    static func cpuMessages(
        for vocabulary: Vocabulary,
        stage: ShiritoriStageType = .normal,
        isRandomStage: Bool = false
    ) -> [String] {
        if stage == .trial {
            switch vocabulary.type {
            case .normal:
                return [
                    "よーし、\(vocabulary.displayWord) ザマス！",
                    "ここは・・・ \(vocabulary.displayWord) でいくザンス！"
                ]
            case .english:
                return [
                    "うふふふ・・・ \(vocabulary.displayWord) ザマス。ごぞんじザンス？",
                    "これならどうザマス？ \(vocabulary.displayWord) ザンス！"
                ]
            case .surprise:
                return [
                    "おほほほ！\(vocabulary.displayWord) ザマス！ミーの きょうようが ひかってるザンス！"
                ]
            case .rare:
                return [
                    "ひらめいたザンス！\(vocabulary.displayWord) とも よめるザマス！"
                ]
            }
        }

        if isRandomStage {
            switch vocabulary.type {
            case .normal:
                return ["しゃあっ、\(vocabulary.displayWord)！", "あざーす（ｶﾞｼｯ\n\(vocabulary.displayWord)！"]
            case .english:
                return ["ヤンケ、「シバクヤンケ」\n\(vocabulary.displayWord)！", "英語読みはリラックスできますね。\n\(vocabulary.displayWord)！"]
            case .surprise:
                return ["その読みはやめろーっ、てか？\n\(vocabulary.displayWord)！", "\(vocabulary.displayWord)はルールで\n禁止ㇲよね、ってか？\nへっ、あまちゃんが。"]
            case .rare:
                return ["アタイってやつは結構鬼畜だな。\n\(vocabulary.displayWord)！", "\(vocabulary.displayWord)。この読みに\n一番戸惑っているのはアタイ\nなんだよね。すごくない?"]
            }
        }

        switch vocabulary.type {
        case .normal:
            return [
                "よし、\(vocabulary.displayWord) だ！",
                "まあ・・・ぶなんに \(vocabulary.displayWord) といこうか"
            ]
        case .english:
            return [
                "ふふふ・・・ \(vocabulary.displayWord) だ",
                "これならどうだ？ \(vocabulary.displayWord) だ！"
            ]
        case .surprise:
            return [
                "はっはっは、\(vocabulary.displayWord) という読み方もあるのだよ！"
            ]
        case .rare:
            return [
                "どうだ、\(vocabulary.displayWord) だ！参ったか！"
            ]
        }
    }

    // CPUメッセージを候補からランダムに1つ選ぶ
    static func randomCPUMessage(
        for vocabulary: Vocabulary,
        stage: ShiritoriStageType = .normal,
        isRandomStage: Bool = false
    ) -> String {
        let messages = cpuMessages(for: vocabulary, stage: stage, isRandomStage: isRandomStage)
        return messages.randomElement() ?? ""
    }

    // CPUがカードを取得した後に、次に選べる文字を付けたメッセージを作成する
    static func cpuMessageWithNextPrompt(
        for vocabulary: Vocabulary,
        nextPrompt: Character?,
        stage: ShiritoriStageType = .normal,
        isRandomStage: Bool = false
    ) -> String {
        let baseMessage = randomCPUMessage(for: vocabulary, stage: stage, isRandomStage: isRandomStage)

        guard let nextPrompt else {
            return baseMessage
        }

        let promptText = KanaNormalizer.promptDisplayText(for: nextPrompt)
        if stage == .trial {
            return "\(baseMessage)\nさあ、『\(promptText)』から\nはじまるカードをえらぶザンス！"
        }
        if isRandomStage {
            return "\(baseMessage)\nほれ、「\(promptText)」やっ！"
        }
        return "\(baseMessage)\n「\(promptText)」から\nはじまるカードを選べ！"
    }
}
