import AppKit
import SwiftUI

private enum WorkspaceSection: String, CaseIterable, Identifiable {
    case dictate, prd, fix, structure, history
    var id: String { rawValue }
    var title: String {
        switch self {
        case .dictate: "Dictate"
        case .prd: "Build a PRD"
        case .fix: "Define a fix"
        case .structure: "Structure thoughts"
        case .history: "History"
        }
    }
    var symbol: String {
        switch self {
        case .dictate: "waveform"
        case .prd: "doc.text"
        case .fix: "ladybug"
        case .structure: "list.bullet.indent"
        case .history: "clock.arrow.circlepath"
        }
    }
    var mode: RantMode? {
        switch self {
        case .dictate: .dictate
        case .prd: .prd
        case .fix: .fix
        case .structure: .structure
        case .history: nil
        }
    }
}

private enum Palette {
    static let paper = Color(red: 0.96, green: 0.95, blue: 0.92)
    static let surface = Color(red: 0.99, green: 0.985, blue: 0.97)
    static let inset = Color(red: 0.92, green: 0.91, blue: 0.88)
    static let ink = Color(red: 0.15, green: 0.16, blue: 0.17)
    static let secondary = Color(red: 0.38, green: 0.39, blue: 0.39)
    static let quiet = Color(red: 0.56, green: 0.55, blue: 0.52)
    static let line = Color(red: 0.84, green: 0.83, blue: 0.79)
    static let signal = Color(red: 0.79, green: 0.21, blue: 0.17)
    static let signalWash = Color(red: 0.98, green: 0.89, blue: 0.85)
    static let done = Color(red: 0.24, green: 0.42, blue: 0.33)
}

