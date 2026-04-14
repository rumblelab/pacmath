import SwiftUI

// Temporarily set to true to freeze Chompy mid-chomp with mouth open and
// keep speech bubbles pinned indefinitely, so App Store screenshots catch him
// in a flattering pose. Revert to false before shipping.
private let pacMathScreenshotMode = false

struct ChompPetView: View {
    var engine: GameEngine
    private let profile = ChompyProfile.shared

    @State private var position: CGFloat = 0.0
    @State private var movingRight = true
    @State private var mouthOpen = false
    @State private var dots: [ChompDot] = []
    @State private var health: CGFloat = 0.0
    @State private var speechBubble: String? = nil
    @State private var lastBubbleTime: Date = .distantPast
    @State private var lastBubbleText: String = ""
    @State private var recentBubbleTexts: [String] = []
    @State private var mealBubbleBudget: Int = 0
    @State private var dotsEatenThisMeal: Int = 0
    @State private var mealSummaryScheduled = false

    private static let healthKey = "pacMathHealth"
    private static let lastFeedKey = "pacMathLastFeedTime"
    private static let legacyHealthKey = "pacHealth"
    private static let legacyLastFeedKey = "pacLastFeedTime"

    private let moveTimer = Timer.publish(every: 0.03, on: .main, in: .common).autoconnect()
    private let chompTimer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()
    @State private var spokeThisTrip = false
    @State private var tripCount = 0

    private var speed: CGFloat {
        0.0008 + health * 0.003
    }

    private var chompColor: Color {
        profile.color.opacity(0.2 + health * 0.8)
    }

    private var chompSize: CGFloat {
        20 + health * 8
    }

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let w = geo.size.width
                let y = geo.size.height / 2

                // Dots as food
                ForEach(dots) { dot in
                    Circle()
                        .fill(dot.isGood ? Theme.correctGreen : Theme.accent)
                        .frame(width: dot.size, height: dot.size)
                        .position(x: dot.x * (w - 40) + 20, y: y)
                }

                // Chomp
                let chompX = position * (w - 40) + 20
                ChompShape(mouthAngle: (pacMathScreenshotMode || mouthOpen) ? 45 : 2, facingRight: movingRight)
                    .fill(chompColor)
                    .frame(width: chompSize, height: chompSize)
                    .position(x: chompX, y: y)

