//
//  ScheduleModels.swift
//  AIPlan
//
//  Created by Codex on 2026/7/13.
//

import Foundation
import SwiftData

enum EventKind: String, Codable, CaseIterable, Hashable {
    case calendar
    case alarm

    var displayName: String {
        switch self {
        case .calendar:
            "日程"
        case .alarm:
            "日程 + 闹钟"
        }
    }

    var shortName: String {
        switch self {
        case .calendar:
            "日程"
        case .alarm:
            "闹钟"
        }
    }

    var symbolName: String {
        switch self {
        case .calendar:
            "calendar"
        case .alarm:
            "alarm.fill"
        }
    }
}

enum ReminderPolicyKind: String, Codable, CaseIterable, Hashable {
    case none
    case atTime
    case tenMinutesBefore
    case customOffset

    var displayName: String {
        switch self {
        case .none:
            "不提醒"
        case .atTime:
            "准时"
        case .tenMinutesBefore:
            "提前 10 分钟"
        case .customOffset:
            "自定义"
        }
    }

    var compactName: String {
        switch self {
        case .none:
            "不提醒"
        case .atTime:
            "准时"
        case .tenMinutesBefore:
            "提前10"
        case .customOffset:
            "自定义"
        }
    }
}

struct ReminderPolicy: Codable, Hashable {
    var kind: ReminderPolicyKind
    var offsetMinutes: Int?

    var displayText: String {
        switch kind {
        case .none:
            "不提醒"
        case .atTime:
            "准时提醒"
        case .tenMinutesBefore:
            "提前 10 分钟"
        case .customOffset:
            "提前 \(offsetMinutes ?? 60) 分钟"
        }
    }
}

enum IntentType: String, Codable, Hashable {
    case create
    case cancel
    case clarify
    case unsupported
}

struct DraftEvent: Codable, Hashable {
    var kind: EventKind
    var rawText: String
    var title: String
    var taskDate: Date
    var taskTime: Date?
    var endAt: Date?
    var reminderPolicy: ReminderPolicy
    var notes: String
    var timezoneIdentifier: String
}

struct IntentResponse: Codable, Hashable {
    var intent: IntentType
    var draft: DraftEvent?
    var targetEventID: String?
    var candidateEventIDs: [String]
    var question: String?
    var message: String?
    var reason: String?
    var confidence: Double
    var ambiguities: [String]
    var needsConfirmation: Bool
}

@Model
final class ScheduleEvent: Identifiable {
    @Attribute(.unique) var id: String
    var kind: String
    var rawText: String
    var title: String
    var taskDate: Date
    var taskTime: Date?
    var endAt: Date?
    var reminderPolicyKind: String
    var reminderOffsetMinutes: Int?
    var notes: String
    var timezoneIdentifier: String
    var isCompleted: Bool
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        kind: EventKind,
        rawText: String,
        title: String,
        taskDate: Date,
        taskTime: Date?,
        endAt: Date?,
        reminderPolicy: ReminderPolicy,
        notes: String,
        timezoneIdentifier: String,
        isCompleted: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind.rawValue
        self.rawText = rawText
        self.title = title
        self.taskDate = taskDate
        self.taskTime = taskTime
        self.endAt = endAt
        self.reminderPolicyKind = reminderPolicy.kind.rawValue
        self.reminderOffsetMinutes = reminderPolicy.offsetMinutes
        self.notes = notes
        self.timezoneIdentifier = timezoneIdentifier
        self.isCompleted = isCompleted
        self.createdAt = createdAt
    }

    convenience init(draft: DraftEvent, reminderPolicy: ReminderPolicy) {
        self.init(
            kind: draft.kind,
            rawText: draft.rawText,
            title: draft.title,
            taskDate: draft.taskDate,
            taskTime: draft.taskTime,
            endAt: draft.endAt,
            reminderPolicy: reminderPolicy,
            notes: draft.notes,
            timezoneIdentifier: draft.timezoneIdentifier
        )
    }

    var eventKind: EventKind {
        EventKind(rawValue: kind) ?? .calendar
    }

    var reminderPolicy: ReminderPolicy {
        ReminderPolicy(
            kind: ReminderPolicyKind(rawValue: reminderPolicyKind) ?? .tenMinutesBefore,
            offsetMinutes: reminderOffsetMinutes
        )
    }

    var startDate: Date {
        taskTime ?? taskDate
    }

    func queryContextEvent() -> QueryContextEvent {
        QueryContextEvent(
            id: id,
            kind: eventKind,
            title: title,
            taskDate: taskDate,
            scheduledAt: taskTime,
            endAt: endAt,
            notes: notes,
            timezoneIdentifier: timezoneIdentifier,
            isCompleted: isCompleted
        )
    }
}

struct MockScheduleParser {
    func parse(text: String, now: Date = Date()) async -> IntentResponse {
        try? await Task.sleep(for: .milliseconds(1200))

        let calendar = Calendar.current
        let timezoneIdentifier = TimeZone.current.identifier
        let normalizedDay = parsedDay(from: text, now: now, calendar: calendar)
        let parsedTime = parsedClockTime(from: text, on: normalizedDay, calendar: calendar)
        let kind: EventKind = containsAlarmIntent(text) ? .alarm : .calendar
        let title = parsedTitle(from: text, kind: kind)
        let endAt = parsedTime.flatMap { calendar.date(byAdding: .hour, value: 1, to: $0) }

        let draft = DraftEvent(
            kind: kind,
            rawText: text,
            title: title,
            taskDate: calendar.startOfDay(for: normalizedDay),
            taskTime: parsedTime,
            endAt: endAt,
            reminderPolicy: ReminderPolicy(kind: .tenMinutesBefore, offsetMinutes: nil),
            notes: kind == .alarm ? "一次性闹钟，起床提醒" : "",
            timezoneIdentifier: timezoneIdentifier
        )

        return IntentResponse(
            intent: .create,
            draft: draft,
            targetEventID: nil,
            candidateEventIDs: [],
            question: nil,
            message: nil,
            reason: nil,
            confidence: kind == .alarm ? 0.92 : 0.88,
            ambiguities: [],
            needsConfirmation: true
        )
    }

    private func containsAlarmIntent(_ text: String) -> Bool {
        ["闹钟", "叫醒", "叫我起床", "起床", "设个闹钟"].contains { text.contains($0) }
    }

    private func parsedDay(from text: String, now: Date, calendar: Calendar) -> Date {
        if text.contains("后天") {
            return calendar.date(byAdding: .day, value: 2, to: now) ?? now
        }
        if text.contains("明") {
            return calendar.date(byAdding: .day, value: 1, to: now) ?? now
        }
        return now
    }

    private func parsedClockTime(from text: String, on day: Date, calendar: Calendar) -> Date? {
        let hour: Int
        let minute: Int

        if text.contains("下午三点") || text.contains("下午 3 点") {
            hour = 15
            minute = 0
        } else if text.contains("8 点") || text.contains("8点") || text.contains("八点") {
            hour = 8
            minute = 0
        } else if text.contains("18:30") || text.contains("六点半") {
            hour = 18
            minute = 30
        } else {
            return nil
        }

        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)
    }

    private func parsedTitle(from text: String, kind: EventKind) -> String {
        if kind == .alarm {
            return "起床"
        }

        var title = text
        ["提醒我", "帮我", "安排", "明天", "明早", "今天", "下午三点", "下午 3 点", "8 点", "8点"].forEach {
            title = title.replacingOccurrences(of: $0, with: "")
        }
        title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "新的日程" : title
    }
}
