// HermesLayoutRenderer.swift
// The native SwiftUI renderer for a `HermesLayout`. This is the fixed, ship-once interpreter:
// it walks the `HermesNode` tree and maps each case to a real SwiftUI primitive. Analogous to
// Scriptable's ListWidget/WidgetText or Widgy's layout engine — the JSON only *selects and
// parameterizes* primitives from this fixed vocabulary; it never supplies executable code.

import SwiftUI
import MapKit

// MARK: - Presentation mode

/// Where a layout is being shown. The same renderer drives both; only chrome/padding differ.
public enum HermesPresentation {
    case compact   // small bubble in the Messages transcript
    case expanded  // full mini-app view when tapped

    var outerPadding: CGFloat { self == .compact ? 12 : 20 }
    var showsHeader: Bool { true }
}

// MARK: - Color helpers

public extension Color {
    /// Parse "#RRGGBB" / "#RRGGBBAA" (or without the leading #). Returns nil on failure.
    init?(hermesHex hex: String?) {
        guard let hex else { return nil }
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard let value = UInt64(s, radix: 16) else { return nil }
        let r, g, b, a: Double
        switch s.count {
        case 6:
            r = Double((value & 0xFF0000) >> 16) / 255
            g = Double((value & 0x00FF00) >> 8) / 255
            b = Double(value & 0x0000FF) / 255
            a = 1
        case 8:
            r = Double((value & 0xFF000000) >> 24) / 255
            g = Double((value & 0x00FF0000) >> 16) / 255
            b = Double((value & 0x0000FF00) >> 8) / 255
            a = Double(value & 0x000000FF) / 255
        default:
            return nil
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

// MARK: - Root renderer

public struct HermesLayoutRenderer: View {
    public let layout: HermesLayout
    public var presentation: HermesPresentation
    /// Called when the user taps an action button. Defaults to opening the deep-link URL.
    public var onAction: ((HermesAction) -> Void)?

    public init(
        layout: HermesLayout,
        presentation: HermesPresentation = .expanded,
        onAction: ((HermesAction) -> Void)? = nil
    ) {
        self.layout = layout
        self.presentation = presentation
        self.onAction = onAction
    }

    private var accent: Color {
        Color(hermesHex: layout.accentColorHex) ?? .accentColor
    }

    private var isAtmosphere: Bool { layout.background?.kind == .atmosphere }

    /// The color the HOST surface behind the renderer should use so the scene extends past
    /// the card's own bounds (scroll overshoot, safe areas). Matches each background kind's
    /// own base so bounce never flashes a mismatched band.
    public static func canvasColor(for layout: HermesLayout) -> Color {
        switch layout.background?.kind {
        case .atmosphere:
            return Color(red: 0.05, green: 0.055, blue: 0.075)
        case .gradient:
            return (layout.background?.colorsHex?.first).flatMap { Color(hermesHex: $0) }
                ?? Color(.systemBackground)
        case .plain, .none:
            return Color(.systemBackground)
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: presentation == .compact ? 8 : 16) {
            if presentation.showsHeader, layout.title != nil || layout.subtitle != nil {
                header
            }

            HermesNodeView(node: layout.root)

            if let actions = layout.actions, !actions.isEmpty {
                actionBar(actions)
            }
        }
        .padding(presentation.outerPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background)
        // The host insets the renderer by 8pt when expanded; a square-cornered glow region
        // reads as an unclipped layer, so the atmosphere gets the same continuous rounding
        // as every surface that sits on it.
        .clipShape(RoundedRectangle(cornerRadius: isAtmosphere ? 24 : 0, style: .continuous))
        .tint(accent)
        .environment(\.hermesAccent, accent)
        .environment(\.hermesOnAction, onAction ?? HermesActionHandler.openDeepLink)
        // Atmosphere is a dark world: force dark-mode system colors for everything on it so
        // grouped cards, labels, and fills read as surfaces IN the scene, not gray boxes on it.
        .environment(\.colorScheme, isAtmosphere ? .dark : colorScheme)
    }

    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder private var header: some View {
        // ADA rule 4 (typography does the layout's work): subtitle as a kerned small-caps
        // micro-label ABOVE the hero title reads as "context, then answer" — closer to how
        // real apps caption a hero value than two same-weight lines stacked flat.
        VStack(alignment: .leading, spacing: 3) {
            if let subtitle = layout.subtitle {
                Text(subtitle.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .kerning(1.1)
                    .foregroundStyle(.secondary)
            }
            if let title = layout.title {
                Text(title)
                    .font(presentation == .compact ? .headline : .system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
            }
        }
    }

    @ViewBuilder private func actionBar(_ actions: [HermesAction]) -> some View {
        VStack(spacing: 8) {
            ForEach(actions, id: \.id) { action in
                HermesPrimaryCTA(label: action.label, systemImage: action.systemImage) {
                    if let onAction {
                        onAction(action)
                    } else {
                        HermesActionHandler.openDeepLink(action)
                    }
                }
            }
        }
    }

    @ViewBuilder private var background: some View {
        switch layout.background?.kind {
        case .gradient:
            let colors = (layout.background?.colorsHex ?? [])
                .compactMap { Color(hermesHex: $0) }
            if colors.count >= 2 {
                LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            } else {
                Color(.systemBackground)
            }
        case .atmosphere:
            // The dark instrument bay the scene panels sit in: near-black base, a tinted key
            // glow top-leading, a faint answering glow bottom-trailing (one light source +
            // bounce, same recipe as the drawn scenes).
            let tint = (layout.background?.colorsHex?.first).flatMap { Color(hermesHex: $0) } ?? accent
            ZStack {
                Color(red: 0.05, green: 0.055, blue: 0.075)
                RadialGradient(colors: [tint.opacity(0.26), .clear],
                               center: .topLeading, startRadius: 10, endRadius: 430)
                RadialGradient(colors: [tint.opacity(0.10), .clear],
                               center: .bottomTrailing, startRadius: 10, endRadius: 390)
            }
            .ignoresSafeArea()
        case .plain, .none:
            Color(.systemBackground)
        }
    }
}

// MARK: - Recursive node view

public struct HermesNodeView: View {
    public let node: HermesNode
    @Environment(\.hermesAccent) private var accent

    public init(node: HermesNode) { self.node = node }

    public var body: some View {
        switch node {
        case let .vstack(spacing, alignment, children):
            VStack(alignment: horizontalAlignment(alignment), spacing: spacing) {
                ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                    HermesNodeView(node: child)
                }
            }
            .frame(maxWidth: .infinity, alignment: frameAlignment(alignment))

        case let .hstack(spacing, alignment, children):
            HStack(alignment: verticalAlignment(alignment), spacing: spacing) {
                ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                    HermesNodeView(node: child)
                }
            }

        case let .text(value, style):
            textView(value, style)

        case let .icon(systemName, sizePt, colorHex):
            Image(systemName: systemName)
                .font(.system(size: sizePt))
                .foregroundStyle(Color(hermesHex: colorHex) ?? accent)
                .symbolRenderingMode(.hierarchical)

        case let .statusBadge(label, colorHex):
            statusBadge(label, colorHex)

        case let .progressRing(value, label, colorHex):
            progressRing(value, label, colorHex)

        case let .progressBar(value, colorHex):
            // ADA rule 8: instruments deserve jewelry — track + gradient fill + glowing
            // position marker, never a bare ProgressView.
            jeweledProgressBar(value: max(0, min(1, value)), color: Color(hermesHex: colorHex) ?? accent)

        case .divider:
            Divider()

        case let .spacer(minLength):
            Spacer(minLength: minLength ?? 0)

        case let .keyValueRow(key, value, iconSystemName):
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if let iconSystemName {
                    ZStack {
                        Circle()
                            .fill(accent.opacity(0.15))
                            .frame(width: 26, height: 26)
                        Image(systemName: iconSystemName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(accent)
                    }
                }
                Text(key)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 12)
                Text(value)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.trailing)
            }

        case let .mapPreview(latitude, longitude, label):
            mapPreview(latitude, longitude, label)

        case let .image(url, aspectRatio, cornerRadius):
            imageView(url, aspectRatio, cornerRadius)

        case let .card(padding, cornerRadius, backgroundHex, child):
            HermesNodeView(node: child)
                .padding(padding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(glassCardBackground(cornerRadius: cornerRadius, backgroundHex: backgroundHex))

        case let .seatChart(rows, selectedSeatId):
            HermesSeatChartView(rows: rows, initialSelectedSeatId: selectedSeatId)

        case let .quickReplyRow(options):
            HermesQuickReplyRowView(options: options)

        case let .checklist(items):
            checklistView(items)

        case let .timeline(entries):
            HermesTimelineView(entries: entries)

        case let .rating(value, maxValue, label, colorHex):
            ratingView(value, maxValue, label, colorHex)

        case let .table(headers, rows):
            tableView(headers, rows)

        case let .gallery(urls, heightPt, cornerRadius):
            galleryView(urls, heightPt, cornerRadius)

        case let .tagRow(labels, colorHex):
            tagRowView(labels, colorHex)

        case let .stat(value, label, iconSystemName, colorHex):
            statView(value, label, iconSystemName, colorHex)

        case let .dateBadge(month, day, weekday, colorHex):
            dateBadgeView(month, day, weekday, colorHex)

        case let .person(name, detail, imageUrl, colorHex):
            personView(name, detail, imageUrl, colorHex)

        case let .barChart(bars, maxValue):
            barChartView(bars, maxValue)

        case let .optionPicker(options, selectedId, confirmLabel, style):
            HermesOptionPickerView(
                options: options, initialSelectedId: selectedId,
                confirmLabel: confirmLabel, style: style
            )

        case let .flightBoard(board):
            HermesFlightBoardView(board: board)

        case let .platedDish(dish):
            HermesPlatedDishView(dish: dish)

        case let .gaugeCluster(gauges):
            HermesGaugeClusterView(gauges: gauges)

        case let .journeyArc(arc):
            HermesJourneyArcView(arc: arc)

        case let .skyScene(sky):
            HermesSkySceneView(sky: sky)

        case let .eventTicket(ticket):
            HermesEventTicketView(ticket: ticket)

        case let .sparkline(spark):
            HermesSparklineView(spark: spark)

        case let .scoreBoard(score):
            HermesScoreBoardView(score: score)

        case let .mediaList(items):
            HermesMediaListView(items: items)

        case let .photoCatalog(items, initialExpandedId, confirmLabel):
            HermesPhotoCatalogView(items: items, initialExpandedId: initialExpandedId, confirmLabel: confirmLabel)

        case let .collapsible(id, title, subtitle, imageUrl, badge, initiallyExpanded, child):
            HermesCollapsibleView(
                id: id, title: title, subtitle: subtitle, imageUrl: imageUrl,
                badge: badge, initiallyExpanded: initiallyExpanded, child: child
            )

        case let .unsupported(typeName):
            // Forward-compat surface: the sender used vocabulary this build doesn't know.
            // Per the no-silent-fallback rule this is visible and named, never blank.
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle.dotted")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                // The one actionable string on the surface — primary, not gray-on-gray.
                Text("Update HermesShare to view this content (\(typeName))")
                    .font(.caption)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(.tertiarySystemFill))
            )
        }
    }

