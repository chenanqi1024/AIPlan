//
//  PlanTheme.swift
//  AIPlan
//
//  Created by Codex on 2026/7/13.
//

import SwiftUI

enum PlanTheme {
    static let surfaceApp = Color(hex: 0x000000)
    static let surfaceCard = Color(hex: 0x1C1C1E)
    static let surfaceCardStrong = Color(hex: 0x2C2C2E)
    static let borderSubtle = Color(hex: 0x3A3A3C)
    static let textPrimary = Color.white
    static let textSecondary = Color(hex: 0xEBEBF5, opacity: 0.60)
    static let textMuted = Color(hex: 0xEBEBF5, opacity: 0.32)
    static let calendarBlue = Color(hex: 0x0A84FF)
    static let alarmOrange = Color(hex: 0xFF9F0A)
    static let successGreen = Color(hex: 0x30D158)
    static let alertRed = Color(hex: 0xFF453A)

    static let pagePadding: CGFloat = 20
    static let sectionSpacing: CGFloat = 18
    static let cardRadius: CGFloat = 18
    static let controlRadius: CGFloat = 14
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        let red = Double((hex >> 16) & 0xFF) / 255.0
        let green = Double((hex >> 8) & 0xFF) / 255.0
        let blue = Double(hex & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue, opacity: opacity)
    }
}

extension View {
    func planCard(
        fill: Color = PlanTheme.surfaceCard.opacity(0.88),
        stroke: Color = PlanTheme.borderSubtle,
        cornerRadius: CGFloat = PlanTheme.cardRadius
    ) -> some View {
        background(fill, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(stroke, lineWidth: 1)
            )
    }

    func planIconBox(
        fill: Color = PlanTheme.calendarBlue.opacity(0.14),
        cornerRadius: CGFloat = 10
    ) -> some View {
        frame(width: 34, height: 34)
            .background(fill, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

enum PlanDateFormatter {
    static func friendlyDate(_ date: Date = Date()) -> String {
        formatted(date, pattern: "M月d日 EEEE")
    }

    static func fullDate(_ date: Date) -> String {
        formatted(date, pattern: "yyyy年M月d日")
    }

    static func weekday(_ date: Date) -> String {
        formatted(date, pattern: "EEEE")
    }

    static func shortTime(_ date: Date?) -> String {
        guard let date else {
            return "全天"
        }
        return formatted(date, pattern: "HH:mm")
    }

    static func formatted(_ date: Date, pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}

struct MetricItem: Identifiable {
    let id = UUID()
    var title: String
    var value: Int
    var symbolName: String
    var color: Color
}
