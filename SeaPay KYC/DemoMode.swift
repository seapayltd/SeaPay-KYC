//
//  DemoMode.swift
//  OceanCheck
//
//  Sandbox mode with fake API responses for App Store review and sales demos.
//  No real API calls are made. Toggle from Settings.
//

import Foundation

enum DemoMode {

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "demoModeEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "demoModeEnabled") }
    }

    // MARK: - Sample Vessel

    static func sampleVessel() -> Vessel {
        var v = Vessel(name: "M/Y OCEANUS", imoNumber: "9876543", flagState: "Malta", portOfRegistry: "Valletta", vesselType: .megayachtCharter)
        v.officialNumber = "MLT-2024-0042"
        v.callSign = "9HA4567"
        v.certificateNumber = "CR/2024/0042"
        v.grossTonnage = "480"
        v.netTonnage = "144"
        v.lengthOverall = "42.5"
        v.registeredLength = "38.2"
        v.breadth = "8.4"
        v.depth = "4.2"
        v.yearBuilt = "2019"
        v.builder = "Benetti, Livorno"
        v.hullMaterial = "GRP"
        v.registeredOwner = "Oceanus Maritime Ltd"
        return v
    }

    // MARK: - Sample Crew

    static func sampleCrew(vesselId: String) -> [KYCCheck] {
        let names: [(String, CrewRank, KYCCheck.CheckStatus)] = [
            ("Marco Rossi", .captain, .passed),
            ("Elena Papadopoulos", .chiefOfficer, .passed),
            ("James Wilson", .chiefEngineer, .passed),
            ("Sofia Andersson", .chiefStewardess, .requiresReview),
            ("Carlos Martinez", .bosun, .passed),
            ("Yuki Tanaka", .cook, .pending),
        ]

        return names.map { name, rank, status in
            var check = KYCCheck(
                id: UUID().uuidString, customerId: "DEMO-\(name.prefix(4).uppercased())",
                customerName: name, agentId: "DEMO", agentName: "Demo Agent",
                checkType: .idVerification, status: status, entityType: .seafarer,
                createdAt: Date().addingTimeInterval(-Double.random(in: 86400...864000))
            )
            check.vesselId = vesselId
            check.crewRank = rank
            check.nationality = ["IT", "GR", "GB", "SE", "ES", "JP"][names.firstIndex(where: { $0.0 == name }) ?? 0]
            check.documentType = "Passport"
            check.documentNumber = "DEMO\(Int.random(in: 100000...999999))"
            check.expiryDate = "2028-\(String(format: "%02d", Int.random(in: 1...12)))-15"
            if status == .passed || status == .requiresReview {
                check.extractedName = name
                check.amlStatus = status == .passed ? "Approved" : "In Review"
                check.amlScore = status == .passed ? Int.random(in: 0...15) : Int.random(in: 60...85)
                check.amlHitCount = status == .passed ? 0 : 1
                check.completedAt = Date().addingTimeInterval(-Double.random(in: 3600...86400))
            }
            check.documents = [
                CrewDocument(type: .passport, documentNumber: check.documentNumber,
                    expiryDate: Calendar.current.date(byAdding: .year, value: 2, to: Date())),
                CrewDocument(type: .seamansBook, documentNumber: "SB-\(Int.random(in: 1000...9999))",
                    expiryDate: Calendar.current.date(byAdding: .month, value: 18, to: Date())),
                CrewDocument(type: .stcwBST,
                    expiryDate: Calendar.current.date(byAdding: .year, value: 3, to: Date())),
            ]
            return check
        }
    }

    // MARK: - Fake API Responses (decoded from JSON since models use let + Codable)

    static var fakeIDResult: IDResult? {
        let json = """
        {"status":"Approved","full_name":"Demo Subject","document_type":"Passport",
         "document_number":"DEMO123456","date_of_birth":"1990-06-15",
         "expiration_date":"2030-06-14","nationality":"Malta","issuing_state":"MLT",
         "issuing_state_name":"Malta","gender":"M","date_of_issue":"2020-06-15",
         "place_of_birth":"Valletta"}
        """
        return try? JSONDecoder().decode(IDResult.self, from: json.data(using: .utf8)!)
    }

    static var fakeAMLResult: AMLResult? {
        let json = """
        {"status":"Approved","score":5,"total_hits":0}
        """
        return try? JSONDecoder().decode(AMLResult.self, from: json.data(using: .utf8)!)
    }

    // MARK: - Populate Demo Data

    static func populateDemoData(vm: KYCViewModel) {
        let vessel = sampleVessel()
        vm.vessels.append(vessel)
        vm.saveVessels()

        let crew = sampleCrew(vesselId: vessel.id)
        vm.checks.append(contentsOf: crew)
        vm.saveChecks()
    }

    static func clearDemoData(vm: KYCViewModel) {
        vm.checks.removeAll { $0.agentId == "DEMO" || $0.agentName == "Demo Agent" }
        vm.vessels.removeAll { $0.imoNumber == "9876543" }
        vm.saveChecks()
        vm.saveVessels()
    }
}
