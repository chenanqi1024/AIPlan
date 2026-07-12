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
    @State private var isPressingMic = false
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
            ZStack {
                Circle()
                    .stroke(PlanTheme.calendarBlue.opacity(isPressingMic ? 0.46 : 0.20), lineWidth: 2)
                    .frame(width: 188, height: 188)
                    .scaleEffect(isPressingMic ? 1.06 : 1)

                Circle()
                    .fill(PlanTheme.calendarBlue.opacity(isPressingMic ? 0.20 : 0.10))
                    .frame(width: 148, height: 148)

                Circle()
                    .fill(PlanTheme.calendarBlue)
                    .frame(width: 108, height: 108)
                    .shadow(color: PlanTheme.calendarBlue.opacity(0.35), radius: isPressingMic ? 28 : 16)

                Image(systemName: "mic.fill")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 204, height: 204)
            .contentShape(Circle())
            .onLongPressGesture(
                minimumDuration: 0.25,
                maximumDistance: 80,
                pressing: { pressing in
                    handleMicPress(pressing)
                },
                perform: {}
            )
            .accessibilityLabel("按住说出安排")
            .accessibilityHint("松开后把识别结果填入输入框")

            VStack(spacing: 7) {
                Text("按住说出安排")
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
        .planCard(stroke: PlanTheme.calendarBlue.opacity(0.34), cornerRadius: 28)
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
            PlanTheme.calendarBlue
        default:
            PlanTheme.textSecondary
        }
    }

    private func handleMicPress(_ pressing: Bool) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
            isPressingMic = pressing
        }

        if pressing {
            isTextFocused = false
            speechCaptureService.startRecording()
            return
        }

        let transcript = speechCaptureService.stopRecording()
        guard !transcript.isEmpty else {
            return
        }
        draftText = transcript
        isTextFocused = true
    }
}
