//
//  SoundEffectManager.swift
//  shiritori
//
//  効果音・BGMの再生を一元管理する
//

import Foundation
import AVFoundation
import UIKit

/// 効果音とBGMの再生を一元管理するクラス
final class SoundEffectManager: NSObject, AVAudioPlayerDelegate {

    /// しりとり画面のBGM・効果音をアプリ内音量50%で再生する。
    private let backgroundMusicVolume: Float = 0.5
    private let soundEffectVolume: Float = 0.5

    /// アプリ全体で共通して使用する効果音管理インスタンス
    static let shared = SoundEffectManager()

    /// 短い効果音を連続再生した場合でも、再生途中で破棄されないようにする
    private var activePlayers: [AVAudioPlayer] = []

    /// 現在再生中のBGMプレイヤー
    private var bgmPlayer: AVAudioPlayer?

    /// 現在再生中のBGM番号
    /// 1 = BGM1、2 = BGM2
    private var currentBGMNumber: Int = 0

    /// BGM1からBGM2へ移行する際のフェードタイマー
    private var bgmFadeTimer: Timer?

    /// 残り12枚の条件を満たした後、BGM2を永久ループさせるかどうか
    private var isBGM2LockedPermanently = false

    /// 外部から直接インスタンスを作成しない
    private override init() {
        super.init()
    }

    /// 指定したData Setの音声を効果音として再生する
    /// - Parameter assetName: Assets.xcassets内のData Set名
    private func play(assetName: String, volume: Float? = nil) {
        guard let asset = NSDataAsset(name: assetName) else {
            return
        }

        do {
            let player = try AVAudioPlayer(data: asset.data)
            player.volume = volume ?? soundEffectVolume
            player.prepareToPlay()
            player.play()

            activePlayers.append(player)
            activePlayers.removeAll { !$0.isPlaying }

        } catch {
            return
        }
    }

    /// プレイヤー・CPUのカーソル移動音を再生する
    func playCursor() {
        play(assetName: "shiritori_card_cursor_01")
    }

    /// しりとりでカードを選んだ時の軽い触覚を返す。
    /// CPUのスキャン移動ではなく、カード選択が確定した時に呼び出す。
    func playCardSelectionHaptic() {
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }

    /// 画面上のボタン押下音を再生する。既存の短いUIカーソル音を共用する。
    func playButtonTap() {
        play(assetName: "shiritori_card_cursor_01")
    }

    /// メッセージを一文字表示するたびに鳴らす効果音を再生する
    func playMessageBeep() {
        play(assetName: "shiritori_message_beep")
    }

    /// 正解音を再生する
    func playSuccess() {
        play(assetName: "shiritori_seikai_pop_v3")
    }

    /// 不正解音を再生する
    func playFailure() {
        play(assetName: "shiritori_fuseikai_pop_v3")
    }

    /// PLAYER敗北メッセージの表示完了後に、敗北用BGMを1回だけ再生する
    func playDefeatBGMOnce() {
        // 共通再生処理はループ設定を行わないため、音源を最後まで1回だけ再生する
        play(assetName: "shiritori_defeat_death_bgm_3sec")
    }

    // MARK: - プロローグBGM

    /// プロローグ専用BGMを1回だけ再生する
    func startPrologueBGM() {

        // すでに再生中のBGMを停止する
        stopBGM()

        // Assets.xcassets内のプロローグBGMを取得する
        guard let asset = NSDataAsset(
            name: "nes_boss_15sec_rhythmic"
        ) else {
            return
        }

        do {
            let player = try AVAudioPlayer(data: asset.data)

            player.volume = backgroundMusicVolume

            // プロローグBGMはループさせない
            player.numberOfLoops = 0

            player.prepareToPlay()

            bgmPlayer = player
            player.play()

        } catch {
            bgmPlayer = nil
        }
    }

    /// プロローグBGMを停止する
    func stopPrologueBGM() {
        bgmPlayer?.stop()
        bgmPlayer = nil
        currentBGMNumber = 0
    }

    // MARK: - ゲーム中BGM

    /// しりとりゲーム中のBGMをBGM1から開始する
    /// BGM1終了後はBGM2、BGM2終了後はBGM1へ戻り、繰り返し再生する
    func startBGM() {
        print("[ShiritoriBGM-DIAG] startBGM called")
        stopBGM()
        currentBGMNumber = 1
        playCurrentBGM()
    }

    /// 現在のBGMを停止する
    func stopBGM() {
        // 診断用：BGM停止がどのタイミングで呼ばれたかを確認する
        print("[ShiritoriBGM-DIAG] stopBGM called; currentBGMNumber=\(currentBGMNumber), isPlaying=\(bgmPlayer?.isPlaying ?? false)")
        // BGMを停止する際は、フェード処理と固定ループ設定も解除する
        bgmFadeTimer?.invalidate()
        bgmFadeTimer = nil
        isBGM2LockedPermanently = false
        bgmPlayer?.stop()
        bgmPlayer = nil
        currentBGMNumber = 0
    }