struct ContentView: View {
    @EnvironmentObject private var model: RantModel
    @State private var section: WorkspaceSection = .dictate
    @State private var showSettings = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Palette.line).frame(width: 1)
            VStack(spacing: 0) {
                titlebar
                Rectangle().fill(Palette.line).frame(height: 1)
                if section == .history {
                    HistoryView { entry in
                        model.useHistory(entry)
                        section = .dictate
                    }
                } else {
                    workspace
                }
            }
            .background(Palette.paper)
        }
        .background(Palette.paper)
        .preferredColorScheme(.light)
        .sheet(isPresented: $showSettings) { SettingsView().environmentObject(model) }
        .onChange(of: section) { _, newValue in
            if let mode = newValue.mode { model.mode = mode }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9).fill(Palette.ink).frame(width: 32, height: 32)
                    Image(systemName: "waveform").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.paper)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text("Rant").font(.system(size: 17, weight: .semibold, design: .rounded)).foregroundStyle(Palette.ink)
                    Text("VOICE STUDIO").font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(1).foregroundStyle(Palette.quiet)
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("WORKSPACE").font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1).foregroundStyle(Palette.quiet).padding(.horizontal, 10).padding(.bottom, 2)
                ForEach(WorkspaceSection.allCases) { item in
                    Button { section = item } label: {
                        HStack(spacing: 10) {
                            Image(systemName: item.symbol).font(.system(size: 13, weight: .medium)).frame(width: 17)
                            Text(item.title).font(.system(size: 13, weight: section == item ? .medium : .regular))
                            Spacer(minLength: 0)
                            if item == .dictate {
                                Text(model.shortcutLabel.uppercased()).font(.system(size: 8, weight: .medium, design: .monospaced)).foregroundStyle(Palette.quiet)
                            }
                        }
                        .foregroundStyle(section == item ? Palette.ink : Palette.secondary)
                        .padding(.horizontal, 10).frame(height: 34)
                        .background(section == item ? Palette.inset.opacity(0.72) : .clear, in: RoundedRectangle(cornerRadius: 7))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Circle().fill(model.canUseGPT ? Palette.done : Palette.quiet).frame(width: 7, height: 7)
                    Text(model.auth.signedInEmail ?? "ChatGPT not connected")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.secondary).lineLimit(1)
                }
                Button { showSettings = true } label: {
                    Label("Settings", systemImage: "slider.horizontal.3").font(.system(size: 12)).foregroundStyle(Palette.secondary)
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
        }
        .padding(.horizontal, 13).padding(.top, 22).padding(.bottom, 20)
        .frame(width: 214)
        .background(Palette.paper)
    }

    private var titlebar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(section.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.ink)
                Text(section.mode?.hint ?? "Your recent voice notes")
                    .font(.system(size: 11)).foregroundStyle(Palette.quiet).lineLimit(1)
            }
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "gearshape").font(.system(size: 14)).foregroundStyle(Palette.secondary).frame(width: 30, height: 30)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.line, lineWidth: 0.7))
            }.buttonStyle(.plain).help("Settings")
        }
        .padding(.horizontal, 24).padding(.vertical, 14)
        .background(Palette.paper)
    }

    private var workspace: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(primaryHeading).font(.system(size: 31, weight: .regular, design: .serif)).tracking(-0.5).foregroundStyle(Palette.ink)
                        Text(model.mode.hint).font(.system(size: 13)).foregroundStyle(Palette.secondary)
                    }
                    Spacer()
                    if model.mode == .dictate { stylePicker }
                }
                .padding(.top, 15)

                recorderSurface
                transcriptSurface
                if let error = model.errorMessage {
                    Label(error, systemImage: "exclamationmark.circle.fill")
                        .font(.system(size: 12)).foregroundStyle(Palette.signal).padding(.horizontal, 4)
                }
                footer
            }
            .padding(.horizontal, 28).padding(.bottom, 30)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.paper)
    }

    private var primaryHeading: String {
        switch model.mode {
        case .dictate: "Say it as it comes."
        case .prd: "Start with the idea."
        case .fix: "Explain what’s broken."
        case .structure: "Think out loud."
        }
    }

    private var stylePicker: some View {
        Menu {
            ForEach(RewriteStyle.allCases) { style in
                Button(style.title) { model.style = style }
            }
        } label: {
            HStack(spacing: 7) {
                Text(model.style.title).font(.system(size: 11, weight: .medium))
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(Palette.secondary).padding(.horizontal, 10).frame(height: 28)
            .background(Palette.surface, in: Capsule())
            .overlay(Capsule().stroke(Palette.line, lineWidth: 0.7))
        }
        .menuStyle(.borderlessButton)
    }

    private var recorderSurface: some View {
        VStack(spacing: 15) {
            HStack {
                HStack(spacing: 7) {
                    Circle().fill(model.isRecording ? Palette.signal : Palette.done).frame(width: 7, height: 7)
                    Text(model.status.uppercased()).font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(0.8).foregroundStyle(Palette.secondary)
                }
                Spacer()
                if model.isRecording { Text("LIVE").font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(0.8).foregroundStyle(Palette.signal) }
            }

            WaveformView(speech: model.speech, active: model.isRecording)
                .frame(height: 78)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 6)
                .accessibilityLabel(model.isRecording ? "Microphone is recording" : "Microphone is idle")

            HStack(spacing: 12) {
                Button { model.toggleRecordingFromWindow() } label: {
                    HStack(spacing: 9) {
                        Image(systemName: model.isRecording ? "stop.fill" : "mic.fill").font(.system(size: 13, weight: .semibold))
                        Text(recordButtonTitle).font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(.white).padding(.horizontal, 18).frame(height: 42)
                    .background(model.isRecording ? Palette.signal : Palette.ink, in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain).disabled(model.isProcessing || model.isStarting)
                .keyboardShortcut(.space, modifiers: [.command, .option])

                Text(model.isRecording ? "Finish with \(model.shortcutLabel)" : "or press \(model.shortcutLabel) from anywhere")
                    .font(.system(size: 11)).foregroundStyle(Palette.quiet)
                Spacer()
                if !model.canUseGPT {
                    Button { showSettings = true } label: {
                        Label("Connect GPT", systemImage: "link").font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.ink)
                    }.buttonStyle(.plain)
                }
            }
        }
        .padding(17)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(Palette.line, lineWidth: 0.75))
    }

    private var recordButtonTitle: String {
        if model.isProcessing { return "Working…" }
        if model.isStarting { return "Starting…" }
        return model.isRecording ? "Finish recording" : "Start speaking"
    }

    private var transcriptSurface: some View {
        HStack(alignment: .top, spacing: 14) {
            transcriptColumn(title: "HEARD", text: $model.rawTranscript, placeholder: model.isRecording ? model.speech.transcript.ifEmpty("Your words will appear here as you speak…") : "Your words will appear here as you speak…", isLive: model.isRecording)
            Rectangle().fill(Palette.line).frame(width: 1)
            transcriptColumn(title: model.mode == .dictate ? "CLEANED" : "RESULT", text: $model.outputText, placeholder: "Your refined text will appear here…", isLive: false)
        }
        .padding(15)
        .frame(minHeight: 218)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(Palette.line, lineWidth: 0.75))
    }

    private func transcriptColumn(title: String, text: Binding<String>, placeholder: String, isLive: Bool) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Text(title).font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(0.9).foregroundStyle(Palette.quiet)
                if isLive { Circle().fill(Palette.signal).frame(width: 5, height: 5) }
            }
            ZStack(alignment: .topLeading) {
                if text.wrappedValue.isEmpty {
                    Text(placeholder).font(.system(size: 12)).foregroundStyle(Palette.quiet.opacity(0.8)).padding(.top, 8).padding(.leading, 5)
                }
                TextEditor(text: text)
                    .font(.system(size: 13)).foregroundStyle(Palette.ink)
                    .scrollContentBackground(.hidden)
                    .background(.clear)
                    .textEditorStyle(.plain)
            }
            .frame(minHeight: 148)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        HStack(spacing: 9) {
            Button { model.copyOutput() } label: { Label("Copy", systemImage: "doc.on.doc") }
            Button { model.insertOutput() } label: { Label("Insert", systemImage: "text.insert") }
            Button { model.speakOutput() } label: { Label("Read aloud", systemImage: "speaker.wave.2") }
            if model.isProcessing {
                ProgressView().controlSize(.small).padding(.leading, 4)
            } else if !model.rawTranscript.isEmpty && model.canUseGPT {
                Button {
                    Task { await model.rewriteCurrentText() }
                } label: { Label("Polish again", systemImage: "sparkle") }
            }
            Spacer()
            Toggle("Speak result", isOn: $model.speechEnabled).toggleStyle(.switch).controlSize(.mini)
                .font(.system(size: 11)).foregroundStyle(Palette.secondary)
        }
        .buttonStyle(QuietActionButtonStyle())
        .disabled(model.outputText.isEmpty && model.rawTranscript.isEmpty)
    }
}

