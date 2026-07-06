// HermesSceneViewsV5.swift
// The v5 scene expansion: drawn ADA centerpieces for the card genres v4 left uncovered
// (Step 0 genres 6–10 in HermesLayout.swift). Same doctrine as HermesSceneViews.swift —
// everything is SwiftUI primitives / Canvas geometry, no assets, deterministic given a seed,
// and each centerpiece exposes one combined VoiceOver label stating its takeaway.
//
//   • HermesJourneyArcView  — dispatch-panel route arc, vehicle at real progress
//   • HermesSkySceneView    — procedural sky (sun/moon/stars/clouds/rain/snow/storm/fog)
//   • HermesEventTicketView — drawn ticket stub: notches, perforation, seeded barcode
//   • HermesSparklineView   — trading-terminal trend tile with lit sparkline
//   • HermesScoreBoardView  — arena scoreboard reusing the split-flap digit tiles

import SwiftUI
import UIKit

// MARK: - Shared instrument-panel chrome

/// The near-black panel treatment every dark scene shares (same family as the flight board):
/// panel base + state-hue radial glow, continuous corners, hairline stroke.
extension View {
    func hermesScenePanel(glow: Color, cornerRadius: CGFloat = 20) -> some View {
        self
            .background(
                ZStack {
                    Color(red: 0.07, green: 0.075, blue: 0.09)
                    RadialGradient(colors: [glow.opacity(0.14), .clear],
                                   center: .topLeading, startRadius: 4, endRadius: 260)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
    }
}

/// Small-caps micro label + value column, shared by the panel footers (same look as the
/// flight board's DEPARTS/GATE/ARRIVES stats).
private struct HermesPanelStat: View {
    let label: String
    let value: String
    var alignment: HorizontalAlignment = .leading
    /// Equal-width columns by default; set false where columns must hug their content
    /// (e.g. the ticket's narrow main panel, where equal thirds truncate real dates).
    var flexible: Bool = true

    var body: some View {
        let column = VStack(alignment: alignment, spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .kerning(1.2)
                .foregroundStyle(.white.opacity(0.55))
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                // 0.55 floor: a smaller-but-complete value beats an ellipsized one at the
                // 300pt compact bubble width.
                .minimumScaleFactor(0.55)
        }
        if flexible {
            column.frame(maxWidth: .infinity,
                         alignment: alignment == .leading ? .leading : (alignment == .trailing ? .trailing : .center))
        } else {
            column
        }
    }
}

/// Glowing status pill (dot + small-caps label), shared across the dark panels.
private struct HermesGlowPill: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
                .shadow(color: color.opacity(0.9), radius: 3)
            Text(text.uppercased())
                .font(.system(size: 10, weight: .bold))
                .kerning(0.8)
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(0.16)))
    }
}

// MARK: - Journey arc (delivery / ride / transit dispatch panel)

/// A route arc between two labeled endpoints with the vehicle at its REAL progress — the
/// journey itself is the scene, not a progress bar with a truck icon next to it.
struct HermesJourneyArcView: View {
    let arc: HermesJourneyArc
    @Environment(\.hermesAccent) private var accent

