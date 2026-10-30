//
//  CardData_Phase17_読み反映版.swift
//  shiritori
//
//  Created by cmStudent on 2026/10/06.
//

import Foundation

// ゲームで使用する25枚のカードデータを管理する
struct CardData {

    // ゲームで使用する25枚のカード
    // 通常読みは各カード1種類に固定し、25枚で一巡できるようにする。
    // 特殊読みは英語・レア・サプライズに分類し、画像から連想できる読みを登録する。
    static let cards: [Card] = [
        Card(id: UUID(), imageName: "card01", vocabularies: [
            Vocabulary(word: "りんご", displayWord: "りんご", type: .normal),
            Vocabulary(word: "あっぷる", displayWord: "あっぷる", type: .english),
            Vocabulary(word: "ふるーつ", displayWord: "ふるーつ", type: .english),
            Vocabulary(word: "くだもの", displayWord: "くだもの", type: .english),
            Vocabulary(word: "あかりんご", displayWord: "あかりんご", type: .rare),
            Vocabulary(word: "きのみ", displayWord: "きのみ", type: .surprise)
        ], isCleared: false),

        Card(id: UUID(), imageName: "card02", vocabularies: [
            Vocabulary(word: "こぶた", displayWord: "こぶた", type: .normal),
            Vocabulary(word: "ぴぐれっと", displayWord: "ぴぐれっと", type: .english),
            Vocabulary(word: "ぶた", displayWord: "ぶた", type: .rare),
            Vocabulary(word: "ぺっと", displayWord: "ぺっと", type: .rare),
            Vocabulary(word: "どうぶつ", displayWord: "どうぶつ", type: .rare),
            Vocabulary(word: "ぬいぐるみ", displayWord: "ぬいぐるみ", type: .surprise),
            Vocabulary(word: "ちょきんばこ", displayWord: "ちょきんばこ", type: .surprise)
        ], isCleared: false),

        Card(id: UUID(), imageName: "card03", vocabularies: [
            Vocabulary(word: "だるま", displayWord: "だるま", type: .normal),
            Vocabulary(word: "ごうかく", displayWord: "ごうかく", type: .rare),
            Vocabulary(word: "おきもの", displayWord: "おきもの", type: .rare),
            Vocabulary(word: "えんぎもの", displayWord: "えんぎもの", type: .rare),
            Vocabulary(word: "がんかけ", displayWord: "がんかけ", type: .rare)
        ], isCleared: false),

        Card(id: UUID(), imageName: "card04", vocabularies: [
            Vocabulary(word: "まど", displayWord: "まど", type: .normal),
            Vocabulary(word: "うぃんどう", displayWord: "うぃんどう", type: .english),
            Vocabulary(word: "かーてん", displayWord: "かーてん", type: .rare),
            Vocabulary(word: "なかまど", displayWord: "なかまど", type: .rare),
            Vocabulary(word: "がらす", displayWord: "がらす", type: .rare)
        ], isCleared: false),

        Card(id: UUID(), imageName: "card05", vocabularies: [
            Vocabulary(word: "どあ", displayWord: "どあ", type: .normal),
            Vocabulary(word: "いりぐち", displayWord: "いりぐち", type: .rare),
            Vocabulary(word: "でぐち", displayWord: "でぐち", type: .rare),
            Vocabulary(word: "げんかん", displayWord: "げんかん", type: .rare),
            Vocabulary(word: "のぶ", displayWord: "のぶ", type: .surprise)
        ], isCleared: false),

        Card(id: UUID(), imageName: "card06", vocabularies: [
            Vocabulary(word: "あさひ", displayWord: "あさひ", type: .normal),
            Vocabulary(word: "さんらいず", displayWord: "さんらいず", type: .english),
            Vocabulary(word: "ひので", displayWord: "ひので", type: .rare),
            Vocabulary(word: "たいよう", displayWord: "たいよう", type: .rare),
            Vocabulary(word: "うみ", displayWord: "うみ", type: .surprise),
            Vocabulary(word: "すいへいせん", displayWord: "すいへいせん", type: .surprise)
        ], isCleared: false),

        Card(id: UUID(), imageName: "card07", vocabularies: [
            Vocabulary(word: "ひとり", displayWord: "ひとり", type: .normal),
            Vocabulary(word: "わん", displayWord: "わん", type: .english),
            Vocabulary(word: "きっず", displayWord: "きっず", type: .english),
            Vocabulary(word: "しょうねん", displayWord: "しょうねん", type: .rare),
            Vocabulary(word: "こども", displayWord: "こども", type: .surprise),
            Vocabulary(word: "がき", displayWord: "がき", type: .surprise),
            Vocabulary(word: "おとこのこ", displayWord: "おとこのこ", type: .surprise)
        ], isCleared: false),

        Card(id: UUID(), imageName: "card08", vocabularies: [
            Vocabulary(word: "りょうり", displayWord: "りょうり", type: .normal),
            Vocabulary(word: "くっきんぐ", displayWord: "くっきんぐ", type: .english),
            Vocabulary(word: "ちょうり", displayWord: "ちょうり", type: .rare),
            Vocabulary(word: "しょくじ", displayWord: "しょくじ", type: .rare),
            Vocabulary(word: "めだまやき", displayWord: "めだまやき", type: .surprise),
            Vocabulary(word: "ごちそう", displayWord: "ごちそう", type: .surprise),
            Vocabulary(word: "ふらいぱん", displayWord: "ふらいぱん", type: .surprise)
        ], isCleared: false),

        Card(id: UUID(), imageName: "card09", vocabularies: [
            Vocabulary(word: "りす", displayWord: "りす", type: .normal),
            Vocabulary(word: "すくわーれる", displayWord: "すくわーれる", type: .english),
            Vocabulary(word: "きのみ", displayWord: "きのみ", type: .rare),
            Vocabulary(word: "しっぽ", displayWord: "しっぽ", type: .rare),
            Vocabulary(word: "ぺっと", displayWord: "ぺっと", type: .rare),
            Vocabulary(word: "どうぶつ", displayWord: "どうぶつ", type: .rare),
            Vocabulary(word: "ぬいぐるみ", displayWord: "ぬいぐるみ", type: .surprise)
        ], isCleared: false),

        Card(id: UUID(), imageName: "card10", vocabularies: [
            Vocabulary(word: "すずめ", displayWord: "すずめ", type: .normal),
            Vocabulary(word: "やちょう", displayWord: "やちょう", type: .rare),
            Vocabulary(word: "ことり", displayWord: "ことり", type: .rare),
            Vocabulary(word: "どうぶつ", displayWord: "どうぶつ", type: .rare),
            Vocabulary(word: "えだ", displayWord: "えだ", type: .surprise),
            Vocabulary(word: "ぬいぐるみ", displayWord: "ぬいぐるみ", type: .surprise),
            Vocabulary(word: "つばさ", displayWord: "つばさ", type: .surprise)
        ], isCleared: false),

        Card(id: UUID(), imageName: "card11", vocabularies: [
            Vocabulary(word: "めいろ", displayWord: "めいろ", type: .normal),
            Vocabulary(word: "まよいみち", displayWord: "まよいみち", type: .rare),
            Vocabulary(word: "ごーる", displayWord: "ごーる", type: .rare),
            Vocabulary(word: "すたーと", displayWord: "すたーと", type: .rare),
            Vocabulary(word: "ふらっぐ", displayWord: "ふらっぐ", type: .surprise),
            Vocabulary(word: "るーと", displayWord: "るーと", type: .surprise),
            Vocabulary(word: "はた", displayWord: "はた", type: .surprise),
            Vocabulary(word: "いけがき", displayWord: "いけがき", type: .surprise)
        ], isCleared: false),

        Card(id: UUID(), imageName: "card12", vocabularies: [
            Vocabulary(word: "ろうそく", displayWord: "ろうそく", type: .normal),
            Vocabulary(word: "きゃんどる", displayWord: "きゃんどる", type: .english),
            Vocabulary(word: "あかり", displayWord: "あかり", type: .rare),
            Vocabulary(word: "しょくだい", displayWord: "しょくだい", type: .rare),
            Vocabulary(word: "ともしび", displayWord: "ともしび", type: .rare),
            Vocabulary(word: "ほのお", displayWord: "ほのお", type: .surprise),
            Vocabulary(word: "ひ", displayWord: "ひ", type: .surprise)
        ], isCleared: false),

        Card(id: UUID(), imageName: "card13", vocabularies: [
            Vocabulary(word: "くつ", displayWord: "くつ", type: .normal),
            Vocabulary(word: "しゅーず", displayWord: "しゅーず", type: .english),
            Vocabulary(word: "はきもの", displayWord: "はきもの", type: .rare),
            Vocabulary(word: "すにーかー", displayWord: "すにーかー", type: .rare)
        ], isCleared: false),

        Card(id: UUID(), imageName: "card14", vocabularies: [
            Vocabulary(word: "つき", displayWord: "つき", type: .normal),
            Vocabulary(word: "むーん", displayWord: "むーん", type: .english),
            Vocabulary(word: "ふるむーん", displayWord: "ふるむーん", type: .english),
            Vocabulary(word: "まんげつ", displayWord: "まんげつ", type: .rare),
            Vocabulary(word: "おつきみ", displayWord: "おつきみ", type: .rare),
            Vocabulary(word: "じゅうごや", displayWord: "じゅうごや", type: .rare),
            Vocabulary(word: "よぞら", displayWord: "よぞら", type: .surprise)
        ], isCleared: false),

        Card(id: UUID(), imageName: "card15", vocabularies: [
            Vocabulary(word: "きつね", displayWord: "きつね", type: .normal),
            Vocabulary(word: "ふぉっくす", displayWord: "ふぉっくす", type: .english),
            Vocabulary(word: "こぎつね", displayWord: "こぎつね", type: .rare),
            Vocabulary(word: "どうぶつ", displayWord: "どうぶつ", type: .rare),
            Vocabulary(word: "ぬいぐるみ", displayWord: "ぬいぐるみ", type: .surprise),
            Vocabulary(word: "おすわり", displayWord: "おすわり", type: .surprise),
            Vocabulary(word: "のぎつね", displayWord: "のぎつね", type: .surprise)
        ], isCleared: false),

        Card(id: UUID(), imageName: "card16", vocabularies: [
            Vocabulary(word: "ねこ", displayWord: "ねこ", type: .normal),
            Vocabulary(word: "きゃっと", displayWord: "きゃっと", type: .english),
            Vocabulary(word: "こねこ", displayWord: "こねこ", type: .rare),
            Vocabulary(word: "ぺっと", displayWord: "ぺっと", type: .rare),
            Vocabulary(word: "どうぶつ", displayWord: "どうぶつ", type: .rare),
            Vocabulary(word: "おすわり", displayWord: "おすわり", type: .surprise),
            Vocabulary(word: "ぬいぐるみ", displayWord: "ぬいぐるみ", type: .surprise),
            Vocabulary(word: "にゃんこ", displayWord: "にゃんこ", type: .surprise),
            Vocabulary(word: "のらねこ", displayWord: "のらねこ", type: .surprise)
        ], isCleared: false),

        Card(id: UUID(), imageName: "card17", vocabularies: [
            Vocabulary(word: "こま", displayWord: "こま", type: .normal),
            Vocabulary(word: "すぴん", displayWord: "すぴん", type: .english),
            Vocabulary(word: "おもちゃ", displayWord: "おもちゃ", type: .rare),
            Vocabulary(word: "いと", displayWord: "いと", type: .rare),
            Vocabulary(word: "ひも", displayWord: "ひも", type: .rare),
            Vocabulary(word: "くるくる", displayWord: "くるくる", type: .surprise),
            Vocabulary(word: "かいてん", displayWord: "かいてん", type: .surprise)
        ], isCleared: false),

        Card(id: UUID(), imageName: "card18", vocabularies: [
            Vocabulary(word: "まくら", displayWord: "まくら", type: .normal),
            Vocabulary(word: "ぴろー", displayWord: "ぴろー", type: .english),
            Vocabulary(word: "しんぐ", displayWord: "しんぐ", type: .rare),
            Vocabulary(word: "すいみん", displayWord: "すいみん", type: .rare),
            Vocabulary(word: "おやすみ", displayWord: "おやすみ", type: .surprise)
        ], isCleared: false),

        Card(id: UUID(), imageName: "card19", vocabularies: [
            Vocabulary(word: "らじお", displayWord: "らじお", type: .normal),
            Vocabulary(word: "れでぃお", displayWord: "れでぃお", type: .english),
            Vocabulary(word: "じゅしんき", displayWord: "じゅしんき", type: .rare),
            Vocabulary(word: "あんてな", displayWord: "あんてな", type: .rare),
            Vocabulary(word: "きかい", displayWord: "きかい", type: .rare),
            Vocabulary(word: "でんぱ", displayWord: "でんぱ", type: .rare),
            Vocabulary(word: "ほうそう", displayWord: "ほうそう", type: .rare),
            Vocabulary(word: "おんがく", displayWord: "おんがく", type: .rare),
            Vocabulary(word: "にゅーす", displayWord: "にゅーす", type: .rare),
            Vocabulary(word: "ばんぐみ", displayWord: "ばんぐみ", type: .surprise)
        ], isCleared: false),

        Card(id: UUID(), imageName: "card20", vocabularies: [
            Vocabulary(word: "おとな", displayWord: "おとな", type: .normal),
            Vocabulary(word: "あだると", displayWord: "あだると", type: .english),
            Vocabulary(word: "びじねすまん", displayWord: "びじねすまん", type: .english),
            Vocabulary(word: "すーつ", displayWord: "すーつ", type: .rare),
            Vocabulary(word: "だんせい", displayWord: "だんせい", type: .rare),
            Vocabulary(word: "ねくたい", displayWord: "ねくたい", type: .rare),
            Vocabulary(word: "さむずあっぷ", displayWord: "さむずあっぷ", type: .surprise),
            Vocabulary(word: "ないすがい", displayWord: "ないすがい", type: .surprise),
            Vocabulary(word: "らっきー", displayWord: "らっきー", type: .surprise),
            Vocabulary(word: "いけめん", displayWord: "いけめん", type: .surprise),
            Vocabulary(word: "のーぷろぶれむ", displayWord: "のーぷろぶれむ", type: .surprise),
            Vocabulary(word: "ろうどうしゃ", displayWord: "ろうどうしゃ", type: .surprise),
        ], isCleared: false),

        Card(id: UUID(), imageName: "card21", vocabularies: [
            Vocabulary(word: "なす", displayWord: "なす", type: .normal),
            Vocabulary(word: "えっぐぷらんと", displayWord: "えっぐぷらんと", type: .english),
            Vocabulary(word: "やさい", displayWord: "やさい", type: .rare),
            Vocabulary(word: "むらさき", displayWord: "むらさき", type: .rare),
            Vocabulary(word: "つけもの", displayWord: "つけもの", type: .surprise),
            Vocabulary(word: "みずなす", displayWord: "みずなす", type: .surprise),
            Vocabulary(word: "こなす", displayWord: "こなす", type: .surprise),
            Vocabulary(word: "あきなす", displayWord: "あきなす", type: .surprise),
        ], isCleared: false),

        Card(id: UUID(), imageName: "card22", vocabularies: [
            Vocabulary(word: "すいか", displayWord: "すいか", type: .normal),
            Vocabulary(word: "うぉーたーめろん", displayWord: "うぉーたーめろん", type: .english),
            Vocabulary(word: "やさい", displayWord: "やさい", type: .rare),
            Vocabulary(word: "しましま", displayWord: "しましま", type: .surprise),
            Vocabulary(word: "たね", displayWord: "たね", type: .surprise)
        ], isCleared: false),

        Card(id: UUID(), imageName: "card23", vocabularies: [
            Vocabulary(word: "がっこう", displayWord: "がっこう", type: .normal),
            Vocabulary(word: "すくーる", displayWord: "すくーる", type: .english),
            Vocabulary(word: "たてもの", displayWord: "たてもの", type: .rare),
            Vocabulary(word: "こうしゃ", displayWord: "こうしゃ", type: .rare),
            Vocabulary(word: "はた", displayWord: "はた", type: .surprise),
            Vocabulary(word: "とけい", displayWord: "とけい", type: .surprise)
        ], isCleared: false),

        Card(id: UUID(), imageName: "card24", vocabularies: [
            Vocabulary(word: "うま", displayWord: "うま", type: .normal),
            Vocabulary(word: "ほーす", displayWord: "ほーす", type: .english),
            Vocabulary(word: "さらぶれっと", displayWord: "さらぶれっと", type: .rare),
            Vocabulary(word: "やせいば", displayWord: "やせいば", type: .rare),
            Vocabulary(word: "どうぶつ", displayWord: "どうぶつ", type: .rare)
        ], isCleared: false),

        Card(id: UUID(), imageName: "card25", vocabularies: [
            Vocabulary(word: "まつり", displayWord: "まつり", type: .normal),
            Vocabulary(word: "ふぇすてぃばる", displayWord: "ふぇすてぃばる", type: .english),
            Vocabulary(word: "みこし", displayWord: "みこし", type: .rare),
            Vocabulary(word: "ちょうちん", displayWord: "ちょうちん", type: .rare),
            Vocabulary(word: "おまつり", displayWord: "おまつり", type: .rare),
            Vocabulary(word: "はっぴ", displayWord: "はっぴ", type: .rare),
            Vocabulary(word: "いせい", displayWord: "いせい", type: .surprise)
        ], isCleared: false)
    ]
}