private struct WaveformView: View {
    @ObservedObject var speech: SpeechCapture
    let active: Bool

    var body: some View {
        GeometryReader { proxy in
            HStack(alignment: .center, spacing: 4) {
                ForEach(0..<37, id: \.self) { index in
                    let curve = abs(sin(Double(index) * 0.58)) * 0.38 + abs(cos(Double(index) * 0.19)) * 0.24
                    let height = active ? max(5, min(64, 5 + (speech.level * 52 * curve * 2.1))) : 5 + curve * 12
                    Capsule().fill(active ? Palette.signal.opacity(0.42 + curve * 0.5) : Palette.line)
                        .frame(width: max(2, min(5, proxy.size.width / 115)), height: height)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct HistoryView: View {
    @EnvironmentObject private var model: RantModel
    let onSelect: (DictationEntry) -> Void
    @State private var confirmClearHistory = false

    init(onSelect: @escaping (DictationEntry) -> Void = { _ in }) {
        self.onSelect = onSelect
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recent voices").font(.system(size: 27, weight: .regular, design: .serif)).foregroundStyle(Palette.ink)
                Spacer()
                if !model.history.isEmpty {
                    Button("Clear history") { confirmClearHistory = true }
                        .font(.system(size: 11)).buttonStyle(.plain)
                }
            }
            .padding(.bottom, 18).padding(.top, 24)
            if model.history.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text("No saved dictations").font(.system(size: 15, weight: .medium)).foregroundStyle(Palette.ink)
                    Text("Your recent voice notes will live here on this Mac.").font(.system(size: 12)).foregroundStyle(Palette.quiet)
                }.padding(.top, 10)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(model.history) { entry in
                            Button { onSelect(entry) } label: {
                                HStack(alignment: .top, spacing: 13) {
                                    Image(systemName: "waveform").font(.system(size: 13)).foregroundStyle(Palette.quiet).frame(width: 24, height: 24)
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(entry.text).font(.system(size: 13)).foregroundStyle(Palette.ink).lineLimit(2).multilineTextAlignment(.leading)
                                        Text(entry.date.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.quiet)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "arrow.up.left").font(.system(size: 10)).foregroundStyle(Palette.quiet)
                                }
                                .padding(.vertical, 13)
                            }
                            .buttonStyle(.plain)
                            Rectangle().fill(Palette.line.opacity(0.7)).frame(height: 1)
                        }
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 28)
        .background(Palette.paper)
        .confirmationDialog("Clear recent voices?", isPresented: $confirmClearHistory, titleVisibility: .visible) {
            Button("Clear history", role: .destructive) { model.clearHistory() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes the saved dictation history from this Mac.")
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: RantModel
    @Environment(\.dismiss) private var dismiss
    @State private var models: [ChatGPTModel] = []
    @State private var selectedModel = ""
    @State private var confirmSignOut = false

    var body: some View {
        VStack(alignment: .leading, spacing: 19) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Settings").font(.system(size: 24, weight: .regular, design: .serif)).foregroundStyle(Palette.ink)
                    Text("Voice, insertion, and your ChatGPT connection").font(.system(size: 12)).foregroundStyle(Palette.quiet)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            Rectangle().fill(Palette.line).frame(height: 1)

            VStack(alignment: .leading, spacing: 10) {
                Text("CHATGPT PLAN").font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1).foregroundStyle(Palette.quiet)
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.auth.signedInEmail ?? "Connect with ChatGPT").font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.ink)
                        Text(model.canUseGPT ? "GPT text cleanup uses your eligible ChatGPT plan." : "Your speech stays on this Mac until you choose to send text for cleanup.")
                            .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                    }
                    Spacer()
                    if model.canUseGPT {
                        Button("Sign out") { confirmSignOut = true }.buttonStyle(.plain)
                    } else {
                        Button { Task { await model.signIn() } } label: {
                            HStack(spacing: 6) { Image(systemName: "person.crop.circle"); Text("Continue with ChatGPT") }
                                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white).padding(.horizontal, 12).frame(height: 32)
                                .background(Palette.ink, in: RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain).disabled(model.isSigningIn)
                    }
                }
                if model.canUseGPT {
                    Picker("Model", selection: $selectedModel) {
                        ForEach(models) { Text($0.displayName).tag($0.slug) }
                    }
                    .onChange(of: selectedModel) { _, newValue in model.selectModel(newValue) }
                    .task {
                        models = await model.loadModels()
                        if selectedModel.isEmpty { selectedModel = models.first?.slug ?? "" }
                    }
                }
            }
            .padding(15).background(Palette.surface, in: RoundedRectangle(cornerRadius: 11)).overlay(RoundedRectangle(cornerRadius: 11).stroke(Palette.line, lineWidth: 0.75))

