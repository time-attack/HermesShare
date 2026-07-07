// HermesLayout.swift
// The declarative JSON schema HermesShare renders. Hermes (the agent) generates a
// `HermesLayout` JSON document per message; this file defines the fixed vocabulary of
// native SwiftUI primitives that document can describe. No new Swift/binary code is ever
// compiled or executed on-device — this mirrors how Scriptable/Widgy work: a fixed native
// renderer interprets a data-driven layout, it does not eval/compile arbitrary code.

import Foundation
import CoreGraphics

// MARK: - Root document

public struct HermesLayout: Codable, Equatable, Sendable {
    public var version: Int
    public var title: String?
    public var subtitle: String?
    public var accentColorHex: String?          // e.g. "#34C759" — drives tint for this card
    public var background: HermesBackground?
    public var root: HermesNode
    public var actions: [HermesAction]?          // tappable actions the card can trigger (deep-link back to Hermes)

    public init(
        version: Int = 1,
        title: String? = nil,
        subtitle: String? = nil,
        accentColorHex: String? = nil,
        background: HermesBackground? = nil,
        root: HermesNode,
        actions: [HermesAction]? = nil
    ) {
        self.version = version
        self.title = title
        self.subtitle = subtitle
        self.accentColorHex = accentColorHex
        self.background = background
        self.root = root
        self.actions = actions
    }
}

public struct HermesBackground: Codable, Equatable, Sendable {
    /// `atmosphere` (v5) turns the whole card into a dark instrument-bay scene: near-black
    /// base with a tinted radial glow (colorsHex[0], else the accent). Content renders in
    /// dark mode on top of it, so scene panels and grouped cards read as one world instead
    /// of gray boxes on white ("the scene is the screen", ADA rule 10).
    public enum Kind: String, Codable { case plain, gradient, atmosphere }
    public var kind: Kind
    public var colorsHex: [String]?             // gradient: 2+ hex top-to-bottom; atmosphere: [0] = glow tint

    public init(kind: Kind, colorsHex: [String]? = nil) {
        self.kind = kind
        self.colorsHex = colorsHex
    }
}