    private var stateColor: Color { Color(hermesHex: arc.statusColorHex) ?? accent }
    private var clampedProgress: CGFloat? {
        guard let p = arc.progress, p.isFinite else { return nil }
        return CGFloat(max(0, min(1, p)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if let carrier = arc.carrier {
                    Text(carrier)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .kerning(1.2)
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer()
                if !arc.status.isEmpty {
                    HermesGlowPill(text: arc.status, color: stateColor)
                }
            }

            arcScene
                .frame(height: 108)

            HStack(alignment: .top) {
                Text(arc.originLabel)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(arc.destinationLabel)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white.opacity(0.5))

            if arc.etaText != nil || arc.detail != nil {
                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                HStack(alignment: .top, spacing: 8) {
                    if let detail = arc.detail {
                        HermesPanelStat(label: "LATEST", value: detail, alignment: .leading)
                    }
                    if let eta = arc.etaText {
                        HermesPanelStat(label: "ETA", value: eta,
                                        alignment: arc.detail == nil ? .leading : .trailing)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hermesScenePanel(glow: stateColor)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11yLabel)
    }

    private var a11yLabel: String {
        var s = "Journey from \(arc.originLabel) to \(arc.destinationLabel)."
        if !arc.status.isEmpty { s += " \(arc.status)." }
        if let d = arc.detail { s += " \(d)." }
        if let e = arc.etaText { s += " Estimated arrival \(e)." }
        return s
    }

    /// A misspelled SF Symbol name would render nothing while the masking disc still draws —
    /// a hole punched in the route. Fall back to the package glyph for unknown names.
    private var vehicleSymbol: String {
        guard let name = arc.vehicleSystemName, UIImage(systemName: name) != nil else {
            return "shippingbox.fill"
        }
        return name
    }

    // Quadratic Bézier route: dashed full path, lit traveled trail, vehicle at progress.
    private var arcScene: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let baseY = h - 10
            let apexY: CGFloat = 10
            let p0 = CGPoint(x: 12, y: baseY)
            let p1 = CGPoint(x: w - 12, y: baseY)
            let control = CGPoint(x: w / 2, y: 2 * apexY - baseY)

            let route = Path { path in
                path.move(to: p0)
                path.addQuadCurve(to: p1, control: control)
            }

            let bezierPoint: (CGFloat) -> CGPoint = { t in
                let u = 1 - t
                return CGPoint(
                    x: u * u * p0.x + 2 * u * t * control.x + t * t * p1.x,
                    y: u * u * p0.y + 2 * u * t * control.y + t * t * p1.y
                )
            }

            ZStack {
                route.stroke(Color.white.opacity(0.22),
                             style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [3, 5]))

                if let p = clampedProgress {
                    route.trimmedPath(from: 0, to: max(0.001, p))
                        .stroke(stateColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .shadow(color: stateColor.opacity(0.8), radius: 4)
                }

                Circle().fill(Color.white.opacity(0.45)).frame(width: 6, height: 6)
                    .position(p0)
                Circle().fill(stateColor).frame(width: 7, height: 7)
                    .shadow(color: stateColor.opacity(0.9), radius: 3)
                    .position(p1)

                if let p = clampedProgress {
                    let vehiclePos = bezierPoint(p)
                    Circle()
                        .fill(Color(red: 0.07, green: 0.075, blue: 0.09))
                        .frame(width: 26, height: 26)
                        .position(vehiclePos)
                    Image(systemName: vehicleSymbol)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .shadow(color: stateColor.opacity(0.9), radius: 4)
                        .position(vehiclePos)
                }
            }
        }
    }
}

// MARK: - Sky scene (procedural weather hero)

/// The sky IS the stage: condition-keyed gradient plus drawn sun/moon/stars/clouds/
/// precipitation, deterministic given `seed`, with the temperature as the hero numeral.
struct HermesSkySceneView: View {
    let sky: HermesSkyScene

    var body: some View {
        ZStack(alignment: .bottom) {
            Canvas { ctx, size in draw(ctx: &ctx, size: size) }
                .accessibilityHidden(true)

            // One bottom row: temp/location/caption leading, hi-lo trailing on the caption's
            // baseline — a shared flow, so long captions wrap instead of running under the
            // hi-lo readout.
            HStack(alignment: .lastTextBaseline, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    if let temp = sky.tempText {
                        Text(temp)
                            .font(.system(size: 52, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    if let location = sky.location {
                        Text(location.uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .kerning(1.4)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    if let caption = sky.caption {
                        Text(caption)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }
                Spacer(minLength: 0)
                if let hiLo = sky.hiLoText {
                    Text(hiLo)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .shadow(color: .black.opacity(0.45), radius: 5, y: 1)
            .padding(16)
        }
        .frame(height: 200)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11yLabel)
    }

    private var a11yLabel: String {
        var s = "Weather: \(sky.caption ?? sky.condition.rawValue)"
        if sky.isNight { s += ", night" }
        if let t = sky.tempText { s += ", \(t)" }
        if let loc = sky.location { s += ", in \(loc)" }
        return s + "."
    }

    private var gradientColors: (top: Color, bottom: Color) {
        switch (sky.condition, sky.isNight) {
        case (.clear, false):  return (Color(red: 0.16, green: 0.42, blue: 0.72), Color(red: 0.55, green: 0.78, blue: 0.94))
        case (.clear, true):   return (Color(red: 0.028, green: 0.043, blue: 0.13), Color(red: 0.10, green: 0.16, blue: 0.31))
        case (.clouds, false): return (Color(red: 0.30, green: 0.43, blue: 0.56), Color(red: 0.62, green: 0.71, blue: 0.79))
        case (.clouds, true):  return (Color(red: 0.06, green: 0.09, blue: 0.17), Color(red: 0.16, green: 0.22, blue: 0.32))
        case (.rain, false):   return (Color(red: 0.27, green: 0.35, blue: 0.42), Color(red: 0.49, green: 0.56, blue: 0.64))
        case (.rain, true):    return (Color(red: 0.055, green: 0.086, blue: 0.13), Color(red: 0.17, green: 0.23, blue: 0.31))
        case (.snow, false):   return (Color(red: 0.48, green: 0.55, blue: 0.63), Color(red: 0.77, green: 0.82, blue: 0.87))
        case (.snow, true):    return (Color(red: 0.075, green: 0.11, blue: 0.16), Color(red: 0.23, green: 0.29, blue: 0.37))
        case (.storm, false):  return (Color(red: 0.12, green: 0.13, blue: 0.18), Color(red: 0.24, green: 0.27, blue: 0.35))
        case (.storm, true):   return (Color(red: 0.06, green: 0.065, blue: 0.10), Color(red: 0.15, green: 0.17, blue: 0.24))
        case (.fog, false):    return (Color(red: 0.43, green: 0.48, blue: 0.53), Color(red: 0.65, green: 0.68, blue: 0.72))
        case (.fog, true):     return (Color(red: 0.10, green: 0.12, blue: 0.15), Color(red: 0.25, green: 0.28, blue: 0.32))
        }
    }

    private func draw(ctx: inout GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height
        let colors = gradientColors

        ctx.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .linearGradient(
                Gradient(colors: [colors.top, colors.bottom]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: h))
        )

        var state: UInt64 = UInt64(truncatingIfNeeded: sky.seed ?? 11) &+ 1
        func rnd() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double((state >> 33) % 1000) / 1000
        }

        switch (sky.condition, sky.isNight) {
        case (.clear, false):
            drawSun(&ctx, at: CGPoint(x: w * 0.74, y: h * 0.28))
        case (.clear, true):
            drawStars(&ctx, w: w, h: h, rnd: rnd)
            drawMoon(&ctx, at: CGPoint(x: w * 0.74, y: h * 0.26), rnd: rnd)
        case (.clouds, let night):
            if night { drawStars(&ctx, w: w, h: h, rnd: rnd, dim: true) }
            drawCloudBank(&ctx, w: w, h: h, rnd: rnd, alpha: night ? 0.16 : 0.65)
        case (.rain, let night):
            drawCloudBank(&ctx, w: w, h: h, rnd: rnd, alpha: night ? 0.14 : 0.45)
            drawRain(&ctx, w: w, h: h, rnd: rnd)
        case (.snow, let night):
            drawCloudBank(&ctx, w: w, h: h, rnd: rnd, alpha: night ? 0.14 : 0.5)
            drawSnow(&ctx, w: w, h: h, rnd: rnd)
        case (.storm, _):
            drawCloudBank(&ctx, w: w, h: h, rnd: rnd, alpha: 0.12, dark: true)
            drawLightning(&ctx, at: CGPoint(x: w * 0.62, y: h * 0.34), h: h)
        case (.fog, _):
            drawFog(&ctx, w: w, h: h)
        }

        // Legibility scrim under the overlay text — day palettes bottom out near-white
        // (snow day measured 1.6:1 against white text without it). Night skies get a
        // lighter touch so the scene keeps its depth.
        let scrim = sky.isNight ? 0.24 : 0.5
        ctx.fill(
            Path(CGRect(x: 0, y: h * 0.45, width: w, height: h * 0.55)),
            with: .linearGradient(
                Gradient(colors: [.clear, .black.opacity(scrim)]),
                startPoint: CGPoint(x: 0, y: h * 0.45),
                endPoint: CGPoint(x: 0, y: h))
        )
    }

    private func drawSun(_ ctx: inout GraphicsContext, at center: CGPoint) {
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 16))
            layer.fill(Path(ellipseIn: CGRect(x: center.x - 34, y: center.y - 34, width: 68, height: 68)),
                       with: .color(Color(red: 1.0, green: 0.88, blue: 0.55).opacity(0.55)))
        }
        ctx.fill(Path(ellipseIn: CGRect(x: center.x - 17, y: center.y - 17, width: 34, height: 34)),
                 with: .radialGradient(
                    Gradient(colors: [Color(red: 1.0, green: 0.95, blue: 0.78),
                                      Color(red: 1.0, green: 0.79, blue: 0.30)]),
                    center: center, startRadius: 2, endRadius: 20))
    }

    /// A full moon with seeded maria — a crescent needs an occluding disc, and every carve
    /// color reads as "dark ball pasted over glow" against the halo (confirmed by design
    /// review). A cratered full moon is honest geometry with no such artifact.
    private func drawMoon(_ ctx: inout GraphicsContext, at center: CGPoint, rnd: () -> Double) {
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 10))
            layer.fill(Path(ellipseIn: CGRect(x: center.x - 22, y: center.y - 22, width: 44, height: 44)),
                       with: .color(.white.opacity(0.25)))
        }
        ctx.fill(Path(ellipseIn: CGRect(x: center.x - 15, y: center.y - 15, width: 30, height: 30)),
                 with: .radialGradient(
                    Gradient(colors: [Color(red: 0.97, green: 0.96, blue: 0.90),
                                      Color(red: 0.87, green: 0.86, blue: 0.78)]),
                    center: CGPoint(x: center.x - 5, y: center.y - 6),
                    startRadius: 2, endRadius: 18))
        let mare = Color(red: 0.72, green: 0.71, blue: 0.63).opacity(0.6)
        for _ in 0..<4 {
            let ang = rnd() * 2 * .pi
            let dist = rnd() * 8.5
            let mx = center.x + cos(ang) * dist
            let my = center.y + sin(ang) * dist
            let mr = 1.6 + rnd() * 2.6
            ctx.fill(Path(ellipseIn: CGRect(x: mx - mr, y: my - mr, width: mr * 2, height: mr * 2)),
                     with: .color(mare))
        }
    }

