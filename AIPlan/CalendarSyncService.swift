//
//  CalendarSyncService.swift
//  AIPlan
//
//  Created by Codex on 2026/7/13.
//

import EventKit
import Foundation

struct CalendarSyncIdentifiers {
    var eventIdentifier: String?
    var calendarItemIdentifier: String?
}

enum CalendarSyncError: LocalizedError {
    case accessDenied
    case defaultCalendarUnavailable
    case eventStartUnavailable

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            "需要允许完整日历访问，才能同步和删除系统日历日程。"
        case .defaultCalendarUnavailable:
            "没有找到可写入的默认系统日历。"
        case .eventStartUnavailable:
            "日程缺少可同步的开始时间。"
        }
    }
}

@MainActor
final class CalendarSyncService {
    let eventStore = EKEventStore()

    var hasFullAccess: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    func requestFullAccessIfNeeded() async throws {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            return
        case .notDetermined:
            let granted = try await requestFullAccess()
            guard granted else {
                throw CalendarSyncError.accessDenied
            }
        case .writeOnly, .denied, .restricted:
            throw CalendarSyncError.accessDenied
        @unknown default:
            throw CalendarSyncError.accessDenied
        }
    }

    func createCalendarEvent(for event: ScheduleEvent) async throws -> CalendarSyncIdentifiers {
        try await requestFullAccessIfNeeded()
        guard let defaultCalendar = eventStore.defaultCalendarForNewEvents else {
            throw CalendarSyncError.defaultCalendarUnavailable
        }

        let calendarEvent = EKEvent(eventStore: eventStore)
        calendarEvent.calendar = defaultCalendar
        calendarEvent.title = event.title
        calendarEvent.timeZone = TimeZone(identifier: event.timezoneIdentifier) ?? .current
        calendarEvent.notes = mergedNotes(for: event)

        if let scheduledAt = event.taskTime {
            calendarEvent.isAllDay = false
            calendarEvent.startDate = scheduledAt
            calendarEvent.endDate = validEndDate(for: event, startDate: scheduledAt)
        } else {
            calendarEvent.isAllDay = true
            let startOfDay = Calendar.current.startOfDay(for: event.taskDate)
            calendarEvent.startDate = startOfDay
            calendarEvent.endDate = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
        }

        if let alarm = makeReminderAlarm(for: event.reminderPolicy) {
            calendarEvent.addAlarm(alarm)
        }

        try eventStore.save(calendarEvent, span: .thisEvent)

        return CalendarSyncIdentifiers(
            eventIdentifier: calendarEvent.eventIdentifier,
            calendarItemIdentifier: calendarEvent.calendarItemIdentifier
        )
    }

    func deleteCalendarEvent(for event: ScheduleEvent) async throws {
        try await requestFullAccessIfNeeded()

        guard let calendarEvent = fetchCalendarEvent(for: event) else {
            return
        }

        try eventStore.remove(calendarEvent, span: .thisEvent)
    }

    func calendarEventExists(for event: ScheduleEvent) -> Bool {
        guard hasFullAccess else {
            return true
        }
        guard event.calendarEventIdentifier != nil || event.calendarItemIdentifier != nil else {
            return true
        }
        return fetchCalendarEvent(for: event) != nil
    }

    private func fetchCalendarEvent(for event: ScheduleEvent) -> EKEvent? {
        if let eventIdentifier = event.calendarEventIdentifier,
           let calendarEvent = eventStore.event(withIdentifier: eventIdentifier) {
            return calendarEvent
        }

        if let itemIdentifier = event.calendarItemIdentifier,
           let calendarItem = eventStore.calendarItem(withIdentifier: itemIdentifier) as? EKEvent {
            return calendarItem
        }

        return nil
    }

    private func requestFullAccess() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            eventStore.requestFullAccessToEvents { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    private func validEndDate(for event: ScheduleEvent, startDate: Date) -> Date {
        guard let endAt = event.endAt, endAt > startDate else {
            return Calendar.current.date(byAdding: .hour, value: 1, to: startDate) ?? startDate.addingTimeInterval(3600)
        }
        return endAt
    }

    private func makeReminderAlarm(for policy: ReminderPolicy) -> EKAlarm? {
        switch policy.kind {
        case .none:
            return nil
        case .atTime:
            return EKAlarm(relativeOffset: 0)
        case .tenMinutesBefore:
            return EKAlarm(relativeOffset: -10 * 60)
        case .customOffset:
            let minutes = max(policy.offsetMinutes ?? 60, 1)
            return EKAlarm(relativeOffset: TimeInterval(-minutes * 60))
        }
    }

    private func mergedNotes(for event: ScheduleEvent) -> String {
        [
            event.notes.isEmpty ? nil : event.notes,
            event.rawText.isEmpty ? nil : "原始输入：\(event.rawText)",
            "AIPlanID：\(event.id)"
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
    }
}