// MARK: - Step 0 — the four ADA questions, answered per card genre
//
// (Required by ada-swiftui-design SKILL Step 0. Answered honestly here BEFORE the redesign,
// grouped by what a card actually REPRESENTS — not by literal node type. These answers drove
// the scene/instrument centerpieces below: `flightBoard`, `platedDish`, `gaugeCluster`, the
// cabin-framed `seatChart`, and the now-spotlight `timeline`.)
//
// GENRE 1 — Flight / travel (pre-flight checklist, boarding, itinerary legs)
//   QUESTION    : "Is my flight on track, and where do I need to be?"
//   METAPHOR    : the airport split-flap departure board + a boarding pass. Airports own
//                 mechanical flip-tile signage, 3-letter IATA codes, gate/time columns.
//   TEMPERATURE : clinical-urgent. Near-black instrument panel, state hue for status.
//   STAGE       : yes — a route between two airports over the world. The board carries a live
//                 route strip with the plane at its ACTUAL progress. Centerpiece: `flightBoard`
//                 (custom split-flap tiles drawn from Rectangle/gradient geometry, rule 7/10).
//
// GENRE 2 — Recipe / food
//   QUESTION    : "What am I making, and is it ready?"
//   METAPHOR    : an editorial cookbook plate shot — the dish itself, plated, steaming.
//   TEMPERATURE : warm. Warm counter light, food hue, rising steam = fresh/hot state.
//   STAGE       : yes — a plated dish on a counter. Centerpiece: `platedDish` (procedural
//                 Canvas: plate rim + well + food mound + seeded garnish specks + blurred
//                 steam wisps), Architecture B (full-bleed scene header, content below).
//
// GENRE 3 — Seat / option pickers
//   QUESTION    : "Which one do I pick?"
//   METAPHOR    : a boarding-pass seat map inside the aircraft cabin.
//   TEMPERATURE : clinical. The seat grid is already a real instrument; pushed further with a
//                 drawn fuselage frame + window ports + FRONT marker so it reads as the cabin
//                 you're choosing a seat IN, not a flat grid (rule 7 physical / rule 10 scene).
//
// GENRE 4 — Itinerary / timeline
//   QUESTION    : "What's happening now, and what's next?"
//   METAPHOR    : a transit/departure timeline rail.
//   TEMPERATURE : calm-clinical. Contextual dimming (rule 6): past recedes, the NOW entry gets
//                 a spotlight surface + accent rail. Verified against the bar, not regressed.
//
// GENRE 5 — Comparison / stat
//   QUESTION    : "How is it doing vs. the target?"
//   METAPHOR    : a finance / cockpit instrument cluster — arc gauges with needles and ticks.
//   TEMPERATURE : clinical. Centerpiece: `gaugeCluster` (arc gauges, 270° sweep, tick marks,
//                 lit value arc, hero numeral) — replaces flat same-weight stat tiles (rule 1).
//
// GENRE 6 — Delivery / ride / transit (v5)
//   QUESTION    : "Where is it, and when does it get to me?"
//   METAPHOR    : a courier dispatch map — the journey itself, drawn as a route arc.
//   TEMPERATURE : clinical-warm. Dark dispatch panel, state hue on the traveled arc.
//   STAGE       : yes — the road between origin and destination. Centerpiece: `journeyArc`
//                 (dashed route arc, lit traveled trail, the vehicle at its REAL progress).
//
// GENRE 7 — Weather / forecast (v5)
//   QUESTION    : "What's the sky doing, and what should I feel about it?"
//   METAPHOR    : the sky itself. Weather apps that win awards draw the weather.
//   TEMPERATURE : matches the condition — warm sun, cold slate rain, indigo night.
//   STAGE       : yes — the sky IS the stage. Centerpiece: `skyScene` (procedural Canvas:
//                 condition-keyed gradient, sun/moon/stars/clouds/rain/snow, hero temperature).
//
// GENRE 8 — Event / booking / reservation (v5)
//   QUESTION    : "What did I get into, and what do I show at the door?"
//   METAPHOR    : the physical ticket stub — perforation, barcode, ADMIT-ONE typography.
//   TEMPERATURE : celebratory-clinical. A keepsake object, not a summary table.
//   STAGE       : the ticket is the object itself. Centerpiece: `eventTicket` (drawn notched
//                 stub shape, perforation, seeded barcode, serif marquee title).
//
// GENRE 9 — Market / trend / time series (v5)
//   QUESTION    : "Which way is it moving, and how hard?"
//   METAPHOR    : a trading terminal tile — sparkline, hero price, signed delta.
//   TEMPERATURE : clinical. Trend hue (gain green / loss red) as information, never decoration.
//   STAGE       : the chart pane. Centerpiece: `sparkline` (smoothed lit path, gradient area,
//                 glowing endpoint dot at the latest value).
//
// GENRE 10 — Score / matchup (v5)
//   QUESTION    : "Who's winning, and is it over?"
//   METAPHOR    : the arena scoreboard — split-flap digits, team colors, a status clock.
//   TEMPERATURE : clinical-urgent. Loser dims (rule 6 contextual dimming), winner stays lit.
//   STAGE       : the scoreboard. Centerpiece: `scoreBoard` (flap-tile scores reusing the
//                 flight board's mechanical tiles, team hue chips, center status pill).
//
// MARK: - Node tree (the fixed widget vocabulary)

