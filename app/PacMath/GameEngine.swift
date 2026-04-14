import Foundation
import UIKit
import CoreHaptics
import Observation

@Observable
class GameEngine {

    // MARK: - Types

    enum Screen { case start, game, results }

    enum GameMode: String, CaseIterable {
        case classic, threeStrikes

        var label: String {
            switch self {
            case .classic:      return "classic"
            case .threeStrikes: return "endless"
            }
        }

        var description: String {
            switch self {
            case .classic:      return "10 right answers keeps chompy happy for another day"
            case .threeStrikes: return "ramps from easy to beast. 3 strikes and you're out."
            }
        }
    }

    enum Difficulty: Int, CaseIterable {
        case easy = 1, medium, hard, beast

        var label: String {
            switch self {
            case .easy:   return "easy"
            case .medium: return "medium"
            case .hard:   return "hard"
            case .beast:  return "beast"
            }
        }

        var description: String {
            switch self {
            case .easy:   return "add & subtract, small numbers"
            case .medium: return "add & subtract, bigger numbers"
            case .hard:   return "times tables & division"
            case .beast:  return "all four operations, large numbers"
            }
        }
    }

    enum FeedbackType { case none, correct, wrong, skip }

    // MARK: - Backend-ready data models

    struct ProblemResult: Codable, Sendable {
        let display: String
        let correctAnswer: Int
        let userAnswer: Int?
        let isCorrect: Bool
        let wasSkipped: Bool
        let solveTimeSeconds: TimeInterval
    }

    struct GameResult: Codable, Sendable {
        let difficulty: Int
        let score: Int
        let correct: Int
        let wrong: Int
        let bestStreak: Int
        let totalTimeSeconds: TimeInterval
        let avgSolveTimeSeconds: TimeInterval?
        let problems: [ProblemResult]
        let completedAt: Date
    }

    // MARK: - Published State

    var screen: Screen = .start
    var gameMode: GameMode = .classic
    var difficulty: Difficulty = .easy
    var soundEnabled: Bool = UserDefaults.standard.object(forKey: "soundEnabled") == nil
        ? true
        : UserDefaults.standard.bool(forKey: "soundEnabled")
    var strikes: Int = 0
    let maxStrikes: Int = 3
    var score: Int = 0
    var streak: Int = 0
    var bestStreak: Int = 0
    var correct: Int = 0
    var wrong: Int = 0
    var currentDisplay: String = ""
    var feedback: String = ""
    var feedbackType: FeedbackType = .none
    var activeDifficulty: Difficulty = .easy
    var highestDifficultyReached: Difficulty = .easy
    var elapsed: TimeInterval = 0
    var problemIndex: Int = 0
    let totalProblems: Int = 10
    var avgTime: TimeInterval? = nil
    var awaitingNext: Bool = false
    var problemTimeRemaining: TimeInterval = 0
    var problemTimeLimit: TimeInterval = 0

    private(set) var currentA: Int? = nil
    private(set) var currentB: Int? = nil
    private(set) var currentAnswer: Int? = nil

    /// Per-problem results for progress dots and backend submission.
    private(set) var problemResults: [ProblemResult] = []

    /// The final game result, populated when the game ends. Ready to POST to a backend.
    private(set) var lastGameResult: GameResult? = nil

    /// Whether the last game set a new high score for its difficulty.
    var isNewHighScore: Bool = false

    // MARK: - Private

    private var hapticEngine: CHHapticEngine?
    private var timer: Timer?
    private var problemStartTime: Date?
    private var totalSolveTime: TimeInterval = 0
    private var solvedCount: Int = 0
    private var gameGeneration: Int = 0
    private var lastProblemDisplay: String = ""
    private var dedupAttempt: Bool = false
    private var consecutiveMisses: Int = 0

    /// Sub-level progress within the current tier (0.0 to 1.0).
    /// In endless mode this is the hidden competence gauge inside the
    /// current tier; in classic it preserves the original fixed-tier ramp.
    private var subLevelProgress: Double = 0.0

