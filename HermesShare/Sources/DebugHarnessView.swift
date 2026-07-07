// DebugHarnessView.swift
// Paste-or-pick a HermesLayout JSON and see it rendered full-screen via the shared renderer.

import SwiftUI
import HermesShared

struct DebugHarnessView: View {
    @State private var selection: Int
    @State private var jsonText: String = ""
    @State private var parseError: String?
    @State private var showingEditor = false
    @ObservedObject private var lastLink = LastDeepLink.shared

    init() {
        _selection = State(initialValue: Self.launchSampleIndex() ?? 0)
    }

    private var samples: [(name: String, layout: HermesLayout)] { HermesSampleLayouts.all }

    /// `-ScreenshotSample "Courier Journey"` — used by `scripts/capture_readme_screenshots.sh`.
    private static func launchSampleIndex() -> Int? {
        let args = ProcessInfo.processInfo.arguments
        guard let flag = args.firstIndex(of: "-ScreenshotSample"), flag + 1 < args.count else { return nil }
        let name = args[flag + 1]
        return HermesSampleLayouts.all.firstIndex { $0.name == name }
    }

    /// The layout currently being rendered — either the picked sample or the edited JSON.
    private var currentLayout: HermesLayout? {
        if showingEditor {
            return try? HermesLayout.decode(fromJSONString: jsonText)
        }
        return samples.indices.contains(selection) ? samples[selection].layout : nil
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                picker
                Divider()
                renderArea
            }
            .navigationTitle("HermesShare · Debug")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        loadJSONForCurrentSelection()
                        showingEditor.toggle()
                    } label: {
                        Image(systemName: showingEditor ? "eye" : "curlybraces")
                    }
                    .accessibilityLabel(showingEditor ? "Preview" : "Edit JSON")
                }
            }
            .sheet(item: Binding(
                get: { lastLink.url.map { IdentifiedURL(url: $0) } },
                set: { _ in lastLink.url = nil }
            )) { wrapped in
                deepLinkSheet(wrapped.url)
            }
        }
    }

    private var picker: some View {
        Picker("Sample", selection: $selection) {
            ForEach(Array(samples.enumerated()), id: \.offset) { index, sample in
                Text(sample.name).tag(index)
            }
        }
        .pickerStyle(.segmented)
        .padding()
        .disabled(showingEditor)
    }

    @ViewBuilder private var renderArea: some View {
        if showingEditor {
            editor
        } else if let layout = currentLayout {
            ScrollView {
                // Capture fired actions in-app rather than round-tripping a hermesshare:// URL
                // through the OS — on a shared simulator another app may claim the scheme, and
                // in production the extension handles actions itself anyway (reply insert).
                HermesLayoutRenderer(layout: layout, presentation: .expanded) { action in
                    LastDeepLink.shared.url = URL(string: action.deepLinkURL)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
        } else {
            ContentUnavailableView("No layout", systemImage: "questionmark.square.dashed")
        }
    }

    private var editor: some View {
        VStack(spacing: 0) {
            if let err = parseError {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color.red.opacity(0.1))
            }
            TextEditor(text: $jsonText)
                .font(.system(.footnote, design: .monospaced))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onChange(of: jsonText) { _, newValue in
                    validate(newValue)
                }
            if let layout = currentLayout {
                Divider()
                ScrollView {
                    HermesLayoutRenderer(layout: layout, presentation: .expanded)
                        .padding()
                }
                .frame(maxHeight: 320)
                .background(Color(.systemGroupedBackground))
            }
        }
    }

    private func deepLinkSheet(_ url: URL) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.up.right.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
            Text("Action fired")
                .font(.title2.bold())
            Text(url.absoluteString)
                .font(.callout.monospaced())
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Text("In production this deep link routes back to Hermes/Photon (see README → NEXT STEPS).")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Done") { lastLink.url = nil }
                .buttonStyle(.borderedProminent)
        }
        .padding(28)
        .presentationDetents([.medium])
    }

    private func loadJSONForCurrentSelection() {
        guard !showingEditor, let layout = currentLayout,
              let data = try? layout.encoded(pretty: true),
              let str = String(data: data, encoding: .utf8) else { return }
        jsonText = str
        parseError = nil
    }

    private func validate(_ text: String) {
        do {
            _ = try HermesLayout.decode(fromJSONString: text)
            parseError = nil
        } catch {
            parseError = "Invalid HermesLayout JSON: \(error.localizedDescription)"
        }
    }
}

private struct IdentifiedURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

#Preview("Package Tracking") {
    ScrollView {
        HermesLayoutRenderer(layout: HermesSampleLayouts.packageTracking)
            .padding()
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("Stat Dashboard") {
    ScrollView {
        HermesLayoutRenderer(layout: HermesSampleLayouts.statDashboard)
            .padding()
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("Map Preview") {
    ScrollView {
        HermesLayoutRenderer(layout: HermesSampleLayouts.mapPreview)
            .padding()
    }
    .background(Color(.systemGroupedBackground))
}