    private func drawStars(_ ctx: inout GraphicsContext, w: CGFloat, h: CGFloat,
                           rnd: () -> Double, dim: Bool = false) {
        for i in 0..<64 {
            let x = rnd() * w
            let y = rnd() * h * 0.72
            let r = 0.5 + rnd() * 1.2
            let alpha = (0.3 + rnd() * 0.6) * (dim ? 0.4 : 1.0)
            let dot = Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
            if i % 9 == 0 && !dim {
                ctx.drawLayer { layer in
                    layer.addFilter(.blur(radius: 2))
                    layer.fill(dot, with: .color(.white.opacity(alpha)))
                }
            }
            ctx.fill(dot, with: .color(.white.opacity(alpha)))
        }
    }

    private func drawCloudBank(_ ctx: inout GraphicsContext, w: CGFloat, h: CGFloat,
                               rnd: () -> Double, alpha: Double, dark: Bool = false) {
        let tint: Color = dark ? Color(red: 0.08, green: 0.09, blue: 0.12) : .white
        for i in 0..<3 {
            let cx = w * (0.2 + 0.3 * Double(i)) + (rnd() - 0.5) * 30
            let cy = h * (0.24 + rnd() * 0.14)
            let scale = 0.8 + rnd() * 0.5
            ctx.drawLayer { layer in
                layer.addFilter(.blur(radius: 7))
                let puffs: [(Double, Double, Double)] = [
                    (-0.5, 0.05, 0.55), (-0.18, -0.16, 0.62), (0.16, -0.08, 0.58),
                    (0.46, 0.06, 0.5), (0.0, 0.14, 0.72)
                ]
                for (dx, dy, s) in puffs {
                    let pw = 78 * scale * s * 2, ph = 44 * scale * s * 2
                    layer.fill(
                        Path(ellipseIn: CGRect(x: cx + dx * 90 * scale - pw / 2,
                                               y: cy + dy * 60 * scale - ph / 2,
                                               width: pw, height: ph)),
                        with: .color(tint.opacity(alpha)))
                }
            }
        }
    }