    /// Rolling window of recent correct-answer solve times for the session pacing model.
    /// Cleared each game so a device shared between kids recalibrates per session.
    private var recentSolveTimes: [TimeInterval] = []
    private let dynamicWindowSize = 5
    private let dynamicWarmupMinimum = 3
    private let endlessWarmupProblems = 5
    private let endlessPromotionBuffer = 0.18
    private let endlessDemotionBuffer = 0.55

    private let correctMessages = ["yes!", "correct!", "nice!", "got it!", "boom!", "yep!", "nailed it!"]

    deinit {
        timer?.invalidate()
    }

    // MARK: - Public API

    func startGame() {
        score = 0
        streak = 0
        bestStreak = 0
        correct = 0
        wrong = 0
        strikes = 0
        feedback = ""
        feedbackType = .none
        activeDifficulty = gameMode == .classic ? difficulty : .easy
        highestDifficultyReached = activeDifficulty
        elapsed = 0
        problemIndex = 0
        avgTime = nil
        awaitingNext = false
        totalSolveTime = 0
        solvedCount = 0
        currentA = nil
        currentB = nil
        currentAnswer = nil
        currentDisplay = ""
        problemResults = []
        lastGameResult = nil
        lastProblemDisplay = ""
        consecutiveMisses = 0
        subLevelProgress = 0.0
        recentSolveTimes = []
        gameGeneration += 1
        prepareHaptics()

        screen = .game
        generateProblem()
        startTimer()
    }

    func checkAnswer(_ answer: Int) {
        guard !awaitingNext, let correctAnswer = currentAnswer else { return }

        let solveTime = problemStartTime.map { Date().timeIntervalSince($0) } ?? 0
        totalSolveTime += solveTime
        solvedCount += 1
        let challengeLevel = gameMode == .threeStrikes ? activeDifficulty.rawValue : effectiveLevel

        let isCorrect = answer == correctAnswer

        problemResults.append(ProblemResult(
            display: currentDisplay,
            correctAnswer: correctAnswer,
            userAnswer: answer,
            isCorrect: isCorrect,
            wasSkipped: false,
            solveTimeSeconds: solveTime
        ))

        if isCorrect {
            correct += 1
            streak += 1
            consecutiveMisses = 0
            if streak > bestStreak { bestStreak = streak }

            if gameMode == .threeStrikes {
                recordSolveTime(solveTime)
                advanceEndlessDifficulty(for: solveTime)
            } else {
                recordSolveTime(solveTime)
                advanceClassicRamp(for: solveTime)
            }

            // Scoring: base 10 × difficulty multiplier + speed bonuses + streak bonus
            var points = 10
            if solveTime < 3.0 { points += 5 }
            if solveTime < 1.5 { points += 5 }
            points += streak
            points *= challengeLevel
            score += points

            // Feedback message
            if streak >= 5 {
                feedback = "\(streak) streak!"
            } else if streak >= 3 {
                feedback = "on fire!"
            } else {
                feedback = correctMessages.randomElement()!
            }
            feedbackType = .correct
            if soundEnabled { AudioManager.shared.playCorrect() }
            playHaptic(intensity: 0.5, sharpness: 0.6)

            // Tighten the between-problem gap as a streak builds — dead air is where
            // flow breaks for a kid in the zone.
            let nextDelay: TimeInterval
            switch streak {
            case 0..<3: nextDelay = 1.0
            case 3..<8: nextDelay = 0.5
            default:    nextDelay = 0.3
            }
            scheduleNext(delay: nextDelay)
        } else {
            wrong += 1
            streak = 0
            consecutiveMisses += 1
            feedback = "answer: \(correctAnswer)"
            feedbackType = .wrong
            if soundEnabled { AudioManager.shared.playWrong() }
            playHaptic(intensity: 1.0, sharpness: 0.3)

            if gameMode == .threeStrikes {
                retreatEndlessDifficulty(skipped: false, solveTime: solveTime)
            } else if consecutiveMisses >= 2 {
                subLevelProgress = max(0.0, subLevelProgress - 0.15)
            }

            if gameMode == .threeStrikes {
                strikes += 1
            }

            let nextDelay = gameMode == .threeStrikes ? 1.25 : 2.0
            scheduleNext(delay: nextDelay)
        }
    }