                // Speech bubble
                if let text = speechBubble {
                    let bubbleX = movingRight
                        ? min(chompX + 50, w - 40)
                        : max(chompX - 50, 40)
                    Text(text)
                        .font(Theme.mono(10, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Theme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .position(x: bubbleX, y: y - 18)
                        .transition(.opacity)
                }
            }
            .frame(height: 46)

            // Health bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.08))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(healthBarColor)
                        .frame(width: geo.size.width * health)
                }
            }
            .frame(height: 4)
            .padding(.horizontal, 40)
        }
        .onAppear {
            loadDots()
            // Greet on open
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showBubble(pick(from: Self.greetingLines))
            }
        }
        .onReceive(moveTimer) { _ in
            if movingRight {
                position = min(position + speed, 1.0)
                if position >= 1.0 {
                    movingRight = false
                    tripBounce()
                }
            } else {
                position = max(position - speed, 0.0)
                if position <= 0.0 {
                    movingRight = true
                    tripBounce()
                }
            }
            eatNearbyDots()
        }
        .onReceive(chompTimer) { _ in
            mouthOpen.toggle()
        }
    }

    private var healthBarColor: Color {
        if health > 0.6 { return Theme.correctGreen }
        if health > 0.3 { return Theme.streakYellow }
        return Theme.accent
    }

    private var tripThoughts: [String] {
        // First trip after greeting = noms
        if tripCount <= 1 {
            return Self.firstTripLines
        }
        // After a while, chill thoughts
        if tripCount >= 4 {
            return Self.chillLines
        }
        // Middle trips = mood-based
        if health < 0.15 {
            return Self.starvingIdleLines
        } else if health < 0.3 {
            return Self.hungryIdleLines
        } else if health > 0.85 {
            return Self.happyIdleLines
        } else {
            return Self.neutralIdleLines
        }
    }

    private func tripBounce() {
        tripCount += 1
        if pacMathScreenshotMode {
            let next = pick(from: Self.screenshotPetLines)
            lastBubbleText = next
            recentBubbleTexts.append(next)
            if recentBubbleTexts.count > 6 {
                recentBubbleTexts.removeFirst(recentBubbleTexts.count - 6)
            }
            withAnimation(.easeOut(duration: 0.2)) {
                speechBubble = next
            }
            return
        }
        guard dots.isEmpty, speechBubble == nil, !spokeThisTrip else { return }
        spokeThisTrip = true
        showBubble(pick(from: tripThoughts))
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            spokeThisTrip = false
        }
    }

    private static let screenshotPetLines = [
        "hi!", "feed me?", "noms?", "ready for math.", "feeling sharp.",
        "hungry.", "hello!", "got snacks?", "math is cool."
    ]

    /// Correct + fast = big green. Correct + slow = small green.
    /// Wrong + slow = big nasty. Wrong + fast = small nasty.
    private func dotSize(for p: GameEngine.ProblemResult) -> CGFloat {
        let t = min(max(p.solveTimeSeconds, 1.0), 10.0)
        let timeRatio = (t - 1.0) / 9.0 // 0 at 1s, 1 at 10s

        if p.isCorrect {
            // Fast = big, slow = small
            return 6 + CGFloat(1.0 - timeRatio) * 8  // 14..6
        } else {
            // Slow = big, fast = small
            return 5 + CGFloat(timeRatio) * 8         // 5..13
        }
    }

    private static let goodReactions = [
        "solid snack.", "nice one.", "that helps.", "good bite.", "okay, yes."
    ]
    private static let badReactions = [
        "bleh.", "not that.", "bad bite.", "nope.", "absolutely not."
    ]
    private static let fullReactions = [
        "back in business.", "okay, I'm good.", "that did it.", "fuel restored."
    ]
    private static let mealSummarySatisfied = [
        "that hit the spot.", "good round.", "clean meal.", "well fed."
    ]
    private static let mealSummaryHungry = [
        "better, not full.", "could do another.", "still room for more.", "more when you're ready."
    ]
    private static let starvingIdleLines = [
        "running on fumes.", "need a round.", "very low fuel.", "could really eat."
    ]
    private static let hungryIdleLines = [
        "feed me?", "one quick round?", "got any math?", "ready for more."
    ]
    private static let happyIdleLines = [
        "feeling sharp.", "ready when you are.", "still buzzing.", "good energy."
    ]
    private static let neutralIdleLines = [
        "thinking...", "math is cool.", "what's next?", "just vibing.", "chomp chomp.", "hi."
    ]
    private static let greetingLines = [
        "hey!", "hi there.", "oh hey!", "hello!", "yo!", "hiii."
    ]
    private static let firstTripLines = [
        "noms?", "hungry.", "got snacks?", "feed me?", "noms plz."
    ]
    private static let chillLines = [
        "don't mind me.", "feelin hungry.", "just chillin.", "noms?", "still here.", "waitin."
    ]

    private func eatNearbyDots() {
        let eatRadius: CGFloat = 0.04
        dots.removeAll { dot in
            if abs(dot.x - position) < eatRadius {
                let previousHealth = health
                let sizeRatio = (dot.size - 4) / 10
                withAnimation(.easeOut(duration: 0.3)) {
                    if dot.isGood {
                        health = min(1.0, health + 0.04 + 0.08 * sizeRatio)
                    } else {
                        health = max(0.0, health - 0.05)
                    }
                }
                saveHealth()
                dotsEatenThisMeal += 1

                // Keep meal commentary sparse and tied to noticeable moments.
                if dot.isGood {
                    if previousHealth < 0.72 && health >= 0.72 {
                        tryMealBubble(from: Self.fullReactions, minInterval: 4.5)
                    } else if previousHealth < 0.25 && health >= 0.25 {
                        tryMealBubble(from: Self.goodReactions, minInterval: 4.5)
                    } else if dotsEatenThisMeal == 1 {
                        tryMealBubble(from: Self.goodReactions, chance: 0.45, minInterval: 4.5)
                    }
                } else {
                    tryMealBubble(from: Self.badReactions, chance: 0.35, minInterval: 4.5)
                }

                return true
            }
            return false
        }

        // All dots eaten
        if dots.isEmpty && mealBubbleBudget > 0 && !mealSummaryScheduled {
            mealSummaryScheduled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                guard dots.isEmpty else { return }
                guard speechBubble == nil else { return }
                guard dotsEatenThisMeal >= 3 else { return }

                if health > 0.6 {
                    tryMealBubble(from: Self.mealSummarySatisfied, minInterval: 0)
                } else {
                    tryMealBubble(from: Self.mealSummaryHungry, minInterval: 0)
                }
            }
        }
    }

    private func pick(from pool: [String]) -> String {
        guard pool.count > 1 else { return pool.first ?? "" }
        let blocked = Set(recentBubbleTexts.suffix(4))
        let candidates = pool.filter { $0 != lastBubbleText && !blocked.contains($0) }
        return (candidates.isEmpty ? pool : candidates).randomElement() ?? pool[0]
    }

    private func canSpeak(minInterval: TimeInterval) -> Bool {
        Date().timeIntervalSince(lastBubbleTime) > minInterval
    }

    private func tryMealBubble(from pool: [String], chance: Double = 1.0, minInterval: TimeInterval) {
        guard mealBubbleBudget > 0 else { return }
        guard canSpeak(minInterval: minInterval) else { return }
        guard Double.random(in: 0...1) <= chance else { return }
        mealBubbleBudget -= 1
        showBubble(pick(from: pool))
    }

    private func showBubble(_ text: String) {
        guard speechBubble == nil else { return }
        lastBubbleText = text
        recentBubbleTexts.append(text)
        if recentBubbleTexts.count > 6 {
            recentBubbleTexts.removeFirst(recentBubbleTexts.count - 6)
        }
        lastBubbleTime = Date()
        withAnimation(.easeOut(duration: 0.15)) {
            speechBubble = text
        }
        guard !pacMathScreenshotMode else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeIn(duration: 0.3)) {
                speechBubble = nil
            }
        }
    }

    private func saveHealth() {
        UserDefaults.standard.set(Double(health), forKey: Self.healthKey)
        UserDefaults.standard.set(Date(), forKey: Self.lastFeedKey)
    }

    private func loadDots() {
        position = 0.0
        movingRight = true
        mealBubbleBudget = 0
        dotsEatenThisMeal = 0
        mealSummaryScheduled = false

        // Load persisted health with time decay
        let defaults = UserDefaults.standard
        let hasNewHealth = defaults.object(forKey: Self.healthKey) != nil
        let saved = CGFloat(defaults.double(forKey: hasNewHealth ? Self.healthKey : Self.legacyHealthKey))
        if let lastFeed = (defaults.object(forKey: Self.lastFeedKey) as? Date) ??
            (defaults.object(forKey: Self.legacyLastFeedKey) as? Date) {
            let hoursSince = Date().timeIntervalSince(lastFeed) / 3600
            let decay = CGFloat(hoursSince * 0.03) // ~3% per hour, ~72% per day
            health = max(0.0, saved - decay)
            if !hasNewHealth {
                saveHealth()
            }
        } else {
            // First launch ever
            health = 0.5
            saveHealth()
        }

        // Load dots from last game if available
        guard let result = engine.lastGameResult else {
            dots = []
            return
        }

        let problems = result.problems
        guard !problems.isEmpty else { return }

        dots = problems.enumerated().map { i, p in
            let x = CGFloat(i + 1) / CGFloat(problems.count + 1)
            return ChompDot(
                x: x,
                isGood: p.isCorrect,
                size: dotSize(for: p)
            )
        }
        mealBubbleBudget = problems.count >= 6 ? 2 : (problems.count >= 3 ? 1 : 0)
    }
}