    private func drawRain(_ ctx: inout GraphicsContext, w: CGFloat, h: CGFloat, rnd: () -> Double) {
        for _ in 0..<44 {
            let x = rnd() * w
            let y = h * 0.34 + rnd() * h * 0.6
            var streak = Path()
            streak.move(to: CGPoint(x: x, y: y))
            streak.addLine(to: CGPoint(x: x - 3, y: y + 11))
            ctx.stroke(streak, with: .color(.white.opacity(0.28)),
                       style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
        }
    }

    private func drawSnow(_ ctx: inout GraphicsContext, w: CGFloat, h: CGFloat, rnd: () -> Double) {
        for i in 0..<46 {
            let x = rnd() * w
            let y = h * 0.3 + rnd() * h * 0.66
            let r = 1.0 + rnd() * 1.6
            let dot = Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
            if i % 5 == 0 {
                ctx.drawLayer { layer in
                    layer.addFilter(.blur(radius: 1.5))
                    layer.fill(dot, with: .color(.white.opacity(0.85)))
                }
            } else {
                ctx.fill(dot, with: .color(.white.opacity(0.75)))
            }
        }
    }

    private func drawLightning(_ ctx: inout GraphicsContext, at start: CGPoint, h: CGFloat) {
        var bolt = Path()
        bolt.move(to: start)
        bolt.addLine(to: CGPoint(x: start.x - 10, y: start.y + h * 0.16))
        bolt.addLine(to: CGPoint(x: start.x - 1, y: start.y + h * 0.16))
        bolt.addLine(to: CGPoint(x: start.x - 13, y: start.y + h * 0.38))
        let style = StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 5))
            layer.stroke(bolt, with: .color(Color(red: 1.0, green: 0.85, blue: 0.4).opacity(0.9)), style: style)
        }
        ctx.stroke(bolt, with: .color(Color(red: 1.0, green: 0.92, blue: 0.65)), style: style)
    }

    private func drawFog(_ ctx: inout GraphicsContext, w: CGFloat, h: CGFloat) {
        for i in 0..<4 {
            let y = h * (0.32 + 0.16 * Double(i))
            ctx.drawLayer { layer in
                layer.addFilter(.blur(radius: 8))
                layer.fill(
                    Path(roundedRect: CGRect(x: -20, y: y, width: w + 40, height: 11), cornerRadius: 6),
                    with: .color(.white.opacity(0.20)))
            }
        }
    }
}

