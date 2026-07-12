//
//  ContentView.swift
//  AIPlan
//
//  Created by chenanqi on 2026/7/13.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        AppRootView()
    }
}

#Preview {
    ContentView()
        .modelContainer(for: ScheduleEvent.self, inMemory: true)
}
