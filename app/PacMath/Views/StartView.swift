import SwiftUI

struct StartView: View {
    var engine: GameEngine
    var speech: SpeechRecognizer
    @State private var isStarting = false
    @State private var showCustomize = false
    @State private var showResetConfirm = false
    @Bindable private var profile = ChompyProfile.shared

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 32) {
                        Spacer().frame(height: 20)

                        // MARK: - Title & Subtitle

                        VStack(spacing: 8) {
                            Text("PacMath")
                                .font(Theme.mono(48, weight: .bold))
                                .foregroundStyle(Theme.background)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Theme.accent)

                            Text("mental math, out loud.")
                                .font(Theme.mono(18))
                                .foregroundStyle(Theme.textSecondary)
                        }

                        // MARK: - Streak & High Score

                        HStack(spacing: 16) {
                            if engine.dailyStreak > 0 {
                                Text("\(engine.dailyStreak) day streak")
                                    .font(Theme.mono(14, weight: .bold))
                                    .foregroundStyle(Theme.streakYellow)
                            }

                            if currentHighScore > 0 {
                                Text("best: \(currentHighScore)")
                                    .font(Theme.mono(14, weight: .bold))
                                    .foregroundStyle(Theme.textSecondary)
                            }

                            if engine.totalTimePlayed >= 60 {
                                Text(engine.formatTimeLong(engine.totalTimePlayed))
                                    .font(Theme.mono(14, weight: .bold))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }

                        // MARK: - Mascot

                        ChompPetView(engine: engine)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                showCustomize = true
                            }

                        // MARK: - Description

                        Text("solve it in your head. say it out loud. feed \(profile.displayName).")
                            .font(Theme.mono(14))
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                            .padding(.horizontal, 8)

                        // MARK: - Mode Picker

                        VStack(spacing: 16) {
                            Text("game mode:")
                                .font(Theme.mono(16))
                                .foregroundStyle(Theme.textPrimary)

                            HStack(spacing: 10) {
                                ForEach(GameEngine.GameMode.allCases, id: \.self) { mode in
                                    modeButton(mode)
                                }
                            }

                            Text(engine.gameMode.description)
                                .font(Theme.mono(13))
                                .foregroundStyle(Theme.textSecondary)
                                .multilineTextAlignment(.center)
                                .frame(height: 36, alignment: .top)
                                .transition(.opacity)
                                .id(engine.gameMode)
                        }

                        if engine.gameMode == .classic {
                            VStack(spacing: 16) {
                                Text("pick your level:")
                                    .font(Theme.mono(16))
                                    .foregroundStyle(Theme.textPrimary)

                                HStack(spacing: 10) {
                                    ForEach(GameEngine.Difficulty.allCases, id: \.self) { level in
                                        difficultyButton(level)
                                    }
                                }

                                Text(engine.difficulty.description)
                                    .font(Theme.mono(13))
                                    .foregroundStyle(Theme.textSecondary)
                                    .multilineTextAlignment(.center)
                                    .frame(height: 36, alignment: .top)
                                    .transition(.opacity)
                                    .id(engine.difficulty)
                            }
                        }

                        Spacer().frame(height: 20)
                    }
                    .padding(.horizontal, 24)
                    .frame(maxWidth: 500)
                    .frame(maxWidth: .infinity)
                }
                .scrollBounceBehavior(.basedOnSize)

                // MARK: - Start Button (pinned to bottom)

                VStack(spacing: 10) {
                    Button {
                        guard !isStarting else { return }
                        isStarting = true
                        speech.requestAuthorization { _ in
                            isStarting = false
                            engine.startGame()
                        }
                    } label: {
                        Text(isStarting ? "PREPARING..." : "START")
                            .font(Theme.mono(22, weight: .bold))
                            .foregroundStyle(Theme.background)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Theme.correctGreen)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .disabled(isStarting)

                    HStack {
                        Button {
                            engine.toggleSound()
                        } label: {
                            Image(systemName: engine.soundEnabled ? "speaker.fill" : "speaker.slash.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.textSecondary.opacity(0.5))
                                .frame(width: 20, height: 20)
                        }

                        Spacer()

                        (Text("pacmath")
                            .foregroundColor(Theme.accent.opacity(0.5))
                         + Text(".lol")
                            .foregroundColor(Theme.textSecondary.opacity(0.4)))
                            .font(Theme.mono(11))
                            .contentShape(Rectangle())
                            .onLongPressGesture(minimumDuration: 1.5) {
                                showResetConfirm = true
                            }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .frame(maxWidth: 500)
                .frame(maxWidth: .infinity)
            }
        }
        .sheet(isPresented: $showCustomize) {
            ChompyCustomizeView(profile: profile)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .alert("Reset high scores?", isPresented: $showResetConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                engine.resetHighScores()
            }
        } message: {
            Text("Clears all high scores. Your daily streak is kept.")
        }
    }

    // MARK: - Helpers

    private var currentHighScore: Int {
        engine.highScore(for: engine.difficulty, mode: engine.gameMode)
    }

    // MARK: - Subviews

    @ViewBuilder
    private func modeButton(_ mode: GameEngine.GameMode) -> some View {
        let isSelected = engine.gameMode == mode

        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                engine.gameMode = mode
            }
        } label: {
            Text(mode.label)
                .font(Theme.mono(14, weight: isSelected ? .bold : .regular))
                .foregroundStyle(isSelected ? Theme.background : Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(isSelected ? Theme.accent : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isSelected ? .clear : Theme.borderColor, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func difficultyButton(_ level: GameEngine.Difficulty) -> some View {
        let isSelected = engine.difficulty == level

        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                engine.difficulty = level
            }
        } label: {
            Text(level.label)
                .font(Theme.mono(14, weight: isSelected ? .bold : .regular))
                .foregroundStyle(isSelected ? Theme.background : Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(isSelected ? Theme.accent : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isSelected ? .clear : Theme.borderColor, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func rampBadge(_ level: GameEngine.Difficulty) -> some View {
        let isStart = level == .easy

        Text(level.label)
            .font(Theme.mono(13, weight: isStart ? .bold : .medium))
            .foregroundStyle(isStart ? Theme.background : Theme.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(isStart ? Theme.streakYellow : Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isStart ? .clear : Theme.borderColor, lineWidth: 1)
            )
    }
}

#Preview {
    StartView(engine: GameEngine(), speech: SpeechRecognizer())
}
