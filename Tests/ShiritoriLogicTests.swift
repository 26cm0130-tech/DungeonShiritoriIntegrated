import Foundation

/// しりとり判定の純粋ロジック（かな正規化・読みの選択・メッセージ・カードデータ）を検証する。
@MainActor
enum ShiritoriLogicTests {
    private static var count = 0

    static func run() throws -> Int {
        try testNormalize()
        try testFirstLastAndEndsWithN()
        try testPromptCharacters()
        try testPromptConsistencyAcrossHiragana()
        try testVocabularySelector()
        try testCPUSelector()
        try testMessageSelector()
        try testCardData()
        print("PASS: しりとり判定ロジック（かな正規化・読み選択・メッセージ・カードデータ） (\(count) assertions)")
        return count
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        count += 1
        if !condition() { throw Failure(message: message) }
    }

    private struct Failure: Error, CustomStringConvertible {
        let message: String
        var description: String { "しりとりロジックのテスト失敗: \(message)" }
    }

    private static func vocab(_ word: String, _ type: WordType = .normal) -> Vocabulary {
        Vocabulary(word: word, displayWord: word, type: type)
    }

    private static func card(_ vocabularies: [Vocabulary], cleared: Bool = false) -> Card {
        Card(id: UUID(), imageName: "test", vocabularies: vocabularies, isCleared: cleared)
    }

    // MARK: - KanaNormalizer

    private static func testNormalize() throws {
        let cases: [(input: String, expected: String)] = [
            ("ぁぃぅぇぉゃゅょっ", "あいうえおやゆよつ"),
            ("がぎぐげござじずぜぞだぢづでど", "かきくけこさしすせそたちつてと"),
            ("ばびぶべぼぱぴぷぺぽ", "はひふへほはひふへほ"),
            ("しょっぷ", "しよつふ"),
            ("ぱんだ", "はんた"),
            // 末尾の長音だけを無視し、語中の長音は残す。
            ("こーひー", "こーひ"),
            ("らーめん", "らーめん"),
            ("かーーー", "か"),
            ("ー", ""),
            ("", "")
        ]
        for item in cases {
            try expect(
                KanaNormalizer.normalize(item.input) == item.expected,
                "normalize(\(item.input)) は \(item.expected)"
            )
        }
    }

    private static func testFirstLastAndEndsWithN() throws {
        try expect(KanaNormalizer.firstCharacter(of: "がっこう") == "か", "先頭は濁音を清音へ")
        try expect(KanaNormalizer.firstCharacter(of: "ぱん") == "は", "先頭は半濁音を清音へ")
        try expect(KanaNormalizer.lastCharacter(of: "しりとりー") == "り", "末尾の長音を無視")
        try expect(KanaNormalizer.lastCharacter(of: "かば") == "は", "末尾は濁音を清音へ")
        try expect(KanaNormalizer.firstCharacter(of: "") == nil, "空文字の先頭はnil")
        try expect(KanaNormalizer.lastCharacter(of: "ー") == nil, "長音だけなら末尾はnil")

        for word in ["みかん", "ぱん", "らいおんー", "ん", "ふるむーん"] {
            try expect(KanaNormalizer.endsWithN(word), "\(word) は「ん」終わり")
        }
        for word in ["", "んご", "りんご", "ー", "あんぱ"] {
            try expect(!KanaNormalizer.endsWithN(word), "\(word) は「ん」終わりではない")
        }
    }

    private static func testPromptCharacters() throws {
        let rows: [(Character, [Character])] = [
            ("か", ["か", "が"]), ("き", ["き", "ぎ"]), ("く", ["く", "ぐ"]),
            ("け", ["け", "げ"]), ("こ", ["こ", "ご"]),
            ("さ", ["さ", "ざ"]), ("し", ["し", "じ"]), ("す", ["す", "ず"]),
            ("せ", ["せ", "ぜ"]), ("そ", ["そ", "ぞ"]),
            ("た", ["た", "だ"]), ("ち", ["ち", "ぢ"]), ("つ", ["つ", "づ"]),
            ("て", ["て", "で"]), ("と", ["と", "ど"]),
            ("は", ["は", "ば", "ぱ"]), ("ひ", ["ひ", "び", "ぴ"]), ("ふ", ["ふ", "ぶ", "ぷ"]),
            ("へ", ["へ", "べ", "ぺ"]), ("ほ", ["ほ", "ぼ", "ぽ"])
        ]
        for (base, expected) in rows {
            try expect(KanaNormalizer.promptCharacters(for: base) == expected, "\(base) 行の表示候補")
        }
        for base: Character in ["あ", "ま", "ん", "ー"] {
            try expect(KanaNormalizer.promptCharacters(for: base) == [base], "\(base) は候補が自分だけ")
        }

        // 表示は全角スペース区切り。
        try expect(KanaNormalizer.promptDisplayText(for: "は") == "は\u{3000}ば\u{3000}ぱ", "は行の表示文字列")
        try expect(KanaNormalizer.promptDisplayText(for: "か") == "か\u{3000}が", "か行の表示文字列")
        try expect(KanaNormalizer.promptDisplayText(for: "あ") == "あ", "候補が1つなら単独表示")
    }