    /// Flat, adaptive system surface for content-layer cards. Per Apple's HIG ("Don't use
    /// Liquid Glass in the content layer") a card sitting inline in scrolling/bubble content
    /// is content, not floating nav chrome — so it gets a plain `secondarySystemBackground`
    /// fill (or the author's explicit `backgroundHex`), never `.glassEffect()`/`.ultraThinMaterial`.
    /// See swiftui-design skill: references/liquid-glass-belongs-to-navigation-not-content.md.
    @ViewBuilder
    private func glassCardBackground(cornerRadius: CGFloat, backgroundHex: String?) -> some View {
        let color = backgroundHex.flatMap(Color.init(hermesHex:)) ?? Color(.secondarySystemBackground)
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(color)
    }

    // MARK: Leaf builders

    @ViewBuilder private func textView(_ value: String, _ style: HermesTextStyle) -> some View {
        Text(value)
            .font(font(for: style))
            .foregroundStyle(Color(hermesHex: style.colorHex) ?? .primary)
            .multilineTextAlignment(textAlignment(style.alignment))
            .frame(maxWidth: .infinity, alignment: frameAlignment(style.alignment))
    }

    @ViewBuilder private func statusBadge(_ label: String, _ colorHex: String) -> some View {
        let color = Color(hermesHex: colorHex) ?? accent
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule().fill(color.opacity(0.15))
        )
    }

    @ViewBuilder private func progressRing(_ value: Double, _ label: String?, _ colorHex: String?) -> some View {
        // ADA rule 5 (numerals are heroes) + rule 8 (jeweled instruments, never bare
        // ProgressView-style rings): larger hero numeral, glow on the lit trail, monospaced.
        let v = max(0, min(1, value))
        let color = Color(hermesHex: colorHex) ?? accent
        ZStack {
            Circle()
                .stroke(color.opacity(0.12), lineWidth: 9)
            Circle()
                .trim(from: 0, to: v)
                .stroke(color, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.7), radius: 4)
            VStack(spacing: 0) {
                Text("\(Int((v * 100).rounded()))")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                + Text("%")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                if let label {
                    Text(label.uppercased())
                        .font(.system(size: 9, weight: .semibold))
                        .kerning(1.0)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 84, height: 84)
    }

    /// ADA recipe: track + gradient fill + glowing lit trail. Never a bare ProgressView.
    @ViewBuilder private func jeweledProgressBar(value: Double, color: Color) -> some View {
        GeometryReader { geo in
            let x = max(6, geo.size.width * value)
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(0.12)).frame(height: 6)
                Capsule()
                    .fill(LinearGradient(colors: [color.opacity(0.35), color],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: x, height: 6)
                    .shadow(color: color.opacity(0.6), radius: 4)
            }
        }
        .frame(height: 6)
    }

    @ViewBuilder private func mapPreview(_ lat: Double, _ lon: Double, _ label: String?) -> some View {
        let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        VStack(alignment: .leading, spacing: 6) {
            Map(initialPosition: .region(MKCoordinateRegion(
                center: coord,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            ))) {
                Marker(label ?? "", coordinate: coord)
                    .tint(accent)
            }
            .allowsHitTesting(false)   // static snapshot feel; no live panning inside a bubble
            .frame(height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            if let label {
                Label(label, systemImage: "mappin.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func imageView(_ url: String, _ aspectRatio: Double?, _ cornerRadius: CGFloat?) -> some View {
        AsyncImage(url: URL(string: url)) { phase in
            switch phase {
            case let .success(image):
                image.resizable().aspectRatio(contentMode: .fill)
            case .failure:
                placeholder(systemName: "photo")
            case .empty:
                placeholder(systemName: "photo", showsProgress: true)
            @unknown default:
                placeholder(systemName: "photo")
            }
        }
        .aspectRatio(aspectRatio.map { CGFloat($0) }, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius ?? 12, style: .continuous))
    }

    @ViewBuilder private func placeholder(systemName: String, showsProgress: Bool = false) -> some View {
        ZStack {
            Rectangle().fill(Color(.tertiarySystemFill))
            if showsProgress {
                ProgressView()
            } else {
                Image(systemName: systemName)
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            }
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
    }

    // MARK: v3 leaf builders

    @ViewBuilder private func checklistView(_ items: [HermesChecklistItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    // A plain bullet (`state: none`, no custom icon) renders as a small dot;
                    // stateful glyphs and custom icons render at full symbol size.
                    let isPlainBullet = (item.iconSystemName == nil && item.state == .none)
                    Image(systemName: item.iconSystemName ?? glyph(for: item.state))
                        .font(.system(size: isPlainBullet ? 6 : 17, weight: .medium))
                        .foregroundStyle(item.state == .checked ? accent : Color.secondary)
                        .frame(width: 22, height: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.text)
                            .font(.subheadline)
                            .foregroundStyle(item.state == .checked ? Color.secondary : .primary)
                            .strikethrough(item.state == .checked, color: .secondary)
                        if let detail = item.detail {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func glyph(for state: HermesChecklistItem.State) -> String {
        switch state {
        case .checked: return "checkmark.circle.fill"
        case .unchecked: return "circle"
        case .none: return "circle.fill"   // rendered tiny below via font size? keep simple dot
        }
    }

    @ViewBuilder private func ratingView(_ value: Double, _ maxValue: Int, _ label: String?, _ colorHex: String?) -> some View {
        let color = Color(hermesHex: colorHex) ?? .yellow
        HStack(spacing: 6) {
            HStack(spacing: 2) {
                ForEach(0..<max(1, maxValue), id: \.self) { i in
                    Image(systemName: starName(index: i, value: value))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(color)
                }
            }
            if let label {
                Text(label)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func starName(index: Int, value: Double) -> String {
        let filled = value - Double(index)
        if filled >= 0.75 { return "star.fill" }
        if filled >= 0.25 { return "star.leadinghalf.filled" }
        return "star"
    }

    @ViewBuilder private func tableView(_ headers: [String]?, _ rows: [[String]]) -> some View {
        let columnCount = max(headers?.count ?? 0, rows.map(\.count).max() ?? 0)
        if columnCount > 0 {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                if let headers {
                    GridRow {
                        ForEach(Array(headers.enumerated()), id: \.offset) { _, h in
                            Text(h)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                        }
                    }
                    Divider().gridCellUnsizedAxes(.horizontal)
                }
                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                    GridRow {
                        ForEach(0..<columnCount, id: \.self) { col in
                            Text(col < row.count ? row[col] : "")
                                .font(.subheadline)
                                .foregroundStyle(col == 0 ? Color.secondary : .primary)
                                .fontWeight(col == 0 ? .regular : .medium)
                        }
                    }
                    if rowIndex < rows.count - 1 {
                        Divider().gridCellUnsizedAxes(.horizontal)
                    }
                }
            }
        }
    }

    @ViewBuilder private func galleryView(_ urls: [String], _ heightPt: CGFloat?, _ cornerRadius: CGFloat?) -> some View {
        let height = heightPt ?? 120
        let radius = cornerRadius ?? 12
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(urls.enumerated()), id: \.offset) { _, url in
                    AsyncImage(url: URL(string: url)) { phase in
                        switch phase {
                        case let .success(image):
                            image.resizable().aspectRatio(contentMode: .fill)
                        default:
                            ZStack {
                                Rectangle().fill(Color(.tertiarySystemFill))
                                Image(systemName: "photo")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(width: height * 4 / 3, height: height)
                    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                }
            }
        }
    }

    @ViewBuilder private func tagRowView(_ labels: [String], _ colorHex: String?) -> some View {
        let color = Color(hermesHex: colorHex) ?? accent
        HermesFlowLayout(spacing: 6, rowSpacing: 6) {
            ForEach(Array(labels.enumerated()), id: \.offset) { _, label in
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(color)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(color.opacity(0.12)))
            }
        }
    }

    @ViewBuilder private func statView(_ value: String, _ label: String, _ iconSystemName: String?, _ colorHex: String?) -> some View {
        let color = Color(hermesHex: colorHex) ?? accent
        VStack(alignment: .leading, spacing: 2) {
            if let iconSystemName {
                Image(systemName: iconSystemName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(color)
            }
            Text(value)
                .font(.title2.weight(.bold).monospacedDigit())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func dateBadgeView(_ month: String, _ day: String, _ weekday: String?, _ colorHex: String?) -> some View {
        let color = Color(hermesHex: colorHex) ?? .red
        VStack(spacing: 0) {
            Text(month.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 3)
                .background(color)
            VStack(spacing: 0) {
                Text(day)
                    .font(.title2.weight(.bold).monospacedDigit())
                    .foregroundStyle(.primary)
                if let weekday {
                    Text(weekday)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(Color(.tertiarySystemBackground))
        }
        .frame(width: 54)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(.separator), lineWidth: 0.5)
        )
    }

    @ViewBuilder private func personView(_ name: String, _ detail: String?, _ imageUrl: String?, _ colorHex: String?) -> some View {
        let color = Color(hermesHex: colorHex) ?? accent
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [color.opacity(0.85), color],
                                         startPoint: .top, endPoint: .bottom))
                if let imageUrl, let url = URL(string: imageUrl) {
                    AsyncImage(url: url) { phase in
                        if case let .success(image) = phase {
                            image.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            initialsText(name)
                        }
                    }
                } else {
                    initialsText(name)
                }
            }
            .frame(width: 38, height: 38)
            .clipShape(Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func initialsText(_ name: String) -> some View {
        Text(name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased())
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(.white)
    }

    @ViewBuilder private func barChartView(_ bars: [HermesBar], _ maxValue: Double?) -> some View {
        let peak = max(maxValue ?? bars.map(\.value).max() ?? 1, 0.0001)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(bars.enumerated()), id: \.offset) { _, bar in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(bar.label)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(bar.valueLabel ?? trimmedNumber(bar.value))
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color(.tertiarySystemFill))
                            Capsule()
                                .fill(Color(hermesHex: bar.colorHex) ?? accent)
                                .frame(width: max(6, geo.size.width * CGFloat(min(1, bar.value / peak))))
                        }
                    }
                    .frame(height: 8)
                }
            }
        }
    }

    private func trimmedNumber(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }

    // MARK: Mapping helpers

    private func font(for style: HermesTextStyle) -> Font {
        let base: Font
        switch style.role {
        case .largeTitle:  base = .largeTitle
        case .title:       base = .title
        case .title2:      base = .title2
        case .title3:      base = .title3
        case .headline:    base = .headline
        case .body:        base = .body
        case .subheadline: base = .subheadline
        case .footnote:    base = .footnote
        case .caption:     base = .caption
        }
        switch style.weight {
        case .regular:  return base
        case .medium:   return base.weight(.medium)
        case .semibold: return base.weight(.semibold)
        case .bold:     return base.weight(.bold)
        }
    }

    private func horizontalAlignment(_ s: String?) -> HorizontalAlignment {
        switch s {
        case "center": return .center
        case "trailing": return .trailing
        default: return .leading
        }
    }

    private func verticalAlignment(_ s: String?) -> VerticalAlignment {
        switch s {
        case "top": return .top
        case "bottom": return .bottom
        case "firstTextBaseline": return .firstTextBaseline
        default: return .center
        }
    }

    private func frameAlignment(_ s: String?) -> Alignment {
        switch s {
        case "center": return .center
        case "trailing": return .trailing
        default: return .leading
        }
    }

    private func textAlignment(_ s: String?) -> TextAlignment {
        switch s {
        case "center": return .center
        case "trailing": return .trailing
        default: return .leading
        }
    }
}

// MARK: - CTA design language
//
// The visual grammar for interactivity, kept deliberately rigid so users are never confused
// about what a tap does:
//
//   1. PRIMARY CTA (`HermesPrimaryCTA`) — the one tap that commits/sends. Always full-width,
//      always `.borderedProminent` (solid, tinted system button — NOT Liquid Glass; this button
//      sits inline in content-layer bubble/card content, not floating nav chrome, so it follows
//      the content-layer rule same as the card background above), always at the bottom of the
//      card. Used by the layout-level action bar AND the seat chart's Confirm button, so it
//      looks identical everywhere.
//   2. QUICK-REPLY CHIPS — custom gradient-filled circular avatar buttons in a wrapping row.
//      Smaller, never full-width, but still button chrome because a chip tap DOES commit
//      (inserts a reply).
//   3. SELECTION STATE — browsing-only taps (picking a seat) change fill/border color on the
//      tapped element itself. No button chrome at all, so they never read as "submit."

/// The single primary-action button used across every card type. If a card commits something,
/// it commits through this exact component.
public struct HermesPrimaryCTA: View {
    public let label: String
    public var systemImage: String?
    public var isEnabled: Bool
    public let action: () -> Void
    @Environment(\.hermesAccent) private var accent

    public init(label: String, systemImage: String? = nil, isEnabled: Bool = true, action: @escaping () -> Void) {
        self.label = label
        self.systemImage = systemImage
        self.isEnabled = isEnabled
        self.action = action
    }

    /// `.borderedProminent` always draws a white label, which fails legibility on bright
    /// accents (white on system yellow measures 1.4:1). Flip to black when the accent is
    /// light — same rule Apple applies to yellow system buttons.
    private var labelColor: Color {
        var (r, g, b, a) = (CGFloat(0), CGFloat(0), CGFloat(0), CGFloat(0))
        UIColor(accent).getRed(&r, green: &g, blue: &b, alpha: &a)
        func lin(_ c: CGFloat) -> CGFloat {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
        return luminance > 0.32 ? .black : .white
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(label)
                    .fontWeight(.semibold)
            }
            .foregroundStyle(labelColor)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!isEnabled)
    }
}

// MARK: - Seat chart

/// Interactive seat picker. Tapping an available seat only updates local selection state
/// (GamePigeon-board style — browse freely); the separate `HermesPrimaryCTA` labeled
/// "Confirm Seat X" is what actually fires the action (which the extension routes into a
/// reply-message insert).
struct HermesSeatChartView: View {
    let rows: [HermesSeatRow]
    @State private var selectedSeatId: String?
    @Environment(\.hermesAccent) private var accent
    @Environment(\.hermesOnAction) private var onAction

    init(rows: [HermesSeatRow], initialSelectedSeatId: String?) {
        self.rows = rows
        // Honor either the explicit selectedSeatId or a seat pre-marked "selected" in JSON.
        let preselected = initialSelectedSeatId
            ?? rows.flatMap(\.seats).first(where: { $0.state == .selected })?.id
        _selectedSeatId = State(initialValue: preselected)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            legend
            // The seat grid lives INSIDE a drawn fuselage — nose at the top, window ports down
            // both sides, a FRONT marker — so it reads as the cabin you're choosing a seat in
            // (ADA rule 10: the grid is a real instrument on a real stage, not a bare table).
            VStack(spacing: 8) {
                Label("FRONT OF CABIN", systemImage: "chevron.up")
                    .font(.system(size: 9, weight: .semibold))
                    .kerning(1.2)
                    .foregroundStyle(accent.opacity(0.7))
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(rows, id: \.rowNumber) { row in
                        seatRow(row)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.top, 12)
            .padding(.horizontal, 6)
            .padding(.bottom, 14)
            .background(HermesCabinFrame(tint: accent))
            HermesPrimaryCTA(
                label: selectedSeatId.map { "Confirm Seat \($0)" } ?? "Select a seat",
                systemImage: "checkmark.seal.fill",
                isEnabled: selectedSeatId != nil
            ) {
                guard let seatId = selectedSeatId else { return }
                onAction(HermesAction(
                    id: "seat-confirm",
                    label: "Confirm Seat \(seatId)",
                    systemImage: "checkmark.seal.fill",
                    deepLinkURL: "hermesshare://action?id=seat-confirm&seat=\(seatId)"
                ))
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 14) {
            legendSwatch(fill: accent.opacity(0.12), stroke: accent.opacity(0.5), label: "Available")
            legendSwatch(fill: Color(.tertiarySystemFill), stroke: .clear, label: "Taken")
            legendSwatch(fill: accent, stroke: .clear, label: "Selected")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func legendSwatch(fill: Color, stroke: Color, label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(fill)
                .stroke(stroke, lineWidth: 1)
                .frame(width: 12, height: 12)
            Text(label)
        }
    }

    @ViewBuilder private func seatRow(_ row: HermesSeatRow) -> some View {
        // Metadata goes UNDER the seats, not trailing them — a trailing badge pushes past the
        // card edge on a 9-abreast row and silently hides behind the horizontal scroll.
        VStack(alignment: .center, spacing: 1) {
            HStack(spacing: 3) {
                Text("\(row.rowNumber)")
                    .font(.caption2.weight(.medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 18, alignment: .trailing)

                ForEach(Array(row.seats.enumerated()), id: \.element.id) { index, seat in
                    seatCell(seat)
                    if row.aisleAfterIndices.contains(index) {
                        Spacer().frame(width: 11)
                    }
                }
            }
            if let badge = rowBadge(row) {
                Text(badge)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(accent)
                    .padding(.leading, 26)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func rowBadge(_ row: HermesSeatRow) -> String? {
        var parts: [String] = []
        if row.isExitRow { parts.append("Exit row") }
        if row.isBulkhead { parts.append("Bulkhead") }
        if row.hasExtraLegroom { parts.append("Extra legroom") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    @ViewBuilder private func seatCell(_ seat: HermesSeat) -> some View {
        let isSelected = seat.id == selectedSeatId
        let isTappable = seat.state == .available || seat.state == .selected

        Text(seat.letter)
            .font(.caption.weight(isSelected ? .bold : .medium))
            .foregroundStyle(seatTextColor(seat, isSelected: isSelected))
            .frame(width: 26, height: 31)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(seatFill(seat, isSelected: isSelected))
                    .stroke(
                        isSelected ? accent : (isTappable ? accent.opacity(0.5) : .clear),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .opacity(seat.state == .unavailable ? 0.35 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .onTapGesture {
                guard isTappable else { return }
                withAnimation(.snappy(duration: 0.2)) {
                    // Tap again to deselect; tap another seat to move the selection.
                    selectedSeatId = isSelected ? nil : seat.id
                }
            }
            .accessibilityLabel("Seat \(seat.id), \(isSelected ? "selected" : seat.state.rawValue)")
            .accessibilityAddTraits(isTappable ? .isButton : [])
    }

    private func seatFill(_ seat: HermesSeat, isSelected: Bool) -> Color {
        if isSelected { return accent }
        switch seat.state {
        case .available, .selected: return accent.opacity(0.12)
        case .taken: return Color(.tertiarySystemFill)
        case .unavailable: return Color(.quaternarySystemFill)
        }
    }

    private func seatTextColor(_ seat: HermesSeat, isSelected: Bool) -> Color {
        if isSelected { return .white }
        switch seat.state {
        case .available, .selected: return accent
        case .taken, .unavailable: return .secondary
        }
    }
}

// MARK: - Timeline

/// Vertical timeline with a leading rail: filled accent dots for past entries, a ringed dot
/// for the current one, hollow gray for future — connected by a thin rail line.
struct HermesTimelineView: View {
    let entries: [HermesTimelineEntry]
    @Environment(\.hermesAccent) private var accent

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 0) {
                        dot(for: entry)
                        if index < entries.count - 1 {
                            Rectangle()
                                .fill(railColor(entry))
                                .frame(width: 2)
                                .frame(minHeight: 18)
                        }
                    }
                    .frame(width: 22)

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(entry.title)
                                // ADA rule 6 (dim what isn't now): past recedes to secondary,
                                // future to tertiary, the NOW entry is full-contrast + bold.
                                .font(.subheadline.weight(entry.state == .current ? .semibold : .regular))
                                .foregroundStyle(titleStyle(entry.state))
                            if let time = entry.time {
                                Spacer(minLength: 8)
                                Text(time)
                                    .font(.caption.weight(.medium).monospacedDigit())
                                    .foregroundStyle(entry.state == .current ? AnyShapeStyle(accent) : AnyShapeStyle(.secondary))
                            }
                        }
                        if let subtitle = entry.subtitle {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(entry.state == .future ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary))
                        }
                    }
                    // The "now" spotlight: the current step floats on a tinted surface.
                    .padding(.vertical, entry.state == .current ? 7 : 0)
                    .padding(.horizontal, entry.state == .current ? 11 : 0)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(entry.state == .current ? accent.opacity(0.10) : .clear)
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, index < entries.count - 1 ? 14 : 0)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private func dot(for entry: HermesTimelineEntry) -> some View {
        ZStack {
            switch entry.state {
            case .past:
                Circle().fill(accent).frame(width: 12, height: 12)
            case .current:
                Circle().stroke(accent, lineWidth: 2.5).frame(width: 14, height: 14)
                Circle().fill(accent).frame(width: 6, height: 6)
            case .future:
                Circle().stroke(Color(.systemGray3), lineWidth: 2).frame(width: 12, height: 12)
            }
            if let icon = entry.iconSystemName, entry.state == .past {
                Image(systemName: icon)
                    .font(.system(size: 6, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(height: 16)
    }

    private func railColor(_ entry: HermesTimelineEntry) -> Color {
        entry.state == .past ? accent.opacity(0.5) : Color(.systemGray4)
    }

    private func titleStyle(_ state: HermesTimelineEntry.State) -> AnyShapeStyle {
        switch state {
        case .current: return AnyShapeStyle(.primary)
        case .past:    return AnyShapeStyle(.secondary)
        case .future:  return AnyShapeStyle(.tertiary)
        }
    }
}

// MARK: - Option picker (generalized select-then-confirm)

/// The generalized seat-chart interaction for arbitrary options: tapping an option only
/// changes local selection (visible fill/border + checkmark), and the standard
/// `HermesPrimaryCTA` commits it. This is THE way any HermesShare card asks the user to
/// choose one of several things — never bare tap-to-fire rows.
struct HermesOptionPickerView: View {
    let options: [HermesPickerOption]
    let confirmLabel: String?
    let style: HermesPickerStyle
    @State private var selectedId: String?
    @Environment(\.hermesAccent) private var accent
    @Environment(\.hermesOnAction) private var onAction

    init(options: [HermesPickerOption], initialSelectedId: String?,
         confirmLabel: String?, style: HermesPickerStyle) {
        self.options = options
        self.confirmLabel = confirmLabel
        self.style = style
        _selectedId = State(initialValue: initialSelectedId)
    }

    private var selectedOption: HermesPickerOption? {
        options.first { $0.id == selectedId }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch style {
            case .list:
                VStack(spacing: 8) {
                    ForEach(options, id: \.id) { option in
                        optionRow(option)
                    }
                }
            case .grid:
                let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(options, id: \.id) { option in
                        gridCell(option)
                    }
                }
            }

            HermesPrimaryCTA(
                label: ctaLabel,
                systemImage: "checkmark.seal.fill",
                isEnabled: selectedId != nil
            ) {
                guard let option = selectedOption else { return }
                onAction(HermesAction(
                    id: "option-confirm",
                    label: "\(confirmLabel ?? "Confirm"): \(option.label)",
                    systemImage: "checkmark.seal.fill",
                    deepLinkURL: "hermesshare://action?id=option-confirm&option=\(option.id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? option.id)"
                ))
            }
        }
    }

    private var ctaLabel: String {
        if let option = selectedOption {
            return "\(confirmLabel ?? "Confirm") — \(option.label)"
        }
        return "Select an option"
    }

    private func toggle(_ option: HermesPickerOption) {
        guard !option.disabled else { return }
        withAnimation(.snappy(duration: 0.2)) {
            selectedId = (selectedId == option.id) ? nil : option.id
        }
    }

    @ViewBuilder private func optionRow(_ option: HermesPickerOption) -> some View {
        let isSelected = option.id == selectedId
        HStack(spacing: 10) {
            optionLeading(option, isSelected: isSelected)
            VStack(alignment: .leading, spacing: 1) {
                Text(option.label)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(option.disabled ? Color.secondary : .primary)
                if let sublabel = option.sublabel {
                    Text(sublabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if let badge = option.badge {
                Text(badge)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(isSelected ? accent : .secondary)
            }
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20))
                .foregroundStyle(isSelected ? accent : Color(.systemGray3))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? accent.opacity(0.10) : Color(.tertiarySystemFill))
                .stroke(isSelected ? accent : .clear, lineWidth: 1.5)
        )
        .opacity(option.disabled ? 0.4 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture { toggle(option) }
        .accessibilityLabel("\(option.label)\(isSelected ? ", selected" : "")")
        .accessibilityAddTraits(option.disabled ? [] : .isButton)
    }

    @ViewBuilder private func gridCell(_ option: HermesPickerOption) -> some View {
        let isSelected = option.id == selectedId
        VStack(spacing: 6) {
            if let imageUrl = option.imageUrl {
                HermesRemoteImage(urlString: imageUrl, fallbackSystemImage: option.systemImage ?? "photo")
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(isSelected ? accent : Color.clear, lineWidth: 2)
                    )
            } else if let systemImage = option.systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(isSelected ? accent : .secondary)
            }
            Text(option.label)
                .font(.subheadline.weight(isSelected ? .semibold : .medium))
                .foregroundStyle(option.disabled ? Color.secondary : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let sublabel = option.sublabel ?? option.badge {
                Text(sublabel)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? accent : .secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? accent.opacity(0.10) : Color(.tertiarySystemFill))
                .stroke(isSelected ? accent : .clear, lineWidth: 1.5)
        )
        .opacity(option.disabled ? 0.4 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture { toggle(option) }
        .accessibilityLabel("\(option.label)\(isSelected ? ", selected" : "")")
        .accessibilityAddTraits(option.disabled ? [] : .isButton)
    }

    @ViewBuilder private func optionLeading(_ option: HermesPickerOption, isSelected: Bool) -> some View {
        if let imageUrl = option.imageUrl {
            HermesRemoteImage(urlString: imageUrl, fallbackSystemImage: option.systemImage ?? "photo")
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isSelected ? accent : Color(.separator).opacity(0.35), lineWidth: 1)
                )
        } else if let systemImage = option.systemImage {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(isSelected ? accent : .secondary)
                .frame(width: 24)
        }
    }
}

// MARK: - Remote image with a dark skeleton (for photo-forward dark cards)

/// AsyncImage whose loading/failure state is a DARK neutral skeleton + glyph, not the system
/// default `tertiarySystemFill` (a light-gray box that reads as "broken" on a dark/atmosphere
/// card). Used by the photo catalog's full-bleed heroes and room tiles.
struct HermesRemoteImage: View {
    let urlString: String?
    var fallbackSystemImage: String = "photo"
    @Environment(\.hermesAccent) private var accent

    var body: some View {
        // A flexible sized BASE (Rectangle takes exactly the frame the caller gives it) with the
        // image as a CLIPPED OVERLAY. An overlay never propagates its intrinsic size to the base,
        // so a huge or extreme-aspect remote photo can't blow up the layout — the earlier
        // `ZStack { Color; image.fill }` let an oversized image destabilize the frame and throw
        // the whole card off-screen on scroll/tap.
        Rectangle()
            .fill(Color(red: 0.08, green: 0.083, blue: 0.10))
            .overlay {
                if let urlString, let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case let .success(image):
                            image.resizable().scaledToFill()
                        case .empty:
                            ProgressView().controlSize(.small).tint(.white.opacity(0.5))
                        default:
                            glyph
                        }
                    }
                } else {
                    glyph
                }
            }
            .clipped()
            .contentShape(Rectangle())
    }

    private var glyph: some View {
        Image(systemName: fallbackSystemImage)
            .font(.system(size: 26, weight: .medium))
            .foregroundStyle(.white.opacity(0.35))
    }
}

// MARK: - Collapsible section (generic expand/collapse)

/// Tap-to-expand section with optional leading photo. Stack several in a `vstack` for
/// multi-section cards where each section can contain any node subtree.
struct HermesCollapsibleView: View {
    let id: String
    let title: String
    let subtitle: String?
    let imageUrl: String?
    let badge: String?
    let initiallyExpanded: Bool
    let child: HermesNode

    @State private var isExpanded: Bool
    @Environment(\.hermesAccent) private var accent

    init(id: String, title: String, subtitle: String?, imageUrl: String?, badge: String?,
         initiallyExpanded: Bool, child: HermesNode) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.imageUrl = imageUrl
        self.badge = badge
        self.initiallyExpanded = initiallyExpanded
        self.child = child
        _isExpanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    HermesNodeView(node: child)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(.separator).opacity(0.35), lineWidth: 0.5)
        )
        .animation(.snappy(duration: 0.25), value: isExpanded)
    }

    private var header: some View {
        Button {
            withAnimation(.snappy(duration: 0.25)) { isExpanded.toggle() }
        } label: {
            HStack(spacing: 10) {
                if let imageUrl {
                    HermesRemoteImage(urlString: imageUrl, fallbackSystemImage: "photo")
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 4)
                if let badge {
                    Text(badge)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(accent)
                }
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(isExpanded ? "expanded" : "collapsed")")
    }
}

// MARK: - Photo catalog (Airbnb-style expandable listing cards)

/// A vertical catalog of full-bleed, photo-forward cards. Collapsed: the hero photo IS the card,
/// with a solid price pill and name over a bottom scrim. Tapping expands it (accordion — one
/// open at a time) into a drawer with a horizontal gallery of the item's rooms; tapping a room
/// promotes its photo to the hero and swaps the price. Selection is ephemeral @State, same model
/// as HermesSeatChartView.
struct HermesPhotoCatalogView: View {
    let items: [HermesCatalogItem]
    let confirmLabel: String?
    @Environment(\.hermesAccent) private var accent
    @Environment(\.hermesOnAction) private var onAction

    @State private var expandedId: String?
    @State private var selectedRoom: [String: String]

    init(items: [HermesCatalogItem], initialExpandedId: String?, confirmLabel: String?) {
        self.items = items
        self.confirmLabel = confirmLabel
        _expandedId = State(initialValue: initialExpandedId)
        // Default each card's selected room to its first room.
        var defaults: [String: String] = [:]
        for item in items { if let first = item.rooms.first { defaults[item.id] = first.id } }
        _selectedRoom = State(initialValue: defaults)
    }

    var body: some View {
        VStack(spacing: 14) {
            ForEach(items, id: \.id) { item in
                card(item)
            }
        }
    }

    private func room(for item: HermesCatalogItem) -> HermesCatalogRoom? {
        guard let id = selectedRoom[item.id] else { return item.rooms.first }
        return item.rooms.first { $0.id == id } ?? item.rooms.first
    }

    @ViewBuilder private func card(_ item: HermesCatalogItem) -> some View {
        let isOpen = expandedId == item.id
        let selected = room(for: item)
        let heroURL = (isOpen ? selected?.imageUrl : nil) ?? item.heroImageUrl
        let pillText = isOpen ? (selected?.price ?? item.priceText) : item.priceText
        let titleSuffix = (isOpen && selected != nil) ? " · \(selected!.name)" : ""

        VStack(spacing: 0) {
            hero(item, heroURL: heroURL, pillText: pillText, titleSuffix: titleSuffix, isOpen: isOpen)
            if isOpen {
                drawer(item, selected: selected)
            }
        }
        .background(Color(red: 0.07, green: 0.073, blue: 0.09))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    // The full-bleed hero. Collapsed: whole thing toggles open. Open: only the chevron collapses.
    @ViewBuilder private func hero(_ item: HermesCatalogItem, heroURL: String?, pillText: String?,
                                   titleSuffix: String, isOpen: Bool) -> some View {
        // The hero is a FIXED 210pt box (the image is a clipped overlay in HermesRemoteImage);
        // every decoration is an `.overlay(alignment:)` on that box, so nothing here can change
        // the card's height or push the layout around — the source of the scroll/tap jumping.
        HermesRemoteImage(urlString: heroURL, fallbackSystemImage: item.fallbackSystemImage ?? "bed.double.fill")
            .frame(height: 210)
            .frame(maxWidth: .infinity)
            .clipped()
            // Bottom scrim so the name is legible over any photo.
            .overlay {
                LinearGradient(
                    stops: [.init(color: .clear, location: 0),
                            .init(color: .black.opacity(0.35), location: 0.55),
                            .init(color: .black.opacity(0.9), location: 1)],
                    startPoint: .top, endPoint: .bottom)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 3) {
                    if let subtitle = item.subtitle {
                        Text(subtitle.uppercased())
                            .font(.system(size: 11, weight: .semibold))
                            .kerning(1.1)
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1)
                    }
                    Text(item.title + titleSuffix)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                }
                .padding(16)
            }
            .overlay(alignment: .topTrailing) {
                pricePill(pillText, unit: item.priceUnit, collapsed: !isOpen).padding(12)
            }
            .overlay(alignment: .bottomTrailing) {
                affordance(count: item.rooms.count, isOpen: isOpen) {
                    withAnimation(.snappy(duration: 0.28)) { expandedId = isOpen ? nil : item.id }
                }
                .padding(12)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                // When open, the hero is inert — only the chevron collapses (avoids eating room taps).
                guard !isOpen else { return }
                withAnimation(.snappy(duration: 0.28)) { expandedId = item.id }
            }
    }

    @ViewBuilder private func pricePill(_ text: String?, unit: String?, collapsed: Bool) -> some View {
        if let text {
            HStack(spacing: 3) {
                Text(text)
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(accent)
                if let unit {
                    Text("/ \(unit)")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color(red: 0.106, green: 0.11, blue: 0.122).opacity(0.92)))
            .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 0.5))
        }
    }

    @ViewBuilder private func affordance(count: Int, isOpen: Bool, onToggle: @escaping () -> Void) -> some View {
        HStack(spacing: 5) {
            if count > 0, !isOpen {
                Image(systemName: "photo.stack.fill").font(.system(size: 10, weight: .semibold))
                Text("\(count)").font(.system(size: 11, weight: .semibold)).monospacedDigit()
            }
            Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                .font(.system(size: 11, weight: .bold))
        }
        .foregroundStyle(.white.opacity(0.9))
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Capsule().fill(.ultraThinMaterial))
        .environment(\.colorScheme, .dark)
        .contentShape(Capsule())
        .onTapGesture(perform: onToggle)   // works whether open (collapse) or closed (expand)
    }

    // The drawer below the hero — solid dark surface, never over the photo.
    @ViewBuilder private func drawer(_ item: HermesCatalogItem, selected: HermesCatalogRoom?) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)

            if !item.rooms.isEmpty {
                HStack {
                    Text("ROOMS")
                        .font(.system(size: 11, weight: .semibold)).kerning(1.1)
                        .foregroundStyle(.white.opacity(0.5))
                    Spacer()
                    Text("swipe →").font(.caption2).foregroundStyle(.white.opacity(0.35))
                }
                roomStrip(item, selected: selected)
            }

            if let tags = item.tags, !tags.isEmpty {
                amenityChips(tags)
            }

            if let detail = item.detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let confirmLabel {
                HermesPrimaryCTA(label: "\(confirmLabel) — \(item.title)", systemImage: "calendar.badge.checkmark") {
                    let roomPart = selected.map { "&room=\($0.id)" } ?? ""
                    onAction(HermesAction(
                        id: "catalog-confirm",
                        label: "\(confirmLabel): \(item.title)\(selected.map { " · \($0.name)" } ?? "")",
                        systemImage: "calendar.badge.checkmark",
                        deepLinkURL: "hermesshare://action?id=catalog-confirm&item=\(item.id)\(roomPart)"
                    ))
                }
                .environment(\.colorScheme, .dark)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.07, green: 0.075, blue: 0.093))
    }

    @ViewBuilder private func roomStrip(_ item: HermesCatalogItem, selected: HermesCatalogRoom?) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(item.rooms, id: \.id) { r in
                    let isSel = r.id == selected?.id
                    VStack(alignment: .leading, spacing: 5) {
                        HermesRemoteImage(urlString: r.imageUrl, fallbackSystemImage: item.fallbackSystemImage ?? "bed.double.fill")
                            .frame(width: 118, height: 84)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(alignment: .topTrailing) {
                                if isSel {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundStyle(accent)
                                        .background(Circle().fill(.black.opacity(0.4)))
                                        .padding(5)
                                }
                            }
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(isSel ? accent : Color.white.opacity(0.08), lineWidth: isSel ? 2 : 0.5)
                            )
                        Text(r.name)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if let price = r.price {
                            Text(price)
                                .font(.caption2.weight(.semibold)).monospacedDigit()
                                .foregroundStyle(accent)
                        }
                    }
                    .frame(width: 118)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.snappy(duration: 0.2)) { selectedRoom[item.id] = r.id }
                    }
                }
            }
        }
    }

    @ViewBuilder private func amenityChips(_ tags: [String]) -> some View {
        let shown = Array(tags.prefix(4))
        let overflow = tags.count - shown.count
        HermesFlowLayout(spacing: 6, rowSpacing: 6) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, tag in
                Text(tag)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
            }
            if overflow > 0 {
                Text("+\(overflow)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Capsule().fill(accent.opacity(0.15)))
            }
        }
    }
}

