//
//  AppRootView.swift
//  AIPlan
//
//  Created by Codex on 2026/7/13.
//

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
    @State private var selectedTab: AppTab = .capture
    @State private var capturePath: [CaptureRoute] = []
    @State private var todayPath: [String] = []
    @State private var speechCaptureService = SpeechCaptureService()

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
                UpcomingView()
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
        }
    }
}
