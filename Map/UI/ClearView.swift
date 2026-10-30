import AVFoundation
import SwiftUI

/// クリア表示(仕様書§13.1、UI仕様書§14)。プレイ画面の上に重ねて、画面全体を覆って表示する
struct ClearView: View {
    /// ゴール到達までの今回のタイム。チュートリアルではnil。
    let currentRunTime: TimeInterval?
    /// 試練の迷宮またはランダムステージの最短タイム
    let bestClearTime: TimeInterval?
    /// 次に進むステージ名
    let nextStageTitle: String
    let leaderboardTitle: String
    let leaderboardMode: LeaderboardMode
    let leaderboardEntries: [LeaderboardEntry]
    /// ランダムステージのテーマ。背景色の切り替えに使う(試練の迷宮・チュートリアルはnil)。
    var theme: DungeonTheme? = nil
    /// TOP100へ保存できた場合は、更新後の記録IDを返す。
    let onSaveName: (String) -> UUID?
    /// 登録済み記録の名前だけを更新する。
    let onUpdateName: (UUID, String) -> Bool
    /// クリア後に次のステージへ進む
    let onNextStage: () -> Void
    /// 対象モードだけ再挑戦を表示する
    let onReplay: (() -> Void)?
    /// 「スタート画面へ」が押されたときの処理
    let onReturn: () -> Void

    @State private var clearAudioPlayer: AVAudioPlayer?
    @State private var clearAudioErrorDelegate: AudioPlaybackErrorDelegate?
    @State private var isCelebrating = false
    @State private var playerName = ""
    @State private var isRegisteringEntry = false
    @State private var didAttemptRegistration = false
    @State private var savedEntryID: UUID?
    @State private var didUpdateName = false
    @State private var didFailNameUpdate = false
    @State private var registrationTask: Task<Void, Never>?
    @FocusState private var isPlayerNameFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var formattedBestClearTime: String {
        guard let bestClearTime else { return "記録なし" }
        return DungeonTimeFormatter.string(from: bestClearTime)
    }

    private var savedEntryRank: Int? {
        guard let savedEntryID else { return nil }
        // 登録結果は保存されたランキングを基準にする。
        return leaderboardEntries.firstIndex(where: { $0.id == savedEntryID }).map { $0 + 1 }
    }

    private var hasPendingNameChange: Bool {
        guard let savedEntryID,
              let savedEntry = leaderboardEntries.first(where: { $0.id == savedEntryID }) else { return false }
        let editedName = String(playerName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(16))
        return !editedName.isEmpty && editedName != savedEntry.playerName
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                DungeonBackground(theme: theme)
                VictoryBurst()
                    .opacity(0.42)
                    .ignoresSafeArea()

                RoundedRectangle(cornerRadius: 26)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.55), Color(red: 0.92, green: 0.70, blue: 0.30), Color.white.opacity(0.35)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
                    .padding(16)
                RoundedRectangle(cornerRadius: 22)
                    .stroke(Color(red: 0.82, green: 0.63, blue: 0.28).opacity(0.38), lineWidth: 1)
                    .padding(24)

