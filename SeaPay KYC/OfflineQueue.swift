//
//  OfflineQueue.swift
//  OceanCheck
//
//  Queues verification requests when offline, auto-retries when connectivity returns.
//  Persisted to disk so queued work survives app restarts.
//

import Foundation
import Network
import os.log

private let queueLogger = Logger(subsystem: "com.seapay.kyc", category: "OfflineQueue")

// MARK: - Queued Action

struct QueuedAction: Codable, Identifiable {
    let id: String
    let createdAt: Date
    let actionType: ActionType
    let checkId: String
    let checkName: String
    var retryCount: Int
    var lastError: String?

    // Payload — stored so we can replay the action
    let frontImageFilename: String?
    let backImageFilename: String?
    let amlName: String?
    let amlNationality: String?
    let amlDocNumber: String?
    let monitoring: Bool

    enum ActionType: String, Codable {
        case idScan
        case amlScreening
        case inviteSession
    }

    var isStale: Bool {
        // Actions older than 24 hours are stale
        Date().timeIntervalSince(createdAt) > 86400
    }

    var statusText: String {
        if retryCount == 0 { return "Queued" }
        if let err = lastError { return "Retry \(retryCount) — \(err)" }
        return "Retrying (\(retryCount))"
    }
}

// MARK: - Offline Queue Manager

@MainActor
class OfflineQueue: ObservableObject {
    static let shared = OfflineQueue()

    @Published var pendingActions: [QueuedAction] = []
    @Published var isProcessing = false

    private let maxRetries = 3
    private var connectivityObserver: NWPathMonitor?
    private let queueFile: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        queueFile = docs.appendingPathComponent("offline_queue.json")
        loadQueue()
    }

    // MARK: - Queue Management

    var isEmpty: Bool { pendingActions.isEmpty }
    var count: Int { pendingActions.count }

    func enqueueIDScan(checkId: String, checkName: String, frontImageFilename: String, backImageFilename: String?) {
        let action = QueuedAction(
            id: UUID().uuidString, createdAt: Date(), actionType: .idScan,
            checkId: checkId, checkName: checkName, retryCount: 0,
            frontImageFilename: frontImageFilename, backImageFilename: backImageFilename,
            amlName: nil, amlNationality: nil, amlDocNumber: nil, monitoring: false
        )
        pendingActions.append(action)
        saveQueue()
        #if DEBUG
        queueLogger.debug("Queued ID scan for \(checkName)")
        #endif
    }

    func enqueueAMLScreening(checkId: String, checkName: String, name: String, nationality: String?, docNumber: String?, monitoring: Bool) {
        let action = QueuedAction(
            id: UUID().uuidString, createdAt: Date(), actionType: .amlScreening,
            checkId: checkId, checkName: checkName, retryCount: 0,
            frontImageFilename: nil, backImageFilename: nil,
            amlName: name, amlNationality: nationality, amlDocNumber: docNumber, monitoring: monitoring
        )
        pendingActions.append(action)
        saveQueue()
        #if DEBUG
        queueLogger.debug("Queued AML screening for \(checkName)")
        #endif
    }

    func enqueueInviteSession(checkId: String, checkName: String) {
        let action = QueuedAction(
            id: UUID().uuidString, createdAt: Date(), actionType: .inviteSession,
            checkId: checkId, checkName: checkName, retryCount: 0,
            frontImageFilename: nil, backImageFilename: nil,
            amlName: nil, amlNationality: nil, amlDocNumber: nil, monitoring: false
        )
        pendingActions.append(action)
        saveQueue()
    }

    func removeAction(id: String) {
        pendingActions.removeAll { $0.id == id }
        saveQueue()
    }

    func clearStale() {
        pendingActions.removeAll { $0.isStale }
        saveQueue()
    }

    func clearAll() {
        pendingActions.removeAll()
        saveQueue()
    }

    // MARK: - Process Queue

    /// Attempt to process all queued actions. Called when connectivity returns.
    func processQueue(vm: KYCViewModel) async {
        guard !isProcessing else { return }
        guard !pendingActions.isEmpty else { return }

        isProcessing = true
        defer { isProcessing = false }

        #if DEBUG
        queueLogger.debug("Processing \(self.pendingActions.count) queued actions")
        #endif

        var completed: [String] = []

        for i in pendingActions.indices {
            guard !pendingActions[i].isStale else {
                completed.append(pendingActions[i].id)
                continue
            }
            guard pendingActions[i].retryCount < maxRetries else {
                continue // Leave in queue for manual retry
            }

            pendingActions[i].retryCount += 1

            do {
                switch pendingActions[i].actionType {
                case .idScan:
                    try await processIDScan(pendingActions[i], vm: vm)
                    completed.append(pendingActions[i].id)

                case .amlScreening:
                    try await processAMLScreening(pendingActions[i], vm: vm)
                    completed.append(pendingActions[i].id)

                case .inviteSession:
                    try await processInviteSession(pendingActions[i], vm: vm)
                    completed.append(pendingActions[i].id)
                }
            } catch {
                pendingActions[i].lastError = error.localizedDescription.prefix(80).description
                #if DEBUG
                queueLogger.error("Queue action failed: \(error.localizedDescription)")
                #endif
            }
        }

        pendingActions.removeAll { completed.contains($0.id) }
        saveQueue()

        if !completed.isEmpty {
            Haptics.success()
        }
    }

    // MARK: - Action Processors

    private func processIDScan(_ action: QueuedAction, vm: KYCViewModel) async throws {
        guard let frontFile = action.frontImageFilename,
              let frontData = vm.loadDocumentImage(filename: frontFile) else { return }
        let backData = action.backImageFilename.flatMap { vm.loadDocumentImage(filename: $0) }
        _ = try await vm.runIDScan(checkId: action.checkId, frontImage: frontData, backImage: backData)
    }

    private func processAMLScreening(_ action: QueuedAction, vm: KYCViewModel) async throws {
        guard let name = action.amlName else { return }
        _ = try await vm.runAMLScreening(checkId: action.checkId, monitoring: action.monitoring)
    }

    private func processInviteSession(_ action: QueuedAction, vm: KYCViewModel) async throws {
        _ = try await vm.createInviteSession(checkId: action.checkId)
    }

    // MARK: - Persistence

    private func loadQueue() {
        guard let data = try? Data(contentsOf: queueFile) else { return }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        pendingActions = (try? decoder.decode([QueuedAction].self, from: data)) ?? []
    }

    private func saveQueue() {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = .prettyPrinted
        try? encoder.encode(pendingActions).write(to: queueFile)
    }

    // MARK: - Connectivity Observer

    func startObserving(vm: KYCViewModel) {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self, weak vm] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor [weak self, weak vm] in
                guard let self, let vm else { return }
                await self.processQueue(vm: vm)
            }
        }
        monitor.start(queue: DispatchQueue(label: "offline.queue.monitor"))
        connectivityObserver = monitor
    }

    func stopObserving() {
        connectivityObserver?.cancel()
        connectivityObserver = nil
    }
}
