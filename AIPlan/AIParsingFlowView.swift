//
//  AIParsingFlowView.swift
//  AIPlan
//
//  Created by Codex on 2026/7/13.
//

import SwiftData
import SwiftUI

struct AIParsingFlowView: View {
    let input: String
    let systemSyncService: ScheduleSystemSyncService
    var onCancel: () -> Void
    var onSaved: () -> Void
    var client: ScheduleAssistantClient = .live()

    @Environment(\.modelContext) private var modelContext
    @Query private var events: [ScheduleEvent]
    @State private var state: ParsingState = .loading
    @State private var saveError: String?
    @State private var isSaving = false

    var body: some View {
        ZStack {
            PlanTheme.surfaceApp.ignoresSafeArea()

            switch state {
            case .loading:
                ParsingLoadingView(input: input, onCancel: onCancel)
            case .confirmation(let response, let draft):
                ConfirmEventView(
                    response: response,
                    draft: draft,
                    isSaving: isSaving,
                    onCancel: onCancel,
                    onSave: save
                )
            case .result(let result):
                AssistantResultView(result: result, onCancel: onCancel)
            case .failed(let message):
                ParsingErrorView(input: input, message: message, onCancel: onCancel) {
                    Task {
                        await load()
                    }
                }
            }
        }
        .task(id: input) {
            await load()
        }
        .toolbar(.hidden, for: .navigationBar)
        .alert("保存失败", isPresented: Binding(
            get: { saveError != nil },
            set: { isPresented in
                if !isPresented {
                    saveError = nil
                }
            }
        )) {
            Button("好") {
                saveError = nil
            }
        } message: {
            Text(saveError ?? "")
        }
    }

    private func save(draft: DraftEvent, reminderPolicy: ReminderPolicy) {
        guard !isSaving else {
            return
        }

        Task {
            await saveSystemAndLocalRecords(draft: draft, reminderPolicy: reminderPolicy)
        }
    }

    private func saveSystemAndLocalRecords(draft: DraftEvent, reminderPolicy: ReminderPolicy) async {
        isSaving = true
        defer {
            isSaving = false
        }

        let event = ScheduleEvent(draft: draft, reminderPolicy: reminderPolicy)

        do {
            try await systemSyncService.createSystemRecords(for: event)
            modelContext.insert(event)
            try modelContext.save()
            onSaved()
        } catch {
            try? await systemSyncService.deleteSystemRecords(for: event)
            saveError = error.localizedDescription
        }
    }