// MARK: - Event ticket (drawn keepsake stub)

/// The classic notched ticket silhouette. `clockwise: true` on the notch arcs makes them cut
/// INTO the shape (SwiftUI's flipped coordinate space inverts the flag's visual meaning).
/// The tear line is anchored a FIXED distance from the trailing edge so it always lands on
/// the stub boundary — a proportional notch only lined up at one specific card width.
struct HermesTicketShape: Shape {
    var stubWidth: CGFloat = 104
    var notchRadius: CGFloat = 9
    var cornerRadius: CGFloat = 18

    func path(in rect: CGRect) -> Path {
        let nx = max(rect.minX + cornerRadius + notchRadius, rect.maxX - stubWidth)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + cornerRadius, y: rect.minY))
        p.addLine(to: CGPoint(x: nx - notchRadius, y: rect.minY))
        p.addArc(center: CGPoint(x: nx, y: rect.minY), radius: notchRadius,
                 startAngle: .degrees(180), endAngle: .degrees(0), clockwise: true)
        p.addLine(to: CGPoint(x: rect.maxX - cornerRadius, y: rect.minY))
        p.addArc(center: CGPoint(x: rect.maxX - cornerRadius, y: rect.minY + cornerRadius),
                 radius: cornerRadius, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cornerRadius))
        p.addArc(center: CGPoint(x: rect.maxX - cornerRadius, y: rect.maxY - cornerRadius),
                 radius: cornerRadius, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: nx + notchRadius, y: rect.maxY))
        p.addArc(center: CGPoint(x: nx, y: rect.maxY), radius: notchRadius,
                 startAngle: .degrees(0), endAngle: .degrees(180), clockwise: true)
        p.addLine(to: CGPoint(x: rect.minX + cornerRadius, y: rect.maxY))
        p.addArc(center: CGPoint(x: rect.minX + cornerRadius, y: rect.maxY - cornerRadius),
                 radius: cornerRadius, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cornerRadius))
        p.addArc(center: CGPoint(x: rect.minX + cornerRadius, y: rect.minY + cornerRadius),
                 radius: cornerRadius, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.closeSubpath()
        return p
    }
}

