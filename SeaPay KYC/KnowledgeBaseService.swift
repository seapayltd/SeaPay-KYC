//
//  KnowledgeBaseService.swift
//  OceanCheck
//
//  Hybrid knowledge base: JSON rules (bundled + synced) with Claude fallback.
//  Replaces hardcoded FlagStateRequirements as the primary source.
//

import Foundation
import os.log

private let kbLogger = Logger(subsystem: "com.seapay.kyc", category: "KnowledgeBase")

@MainActor
final class KnowledgeBaseService {
    static let shared = KnowledgeBaseService()

    private var db: MaritimeRulesDB
    private let customRulesURL: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        customRulesURL = docs.appendingPathComponent("custom_rules.json")

        // Load bundled JSON
        if let url = Bundle.main.url(forResource: "maritime_requirements", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let loaded = try? JSONDecoder().decode(MaritimeRulesDB.self, from: data) {
            db = loaded
            kbLogger.info("Loaded \(loaded.crewRules.count) crew rules, \(loaded.vesselRules.count) vessel rules (v\(loaded.version))")
        } else {
            db = MaritimeRulesDB(version: 0, lastUpdated: "", crewRules: [], vesselRules: [], customRules: [])
            kbLogger.warning("Failed to load bundled maritime_requirements.json")
        }

        // Overlay custom rules
        if let data = try? Data(contentsOf: customRulesURL),
           let custom = try? JSONDecoder().decode([RequirementRule].self, from: data) {
            db.customRules = custom
            kbLogger.info("Loaded \(custom.count) custom rules")
        }
    }

    // MARK: - Crew Requirements

    func crewRequirements(flag: String, vesselType: VesselType?, gt: Double?, loa: Double?, rank: CrewRank?) -> (docs: [MaritimeDocType], sources: [String])? {
        let rankCat = rank?.category.rawValue
        let vtStr = vesselType?.rawValue

        let allRules = db.crewRules + db.customRules.filter { $0.flag == flag || $0.flag == "*" }
        let matching = allRules.filter { $0.matches(flag: flag, vesselType: vtStr, gt: gt, loa: loa, rankCat: rankCat) }

        guard !matching.isEmpty else { return nil }

        var docSet = Set<String>()
        var sources: [String] = []
        for rule in matching {
            docSet.formUnion(rule.required)
            if let s = rule.source, !s.isEmpty, !sources.contains(s) { sources.append(s) }
        }

        let docs = docSet.compactMap { raw in MaritimeDocType.allCases.first(where: { $0.rawValue == raw }) }
        return (docs.sorted(by: { $0.displayName < $1.displayName }), sources)
    }

    // MARK: - Vessel Requirements

    func vesselRequirements(flag: String, vesselType: VesselType?, gt: Double?, loa: Double?, rl: Double?, yearBuilt: Int?) -> (docs: [VesselDocType], sources: [String])? {
        let vtStr = vesselType?.rawValue
        let effectiveLOA = loa ?? rl

        let allRules = db.vesselRules + db.customRules
        let matching = allRules.filter { $0.matches(flag: flag, vesselType: vtStr, gt: gt, loa: effectiveLOA, yearBuilt: yearBuilt) }

        guard !matching.isEmpty else { return nil }

        var docSet = Set<String>()
        var sources: [String] = []
        for rule in matching {
            docSet.formUnion(rule.required)
            if let s = rule.source, !s.isEmpty, !sources.contains(s) { sources.append(s) }
        }

        let docs = docSet.compactMap { raw in VesselDocType.allCases.first(where: { $0.rawValue == raw }) }
        return (docs.sorted(by: { $0.displayName < $1.displayName }), sources)
    }

    // MARK: - Flag Coverage

    func hasRulesForFlag(_ flag: String) -> Bool {
        let f = flag.lowercased()
        return db.crewRules.contains(where: { $0.flag.lowercased() == f }) ||
               db.vesselRules.contains(where: { $0.flag.lowercased() == f }) ||
               db.customRules.contains(where: { $0.flag.lowercased() == f })
    }

    // MARK: - Custom Rules

    func addCustomRule(_ rule: RequirementRule) {
        db.customRules.append(rule)
        saveCustomRules()
    }

    func removeCustomRule(id: String) {
        db.customRules.removeAll { $0.id == id }
        saveCustomRules()
    }

    private func saveCustomRules() {
        if let data = try? JSONEncoder().encode(db.customRules) {
            try? data.write(to: customRulesURL)
        }
    }

    // MARK: - Backend Sync

    func updateFromBackend(data: Data) {
        guard let updated = try? JSONDecoder().decode(MaritimeRulesDB.self, from: data),
              updated.version > db.version else { return }
        let custom = db.customRules // Preserve custom rules
        db = updated
        db.customRules = custom
        kbLogger.info("Updated knowledge base to v\(updated.version)")
    }

    var currentVersion: Int { db.version }
}
