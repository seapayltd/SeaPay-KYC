//
//  MergeReviewSheet.swift
//  OceanCheck
//
//  Shows diff before merging pulled data. User confirms what to accept.
//

import SwiftUI

struct MergeReviewSheet: View {
    let diff: MergeDiff
    let vesselName: String
    var onAccept: (Bool, Bool, Bool) -> Void  // (vesselChanges, newChecks, updates)
    var onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var acceptVessel = true
    @State private var acceptNew = true
    @State private var acceptUpdates = true

    var body: some View {
        NavigationStack {
            List {
                // Summary
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Merge for \(vesselName)").font(Typo.body).fontWeight(.semibold)
                            Text("\(diff.totalChanges) change\(diff.totalChanges == 1 ? "" : "s") from remote").font(Typo.meta).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }

                // Vessel field changes
                if !diff.vesselChanges.isEmpty {
                    Section {
                        Toggle("Accept vessel changes", isOn: $acceptVessel).font(Typo.body).tint(.primary)
                        ForEach(diff.vesselChanges) { change in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(change.field).font(Typo.meta).foregroundStyle(.secondary)
                                HStack(spacing: 8) {
                                    Text(change.localValue).font(Typo.body).strikethrough().foregroundStyle(.secondary)
                                    Image(systemName: "arrow.right").font(.system(size: 10)).foregroundStyle(.secondary)
                                    Text(change.remoteValue).font(Typo.body).fontWeight(.medium)
                                }
                            }
                        }
                    } header: {
                        Label("Vessel Changes", systemImage: "ferry").foregroundStyle(Color.review)
                    }
                }

                // New crew/checks
                if !diff.newChecks.isEmpty {
                    Section {
                        Toggle("Accept new crew", isOn: $acceptNew).font(Typo.body).tint(.primary)
                        ForEach(diff.newChecks, id: \.id) { check in
                            HStack(spacing: 10) {
                                Image(systemName: "plus.circle.fill").foregroundStyle(Color.clear_).font(.system(size: 14))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(check.customerName).font(Typo.body)
                                    Text(check.entityType.rawValue).font(Typo.meta).foregroundStyle(.secondary)
                                }
                            }
                        }
                    } header: {
                        Label("\(diff.newChecks.count) New", systemImage: "person.badge.plus").foregroundStyle(Color.clear_)
                    }
                }

                // Updated checks
                if !diff.updatedChecks.isEmpty {
                    Section {
                        Toggle("Accept updates", isOn: $acceptUpdates).font(Typo.body).tint(.primary)
                        ForEach(diff.updatedChecks) { update in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(update.checkName).font(Typo.body).fontWeight(.medium)
                                ForEach(update.changes, id: \.self) { change in
                                    Text(change).font(Typo.meta).foregroundStyle(Color.review)
                                }
                            }
                        }
                    } header: {
                        Label("\(diff.updatedChecks.count) Updated", systemImage: "arrow.triangle.2.circlepath").foregroundStyle(Color.review)
                    }
                }

                // Removed (info only — not auto-deleted)
                if !diff.removedCheckIds.isEmpty {
                    Section {
                        Text("\(diff.removedCheckIds.count) crew member\(diff.removedCheckIds.count == 1 ? "" : "s") not present in remote data. Local copies will be kept.")
                            .font(Typo.meta).foregroundStyle(.secondary)
                    } header: {
                        Label("Not in Remote", systemImage: "minus.circle").foregroundStyle(Color.flagged)
                    }
                }
            }
            .navigationTitle("Review Merge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel(); dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Accept") {
                        onAccept(acceptVessel, acceptNew, acceptUpdates)
                        dismiss()
                    }.fontWeight(.semibold)
                }
            }
        }
    }
}