                ScrollView(.vertical) {
                    VStack(spacing: 0) {
                        Spacer(minLength: 12)
                        titleBadge
                        crownBadge
                        titleText(width: max(0, geometry.size.width - 64))
                        victoryTitle
                        ornamentalDivider
                        clearSummary
                        timeSummary
                        tutorialClearMessage
                        nameEntrySection
                        leaderboardPanel
                        Spacer(minLength: currentRunTime == nil ? 64 : 18)
                        nextStageButton
                        replayButton
                        returnButton
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 18)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: max(0, geometry.size.height - 56), alignment: .top)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .padding(.horizontal, 32)
                .padding(.vertical, 28)
                .clipShape(RoundedRectangle(cornerRadius: 22))
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完了") {
                    isPlayerNameFocused = false
                }
                .font(DungeonTypography.maruMonica(size: 16))
            }
        }
        .onAppear {
            if playerName.isEmpty { playerName = "プレイヤー" }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 1.15).repeatForever(autoreverses: true)) {
                isCelebrating = true
            }
            guard let player = AudioPlayback.makePlayer(for: .gameClear) else { return }
            let errorDelegate = AudioPlaybackErrorDelegate(resource: .gameClear)
            player.delegate = errorDelegate
            AudioPlayback.play(player, for: .gameClear)
            clearAudioPlayer = player
            clearAudioErrorDelegate = errorDelegate
        }
        .onDisappear {
            registrationTask?.cancel()
            registrationTask = nil
            AudioPlayback.stop(clearAudioPlayer)
            clearAudioPlayer = nil
            clearAudioErrorDelegate = nil
        }
    }

    private var titleBadge: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
            Text("DUNGEON CONQUERED")
                .tracking(3)
            Image(systemName: "sparkles")
        }
        .font(DungeonTypography.maruMonica(size: 14))
        .foregroundStyle(Color(red: 0.94, green: 0.75, blue: 0.36))
    }

    private var crownBadge: some View {
        ZStack {
            Circle()
                .fill(Color(red: 0.88, green: 0.63, blue: 0.22).opacity(0.13))
                .frame(width: 112, height: 112)
            Circle()
                .stroke(Color(red: 0.96, green: 0.75, blue: 0.34).opacity(0.85), lineWidth: 2)
                .frame(width: 92, height: 92)
            Image(systemName: "crown.fill")
                .font(DungeonTypography.maruMonica(size: 43))
                .foregroundStyle(LinearGradient(
                    colors: [Color(red: 1.0, green: 0.88, blue: 0.52), Color(red: 0.78, green: 0.48, blue: 0.12)],
                    startPoint: .top,
                    endPoint: .bottom
                ))
        }
        .scaleEffect(isCelebrating ? 1.06 : 0.96)
        .shadow(color: Color(red: 1.0, green: 0.67, blue: 0.18).opacity(0.65), radius: isCelebrating ? 30 : 12)
        .padding(.top, 22)
        .padding(.bottom, 14)
    }

    private func titleText(width: CGFloat) -> some View {
        Text("おめでとう!")
            .font(DungeonTypography.maruMonica(size: min(width * 0.145, 58)))
            .tracking(2)
            .lineLimit(1)
            .minimumScaleFactor(0.55)
            .foregroundStyle(LinearGradient(
                colors: [Color(red: 1.0, green: 0.91, blue: 0.62), Color(red: 0.94, green: 0.68, blue: 0.24), Color(red: 0.76, green: 0.43, blue: 0.10)],
                startPoint: .top,
                endPoint: .bottom
            ))
            .shadow(color: Color(red: 1.0, green: 0.66, blue: 0.18).opacity(0.7), radius: isCelebrating ? 24 : 8)
    }

    private var victoryTitle: some View {
        Text("VICTORY")
            .font(DungeonTypography.maruMonica(size: 25))
            .tracking(9)
            .foregroundStyle(Color.white.opacity(0.92))
            .padding(.top, 8)
    }

    private var ornamentalDivider: some View {
        HStack(spacing: 12) {
            Rectangle().fill(Color(red: 0.80, green: 0.62, blue: 0.30).opacity(0.75)).frame(height: 1)
            Image(systemName: "diamond.fill")
                .font(DungeonTypography.maruMonica(size: 9))
                .foregroundStyle(Color(red: 0.95, green: 0.75, blue: 0.35))
            Rectangle().fill(Color(red: 0.80, green: 0.62, blue: 0.30).opacity(0.75)).frame(height: 1)
        }
        .frame(maxWidth: 250)
        .padding(.vertical, 18)
    }

    private var clearSummary: some View {
        VStack(spacing: 8) {
            Text("ゲームクリア")
                .font(DungeonTypography.maruMonica(size: 27))
                .foregroundStyle(.white)
            Text("迷宮の試練を突破した")
                .font(DungeonTypography.maruMonica(size: 16))
                .foregroundStyle(Color.white.opacity(0.70))
        }
    }

    @ViewBuilder
    private var tutorialClearMessage: some View {
        if currentRunTime == nil {
            Text("次からは\nクリアタイムが記録されます")
                .font(DungeonTypography.maruMonica(size: 20))
                .multilineTextAlignment(.center)
                .lineSpacing(5)
                .foregroundStyle(Color(red: 1.0, green: 0.84, blue: 0.45))
                .padding(.top, 28)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var timeSummary: some View {
        if let currentRunTime {
            VStack(spacing: 7) {
                Text("今回のクリアタイム")
                    .font(DungeonTypography.maruMonica(size: 16))
                    .foregroundStyle(Color.white.opacity(0.72))
                Text(DungeonTimeFormatter.string(from: currentRunTime))
                    .font(DungeonTypography.maruMonica(size: 34))
                    .monospacedDigit()
                    .foregroundStyle(Color(red: 1.0, green: 0.84, blue: 0.45))
                Text("最短クリアタイム：\(formattedBestClearTime)")
                    .font(DungeonTypography.maruMonica(size: 16))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.top, 4)
            }
            .padding(.top, 18)
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private var nameEntrySection: some View {
        if currentRunTime != nil {
            VStack(spacing: 7) {
                HStack(spacing: 8) {
                    TextField(
                        "",
                        text: $playerName,
                        prompt: Text("プレイヤー名を入力")
                            .foregroundColor(Color.white.opacity(0.55))
                    )
                        .font(DungeonTypography.maruMonica(size: 17))
                        .foregroundColor(.white)
                        .tint(Color(red: 1.0, green: 0.84, blue: 0.45))
                        .textFieldStyle(.plain)
                        .keyboardType(.default)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($isPlayerNameFocused)
                        .submitLabel(.done)
                        .onSubmit { isPlayerNameFocused = false }
                        .onChangeCompat(of: playerName) { _, _ in
                            didFailNameUpdate = false
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 42)
                        .background(Color.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.35), lineWidth: 1))
                        .disabled(isRegisteringEntry || (didAttemptRegistration && savedEntryID == nil))

                    Button(action: beginLeaderboardRegistration) {
                        HStack(spacing: 5) {
                            if isRegisteringEntry {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(Color(red: 0.12, green: 0.09, blue: 0.04))
                                Text("登録中")
                            } else if didAttemptRegistration, savedEntryID != nil,
                                      hasPendingNameChange || playerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text("更新")
                            } else if didAttemptRegistration, savedEntryID != nil {
                                Image(systemName: "checkmark.seal.fill")
                                Text("登録済み")
                            } else if didAttemptRegistration {
                                Image(systemName: "checkmark")
                                Text("確認済み")
                            } else {
                                Text("記録")
                            }
                        }
                        .font(DungeonTypography.maruMonica(size: 15))
                        .frame(width: 96, height: 42)
                        .foregroundStyle(Color(red: 0.12, green: 0.09, blue: 0.04))
                        .background(Color(red: 0.95, green: 0.74, blue: 0.32), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .disabled(
                        isRegisteringEntry
                            || playerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || (didAttemptRegistration && !hasPendingNameChange)
                    )
                    .opacity(playerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.65 : 1)
                }

                registrationFeedback
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
            }
            .padding(.top, 16)
        }
    }

    @ViewBuilder
    private var registrationFeedback: some View {
        if isRegisteringEntry {
            Text(didAttemptRegistration ? "変更した名前をランキングへ反映しています…" : "名前とクリアタイムをランキングへ登録しています…")
                .foregroundStyle(Color.white.opacity(0.82))
                .transition(.opacity)
        } else if didFailNameUpdate {
            Label("名前を更新できませんでした。もう一度お試しください", systemImage: "exclamationmark.circle.fill")
                .foregroundStyle(Color(red: 1.0, green: 0.72, blue: 0.62))
                .transition(.move(edge: .top).combined(with: .opacity))
        } else if didAttemptRegistration, savedEntryID != nil,
                  playerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text("名前を入力してください")
                .foregroundStyle(Color.white.opacity(0.82))
        } else if hasPendingNameChange {
            Text("名前を直したら「更新」を押してください")
                .foregroundStyle(Color.white.opacity(0.82))
                .transition(.opacity)
        } else if didAttemptRegistration, let rank = savedEntryRank {
            Label(
                didUpdateName ? "名前を更新しました！ ランキング \(rank) 位" : "登録完了！ ランキング \(rank) 位",
                systemImage: "checkmark.seal.fill"
            )
                .foregroundStyle(Color(red: 1.0, green: 0.84, blue: 0.45))
                .transition(.move(edge: .top).combined(with: .opacity))
        } else if didAttemptRegistration {
            Label("今回のタイムはTOP100圏外でした", systemImage: "info.circle.fill")
                .foregroundStyle(Color.white.opacity(0.78))
                .transition(.move(edge: .top).combined(with: .opacity))
        } else {
            Text("名前を入力してランキングに記録")
                .foregroundStyle(.white.opacity(0.75))
        }
    }

    private func beginLeaderboardRegistration() {
        guard !isRegisteringEntry else { return }
        let cleanName = String(playerName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(16))
        guard !cleanName.isEmpty else { return }

        let entryID: UUID?
        let nameUpdateSucceeded: Bool?
        if didAttemptRegistration {
            guard let savedEntryID, hasPendingNameChange else { return }
            nameUpdateSucceeded = onUpdateName(savedEntryID, cleanName)
            entryID = savedEntryID
        } else {
            // 保存を先に完了し、画面を離れて演出Taskがキャンセルされても記録を失わない。
            entryID = onSaveName(cleanName)
            nameUpdateSucceeded = nil
        }

        SoundEffectManager.shared.playButtonTap()
        isPlayerNameFocused = false
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
            isRegisteringEntry = true
        }
        registrationTask?.cancel()
        registrationTask = Task { @MainActor in
            if !reduceMotion {
                try? await Task.sleep(nanoseconds: 550_000_000)
            }
            guard !Task.isCancelled else {
                registrationTask = nil
                return
            }

            savedEntryID = entryID
            playerName = cleanName
            if let nameUpdateSucceeded {
                didUpdateName = nameUpdateSucceeded
                didFailNameUpdate = !nameUpdateSucceeded
            }
            withAnimation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.72)) {
                isRegisteringEntry = false
                didAttemptRegistration = true
            }
            registrationTask = nil
        }
    }

    @ViewBuilder
    private var leaderboardPanel: some View {
        if currentRunTime != nil {
            VStack(spacing: 6) {
                HStack(alignment: .center) {
                    Text("\(leaderboardTitle)  TOP 100")
                        .font(DungeonTypography.maruMonica(size: 16))
                        .foregroundStyle(Color(red: 1.0, green: 0.84, blue: 0.45))
                        .frame(maxWidth: .infinity, alignment: .leading)

                }

                if leaderboardEntries.isEmpty {
                    Text("記録はまだありません")
                        .font(DungeonTypography.maruMonica(size: 15))
                        .foregroundStyle(.white.opacity(0.65))
                        .frame(maxWidth: .infinity, minHeight: 56)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView(.vertical) {
                            LazyVStack(spacing: 4) {
                                ForEach(Array(leaderboardEntries.prefix(100).enumerated()), id: \.element.id) { index, entry in
                                    LeaderboardRowView(
                                        rank: index + 1,
                                        entry: entry,
                                        isHighlighted: entry.id == savedEntryID
                                    )
                                    .id(entry.id)
                                    .transition(.move(edge: .top).combined(with: .opacity))
                                }
                            }
                            .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.78), value: leaderboardEntries.map(\.id))
                        }
                        .frame(height: 150)
                        .scrollIndicators(.visible)
                        .onChangeCompat(of: leaderboardEntries.map(\.id)) { _, _ in
                            guard let savedEntryID,
                                  leaderboardEntries.contains(where: { $0.id == savedEntryID }) else { return }
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.45)) {
                                proxy.scrollTo(savedEntryID, anchor: .center)
                            }
                        }
                    }
                }
            }
            .padding(10)
            .background(Color.black.opacity(0.36), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(red: 0.82, green: 0.63, blue: 0.28).opacity(0.45), lineWidth: 1))
            .padding(.top, 12)
        }
    }

    private var nextStageButton: some View {
        Button(action: onNextStage) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.right.circle.fill")
                Text(nextStageTitle)
            }
            .font(DungeonTypography.maruMonica(size: 19))
            .frame(maxWidth: .infinity, minHeight: 54)
            .foregroundStyle(Color(red: 0.12, green: 0.09, blue: 0.04))
            .background(LinearGradient(
                colors: [Color(red: 1.0, green: 0.85, blue: 0.49), Color(red: 0.78, green: 0.53, blue: 0.18)],
                startPoint: .top,
                endPoint: .bottom
            ), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.68), lineWidth: 1))
        }
        .buttonStyle(DungeonPressButtonStyle())
        .frame(maxWidth: 290)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var replayButton: some View {
        if let onReplay {
            Button(action: onReplay) {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.counterclockwise")
                    Text("もう一度遊ぶ")
                }
                .font(DungeonTypography.maruMonica(size: 19))
                .frame(maxWidth: .infinity, minHeight: 54)
                .foregroundStyle(Color(red: 0.12, green: 0.09, blue: 0.04))
                .background(LinearGradient(
                    colors: [Color(red: 1.0, green: 0.85, blue: 0.49), Color(red: 0.78, green: 0.53, blue: 0.18)],
                    startPoint: .top,
                    endPoint: .bottom
                ), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.68), lineWidth: 1))
            }
            .buttonStyle(DungeonPressButtonStyle())
            .frame(maxWidth: 290)
        }
    }

    private var returnButton: some View {
        Button(action: onReturn) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.uturn.backward")
                Text("スタート画面へ")
            }
            .font(DungeonTypography.maruMonica(size: 19))
            .frame(maxWidth: .infinity, minHeight: 50)
            .foregroundStyle(.white.opacity(0.9))
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.45), lineWidth: 1))
        }
        .buttonStyle(DungeonPressButtonStyle())
        .frame(maxWidth: 290)
        .padding(.bottom, 24)
    }
}

