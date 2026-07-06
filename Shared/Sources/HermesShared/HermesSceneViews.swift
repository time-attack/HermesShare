// HermesSceneViews.swift
// The custom-drawn ADA centerpieces (ada-swiftui-design rule 10: "Draw the scene"). These are
// the domain-unique, state-encoding heroes that separate an ADA-grade card from a well-dressed
// spreadsheet. Everything here is built from SwiftUI primitives / Canvas geometry — no assets,
// no bitmaps, and still a fixed interpreter (the JSON only parameterizes these drawings).
//
//   • HermesFlightBoardView  — airport split-flap departure board + live route strip
//   • HermesPlatedDishView   — procedural Canvas plate/food/garnish/steam scene
//   • HermesGaugeClusterView — cockpit-style arc gauge instrument cluster
//   • HermesCabinFrame       — the fuselage the seat map lives inside
//
// All decorative layers are hidden from VoiceOver; each centerpiece exposes one combined
// accessibility label stating its takeaway (rule 11).

import SwiftUI

// MARK: - Flight board (split-flap departure board)

/// One split-flap tile: a dark rounded slug with a top-lit gradient, a mechanical seam across
/// the middle, and one monospaced glyph. Real geometry, not a restyled Text (rule 7).
struct HermesSplitFlapTile: View {
    let character: String
    var width: CGFloat = 26

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(white: 0.17), Color(white: 0.085)],
                    startPoint: .top, endPoint: .bottom))
            Text(character)
                .font(.system(size: width * 0.72, weight: .bold, design: .monospaced))
                .foregroundStyle(Color(white: 0.96))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            // The split-flap seam: a hard shadow line with a hairline highlight just below it.
            VStack(spacing: 0) {
                Rectangle().fill(Color.black.opacity(0.55)).frame(height: 1.2)
                Rectangle().fill(Color.white.opacity(0.05)).frame(height: 0.6)
            }
        }
        .frame(width: width, height: width * 1.34)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(Color.black.opacity(0.6), lineWidth: 0.5))
    }
}

/// The flight-card hero: split-flap origin/destination codes, a route strip carrying the plane
/// at its real `progress`, and DEPARTS / GATE / ARRIVES columns — the whole card is one dark
/// instrument panel. Encodes state: the status hue + plane position are driven by the data.
struct HermesFlightBoardView: View {
    let board: HermesFlightBoard
    @Environment(\.hermesAccent) private var accent