    /// 画面に出す候補と、判定で同じ行とみなす文字が食い違わないことを、ひらがな全体で確かめる。
    private static func testPromptConsistencyAcrossHiragana() throws {
        let smallKana = Set("ぁぃぅぇぉゃゅょっ")
        for value in UInt32(0x3041)...UInt32(0x3096) {
            guard let scalar = Unicode.Scalar(value) else { continue }
            let kana = Character(scalar)
            guard let base = KanaNormalizer.firstCharacter(of: String(kana)) else {
                throw Failure(message: "U+\(String(value, radix: 16)) の正規化結果が空")
            }
            let candidates = KanaNormalizer.promptCharacters(for: base)
            try expect(
                candidates.allSatisfy { KanaNormalizer.firstCharacter(of: String($0)) == base },
                "\(base) の表示候補はすべて同じ行として判定される"
            )
            // 小さいかなは表示に出さない設計。濁音・半濁音は必ず表示候補に含まれる。
            if !smallKana.contains(kana) {
                try expect(candidates.contains(kana), "\(kana) は \(base) の表示候補に含まれる")
            }
        }
    }

    // MARK: - VocabularySelector（プレイヤーの読みの自動決定）

    private static func testVocabularySelector() throws {
        try expect(VocabularySelector.select(from: [], currentPrompt: "あ") == nil, "読みがなければnil")

        // 種類の優先順位は rare > surprise > english > normal。
        let all = [vocab("あさ"), vocab("あめ", .english), vocab("あり", .surprise), vocab("あか", .rare)]
        try expect(VocabularySelector.select(from: all, currentPrompt: "あ")?.word == "あか", "rareを最優先")
        try expect(VocabularySelector.select(from: Array(all.prefix(3)), currentPrompt: "あ")?.word == "あり", "次にsurprise")
        try expect(VocabularySelector.select(from: Array(all.prefix(2)), currentPrompt: "あ")?.word == "あめ", "次にenglish")
        try expect(VocabularySelector.select(from: Array(all.prefix(1)), currentPrompt: "あ")?.word == "あさ", "最後にnormal")
        try expect(
            VocabularySelector.select(from: [vocab("あか", .rare), vocab("あお", .rare)], currentPrompt: "あ")?.word == "あか",
            "同じ種類は登録順"
        )

        // 要求文字に接続できる読みを優先する（濁音も同じ行として接続できる）。
        try expect(
            VocabularySelector.select(from: [vocab("さかな", .rare), vocab("ごま")], currentPrompt: "こ")?.word == "ごま",
            "接続できる読みを種類の優先順位より先に選ぶ"
        )
        try expect(
            VocabularySelector.select(from: [vocab("がっこう")], currentPrompt: "か")?.word == "がっこう",
            "濁音始まりも清音の要求文字に接続"
        )

        // 「ん」で終わる読みは、他に選べる読みがあれば避ける。
        try expect(
            VocabularySelector.select(from: [vocab("あん", .rare), vocab("あさ")], currentPrompt: "あ")?.word == "あさ",
            "「ん」終わりを避ける"
        )
        try expect(
            VocabularySelector.select(from: [vocab("あん", .rare), vocab("あさん")], currentPrompt: "あ")?.word == "あん",
            "すべて「ん」終わりなら種類の優先順位で選ぶ"
        )

        // 接続できる読みがなければ、カード内の全読みから選ぶ（接続失敗の判定は呼び出し側）。
        try expect(
            VocabularySelector.select(from: [vocab("りんご")], currentPrompt: "く")?.word == "りんご",
            "接続できなくても読みを返す"
        )
        try expect(
            VocabularySelector.select(from: [vocab("さん", .rare), vocab("さくら")], currentPrompt: "り")?.word == "さくら",
            "接続できない場合も「ん」終わりを避ける"
        )
    }

    // MARK: - CPUSelector（CPUが選ぶカードと読み）