public indirect enum HermesNode: Codable, Equatable, Sendable {
    case vstack(spacing: CGFloat, alignment: String?, children: [HermesNode])
    case hstack(spacing: CGFloat, alignment: String?, children: [HermesNode])
    case text(String, style: HermesTextStyle)
    case icon(systemName: String, sizePt: CGFloat, colorHex: String?)
    case statusBadge(label: String, colorHex: String)
    case progressRing(value: Double, label: String?, colorHex: String?)   // 0.0...1.0
    case progressBar(value: Double, colorHex: String?)
    case divider
    case spacer(minLength: CGFloat?)
    case keyValueRow(key: String, value: String, iconSystemName: String? = nil)
    case mapPreview(latitude: Double, longitude: Double, label: String?)  // static map snapshot, no live MapKit session
    case image(url: String, aspectRatio: Double?, cornerRadius: CGFloat?)
    case card(padding: CGFloat, cornerRadius: CGFloat, backgroundHex: String?, child: HermesNode)
    case seatChart(rows: [HermesSeatRow], selectedSeatId: String?)   // interactive picker: tap selects locally, a separate primary CTA commits
    case quickReplyRow(options: [HermesQuickReplyOption])            // single-tap chips: tapping immediately composes+inserts a reply

    // v3 vocabulary — richer content primitives.

    /// Checklist with per-item state (checked / unchecked / none). Use for packing lists,
    /// task lists, prep steps — anywhere "done vs pending" matters.
    case checklist(items: [HermesChecklistItem])
    /// Vertical timeline with a leading rail (itineraries, order tracking, multi-leg trips).
    case timeline(entries: [HermesTimelineEntry])
    /// Star rating (value out of maxValue stars, half-stars supported) with optional label.
    case rating(value: Double, maxValue: Int, label: String?, colorHex: String?)
    /// Simple text grid with an optional header row. Use for comparisons and specs.
    case table(headers: [String]?, rows: [[String]])
    /// Horizontally scrolling strip of images (media galleries).
    case gallery(urls: [String], heightPt: CGFloat?, cornerRadius: CGFloat?)
    /// Row of small non-interactive capsule tags (ingredients, amenities, genres).
    case tagRow(labels: [String], colorHex: String?)
    /// One big-number stat tile (value + caption + optional icon). Compose several in an hstack.
    case stat(value: String, label: String, iconSystemName: String?, colorHex: String?)
    /// Calendar-page date glyph (month abbreviation over a large day number).
    case dateBadge(month: String, day: String, weekday: String?, colorHex: String?)
    /// Person row: initials/photo avatar + name + optional detail line.
    case person(name: String, detail: String?, imageUrl: String?, colorHex: String?)
    /// Simple horizontal bar chart (polls, comparisons). Values are relative; the longest
    /// bar fills the width unless maxValue is given.
    case barChart(bars: [HermesBar], maxValue: Double?)
    /// SELECT-THEN-CONFIRM picker (the generalized seatChart interaction): tapping an option
    /// only highlights it locally; a separate primary CTA labeled `confirmLabel` commits the
    /// selection as a reply. REQUIRED for any card that asks the user to choose something.
    case optionPicker(options: [HermesPickerOption], selectedId: String?, confirmLabel: String?, style: HermesPickerStyle)

    // v4 — real ADA scene/instrument centerpieces (custom-drawn, encode real state). See the
    // Step 0 block above. Each is the HERO of its card genre, not a retint of a flat element.

    /// Airport split-flap departure board: flip-tile IATA codes, a live route strip with the
    /// plane at its actual progress, and DEPARTS/GATE/ARRIVES columns. Flight-card centerpiece.
    case flightBoard(HermesFlightBoard)
    /// Procedurally-drawn plated dish (Canvas): plate + food mound + seeded garnish + steam.
    /// Editorial cookbook hero for recipe cards.
    case platedDish(HermesPlatedDish)
    /// A cluster of arc gauges (finance/cockpit instrument look) — the comparison/stat hero.
    case gaugeCluster(gauges: [HermesGauge])

    /// A ranked list of media rows, each with a leading square artwork thumbnail (album cover,
    /// movie poster, product shot, avatar), a rank numeral, title/subtitle, and a trailing
    /// value. THE shape for "top N <things>" content — a bare barChart throws away the artwork
    /// and the per-item detail that make a ranking recognizable.
    case mediaList(items: [HermesMediaItem])

    /// An Airbnb-style catalog of large, photo-forward cards (hotels, rentals, restaurants,
    /// listings). Each card is a full-bleed hero photo with a solid price pill + name over a
    /// scrim; tapping expands it (accordion) to reveal a horizontal gallery of that item's
    /// photos (rooms) — tapping a photo promotes it to the hero. THE shape for "show me a
    /// browsable catalog with different pictures when I pick one." `initialExpandedId` opens
    /// one card by default; `confirmLabel` adds a per-card commit CTA.
    case photoCatalog(items: [HermesCatalogItem], initialExpandedId: String?, confirmLabel: String?)

    /// A single expandable section: header row (optional photo + title) reveals nested content
    /// on tap. Stack several in a `vstack` for multi-section cards (itineraries, FAQs, plans).
    /// Unlike `photoCatalog` (listing accordion), each section can contain any node subtree.
    case collapsible(id: String, title: String, subtitle: String?, imageUrl: String?,
                     badge: String?, initiallyExpanded: Bool, child: HermesNode)

    // v5 — scene expansion (Step 0 genres 6–10 above). Same doctrine as v4: each is a
    // custom-drawn, state-encoding hero for its genre, never a restyled flat element.

    /// Dispatch-panel route arc with the vehicle at its real progress. Delivery/ride/transit hero.
    case journeyArc(HermesJourneyArc)
    /// Procedurally-drawn sky (condition-keyed gradient + sun/moon/stars/clouds/precipitation)
    /// with a hero temperature numeral. Weather-card hero.
    case skyScene(HermesSkyScene)
    /// Drawn ticket stub: notched outline, perforation, seeded barcode. Event/booking hero.
    case eventTicket(HermesEventTicket)
    /// Trading-terminal trend tile: hero value, signed delta pill, lit sparkline. Market hero.
    case sparkline(HermesSparkline)
    /// Arena scoreboard with split-flap score digits and team hue chips. Matchup hero.
    case scoreBoard(HermesScoreBoard)

    /// Forward compatibility: a node whose `type` this build doesn't know decodes to this
    /// (and renders as a visible "update HermesShare" chip) instead of failing the whole
    /// card. Honest-by-design per the no-silent-fallback rule: the gap is on screen, named,
    /// and the rest of the card still renders. Re-encoding preserves the type name only.
    case unsupported(typeName: String)

    // Codable conformance is hand-written in HermesLayoutCodable.swift (kept separate for
    // readability — the enum-with-associated-values Codable boilerplate is verbose).
}

