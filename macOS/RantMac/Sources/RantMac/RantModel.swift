import AppKit
import AVFoundation
import Combine
import Foundation

enum RantMode: String, CaseIterable, Identifiable {
    case dictate, prd, fix, structure
    var id: String { rawValue }
    var title: String {
        switch self {
        case .dictate: "Dictate"
        case .prd: "PRD"
        case .fix: "Fix"
        case .structure: "Structure"
        }
    }
    var hint: String {
        switch self {
        case .dictate: "Speak naturally. Rant removes filler and smooths the rough edges."
        case .prd: "Describe a feature or product idea. Get a clear, implementation-ready PRD."
        case .fix: "Explain what’s broken. Get a reproduction-focused fix brief."
        case .structure: "Think out loud. Rant organizes what you said without adding details."
        }
    }
}

enum RewriteStyle: String, CaseIterable, Identifiable {
    case natural, concise, professional, email
    var id: String { rawValue }
    var title: String {
        switch self {
        case .natural: "Natural"
        case .concise: "Concise"
        case .professional: "Professional"
        case .email: "Email"
        }
    }
}

struct DictationEntry: Codable, Identifiable {
    let id: UUID
    let text: String
    let date: Date
}

@MainActor
final class RantModel: ObservableObject {
    @Published var mode: RantMode = .dictate
    @Published var style: RewriteStyle = .natural
    @Published var isStarting = false
    @Published var isRecording = false
    @Published var isProcessing = false
    @Published var isSigningIn = false
    @Published var rawTranscript = ""
    @Published var outputText = ""
    @Published var status = "Ready when you are"
    @Published var shortcutLabel = "⌘⌥ Space"
    @Published var errorMessage: String?
    @Published var history: [DictationEntry] = []
    @Published var autoPaste = true
    @Published var speechEnabled = false

    let speech = SpeechCapture()
    let auth = ChatGPTOAuth()
    private var planClient: ChatGPTPlanClient!
    private let synthesizer = AVSpeechSynthesizer()
    private var startedFromShortcut = false
    private var targetBundleID: String?
    private var lastTargetBundleID: String?
    private let historyKey = "rant.dictation.history"

    init() {
        planClient = ChatGPTPlanClient(auth: auth)
        if let data = UserDefaults.standard.data(forKey: historyKey),
           let entries = try? JSONDecoder().decode([DictationEntry].self, from: data) {
            history = entries
        }
        autoPaste = UserDefaults.standard.object(forKey: "rant.auto-paste") as? Bool ?? true
    }

    var canUseGPT: Bool { auth.isPlanEnabled }

    func toggleFromShortcut() {
        if isRecording {
            Task { await finishRecording() }
        } else if isStarting || isProcessing {
            return
        } else {
            startedFromShortcut = true
            targetBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            isStarting = true
            Task { await beginRecording() }
        }
    }

    func setShortcutLabel(_ label: String?) {
        shortcutLabel = label ?? "Unavailable"
        if label == nil { status = "Global shortcut unavailable · check for a key conflict" }
    }

    func toggleRecordingFromWindow() {
        if isRecording {
            Task { await finishRecording() }
        } else if isStarting || isProcessing {
            return
        } else {
            startedFromShortcut = false
            targetBundleID = nil
            isStarting = true
            Task { await beginRecording() }
        }
    }

    func beginRecording() async {
        errorMessage = nil
        rawTranscript = ""
        outputText = ""
        do {
            try await speech.start()
            isStarting = false
            isRecording = true
            status = "Listening · \(shortcutLabel) to finish"
        } catch {
            speech.cancel()
            isStarting = false
            isRecording = false
            startedFromShortcut = false
            targetBundleID = nil
            errorMessage = error.localizedDescription
            status = "Microphone unavailable"
        }
    }

    func finishRecording() async {
        guard isRecording else { return }
        isRecording = false
        isProcessing = true
        status = "Finishing transcript…"
        let text = await speech.stop()
        rawTranscript = text
        guard !text.isEmpty else {
            isProcessing = false
            status = "No speech found"
            startedFromShortcut = false
            targetBundleID = nil
            return
        }

        if canUseGPT {
            status = mode == .dictate ? "Polishing your words…" : "Building your brief…"
            do {
                outputText = try await planClient.rewrite(text, instructions: instructions(for: mode, style: style))
                status = "Ready to insert"
            } catch {
                outputText = text
                errorMessage = error.localizedDescription
                status = "Transcript ready · GPT cleanup unavailable"
            }
        } else {
            outputText = text
            status = "Transcript ready · sign in to enable GPT cleanup"
        }

        saveHistory(outputText)
        if startedFromShortcut && mode == .dictate && autoPaste {
            let pasted = await PasteBridge.paste(outputText, into: targetBundleID)
            status = pasted ? "Inserted into the previous app" : "Copied · select the target app and paste"
        } else {
            PasteBridge.copy(outputText)
        }
        if startedFromShortcut { lastTargetBundleID = targetBundleID }
        if speechEnabled { speakOutput() }
        startedFromShortcut = false
        targetBundleID = nil
        isProcessing = false
    }

    func rewriteCurrentText() async {
        let text = rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard canUseGPT else {
            errorMessage = "Sign in with ChatGPT to polish text using your plan."
            return
        }
        isProcessing = true
        errorMessage = nil
        status = "Polishing your words…"
        do {
            outputText = try await planClient.rewrite(text, instructions: instructions(for: mode, style: style))
            status = "Ready to insert"
            saveHistory(outputText)
        } catch {
            errorMessage = error.localizedDescription
            status = "Couldn’t polish the transcript"
        }
        isProcessing = false
    }

