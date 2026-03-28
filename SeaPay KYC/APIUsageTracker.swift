//
//  APIUsageTracker.swift
//  OceanCheck
//
//  Tracks API call counts by type and day for cost awareness.
//  Persisted in UserDefaults (lightweight, no encryption needed).
//

import Foundation

struct APIDailyUsage: Codable, Identifiable {
    let date: String // yyyy-MM-dd
    var idScans: Int
    var amlScreenings: Int
    var poaChecks: Int
    var claudeOCR: Int
    var sessions: Int

    var id: String { date }

    var totalCalls: Int { idScans + amlScreenings + poaChecks + claudeOCR + sessions }

    /// Rough cost estimate based on typical API pricing
    var estimatedCost: Double {
        Double(idScans) * 0.50 +       // ID verification ~$0.50
        Double(amlScreenings) * 0.30 +  // AML screening ~$0.30
        Double(poaChecks) * 0.40 +      // PoA ~$0.40
        Double(claudeOCR) * 0.02 +      // Claude Vision ~$0.02
        Double(sessions) * 0.10          // Session creation ~$0.10
    }
}

enum APIUsageTracker {

    private static let storageKey = "apiUsageHistory"

    private static var dateFmt: DateFormatter {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }

    private static var today: String { dateFmt.string(from: Date()) }

    // MARK: - Track

    enum CallType { case idScan, amlScreening, poaCheck, claudeOCR, session }

    static func track(_ type: CallType) {
        guard !DemoMode.isEnabled else { return } // Don't track demo calls
        var history = loadHistory()
        let todayKey = today
        var entry = history.first(where: { $0.date == todayKey }) ?? APIDailyUsage(date: todayKey, idScans: 0, amlScreenings: 0, poaChecks: 0, claudeOCR: 0, sessions: 0)

        switch type {
        case .idScan: entry.idScans += 1
        case .amlScreening: entry.amlScreenings += 1
        case .poaCheck: entry.poaChecks += 1
        case .claudeOCR: entry.claudeOCR += 1
        case .session: entry.sessions += 1
        }

        if let i = history.firstIndex(where: { $0.date == todayKey }) {
            history[i] = entry
        } else {
            history.insert(entry, at: 0)
        }

        // Keep last 90 days
        let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date()
        let cutoffStr = dateFmt.string(from: cutoff)
        history.removeAll { $0.date < cutoffStr }

        saveHistory(history)
    }

    // MARK: - Query

    static func todayUsage() -> APIDailyUsage {
        loadHistory().first(where: { $0.date == today }) ?? APIDailyUsage(date: today, idScans: 0, amlScreenings: 0, poaChecks: 0, claudeOCR: 0, sessions: 0)
    }

    static func last30Days() -> [APIDailyUsage] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let cutoffStr = dateFmt.string(from: cutoff)
        return loadHistory().filter { $0.date >= cutoffStr }.sorted { $0.date > $1.date }
    }

    static func totalLast30Days() -> (calls: Int, cost: Double) {
        let days = last30Days()
        return (days.reduce(0) { $0 + $1.totalCalls }, days.reduce(0.0) { $0 + $1.estimatedCost })
    }

    // MARK: - Persistence

    private static func loadHistory() -> [APIDailyUsage] {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return [] }
        return (try? JSONDecoder().decode([APIDailyUsage].self, from: data)) ?? []
    }

    private static func saveHistory(_ history: [APIDailyUsage]) {
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