    private static func testCPUSelector() throws {
        try expect(CPUSelector.select(from: [card([vocab("いぬ")])], currentPrompt: "あ") == nil, "接続できるカードがなければnil")
        try expect(
            CPUSelector.select(from: [card([vocab("あか")], cleared: true)], currentPrompt: "あ") == nil,
            "取得済みカードは対象外"
        )

        // 種類の優先順位は normal > english > surprise > rare。
        let rare = card([vocab("あか", .rare)])
        let surprise = card([vocab("あひ", .surprise)])
        let english = card([vocab("あめ", .english)])
        let normal = card([vocab("あお")])
        let steps: [(cards: [Card], expected: Card, word: String)] = [
            ([rare, surprise, english, normal], normal, "あお"),
            ([rare, surprise, english], english, "あめ"),
            ([rare, surprise], surprise, "あひ"),
            ([rare], rare, "あか")
        ]
        for step in steps {
            let result = CPUSelector.select(from: step.cards, currentPrompt: "あ")
            try expect(
                result?.card.id == step.expected.id && result?.vocabulary.word == step.word,
                "CPUは \(step.word) を選ぶ"
            )
        }

        let first = card([vocab("あか")])
        let second = card([vocab("あお")])
        try expect(
            CPUSelector.select(from: [first, second], currentPrompt: "あ")?.card.id == first.id,
            "同じ種類は登録順のカード"
        )

        // 「ん」で終わる読みは避け、避けられなければ種類の優先順位で選ぶ。
        let nEnding = card([vocab("あん")])
        let safeRare = card([vocab("あか", .rare)])
        try expect(
            CPUSelector.select(from: [nEnding, safeRare], currentPrompt: "あ")?.card.id == safeRare.id,
            "「ん」終わりのnormalより、安全なrareを選ぶ"
        )
        let nNormal = card([vocab("あまん")])
        let nRare = card([vocab("あん", .rare)])
        try expect(
            CPUSelector.select(from: [nRare, nNormal], currentPrompt: "あ")?.card.id == nNormal.id,
            "すべて「ん」終わりならnormalを選ぶ"
        )

        try expect(
            CPUSelector.select(from: [card([vocab("ばなな")])], currentPrompt: "は")?.vocabulary.word == "ばなな",
            "濁音始まりも清音の要求文字に接続"
        )
    }

    // MARK: - MessageSelector

    private static func testMessageSelector() throws {
        let types: [WordType] = [.normal, .english, .surprise, .rare]
        for stage in [ShiritoriStageType.normal, .trial] {
            for type in types {
                // 読みではなく表示用の語がメッセージに使われることを確かめるため、別の語を渡す。
                let vocabulary = Vocabulary(word: "ひらがな", displayWord: "表示語", type: type)
                try expect(
                    MessageSelector.playerMessage(for: vocabulary, stage: stage).contains("表示語"),
                    "取得メッセージに表示語を含む (\(stage), \(type))"
                )
                let messages = MessageSelector.cpuMessages(for: vocabulary, stage: stage)
                try expect(
                    !messages.isEmpty && messages.allSatisfy { $0.contains("表示語") },
                    "CPUメッセージ候補はすべて表示語を含む (\(stage), \(type))"
                )

                let withPrompt = MessageSelector.cpuMessageWithNextPrompt(for: vocabulary, nextPrompt: "は", stage: stage)
                try expect(
                    withPrompt.contains("表示語") && withPrompt.contains("は\u{3000}ば\u{3000}ぱ"),
                    "次の文字の全候補を案内する (\(stage), \(type))"
                )
                let withoutPrompt = MessageSelector.cpuMessageWithNextPrompt(for: vocabulary, nextPrompt: nil, stage: stage)
                try expect(messages.contains(withoutPrompt), "次の文字がなければ候補メッセージのみ (\(stage), \(type))")
            }
        }
    }

    // MARK: - カードデータ（編集ミスを検出する）

    private static func isHiraganaOrLongVowelMark(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy {
            ($0.value >= 0x3041 && $0.value <= 0x3096) || $0.value == 0x30FC
        }
    }

    private static func testCardData() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let decks: [(name: String, cards: [Card])] = [
            ("CardData（通常）", CardData.cards),
            ("CardData2（試練）", CardData2.cards)
        ]