    /// 残り12枚になった時点でBGM2へ移行し、以後はBGM2だけをループする
    /// BGM1が再生中なら指定秒数をかけて音量を下げ、終了後にBGM2へ切り替える。
    func switchToBGM2Permanently(fadeOutDuration: TimeInterval = 3.0) {
        // 同じ条件が重複して通知されても、切り替え処理を再実行しない
        guard !isBGM2LockedPermanently else { return }
        isBGM2LockedPermanently = true

        bgmFadeTimer?.invalidate()
        bgmFadeTimer = nil

        // BGM2が既に流れている場合は、フェードせずBGM2の無限ループに固定する
        if currentBGMNumber == 2, let player = bgmPlayer, player.isPlaying {
            player.numberOfLoops = -1
            return
        }

        // BGM1が流れていない場合は、直ちにBGM2を開始する
        guard currentBGMNumber == 1,
              let player = bgmPlayer,
              player.isPlaying,
              fadeOutDuration > 0 else {
            bgmPlayer?.stop()
            bgmPlayer = nil
            currentBGMNumber = 2
            playCurrentBGM()
            return
        }

        let startingVolume = player.volume
        let fadeStartDate = Date()

        // 音量を一定間隔で少しずつ下げ、指定秒数後にBGM2へ切り替える
        bgmFadeTimer = Timer.scheduledTimer(
            withTimeInterval: 0.05,
            repeats: true
        ) { [weak self, weak player] timer in
            guard let self, let player else {
                timer.invalidate()
                return
            }
            guard self.bgmPlayer === player,
                  self.isBGM2LockedPermanently else {
                timer.invalidate()
                return
            }

            let elapsed = Date().timeIntervalSince(fadeStartDate)
            let progress = min(max(elapsed / fadeOutDuration, 0), 1)
            player.volume = startingVolume * Float(1 - progress)

            if progress >= 1 {
                self.finishBGM2Transition(from: player)
            }
        }
    }

    /// BGM1のフェードが終わったときに、永久ループするBGM2を開始する
    private func finishBGM2Transition(from previousPlayer: AVAudioPlayer) {
        bgmFadeTimer?.invalidate()
        bgmFadeTimer = nil

        // 古いプレイヤーからの完了通知が新しいBGMに影響しないよう確認する
        guard bgmPlayer === previousPlayer else { return }

        previousPlayer.stop()
        bgmPlayer = nil
        currentBGMNumber = 2
        playCurrentBGM()
    }

    /// 現在のBGM番号に対応するData Setを再生する
    private func playCurrentBGM() {
        let assetName: String

        switch currentBGMNumber {
        case 1:
            assetName = "shiritoriBGM1"

        case 2:
            assetName = "shiritoriBGM2"

        default:
            return
        }

        print("[ShiritoriBGM-DIAG] requesting asset: \(assetName)")
        guard let asset = NSDataAsset(name: assetName) else {
            print("[ShiritoriBGM-DIAG] ERROR: NSDataAsset not found: \(assetName)")
            return
        }
        print("[ShiritoriBGM-DIAG] asset loaded: \(assetName), bytes=\(asset.data.count)")

        do {
            let player = try AVAudioPlayer(data: asset.data)
            print("[ShiritoriBGM-DIAG] AVAudioPlayer created: \(assetName), duration=\(player.duration)")
            player.volume = backgroundMusicVolume

            // 切り替え条件成立後のBGM2は、音源終了時に戻らず無限ループさせる
            if currentBGMNumber == 2 && isBGM2LockedPermanently {
                player.numberOfLoops = -1
            }

            // BGM1のみ、試験的に1.1倍速で再生する。BGM2は通常速度を維持する
            if currentBGMNumber == 1 {
                player.enableRate = true
                player.rate = 1.1
            }
            
            player.delegate = self
            let prepared = player.prepareToPlay()
            print("[ShiritoriBGM-DIAG] prepareToPlay=\(prepared), number=\(currentBGMNumber), rate=\(player.rate)")

            bgmPlayer = player
            let started = player.play()
            print("[ShiritoriBGM-DIAG] play() returned=\(started), isPlaying=\(player.isPlaying), number=\(currentBGMNumber)")

            // 診断専用：再生開始後も再生位置・音量・出力先が正常か確認する。
            // 再生処理やゲーム動作そのものは変更しない。
            for delay: TimeInterval in [2.0, 5.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak player] in
                    guard let self, let player else {
                        print("[ShiritoriBGM-DIAG] after \(delay)s: player released")
                        return
                    }

                    let ownsPlayer = self.bgmPlayer === player
                    let session = AVAudioSession.sharedInstance()
                    let outputs = session.currentRoute.outputs
                        .map { "\($0.portType.rawValue):\($0.portName)" }
                        .joined(separator: ", ")

                    print(
                        "[ShiritoriBGM-DIAG] after \(delay)s: " +
                        "currentTime=\(player.currentTime), duration=\(player.duration), " +
                        "volume=\(player.volume), isPlaying=\(player.isPlaying), " +
                        "managerOwnsPlayer=\(ownsPlayer), systemOutputVolume=\(session.outputVolume), " +
                        "outputs=[\(outputs)]"
                    )
                }
            }

        } catch {
            print("[ShiritoriBGM-DIAG] ERROR creating BGM player for \(assetName): \(error)")
            bgmPlayer = nil
        }
    }

    /// BGM1またはBGM2の再生終了時に、次のBGMへ切り替える
    func audioPlayerDidFinishPlaying(
        _ player: AVAudioPlayer,
        successfully flag: Bool
    ) {
        print("[ShiritoriBGM-DIAG] didFinishPlaying success=\(flag), currentNumber=\(currentBGMNumber), currentPlayerMatches=\(player === bgmPlayer)")
        guard player === bgmPlayer else {
            return
        }

        // BGM2固定モード中はBGM1へ戻さない
        if isBGM2LockedPermanently {
            if currentBGMNumber == 1 {
                // フェード中にBGM1が自然終了した場合は、BGM2へ即時移行する
                finishBGM2Transition(from: player)
            } else if currentBGMNumber == 2 {
                // 万一BGM2の終了通知が来ても、BGM2を再び開始する
                playCurrentBGM()
            }
            return
        }

        // 通常時はBGM1 → BGM2 → BGM1 の順番で繰り返す
        if currentBGMNumber == 1 {
            currentBGMNumber = 2
        } else {
            currentBGMNumber = 1
        }

        playCurrentBGM()
    }
}