// MARK: - Mini Chomp for buttons

struct MiniChompView: View {
    private let profile = ChompyProfile.shared

    @State private var position: CGFloat = 0.0
    @State private var movingRight = true
    @State private var mouthOpen = false

    private let moveTimer = Timer.publish(every: 0.03, on: .main, in: .common).autoconnect()
    private let chompTimer = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geo in
            ChompShape(mouthAngle: (pacMathScreenshotMode || mouthOpen) ? 40 : 2, facingRight: movingRight)
                .fill(profile.color)
                .frame(width: 16, height: 16)
                .position(
                    x: 8 + position * (geo.size.width - 16),
                    y: geo.size.height / 2
                )
        }
        .onReceive(moveTimer) { _ in
            if movingRight {
                position = min(position + 0.005, 1.0)
                if position >= 1.0 { movingRight = false }
            } else {
                position = max(position - 0.005, 0.0)
                if position <= 0.0 { movingRight = true }
            }
        }
        .onReceive(chompTimer) { _ in
            mouthOpen.toggle()
        }
    }
}

// MARK: - Game Chomp (lives on the game screen)

/// Wrapper that reads engine and passes messages to the animation view.
struct GameChompView: View {
    var engine: GameEngine

    @State private var bubble: String? = nil
    @State private var lastBubbleTime: Date = .distantPast
    @State private var lastBubbleText: String = ""
    @State private var recentBubbleTexts: [String] = []
    @State private var lastCelebratedStreak: Int = 0