    func skip() {
        guard !awaitingNext, let correctAnswer = currentAnswer else { return }

        problemResults.append(ProblemResult(
            display: currentDisplay,
            correctAnswer: correctAnswer,
            userAnswer: nil,
            isCorrect: false,
            wasSkipped: true,
            solveTimeSeconds: problemStartTime.map { Date().timeIntervalSince($0) } ?? 0
        ))

        wrong += 1
        streak = 0
        consecutiveMisses += 1
        feedbackType = .skip

        if gameMode == .threeStrikes {
            let solveTime = problemStartTime.map { Date().timeIntervalSince($0) } ?? problemTimeLimit
            retreatEndlessDifficulty(skipped: true, solveTime: solveTime)
        } else if consecutiveMisses >= 2 {
            subLevelProgress = max(0.0, subLevelProgress - 0.15)
        }

        if gameMode == .threeStrikes {
            strikes += 1
            feedback = "answer: \(correctAnswer)"
            if soundEnabled {
                AudioManager.shared.playWrong()
            }
            playHaptic(intensity: 1.0, sharpness: 0.3)
        } else {
            feedback = "\(correctAnswer)"
        }

        let nextDelay = gameMode == .threeStrikes ? 1.25 : 2.0
        scheduleNext(delay: nextDelay)
    }

    func quit() {
        endGame()
    }

    func toggleSound() {
        soundEnabled.toggle()
        UserDefaults.standard.set(soundEnabled, forKey: "soundEnabled")
    }

