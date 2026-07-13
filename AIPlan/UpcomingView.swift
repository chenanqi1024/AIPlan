//
//  UpcomingView.swift
//  AIPlan
//
//  Created by Codex on 2026/7/13.
//

import SwiftData
import SwiftUI

struct UpcomingView: View {
    let systemSyncService: ScheduleSystemSyncService

    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var modelContext
    @Query private var events: [ScheduleEvent]

    @State private var showsPast = false
    @State private var showsCompleted = false
    @State private var pendingDeleteEventID: String?
    @State private var operationError: String?

    private var calendar: Calendar {
        .current
    }

    private var sortedEvents: [ScheduleEvent] {
        events.sorted { lhs, rhs in
            if lhs.startDate == rhs.startDate {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.startDate < rhs.startDate
        }
    }

    private var todayEvents: [ScheduleEvent] {
        sortedEvents.filter { !$0.isCompleted && calendar.isDateInToday($0.startDate) }
    }

    private var tomorrowEvents: [ScheduleEvent] {
        sortedEvents.filter { !$0.isCompleted && calendar.isDateInTomorrow($0.startDate) }
    }

    private var futureEvents: [ScheduleEvent] {
        let today = calendar.startOfDay(for: Date())
        return sortedEvents.filter {
            !$0.isCompleted && calendar.startOfDay(for: $0.startDate) > today
        }
    }

    private var laterEvents: [ScheduleEvent] {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        let tomorrowStart = calendar.startOfDay(for: tomorrow)
        return sortedEvents.filter {
            !$0.isCompleted && calendar.startOfDay(for: $0.startDate) > tomorrowStart
        }
    }

    private var laterEventGroups: [ScheduleDayGroup] {
        laterEvents.reduce(into: []) { groups, event in
            let day = calendar.startOfDay(for: event.startDate)
            if let lastIndex = groups.indices.last, calendar.isDate(groups[lastIndex].date, inSameDayAs: day) {
                groups[lastIndex].events.append(event)
            } else {
                groups.append(ScheduleDayGroup(date: day, events: [event]))
            }
        }
    }

    private var pastEvents: [ScheduleEvent] {
        let today = calendar.startOfDay(for: Date())
        return sortedEvents.filter {
            !$0.isCompleted && calendar.startOfDay(for: $0.startDate) < today
        }
    }

    private var completedEvents: [ScheduleEvent] {
        sortedEvents.filter(\.isCompleted)
    }

    private var nextEvent: ScheduleEvent? {
        sortedEvents.first { !$0.isCompleted && $0.startDate >= Date() }
    }

    var body: some View {
        ZStack {
            PlanTheme.surfaceApp.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    dashboard

                    if events.isEmpty {
                        emptyState
                    } else {
                        todaySection
                        pastDisclosure
                        tomorrowSection
                        laterSection
                        completedDisclosure
                    }
                }
                .padding(.horizontal, PlanTheme.pagePadding)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .alert("操作失败", isPresented: Binding(
            get: { operationError != nil },
            set: { isPresented in
                if !isPresented {
                    operationError = nil
                }
            }
        )) {
            Button("好") {
                operationError = nil
            }
        } message: {
            Text(operationError ?? "")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(PlanDateFormatter.friendlyDate())
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(PlanTheme.textSecondary)

            Text("全部日程")
                .font(.system(size: 32, weight: .heavy))
                .foregroundStyle(PlanTheme.textPrimary)

            Text("今天 \(todayEvents.count) 项 · 未来 \(futureEvents.count) 项")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(PlanTheme.textSecondary)

            if let nextEvent {
                Text("下一项 \(PlanDateFormatter.shortTime(nextEvent.taskTime)) \(nextEvent.title)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(nextEvent.eventKind == .alarm ? PlanTheme.alarmOrange : PlanTheme.calendarBlue)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var dashboard: some View {
        HStack(spacing: 8) {
            MetricCard(item: MetricItem(
                title: "待处理",
                value: todayEvents.count + futureEvents.count,
                symbolName: "clock.fill",
                color: PlanTheme.calendarBlue
            ))
            MetricCard(item: MetricItem(
                title: "已过",
                value: pastEvents.count,
                symbolName: "exclamationmark.circle.fill",
                color: PlanTheme.alertRed
            ))
            MetricCard(item: MetricItem(
                title: "完成",
                value: completedEvents.count,
                symbolName: "checkmark.circle.fill",
                color: PlanTheme.successGreen
            ))
        }
    }

    private var emptyState: some View {
        ContentUnavailableView("暂无日程", systemImage: "calendar.badge.plus")
            .foregroundStyle(PlanTheme.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 260)
    }

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("今天")
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(PlanTheme.textPrimary)
                Text(PlanDateFormatter.weekday(Date()))
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(PlanTheme.textSecondary)
                Text("\(todayEvents.count) 项")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(PlanTheme.textSecondary)
            }

            if todayEvents.isEmpty {
                Text("暂无日程")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(PlanTheme.textMuted)
                    .frame(maxWidth: .infinity, minHeight: 66)
                    .planCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(todayEvents.enumerated()), id: \.element.id) { index, event in
                        TimelineEventRow(
                            event: event,
                            isLast: index == todayEvents.count - 1,
                            onOpenCalendar: openSystemCalendar,
                            onToggleComplete: toggleComplete,
                            onDelete: delete
                        )
                    }
                }
            }
        }
    }

    private var pastDisclosure: some View {
        VStack(spacing: 10) {
            DisclosureHeader(
                title: "已过事项 \(pastEvents.count) 项",
                isExpanded: showsPast,
                action: { showsPast.toggle() }
            )

            if showsPast {
                VStack(spacing: 0) {
                    ForEach(Array(pastEvents.enumerated()), id: \.element.id) { index, event in
                        TimelineEventRow(
                            event: event,
                            isLast: index == pastEvents.count - 1,
                            onOpenCalendar: openSystemCalendar,
                            onToggleComplete: toggleComplete,
                            onDelete: delete
                        )
                    }
                }
            }
        }
    }

    private var tomorrowSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
                Text("明天")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(PlanTheme.textPrimary)
                Text(PlanDateFormatter.weekday(tomorrow))
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(PlanTheme.textSecondary)
                Text("\(tomorrowEvents.count) 项")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(PlanTheme.textSecondary)
            }

            if tomorrowEvents.isEmpty {
                Text("暂无日程")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(PlanTheme.textMuted)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .planCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(tomorrowEvents.enumerated()), id: \.element.id) { index, event in
                        TimelineEventRow(
                            event: event,
                            isLast: index == tomorrowEvents.count - 1,
                            onOpenCalendar: openSystemCalendar,
                            onToggleComplete: toggleComplete,
                            onDelete: delete
                        )
                    }
                }
            }
        }
    }

    private var laterSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("未来日程")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(PlanTheme.textPrimary)
                Text("\(laterEvents.count) 项")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(PlanTheme.textSecondary)
            }

            if laterEventGroups.isEmpty {
                Text("暂无更多日程")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(PlanTheme.textMuted)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .planCard()
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(laterEventGroups) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Text(PlanDateFormatter.fullDate(group.date))
                                    .font(.system(size: 14, weight: .heavy))
                                    .foregroundStyle(PlanTheme.textPrimary)
                                Text(PlanDateFormatter.weekday(group.date))
                                    .font(.system(size: 13, weight: .heavy))
                                    .foregroundStyle(PlanTheme.textSecondary)
                                Text("\(group.events.count) 项")
                                    .font(.system(size: 13, weight: .heavy))
                                    .foregroundStyle(PlanTheme.textSecondary)
                            }

                            VStack(spacing: 0) {
                                ForEach(Array(group.events.enumerated()), id: \.element.id) { index, event in
                                    TimelineEventRow(
                                        event: event,
                                        isLast: index == group.events.count - 1,
                                        onOpenCalendar: openSystemCalendar,
                                        onToggleComplete: toggleComplete,
                                        onDelete: delete
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var completedDisclosure: some View {
        VStack(spacing: 10) {
            DisclosureHeader(
                title: "已完成 \(completedEvents.count) 项",
                isExpanded: showsCompleted,
                action: { showsCompleted.toggle() }
            )

            if showsCompleted {
                VStack(spacing: 0) {
                    ForEach(Array(completedEvents.enumerated()), id: \.element.id) { index, event in
                        TimelineEventRow(
                            event: event,
                            isLast: index == completedEvents.count - 1,
                            onOpenCalendar: openSystemCalendar,
                            onToggleComplete: toggleComplete,
                            onDelete: delete
                        )
                    }
                }
            }
        }
    }

    private func openSystemCalendar(_ event: ScheduleEvent) {
        guard let url = calendarURL(for: event.startDate) else {
            operationError = "无法打开系统日历"
            return
        }

        openURL(url) { accepted in
            if !accepted {
                operationError = "无法打开系统日历"
            }
        }
    }

    private func calendarURL(for date: Date) -> URL? {
        let targetDate = calendar.startOfDay(for: date)
        let seconds = Int(targetDate.timeIntervalSinceReferenceDate)
        return URL(string: "calshow:\(seconds)")
    }

    private func toggleComplete(_ event: ScheduleEvent) {
        event.isCompleted.toggle()
        try? modelContext.save()
    }

    private func delete(_ event: ScheduleEvent) {
        guard pendingDeleteEventID == nil else {
            return
        }

        pendingDeleteEventID = event.id
        Task {
            do {
                try await systemSyncService.deleteSystemRecords(for: event)
                modelContext.delete(event)
                try modelContext.save()
            } catch {
                operationError = error.localizedDescription
            }
            pendingDeleteEventID = nil
        }
    }
}

private struct ScheduleDayGroup: Identifiable {
    let date: Date
    var events: [ScheduleEvent]

    var id: Date {
        date
    }
}

private struct MetricCard: View {
    let item: MetricItem

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: item.symbolName)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(item.color)

            VStack(alignment: .leading, spacing: 1) {
                Text("\(item.value)")
                    .font(.system(size: 19, weight: .heavy))
                    .foregroundStyle(PlanTheme.textPrimary)
                Text(item.title)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(PlanTheme.textSecondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .planCard(fill: PlanTheme.surfaceCard.opacity(0.62), stroke: item.color.opacity(0.30), cornerRadius: 14)
    }
}

private struct DisclosureHeader: View {
    let title: String
    let isExpanded: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(PlanTheme.textSecondary)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(PlanTheme.textMuted)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct TimelineEventRow: View {
    let event: ScheduleEvent
    let isLast: Bool
    var onOpenCalendar: (ScheduleEvent) -> Void
    var onToggleComplete: (ScheduleEvent) -> Void
    var onDelete: (ScheduleEvent) -> Void

    private var accent: Color {
        event.eventKind == .alarm ? PlanTheme.alarmOrange : PlanTheme.calendarBlue
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .trailing, spacing: 5) {
                Text(PlanDateFormatter.shortTime(event.taskTime))
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(accent)
                    .frame(width: 48, alignment: .trailing)

                Circle()
                    .fill(accent)
                    .frame(width: 7, height: 7)

                Rectangle()
                    .fill(isLast ? .clear : PlanTheme.borderSubtle)
                    .frame(width: 1, height: 42)
            }
            .frame(width: 48)

            HStack(spacing: 11) {
                Button {
                    onToggleComplete(event)
                } label: {
                    Image(systemName: event.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(event.isCompleted ? PlanTheme.successGreen : PlanTheme.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(event.isCompleted ? "标记为未完成" : "标记为完成")

                Button {
                    onOpenCalendar(event)
                } label: {
                    Image(systemName: event.eventKind.symbolName)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(accent)
                        .planIconBox(fill: accent.opacity(0.14))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("在系统日历中打开 \(PlanDateFormatter.fullDate(event.startDate))")

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        Text(event.eventKind.shortName)
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(accent)
                        Text(event.notes.isEmpty ? event.reminderPolicy.displayText : event.notes)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(PlanTheme.textSecondary)
                            .lineLimit(1)
                    }

                    Text(event.title)
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(PlanTheme.textPrimary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button(role: .destructive) {
                    onDelete(event)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(PlanTheme.textMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("删除日程")
            }
            .padding(.vertical, 11)
            .padding(.horizontal, 12)
            .planCard(fill: PlanTheme.surfaceCard.opacity(0.62), stroke: accent.opacity(0.27), cornerRadius: 18)
        }
    }
}
