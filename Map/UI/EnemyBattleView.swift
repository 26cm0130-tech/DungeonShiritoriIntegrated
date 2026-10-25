import SwiftUI

/// 戦闘中のダンジョン表示には敵だけを重ねる。
struct EnemyBattleView: View {
    let battle: EnemyBattle
    let playerHP: Int
    let playerAttackAnimationID: Int
    let counterAttackAnimationID: Int
    let defeatRecoilAnimationID: Int

    @State private var isBreathing = false
    @State private var isCountering = false
    @State private var isHit = false
    @State private var enemyOffset: CGFloat = 0
    @State private var enemyHitTilt = 0.0
    @State private var damageLabel: String?
    @State private var damageLabelOffset: CGFloat = 12
    @State private var hitTask: Task<Void, Never>?
    @State private var counterTask: Task<Void, Never>?

    private var enemyImage: String {
        if isCountering { return battle.kind.attackImageName }
        if isHit { return battle.kind.hitImageName }
        if battle.kind == .dragon && isBreathing { return "MessageMonsterMove1" }
        return battle.kind.imageName
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Image(enemyImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(
                        width: min(geometry.size.width * 0.62, 190),
                        height: min(geometry.size.height * 0.76, 190)
                    )
                    .overlay {
                        Image(enemyImage)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(
                                width: min(geometry.size.width * 0.62, 190),
                                height: min(geometry.size.height * 0.76, 190)
                            )
                            .colorMultiply(Color(red: 1.0, green: 0.08, blue: 0.06))
                            .opacity(isHit ? 0.98 : 0)
                            .animation(.easeOut(duration: 0.06), value: isHit)
                    }
                    .offset(x: enemyOffset, y: isBreathing && enemyOffset == 0 ? -3 : 0)
                    .scaleEffect(isHit ? 1.06 : (isBreathing && enemyOffset == 0 ? 1.035 : (isCountering ? 1.08 : 1)))
                    .rotationEffect(.degrees(isHit ? enemyHitTilt : (enemyOffset == 0 ? 0 : 5)))
                    .shadow(
                        color: isHit ? Color(red: 0.98, green: 0.12, blue: 0.08).opacity(0.95) : .black.opacity(0.72),
                        radius: isHit ? 17 : 12,
                        y: 6
                    )
                    .animation(.easeOut(duration: 0.08), value: isHit)
                    .position(x: geometry.size.width * 0.5, y: geometry.size.height * 0.57)
                    .accessibilityLabel(battle.kind.name)

                if let damageLabel {
                    Text(damageLabel)
                        .font(DungeonTypography.maruMonica(size: 26))
                        .foregroundStyle(Color(red: 1.0, green: 0.83, blue: 0.24))
                        .shadow(color: Color(red: 0.98, green: 0.12, blue: 0.08), radius: 7)
                        .shadow(color: .black, radius: 3, y: 2)
                        .offset(y: damageLabelOffset - 12)
                        .position(x: geometry.size.width * 0.5, y: geometry.size.height * 0.82)
                        .transition(.scale.combined(with: .opacity))
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .allowsHitTesting(false)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 640_000_000)
                guard !Task.isCancelled else { break }
                withAnimation(.easeInOut(duration: 0.5)) { isBreathing.toggle() }
            }
        }
        .onChangeCompat(of: battle.enemyHP) { oldHP, newHP in
            guard newHP < oldHP else { return }
            playHitReaction(damage: oldHP - newHP)
        }
        .onChangeCompat(of: counterAttackAnimationID) { _, _ in
            playCounterReaction()
        }
        .onChangeCompat(of: defeatRecoilAnimationID) { _, _ in
            playDefeatRecoil()
        }
        .onDisappear {
            hitTask?.cancel()
            counterTask?.cancel()
        }
    }

    private func playHitReaction(damage: Int) {
        hitTask?.cancel()
        hitTask = Task { @MainActor in
            damageLabel = "−\(damage)"
            damageLabelOffset = 12
            isHit = true
            withAnimation(.easeOut(duration: 0.12)) {
                damageLabelOffset = -18
            }
            await playImpactMotion(recoil: 18)
            guard !Task.isCancelled else { return }
            isHit = false
            try? await Task.sleep(nanoseconds: 360_000_000)
            guard !Task.isCancelled else { return }
            damageLabel = nil
            hitTask = nil
        }
    }

    /// 赤い閃光と短い左右の反動で、敵の被弾をレトロなヒット演出にする。
    @MainActor
    private func playImpactMotion(recoil: CGFloat) async {
        withAnimation(.easeOut(duration: 0.055)) {
            enemyOffset = -recoil
            enemyHitTilt = -5
        }
        try? await Task.sleep(nanoseconds: 55_000_000)
        guard !Task.isCancelled else { return }

        withAnimation(.linear(duration: 0.05)) {
            enemyOffset = recoil * 0.65
            enemyHitTilt = 4
        }
        try? await Task.sleep(nanoseconds: 50_000_000)
        guard !Task.isCancelled else { return }

        withAnimation(.linear(duration: 0.05)) {
            enemyOffset = -recoil * 0.3
            enemyHitTilt = -2
        }
        try? await Task.sleep(nanoseconds: 50_000_000)
        guard !Task.isCancelled else { return }

        withAnimation(.spring(response: 0.12, dampingFraction: 0.62)) {
            enemyOffset = 0
            enemyHitTilt = 0
        }
        try? await Task.sleep(nanoseconds: 120_000_000)
    }

    /// 撃破確定前に、赤い被弾表現を伴う最後ののけぞりを再生する。
    private func playDefeatRecoil() {
        hitTask?.cancel()
        hitTask = Task { @MainActor in
            isHit = true
            await playImpactMotion(recoil: 24)
            guard !Task.isCancelled else { return }
            isHit = false
            hitTask = nil
        }
    }

    private func playCounterReaction() {
        counterTask?.cancel()
        counterTask = Task { @MainActor in
            // 呼び出し直後に敵の反撃モーションを開始する。
            isCountering = true
            withAnimation(.easeOut(duration: 0.12)) { enemyOffset = 18 }
            try? await Task.sleep(nanoseconds: 170_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.16)) { enemyOffset = 0 }
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard !Task.isCancelled else { return }
            isCountering = false
            counterTask = nil
        }
    }
}

struct EnemyEncounterSpeechOverlay: View {
    let speech: EnemyEncounterSpeech
    let showEnemySprite: Bool

    var body: some View {
        VStack(spacing: 4) {
            EnemySpeechBubbleView(text: speech.message)
                .padding(.horizontal, 8)

            if showEnemySprite {
                Image(speech.kind.imageName)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)
                    .shadow(color: .black.opacity(0.8), radius: 5, y: 3)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
        .allowsHitTesting(false)
    }
}

struct EnemyDefeatSpeechOverlay: View {
    let speech: EnemyDefeatSpeech

    var body: some View {
        VStack(spacing: 4) {
            EnemySpeechBubbleView(text: speech.message)
                .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 8)
        .transition(.scale.combined(with: .opacity))
        .allowsHitTesting(false)
    }
}

private struct EnemySpeechBubbleView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(DungeonTypography.maruMonica(size: 14))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .minimumScaleFactor(0.82)
            .lineSpacing(2)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.94), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(red: 0.78, green: 0.66, blue: 0.38), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.75), radius: 6, y: 3)
    }
}