    func formatTime(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(interval)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    // MARK: - Private Helpers

    /// Baseline per-level time limit used before the adaptive window has data.
    private var baseTimeLimitForLevel: TimeInterval {
        switch effectiveLevel {
        case 1:  return 10  // easy
        case 2:  return 12  // medium
        case 3:  return 15  // hard
        default: return 18  // beast
        }
    }

    /// Median of recent correct solve times. nil until the window has warmup data.
    private var personalMedian: TimeInterval? {
        guard recentSolveTimes.count >= dynamicWarmupMinimum else { return nil }
        let sorted = recentSolveTimes.sorted()
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }

    /// Per-problem time limit in endless mode. Adapts to the player's recent pace so the
    /// pressure *feels* constant — faster kids get tighter clocks, slower kids get looser
    /// ones. Falls back to the baseline until the warmup window fills.
    private var adaptiveTimeLimit: TimeInterval {
        let base = baseTimeLimitForLevel
        var target = personalMedian.map { max(base * 0.45, $0 * 1.9) } ?? base

        if isEndlessWarmup {
            target *= 1.2
        }

        // Recovery padding: if they're slipping, loosen pressure immediately so the
        // next problem feels recoverable instead of like a death spiral.
        if consecutiveMisses >= 1 {
            target *= 1.12
        }
        if consecutiveMisses >= 2 {
            target *= 1.18
        }

        // Clamp: never chaos-tight, never boredom-loose.
        let minTime: TimeInterval = isEndlessWarmup ? 5 : 4
        let maxTime: TimeInterval = base + (isEndlessWarmup ? 12 : 9)
        return max(minTime, min(maxTime, target))
    }

    private var isEndlessWarmup: Bool {
        gameMode == .threeStrikes && problemIndex <= endlessWarmupProblems
    }

    /// In endless mode, difficulty is the live tier estimate; in classic it stays fixed.
    private var effectiveLevel: Int {
        gameMode == .classic ? difficulty.rawValue : activeDifficulty.rawValue
    }

    /// Helper to interpolate an Int range based on sub-level progress (0.0–1.0).
    private func scaled(_ low: Int, _ high: Int) -> Int {
        low + Int(Double(high - low) * subLevelProgress)
    }

    private func recordSolveTime(_ solveTime: TimeInterval) {
        recentSolveTimes.append(solveTime)
        if recentSolveTimes.count > dynamicWindowSize {
            recentSolveTimes.removeFirst()
        }
    }

    private func advanceClassicRamp(for solveTime: TimeInterval) {
        let advance: Double
        if let median = personalMedian {
            if solveTime < median * 0.6 {
                advance = 0.25
            } else if solveTime > median * 1.3 {
                advance = 0.12
            } else {
                advance = 0.2
            }
        } else {
            advance = 0.2
        }
        subLevelProgress = min(1.0, subLevelProgress + advance)
    }

    private func endlessPressureFraction(for solveTime: TimeInterval) -> Double {
        let limit = max(problemTimeLimit, 0.1)
        return max(0.0, min(1.5, solveTime / limit))
    }

    private func advanceEndlessDifficulty(for solveTime: TimeInterval) {
        let fraction = endlessPressureFraction(for: solveTime)
        let advance: Double

        switch fraction {
        case ..<0.18:
            advance = 0.36
        case ..<0.3:
            advance = 0.3
        case ..<0.45:
            advance = 0.24
        case ..<0.65:
            advance = 0.18
        default:
            advance = 0.14
        }

        subLevelProgress += advance

        while subLevelProgress >= 1.0 {
            guard activeDifficulty != .beast else {
                subLevelProgress = 1.0
                return
            }

            let nextRaw = activeDifficulty.rawValue + 1
            activeDifficulty = Difficulty(rawValue: nextRaw) ?? .beast
            if activeDifficulty.rawValue > highestDifficultyReached.rawValue {
                highestDifficultyReached = activeDifficulty
            }
            subLevelProgress = max(endlessPromotionBuffer, subLevelProgress - 1.0)
        }
    }

    private func retreatEndlessDifficulty(skipped: Bool, solveTime: TimeInterval) {
        let fraction = endlessPressureFraction(for: solveTime)
        var retreat = skipped ? 0.32 : 0.22

        if fraction > 0.85 {
            retreat += 0.06
        }
        if consecutiveMisses >= 2 {
            retreat += 0.08
        }
        if isEndlessWarmup {
            retreat *= 0.65
        }

        subLevelProgress -= retreat

        while subLevelProgress < 0.0 {
            guard activeDifficulty != .easy else {
                subLevelProgress = 0.0
                return
            }

            let previousRaw = activeDifficulty.rawValue - 1
            activeDifficulty = Difficulty(rawValue: previousRaw) ?? .easy
            subLevelProgress += endlessDemotionBuffer
        }
    }

    private func generateProblem() {
        problemIndex += 1
        problemStartTime = Date()

        let level = effectiveLevel
        let roundDifficulty = Difficulty(rawValue: level) ?? .beast
        activeDifficulty = roundDifficulty
        if roundDifficulty.rawValue > highestDifficultyReached.rawValue {
            highestDifficultyReached = roundDifficulty
        }

        var a = 0
        var b = 0
        var answer = 0
        var symbol = "+"

        switch level {
        case 1: // easy: add/subtract, sums ramp from 5 → 10
            let maxSum = scaled(5, 10)
            if Bool.random() {
                a = Int.random(in: 1...max(2, maxSum / 2))
                b = Int.random(in: 1...max(1, maxSum - a))
                answer = a + b
                symbol = "+"
            } else {
                a = Int.random(in: 2...maxSum)
                b = Int.random(in: 1...max(1, a - 1))
                answer = a - b
                symbol = "\u{2212}" // −
            }

        case 2: // medium: add/subtract, sums ramp from 12 → 20
            let maxSum = scaled(12, 20)
            let minA = scaled(3, 6)
            if Bool.random() {
                a = Int.random(in: minA...max(minA, maxSum - 2))
                b = Int.random(in: 2...max(2, maxSum - a))
                answer = a + b
                symbol = "+"
            } else {
                a = Int.random(in: max(minA, 4)...maxSum)
                b = Int.random(in: 2...max(2, min(a - 1, maxSum / 2)))
                answer = a - b
                symbol = "\u{2212}" // −
            }

        case 3: // hard: ×/÷, tables ramp from 2–5 → 2–10
            let maxFactor = scaled(5, 10)
            if Bool.random() {
                a = Int.random(in: 2...max(2, scaled(3, 5)))
                b = Int.random(in: 2...maxFactor)
                answer = a * b
                symbol = "\u{00D7}" // ×
            } else {
                b = Int.random(in: 2...max(2, scaled(3, 5)))
                answer = Int.random(in: 2...maxFactor)
                a = b * answer
                symbol = "\u{00F7}" // ÷
            }

        default: // beast (4): all four ops, ranges ramp up
            let addMax = scaled(50, 99)
            let multMax = scaled(6, 12)
            let op = Int.random(in: 0...3)
            switch op {
            case 0:
                a = Int.random(in: 15...addMax)
                b = Int.random(in: 15...addMax)
                answer = a + b
                symbol = "+"
            case 1:
                a = Int.random(in: 25...addMax)
                b = Int.random(in: 10...max(10, a - 1))
                answer = a - b
                symbol = "\u{2212}" // −
            case 2:
                a = Int.random(in: 3...multMax)
                b = Int.random(in: 3...multMax)
                answer = a * b
                symbol = "\u{00D7}" // ×
            default:
                b = Int.random(in: 2...multMax)
                answer = Int.random(in: 2...multMax)
                a = b * answer
                symbol = "\u{00F7}" // ÷
            }
        }

        let display = "\(a) \(symbol) \(b)"

        // Dedup: reroll once if we got the exact same problem back-to-back
        if display == lastProblemDisplay && !dedupAttempt {
            dedupAttempt = true
            problemIndex -= 1
            generateProblem()
            return
        }
        dedupAttempt = false

        currentA = a
        currentB = b
        currentAnswer = answer
        currentDisplay = display
        lastProblemDisplay = display
        feedbackType = .none
        awaitingNext = false

        if gameMode == .threeStrikes {
            problemTimeLimit = adaptiveTimeLimit
            problemTimeRemaining = problemTimeLimit
        }
    }

    private func scheduleNext(delay: TimeInterval) {
        awaitingNext = true
        let gen = gameGeneration

        let isGameOver: Bool
        switch gameMode {
        case .classic:
            isGameOver = correct + wrong >= totalProblems
        case .threeStrikes:
            isGameOver = strikes >= maxStrikes
        }

        if isGameOver {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.gameGeneration == gen else { return }
                self.endGame()
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.gameGeneration == gen else { return }
                self.generateProblem()
            }
        }
    }