// MARK: - v3 node payloads

/// One checklist row. `state` drives the leading glyph and text treatment.
public struct HermesChecklistItem: Codable, Equatable, Sendable {
    public enum State: String, Codable, Sendable {
        case checked      // filled checkmark, secondary/struck text
        case unchecked    // empty circle, primary text
        case none         // plain bullet — for lists without completion semantics
    }
    public var text: String
    public var detail: String?
    public var state: State
    public var iconSystemName: String?   // overrides the state glyph when set

    public init(text: String, detail: String? = nil, state: State = .none, iconSystemName: String? = nil) {
        self.text = text
        self.detail = detail
        self.state = state
        self.iconSystemName = iconSystemName
    }
}

/// One timeline row. `state` colors the rail dot (past = filled accent, current = ringed,
/// future = hollow gray).
public struct HermesTimelineEntry: Codable, Equatable, Sendable {
    public enum State: String, Codable, Sendable { case past, current, future }
    public var time: String?             // freeform: "9:40 AM", "Day 2", "Jul 8"
    public var title: String
    public var subtitle: String?
    public var state: State
    public var iconSystemName: String?   // shown inside the rail dot when set

    public init(time: String? = nil, title: String, subtitle: String? = nil,
                state: State = .future, iconSystemName: String? = nil) {
        self.time = time
        self.title = title
        self.subtitle = subtitle
        self.state = state
        self.iconSystemName = iconSystemName
    }
}

/// One bar in a `barChart`.
public struct HermesBar: Codable, Equatable, Sendable {
    public var label: String
    public var value: Double
    public var valueLabel: String?       // shown trailing the bar; defaults to the raw value
    public var colorHex: String?

    public init(label: String, value: Double, valueLabel: String? = nil, colorHex: String? = nil) {
        self.label = label
        self.value = value
        self.valueLabel = valueLabel
        self.colorHex = colorHex
    }
}

/// One choice in an `optionPicker`. Tapping selects locally (visible highlight); the picker's
/// own primary CTA commits, exactly like seatChart's confirm interaction.
public struct HermesPickerOption: Codable, Equatable, Sendable {
    public var id: String                // carried by the confirm reply
    public var label: String
    public var sublabel: String?
    public var systemImage: String?
    public var imageUrl: String?         // optional leading photo thumbnail (list/grid rows)
    public var badge: String?            // trailing accent text, e.g. "$42", "7:30 PM", "+15 min"
    public var disabled: Bool

    public init(id: String, label: String, sublabel: String? = nil, systemImage: String? = nil,
                imageUrl: String? = nil, badge: String? = nil, disabled: Bool = false) {
        self.id = id
        self.label = label
        self.sublabel = sublabel
        self.systemImage = systemImage
        self.imageUrl = imageUrl
        self.badge = badge
        self.disabled = disabled
    }
}

public enum HermesPickerStyle: String, Codable, Sendable {
    case list   // full-width rows (default) — best for options with sublabels/badges
    case grid   // 2-column compact cells — best for short labels (sizes, times)
}

// MARK: - v4 scene / instrument payloads

/// A split-flap airport departure board. Codes are shown as flip tiles; `progress` (0...1)
/// places the plane along a route strip between the two codes (nil = not yet departed).
public struct HermesFlightBoard: Codable, Equatable, Sendable {
    public var origin: String            // 3-letter IATA, e.g. "SFO"
    public var destination: String       // e.g. "NRT"
    public var originCity: String?       // shown small under the origin code
    public var destinationCity: String?
    public var flightCode: String?       // e.g. "UA 837"
    public var departTime: String?       // freeform, e.g. "10:45"
    public var arriveTime: String?
    public var gate: String?             // e.g. "G93"
    public var status: String            // e.g. "Boarding", "On time", "Delayed", "In flight"
    public var statusColorHex: String?   // state hue (green on-time / amber delayed / blue boarding)
    public var progress: Double?         // 0...1 along the route; nil before departure

    public init(origin: String, destination: String, originCity: String? = nil,
                destinationCity: String? = nil, flightCode: String? = nil,
                departTime: String? = nil, arriveTime: String? = nil, gate: String? = nil,
                status: String, statusColorHex: String? = nil, progress: Double? = nil) {
        self.origin = origin
        self.destination = destination
        self.originCity = originCity
        self.destinationCity = destinationCity
        self.flightCode = flightCode
        self.departTime = departTime
        self.arriveTime = arriveTime
        self.gate = gate
        self.status = status
        self.statusColorHex = statusColorHex
        self.progress = progress
    }
}

