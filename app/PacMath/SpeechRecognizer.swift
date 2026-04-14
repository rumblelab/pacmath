import Foundation
import Speech
import AVFoundation
import Observation

@Observable
class SpeechRecognizer {

    // MARK: - Public state

    var transcript: String = ""
    var isListening: Bool = false
    var isAuthorized: Bool = false
    var isUnavailable: Bool = false
    var onNumber: ((Int) -> Void)?

    // MARK: - Private state

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    private var echoA: Int?
    private var echoB: Int?
    private var expectedAnswer: Int?

    /// Pending number from interim results, waiting to be confirmed by stability.
    private var pendingNumber: Int?
    private var pendingTimer: Timer?

    /// Numbers already delivered via `onNumber` this session, to avoid double-firing.
    private var deliveredNumbers: Set<Int> = []

    /// Generation counter to prevent stale callbacks from triggering restarts.
    private var sessionGeneration: Int = 0

    /// Errors since the last successful (non-empty) recognition result. Used to detect
    /// persistent failure (e.g. offline with no on-device model) and fall back to keypad.
    private var consecutiveErrors: Int = 0
    private static let unavailableErrorThreshold = 3

    // MARK: - Word-to-number tables

    private static let onesMap: [String: Int] = [
        "zero": 0, "oh": 0,
        "one": 1, "two": 2, "three": 3,
        "four": 4, "poor": 4, "pour": 4,
        "five": 5, "six": 6, "sex": 6,
        "seven": 7, "eight": 8, "nine": 9, "ten": 10,
        "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14,
        "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18,
        "nineteen": 19
    ]

    private static let tensMap: [String: Int] = [
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50,
        "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90
    ]

    private static let ambiguousMap: [String: Int] = [
        "to": 2, "too": 2, "for": 4
    ]

    private static let fillerPatterns: [String] = [
        "the answer is", "it is", "its", "it's",
        "that is", "that's", "is equal to",
        "equals", "i think", "i say", "i got",
        "umm", "um", "uh", "hmm", "hm",
        "well", "like", "maybe", "so", "okay", "ok",
        "is"
    ]

    /// Regexes for stretched filler words like "issssss" or "ummmm".
    private static let stretchyFillerPatterns: [String] = [
        "\\bis+\\b",
        "\\bum+\\b",
        "\\buh+\\b",
        "\\bh+m+\\b",
        "\\bok+a+y*\\b"
    ]

    private static let operatorWords: [String] = [
        "plus", "minus", "times", "divided by", "multiplied by",
        "add", "subtract", "and", "x", "over", "take away",
        "+", "-", "×", "÷", "*", "/"
    ]

    private static let promptLeadIns: [String] = [
        "what's", "whats", "what is"
    ]

    // MARK: - Public methods