            VStack(alignment: .leading, spacing: 12) {
                Text("DICTATION").font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1).foregroundStyle(Palette.quiet)
                Toggle(isOn: Binding(get: { model.autoPaste }, set: { model.updateAutoPaste($0) })) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Insert text automatically after the global shortcut").font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.ink)
                        Text("\(model.shortcutLabel) starts and finishes a dictation anywhere on your Mac.").font(.system(size: 11)).foregroundStyle(Palette.quiet)
                    }
                }.toggleStyle(.switch).controlSize(.small)
                HStack {
                    Label("Type into the active app", systemImage: "cursorarrow.insert")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.ink)
                    Spacer()
                    Button("Allow Accessibility") { model.requestAccessibility() }.font(.system(size: 11))
                }
                Text("macOS asks for Accessibility permission so Rant can press Paste in the app you were using. Without it, Rant still copies the finished text.")
                    .font(.system(size: 10)).foregroundStyle(Palette.quiet)
            }
            .padding(15).background(Palette.surface, in: RoundedRectangle(cornerRadius: 11)).overlay(RoundedRectangle(cornerRadius: 11).stroke(Palette.line, lineWidth: 0.75))

            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.circle.fill").font(.system(size: 11)).foregroundStyle(Palette.signal)
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(width: 560, height: 475)
        .background(Palette.paper)
        .task {
            models = await model.loadModels()
            if selectedModel.isEmpty { selectedModel = models.first?.slug ?? "" }
        }
        .confirmationDialog("Sign out of ChatGPT?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { Task { await model.signOut() } }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Rant will stop using your ChatGPT plan until you sign in again.")
        }
    }
}

private struct QuietActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Palette.secondary)
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Palette.line, lineWidth: 0.7))
            .opacity(configuration.isPressed ? 0.65 : 1)
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