/// A procedurally-drawn plated dish. All fields optional except through defaults — the render
/// is deterministic given `seed`, so the same recipe draws the same plate every time.
public struct HermesPlatedDish: Codable, Equatable, Sendable {
    public var title: String?
    public var caption: String?          // e.g. "Serves 2 · 35 min"
    public var foodColorHex: String?     // main food hue
    public var garnishColorHex: String?  // garnish specks hue
    public var seed: Int?                // stable procedural placement (defaults to a fixed seed)
    public var steam: Bool               // rising steam = hot/fresh state

    public init(title: String? = nil, caption: String? = nil, foodColorHex: String? = nil,
                garnishColorHex: String? = nil, seed: Int? = nil, steam: Bool = true) {
        self.title = title
        self.caption = caption
        self.foodColorHex = foodColorHex
        self.garnishColorHex = garnishColorHex
        self.seed = seed
        self.steam = steam
    }
}

/// One amenity tile in a `photoCatalog` drawer — icon-first, short label underneath.
public struct HermesCatalogAmenity: Codable, Equatable, Sendable {
    public var label: String
    public var systemImage: String

    public init(label: String, systemImage: String) {
        self.label = label
        self.systemImage = systemImage
    }

    /// Maps legacy plain-text tags to icon tiles when authors omit `systemImage`.
    public static func inferred(from tag: String) -> HermesCatalogAmenity {
        let key = tag.lowercased()
        let icon: String
        switch true {
        case key.contains("onsen"), key.contains("bath"), key.contains("spa"): icon = "bathtub.fill"
        case key.contains("breakfast"), key.contains("coffee"): icon = "cup.and.saucer.fill"
        case key.contains("garden"), key.contains("courtyard"), key.contains("terrace"): icon = "leaf.fill"
        case key.contains("shuttle"), key.contains("bus"), key.contains("transfer"): icon = "bus.fill"
        case key.contains("wifi"), key.contains("wi-fi"): icon = "wifi"
        case key.contains("gym"), key.contains("fitness"): icon = "figure.run"
        case key.contains("restaurant"), key.contains("dining"): icon = "fork.knife"
        case key.contains("bar"), key.contains("cocktail"): icon = "wineglass.fill"
        case key.contains("pool"), key.contains("swim"): icon = "figure.pool.swim"
        case key.contains("parking"), key.contains("garage"): icon = "parkingsign.circle.fill"
        case key.contains("pet"), key.contains("dog"): icon = "pawprint.fill"
        case key.contains("lounge"), key.contains("sofa"): icon = "sofa.fill"
        case key.contains("check-in"), key.contains("24h"), key.contains("24 h"): icon = "clock.fill"
        case key.contains("view"), key.contains("skyline"): icon = "building.2.fill"
        case key.contains("tea"): icon = "teapot.fill"
        case key.contains("machiya"), key.contains("ryokan"): icon = "house.fill"
        case key.contains("pod"), key.contains("bed"): icon = "bed.double.fill"
        case key.contains("kitchen"): icon = "refrigerator.fill"
        case key.contains("laundry"): icon = "washer.fill"
        case key.contains("ac"), key.contains("air"): icon = "snowflake"
        default: icon = "checkmark.seal.fill"
        }
        return HermesCatalogAmenity(label: tag, systemImage: icon)
    }
}

/// One photo tile inside a `photoCatalog` card — a room, a table, a unit. Tapping it promotes
/// its photo to the card's hero and swaps the price pill to `price`.
public struct HermesCatalogRoom: Codable, Equatable, Sendable {
    public var id: String
    public var imageUrl: String?
    public var name: String          // e.g. "Garden Room"
    public var price: String?        // exact rate for this room, e.g. "$380"

    public init(id: String, imageUrl: String? = nil, name: String, price: String? = nil) {
        self.id = id
        self.imageUrl = imageUrl
        self.name = name
        self.price = price
    }
}

/// One card in a `photoCatalog`: a full-bleed hero photo, a solid price pill, name/area/rating,
/// and (revealed on expand) a horizontal gallery of `rooms` + amenity `tags` + `detail`.
public struct HermesCatalogItem: Codable, Equatable, Sendable {
    public var id: String
    public var heroImageUrl: String?    // collapsed hero; the selected room's photo replaces it when expanded
    public var title: String            // "Hiiragiya Ryokan"
    public var subtitle: String?        // "Higashiyama · ★ 4.8"
    public var priceText: String?       // collapsed pill, e.g. "from $88"
    public var priceUnit: String?       // "night"
    public var rooms: [HermesCatalogRoom]  // the room gallery revealed on expand
    public var amenities: [HermesCatalogAmenity]?  // icon tiles in the expanded drawer (preferred)
    public var tags: [String]?          // legacy text tags — auto-mapped to icons when amenities omitted
    public var detail: String?          // a short description line
    public var fallbackSystemImage: String?  // placeholder glyph; default "bed.double.fill"

