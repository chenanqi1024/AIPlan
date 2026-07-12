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
        case recording
        case unavailable(String)
        case failed(String)
    }

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh_CN"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    var state: CaptureState = .idle
    var transcript = ""
    var hasSpeechAuthorization = SFSpeechRecognizer.authorizationStatus() == .authorized
    var hasMicrophoneAuthorization = false

    var canRecord: Bool {
        hasSpeechAuthorization && hasMicrophoneAuthorization && recognizer?.isAvailable == true
    }

    var statusText: String {
        switch state {
        case .idle:
            if canRecord {
                return transcript.isEmpty ? "按住麦克风开始语音录入" : "识别完成，可修改后发送"
            }
            return "需要麦克风和语音识别权限"
        case .requestingPermission:
            return "正在请求语音权限"
        case .recording:
            return transcript.isEmpty ? "正在聆听..." : transcript
        case .unavailable(let message), .failed(let message):
            return message
        }
    }

    func requestAuthorizationIfNeeded() async {
        state = .requestingPermission
        async let speechGranted = requestSpeechAuthorization()
        async let microphoneGranted = requestMicrophoneAuthorization()

        hasSpeechAuthorization = await speechGranted
        hasMicrophoneAuthorization = await microphoneGranted

        if canRecord {
            state = .idle
        } else {
            state = .unavailable("请在系统设置中允许麦克风和语音识别")
        }
    }

    func startRecording() {
        guard canRecord else {
            state = .unavailable("请在系统设置中允许麦克风和语音识别")
            return
        }

        stopRecording(commitAudio: false)
        transcript = ""

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            if recognizer?.supportsOnDeviceRecognition == true {
                request.requiresOnDeviceRecognition = false
            }

            recognitionRequest = request
            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer, _ in
                request?.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()
            state = .recording

            recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else {
                        return
                    }
                    if let result {
                        self.transcript = result.bestTranscription.formattedString
                    }
                    if let error {
                        self.finishAfterRecognition(message: error.localizedDescription)
                    } else if result?.isFinal == true {
                        self.stopRecording(commitAudio: true)
                    }
                }
            }
        } catch {
            stopRecording(commitAudio: false)
            state = .failed(error.localizedDescription)
        }
    }

    @discardableResult
    func stopRecording(commitAudio: Bool = true) -> String {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)

        if commitAudio {
            recognitionRequest?.endAudio()
        } else {
            recognitionTask?.cancel()
        }

        recognitionRequest = nil
        recognitionTask = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        if case .recording = state {
            state = .idle
        }
        return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func finishAfterRecognition(message: String) {
        stopRecording(commitAudio: false)
        if transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            state = .failed(message)
        } else {
            state = .idle
        }
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
}
