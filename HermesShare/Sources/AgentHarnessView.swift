// AgentHarnessView.swift
// Live dashboard for a running Hermes agent: connection/pairing, status header,
// current task + action, todo checklist, and the latest preview screenshot.
// Mirrors everything into a Live Activity via AgentLiveActivityController.

import HermesShared
import SwiftUI

struct AgentHarnessView: View {
    @StateObject private var client = AgentHarnessClient()
    @StateObject private var liveActivity = AgentLiveActivityController()

    @State private var pairingCode = ""
    @State private var showPairSheet = false

    var body: some View {
        NavigationStack {
            Group {
                if client.isPaired {
                    dashboard
                } else {
                    pairingIntro
                }
            }
            .navigationTitle("Hermes Agent")
            .toolbar {
                if client.isPaired {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button(role: .destructive) {
                                stopMonitoring()
                                client.unpair()
                            } label: {
                                Label("Unpair", systemImage: "personalhotspot.slash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showPairSheet) { pairSheet }
        .onAppear(perform: wireCallbacks)
    }

    private func wireCallbacks() {
        client.onStateChange = { state in
            liveActivity.apply(state: state)
        }
        client.onSessionEnd = {
            liveActivity.endSession(finalState: client.state)
        }

        // `-HarnessAutoPair <serverURL> <code>` — headless pairing for automated tests.
        let args = ProcessInfo.processInfo.arguments
        if let flag = args.firstIndex(of: "-HarnessAutoPair"), flag + 2 < args.count, !client.isPaired {
            client.serverURLString = args[flag + 1]
            Task { await client.pair(code: args[flag + 2]) }
            return
        }

        if client.isPaired {
            client.connect()
        }
    }

    private func stopMonitoring() {
        liveActivity.endCurrentActivity()
        client.disconnect()
    }

    // MARK: - Pairing

    private var pairingIntro: some View {
        VStack(spacing: 20) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 52))
                .foregroundStyle(.tint)
            Text("Pair with your agent")
                .font(.title2.bold())
            Text("Run `hermes-harness serve` on your Mac, then enter the server address and the 6-digit code it prints.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                showPairSheet = true
            } label: {
                Label("Pair", systemImage: "link")
                    .frame(maxWidth: 220)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var pairSheet: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    TextField("http://192.168.x.x:8642", text: $client.serverURLString)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                Section("Pairing code") {
                    TextField("6-digit code", text: $pairingCode)
                        .keyboardType(.numberPad)
                        .font(.title3.monospaced())
                }
                if case .failed(let message) = client.phase {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
                Section {
                    Button {
                        Task {
                            await client.pair(code: pairingCode)
                            if client.isPaired {
                                showPairSheet = false
                            }
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if client.phase == .connecting {
                                ProgressView()
                            } else {
                                Text("Pair & Connect").bold()
                            }
                            Spacer()
                        }
                    }
                    .disabled(pairingCode.count < 4 || client.phase == .connecting)
                }
            }
            .navigationTitle("Pair")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showPairSheet = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Dashboard

    @ViewBuilder private var dashboard: some View {
        if let state = client.state {
            ScrollView {
                VStack(spacing: 14) {
                    statusHeader(state)
                    if let action = state.currentAction, !action.isEmpty {
                        actionRow(action, status: state.status)
                    }
                    if let image = client.screenshot {
                        screenshotCard(image)
                    }
                    todoCard(state)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
        } else {
            VStack(spacing: 14) {
                connectionPill
                ContentUnavailableView(
                    "Waiting for the agent",
                    systemImage: "hourglass",
                    description: Text("Paired and listening — state will appear as soon as the agent reports in.")
                )
            }
        }
    }

    private var connectionPill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(client.phase == .connected ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(client.phase.label)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: Capsule())
    }

    private func statusHeader(_ state: AgentSessionState) -> some View {
        let accent = Color(hexString: state.status.accentHex) ?? .blue
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(state.status.displayName, systemImage: state.status.systemImage)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(accent.opacity(0.18), in: Capsule())
                    .foregroundStyle(accent)
                Spacer()
                connectionPill
            }
            Text(state.title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(state.headline)
                .font(.title3.bold())
            HStack(spacing: 10) {
                ProgressView(value: state.progress)
                    .tint(accent)
                Text("\(state.completedCount)/\(state.totalCount)")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func actionRow(_ action: String, status: AgentRunStatus) -> some View {
        let accent = Color(hexString: status.accentHex) ?? .blue
        return HStack(spacing: 10) {
            Image(systemName: "terminal.fill")
                .foregroundStyle(accent)
            Text(action)
                .font(.footnote.monospaced())
                .lineLimit(3)
            Spacer(minLength: 0)
            if status == .working {
                ProgressView().controlSize(.small)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func screenshotCard(_ image: UIImage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Live preview", systemImage: "eye.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func todoCard(_ state: AgentSessionState) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Todos", systemImage: "checklist")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if state.todos.isEmpty {
                Text("No todos reported yet.")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
            ForEach(state.todos) { todo in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    todoGlyph(todo.status)
                    Text(todo.content)
                        .font(.subheadline)
                        .strikethrough(todo.status == .cancelled)
                        .foregroundStyle(todoTextColor(todo.status))
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder private func todoGlyph(_ status: AgentTodoItem.Status) -> some View {
        switch status {
        case .completed:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .inProgress:
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .foregroundStyle(.blue)
                .symbolEffect(.rotate, options: .repeating)
        case .pending:
            Image(systemName: "circle").foregroundStyle(.secondary)
        case .cancelled:
            Image(systemName: "xmark.circle").foregroundStyle(.tertiary)
        }
    }

    private func todoTextColor(_ status: AgentTodoItem.Status) -> Color {
        switch status {
        case .completed: return .secondary
        case .cancelled: return Color(.tertiaryLabel)
        default: return .primary
        }
    }
}

extension Color {
    init?(hexString: String) {
        var hex = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let value = UInt64(hex, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
