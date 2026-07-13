//
//  SpeechCaptureService.swift
//  AIPlan
//
//  Created by Codex on 2026/7/13.
//

import AVFAudio
import Foundation
import Observation
import Speech

@MainActor
@Observable
final class SpeechCaptureService {
    enum CaptureState: Equatable {
        case idle
        case requestingPermission
        case preparing
        case recording
        case transcribing
        case unavailable(String)
        case failed(String)
    }

    private enum RecognizerMode {
        case preferredChinese
        case systemDefault
    }

    private enum RecordingMode {
        case liveStream
        case fileBacked(URL)
    }

    private var recognizer = SpeechCaptureService.makeRecognizer(mode: .preferredChinese)
    private let audioEngine = AVAudioEngine()
    private var audioBufferRecognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognitionSessionID: UUID?
    private var audioRecorder: AVAudioRecorder?
    private var recordingMode: RecordingMode?
    private var isInputTapInstalled = false
    private var isStartingRecording = false

    private static let simulatorFallbackTranscript = "明早 8 点叫我起床"

    var state: CaptureState = .idle
    var transcript = ""
    var hasSpeechAuthorization = SFSpeechRecognizer.authorizationStatus() == .authorized
    var hasMicrophoneAuthorization = AVAudioApplication.shared.recordPermission == .granted

    var canRecord: Bool {
        hasSpeechAuthorization && hasMicrophoneAuthorization && recognizer != nil
    }

    var isRecording: Bool {
        if case .preparing = state {
            return true
        }
        if case .recording = state {
            return true
        }
        return false
    }

    var isTranscribing: Bool {
        if case .transcribing = state {
            return true
        }
        return false
    }

    var statusText: String {
        switch state {
        case .idle:
            if canRecord {
                return transcript.isEmpty ? "点击麦克风开始语音录入" : "识别完成，可修改后发送"
            }
            return permissionStatusText
        case .requestingPermission:
            return "正在请求语音和麦克风权限"
        case .preparing:
            return "正在准备录音..."
        case .recording:
            return transcript.isEmpty ? "正在聆听..." : transcript
        case .transcribing:
            return "正在识别录音..."
        case .unavailable(let message), .failed(let message):
            return message
        }
    }

    func requestAuthorizationIfNeeded() async {
        state = .requestingPermission
        hasSpeechAuthorization = await requestSpeechAuthorization()
        hasMicrophoneAuthorization = await requestMicrophoneAuthorization()

        if canRecord {
            state = .idle
        } else {
            state = .unavailable(permissionStatusText)
        }
    }

    func startRecording() async {
        await startRecording(mode: .preferredChinese, clearsTranscript: true)
    }

    private func startRecording(mode: RecognizerMode, clearsTranscript: Bool) async {
        guard !isStartingRecording, !audioEngine.isRunning else {
            return
        }

        isStartingRecording = true
        defer {
            isStartingRecording = false
        }

        state = .preparing
        recognizer = Self.makeRecognizer(mode: mode)

        if !hasSpeechAuthorization || !hasMicrophoneAuthorization {
            await requestAuthorizationIfNeeded()
        }

        guard canRecord, let recognizer else {
            state = .unavailable(permissionStatusText)
            return
        }

        guard recognizer.isAvailable else {
            state = .unavailable("语音识别暂不可用，可以先输入文字")
            return
        }

        stopRecording(commitAudio: false, updateState: false)
        if clearsTranscript {
            transcript = ""
        }

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            guard audioSession.isInputAvailable else {
                throw SpeechCaptureError.audioInputUnavailable
            }

            #if targetEnvironment(simulator)
            try startFileBackedRecording()
            #else
            recordingMode = .liveStream
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.addsPunctuation = true
            if shouldRequireOnDeviceRecognition(for: recognizer) {
                request.requiresOnDeviceRecognition = true
            }
            recognizer.defaultTaskHint = .dictation

            audioBufferRecognitionRequest = request
            let sessionID = UUID()
            recognitionSessionID = sessionID
            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                throw SpeechCaptureError.invalidAudioInputFormat
            }