    func insertOutput() {
        let text = outputText.isEmpty ? rawTranscript : outputText
        guard !text.isEmpty else { return }
        Task {
            let pasted = await PasteBridge.paste(text, into: lastTargetBundleID)
            status = pasted ? "Inserted into the previous app" : "Copied · select the target app and paste"
        }
    }

    func copyOutput() {
        let text = outputText.isEmpty ? rawTranscript : outputText
        guard !text.isEmpty else { return }
        PasteBridge.copy(text)
        status = "Copied to clipboard"
    }

    func speakOutput() {
        let text = outputText.isEmpty ? rawTranscript : outputText
        guard !text.isEmpty else { return }
        synthesizer.stopSpeaking(at: .immediate)
        synthesizer.speak(AVSpeechUtterance(string: text))
    }

    func stopSpeaking() { synthesizer.stopSpeaking(at: .immediate) }

    func signIn() async {
        guard !isSigningIn else { return }
        isSigningIn = true
        defer { isSigningIn = false }
        errorMessage = nil
        status = "Waiting for ChatGPT sign-in…"
        do {
            try await auth.signIn()
            _ = try await planClient.availableModels()
            status = "Connected to ChatGPT"
        } catch {
            errorMessage = error.localizedDescription
            status = "ChatGPT sign-in didn’t finish"
        }
    }

    func signOut() async {
        let revoked = await auth.signOut()
        status = revoked ? "Signed out of ChatGPT" : "Signed out on this Mac · remote revocation couldn’t be confirmed"
    }

    func loadModels() async -> [ChatGPTModel] {
        (try? await planClient.availableModels()) ?? []
    }

    func selectModel(_ slug: String) { planClient.setModel(slug) }

    func companionSnapshot() -> [String: Any] {
        [
            "connected": canUseGPT,
            "recording": isRecording,
            "starting": isStarting,
            "processing": isProcessing,
            "signingIn": isSigningIn,
            "transcript": rawTranscript,
            "output": outputText,
            "status": status,
            "error": errorMessage as Any? ?? NSNull()
        ]
    }

    func companionStartRecording(modeName: String?) {
        guard !isStarting && !isRecording && !isProcessing else { return }
        if let modeName, let selected = RantMode(rawValue: modeName) { mode = selected }
        startedFromShortcut = false
        targetBundleID = nil
        isStarting = true
        Task { await beginRecording() }
    }

    func companionStopRecording() {
        guard isRecording else { return }
        Task { await finishRecording() }
    }

    func companionSignIn() {
        Task { await signIn() }
    }

    func companionRewrite(_ text: String, modeName: String?, styleName: String?) async throws -> String {
        guard canUseGPT else { throw PlanAPIError.responseFailed }
        let selectedMode = modeName.flatMap(RantMode.init(rawValue:)) ?? .dictate
        let selectedStyle = styleName.flatMap(RewriteStyle.init(rawValue:)) ?? .natural
        return try await planClient.rewrite(text, instructions: instructions(for: selectedMode, style: selectedStyle))
    }

    func requestAccessibility() { PasteBridge.requestAccessibilityPermission() }

    func clearHistory() {
        history = []
        UserDefaults.standard.removeObject(forKey: historyKey)
    }

    func useHistory(_ entry: DictationEntry) {
        mode = .dictate
        rawTranscript = entry.text
        outputText = entry.text
        status = "History transcript loaded"
    }

    func updateAutoPaste(_ value: Bool) {
        autoPaste = value
        UserDefaults.standard.set(value, forKey: "rant.auto-paste")
    }

    private func saveHistory(_ text: String) {
        guard !text.isEmpty else { return }
        history.insert(DictationEntry(id: UUID(), text: text, date: Date()), at: 0)
        history = Array(history.prefix(30))
        if let data = try? JSONEncoder().encode(history) { UserDefaults.standard.set(data, forKey: historyKey) }
    }

    private func instructions(for mode: RantMode, style: RewriteStyle) -> String {
        switch mode {
        case .dictate:
            let styleGuide: String
            switch style {
            case .natural: styleGuide = "Keep the speaker's natural voice. Remove filler, false starts, and accidental repetition. Fix grammar and punctuation without changing meaning or adding details. Return only the cleaned text."
            case .concise: styleGuide = "Make the text concise while preserving all important facts, requests, and intent. Remove filler and repetition. Do not invent details. Return only the revised text."
            case .professional: styleGuide = "Rewrite this as clear, polished professional writing. Preserve the speaker's meaning and all concrete details. Remove filler. Do not add facts. Return only the revised text."
            case .email: styleGuide = "Turn this dictation into a polished, natural email. Add a suitable greeting and sign-off only when the transcript makes the context clear. Preserve all meaning and details; do not invent names, facts, or commitments. Return only the email."
            }
            return "You clean up dictated speech for insertion into other apps. \(styleGuide)"
        case .prd:
            return "You are an expert product manager. Convert the user's feature idea into a practical, implementation-ready PRD. Include overview, measurable goals, non-goals, 3-5 user stories with Given/When/Then acceptance criteria, technical specification, UI/UX, constraints, implementation phases, verification, edge cases, and open questions. Make reasonable assumptions explicit. If critical information is missing, ask up to three concise questions. Return only the PRD or questions."
        case .fix:
            return "You are a senior software engineer. Turn the user's bug report into a structured fix brief with problem definition, context, reproduction steps, expected versus actual behavior, likely cause, proposed solution, implementation steps, verification, and edge cases. Do not claim certainty beyond the report. Ask up to three concise questions if key reproduction details are missing. Return only the fix brief or questions."
        case .structure:
            return "Organize the user's spoken thoughts without adding information. Use a title, summary, key points, details, and action items if present. Preserve intent and emphasis. Return only the structured text."
        }
    }
}