    public init(id: String, heroImageUrl: String? = nil, title: String, subtitle: String? = nil,
                priceText: String? = nil, priceUnit: String? = nil, rooms: [HermesCatalogRoom] = [],
                amenities: [HermesCatalogAmenity]? = nil, tags: [String]? = nil, detail: String? = nil,
                fallbackSystemImage: String? = nil) {
        self.id = id
        self.heroImageUrl = heroImageUrl
        self.title = title
        self.subtitle = subtitle
        self.priceText = priceText
        self.priceUnit = priceUnit
        self.rooms = rooms
        self.amenities = amenities
        self.tags = tags
        self.detail = detail
        self.fallbackSystemImage = fallbackSystemImage
    }

    /// Resolved amenity tiles: explicit `amenities` win; plain `tags` are icon-mapped.
    public var resolvedAmenities: [HermesCatalogAmenity] {
        if let amenities, !amenities.isEmpty { return amenities }
        return tags?.map { HermesCatalogAmenity.inferred(from: $0) } ?? []
    }
}

/// One row in a `mediaList`: a ranked media item with leading artwork.
public struct HermesMediaItem: Codable, Equatable, Sendable {
    public var rank: Int?             // shows a rank numeral in the leading gutter (e.g. 1)
    public var imageUrl: String?     // square artwork (album cover, poster, product); AsyncImage
    public var title: String         // primary line, e.g. the song title
    public var subtitle: String?     // secondary line, e.g. the artist
    public var trailing: String?     // trailing value, e.g. "1,248"
    public var trailingSub: String?  // small line under the trailing value, e.g. "plays"
    public var fallbackSystemImage: String?  // shown when imageUrl is nil/unreachable; default music.note

    public init(rank: Int? = nil, imageUrl: String? = nil, title: String, subtitle: String? = nil,
                trailing: String? = nil, trailingSub: String? = nil, fallbackSystemImage: String? = nil) {
        self.rank = rank
        self.imageUrl = imageUrl
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
        self.trailingSub = trailingSub
        self.fallbackSystemImage = fallbackSystemImage
    }
}

/// One arc gauge in a `gaugeCluster`. `value` (0...1) fills the 270° arc; `valueText` is the
/// hero numeral shown in the center (falls back to the percentage).
public struct HermesGauge: Codable, Equatable, Sendable {
    public var label: String
    public var value: Double             // 0...1 arc fill
    public var valueText: String?        // center numeral, e.g. "142ms", "99.2%"
    public var colorHex: String?         // state hue

    public init(label: String, value: Double, valueText: String? = nil, colorHex: String? = nil) {
        self.label = label
        self.value = value
        self.valueText = valueText
        self.colorHex = colorHex
    }
}

// MARK: - v5 scene payloads

/// A courier/ride/transit journey drawn as a route arc. `progress` (0...1) places the vehicle
/// glyph along the arc; nil renders the route fully dashed (not yet started).
public struct HermesJourneyArc: Codable, Equatable, Sendable {
    public var originLabel: String        // short endpoint label, e.g. "Facility · Queens"
    public var destinationLabel: String   // e.g. "You · Fort Greene"
    public var carrier: String?           // top-left micro label, e.g. "UPS · 1Z 999 AA1 03"
    public var vehicleSystemName: String? // SF Symbol riding the arc; default "shippingbox.fill"
    public var status: String             // e.g. "Out for delivery", "Driver en route"
    public var statusColorHex: String?    // state hue for the pill + lit trail
    public var progress: Double?          // 0...1 along the arc; nil = not started
    public var etaText: String?           // e.g. "2:40 PM"
    public var detail: String?            // e.g. "7 stops away"

    public init(originLabel: String, destinationLabel: String, carrier: String? = nil,
                vehicleSystemName: String? = nil, status: String, statusColorHex: String? = nil,
                progress: Double? = nil, etaText: String? = nil, detail: String? = nil) {
        self.originLabel = originLabel
        self.destinationLabel = destinationLabel
        self.carrier = carrier
        self.vehicleSystemName = vehicleSystemName
        self.status = status
        self.statusColorHex = statusColorHex
        self.progress = progress
        self.etaText = etaText
        self.detail = detail
    }
}