    private static let wrongSays = [
        "oof.", "rough one.", "missed it.", "not that.", "shake it off."
    ]
    private static let skipSays = [
        "too slow.", "we'll get the next one.", "next bite.", "keep moving."
    ]
    private static let earlyStreakSays = [
        "there it is.", "warming up.", "okay, now we're moving.", "that's a run."
    ]
    private static let midStreakSays = [
        "locked in.", "clean work.", "that's real momentum.", "now we're cooking."
    ]
    private static let bigStreakSays = [
        "dialed in.", "this is a feast.", "do not blink.", "serious run."
    ]
    private static let streakMilestones: Set<Int> = [3, 5, 8, 12, 16, 20]

    private static let screenshotGameLines = [
        "locked in.", "clean work.", "that's a run.", "still cooking.",
        "serious run.", "nice one.", "chomp.", "dialed in.", "feast mode."
    ]

    private func rotateScreenshotBubble() {
        let line = pick(from: Self.screenshotGameLines)
        lastBubbleText = line
        recentBubbleTexts.append(line)
        if recentBubbleTexts.count > 6 {
            recentBubbleTexts.removeFirst(recentBubbleTexts.count - 6)
        }
        withAnimation(.easeOut(duration: 0.2)) {
            bubble = line
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            guard pacMathScreenshotMode else { return }
            rotateScreenshotBubble()
        }
    }

    private func streakPool(for streak: Int) -> [String] {
        switch streak {
        case 0..<5:
            return Self.earlyStreakSays
        case 5..<12:
            return Self.midStreakSays
        default:
            return Self.bigStreakSays
        }
    }

    private func shouldCelebrate(streak: Int) -> Bool {
        if Self.streakMilestones.contains(streak) { return true }
        return streak >= 24 && streak.isMultiple(of: 6)
    }