private struct LeaderboardRowView: View {
    let rank: Int
    let entry: LeaderboardEntry
    let isHighlighted: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text("\(rank)")
                .frame(width: 32, alignment: .trailing)
                .foregroundStyle(Color(red: 1.0, green: 0.84, blue: 0.45))
            Text(entry.playerName)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(DungeonTimeFormatter.string(from: entry.clearTime))
                .monospacedDigit()
            if let seed = entry.seed {
                Text(String(format: "%04llX", seed & 0xFFFF))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .font(DungeonTypography.maruMonica(size: 14))
        .foregroundStyle(.white.opacity(0.92))
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background {
            RoundedRectangle(cornerRadius: 7)
                .fill(isHighlighted
                    ? Color(red: 0.95, green: 0.74, blue: 0.32).opacity(0.28)
                    : (rank.isMultiple(of: 2) ? Color.white.opacity(0.055) : .clear))
        }
        .overlay {
            if isHighlighted {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color(red: 1.0, green: 0.84, blue: 0.45).opacity(0.9), lineWidth: 1.5)
            }
        }
    }
}

/// 迷宮RPGらしい光の放射を描き、クリアした瞬間の高揚感を加える。
private struct VictoryBurst: View {
    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let rayCount = 28
            let radius = hypot(size.width, size.height)

            for index in 0..<rayCount {
                let angle = CGFloat(index) / CGFloat(rayCount) * 2 * .pi
                let innerRadius = index.isMultiple(of: 2) ? radius * 0.12 : radius * 0.24
                let outerRadius = radius * 0.86
                var ray = Path()
                ray.move(to: CGPoint(x: center.x + cos(angle) * innerRadius, y: center.y + sin(angle) * innerRadius))
                ray.addLine(to: CGPoint(x: center.x + cos(angle) * outerRadius, y: center.y + sin(angle) * outerRadius))
                context.stroke(ray, with: .color(Color(red: 0.98, green: 0.72, blue: 0.28).opacity(index.isMultiple(of: 2) ? 0.25 : 0.11)), lineWidth: index.isMultiple(of: 2) ? 2 : 1)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
