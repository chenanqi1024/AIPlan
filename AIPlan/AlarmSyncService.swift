//
//  AlarmSyncService.swift
//  AIPlan
//
//  Created by Codex on 2026/7/13.
//

import AlarmKit
import Foundation
import SwiftUI

struct PlanAlarmMetadata: AlarmMetadata {
    var eventID: String
    var title: String
    var rawText: String
}

enum AlarmSyncError: LocalizedError {
    case accessDenied
    case alarmNeedsSpecificTime

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            "需要允许闹钟权限，才能创建系统强提醒闹钟。"
        case .alarmNeedsSpecificTime:
            "闹钟必须包含具体时间。"
        }
    }
}

@MainActor
final class AlarmSyncService {
    private let manager = AlarmManager.shared

    func requestAuthorizationIfNeeded() async throws {
        switch manager.authorizationState {
        case .authorized:
            return
        case .notDetermined:
            let state = try await manager.requestAuthorization()
            guard state == .authorized else {
                throw AlarmSyncError.accessDenied
            }
        case .denied:
            throw AlarmSyncError.accessDenied
        @unknown default:
            throw AlarmSyncError.accessDenied
        }
    }

    func scheduleAlarm(for event: ScheduleEvent) async throws -> UUID {
        try await requestAuthorizationIfNeeded()
        guard let scheduledAt = event.taskTime else {
            throw AlarmSyncError.alarmNeedsSpecificTime
        }

        let alarmID = UUID(uuidString: event.alarmIdentifier ?? event.id) ?? UUID()
        let metadata = PlanAlarmMetadata(
            eventID: event.id,
            title: event.title,
            rawText: event.rawText
        )
        let presentation = AlarmPresentation(
            alert: AlarmPresentation.Alert(title: "AI 日程闹钟")
        )
        let attributes = AlarmAttributes(
            presentation: presentation,
            metadata: metadata,
            tintColor: .orange
        )
        let configuration = AlarmManager.AlarmConfiguration<PlanAlarmMetadata>.alarm(
            schedule: .fixed(scheduledAt),
            attributes: attributes
        )

        _ = try await manager.schedule(id: alarmID, configuration: configuration)
        return alarmID
    }

    func cancelAlarm(identifier: String?) async throws {
        guard let identifier, let alarmID = UUID(uuidString: identifier) else {
            return
        }
        try manager.cancel(id: alarmID)
    }
}
