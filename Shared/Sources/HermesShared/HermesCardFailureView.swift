// HermesCardFailureView.swift
// The honest error state shown when a specific tapped card cannot be resolved after
// retries. This is a permanent product surface that ships in Release — NOT a debug-only
// view — because the alternative (silently substituting a cached/most-recent card, or a
// friendly dead-end with no evidence) is exactly what made the wrong-card bug survive
// multiple fix attempts: there was never any visible signal of what actually happened.
//
// It deliberately looks like a diagnostic panel, not a polished empty-state graphic. The
// lines it renders come verbatim from HermesCardDiagnostics.reportLines, the same lines
// the extension writes to the on-device debug log, so screen and log always agree.

import SwiftUI
import UIKit

/// Identifies WHICH build is running, on screen and in the log. Exists because the
/// "silent fallback still happening" report class has twice turned out to be a stale
/// build on-device (the IPA tunnel dies when a session exits, so a fix that was built
/// and hosted can silently never arrive). Any screenshot or log pull now says which
/// build produced it. Bump the date/tag whenever behavior changes.
public enum HermesBuildInfo {
    public static let stamp = "2026-07-07.9 catalog-layout-fix"
}

public struct HermesCardFailureView: View {

    private let diagnostics: HermesCardDiagnostics
    private let urlRetriesExhausted: Int
    private let cachedSessionKeys: [String]

    public init(diagnostics: HermesCardDiagnostics, urlRetriesExhausted: Int, cachedSessionKeys: [String]) {
        self.diagnostics = diagnostics
        self.urlRetriesExhausted = urlRetriesExhausted
        self.cachedSessionKeys = cachedSessionKeys
    }

    /// Exposed so tests can assert the on-screen content matches the logged content.
    /// The build stamp is part of the report: a stale installed build is a documented
    /// cause of "the fix didn't work" reports, and this makes it visible in both places.
    public var reportLines: [String] {
        diagnostics.reportLines(urlRetriesExhausted: urlRetriesExhausted,
                                cachedSessionKeys: cachedSessionKeys)
            + ["build: \(HermesBuildInfo.stamp)"]
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Couldn't load this card")
                            .font(.headline)
                        Text("HermesShare refused to guess — here's exactly what happened.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(reportLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                Text("Close this card and tap its bubble again — Messages usually re-delivers the contents on a fresh open. This same report is in the HermesShare debug log.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
    }
}