/// A procedurally-drawn sky. `condition` + `isNight` pick the palette and the drawn elements
/// (sun disc, crescent moon + seeded stars, cloud clusters, rain streaks, snow, lightning,
/// fog bands); `seed` keeps star/cloud placement stable across renders.
public struct HermesSkyScene: Codable, Equatable, Sendable {
    public enum Condition: String, Codable, Sendable { case clear, clouds, rain, snow, storm, fog }
    public var condition: Condition
    public var isNight: Bool
    public var tempText: String?          // hero numeral, pre-formatted: "72°"
    public var hiLoText: String?          // "H 78° · L 63°"
    public var location: String?          // small-caps under the numeral
    public var caption: String?           // human line: "Clear evening — good flying weather"
    public var seed: Int?

    public init(condition: Condition = .clear, isNight: Bool = false, tempText: String? = nil,
                hiLoText: String? = nil, location: String? = nil, caption: String? = nil,
                seed: Int? = nil) {
        self.condition = condition
        self.isNight = isNight
        self.tempText = tempText
        self.hiLoText = hiLoText
        self.location = location
        self.caption = caption
        self.seed = seed
    }
}

/// A drawn ticket stub (notched outline, perforation, seeded barcode). The keepsake object
/// for events, reservations, and bookings.
public struct HermesEventTicket: Codable, Equatable, Sendable {
    public var kicker: String?            // small-caps line above the title, e.g. "WORLD TOUR · SEC 104"
    public var title: String              // marquee line, serif
    public var venue: String?
    public var dateText: String?          // freeform: "Fri, Aug 21"
    public var timeText: String?          // "8:00 PM"
    public var seatText: String?          // "Sec 104 · Row F · Seat 12"
    public var code: String?              // confirmation code under the barcode
    public var accentColorHex: String?    // ticket band + glow hue; defaults to the card accent
    public var seed: Int?                 // stable barcode bar pattern

    public init(kicker: String? = nil, title: String, venue: String? = nil, dateText: String? = nil,
                timeText: String? = nil, seatText: String? = nil, code: String? = nil,
                accentColorHex: String? = nil, seed: Int? = nil) {
        self.kicker = kicker
        self.title = title
        self.venue = venue
        self.dateText = dateText
        self.timeText = timeText
        self.seatText = seatText
        self.code = code
        self.accentColorHex = accentColorHex
        self.seed = seed
    }
}

/// A trading-terminal trend tile. `points` are raw series values (normalized in the view);
/// `trend` drives the state hue (gain green / loss red / flat gray) unless `colorHex` overrides.
public struct HermesSparkline: Codable, Equatable, Sendable {
    public enum Trend: String, Codable, Sendable { case up, down, flat }
    public var label: String              // "AAPL · NASDAQ"
    public var valueText: String          // hero numeral, pre-formatted: "$212.44"
    public var deltaText: String?         // "+1.8% today"
    public var trend: Trend
    public var colorHex: String?
    public var points: [Double]           // raw series; non-finite values are dropped in the view
    public var caption: String?           // "Past 30 days"

    public init(label: String, valueText: String, deltaText: String? = nil, trend: Trend = .flat,
                colorHex: String? = nil, points: [Double] = [], caption: String? = nil) {
        self.label = label
        self.valueText = valueText
        self.deltaText = deltaText
        self.trend = trend
        self.colorHex = colorHex
        self.points = points
        self.caption = caption
    }
}

/// An arena scoreboard. Scores are pre-formatted strings rendered as split-flap digit tiles;
/// `winner` dims the other side (contextual dimming) — use `.none` while a game is live.
public struct HermesScoreBoard: Codable, Equatable, Sendable {
    public enum Winner: String, Codable, Sendable { case home, away, none }
    public var homeName: String           // short code reads best: "LAL"
    public var homeScore: String
    public var homeColorHex: String?
    public var awayName: String
    public var awayScore: String
    public var awayColorHex: String?
    public var statusText: String?        // "FINAL", "Q4 · 2:31", "HT"
    public var detail: String?            // "Crypto.com Arena · Lakers lead series 3–2"
    public var winner: Winner

    public init(homeName: String, homeScore: String, homeColorHex: String? = nil,
                awayName: String, awayScore: String, awayColorHex: String? = nil,
                statusText: String? = nil, detail: String? = nil, winner: Winner = .none) {
        self.homeName = homeName
        self.homeScore = homeScore
        self.homeColorHex = homeColorHex
        self.awayName = awayName
        self.awayScore = awayScore
        self.awayColorHex = awayColorHex
        self.statusText = statusText
        self.detail = detail
        self.winner = winner
    }
}

