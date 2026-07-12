//
//  AIPlanApp.swift
//  AIPlan
//
//  Created by chenanqi on 2026/7/13.
//

import SwiftUI
import SwiftData

@main
struct AIPlanApp: App {
    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
        .modelContainer(for: ScheduleEvent.self)
    }
}
