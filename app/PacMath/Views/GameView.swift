import SwiftUI

struct GameView: View {
    var engine: GameEngine
    var speech: SpeechRecognizer
    @State private var keyboardAnswer: String = ""
    @State private var useMic: Bool = true

    // MARK: - Animation state

    @State private var problemID: String = ""
    @State private var pulseGlow: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            hudBar
                .padding(.horizontal, 24)
                .padding(.top, 12)

            progressDots
                .padding(.top, 16)

            Spacer()

            problemDisplay
            if engine.gameMode == .threeStrikes {
                countdownBar
                    .padding(.top, 12)
                    .padding(.horizontal, 48)
            }
            feedbackText
                .padding(.top, 8)

            GameChompView(engine: engine)
                .padding(.top, 12)

            Spacer()

            if speech.isAuthorized && useMic {
                micIndicator
                    .padding(.bottom, 12)
            } else {
                if speech.isUnavailable {
                    Text("speech unavailable — type your answer")
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.bottom, 4)
                }
                numberPad
                    .padding(.bottom, 8)
            }

            gameControls
                .padding(.bottom, 8)

            (Text("pacmath")
                .foregroundColor(Theme.accent.opacity(0.5))
             + Text(".lol")
                .foregroundColor(Theme.textSecondary.opacity(0.4)))
                .font(Theme.mono(11))
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
        .onAppear {
            problemID = engine.currentDisplay
            speech.onNumber = { number in
                guard !engine.awaitingNext else { return }
                engine.checkAnswer(number)
            }
            if useMic {
                useMic = speech.start(
                    echoA: engine.currentA,
                    echoB: engine.currentB,
                    expectedAnswer: engine.currentAnswer
                )
            }
        }
        .onChange(of: engine.currentDisplay) { _, newValue in
            withAnimation(.spring(duration: 0.35, bounce: 0.3)) {
                problemID = newValue
            }
            keyboardAnswer = ""
            guard useMic else { return }
            useMic = speech.restartRecognition(
                echoA: engine.currentA,
                echoB: engine.currentB,
                expectedAnswer: engine.currentAnswer
            )
        }
        .onChange(of: speech.isAuthorized) { _, authorized in
            if authorized && engine.screen == .game && useMic {
                useMic = speech.start(
                    echoA: engine.currentA,
                    echoB: engine.currentB,
                    expectedAnswer: engine.currentAnswer
                )
            } else if !authorized {
                useMic = false
            }
        }
        .onChange(of: speech.isUnavailable) { _, unavailable in
            if unavailable {
                useMic = false
            }
        }
        .onDisappear {
            speech.stop()
            speech.onNumber = nil
        }
    }

    // MARK: - HUD Bar

    private var hudBar: some View {
        HStack {
            hudItem(label: "score", value: "\(engine.score)")
            Spacer()
            hudItem(label: "streak", value: "\(engine.streak)")
            Spacer()
            hudItem(label: "time", value: engine.formatTime(engine.elapsed))
            Spacer()
            Button {
                engine.toggleSound()
            } label: {
                Image(systemName: engine.soundEnabled ? "speaker.fill" : "speaker.slash.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func hudItem(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(Theme.mono(10, weight: .medium))
                .textCase(.uppercase)
                .foregroundStyle(Theme.textSecondary)
            Text(value)
                .font(Theme.mono(24, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .contentTransition(.numericText())
        }
    }

    // MARK: - Progress Dots / Strikes

    @ViewBuilder
    private var progressDots: some View {
        if engine.gameMode == .threeStrikes {
            strikeIndicator
        } else {
            classicDots
        }
    }

    private var classicDots: some View {
        HStack(spacing: 8) {
            ForEach(1...engine.totalProblems, id: \.self) { index in
                Circle()
                    .fill(dotColor(for: index))
                    .frame(width: 10, height: 10)
                    .scaleEffect(index == engine.problemIndex ? 1.3 : 1.0)
                    .animation(.easeInOut(duration: 0.3), value: engine.problemIndex)
            }
        }
    }

    private var strikeIndicator: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Text("#\(engine.problemIndex)")
                    .font(Theme.mono(14, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)

                Spacer()

                HStack(spacing: 6) {
                    ForEach(0..<engine.maxStrikes, id: \.self) { i in
                        Image(systemName: i < engine.strikes ? "heart.slash.fill" : "heart.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(i < engine.strikes ? Theme.accent : Theme.correctGreen)
                            .animation(.easeInOut(duration: 0.3), value: engine.strikes)
                    }
                }
            }

            HStack(spacing: 6) {
                ForEach(GameEngine.Difficulty.allCases, id: \.self) { level in
                    rampChip(level)
                }
            }
        }
        .padding(.horizontal, 24)
    }

    private func dotColor(for index: Int) -> Color {
        let arrayIndex = index - 1 // dots are 1-based, array is 0-based
        if index == engine.problemIndex {
            return Theme.textPrimary
        } else if arrayIndex >= 0 && arrayIndex < engine.problemResults.count {
            return engine.problemResults[arrayIndex].isCorrect ? Theme.correctGreen : Theme.accent
        } else {
            return Theme.textPrimary.opacity(0.15)
        }
    }

    private func difficultyColor(_ level: GameEngine.Difficulty) -> Color {
        switch level {
        case .easy:
            return Theme.streakYellow
        case .medium:
            return Theme.correctGreen
        case .hard:
            return Theme.accent
        case .beast:
            return Theme.textPrimary
        }
    }

    @ViewBuilder
    private func rampChip(_ level: GameEngine.Difficulty) -> some View {
        let isActive = engine.activeDifficulty == level
        let isReached = level.rawValue <= engine.highestDifficultyReached.rawValue

        Text(level.label)
            .font(Theme.mono(11, weight: isActive ? .bold : .medium))
            .foregroundStyle(isActive ? Theme.background : (isReached ? Theme.textPrimary : Theme.textSecondary))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .background(isActive ? difficultyColor(level) : Theme.cardBackground)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(isReached && !isActive ? Theme.borderColor : .clear, lineWidth: 1)
            )
            .opacity(isReached ? 1.0 : 0.45)
    }

    // MARK: - Countdown Bar

    private var countdownBar: some View {
        let fraction = engine.problemTimeLimit > 0
            ? engine.problemTimeRemaining / engine.problemTimeLimit
            : 1.0
        let barColor: Color = fraction > 0.3 ? Theme.correctGreen :
                              (fraction > 0.15 ? Theme.streakYellow : Theme.accent)

        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 6)
                RoundedRectangle(cornerRadius: 3)
                    .fill(barColor)
                    .frame(width: geo.size.width * max(fraction, 0), height: 6)
                    .animation(.linear(duration: 0.1), value: fraction)
            }
        }
        .frame(height: 6)
    }

    // MARK: - Problem Display

    private var problemDisplay: some View {
        Text(engine.currentDisplay)
            .font(Theme.mono(52, weight: .bold))
            .foregroundStyle(Theme.textPrimary)
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .padding(.horizontal, 32)
            .id(problemID)
            .transition(.scale(scale: 0.6).combined(with: .opacity))
    }

    // MARK: - Feedback Text

    private var feedbackText: some View {
        Text(engine.feedback.isEmpty ? " " : engine.feedback)
            .font(Theme.mono(18, weight: .medium))
            .foregroundStyle(engine.feedbackType != .none ? feedbackColor : .clear)
            .frame(height: 28)
            .animation(.easeOut(duration: 0.3), value: engine.feedbackType)
    }

    private var feedbackColor: Color {
        switch engine.feedbackType {
        case .correct: return Theme.correctGreen
        case .wrong:   return Theme.accent
        case .skip:    return Theme.textPrimary.opacity(0.5)
        case .none:    return .clear
        }
    }

    // MARK: - Mic Indicator

    private var micIndicator: some View {
        VStack(spacing: 8) {
            Button {
                useMic = false
                speech.stop(deactivateSession: false)
            } label: {
                ZStack {
                    if speech.isListening {
                        // Pulsing glow ring
                        Circle()
                            .fill(Theme.accent.opacity(0.3))
                            .frame(width: 56, height: 56)
                            .scaleEffect(pulseGlow ? 1.5 : 1.0)
                            .opacity(pulseGlow ? 0.0 : 0.6)
                            .animation(
                                .easeInOut(duration: 1.2).repeatForever(autoreverses: false),
                                value: pulseGlow
                            )
                            .onAppear { pulseGlow = true }
                            .onDisappear { pulseGlow = false }

                        Circle()
                            .fill(Theme.accent)
                            .frame(width: 40, height: 40)

                        Image(systemName: "mic.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                    } else {
                        Circle()
                            .fill(Color.white.opacity(0.12))
                            .frame(width: 40, height: 40)

                        Image(systemName: "mic.slash.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .frame(width: 56, height: 56)
            }

            Text(speech.transcript.isEmpty ? " " : speech.transcript)
                .font(Theme.mono(13, weight: .regular).italic())
                .foregroundStyle(
                    speech.transcript.isEmpty ? .clear :
                    (speech.isListening ? Theme.streakYellow : Theme.textSecondary)
                )
                .lineLimit(1)
                .truncationMode(.head)
                .padding(.horizontal, 40)
                .frame(height: 18)
        }
    }

    // MARK: - Number Pad

    private var numberPad: some View {
        VStack(spacing: 6) {
            // Answer display
            HStack(spacing: 8) {
                Text(keyboardAnswer.isEmpty ? " " : keyboardAnswer)
                    .font(Theme.mono(28, weight: .bold))
                    .foregroundStyle(keyboardAnswer.isEmpty ? .clear : Theme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(Theme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Theme.borderColor, lineWidth: 1)
                    )

                if speech.isAuthorized {
                    Button {
                        keyboardAnswer = ""
                        useMic = speech.start(
                            echoA: engine.currentA,
                            echoB: engine.currentB,
                            expectedAnswer: engine.currentAnswer
                        )
                    } label: {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(width: 38, height: 38)
                            .background(Theme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
            .padding(.horizontal, 4)

            // Pad buttons
            let rows: [[PadKey]] = [
                [.digit(1), .digit(2), .digit(3)],
                [.digit(4), .digit(5), .digit(6)],
                [.digit(7), .digit(8), .digit(9)],
                [.delete,   .digit(0), .enter],
            ]
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(row, id: \.self) { key in
                        Button {
                            padTap(key)
                        } label: {
                            padLabel(key)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(padBackground(key))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 32)
    }

    private enum PadKey: Hashable {
        case digit(Int)
        case delete
        case enter
    }

    private func padTap(_ key: PadKey) {
        switch key {
        case .digit(let n):
            guard keyboardAnswer.count < 5 else { return }
            keyboardAnswer.append("\(n)")
        case .delete:
            if !keyboardAnswer.isEmpty { keyboardAnswer.removeLast() }
        case .enter:
            guard let answer = Int(keyboardAnswer) else { return }
            engine.checkAnswer(answer)
            keyboardAnswer = ""
        }
    }

    @ViewBuilder
    private func padLabel(_ key: PadKey) -> some View {
        switch key {
        case .digit(let n):
            Text("\(n)")
                .font(Theme.mono(20, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
        case .delete:
            Image(systemName: "delete.left")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        case .enter:
            Image(systemName: "return")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
        }
    }

    private func padBackground(_ key: PadKey) -> Color {
        switch key {
        case .enter: return Theme.accent
        default: return Color.white.opacity(0.08)
        }
    }

    // MARK: - Game Controls

    private var gameControls: some View {
        HStack(spacing: 24) {
            Button {
                engine.skip()
            } label: {
                Text("skip")
                    .font(Theme.mono(14, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Theme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Theme.borderColor, lineWidth: 1)
                    )
            }

            Button {
                engine.quit()
            } label: {
                Text("quit")
                    .font(Theme.mono(14, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Theme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Theme.borderColor, lineWidth: 1)
                    )
            }
        }
    }
}