// MARK: - Seat chart (airplane seat map)

/// One selectable seat in a `seatChart` row.
public struct HermesSeat: Codable, Equatable, Sendable {
    public enum State: String, Codable, Sendable {
        case available      // tappable, not yet picked
        case taken          // occupied by someone else — not tappable
        case selected       // pre-selected by the layout author (e.g. Hermes suggesting a seat)
        case unavailable    // blocked/nonexistent (crew rest, broken recline) — not tappable
    }
    public var id: String        // e.g. "22A" — this is what the Confirm reply carries
    public var letter: String    // column letter shown inside the seat, e.g. "A"
    public var state: State

    public init(id: String, letter: String, state: State = .available) {
        self.id = id
        self.letter = letter
        self.state = state
    }
}

/// One row of seats plus its metadata. `aisleAfterIndices` marks 0-based seat indices after
/// which a visible aisle gap is drawn — e.g. [2, 5] renders a 3-3-3 economy layout, [1, 5]
/// renders 2-4-2.
public struct HermesSeatRow: Codable, Equatable, Sendable {
    public var rowNumber: Int
    public var seats: [HermesSeat]
    public var aisleAfterIndices: [Int]
    public var isExitRow: Bool
    public var isBulkhead: Bool
    public var hasExtraLegroom: Bool

    public init(
        rowNumber: Int,
        seats: [HermesSeat],
        aisleAfterIndices: [Int] = [],
        isExitRow: Bool = false,
        isBulkhead: Bool = false,
        hasExtraLegroom: Bool = false
    ) {
        self.rowNumber = rowNumber
        self.seats = seats
        self.aisleAfterIndices = aisleAfterIndices
        self.isExitRow = isExitRow
        self.isBulkhead = isBulkhead
        self.hasExtraLegroom = hasExtraLegroom
    }
}

// MARK: - Quick-reply chips

/// A single chip in a `quickReplyRow`. Tapping a chip is a *committing* interaction: it
/// immediately composes and inserts a reply message (unlike seat selection, which is
/// local-only until the primary CTA commits). Use chips for one-step confirm/deny or
/// multiple-choice; use `seatChart`-style select-then-confirm for anything multi-step.
public struct HermesQuickReplyOption: Codable, Equatable, Sendable {
    public var id: String
    public var label: String
    public var systemImage: String?
    public var deepLinkURL: String?   // defaults to hermesshare://action?id=<id> when omitted

    public init(id: String, label: String, systemImage: String? = nil, deepLinkURL: String? = nil) {
        self.id = id
        self.label = label
        self.systemImage = systemImage
        self.deepLinkURL = deepLinkURL
    }
}

public struct HermesTextStyle: Codable, Equatable, Sendable {
    public enum Weight: String, Codable { case regular, medium, semibold, bold }
    public enum Role: String, Codable {
        case largeTitle, title, title2, title3, headline, body, subheadline, footnote, caption
    }
    public var role: Role
    public var weight: Weight
    public var colorHex: String?
    public var alignment: String?   // "leading" | "center" | "trailing"

    public init(
        role: Role = .body,
        weight: Weight = .regular,
        colorHex: String? = nil,
        alignment: String? = nil
    ) {
        self.role = role
        self.weight = weight
        self.colorHex = colorHex
        self.alignment = alignment
    }
}

public struct HermesAction: Codable, Equatable, Sendable {
    public var id: String
    public var label: String
    public var systemImage: String?
    public var deepLinkURL: String   // e.g. hermesshare://action?id=... — extension opens this via URLScheme, host app or Photon webhook handles it

    public init(id: String, label: String, systemImage: String? = nil, deepLinkURL: String) {
        self.id = id
        self.label = label
        self.systemImage = systemImage
        self.deepLinkURL = deepLinkURL
    }

    /// How a tap on this action should behave, decided purely by the `deepLinkURL` scheme.
    /// Kept here (not in the extension) so it's unit-testable and both targets agree:
    ///
    ///   • `hermesshare://…` (or an empty/unparseable URL) → INSERT A REPLY into the thread
    ///     ("✓ <label>"), the GamePigeon-style commit. Fail-safe default: a commit that shows a
    ///     confirmation beats silently opening nothing.
    ///   • any real scheme (`https`, `http`, `spotify`, `maps`, `tel`, …) → OPEN EXTERNALLY and
    ///     send NO reply — so a display card can offer "Open in Spotify" without spamming the
    ///     thread with a fake "✓ Open in Spotify" bubble.
    public var insertsReply: Bool {
        guard let scheme = URL(string: deepLinkURL)?.scheme?.lowercased(), !scheme.isEmpty else {
            return true
        }
        return scheme == "hermesshare"
    }
}
