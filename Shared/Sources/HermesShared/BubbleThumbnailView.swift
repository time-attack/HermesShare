// BubbleThumbnailView.swift
// Plain graphic-only preview for MSMessageTemplateLayout.image. Apple already renders
// caption / subcaption / imageTitle / imageSubtitle around the bubble — the image slot
// must NOT repeat titles or stats or it overlaps and clutters at bubble scale.

import SwiftUI

public enum BubbleThumbnailKind: Sendable, Equatable {
    case flight, gauge, picker, dish, sky, journey, sparkline, scoreboard, ticket, media, poll, generic
}

public extension HermesLayout {
    var bubbleThumbnailKind: BubbleThumbnailKind {
        Self.findBubbleThumbnailKind(in: root)
    }

    private static func findBubbleThumbnailKind(in node: HermesNode) -> BubbleThumbnailKind {
        switch node {
        case .flightBoard: return .flight
        case .gaugeCluster: return .gauge
        case .seatChart, .optionPicker: return .picker
        case .platedDish: return .dish
        case .skyScene: return .sky
        case .journeyArc: return .journey
        case .sparkline: return .sparkline
        case .scoreBoard: return .scoreboard
        case .eventTicket: return .ticket
        case .mediaList: return .media
        case .photoCatalog: return .media
        case .collapsible: return .picker
        case .quickReplyRow: return .poll
        case .vstack(_, _, let children), .hstack(_, _, let children):
            for child in children {
                let kind = findBubbleThumbnailKind(in: child)
                if kind != .generic { return kind }
            }
        case .card(_, _, _, let child):
            let kind = findBubbleThumbnailKind(in: child)
            if kind != .generic { return kind }
        default:
            break
        }
        return .generic
    }
}

public struct BubbleThumbnailView: View {
    public let layout: HermesLayout

    public init(layout: HermesLayout) {
        self.layout = layout
    }

    private var accent: Color {
        Color(hermesHex: layout.accentColorHex) ?? .accentColor
    }

    private var kind: BubbleThumbnailKind { layout.bubbleThumbnailKind }

    public var body: some View {
        ZStack {
            Color(red: 19 / 255, green: 21 / 255, blue: 26 / 255)
            RadialGradient(
                colors: [accent.opacity(0.32), .clear],
                center: UnitPoint(x: 0.5, y: 0.42),
                startRadius: 8,
                endRadius: 150
            )
            graphic
        }
        .frame(width: 300, height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private var graphic: some View {
        switch kind {
        case .flight:
            FlightGraphic(accent: accent)
        case .gauge:
            GaugeGraphic(accent: accent)
        case .picker:
            PickerGraphic(accent: accent)
        case .dish:
            DishGraphic(accent: accent)
        case .sky:
            SkyGraphic(accent: accent)
        case .journey:
            JourneyGraphic(accent: accent)
        case .sparkline:
            SparklineGraphic(accent: accent)
        case .scoreboard:
            ScoreboardGraphic(accent: accent)
        case .ticket:
            TicketGraphic(accent: accent)
        case .media:
            MediaGraphic(accent: accent)
        case .poll:
            PollGraphic(accent: accent)
        case .generic:
            GenericGraphic(accent: accent)
        }
    }
}

// MARK: - Graphic primitives (text-free, one simple metaphor each)

private struct FlightGraphic: View {
    let accent: Color
    var body: some View {
        Canvas { ctx, size in
            let y = size.height * 0.46
            let x0 = size.width * 0.18
            let x1 = size.width * 0.82
            let progress: CGFloat = 0.62
            var base = Path()
            base.move(to: CGPoint(x: x0, y: y))
            base.addLine(to: CGPoint(x: x1, y: y))
            ctx.stroke(base, with: .color(.white.opacity(0.18)), lineWidth: 4)
            var lit = Path()
            lit.move(to: CGPoint(x: x0, y: y))
            lit.addLine(to: CGPoint(x: x0 + (x1 - x0) * progress, y: y))
            ctx.stroke(lit, with: .color(accent), lineWidth: 4)
            let px = x0 + (x1 - x0) * progress
            let dot = CGRect(x: px - 8, y: y - 8, width: 16, height: 16)
            ctx.fill(Path(ellipseIn: dot), with: .color(accent))
        }
        .frame(width: 220, height: 120)
    }
}

private struct GaugeGraphic: View {
    let accent: Color
    var body: some View {
        Canvas { ctx, size in
            let cx = size.width / 2
            let cy = size.height * 0.58
            let r: CGFloat = 52
            var track = Path()
            track.addArc(center: CGPoint(x: cx, y: cy), radius: r,
                         startAngle: .degrees(135), endAngle: .degrees(45), clockwise: true)
            ctx.stroke(track, with: .color(.white.opacity(0.14)), lineWidth: 12)
            var value = Path()
            value.addArc(center: CGPoint(x: cx, y: cy), radius: r,
                         startAngle: .degrees(135), endAngle: .degrees(135 + 270 * 0.82), clockwise: false)
            ctx.stroke(value, with: .color(accent), lineWidth: 12)
        }
        .frame(width: 160, height: 120)
    }
}

private struct PickerGraphic: View {
    let accent: Color
    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<5, id: \.self) { i in
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(i == 2 ? accent : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(i == 2 ? accent : Color.white.opacity(0.22), lineWidth: 3)
                    )
                    .frame(width: 36, height: 36)
            }
        }
    }
}

