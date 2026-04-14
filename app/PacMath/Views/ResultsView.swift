import SwiftUI

struct ResultsView: View {
    var engine: GameEngine

    @State private var confettiPieces: [ConfettiPiece] = []
    @State private var showConfetti = false

    private let columns2 = Array(repeating: GridItem(.flexible(), spacing: 12), count: 2)
    private let columns3 = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 32) {
                    Spacer().frame(height: 20)

                    // MARK: - Title & Rank

                    Text(performanceTitle)
                        .font(Theme.mono(36, weight: .bold))
                        .foregroundStyle(Theme.background)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Theme.accent)

                    Text(summaryLine)
                        .font(Theme.mono(14, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)

                    // MARK: - High Score

                    HStack(spacing: 8) {
                        if engine.isNewHighScore {
                            Text("new high score!")
                                .font(Theme.mono(16, weight: .bold))
                                .foregroundStyle(Theme.streakYellow)
                        } else {
                            Text("best: \(engine.highScore(for: engine.difficulty, mode: engine.gameMode))")
                                .font(Theme.mono(14, weight: .medium))
                                .foregroundStyle(Theme.textSecondary)
                        }

                        if engine.gameMode == .threeStrikes {
                            HStack(spacing: 4) {
                                ForEach(0..<engine.maxStrikes, id: \.self) { _ in
                                    Image(systemName: "heart.slash.fill")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Theme.accent)
                                }
                            }
                        }
                    }

                    // MARK: - Progress Dots

                    WrappingDots(results: engine.problemResults, sizedByTime: engine.gameMode == .threeStrikes)

                    // MARK: - Last Missed Problem

                    if let missed = engine.problemResults.last(where: { !$0.isCorrect }) {
                        VStack(spacing: 4) {
                            HStack(spacing: 0) {
                                Text(missed.display)
                                    .font(Theme.mono(20, weight: .bold))
                                    .foregroundStyle(Theme.accent)
                                Text(" = \(missed.correctAnswer)")
                                    .font(Theme.mono(20, weight: .medium))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            if let userAnswer = missed.userAnswer {
                                Text("you said \(userAnswer)")
                                    .font(Theme.mono(12))
                                    .foregroundStyle(Theme.textSecondary.opacity(0.5))
                            } else {
                                Text("time's up")
                                    .font(Theme.mono(12))
                                    .foregroundStyle(Theme.textSecondary.opacity(0.5))
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(Theme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Theme.accent.opacity(0.3), lineWidth: 1)
                        )
                    }

                    // MARK: - Stats Grid

                    ViewThatFits(in: .horizontal) {
                        statsGrid(columns: columns3)
                        statsGrid(columns: columns2)
                    }

                    // MARK: - Action Buttons

                    VStack(spacing: 14) {
                        Button {
                            engine.startGame()
                        } label: {
                            Text("GO AGAIN")
                                .font(Theme.mono(22, weight: .bold))
                                .foregroundStyle(Theme.background)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 18)
                                .background(Theme.correctGreen)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)

                        Button {
                            engine.screen = .start
                        } label: {
                            ZStack {
                                MiniChompView()
                                Text("FEED \(ChompyProfile.shared.displayName.uppercased())")
                                    .font(Theme.mono(18, weight: .bold))
                                    .foregroundStyle(Theme.textPrimary)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(Theme.borderColor, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    HStack {
                        Button {
                            engine.toggleSound()
                        } label: {
                            Image(systemName: engine.soundEnabled ? "speaker.fill" : "speaker.slash.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.textSecondary.opacity(0.5))
                        }

                        Spacer()

                        (Text("pacmath")
                            .foregroundColor(Theme.accent.opacity(0.5))
                         + Text(".lol")
                            .foregroundColor(Theme.textSecondary.opacity(0.4)))
                            .font(Theme.mono(11))
                    }

                    Spacer().frame(height: 20)
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: 500)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)

            // MARK: - Confetti overlay

            if showConfetti {
                ConfettiView(pieces: confettiPieces)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .onAppear {
            let total = engine.correct + engine.wrong
            let isPerfect = total > 0 && engine.wrong == 0
            if engine.isNewHighScore || isPerfect {
                launchConfetti()
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private func statsGrid(columns: [GridItem]) -> some View {
        LazyVGrid(columns: columns, spacing: 12) {
            statCard(label: "score", value: "\(engine.score)")
            statCard(label: "correct", value: "\(engine.correct)")
            if engine.gameMode != .threeStrikes {
                statCard(label: "wrong", value: "\(engine.wrong)")
            }
            if engine.gameMode == .threeStrikes {
                statCard(label: "reached", value: engine.highestDifficultyReached.label)
            }
            statCard(label: "best streak", value: "\(engine.bestStreak)")
            statCard(label: "avg answer", value: formattedAvgTime)
            statCard(label: "time", value: engine.formatTime(engine.elapsed))
        }
    }

    @ViewBuilder
    private func statCard(label: String, value: String) -> some View {
        VStack(spacing: 6) {
            Text(label.uppercased())
                .font(Theme.mono(11, weight: .medium))
                .foregroundStyle(Theme.textSecondary)

            Text(value)
                .font(Theme.mono(28, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
        }
        .resultCard()
    }

    private var formattedAvgTime: String {
        guard let avg = engine.avgTime else { return "\u{2014}" }
        return String(format: "%.1fs", avg)
    }

    // MARK: - Performance Title

    private var performanceTitle: String {
        let total = engine.correct + engine.wrong
        guard total > 0 else { return "done!" }
        let ratio = Double(engine.correct) / Double(total)

        if engine.gameMode == .threeStrikes {
            // Three strikes titles based on survival length
            switch engine.correct {
            case 0...2:   return "warm up"
            case 3...6:   return "not bad"
            case 7...12:  return "solid run"
            case 13...19: return "on fire"
            case 20...29: return "machine"
            default:      return "chomp champ"
            }
        } else {
            // Classic titles based on accuracy
            if ratio >= 1.0 { return "perfect" }
            if ratio >= 0.9 { return "chomp champ" }
            if ratio >= 0.7 { return "solid" }
            if ratio >= 0.5 { return "not bad" }
            return "keep going"
        }
    }

    private var summaryLine: String {
        if engine.gameMode == .threeStrikes {
            return "\(engine.correct)/\(engine.correct + engine.wrong) in endless, reached \(engine.highestDifficultyReached.label)"
        }

        return "\(engine.correct)/\(engine.correct + engine.wrong) on \(engine.difficulty.label) in \(engine.formatTime(engine.elapsed))"
    }

    // MARK: - Confetti

    private func launchConfetti() {
        confettiPieces = (0..<40).map { _ in
            ConfettiPiece(
                x: CGFloat.random(in: 0...1),
                delay: Double.random(in: 0...0.4),
                color: [Theme.correctGreen, Theme.accent, Theme.streakYellow, .white].randomElement()!,
                size: CGFloat.random(in: 5...10),
                duration: Double.random(in: 1.5...2.5)
            )
        }
        showConfetti = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            showConfetti = false
        }
    }
}

// MARK: - Confetti Piece & View

struct ConfettiPiece: Identifiable {
    let id = UUID()
    let x: CGFloat
    let delay: Double
    let color: Color
    let size: CGFloat
    let duration: Double
}

struct ConfettiView: View {
    let pieces: [ConfettiPiece]

    var body: some View {
        GeometryReader { geo in
            ForEach(pieces) { piece in
                ConfettiDot(piece: piece, screenHeight: geo.size.height)
                    .position(x: piece.x * geo.size.width, y: -20)
            }
        }
    }
}

struct ConfettiDot: View {
    let piece: ConfettiPiece
    let screenHeight: CGFloat
    @State private var fallen = false

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(piece.color)
            .frame(width: piece.size, height: piece.size * 1.4)
            .rotationEffect(.degrees(fallen ? Double.random(in: 180...720) : 0))
            .offset(y: fallen ? screenHeight + 40 : 0)
            .opacity(fallen ? 0 : 1)
            .animation(
                .easeIn(duration: piece.duration).delay(piece.delay),
                value: fallen
            )
            .onAppear { fallen = true }
    }
}

// MARK: - Wrapping Dots

struct WrappingDots: View {
    let results: [GameEngine.ProblemResult]
    var sizedByTime: Bool = false

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(results.indices, id: \.self) { i in
                let r = results[i]
                let size = sizedByTime ? dotSize(for: r.solveTimeSeconds) : 10.0
                Circle()
                    .fill(r.isCorrect ? Theme.correctGreen :
                          (r.wasSkipped ? Theme.textPrimary.opacity(0.3) : Theme.accent))
                    .frame(width: size, height: size)
            }
        }
    }

    /// Maps solve time to dot size: fast (~1s) = tiny 6pt, slow (~10s+) = fat 22pt.
    private func dotSize(for time: TimeInterval) -> CGFloat {
        let minSize: CGFloat = 6
        let maxSize: CGFloat = 22
        let t = min(max(time, 1.0), 10.0) // clamp to 1...10
        let ratio = (t - 1.0) / 9.0       // 0...1
        return minSize + (maxSize - minSize) * ratio
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        guard !rows.isEmpty else { return .zero }
        let height = rows.enumerated().reduce(CGFloat.zero) { total, pair in
            let rowHeight = pair.element.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            return total + rowHeight + (pair.offset > 0 ? spacing : 0)
        }
        let width = proposal.width ?? .infinity
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var y = bounds.minY

        for row in rows {
            let rowHeight = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            let rowWidth = row.enumerated().reduce(CGFloat.zero) { total, pair in
                total + pair.element.sizeThatFits(.unspecified).width + (pair.offset > 0 ? spacing : 0)
            }
            var x = bounds.minX + (bounds.width - rowWidth) / 2 // center

            for subview in row {
                let size = subview.sizeThatFits(.unspecified)
                subview.place(at: CGPoint(x: x, y: y + (rowHeight - size.height) / 2), proposal: .unspecified)
                x += size.width + spacing
            }
            y += rowHeight + spacing
        }
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [[LayoutSubviews.Element]] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [[LayoutSubviews.Element]] = [[]]
        var currentWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentWidth + size.width + (rows.last!.isEmpty ? 0 : spacing) > maxWidth {
                rows.append([subview])
                currentWidth = size.width
            } else {
                currentWidth += size.width + (rows.last!.isEmpty ? 0 : spacing)
                rows[rows.count - 1].append(subview)
            }
        }
        return rows
    }
}

#Preview {
    let engine = GameEngine()
    engine.score = 87
    engine.correct = 8
    engine.wrong = 2
    engine.bestStreak = 5
    engine.avgTime = 2.3
    engine.elapsed = 47
    engine.screen = .results
    return ResultsView(engine: engine)
}