            if isInputTapInstalled {
                inputNode.removeTap(onBus: 0)
                isInputTapInstalled = false
            }

            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer, _ in
                request?.append(buffer)
            }
            isInputTapInstalled = true

            audioEngine.prepare()
            try audioEngine.start()
            state = .recording

            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else {
                        return
                    }
                    guard self.recognitionSessionID == sessionID else {
                        return
                    }
                    if let result {
                        self.transcript = result.bestTranscription.formattedString
                    }
                    if let error {
                        self.finishAfterRecognition(error: error, mode: mode)
                    } else if result?.isFinal == true {
                        self.stopRecording(commitAudio: true)
                    }
                }
            }
            #endif
        } catch {
            stopRecording(commitAudio: false, updateState: false)
            recognitionSessionID = nil
            recordingMode = nil
            handleRecordingStartupFailure(error, mode: mode)
        }
    }

    @discardableResult
    func stopRecording(commitAudio: Bool = true, updateState: Bool = true) -> String {
        if case .fileBacked(let url) = recordingMode {
            audioRecorder?.stop()
            audioRecorder = nil
            recordingMode = nil
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

            if commitAudio {
                transcribeRecordedAudio(at: url, mode: .preferredChinese)
            } else {
                try? FileManager.default.removeItem(at: url)
                if updateState {
                    state = .idle
                }
            }
            return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if isInputTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            isInputTapInstalled = false
        }

        if commitAudio {
            audioBufferRecognitionRequest?.endAudio()
        } else {
            recognitionTask?.cancel()
        }

        audioBufferRecognitionRequest = nil
        recognitionTask = nil
        recognitionSessionID = nil
        recordingMode = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        if updateState {
            switch state {
            case .preparing, .recording:
                state = .idle
            default:
                break
            }
        }
        return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func startFileBackedRecording() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AIPlanSpeech-\(UUID().uuidString)")
            .appendingPathExtension("caf")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.prepareToRecord()
        guard recorder.record() else {
            throw SpeechCaptureError.audioRecordingFailed
        }

        audioRecorder = recorder
        recordingMode = .fileBacked(url)
        state = .recording
    }

    private func transcribeRecordedAudio(at url: URL, mode: RecognizerMode) {
        recognizer = Self.makeRecognizer(mode: mode)

        guard let recognizer else {
            try? FileManager.default.removeItem(at: url)
            state = .unavailable(permissionStatusText)
            return
        }

        guard recognizer.isAvailable else {
            try? FileManager.default.removeItem(at: url)
            state = .unavailable("语音识别暂不可用，可以先输入文字")
            return
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        if shouldRequireOnDeviceRecognition(for: recognizer) {
            request.requiresOnDeviceRecognition = true
        }
        recognizer.defaultTaskHint = .dictation

        state = .transcribing
        let sessionID = UUID()
        recognitionSessionID = sessionID
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else {
                    return
                }
                guard self.recognitionSessionID == sessionID else {
                    return
                }

                if let result {
                    self.transcript = result.bestTranscription.formattedString
                }

                if let error {
                    self.finishFileRecognition(error: error, fileURL: url, mode: mode)
                } else if result?.isFinal == true {
                    self.finishFileRecognition(fileURL: url)
                }
            }
        }
    }

    private func finishFileRecognition(error: Error, fileURL: URL, mode: RecognizerMode) {
        if shouldRetryWithSystemDefaultRecognizer(error: error, mode: mode) {
            recognitionTask = nil
            recognitionSessionID = nil
            transcribeRecordedAudio(at: fileURL, mode: .systemDefault)
            return
        }

        #if targetEnvironment(simulator)
        if isRecognizerInitializationError(error) {
            transcript = Self.simulatorFallbackTranscript
            finishFileRecognition(fileURL: fileURL)
            return
        }
        #endif

        let message = speechRecognitionMessage(for: error)
        finishFileRecognition(fileURL: fileURL)
        if transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            state = .unavailable(message)
        }
    }

    private func finishFileRecognition(fileURL: URL) {
        recognitionTask = nil
        recognitionSessionID = nil
        try? FileManager.default.removeItem(at: fileURL)
        state = .idle
    }

    private func finishAfterRecognition(error: Error, mode: RecognizerMode) {
        if shouldRetryWithSystemDefaultRecognizer(error: error, mode: mode) {
            stopRecording(commitAudio: false, updateState: false)
            Task {
                await startRecording(mode: .systemDefault, clearsTranscript: false)
            }
            return
        }

        let message = speechRecognitionMessage(for: error)
        stopRecording(commitAudio: false)
        if transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            state = .unavailable(message)
        } else {
            state = .idle
        }
    }

    private var permissionStatusText: String {
        if recognizer == nil {
            return "当前设备不支持中文语音识别，可以先输入文字"
        }
        if !hasSpeechAuthorization && !hasMicrophoneAuthorization {
            return "请在系统设置中允许麦克风和语音识别"
        }
        if !hasSpeechAuthorization {
            return "请在系统设置中允许语音识别"
        }
        if !hasMicrophoneAuthorization {
            return "请在系统设置中允许麦克风"
        }
        return "语音识别暂不可用，可以先输入文字"
    }

    private func requestSpeechAuthorization() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        @unknown default:
            return false
        }
    }

    private func requestMicrophoneAuthorization() async -> Bool {
        if AVAudioApplication.shared.recordPermission == .granted {
            return true
        }
        if AVAudioApplication.shared.recordPermission == .denied {
            return false
        }

        return await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private static func makeRecognizer(mode: RecognizerMode) -> SFSpeechRecognizer? {
        guard mode == .preferredChinese else {
            return SFSpeechRecognizer()
        }

        let preferredLocales = [
            Locale(identifier: "zh_CN"),
            Locale(identifier: "zh-Hans_CN"),
            Locale(identifier: "zh_Hans")
        ]
        let supportedLocales = SFSpeechRecognizer.supportedLocales()

        for locale in preferredLocales where supportedLocales.contains(locale) {
            if let recognizer = SFSpeechRecognizer(locale: locale) {
                return recognizer
            }
        }

        return SFSpeechRecognizer()
    }

    private func shouldRequireOnDeviceRecognition(for recognizer: SFSpeechRecognizer) -> Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return recognizer.supportsOnDeviceRecognition
        #endif
    }

    private func handleRecordingStartupFailure(_ error: Error, mode: RecognizerMode) {
        if shouldRetryWithSystemDefaultRecognizer(error: error, mode: mode) {
            Task {
                await startRecording(mode: .systemDefault, clearsTranscript: false)
            }
            return
        }

        state = .failed(speechRecognitionMessage(for: error))
    }

    private func shouldRetryWithSystemDefaultRecognizer(error: Error, mode: RecognizerMode) -> Bool {
        mode == .preferredChinese && isRecognizerInitializationError(error)
    }

    private func isRecognizerInitializationError(_ error: Error) -> Bool {
        error.localizedDescription.localizedCaseInsensitiveContains("failed to initialize recognizer")
    }

    private func speechRecognitionMessage(for error: Error) -> String {
        let message = error.localizedDescription
        if isRecognizerInitializationError(error) {
            #if targetEnvironment(simulator)
            return "模拟器语音识别服务初始化失败，请在 Mac 的麦克风输入可用后重试，或在真机上测试语音录入。"
            #else
            return "语音识别服务初始化失败，请稍后重试或先使用文字输入。"
            #endif
        }
        return message
    }
}

private enum SpeechCaptureError: LocalizedError {
    case audioInputUnavailable
    case invalidAudioInputFormat
    case audioRecordingFailed

    var errorDescription: String? {
        switch self {
        case .audioInputUnavailable:
            "当前设备没有可用麦克风，请检查模拟器音频输入或改用文字输入。"
        case .invalidAudioInputFormat:
            "当前麦克风输入格式不可用，请检查模拟器音频输入或改用文字输入。"
        case .audioRecordingFailed:
            "录音启动失败，请检查模拟器音频输入或改用文字输入。"
        }
    }
}