    private func endGame() {
        // Invalidate any delayed "next problem" callbacks that were scheduled
        // before the user quit or the round naturally ended.
        gameGeneration += 1
        awaitingNext = false

        stopTimer()
        if solvedCount > 0 {
            avgTime = totalSolveTime / Double(solvedCount)
        } else {
            avgTime = nil
        }

        lastGameResult = GameResult(
            difficulty: gameMode == .threeStrikes ? highestDifficultyReached.rawValue : difficulty.rawValue,
            score: score,
            correct: correct,
            wrong: wrong,
            bestStreak: bestStreak,
            totalTimeSeconds: elapsed,
            avgSolveTimeSeconds: avgTime,
            problems: problemResults,
            completedAt: Date()
        )

        recordDailyPlay()
        addToTotalTime(elapsed)

        // Check for new high score
        let previous = highScore(for: difficulty, mode: gameMode)
        if score > previous {
            setHighScore(score, for: difficulty, mode: gameMode)
            isNewHighScore = true
        } else {
            isNewHighScore = false
        }

        screen = .results
    }

    // MARK: - Total Time Played

    private static let totalTimeKey = "totalTimePlayed"

    var totalTimePlayed: TimeInterval {
        UserDefaults.standard.double(forKey: Self.totalTimeKey)
    }

    private func addToTotalTime(_ time: TimeInterval) {
        let total = totalTimePlayed + time
        UserDefaults.standard.set(total, forKey: Self.totalTimeKey)
    }

