//
//  AppRootView.swift
//  AIPlan
//
//  Created by Codex on 2026/7/13.
//

import EventKit
import SwiftData
import SwiftUI

enum AppTab: Hashable {
    case capture
    case today

    var title: String {
        switch self {
        case .capture:
            "录入"
        case .today:
            "今日"
        }
    }

    var symbolName: String {
        switch self {
        case .capture:
            "mic.fill"
        case .today:
            "calendar"
        }
    }
}

enum CaptureRoute: Hashable {
    case parsing(String)
}

struct AppRootView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var events: [ScheduleEvent]

    @State private var selectedTab: AppTab = .capture
    @State private var capturePath: [CaptureRoute] = []
    @State private var todayPath: [String] = []
    @State private var speechCaptureService = SpeechCaptureService()
    @State private var systemSyncService = ScheduleSystemSyncService()
    @State private var isReconcilingCalendarChanges = false

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack(path: $capturePath) {
                CaptureView(speechCaptureService: speechCaptureService) { text in
                    capturePath.append(.parsing(text))
                }
                .navigationDestination(for: CaptureRoute.self) { route in
                    switch route {
                    case .parsing(let input):
                        AIParsingFlowView(
                            input: input,
                            systemSyncService: systemSyncService,
                            onCancel: {
                                capturePath.removeAll()
                            },
                            onSaved: {
                                capturePath.removeAll()
                                selectedTab = .today
                            }
                        )
                    }
                }
            }
            .tabItem {
                Label(AppTab.capture.title, systemImage: AppTab.capture.symbolName)
            }
            .tag(AppTab.capture)

            NavigationStack(path: $todayPath) {
                UpcomingView(systemSyncService: systemSyncService)
            }
            .tabItem {
                Label(AppTab.today.title, systemImage: AppTab.today.symbolName)
            }
            .tag(AppTab.today)
        }
        .tint(PlanTheme.calendarBlue)
        .preferredColorScheme(.dark)
        .task {
            await speechCaptureService.requestAuthorizationIfNeeded()
            await systemSyncService.requestRequiredPermissions()
            await reconcileExternalCalendarDeletions()
        }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in
            Task {
                await reconcileExternalCalendarDeletions()
            }
        }
    }

    private func reconcileExternalCalendarDeletions() async {
        guard !isReconcilingCalendarChanges else {
            return
        }
        isReconcilingCalendarChanges = true
        defer {
            isReconcilingCalendarChanges = false
        }

        try? await systemSyncService.reconcileExternalCalendarDeletions(
            events: events,
            modelContext: modelContext
        )
    }
}
