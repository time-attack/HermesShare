// HermesFormState.swift
// Shared, per-card state for `fieldId` inputs — the Adaptive Cards `Input.*` model.
//
// A control that carries a `fieldId` stops being fire-and-forget: it writes its selection here
// instead of composing a message, and renders NO confirm button of its own. The card's single
// submit bar reads this for its live summary, its button label, and the `HermesSubmission`
// payload it attaches to the one reply it inserts. Controls without a `fieldId` are untouched.

import SwiftUI

@MainActor
public final class HermesFormState: ObservableObject {

    /// fieldId -> selected option id (RAW ids, never labels — labels are for humans only).
    /// ponytail: [String: String], single-select only. That covers seat / option / chip
    /// pickers, which is every input the schema has. Multi-select or typed values (numbers,
    /// dates) would need [String: [HermesValue]] and a value enum — add it when a node needs it.
    @Published public private(set) var values: [String: String] = [:]

    /// True when the layout contains ANY `fieldId` input, even before anything is picked. This
    /// is what tells a card with no layout-level `actions` that it still needs a submit button,
    /// so a form can never be stranded with no way to send.
    public let hasInputs: Bool

    public init(seededFrom layout: HermesLayout) {
        let inputs = Self.inputs(in: layout.root)
        self.hasInputs = !inputs.isEmpty
        for input in inputs {
            if let seeded = input.seeded { values[input.fieldId] = seeded }
        }
    }

    public func set(_ fieldId: String, _ value: String) {
        values[fieldId] = value
    }

    public var isEmpty: Bool { values.isEmpty }

    /// Short human summary of the current selections for the submit bar, e.g. "23D · 1 bag".
    /// Walks the layout in TREE order (never dictionary order) or the button label jitters
    /// between renders.
    public func summary(for layout: HermesLayout) -> String {
        Self.inputs(in: layout.root)
            .compactMap { input in
                guard let value = values[input.fieldId] else { return nil }
                return input.labels[value] ?? value
            }
            .joined(separator: " · ")
    }

    // MARK: - Tree walk (one walk, used for both seeding and the summary)

    private struct Input {
        let fieldId: String
        let seeded: String?
        /// option id -> human label. Empty means "the id IS the label" (seat "23D").
        let labels: [String: String]
    }

    private static func inputs(in node: HermesNode) -> [Input] {
        switch node {
        case let .vstack(_, _, children), let .hstack(_, _, children):
            return children.flatMap(inputs(in:))
        case let .card(_, _, _, child):
            return inputs(in: child)
        case let .collapsible(_, _, _, _, _, _, child):
            return inputs(in: child)
        case let .optionPicker(options, selectedId, _, _, fieldId):
            guard let fieldId else { return [] }
            return [Input(fieldId: fieldId, seeded: selectedId,
                          labels: labelMap(options.map { ($0.id, $0.label) }))]
        case let .seatChart(rows, selectedSeatId, fieldId):
            guard let fieldId else { return [] }
            let seeded = selectedSeatId ?? rows.flatMap(\.seats).first { $0.state == .selected }?.id
            return [Input(fieldId: fieldId, seeded: seeded, labels: [:])]
        case let .quickReplyRow(options, fieldId):
            guard let fieldId else { return [] }
            return [Input(fieldId: fieldId, seeded: nil,
                          labels: labelMap(options.map { ($0.id, $0.label) }))]
        default:
            // ponytail: only the four container cases above recurse. A future node type that
            // nests children must be added here or its inputs are invisible to the form — the
            // compiler cannot catch that omission.
            return []
        }
    }

    private static func labelMap(_ pairs: [(String, String)]) -> [String: String] {
        Dictionary(pairs, uniquingKeysWith: { first, _ in first })
    }
}
