//
//  OfflineQueueView.swift
//  OceanCheck
//
//  View and manage queued offline actions.
//

import SwiftUI

struct OfflineQueueView: View {
    @ObservedObject var vm: KYCViewModel
    @ObservedObject var queue: OfflineQueue = .shared

    var body: some View {
        List {
            if queue.isProcessing {
                Section {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Syncing queued actions...").font(Typo.body).foregroundStyle(.secondary)
                    }
                }
            }

            if queue.pendingActions.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle").font(.system(size: 32)).foregroundStyle(.quaternary)
                        Text("Queue is empty").font(Typo.body).foregroundStyle(.secondary)
                        Text("Actions are queued automatically when you're offline.").font(Typo.meta).foregroundStyle(.quaternary).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
            } else {
                Section("\(queue.pendingActions.count) Pending") {
                    ForEach(queue.pendingActions) { action in
                        HStack(spacing: 12) {
                            Image(systemName: actionIcon(action.actionType))
                                .font(.system(size: 13)).foregroundStyle(.secondary)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(action.checkName).font(Typo.body).fontWeight(.medium)
                                Text(actionLabel(action.actionType)).font(Typo.meta).foregroundStyle(.secondary)
                                HStack(spacing: 6) {
                                    Text(action.statusText).font(.system(size: 10)).foregroundStyle(action.retryCount > 0 ? Color.review : Color.secondary.opacity(0.5))
                                    Text(action.createdAt.formatted(.relative(presentation: .named))).font(.system(size: 10)).foregroundStyle(.secondary.opacity(0.5))
                                }
                            }

                            Spacer()

                            if action.retryCount >= 3 {
                                Image(systemName: "exclamationmark.triangle").font(.system(size: 12)).foregroundStyle(Color.review)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                queue.removeAction(id: action.id)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    }
                }

                Section {
                    Button {
                        Task { await queue.processQueue(vm: vm) }
                    } label: {
                        HStack {
                            Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 13))
                            Text("Retry All Now").font(Typo.body)
                        }
                        .foregroundStyle(vm.isOnline ? .primary : .secondary)
                    }
                    .disabled(!vm.isOnline)

                    Button(role: .destructive) {
                        queue.clearAll()
                    } label: {
                        HStack {
                            Image(systemName: "trash").font(.system(size: 13))
                            Text("Clear Queue").font(Typo.body)
                        }
                        .foregroundStyle(Color.flagged)
                    }
                }
            }
        }
        .navigationTitle("Offline Queue")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func actionIcon(_ type: QueuedAction.ActionType) -> String {
        switch type {
        case .idScan: return "person.text.rectangle"
        case .amlScreening: return "shield.checkered"
        case .inviteSession: return "link"
        }
    }

    private func actionLabel(_ type: QueuedAction.ActionType) -> String {
        switch type {
        case .idScan: return "ID Verification"
        case .amlScreening: return "AML Screening"
        case .inviteSession: return "Invite Session"
        }
    }
}