struct HermesEventTicketView: View {
    let ticket: HermesEventTicket
    @Environment(\.hermesAccent) private var accent

    private var tint: Color { Color(hermesHex: ticket.accentColorHex) ?? accent }
    /// Stub frame (96) + trailing padding (8) — the shape's tear line anchors to this.
    private let stubWidth: CGFloat = 104

    var body: some View {
        HStack(spacing: 0) {
            mainPanel
                .frame(maxWidth: .infinity, alignment: .leading)
            stub
        }
        .frame(minHeight: 150)
        .background(
            ZStack {
                Color(red: 0.07, green: 0.075, blue: 0.09)
                RadialGradient(colors: [tint.opacity(0.20), .clear],
                               center: .topLeading, startRadius: 4, endRadius: 320)
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(LinearGradient(colors: [tint, tint.opacity(0.55)],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(width: 5)
                    Spacer()
                }
            }
        )
        .clipShape(HermesTicketShape(stubWidth: stubWidth))
        .overlay(
            HermesTicketShape(stubWidth: stubWidth)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .overlay(perforation)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11yLabel)
    }

    private var a11yLabel: String {
        var s = "Ticket: \(ticket.title)"
        if let v = ticket.venue { s += " at \(v)" }
        if let d = ticket.dateText { s += ", \(d)" }
        if let t = ticket.timeText { s += ", \(t)" }
        if let seat = ticket.seatText { s += ", \(seat)" }
        return s + "."
    }

    private var mainPanel: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let kicker = ticket.kicker {
                Text(kicker.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .kerning(1.6)
                    .foregroundStyle(tint)
            }
            Text(ticket.title)
                .font(.system(size: 21, weight: .bold, design: .serif))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
            if let venue = ticket.venue {
                Text(venue)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
            }
            Spacer(minLength: 10)
            // Two rows, not three columns — the main panel is ~240pt wide and real dates/
            // seats truncate when forced into equal thirds.
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 22) {
                    if let date = ticket.dateText { HermesPanelStat(label: "DATE", value: date, flexible: false) }
                    if let time = ticket.timeText { HermesPanelStat(label: "TIME", value: time, flexible: false) }
                }
                if let seat = ticket.seatText { HermesPanelStat(label: "SEAT", value: seat, flexible: false) }
            }
        }
        .padding(.leading, 21)
        .padding(.trailing, 12)
        .padding(.vertical, 16)
    }

    // Seeded barcode + code — the part you'd tear off at the door.
    private var stub: some View {
        var state: UInt64 = UInt64(truncatingIfNeeded: ticket.seed ?? 5) &+ 1
        func rnd() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double((state >> 33) % 1000) / 1000
        }
        let widths: [CGFloat] = (0..<20).map { _ in CGFloat(1.0 + rnd() * 2.6) }

        return VStack(spacing: 8) {
            Spacer(minLength: 12)
            HStack(alignment: .center, spacing: 2) {
                ForEach(Array(widths.enumerated()), id: \.offset) { i, barWidth in
                    Rectangle()
                        .fill(Color.white.opacity(i % 4 == 0 ? 0.9 : 0.7))
                        .frame(width: barWidth, height: 46)
                }
            }
            if let code = ticket.code {
                Text(code)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .kerning(1.5)
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 12)
        }
        .frame(width: 96)
        .padding(.trailing, 8)
    }

    private var perforation: some View {
        GeometryReader { geo in
            let x = max(27, geo.size.width - stubWidth)
            Path { path in
                path.move(to: CGPoint(x: x, y: 12))
                path.addLine(to: CGPoint(x: x, y: geo.size.height - 12))
            }
            .stroke(Color.white.opacity(0.22),
                    style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
        }
    }
}

