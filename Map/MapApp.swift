//
//  MapApp.swift
//  Map
//
//  Created by cmStudent on 2026/09/28.
//

import SwiftUI
import CoreText
import FirebaseCore

/// 画面全体の文字サイズをまとめて調整する。
enum DungeonTypography {
    static let readabilityScale: CGFloat = 1.18

    static func maruMonica(size: CGFloat) -> Font {
        .custom("x12y16pxMaruMonica", size: size * readabilityScale)
    }

    static func system(
        size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> Font {
        .system(size: size * readabilityScale, weight: weight, design: design)
    }
}

@main
struct MapApp: App {
    init() {
        // Firebase設定ファイルがある場合だけ初期化する。
        // 未設定・未接続でも端末内ランキングで通常どおり遊べる。
        if FirebaseApp.app() == nil,
           Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") != nil {
            FirebaseApp.configure()
        }
        guard let fontURL = Bundle.main.url(forResource: "x12y16pxMaruMonica", withExtension: "ttf") else { return }
        CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, nil)
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if CommandLine.arguments.contains("--enemy-remains-preview") {
                EnemyRemainsPreview()
            } else if CommandLine.arguments.contains("--enemy-motion-preview") {
                EnemyMotionPreview()
            } else {
                ContentView()
            }
            #else
            ContentView()
            #endif
        }
    }
}
