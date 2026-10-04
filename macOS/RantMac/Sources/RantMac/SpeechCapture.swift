import AVFoundation
import Speech

@MainActor
final class SpeechCapture: ObservableObject {
    @Published private(set) var transcript = ""
    @Published private(set) var level = 0.0

    private let engine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale.current)
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var finalText = ""
    private var recognitionFinished = false
    private var recognitionCompletion: CheckedContinuation<Void, Never>?
    private var finishTimeout: Task<Void, Never>?

    func start() async throws {
        guard let recognizer, recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            throw SpeechError.onDeviceUnavailable
        }
        let microphoneAllowed = await AVCaptureDevice.requestAccess(for: .audio)
        guard microphoneAllowed else { throw SpeechError.microphonePermission }
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speechStatus == .authorized else { throw SpeechError.speechPermission }

        transcript = ""
        finalText = ""
        recognitionFinished = false
        let recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.requiresOnDeviceRecognition = true
        request = recognitionRequest

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            recognitionRequest.append(buffer)
            let channel = buffer.floatChannelData?.pointee
            let count = Int(buffer.frameLength)
            let meanSquare = channel.map { samples in
                (0..<count).reduce(Float(0)) { $0 + samples[$1] * samples[$1] } / Float(max(count, 1))
            } ?? 0
            let amplitude = min(1, Double(sqrt(meanSquare)) * 5)
            Task { @MainActor in self?.level = amplitude }
        }

        task = recognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            Task { @MainActor in
                guard let self else { return }
                if let text {
                    self.transcript = text
                    self.finalText = text
                }
                if isFinal || error != nil {
                    self.level = 0
                    self.recognitionFinished = true
                    self.resumeRecognitionWaiter()
                }
            }
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            engine.stop()
            task?.cancel()
            task = nil
            request = nil
            level = 0
            throw error
        }
    }

    func stop() async -> String {
        if engine.isRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        request?.endAudio()
        task?.finish()
        if !recognitionFinished {
            await withCheckedContinuation { continuation in
                if recognitionFinished {
                    continuation.resume()
                    return
                }
                recognitionCompletion = continuation
                finishTimeout = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(2))
                    guard !Task.isCancelled else { return }
                    self?.recognitionFinished = true
                    self?.resumeRecognitionWaiter()
                }
            }
        }
        let result = finalText.isEmpty ? transcript : finalText
        request = nil
        task = nil
        level = 0
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func cancel() {
        if engine.isRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        task?.cancel()
        finishTimeout?.cancel()
        finishTimeout = nil
        resumeRecognitionWaiter()
        task = nil
        request = nil
        level = 0
    }

    private func resumeRecognitionWaiter() {
        finishTimeout?.cancel()
        finishTimeout = nil
        let continuation = recognitionCompletion
        recognitionCompletion = nil
        continuation?.resume()
    }
}

enum SpeechError: LocalizedError {
    case onDeviceUnavailable
    case microphonePermission
    case speechPermission

    var errorDescription: String? {
        switch self {
        case .onDeviceUnavailable: "On-device speech recognition isn’t available for the current language on this Mac. Audio wasn’t sent to a speech service."
        case .microphonePermission: "Rant needs microphone access. Allow it in System Settings → Privacy & Security → Microphone."
        case .speechPermission: "Rant needs speech recognition access. Allow it in System Settings → Privacy & Security → Speech Recognition."
        }
    }
}