    private var stateColor: Color { Color(hermesHex: board.statusColorHex) ?? accent }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                if let code = board.flightCode {
                    Text(code)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .kerning(1.5)
                        .foregroundStyle(.white.opacity(0.55))
                }
                Spacer()
                statusPill
            }

            HStack(alignment: .center, spacing: 8) {
                flapGroup(board.origin)
                routeStrip
                flapGroup(board.destination)
            }

            if board.originCity != nil || board.destinationCity != nil {
                HStack(alignment: .top) {
                    Text(board.originCity ?? "")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(board.destinationCity ?? "")
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
            }

            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)

            HStack(alignment: .top, spacing: 8) {
                boardStat("DEPARTS", board.departTime, align: .leading)
                boardStat("GATE", board.gate, align: .center)
                boardStat("ARRIVES", board.arriveTime, align: .trailing)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(boardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11yLabel)
    }

    private var a11yLabel: String {
        var s = "Flight"
        if let c = board.flightCode { s += " \(c)" }
        s += " from \(board.origin) to \(board.destination). \(board.status)."
        if let g = board.gate { s += " Gate \(g)." }
        if let d = board.departTime { s += " Departs \(d)." }
        return s
    }

    private func flapGroup(_ code: String) -> some View {
        HStack(spacing: 3) {
            ForEach(Array(code.uppercased().enumerated()), id: \.offset) { _, ch in
                HermesSplitFlapTile(character: String(ch))
            }
        }
        .fixedSize()
    }

    // Dashed base line + solid lit trail trimmed to progress + plane at the real position.
    private var routeStrip: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let midY = geo.size.height / 2
            let p = CGFloat(max(0, min(1, board.progress ?? 0)))
            let planeX = max(9, min(w - 9, w * p))
            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: 6, y: midY))
                    path.addLine(to: CGPoint(x: w - 6, y: midY))
                }
                .stroke(Color.white.opacity(0.22),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [2, 4]))
                if board.progress != nil {
                    Path { path in
                        path.move(to: CGPoint(x: 6, y: midY))
                        path.addLine(to: CGPoint(x: planeX, y: midY))
                    }
                    .stroke(stateColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .shadow(color: stateColor.opacity(0.8), radius: 4)
                }
                Circle().fill(Color.white.opacity(0.45)).frame(width: 5, height: 5)
                    .position(x: 6, y: midY)
                Circle().fill(stateColor).frame(width: 6, height: 6)
                    .position(x: w - 6, y: midY)
                Image(systemName: "airplane")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .shadow(color: stateColor.opacity(0.9), radius: 4)
                    .position(x: planeX, y: midY)
            }
        }
        .frame(height: 22)
        .frame(minWidth: 36, maxWidth: .infinity)
    }

    private var statusPill: some View {
        HStack(spacing: 5) {
            Circle().fill(stateColor).frame(width: 6, height: 6)
                .shadow(color: stateColor.opacity(0.9), radius: 3)
            Text(board.status.uppercased())
                .font(.system(size: 10, weight: .bold))
                .kerning(0.8)
                .foregroundStyle(stateColor)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Capsule().fill(stateColor.opacity(0.16)))
    }

    private func boardStat(_ label: String, _ value: String?, align: HorizontalAlignment) -> some View {
        VStack(alignment: align, spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .kerning(1.2)
                .foregroundStyle(.white.opacity(0.4))
            Text(value ?? "—")
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.92))
        }
        .frame(maxWidth: .infinity,
               alignment: align == .leading ? .leading : (align == .trailing ? .trailing : .center))
    }

    private var boardBackground: some View {
        ZStack {
            Color(red: 0.07, green: 0.075, blue: 0.09)
            RadialGradient(
                colors: [stateColor.opacity(0.14), .clear],
                center: .topLeading, startRadius: 4, endRadius: 260)
        }
    }
}

// MARK: - Plated dish (procedural Canvas scene)

/// A procedurally-drawn plated dish: warm counter light, a plate (rim + well + specular
/// highlight), a food mound with seeded garnish specks, and blurred rising steam when hot.
/// Deterministic given `seed`. Editorial cookbook hero (Architecture B: full-bleed scene, the
/// recipe content sits on a surface below it).
struct HermesPlatedDishView: View {
    let dish: HermesPlatedDish

    private var foodColor: Color { Color(hermesHex: dish.foodColorHex) ?? Color(red: 0.80, green: 0.42, blue: 0.18) }
    private var garnishColor: Color { Color(hermesHex: dish.garnishColorHex) ?? Color(red: 0.44, green: 0.68, blue: 0.30) }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Canvas { ctx, size in draw(ctx: &ctx, size: size) }
                .accessibilityHidden(true)

            if dish.title != nil || dish.caption != nil {
                VStack(alignment: .leading, spacing: 2) {
                    if let title = dish.title {
                        Text(title)
                            .font(.system(size: 22, weight: .bold, design: .serif))
                            .foregroundStyle(.white)
                    }
                    if let caption = dish.caption {
                        Text(caption.uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .kerning(1.4)
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }
                .shadow(color: .black.opacity(0.5), radius: 6, y: 1)
                .padding(16)
            }
        }
        .frame(height: 208)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Illustration of a plated dish: \(dish.title ?? "the recipe")\(dish.steam ? ", served hot" : "").")
    }