private struct DishGraphic: View {
    let accent: Color
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.2), lineWidth: 3)
                .frame(width: 88, height: 88)
            Ellipse()
                .fill(accent.opacity(0.55))
                .frame(width: 56, height: 34)
                .offset(y: 6)
        }
    }
}

private struct SkyGraphic: View {
    let accent: Color
    var body: some View {
        Circle()
            .fill(
                RadialGradient(colors: [accent, accent.opacity(0.35)], center: .center, startRadius: 0, endRadius: 44)
            )
            .frame(width: 72, height: 72)
    }
}

private struct JourneyGraphic: View {
    let accent: Color
    var body: some View {
        Canvas { ctx, size in
            var path = Path()
            path.move(to: CGPoint(x: size.width * 0.14, y: size.height * 0.68))
            path.addQuadCurve(to: CGPoint(x: size.width * 0.86, y: size.height * 0.32),
                              control: CGPoint(x: size.width * 0.5, y: size.height * 0.08))
            ctx.stroke(path, with: .color(.white.opacity(0.18)), style: StrokeStyle(lineWidth: 4, dash: [8, 6]))
            var lit = Path()
            lit.move(to: CGPoint(x: size.width * 0.14, y: size.height * 0.68))
            lit.addQuadCurve(to: CGPoint(x: size.width * 0.58, y: size.height * 0.48),
                             control: CGPoint(x: size.width * 0.32, y: size.height * 0.38))
            ctx.stroke(lit, with: .color(accent), lineWidth: 4)
            let dot = CGRect(x: size.width * 0.58 - 8, y: size.height * 0.48 - 8, width: 16, height: 16)
            ctx.fill(Path(ellipseIn: dot), with: .color(accent))
        }
        .frame(width: 220, height: 120)
    }
}

private struct SparklineGraphic: View {
    let accent: Color
    var body: some View {
        Canvas { ctx, size in
            let pts: [CGPoint] = [0.08, 0.22, 0.18, 0.42, 0.36, 0.28, 0.52, 0.62, 0.68, 0.48, 0.82, 0.72, 0.92, 0.58]
                .enumerated().map { i, y in
                    CGPoint(x: size.width * CGFloat(i) / 13, y: size.height * (1 - y))
                }
            var path = Path()
            path.move(to: pts[0])
            for p in pts.dropFirst() { path.addLine(to: p) }
            ctx.stroke(path, with: .color(accent), lineWidth: 3)
        }
        .frame(width: 200, height: 90)
    }
}

private struct ScoreboardGraphic: View {
    let accent: Color
    var body: some View {
        HStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .frame(width: 56, height: 44)
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(accent.opacity(0.35))
                .frame(width: 56, height: 44)
        }
    }
}

private struct TicketGraphic: View {
    let accent: Color
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(accent.opacity(0.7), lineWidth: 2)
                .frame(width: 120, height: 72)
            Rectangle()
                .fill(Color.white.opacity(0.15))
                .frame(width: 1, height: 72)
                .offset(x: -20)
        }
    }
}

private struct MediaGraphic: View {
    let accent: Color
    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { i in
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(i == 1 ? accent.opacity(0.45) : Color.white.opacity(0.1))
                    .frame(width: 40, height: 40)
            }
        }
    }
}

private struct PollGraphic: View {
    let accent: Color
    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { i in
                Capsule()
                    .fill(i == 1 ? accent : Color.white.opacity(0.12))
                    .frame(width: 52, height: 28)
            }
        }
    }
}

private struct GenericGraphic: View {
    let accent: Color
    var body: some View {
        // Plain fallback: accent glow from canvas only.
        Color.clear.frame(width: 1, height: 1)
    }
}