    func formatTimeLong(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    // MARK: - High Scores

    func highScore(for diff: Difficulty, mode: GameMode = .classic) -> Int {
        let defaults = UserDefaults.standard
        let key = highScoreKey(for: diff, mode: mode)
        let score = defaults.integer(forKey: key)

        guard mode == .threeStrikes, score == 0 else {
            return score
        }

        return Difficulty.allCases
            .map { defaults.integer(forKey: legacyThreeStrikesHighScoreKey(for: $0)) }
            .max() ?? 0
    }

    private func setHighScore(_ score: Int, for diff: Difficulty, mode: GameMode) {
        UserDefaults.standard.set(score, forKey: highScoreKey(for: diff, mode: mode))
    }

    private func highScoreKey(for diff: Difficulty, mode: GameMode) -> String {
        switch mode {
        case .classic:
            return "highScore_\(mode.rawValue)_\(diff.rawValue)"
        case .threeStrikes:
            return "highScore_\(mode.rawValue)"
        }
    }

    private func legacyThreeStrikesHighScoreKey(for diff: Difficulty) -> String {
        "highScore_\(GameMode.threeStrikes.rawValue)_\(diff.rawValue)"
    }

    func resetHighScores() {
        let defaults = UserDefaults.standard
        for mode in GameMode.allCases {
            for diff in Difficulty.allCases {
                defaults.removeObject(forKey: highScoreKey(for: diff, mode: mode))
                defaults.removeObject(forKey: legacyThreeStrikesHighScoreKey(for: diff))
            }
        }
    }

    // MARK: - Daily Streak

    private static let lastPlayDateKey = "lastPlayDate"
    private static let dailyStreakKey = "dailyStreak"

    var dailyStreak: Int {
        // If last play was yesterday or today, streak is valid
        let stored = UserDefaults.standard.integer(forKey: Self.dailyStreakKey)
        guard let lastDate = UserDefaults.standard.object(forKey: Self.lastPlayDateKey) as? Date else {
            return 0
        }
        let cal = Calendar.current
        if cal.isDateInToday(lastDate) || cal.isDateInYesterday(lastDate) {
            return stored
        }
        return 0  // streak broken
    }

    func recordDailyPlay() {
        let cal = Calendar.current
        let now = Date()
        let lastDate = UserDefaults.standard.object(forKey: Self.lastPlayDateKey) as? Date

        if let last = lastDate, cal.isDateInToday(last) {
            // Already played today — no change
            return
        }

        var newStreak: Int
        if let last = lastDate, cal.isDateInYesterday(last) {
            // Consecutive day — increment
            newStreak = UserDefaults.standard.integer(forKey: Self.dailyStreakKey) + 1
        } else {
            // First day or streak broken
            newStreak = 1
        }

        UserDefaults.standard.set(newStreak, forKey: Self.dailyStreakKey)
        UserDefaults.standard.set(now, forKey: Self.lastPlayDateKey)
    }

    // MARK: - Haptics

    private func prepareHaptics() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            let engine = try CHHapticEngine()
            engine.isMutedForAudio = false
            engine.resetHandler = { [weak self] in
                try? self?.hapticEngine?.start()
            }
            try engine.start()
            hapticEngine = engine
        } catch {
            print("Haptics unavailable: \(error)")
        }
    }

    private func playHaptic(intensity: Float, sharpness: Float) {
        guard let engine = hapticEngine else { return }
        let event = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
            ],
            relativeTime: 0
        )
        do {
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
        } catch {
            print("Haptic playback failed: \(error)")
        }
    }

    // MARK: - Timer

    private var lastTickDate: Date?

    private func startTimer() {
        elapsed = 0
        stopTimer()
        lastTickDate = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            let now = Date()
            let dt = now.timeIntervalSince(self.lastTickDate ?? now)
            self.lastTickDate = now
            self.elapsed += dt

            // Countdown for three strikes
            if self.gameMode == .threeStrikes && !self.awaitingNext && self.currentAnswer != nil {
                self.problemTimeRemaining = max(0, self.problemTimeRemaining - dt)
                if self.problemTimeRemaining <= 0 {
                    self.skip()
                }
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