    var body: some View {
        GameChompAnimator(bubble: bubble)
            .onAppear {
                lastCelebratedStreak = 0
                recentBubbleTexts = []
                if pacMathScreenshotMode {
                    rotateScreenshotBubble()
                }
            }
            .onChange(of: engine.feedbackType) { _, newType in
                guard newType != .none else { return }

                switch newType {
                case .correct:
                    guard shouldCelebrate(streak: engine.streak) else { return }
                    guard engine.streak > lastCelebratedStreak else { return }
                    guard canSpeak(minInterval: 4.5) else { return }
                    lastCelebratedStreak = engine.streak
                    showBubble(pick(from: streakPool(for: engine.streak)))
                case .wrong:
                    guard engine.wrong == 1 || engine.wrong.isMultiple(of: 2) else { return }
                    guard canSpeak(minInterval: 5.0) else { return }
                    showBubble(pick(from: Self.wrongSays))
                case .skip:
                    guard canSpeak(minInterval: 5.0) else { return }
                    showBubble(pick(from: Self.skipSays))
                case .none:
                    break
                }
            }
    }

    private func pick(from pool: [String]) -> String {
        guard pool.count > 1 else { return pool.first ?? "" }
        let blocked = Set(recentBubbleTexts.suffix(4))
        let candidates = pool.filter { $0 != lastBubbleText && !blocked.contains($0) }
        return (candidates.isEmpty ? pool : candidates).randomElement() ?? pool[0]
    }

    private func canSpeak(minInterval: TimeInterval) -> Bool {
        Date().timeIntervalSince(lastBubbleTime) > minInterval
    }

    private func showBubble(_ text: String) {
        guard bubble == nil else { return }
        lastBubbleText = text
        recentBubbleTexts.append(text)
        if recentBubbleTexts.count > 6 {
            recentBubbleTexts.removeFirst(recentBubbleTexts.count - 6)
        }
        lastBubbleTime = Date()
        withAnimation(.easeOut(duration: 0.15)) {
            bubble = text
        }
        guard !pacMathScreenshotMode else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeIn(duration: 0.2)) {
                bubble = nil
            }
        }
    }
}

/// Pure animation — no engine dependency, never disrupted by game state changes.
private struct GameChompAnimator: View {
    var bubble: String?
    private let profile = ChompyProfile.shared

    @State private var position: CGFloat = 0.3
    @State private var movingRight = true
    @State private var mouthOpen = false
    @State private var frameCount: Int = 0

    private let moveTimer = Timer.publish(every: 0.03, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let chompX = position * (w - 40) + 20
            let y = geo.size.height / 2

            ChompShape(mouthAngle: (pacMathScreenshotMode || mouthOpen) ? 45 : 2, facingRight: movingRight)
                .fill(profile.color)
                .frame(width: 20, height: 20)
                .position(x: chompX, y: y)

            if let text = bubble {
                let bubbleX = movingRight
                    ? min(chompX + 45, w - 30)
                    : max(chompX - 45, 30)
                Text(text)
                    .font(Theme.mono(10, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Theme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .position(x: bubbleX, y: y - 16)
                    .transition(.opacity)
            }
        }
        .frame(height: 32)
        .padding(.horizontal, 24)
        .onReceive(moveTimer) { _ in
            if movingRight {
                position = min(position + 0.002, 1.0)
                if position >= 1.0 { movingRight = false }
            } else {
                position = max(position - 0.002, 0.0)
                if position <= 0.0 { movingRight = true }
            }
            frameCount += 1
            if frameCount % 8 == 0 {
                mouthOpen.toggle()
            }
        }
    }
}

// MARK: - Data

struct ChompDot: Identifiable {
    let id = UUID()
    var x: CGFloat
    let isGood: Bool
    let size: CGFloat
}

struct ChompShape: Shape {
    var mouthAngle: Double
    var facingRight: Bool

    var animatableData: Double {
        get { mouthAngle }
        set { mouthAngle = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2

        let halfMouth = mouthAngle / 2
        let startAngle: Double
        let endAngle: Double

        if facingRight {
            startAngle = halfMouth
            endAngle = 360 - halfMouth
        } else {
            startAngle = 180 + halfMouth
            endAngle = 180 - halfMouth
        }

        var path = Path()
        path.move(to: center)
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(startAngle),
            endAngle: .degrees(endAngle),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}