// MARK: - Sparkline (trading-terminal trend tile)

struct HermesSparklineView: View {
    let spark: HermesSparkline
    @Environment(\.hermesAccent) private var accent

    private var stateColor: Color {
        if let c = Color(hermesHex: spark.colorHex) { return c }
        switch spark.trend {
        case .up:   return Color(red: 0.19, green: 0.82, blue: 0.35)
        case .down: return Color(red: 1.0, green: 0.27, blue: 0.23)
        case .flat: return Color(white: 0.62)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(spark.label.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .kerning(1.3)
                        .foregroundStyle(.white.opacity(0.55))
                    Text(spark.valueText)
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.95))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                Spacer()
                if let delta = spark.deltaText {
                    HermesGlowPill(text: delta, color: stateColor)
                }
            }

            chart
                .frame(height: 62)

            if let caption = spark.caption {
                Text(caption.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .kerning(1.2)
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hermesScenePanel(glow: stateColor)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11yLabel)
    }

    // The takeaway must survive without color: name the trend direction explicitly.
    private var a11yLabel: String {
        let direction: String
        switch spark.trend {
        case .up:   direction = "rising"
        case .down: direction = "falling"
        case .flat: direction = "flat"
        }
        var s = "\(spark.label): \(spark.valueText), \(direction)"
        if let delta = spark.deltaText { s += ", \(delta)" }
        if let caption = spark.caption { s += ", \(caption)" }
        return s + "."
    }

    private var chart: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let values = spark.points.filter(\.isFinite)

            ZStack {
                ForEach(1..<4) { i in
                    Path { p in
                        let y = h * CGFloat(i) / 4
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: w, y: y))
                    }
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
                }

                if values.count >= 2 {
                    let lo = values.min() ?? 0
                    let hi = values.max() ?? 1
                    let range = hi - lo
                    // A flat series (or a range that overflowed to non-finite) draws
                    // mid-chart — pinning "no movement" to the bottom edge read as a crash
                    // to zero, and inconsistently with the <2-points dashed midline.
                    let isFlat = !(range > 0) || !range.isFinite
                    let pad = h * 0.12
                    let pts: [CGPoint] = values.enumerated().map { i, v in
                        CGPoint(
                            x: w * CGFloat(i) / CGFloat(values.count - 1),
                            y: isFlat ? h / 2 : pad + (1 - CGFloat((v - lo) / range)) * (h - 2 * pad)
                        )
                    }
                    let line = smoothedPath(through: pts)
                    let area = areaPath(under: line, points: pts, height: h)

                    area.fill(LinearGradient(
                        colors: [stateColor.opacity(0.28), stateColor.opacity(0.02)],
                        startPoint: .top, endPoint: .bottom))

                    line.stroke(stateColor, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .shadow(color: stateColor.opacity(0.7), radius: 4)

                    Circle().fill(stateColor).frame(width: 6, height: 6)
                        .shadow(color: stateColor.opacity(0.9), radius: 4)
                        .position(pts[pts.count - 1])
                } else {
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: h / 2))
                        p.addLine(to: CGPoint(x: w, y: h / 2))
                    }
                    .stroke(Color.white.opacity(0.18),
                            style: StrokeStyle(lineWidth: 1.5, dash: [3, 5]))
                }
            }
        }
    }

    private func areaPath(under line: Path, points: [CGPoint], height: CGFloat) -> Path {
        var area = line
        guard let last = points.last, let first = points.first else { return area }
        area.addLine(to: CGPoint(x: last.x, y: height))
        area.addLine(to: CGPoint(x: first.x, y: height))
        area.closeSubpath()
        return area
    }

    /// Midpoint quadratic smoothing — enough curvature to read as a market line, cheap enough
    /// for a message bubble.
    private func smoothedPath(through pts: [CGPoint]) -> Path {
        var path = Path()
        guard let first = pts.first else { return path }
        path.move(to: first)
        for i in 1..<pts.count {
            let prev = pts[i - 1]
            let cur = pts[i]
            let mid = CGPoint(x: (prev.x + cur.x) / 2, y: (prev.y + cur.y) / 2)
            path.addQuadCurve(to: mid, control: prev)
        }
        if let last = pts.last { path.addLine(to: last) }
        return path
    }
}

