// DebugConformanceView.swift
// WraithVPN
//
// Founder-only debug conformance runner. Lists named test scenarios
// (cells) and shows per-cell pass/fail status with execution time.
// "Run all" runs sequentially with 2s gaps for easy visual inspection.

import SwiftUI

struct DebugConformanceView: View {

    @ObservedObject private var runner = DebugConformanceRunner.shared
    @State private var showRunAllConfirmation = false

    var body: some View {
        ZStack {
            Color.kfBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header with "Run All" button
                HStack {
                    Text("Conformance Cells")
                        .font(.headline)

                    Spacer()

                    Button {
                        showRunAllConfirmation = true
                    } label: {
                        Label("Run All", systemImage: "play.fill")
                            .font(.caption.weight(.medium))
                    }
                }
                .padding()
                .background(Color.kfSurface)

                // Cell list
                if DebugConformanceCell.allCases.isEmpty {
                    Spacer()
                    Text("No cells defined.")
                        .foregroundColor(.secondary)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(DebugConformanceCell.allCases, id: \.rawValue) { cell in
                                cellRow(cell)
                            }
                        }
                        .padding()
                    }
                }
            }
        }
        .navigationTitle("Debug Conformance")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Run all cells?", isPresented: $showRunAllConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Run", role: .none) {
                Task {
                    await runner.runAll()
                }
            }
        } message: {
            Text("This will run \(DebugConformanceCell.allCases.count) cells sequentially.")
        }
    }

    // MARK: - Subviews

    private func cellRow(_ cell: DebugConformanceCell) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(cell.displayName)
                        .font(.subheadline.weight(.semibold))

                    if let result = runner.lastResults[cell.rawValue] {
                        HStack(spacing: 6) {
                            if result.pass {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("PASS")
                                    .font(.caption.weight(.medium))
                                    .foregroundColor(.green)
                            } else {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                                Text("FAIL")
                                    .font(.caption.weight(.medium))
                                    .foregroundColor(.red)
                            }
                            Text(result.reason)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                    } else {
                        Text("Not run")
                            .font(.caption)
                            .foregroundColor(.tertiary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    if runner.isRunning == cell.rawValue {
                        ProgressView()
                            .scaleEffect(0.8, anchor: .center)
                    } else {
                        Button {
                            Task {
                                await runner.run(cell)
                            }
                        } label: {
                            Image(systemName: "play.fill")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .disabled(runner.isRunning != nil)
                    }

                    if let result = runner.lastResults[cell.rawValue] {
                        Text("\(result.durationMs)ms")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Show details if present
            if let result = runner.lastResults[cell.rawValue], !result.details.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Divider()
                        .padding(.vertical, 4)

                    ForEach(Array(result.details.sorted { $0.key < $1.key }), id: \.key) { key, value in
                        HStack {
                            Text(key)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(value)
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(Color.kfSurface)
        .cornerRadius(8)
    }
}

#Preview {
    NavigationStack {
        DebugConformanceView()
    }
}