        for deck in decks {
            try expect(deck.cards.count == 25, "\(deck.name): 25枚")
            try expect(Set(deck.cards.map(\.imageName)).count == 25, "\(deck.name): 画像名が重複しない")

            for card in deck.cards {
                let label = "\(deck.name) \(card.imageName)"
                try expect(!card.isCleared, "\(label): 初期状態は未取得")
                try expect(card.vocabularies.filter { $0.type == .normal }.count == 1, "\(label): 通常読みがちょうど1つ")

                let words = card.vocabularies.map(\.word)
                try expect(Set(words).count == words.count, "\(label): 同じ読みを重複登録しない")
                try expect(
                    words.contains { !KanaNormalizer.endsWithN($0) },
                    "\(label): 「ん」で終わらない読みが1つ以上ある"
                )

                for vocabulary in card.vocabularies {
                    let word = vocabulary.word
                    try expect(
                        !word.isEmpty && word.allSatisfy(isHiraganaOrLongVowelMark),
                        "\(label): 読み「\(word)」はひらがなと長音だけ"
                    )
                    try expect(!vocabulary.displayWord.isEmpty, "\(label): 表示語が空でない")
                    let head = KanaNormalizer.firstCharacter(of: word)
                    try expect(head != nil && head != "ん" && head != "ー", "\(label): 「\(word)」は先頭で詰まない")
                }

                // 画像がAsset Catalogに存在し、中身がある。
                let imageset = repoRoot
                    .appendingPathComponent("Map/ShiritoriAssets.xcassets/\(card.imageName).imageset")
                let files = (try? FileManager.default.contentsOfDirectory(atPath: imageset.path)) ?? []
                try expect(
                    files.contains { $0 != "Contents.json" },
                    "\(label): 画像アセットが存在する"
                )
            }
        }

        // 通常版は、通常読みだけで25枚を一巡できる設計。語の差し替えで壊れないようにする。
        let normalWords = CardData.cards.compactMap { card in
            card.vocabularies.first { $0.type == .normal }?.word
        }
        try expect(normalWords.count == 25, "通常版: 全カードに通常読みがある")
        try expect(normalWords.allSatisfy { !KanaNormalizer.endsWithN($0) }, "通常版: 通常読みは「ん」で終わらない")
        try expect(normalWordsFormOneLoop(normalWords), "通常版: 通常読みの接続が25枚で一巡できる")

        // デッキ全体の読みの接続性を数値化し、ランダムステージ用デッキの比較材料を出す。
        // これは全読みを使った静的指標であり、実対戦の残り枚数を保証するものではない。
        let normalMetrics = deckConnectivityMetrics(CardData.cards)
        let trialMetrics = deckConnectivityMetrics(CardData2.cards)
        print("DECK-COMPARE CardData: readings=\(normalMetrics.readings), nEnding=\(normalMetrics.nEnding), deadEndReadings=\(normalMetrics.deadEnds), avgFollowUps=\(String(format: "%.2f", normalMetrics.averageFollowUps))")
        print("DECK-COMPARE CardData2: readings=\(trialMetrics.readings), nEnding=\(trialMetrics.nEnding), deadEndReadings=\(trialMetrics.deadEnds), avgFollowUps=\(String(format: "%.2f", trialMetrics.averageFollowUps))")
    }

    private static func deckConnectivityMetrics(_ cards: [Card]) -> (readings: Int, nEnding: Int, deadEnds: Int, averageFollowUps: Double) {
        let words = cards.flatMap { $0.vocabularies.map(\.word) }
        let startingCharacters = words.compactMap { KanaNormalizer.firstCharacter(of: $0) }
        let startingCounts = startingCharacters.reduce(into: [Character: Int]()) { counts, character in
            counts[character, default: 0] += 1
        }
        let followUpCounts = words.compactMap { KanaNormalizer.lastCharacter(of: $0) }.map {
            startingCounts[$0, default: 0]
        }
        let deadEnds = followUpCounts.filter { $0 == 0 }.count
        return (
            readings: words.count,
            nEnding: words.filter { KanaNormalizer.endsWithN($0) }.count,
            deadEnds: deadEnds,
            averageFollowUps: followUpCounts.isEmpty ? 0 : Double(followUpCounts.reduce(0, +)) / Double(followUpCounts.count)
        )
    }

    /// 各語を「先頭文字→末尾文字」の辺とみなし、全辺を使う閉じた経路があるか（次数の釣り合いと連結）を確かめる。
    private static func normalWordsFormOneLoop(_ words: [String]) -> Bool {
        var outDegree: [Character: Int] = [:]
        var inDegree: [Character: Int] = [:]
        var neighbors: [Character: Set<Character>] = [:]
        for word in words {
            guard let head = KanaNormalizer.firstCharacter(of: word),
                  let tail = KanaNormalizer.lastCharacter(of: word) else { return false }
            outDegree[head, default: 0] += 1
            inDegree[tail, default: 0] += 1
            neighbors[head, default: []].insert(tail)
            neighbors[tail, default: []].insert(head)
        }
        let nodes = Set(outDegree.keys).union(inDegree.keys)
        guard nodes.allSatisfy({ outDegree[$0, default: 0] == inDegree[$0, default: 0] }),
              let start = nodes.first else { return false }

        var visited: Set<Character> = [start]
        var stack = [start]
        while let current = stack.popLast() {
            for next in neighbors[current, default: []] {
                if visited.insert(next).inserted { stack.append(next) }
            }
        }
        return visited == nodes
    }
}