// MARK: - Scoreboard (arena matchup panel)

struct HermesScoreBoardView: View {
    let score: HermesScoreBoard
    @Environment(\.hermesAccent) private var accent

    private var homeColor: Color { Color(hermesHex: score.homeColorHex) ?? accent }
    private var awayColor: Color { Color(hermesHex: score.awayColorHex) ?? accent }
    private var glowColor: Color {
        switch score.winner {
        case .home: return homeColor
        case .away: return awayColor
        case .none: return accent
        }
    }

    var body: some View {
        VStack(spacing: 13) {
            if let status = score.statusText {
                Text(status.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .kerning(1.4)
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(0.10)))
            }

            HStack(alignment: .center, spacing: 10) {
                teamColumn(name: score.homeName, scoreText: score.homeScore,
                           color: homeColor, dimmed: score.winner == .away)
                Text("–")
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))
                teamColumn(name: score.awayName, scoreText: score.awayScore,
                           color: awayColor, dimmed: score.winner == .home)
            }
            .frame(maxWidth: .infinity)

            if let detail = score.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.45))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .hermesScenePanel(glow: glowColor)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11yLabel)
    }

    private var a11yLabel: String {
        var s = "Scoreboard: \(score.homeName) \(score.homeScore), \(score.awayName) \(score.awayScore)."
        if let st = score.statusText { s += " \(st)." }
        switch score.winner {
        case .home: s += " \(score.homeName) won."
        case .away: s += " \(score.awayName) won."
        case .none: break
        }
        return s
    }

    // Contextual dimming (rule 6): the losing side recedes, the winner stays lit.
    private func teamColumn(name: String, scoreText: String, color: Color, dimmed: Bool) -> some View {
        VStack(spacing: 9) {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 8, height: 8)
                    .shadow(color: color.opacity(0.9), radius: 3)
                Text(name.uppercased())
                    .font(.system(size: 12, weight: .semibold))
                    .kerning(1.1)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            digitTiles(scoreText)
        }
        .opacity(dimmed ? 0.45 : 1)
        .frame(maxWidth: .infinity)
    }

    /// Flap tiles sized to the column: fixed 30pt tiles overflow the half-width column once
    /// a score reaches 4+ characters (cricket "287/6", tennis sets), so the tile width
    /// adapts to what the column actually offers.
    private func digitTiles(_ scoreText: String) -> some View {
        let chars = Array(scoreText.isEmpty ? "–" : scoreText)
        return GeometryReader { geo in
            let n = CGFloat(chars.count)
            let tileWidth = min(30, max(12, (geo.size.width - 3 * (n - 1)) / n))
            HStack(spacing: 3) {
                ForEach(Array(chars.enumerated()), id: \.offset) { _, ch in
                    HermesSplitFlapTile(character: String(ch), width: tileWidth)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 41)
    }
}