    private func draw(ctx: inout GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height

        // Warm counter light (one soft source, upper area).
        ctx.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .radialGradient(
                Gradient(colors: [Color(red: 0.22, green: 0.15, blue: 0.10),
                                  Color(red: 0.09, green: 0.065, blue: 0.05)]),
                center: CGPoint(x: w * 0.5, y: h * 0.30),
                startRadius: 8, endRadius: max(w, h) * 0.85))

        let cx = w * 0.5, cy = h * 0.60
        let plateW = min(w * 0.74, 300.0), plateH = plateW * 0.44

        func ellipse(_ ex: Double, _ ey: Double, _ ew: Double, _ eh: Double) -> Path {
            Path(ellipseIn: CGRect(x: ex - ew / 2, y: ey - eh / 2, width: ew, height: eh))
        }

        // Cast shadow under the plate.
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 9))
            layer.fill(ellipse(cx, cy + plateH * 0.28, plateW * 0.96, plateH * 0.62),
                       with: .color(.black.opacity(0.45)))
        }
        // Plate rim (top-lit).
        ctx.fill(ellipse(cx, cy, plateW, plateH),
                 with: .linearGradient(
                    Gradient(colors: [Color(white: 0.97), Color(white: 0.78)]),
                    startPoint: CGPoint(x: cx, y: cy - plateH / 2),
                    endPoint: CGPoint(x: cx, y: cy + plateH / 2)))
        // Well.
        let wellW = plateW * 0.72, wellH = plateH * 0.70
        ctx.fill(ellipse(cx, cy, wellW, wellH), with: .color(Color(white: 0.90)))
        ctx.stroke(ellipse(cx, cy, wellW, wellH), with: .color(.black.opacity(0.10)), lineWidth: 1.5)

        // Food mound (radial toward the light).
        let foodW = wellW * 0.74, foodH = wellH * 0.66
        ctx.fill(ellipse(cx, cy - foodH * 0.04, foodW, foodH),
                 with: .radialGradient(
                    Gradient(colors: [foodColor.opacity(1.0), foodColor.opacity(0.72)]),
                    center: CGPoint(x: cx - foodW * 0.18, y: cy - foodH * 0.28),
                    startRadius: 2, endRadius: foodW * 0.62))

        // Seeded garnish specks, uniformly scattered inside the food ellipse.
        var state: UInt64 = UInt64(truncatingIfNeeded: dish.seed ?? 7) &+ 1
        func rnd() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double((state >> 33) % 1000) / 1000
        }
        for _ in 0..<28 {
            let ang = rnd() * 2 * .pi
            let rad = (0.15 + 0.80 * (rnd() * rnd()).squareRoot())
            let px = cx + cos(ang) * (foodW * 0.44) * rad
            let py = (cy - foodH * 0.04) + sin(ang) * (foodH * 0.42) * rad
            let s = 1.6 + rnd() * 2.4
            let tint = rnd() > 0.5 ? garnishColor : garnishColor.opacity(0.7)
            ctx.fill(Path(ellipseIn: CGRect(x: px - s / 2, y: py - s / 2, width: s, height: s)),
                     with: .color(tint))
        }

        // Specular highlight on the rim (upper-left, one light source).
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 4))
            layer.fill(ellipse(cx - plateW * 0.24, cy - plateH * 0.26, plateW * 0.30, plateH * 0.16),
                       with: .color(.white.opacity(0.7)))
        }

        // Steam: wavy sine ribbons rising off the food, blurred for atmosphere.
        if dish.steam {
            ctx.drawLayer { layer in
                layer.addFilter(.blur(radius: 3))
                for i in 0..<3 {
                    let baseX = cx + Double(i - 1) * foodW * 0.24
                    let baseY = cy - foodH * 0.28
                    let rise = h * 0.34
                    var path = Path()
                    path.move(to: CGPoint(x: baseX, y: baseY))
                    var t = 0.0
                    while t <= 1.0 {
                        let y = baseY - rise * t
                        let x = baseX + sin(t * .pi * 3 + Double(i) * 1.7) * 9 * (1 - t)
                        path.addLine(to: CGPoint(x: x, y: y))
                        t += 0.08
                    }
                    layer.stroke(path,
                                 with: .color(.white.opacity(0.20)),
                                 style: StrokeStyle(lineWidth: 3, lineCap: .round))
                }
            }
        }
    }
}

