//
//  ScheduleAssistantClient.swift
//  AIPlan
//
//  Created by Codex on 2026/7/13.
//

import Foundation

struct AssistantRequest: Codable {
    var text: String
    var now: Date
    var timezone: String
    var locale: String
    var context: ScheduleQueryContext
}

struct ScheduleQueryContext: Codable {
    var events: [QueryContextEvent]
}

struct QueryContextEvent: Codable, Hashable {
    var id: String
    var kind: EventKind
    var title: String
    var taskDate: Date
    var scheduledAt: Date?
    var endAt: Date?
    var notes: String
    var timezoneIdentifier: String
    var isCompleted: Bool
}

enum AssistantResponseKind: String, Codable, Hashable {
    case intent
    case query
}

struct AssistantResponse: Codable, Hashable {
    var type: AssistantResponseKind
    var intent: IntentResponse?
    var query: ScheduleQueryResponse?
    var routeReason: String?
    var routeConfidence: Double
}

enum ScheduleQueryStatus: String, Codable, Hashable {
    case answer
    case clarify
    case unsupported
}

struct ScheduleQueryResponse: Codable, Hashable {
    var status: ScheduleQueryStatus
    var title: String
    var answer: String?
    var suggestions: [String]
    var referencedEventIDs: [String]
    var rangeStart: Date?
    var rangeEnd: Date?
    var question: String?
    var message: String?
    var confidence: Double
    var ambiguities: [String]
}

struct APIErrorResponse: Codable, Hashable {
    var error: APIErrorBody
}

struct APIErrorBody: Codable, Hashable {
    var code: String
    var message: String
}

struct ScheduleAssistantClient {
    var resolve: (_ text: String, _ contextEvents: [QueryContextEvent]) async throws -> AssistantResponse

    static func live(
        baseURL: URL = URL(string: "https://planasstanttest-dbmejgslku.cn-hangzhou.fcapp.run")!,
        session: URLSession = .shared
    ) -> ScheduleAssistantClient {
        ScheduleAssistantClient { text, contextEvents in
            let endpoint = baseURL.appending(path: "/v1/schedule/assistant")
            let requestBody = AssistantRequest(
                text: text,
                now: Date(),
                timezone: TimeZone.current.identifier,
                locale: "zh_CN",
                context: ScheduleQueryContext(events: contextEvents)
            )

            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 15
            request.httpBody = try PlanJSONDateCoder.encoder.encode(requestBody)

            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ScheduleAssistantError.invalidResponse
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                if let apiError = try? PlanJSONDateCoder.decoder.decode(APIErrorResponse.self, from: data) {
                    throw ScheduleAssistantError.api(apiError.error.message)
                }
                throw ScheduleAssistantError.httpStatus(httpResponse.statusCode)
            }

            return try PlanJSONDateCoder.decoder.decode(AssistantResponse.self, from: data)
        }
    }
}

enum ScheduleAssistantError: LocalizedError {
    case invalidResponse
    case httpStatus(Int)
    case api(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "后端响应无效"
        case .httpStatus(let statusCode):
            "后端请求失败，状态码 \(statusCode)"
        case .api(let message):
            message
        }
    }
}

enum PlanJSONDateCoder {
    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(string(from: date))
        }
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO 8601 date-time: \(value)"
            )
        }
        return decoder
    }

    static func string(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
        return formatter.string(from: date)
    }

    static func date(from value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}