    private func load() async {
        state = .loading
        let contextEvents = events
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(200)
            .map { $0.queryContextEvent() }

        do {
            let assistantResponse = try await client.resolve(input, Array(contextEvents))
            if let intent = assistantResponse.intent, intent.intent == .create, let draft = intent.draft {
                state = .confirmation(intent, draft)
            } else {
                state = .result(AssistantDisplayResult(assistantResponse: assistantResponse))
            }
        } catch is CancellationError {
            return
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

private enum ParsingState {
    case loading
    case confirmation(IntentResponse, DraftEvent)
    case result(AssistantDisplayResult)
    case failed(String)
}

struct AssistantDisplayResult {
    var title: String
    var message: String
    var footnote: String?
    var suggestions: [String]
    var accent: Color

    init(assistantResponse: AssistantResponse) {
        if let query = assistantResponse.query {
            title = query.title
            message = query.answer ?? query.question ?? query.message ?? "暂时无法回答这个问题。"
            suggestions = query.suggestions
            footnote = assistantResponse.routeReason
            accent = query.status == .answer ? PlanTheme.calendarBlue : PlanTheme.alarmOrange
            return
        }

        if let intent = assistantResponse.intent {
            switch intent.intent {
            case .clarify:
                title = "需要补充信息"
                message = intent.question ?? intent.message ?? "请补充更明确的日程信息。"
                accent = PlanTheme.alarmOrange
            case .cancel:
                title = "暂未执行取消"
                message = intent.message ?? intent.reason ?? "后端识别到取消意图，但本轮尚未接入删除日程流程。"
                accent = PlanTheme.alertRed
            case .unsupported:
                title = "暂不支持"
                message = intent.message ?? intent.reason ?? "这个请求暂时不支持。"
                accent = PlanTheme.alertRed
            case .create:
                title = "未生成可确认日程"
                message = intent.message ?? intent.reason ?? "后端未返回可确认的日程草稿。"
                accent = PlanTheme.alertRed
            }
            suggestions = intent.ambiguities
            footnote = assistantResponse.routeReason
            return
        }

        title = "无法解析"
        message = "后端没有返回可展示的结果。"
        suggestions = []
        footnote = assistantResponse.routeReason
        accent = PlanTheme.alertRed
    }
}

private struct ParsingLoadingView: View {
    let input: String
    var onCancel: () -> Void

    @State private var rotation = 0.0
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 0) {
            flowNavBar(title: "AI 解析", onCancel: onCancel)

            VStack(spacing: 22) {
                Spacer(minLength: 10)
                animationView
                headerCopy
                originalInputCard
                steps
                Spacer(minLength: 24)
            }
            .padding(.horizontal, PlanTheme.pagePadding)
            .padding(.top, 14)
            .padding(.bottom, 24)
        }
        .onAppear {
            withAnimation(.linear(duration: 1.35).repeatForever(autoreverses: false)) {
                rotation = 360
            }
            withAnimation(.easeInOut(duration: 0.92).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    private var animationView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .stroke(PlanTheme.borderSubtle, lineWidth: 1)
                .frame(width: 190, height: 190)

            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(PlanTheme.calendarBlue.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(PlanTheme.calendarBlue.opacity(0.18), lineWidth: 1)
                )
                .frame(width: 170, height: 170)
                .scaleEffect(pulse ? 1.03 : 0.98)

            Circle()
                .trim(from: 0.12, to: 0.86)
                .stroke(PlanTheme.calendarBlue, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .frame(width: 152, height: 152)
                .rotationEffect(.degrees(rotation))

            Circle()
                .trim(from: 0.08, to: 0.72)
                .stroke(PlanTheme.alarmOrange.opacity(0.78), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: 112, height: 112)
                .rotationEffect(.degrees(-rotation))

            Text("AI")
                .font(.system(size: 36, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 76, height: 76)
                .background(PlanTheme.surfaceCardStrong, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(PlanTheme.calendarBlue.opacity(0.55), lineWidth: 1)
                )
        }
        .frame(width: 210, height: 210)
        .accessibilityHidden(true)
    }

    private var headerCopy: some View {
        VStack(spacing: 8) {
            Text("AI 正在解析")
                .font(.system(size: 30, weight: .heavy))
                .foregroundStyle(PlanTheme.textPrimary)

            Text("正在识别时间、语义和提醒策略")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(PlanTheme.textSecondary)
        }
    }

    private var originalInputCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "quote.bubble.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(PlanTheme.calendarBlue)
                Text("原始输入")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(PlanTheme.calendarBlue)
            }

            Text("“\(input)”")
                .font(.system(size: 17, weight: .heavy))
                .foregroundStyle(PlanTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .planCard(stroke: PlanTheme.calendarBlue.opacity(0.34), cornerRadius: 20)
    }

    private var steps: some View {
        VStack(spacing: 10) {
            ParsingStepRow(
                symbolName: "sparkles",
                title: "语义识别",
                subtitle: "判断创建、取消、提醒或闹钟意图"
            )
            ParsingStepRow(
                symbolName: "clock.fill",
                title: "时间归一",
                subtitle: "把自然语言时间转换为绝对日期"
            )
            ParsingStepRow(
                symbolName: "checkmark.seal.fill",
                title: "策略生成",
                subtitle: "生成提醒策略并等待用户确认"
            )
        }
    }
}

private struct AssistantResultView: View {
    let result: AssistantDisplayResult
    var onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            flowNavBar(title: "AI 解析结果", onCancel: onCancel)

            VStack(spacing: 18) {
                Spacer(minLength: 40)

                Image(systemName: "text.bubble.fill")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(result.accent)
                    .frame(width: 76, height: 76)
                    .background(result.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                VStack(spacing: 8) {
                    Text(result.title)
                        .font(.system(size: 26, weight: .heavy))
                        .foregroundStyle(PlanTheme.textPrimary)
                        .multilineTextAlignment(.center)

                    Text(result.message)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(PlanTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }

                if !result.suggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(result.suggestions, id: \.self) { suggestion in
                            HStack(alignment: .top, spacing: 8) {
                                Circle()
                                    .fill(result.accent)
                                    .frame(width: 5, height: 5)
                                    .padding(.top, 7)
                                Text(suggestion)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(PlanTheme.textSecondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .planCard(stroke: result.accent.opacity(0.28), cornerRadius: 18)
                }

                if let footnote = result.footnote, !footnote.isEmpty {
                    Text(footnote)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(PlanTheme.textMuted)
                        .multilineTextAlignment(.center)
                }

                Spacer(minLength: 24)
            }
            .padding(.horizontal, PlanTheme.pagePadding)
        }
    }
}

private struct ParsingErrorView: View {
    let input: String
    let message: String
    var onCancel: () -> Void
    var onRetry: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            flowNavBar(title: "AI 解析", onCancel: onCancel)

            VStack(spacing: 18) {
                Spacer(minLength: 56)

                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(PlanTheme.alertRed)
                    .frame(width: 76, height: 76)
                    .background(PlanTheme.alertRed.opacity(0.14), in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                VStack(spacing: 8) {
                    Text("解析失败")
                        .font(.system(size: 28, weight: .heavy))
                        .foregroundStyle(PlanTheme.textPrimary)

                    Text(message)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(PlanTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("原始输入")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(PlanTheme.alertRed)
                    Text("“\(input)”")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(PlanTheme.textPrimary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .planCard(stroke: PlanTheme.alertRed.opacity(0.34), cornerRadius: 20)

                HStack(spacing: 12) {
                    Button(action: onCancel) {
                        Text("返回录入")
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(PlanTheme.surfaceCardStrong, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    Button(action: onRetry) {
                        Text("重试")
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(PlanTheme.calendarBlue, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }

                Spacer(minLength: 24)
            }
            .padding(.horizontal, PlanTheme.pagePadding)
        }
    }
}

private struct ParsingStepRow: View {
    let symbolName: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbolName)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(PlanTheme.calendarBlue)
                .planIconBox()

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(PlanTheme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(PlanTheme.textSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .planCard(fill: PlanTheme.surfaceCard, cornerRadius: 16)
    }
}

struct ConfirmEventView: View {
    let response: IntentResponse
    let draft: DraftEvent
    let isSaving: Bool
    var onCancel: () -> Void
    var onSave: (DraftEvent, ReminderPolicy) -> Void

    @State private var title: String
    @State private var taskDate: Date
    @State private var taskTime: Date
    @State private var hasTime: Bool
    @State private var reminderKind: ReminderPolicyKind
    @State private var customOffsetText: String
    @State private var notes: String

    init(
        response: IntentResponse,
        draft: DraftEvent,
        isSaving: Bool = false,
        onCancel: @escaping () -> Void,
        onSave: @escaping (DraftEvent, ReminderPolicy) -> Void
    ) {
        self.response = response
        self.draft = draft
        self.isSaving = isSaving
        self.onCancel = onCancel
        self.onSave = onSave
        _title = State(initialValue: draft.title)
        _taskDate = State(initialValue: draft.taskDate)
        _taskTime = State(initialValue: draft.taskTime ?? Self.defaultTime(on: draft.taskDate))
        _hasTime = State(initialValue: draft.taskTime != nil)
        _reminderKind = State(initialValue: draft.reminderPolicy.kind)
        _customOffsetText = State(initialValue: "\(draft.reminderPolicy.offsetMinutes ?? 60)")
        _notes = State(initialValue: draft.notes)
    }

    var body: some View {
        VStack(spacing: 0) {
            flowNavBar(title: "AI 解析结果", onCancel: onCancel)

            ScrollView {
                VStack(spacing: 10) {
                    summaryCard
                    editableFields
                    confirmationCard
                }
                .padding(.horizontal, PlanTheme.pagePadding)
                .padding(.top, 10)
                .padding(.bottom, 104)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom) {
            actionBar
        }
        .onChange(of: reminderKind) { _, newValue in
            if newValue == .customOffset, customOffsetText.isEmpty {
                customOffsetText = "60"
            }
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("原始输入")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(PlanTheme.textSecondary)

            Text("“\(draft.rawText)”")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(PlanTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                HStack(spacing: 7) {
                    Image(systemName: draft.kind.symbolName)
                        .font(.system(size: 15, weight: .bold))
                    Text(draft.kind.displayName)
                        .font(.system(size: 12, weight: .heavy))
                }
                .foregroundStyle(draft.kind == .alarm ? PlanTheme.alarmOrange : PlanTheme.calendarBlue)

                Spacer()

                Text("\(Int(response.confidence * 100))%")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(PlanTheme.textSecondary)
            }
        }
        .padding(10)
        .planCard(stroke: PlanTheme.alarmOrange.opacity(0.34), cornerRadius: 20)
    }

    private var editableFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("标题")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(PlanTheme.textSecondary)

            TextField("标题", text: $title)
                .font(.system(size: 17, weight: .heavy))
                .foregroundStyle(PlanTheme.textPrimary)
                .textInputAutocapitalization(.never)
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(PlanTheme.surfaceCardStrong, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            HStack(spacing: 8) {
                ConfirmField(symbolName: "calendar", label: "日期", tint: PlanTheme.calendarBlue) {
                    DatePicker("", selection: $taskDate, displayedComponents: .date)
                        .labelsHidden()
                        .tint(PlanTheme.calendarBlue)
                }

                ConfirmField(symbolName: "clock.fill", label: "时间", tint: PlanTheme.calendarBlue) {
                    DatePicker("", selection: $taskTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .tint(PlanTheme.calendarBlue)
                        .disabled(!hasTime)
                }
            }

            HStack(spacing: 8) {
                ConfirmField(symbolName: "switch.2", label: "包含具体时间", tint: PlanTheme.calendarBlue) {
                    Toggle("", isOn: $hasTime)
                        .labelsHidden()
                        .tint(PlanTheme.calendarBlue)
                }

                ConfirmField(symbolName: "bell.fill", label: "提醒策略", tint: PlanTheme.alarmOrange) {
                    Text(currentReminderPolicy.displayText)
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(PlanTheme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.74)
                }
            }

            Picker("提醒策略", selection: $reminderKind) {
                ForEach(ReminderPolicyKind.allCases, id: \.self) { kind in
                    Text(kind.compactName).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .frame(height: 32)
            .tint(PlanTheme.calendarBlue)

            if reminderKind == .customOffset {
                HStack(spacing: 10) {
                    Text("提前分钟数")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(PlanTheme.textSecondary)
                    TextField("60", text: $customOffsetText)
                        .keyboardType(.numberPad)
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(PlanTheme.textPrimary)
                        .multilineTextAlignment(.trailing)
                }
                .padding(.horizontal, 10)
                .frame(height: 38)
                .background(PlanTheme.surfaceCardStrong, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            TextField("备注", text: $notes, axis: .vertical)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(PlanTheme.textSecondary)
                .lineLimit(1...3)
                .padding(.horizontal, 10)
                .frame(minHeight: 34)
                .background(PlanTheme.surfaceCardStrong, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Text("原文调整：\(draft.rawText)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(PlanTheme.textSecondary)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                .background(PlanTheme.surfaceCardStrong, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(12)
        .planCard(cornerRadius: 20)
    }

    private var confirmationCard: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("确认提示")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(PlanTheme.textSecondary)
            Text("已按设备所在时区解析为 \(PlanDateFormatter.fullDate(taskDate)) \(hasTime ? PlanDateFormatter.shortTime(taskTime) : "全天")，请确认。")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(PlanTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .planCard(cornerRadius: 18)
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button(action: onCancel) {
                Text("取消")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 42)
                    .background(PlanTheme.surfaceCardStrong, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            Button(action: save) {
                Text(isSaving ? "保存中..." : (draft.kind == .alarm ? "保存日程和闹钟" : "保存日程"))
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .frame(maxWidth: .infinity, minHeight: 42)
                    .background(PlanTheme.alarmOrange, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .disabled(isSaving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(10)
        .background(PlanTheme.surfaceApp.opacity(0.95), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(PlanTheme.borderSubtle, lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(PlanTheme.surfaceApp.opacity(0.82))
    }

    private var currentReminderPolicy: ReminderPolicy {
        ReminderPolicy(kind: reminderKind, offsetMinutes: customOffset)
    }

    private var customOffset: Int? {
        guard reminderKind == .customOffset else {
            return nil
        }
        return max(Int(customOffsetText) ?? 60, 1)
    }

    private func save() {
        let editedDraft = makeEditedDraft()
        onSave(editedDraft, currentReminderPolicy)
    }

    private func makeEditedDraft() -> DraftEvent {
        let calendar = Calendar.current
        let normalizedTaskDate = calendar.startOfDay(for: taskDate)
        let scheduledAt: Date?

        if hasTime {
            let timeComponents = calendar.dateComponents([.hour, .minute], from: taskTime)
            var dateComponents = calendar.dateComponents([.year, .month, .day], from: taskDate)
            dateComponents.hour = timeComponents.hour
            dateComponents.minute = timeComponents.minute
            scheduledAt = calendar.date(from: dateComponents)
        } else {
            scheduledAt = nil
        }

        return DraftEvent(
            kind: draft.kind,
            rawText: draft.rawText,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            taskDate: normalizedTaskDate,
            taskTime: scheduledAt,
            endAt: scheduledAt.flatMap { calendar.date(byAdding: .hour, value: 1, to: $0) },
            reminderPolicy: currentReminderPolicy,
            notes: notes,
            timezoneIdentifier: draft.timezoneIdentifier
        )
    }

    private static func defaultTime(on date: Date) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        components.hour = 9
        components.minute = 0
        return Calendar.current.date(from: components) ?? date
    }
}

private struct ConfirmField<Content: View>: View {
    let symbolName: String
    let label: String
    let tint: Color
    let content: () -> Content

    init(
        symbolName: String,
        label: String,
        tint: Color,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.symbolName = symbolName
        self.label = label
        self.tint = tint
        self.content = content
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbolName)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(PlanTheme.textSecondary)
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(PlanTheme.surfaceCardStrong, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

@ViewBuilder
private func flowNavBar(title: String, onCancel: @escaping () -> Void) -> some View {
    HStack {
        Color.clear
            .frame(width: 30, height: 30)

        Spacer()

        Text(title)
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(PlanTheme.textPrimary)

        Spacer()

        Button(action: onCancel) {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("关闭")
    }
    .frame(height: 46)
    .padding(.horizontal, PlanTheme.pagePadding)
}
