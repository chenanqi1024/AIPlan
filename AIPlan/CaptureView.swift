//
//  CaptureView.swift
//  AIPlan
//
//  Created by Codex on 2026/7/13.
//

import SwiftUI

struct CaptureView: View {
    let speechCaptureService: SpeechCaptureService
    var onSubmit: (String) -> Void

    @State private var draftText = ""
    @State private var isMicPulsing = false
    @State private var lastAppliedTranscript = ""
    @FocusState private var isTextFocused: Bool

    private var canSubmit: Bool {
        !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack {
            PlanTheme.surfaceApp.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: PlanTheme.sectionSpacing) {
                    header
                    voiceCard
                    Spacer(minLength: 18)
                }
                .padding(.horizontal, PlanTheme.pagePadding)
                .padding(.top, 18)
                .padding(.bottom, 96)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom) {
            composer
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(PlanDateFormatter.friendlyDate())
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(PlanTheme.textSecondary)

            Text("今天想安排什么？")
                .font(.system(size: 31, weight: .heavy))
                .foregroundStyle(PlanTheme.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var voiceCard: some View {
        VStack(spacing: 18) {
            Button {
                toggleMicRecording()
            } label: {
                micButtonArtwork
            }
            .buttonStyle(.plain)
            .disabled(speechCaptureService.isTranscribing)
            .accessibilityLabel(speechCaptureService.isRecording ? "结束语音录入" : "开始语音录入")
            .accessibilityHint("再次点击后把识别结果填入输入框")

            VStack(spacing: 7) {
                Text(speechCaptureService.isRecording ? "正在语音输入" : "点击说出安排")
                    .font(.system(size: 21, weight: .heavy))
                    .foregroundStyle(PlanTheme.textPrimary)

                Text(speechCaptureService.statusText)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(statusTint)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 360)
        .padding(.horizontal, 22)
        .padding(.vertical, 26)
        .planCard(stroke: micAccent.opacity(speechCaptureService.isRecording ? 0.58 : 0.34), cornerRadius: 28)
        .onChange(of: speechCaptureService.isRecording) { _, isRecording in
            if isRecording {
                isMicPulsing = false
                withAnimation(.easeInOut(duration: 0.82).repeatForever(autoreverses: true)) {
                    isMicPulsing = true
                }
            } else {
                withAnimation(.easeOut(duration: 0.18)) {
                    isMicPulsing = false
                }
            }
        }
        .onChange(of: speechCaptureService.transcript) { _, transcript in
            applyTranscriptIfReady(transcript)
        }
        .onChange(of: speechCaptureService.state) { _, _ in
            applyTranscriptIfReady(speechCaptureService.transcript)
        }
    }

    private var micButtonArtwork: some View {
        ZStack {
            if speechCaptureService.isRecording {
                Circle()
                    .stroke(micAccent.opacity(0.28), lineWidth: 2)
                    .frame(width: 202, height: 202)
                    .scaleEffect(isMicPulsing ? 1.12 : 0.96)

                Circle()
                    .stroke(micAccent.opacity(0.38), lineWidth: 2)
                    .frame(width: 176, height: 176)
                    .scaleEffect(isMicPulsing ? 1.08 : 0.98)
            }

            Circle()
                .stroke(micAccent.opacity(speechCaptureService.isRecording ? 0.68 : 0.20), lineWidth: 2)
                .frame(width: 188, height: 188)
                .scaleEffect(speechCaptureService.isRecording ? 1.04 : 1)

            Circle()
                .fill(micAccent.opacity(speechCaptureService.isRecording ? 0.22 : 0.10))
                .frame(width: 148, height: 148)

            Circle()
                .fill(micAccent)
                .frame(width: 108, height: 108)
                .shadow(color: micAccent.opacity(0.40), radius: speechCaptureService.isRecording ? 30 : 16)
                .scaleEffect(speechCaptureService.isRecording && isMicPulsing ? 1.07 : 1)

            Image(systemName: speechCaptureService.isRecording ? "stop.fill" : "mic.fill")
                .font(.system(size: speechCaptureService.isRecording ? 34 : 38, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: 204, height: 204)
        .contentShape(Circle())
    }

    private var composer: some View {
        HStack(spacing: 12) {
            TextField("明早 8 点叫我起床", text: $draftText, axis: .vertical)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(PlanTheme.textPrimary)
                .lineLimit(1...3)
                .textInputAutocapitalization(.never)
                .submitLabel(.send)
                .focused($isTextFocused)
                .onSubmit(submit)
                .padding(.horizontal, 14)
                .frame(minHeight: 54)
                .background(
                    PlanTheme.surfaceCard,
                    in: RoundedRectangle(cornerRadius: PlanTheme.cardRadius, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: PlanTheme.cardRadius, style: .continuous)
                        .stroke(PlanTheme.borderSubtle, lineWidth: 1)
                )

            Button(action: submit) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 54, height: 54)
                    .background(
                        canSubmit ? PlanTheme.calendarBlue : PlanTheme.surfaceCardStrong,
                        in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                    )
            }
            .disabled(!canSubmit)
            .accessibilityLabel("提交安排")
        }
        .padding(.horizontal, PlanTheme.pagePadding)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(PlanTheme.surfaceApp.opacity(0.95))
    }

    private func submit() {
        let text = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return
        }
        isTextFocused = false
        onSubmit(text)
    }

    private var statusTint: Color {
        switch speechCaptureService.state {
        case .failed, .unavailable:
            PlanTheme.alertRed
        case .recording:
            PlanTheme.alertRed
        case .transcribing:
            PlanTheme.calendarBlue
        default:
            PlanTheme.textSecondary
        }
    }

    private var micAccent: Color {
        speechCaptureService.isRecording ? PlanTheme.alertRed : PlanTheme.calendarBlue
    }

    private func toggleMicRecording() {
        guard !speechCaptureService.isTranscribing else {
            return
        }

        if speechCaptureService.isRecording {
            commitTranscriptFromRecording()
            return
        }

        Task {
            isTextFocused = false
            await speechCaptureService.startRecording()
        }
    }

    private func commitTranscriptFromRecording() {
        let transcript = speechCaptureService.stopRecording()
        guard !transcript.isEmpty else {
            return
        }
        draftText = transcript
        lastAppliedTranscript = transcript
        isTextFocused = true
    }

    private func applyTranscriptIfReady(_ transcript: String) {
        let cleanedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTranscript.isEmpty else {
            return
        }
        guard !speechCaptureService.isRecording, !speechCaptureService.isTranscribing else {
            return
        }
        guard cleanedTranscript != lastAppliedTranscript else {
            return
        }

        draftText = cleanedTranscript
        lastAppliedTranscript = cleanedTranscript
        isTextFocused = true
    }
}