    func requestAuthorization(completion: ((Bool) -> Void)? = nil) {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                guard let self else {
                    completion?(false)
                    return
                }
                switch status {
                case .authorized:
                    self.requestMicrophoneAccess(completion: completion)
                default:
                    self.isAuthorized = false
                    completion?(false)
                }
            }
        }
    }

    @discardableResult
    func start(echoA: Int?, echoB: Int?, expectedAnswer: Int?) -> Bool {
        // Clean up any previous session first.
        cleanUp()

        self.echoA = echoA
        self.echoB = echoB
        self.expectedAnswer = expectedAnswer
        self.transcript = ""
        self.deliveredNumbers = []
        self.pendingNumber = nil
        self.consecutiveErrors = 0
        self.isUnavailable = false

        guard isAuthorized else {
            isListening = false
            return false
        }
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            isListening = false
            isUnavailable = true
            return false
        }

        do {
            let didStart = try startRecognitionSession(speechRecognizer: speechRecognizer)
            isListening = didStart
            if !didStart { isUnavailable = true }
            return didStart
        } catch {
            print("[SpeechRecognizer] Failed to start: \(error.localizedDescription)")
            isListening = false
            isUnavailable = true
            return false
        }
    }

    /// Light restart for the next problem. Keeps the audio engine alive so UI animation
    /// doesn't hitch when the game swaps prompts.
    @discardableResult
    func restartRecognition(echoA: Int?, echoB: Int?, expectedAnswer: Int?) -> Bool {
        self.echoA = echoA
        self.echoB = echoB
        self.expectedAnswer = expectedAnswer
        self.transcript = ""
        self.deliveredNumbers = []
        self.consecutiveErrors = 0
        self.isUnavailable = false
        cancelPending()

        guard isAuthorized else {
            isListening = false
            return false
        }
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            isListening = false
            isUnavailable = true
            return false
        }

        cleanUpRecognition()

        do {
            let didStart = try startRecognitionSession(speechRecognizer: speechRecognizer)
            isListening = didStart
            if !didStart { isUnavailable = true }
            return didStart
        } catch {
            print("[SpeechRecognizer] Failed to restart lightly: \(error.localizedDescription)")
            isListening = false
            isUnavailable = true
            return false
        }
    }

    func stop(deactivateSession: Bool = true) {
        isListening = false
        cleanUp()
        if deactivateSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    // MARK: - Private: Authorization

    private func requestMicrophoneAccess(completion: ((Bool) -> Void)? = nil) {
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                self?.isAuthorized = granted
                completion?(granted)
            }
        }
    }

    // MARK: - Private: Audio engine (kept running across recognition restarts)

    private var engineRunning = false

    private func ensureAudioEngine() throws -> Bool {
        if engineRunning && audioEngine.isRunning { return true }

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .mixWithOthers])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        guard let inputs = audioSession.availableInputs, !inputs.isEmpty else {
            return false
        }

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            return false
        }

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        engineRunning = true
        return true
    }

    private func stopAudioEngine() {
        audioEngine.inputNode.removeTap(onBus: 0)
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        engineRunning = false
    }

    // MARK: - Private: Recognition session

    @discardableResult
    private func startRecognitionSession(speechRecognizer: SFSpeechRecognizer) throws -> Bool {
        guard try ensureAudioEngine() else { return false }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .confirmation
        // Always force on-device so audio never leaves the device, even in edge
        // cases where a locale model isn't installed. If on-device isn't available,
        // recognition will error and isUnavailable handling falls back to keypad.
        request.requiresOnDeviceRecognition = true
        if #available(iOS 17, *) {
            request.addsPunctuation = false
        }
        self.recognitionRequest = request

        sessionGeneration += 1
        let gen = sessionGeneration

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            DispatchQueue.main.async {
                guard gen == self.sessionGeneration else { return }

                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    self.handleResult(text: result.bestTranscription.formattedString, isFinal: result.isFinal)
                    if !result.bestTranscription.formattedString.isEmpty {
                        self.consecutiveErrors = 0
                    }
                }

                if error != nil {
                    self.consecutiveErrors += 1
                    if self.consecutiveErrors >= Self.unavailableErrorThreshold {
                        self.cleanUpRecognition()
                        self.isListening = false
                        self.isUnavailable = true
                        return
                    }
                }

                if error != nil || (result?.isFinal ?? false) {
                    self.cleanUpRecognition()
                    if self.isListening {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                            guard let self, self.isListening else { return }
                            guard gen == self.sessionGeneration else { return }
                            guard let sr = self.speechRecognizer, sr.isAvailable else {
                                self.isListening = false
                                self.isUnavailable = true
                                return
                            }
                            self.transcript = ""
                            self.deliveredNumbers = []
                            do {
                                try self.startRecognitionSession(speechRecognizer: sr)
                            } catch {
                                print("[SpeechRecognizer] Restart failed: \(error.localizedDescription)")
                                self.isListening = false
                                self.isUnavailable = true
                            }
                        }
                    }
                }
            }
        }

        return true
    }

    // MARK: - Private: Cleanup

    /// Light cleanup — only the recognition task/request. Audio engine keeps running.
    private func cleanUpRecognition() {
        pendingTimer?.invalidate()
        pendingTimer = nil
        pendingNumber = nil

        recognitionTask?.cancel()
        recognitionTask = nil

        recognitionRequest?.endAudio()
        recognitionRequest = nil
    }

    /// Full cleanup — tears down everything including the audio engine.
    private func cleanUp() {
        cleanUpRecognition()
        stopAudioEngine()
    }

    // MARK: - Private: Result handling

    private func handleResult(text: String, isFinal: Bool) {
        guard let number = extractNumber(from: text) else {
            // No number detected.
            // If it looks like a prompt read, cancel any pending number from before
            // (e.g. they said a number then started reading the prompt).
            if looksLikePromptRead(text) {
                cancelPending()
                if isFinal {
                    // Swallow full prompt-read utterances that don't end in an answer
                    // and wait for the next clean answer.
                    transcript = ""
                }
            } else if isFinal {
                cancelPending()
            }
            return
        }

        let isOperand = isLikelyPromptOperand(number, in: text)

        if isFinal {
            // Never lock in a read-aloud as a final wrong answer.
            // If they said "5" and it's an operand (but not the answer),
            // and the recognizer cut the session there, ignore it.
            if isOperand {
                cancelPending()
                transcript = ""
            } else {
                acceptNumber(number)
            }
        } else {
            // Interim result: fast-path correct answers to eliminate lag.
            if number == expectedAnswer && !isOperand {
                acceptNumber(number)
                return
            }

            // Otherwise use pending timer approach.
            if pendingNumber == number {
                // Same number still holding — timer already running.
                return
            }
            // New or changed number — reset timer.
            cancelPending()
            pendingNumber = number

            // If it's an operand (and not the correct answer), give them more time
            // to finish reading the problem before counting it as "wrong".
            // Non-operands get the standard fast 0.8s feedback.
            let timeout = isOperand ? 1.5 : 0.8

            pendingTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if let n = self.pendingNumber {
                        self.acceptNumber(n)
                    }
                }
            }
        }
    }

    private func acceptNumber(_ number: Int) {
        cancelPending()
        guard !deliveredNumbers.contains(number) else { return }
        deliveredNumbers.insert(number)
        onNumber?(number)
    }

    private func cancelPending() {
        pendingTimer?.invalidate()
        pendingTimer = nil
        pendingNumber = nil
    }

    private func isLikelyPromptOperand(_ number: Int, in text: String) -> Bool {
        guard number == echoA || number == echoB else { return false }
        guard number != expectedAnswer else { return false }

        let cleaned = cleanFillers(text.lowercased())
        let words = cleaned.split(separator: " ")

        // Only suppress bare one-number partials like "five" while the child is
        // starting to read the prompt. If they say anything richer, let other
        // prompt-read heuristics handle it.
        return words.count <= 1
    }

    private func looksLikePromptRead(_ text: String) -> Bool {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        if Self.promptLeadIns.contains(where: { lower.hasPrefix($0) }) {
            return true
        }

        if Self.operatorWords.contains(where: { lower.contains($0) }) {
            return true
        }

        if lower.contains("+") || lower.contains("-") || lower.contains("×") || lower.contains("÷") || lower.contains("=") {
            return true
        }

        return false
    }

    // MARK: - Private: Number extraction

    private func extractNumber(from rawText: String) -> Int? {
        var text = rawText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        // Strip problem echo (e.g. "three plus seven")
        text = stripEcho(from: text)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        // 1) Try digit extraction first — find digit sequences, take the last.
        let digitMatches = text.matches(of: /\d+/)
        if let lastMatch = digitMatches.last {
            let digits = String(lastMatch.output)
            if let value = Int(digits) {
                // Check for "negative" / "minus" prefix
                let prefixRange = text.startIndex..<lastMatch.range.lowerBound
                let prefix = String(text[prefixRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                let isNegative = prefix.hasSuffix("negative") || prefix.hasSuffix("minus")
                return isNegative ? -value : value
            }
        }

        // 2) Clean filler words
        text = cleanFillers(text)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        // 3) Handle negative prefix
        var isNegative = false
        if text.hasPrefix("negative ") || text.hasPrefix("minus ") {
            isNegative = true
            text = String(text.drop(while: { $0 != " " })).trimmingCharacters(in: .whitespaces)
        }

        // 4) Check ambiguous words — only if the entire cleaned text is exactly the word.
        if let ambiguous = Self.ambiguousMap[text] {
            return isNegative ? -ambiguous : ambiguous
        }

        // 5) Parse word-based numbers — try from each word position
        //    so "blah eight" → skip "blah", parse "eight" → 8
        let words = text.split(separator: " ").map(String.init)
        for start in words.indices {
            let segment = words[start...].joined(separator: " ")
            if let parsed = parseWordNumber(segment) {
                return isNegative ? -parsed : parsed
            }
        }

        // 6) Ambiguous words — check last word
        if let last = words.last, let value = Self.ambiguousMap[last] {
            return isNegative ? -value : value
        }

        return nil
    }

    // MARK: - Private: Filler cleaning

    private func cleanFillers(_ text: String) -> String {
        var result = text

        for pattern in Self.stretchyFillerPatterns {
            result = result.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }

        // Sort longest-first so "the answer is" matches before "is"
        let sorted = Self.fillerPatterns.sorted { $0.count > $1.count }
        for filler in sorted {
            let escaped = NSRegularExpression.escapedPattern(for: filler)
            let pattern = "\\b\(escaped)\\b"
            result = result.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        // Collapse whitespace
        result = result.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Private: Echo stripping

    private func stripEcho(from text: String) -> String {
        guard let a = echoA, let b = echoB else { return text }

        // Build patterns for both operand numbers.
        let aWords = numberToWords(a)
        let bWords = numberToWords(b)

        // Also include digit representations.
        var aPatterns = aWords + ["\(abs(a))"]
        var bPatterns = bWords + ["\(abs(b))"]

        // Deduplicate
        aPatterns = Array(Set(aPatterns))
        bPatterns = Array(Set(bPatterns))

        let aGroup = aPatterns.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        let bGroup = bPatterns.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        let opGroup = Self.operatorWords.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")

        // Match a [op] b, with optional spaces and an optional "is", "equals" or "=" at the end.
        let pattern = "(?:\(aGroup))\\s*(?:\(opGroup))\\s*(?:\(bGroup))(?:\\s*(?:is|equals|=))?"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return text
        }

        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: " ")
    }

    /// Convert an integer to its English word representations for echo matching.
    private func numberToWords(_ n: Int) -> [String] {
        let absN = abs(n)
        var results: [String] = []

        if let word = Self.onesMap.first(where: { $0.value == absN && $0.key != "oh" })?.key {
            results.append(word)
        }

        if absN >= 20 && absN <= 99 {
            let tens = (absN / 10) * 10
            let ones = absN % 10
            if let tensWord = Self.tensMap.first(where: { $0.value == tens })?.key {
                if ones == 0 {
                    results.append(tensWord)
                } else if let onesWord = Self.onesMap.first(where: { $0.value == ones && $0.key != "oh" })?.key {
                    results.append("\(tensWord) \(onesWord)")
                }
            }
        }

        if absN >= 100 && absN <= 999 {
            let hundreds = absN / 100
            let remainder = absN % 100
            if let hundredsWord = Self.onesMap.first(where: { $0.value == hundreds && $0.key != "oh" })?.key {
                if remainder == 0 {
                    results.append("\(hundredsWord) hundred")
                } else {
                    // Recursively get the remainder words
                    let remWords = numberToWords(remainder)
                    for rw in remWords {
                        results.append("\(hundredsWord) hundred \(rw)")
                        results.append("\(hundredsWord) hundred and \(rw)")
                    }
                }
            }
        }

        if absN >= 1000 {
            let thousands = absN / 1000
            let remainder = absN % 1000
            if let thWord = Self.onesMap.first(where: { $0.value == thousands && $0.key != "oh" })?.key {
                if remainder == 0 {
                    results.append("\(thWord) thousand")
                } else {
                    let remWords = numberToWords(remainder)
                    for rw in remWords {
                        results.append("\(thWord) thousand \(rw)")
                    }
                }
            }
        }

        return results
    }

    // MARK: - Private: Word-to-number parsing

    /// Parse a string of English number words into an Int.
    /// Handles compounds like "twenty three", "one hundred forty four", "two thousand three hundred".
    private func parseWordNumber(_ text: String) -> Int? {
        let words = text.split(separator: " ").map { String($0) }
        guard !words.isEmpty else { return nil }

        var total = 0
        var current = 0
        var hasNumber = false

        var i = 0
        while i < words.count {
            let word = words[i]

            if let ones = Self.onesMap[word] {
                current += ones
                hasNumber = true
                i += 1
            } else if let tens = Self.tensMap[word] {
                current += tens
                hasNumber = true
                i += 1
            } else if word == "hundred" {
                // "hundred" multiplies whatever is in current (or 1 if nothing).
                if current == 0 { current = 1 }
                current *= 100
                hasNumber = true
                i += 1
            } else if word == "thousand" {
                // "thousand" multiplies current and shifts to total.
                if current == 0 { current = 1 }
                total += current * 1000
                current = 0
                hasNumber = true
                i += 1
            } else if word == "and" {
                // Skip "and" in constructions like "one hundred and twenty three"
                i += 1
            } else {
                // Non-number word found — treat as chatter.
                return nil
            }
        }

        guard hasNumber else { return nil }

        total += current
        return total
    }
}