// MARK: - Gauge cluster (cockpit instrument look)

/// A row of arc gauges — 270° sweep, tick marks, a lit value arc, a hero numeral in the center.
/// Replaces flat, equal-weight stat tiles with a finance/instrument-cluster centerpiece.
struct HermesGaugeClusterView: View {
    let gauges: [HermesGauge]
    @Environment(\.hermesAccent) private var accent

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(Array(gauges.enumerated()), id: \.offset) { _, gauge in
                gaugeView(gauge)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private func gaugeView(_ gauge: HermesGauge) -> some View {
        let color = Color(hermesHex: gauge.colorHex) ?? accent
        let v = max(0, min(1, gauge.value))
        return VStack(spacing: 9) {
            ZStack {
                // Track (270°, gap at the bottom).
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(Color.white.opacity(0.10),
                            style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(135))
                // Lit value arc.
                Circle()
                    .trim(from: 0, to: 0.75 * v)
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [color.opacity(0.4), color]),
                            center: .center,
                            startAngle: .degrees(135),
                            endAngle: .degrees(135 + 270)),
                        style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(135))
                    .shadow(color: color.opacity(0.6), radius: 4)
                // Tick marks around the arc.
                ForEach(0..<10, id: \.self) { i in
                    Capsule()
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 1.5, height: 4)
                        .offset(y: -33)
                        .rotationEffect(.degrees(135 + Double(i) * (270.0 / 9.0)))
                }
                Text(gauge.valueText ?? "\(Int((v * 100).rounded()))")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
            }
            .frame(width: 76, height: 76)
            Text(gauge.label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .kerning(1.0)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(gauge.label): \(gauge.valueText ?? "\(Int((v * 100).rounded())) percent")")
    }
}

// MARK: - Cabin frame (the fuselage the seat map sits inside)

/// Aircraft-cabin outline: a fuselage with a rounded nose at the top and window ports down each
/// side, so the seat grid reads as the cabin you're picking a seat *in* — not a bare grid.
struct HermesCabinFrame: View {
    var tint: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let noseInset = min(h * 0.14, 34)
            ZStack {
                fuselage(w: w, h: h, noseInset: noseInset)
                    .fill(Color.white.opacity(0.035))
                fuselage(w: w, h: h, noseInset: noseInset)
                    .stroke(tint.opacity(0.28), lineWidth: 1.5)
                windows(w: w, h: h, noseInset: noseInset)
            }
        }
    }

    private func fuselage(w: CGFloat, h: CGFloat, noseInset: CGFloat) -> Path {
        Path { p in
            let sideInset: CGFloat = 3
            p.move(to: CGPoint(x: sideInset, y: h))
            p.addLine(to: CGPoint(x: sideInset, y: noseInset))
            p.addQuadCurve(to: CGPoint(x: w / 2, y: 2),
                           control: CGPoint(x: sideInset, y: noseInset * 0.30))
            p.addQuadCurve(to: CGPoint(x: w - sideInset, y: noseInset),
                           control: CGPoint(x: w - sideInset, y: noseInset * 0.30))
            p.addLine(to: CGPoint(x: w - sideInset, y: h))
        }
    }

    private func windows(w: CGFloat, h: CGFloat, noseInset: CGFloat) -> some View {
        let count = max(3, Int((h - noseInset) / 26))
        let startY = noseInset + 16
        let step = (h - startY - 10) / CGFloat(max(1, count - 1))
        return ForEach(0..<count, id: \.self) { i in
            let y = startY + CGFloat(i) * step
            Group {
                windowPort.position(x: 9, y: y)
                windowPort.position(x: w - 9, y: y)
            }
        }
    }

    private var windowPort: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(tint.opacity(0.22))
            .frame(width: 5, height: 8)
    }
}