// MARK: - Media list (ranked rows with leading artwork)

/// A ranked list of media rows, each an Apple-Music-style row: rank numeral, a square artwork
/// thumbnail (AsyncImage with an SF-Symbol fallback so it's never a blank box), title/subtitle,
/// and a trailing value. The `image` node is a full-width hero and lays out badly inline; this
/// is the primitive for "top N songs / movies / products" content.
struct HermesMediaListView: View {
    let items: [HermesMediaItem]
    @Environment(\.hermesAccent) private var accent

    var body: some View {
        VStack(spacing: 12) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                if index > 0 {
                    Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1)
                }
                row(item)
            }
        }
    }

    @ViewBuilder private func row(_ item: HermesMediaItem) -> some View {
        HStack(spacing: 12) {
            if let rank = item.rank {
                Text("\(rank)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 20, alignment: .center)
            }
            artwork(item)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let trailing = item.trailing {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(trailing)
                        .font(.subheadline.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                    if let ts = item.trailingSub {
                        Text(ts.uppercased())
                            .font(.system(size: 9, weight: .semibold))
                            .kerning(0.6)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11y(item))
    }

    private func a11y(_ item: HermesMediaItem) -> String {
        var s = ""
        if let r = item.rank { s += "Number \(r), " }
        s += item.title
        if let sub = item.subtitle { s += " by \(sub)" }
        if let t = item.trailing { s += ", \(t)\(item.trailingSub.map { " \($0)" } ?? "")" }
        return s
    }

    @ViewBuilder private func artwork(_ item: HermesMediaItem) -> some View {
        let fallback = item.fallbackSystemImage ?? "music.note"
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(accent.opacity(0.16))
            .frame(width: 52, height: 52)
            .overlay {
                if let urlString = item.imageUrl, let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case let .success(image):
                            image.resizable().aspectRatio(contentMode: .fill)
                        case .empty:
                            ProgressView().controlSize(.small)
                        default:
                            Image(systemName: fallback)
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(accent)
                        }
                    }
                } else {
                    Image(systemName: fallback)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(accent)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
    }
}

// MARK: - Quick-reply chips

/// One-tap committing chips, styled like iMessage's own pinned-contact avatars: a circular
/// gradient-tinted icon bubble with a short label underneath, laid out in a wrapping,
/// centered flow (never a single-row horizontal scroll a user has to discover).
struct HermesQuickReplyRowView: View {
    let options: [HermesQuickReplyOption]
    @Environment(\.hermesAccent) private var accent
    @Environment(\.hermesOnAction) private var onAction

    var body: some View {
        HermesFlowLayout(spacing: 16, rowSpacing: 14) {
            ForEach(options, id: \.id) { option in
                Button {
                    onAction(HermesAction(
                        id: option.id,
                        label: option.label,
                        systemImage: option.systemImage,
                        deepLinkURL: option.deepLinkURL ?? "hermesshare://action?id=\(option.id)"
                    ))
                } label: {
                    VStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [avatarColor(for: option).opacity(0.9), avatarColor(for: option)],
                                        startPoint: .top, endPoint: .bottom
                                    )
                                )
                                .frame(width: 56, height: 56)
                            if let sym = option.systemImage {
                                Image(systemName: sym)
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundStyle(.white)
                            } else {
                                Text(initials(for: option.label))
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        Text(option.label)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .frame(width: 72)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Deterministic per-option tint (derived from the option id, so the same option always
    /// gets the same color across renders) — same spirit as iMessage's per-contact avatar tint.
    private func avatarColor(for option: HermesQuickReplyOption) -> Color {
        let palette: [Color] = [accent, .blue, .purple, .orange, .pink, .teal, .indigo]
        let hash = option.id.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return palette[hash % palette.count]
    }

    private func initials(for label: String) -> String {
        let words = label.split(separator: " ")
        let letters = words.prefix(2).compactMap { $0.first }
        return String(letters).uppercased()
    }
}

/// A simple wrapping flow layout (like iMessage's tapback/suggested-reply pill grid): lays
/// children left-to-right, wrapping to a new row when the current row would overflow the
/// available width. Rows are NOT stretched to fill width — pills stay their natural size and
/// the whole flow is centered, matching how iMessage centers its own suggestion pills.
struct HermesFlowLayout: Layout {
    var spacing: CGFloat = 8
    var rowSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = arrangeRows(subviews: subviews, maxWidth: maxWidth)

        var totalHeight: CGFloat = 0
        var maxRowWidth: CGFloat = 0
        for row in rows {
            var rowHeight: CGFloat = 0
            var rowWidth: CGFloat = 0
            for (index, item) in row.enumerated() {
                rowHeight = max(rowHeight, item.size.height)
                rowWidth += item.size.width
                if index > 0 { rowWidth += spacing }
            }
            totalHeight += rowHeight
            if totalHeight > rowHeight { totalHeight += rowSpacing } // add gap before this row, not after the last
            maxRowWidth = max(maxRowWidth, rowWidth)
        }
        return CGSize(width: min(maxRowWidth, maxWidth), height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrangeRows(subviews: subviews, maxWidth: bounds.width)
        var y = bounds.minY
        for row in rows {
            var rowWidth: CGFloat = 0
            var rowHeight: CGFloat = 0
            for (index, item) in row.enumerated() {
                rowWidth += item.size.width
                if index > 0 { rowWidth += spacing }
                rowHeight = max(rowHeight, item.size.height)
            }
            var x = bounds.minX + max(0, (bounds.width - rowWidth) / 2) // center each row, like iMessage's pills
            for item in row {
                item.subview.place(
                    at: CGPoint(x: x, y: y + (rowHeight - item.size.height) / 2),
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + spacing
            }
            y += rowHeight + rowSpacing
        }
    }

    private struct Item { let subview: LayoutSubview; let size: CGSize }

    private func arrangeRows(subviews: Subviews, maxWidth: CGFloat) -> [[Item]] {
        var rows: [[Item]] = []
        var current: [Item] = []
        var currentWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let addedWidth = size.width + (current.isEmpty ? 0 : spacing)
            if !current.isEmpty, currentWidth + addedWidth > maxWidth {
                rows.append(current)
                current = []
                currentWidth = 0
            }
            current.append(Item(subview: subview, size: size))
            currentWidth += size.width + (current.count > 1 ? spacing : 0)
        }
        if !current.isEmpty { rows.append(current) }
        return rows
    }
}

// MARK: - Accent color environment

private struct HermesAccentKey: EnvironmentKey {
    static let defaultValue: Color = .accentColor
}

public extension EnvironmentValues {
    // Public so hosts that build HermesPrimaryCTA outside the renderer (the extension's
    // pinned action bar, the test harness) can hand it the accent for label-color logic.
    var hermesAccent: Color {
        get { self[HermesAccentKey.self] }
        set { self[HermesAccentKey.self] = newValue }
    }
}

// MARK: - Action environment (lets nested interactive nodes fire actions)

private struct HermesOnActionKey: EnvironmentKey {
    static let defaultValue: (HermesAction) -> Void = HermesActionHandler.openDeepLink
}

extension EnvironmentValues {
    var hermesOnAction: (HermesAction) -> Void {
        get { self[HermesOnActionKey.self] }
        set { self[HermesOnActionKey.self] = newValue }
    }
}

// MARK: - Action handling

public enum HermesActionHandler {
    /// Opens the action's deep-link URL. In the extension this rides through
    /// `MSMessagesAppViewController` (see the extension target); here we provide a UIKit
    /// fallback used by the host app's debug screen.
    ///
    /// TODO(hermes-roundtrip): actually delivering the tap back to the Hermes/Photon backend
    /// (POST to a webhook) is future work — see README "NEXT STEPS". For v1 we just open the URL.
    public static func openDeepLink(_ action: HermesAction) {
        guard let url = URL(string: action.deepLinkURL) else { return }
        #if canImport(UIKit)
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
        #endif
    }
}

#if canImport(UIKit)
import UIKit
#endif
