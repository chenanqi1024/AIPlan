//
//  ScheduleSystemSyncService.swift
//  AIPlan
//
//  Created by Codex on 2026/7/13.
//

import EventKit
import Foundation
import SwiftData

@MainActor
final class ScheduleSystemSyncService {
    let calendarSyncService = CalendarSyncService()
    let alarmSyncService = AlarmSyncService()

    func requestRequiredPermissions() async {
        _ = try? await calendarSyncService.requestFullAccessIfNeeded()
        _ = try? await alarmSyncService.requestAuthorizationIfNeeded()
    }

    func createSystemRecords(for event: ScheduleEvent) async throws {
        let identifiers = try await calendarSyncService.createCalendarEvent(for: event)
        event.calendarEventIdentifier = identifiers.eventIdentifier
        event.calendarItemIdentifier = identifiers.calendarItemIdentifier

        guard event.eventKind == .alarm else {
            return
        }

        do {
            let alarmID = try await alarmSyncService.scheduleAlarm(for: event)
            event.alarmIdentifier = alarmID.uuidString
        } catch {
            try? await calendarSyncService.deleteCalendarEvent(for: event)
            event.calendarEventIdentifier = nil
            event.calendarItemIdentifier = nil
            throw error
        }
    }

    func deleteSystemRecords(for event: ScheduleEvent) async throws {
        var deletionError: Error?

        do {
            try await calendarSyncService.deleteCalendarEvent(for: event)
        } catch {
            deletionError = error
        }

        do {
            try await alarmSyncService.cancelAlarm(identifier: event.alarmIdentifier)
        } catch {
            if deletionError == nil {
                deletionError = error
            }
        }

        if let deletionError {
            throw deletionError
        }
    }

    func reconcileExternalCalendarDeletions(
        events: [ScheduleEvent],
        modelContext: ModelContext
    ) async throws {
        guard calendarSyncService.hasFullAccess else {
            return
        }

        var didDelete = false
        for event in events where event.calendarEventIdentifier != nil || event.calendarItemIdentifier != nil {
            guard !calendarSyncService.calendarEventExists(for: event) else {
                continue
            }

            try? await alarmSyncService.cancelAlarm(identifier: event.alarmIdentifier)
            modelContext.delete(event)
            didDelete = true
        }

        if didDelete {
            try modelContext.save()
        }
    }
}
