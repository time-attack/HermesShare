// HermesSampleLayouts.swift
// Realistic `HermesLayout` fixtures used to drive Xcode Previews, the host app's debug
// harness, the unit tests, and the extension's hardcoded default payload. These are exactly
// the kind of documents Hermes would generate per message.

import Foundation

public enum HermesSampleLayouts {

    public static var all: [(name: String, layout: HermesLayout)] {
        [
            ("Package Tracking", packageTracking),
            ("Stat Dashboard", statDashboard),
            ("Map Preview", mapPreview),
            ("Seat Chart", seatSelection),
            ("Quick Reply", quickReply),
            ("Trip Day Plan", tripDayPlan),
            ("Courier Journey", courierJourney),
            ("Weather Tonight", weatherTonight),
            ("Concert Ticket", concertTicket),
            ("Market Pulse", marketPulse),
            ("Game Final", gameFinal)
        ]
    }

    // MARK: v5 showcase — the scene-expansion heroes

    /// Delivery card: journeyArc hero + spotlight timeline, on an atmosphere background.
    public static let courierJourney = HermesLayout(
        version: 1,
        title: "Your package is close",
        subtitle: "Order #HS-48213 · UPS Ground",
        accentColorHex: "#30D158",
        background: HermesBackground(kind: .atmosphere),
        root: .vstack(spacing: 16, alignment: "leading", children: [
            .journeyArc(HermesJourneyArc(
                originLabel: "Facility · Maspeth, NY",
                destinationLabel: "You · Fort Greene",
                carrier: "1Z 999 AA1 03",
                vehicleSystemName: "box.truck.fill",
                status: "Out for delivery",
                statusColorHex: "#30D158",
                progress: 0.78,
                etaText: "2:40 PM",
                detail: "7 stops away"
            )),
            .card(padding: 16, cornerRadius: 16, backgroundHex: nil, child:
                .timeline(entries: [
                    HermesTimelineEntry(time: "6:02", title: "Departed facility", subtitle: "Maspeth, NY", state: .past),
                    HermesTimelineEntry(time: "9:14", title: "Out for delivery", subtitle: "On the truck", state: .current),
                    HermesTimelineEntry(time: "~2:40", title: "Delivered", subtitle: "Front door — photo on arrival", state: .future)
                ])
            )
        ]),
        actions: [HermesAction(id: "notify-arrival", label: "Notify me at the door",
                               systemImage: "bell.badge.fill",
                               deepLinkURL: "hermesshare://action?id=notify-arrival")]
    )

    /// Weather card: skyScene hero + a compact condition stat strip.
    public static let weatherTonight = HermesLayout(
        version: 1,
        title: nil,
        subtitle: nil,
        accentColorHex: "#0A84FF",
        background: HermesBackground(kind: .atmosphere, colorsHex: ["#1B2C55"]),
        root: .vstack(spacing: 16, alignment: "leading", children: [
            .skyScene(HermesSkyScene(
                condition: .clear, isNight: true,
                tempText: "63°", hiLoText: "H 78° · L 58°",
                location: "Fort Greene, Brooklyn",
                caption: "Clear evening — the terrace kind",
                seed: 21
            )),
            .card(padding: 16, cornerRadius: 16, backgroundHex: nil, child:
                .hstack(spacing: 12, alignment: "top", children: [
                    .stat(value: "6 mph", label: "Wind", iconSystemName: "wind", colorHex: nil),
                    .stat(value: "41%", label: "Humidity", iconSystemName: "humidity.fill", colorHex: nil),
                    .stat(value: "10 PM", label: "Moonrise", iconSystemName: "moonrise.fill", colorHex: nil)
                ])
            )
        ]),
        actions: nil
    )

    /// Event card: eventTicket hero + door details. No layout title — the ticket's serif
    /// marquee IS the headline (two display-scale titles competed in design review).
    public static let concertTicket = HermesLayout(
        version: 1,
        title: nil,
        subtitle: nil,
        accentColorHex: "#BF5AF2",
        background: HermesBackground(kind: .atmosphere, colorsHex: ["#BF5AF2"]),
        root: .vstack(spacing: 16, alignment: "leading", children: [
            .eventTicket(HermesEventTicket(
                kicker: "World Tour · Brooklyn N2",
                title: "Khruangbin",
                venue: "Kings Theatre",
                dateText: "Fri Aug 21",
                timeText: "8:00 PM",
                seatText: "ORCH C · 12",
                code: "K7Q2XW",
                accentColorHex: "#BF5AF2",
                seed: 12
            )),
            .card(padding: 16, cornerRadius: 16, backgroundHex: nil, child:
                .vstack(spacing: 4, alignment: "leading", children: [
                    .keyValueRow(key: "Doors", value: "7:00 PM", iconSystemName: "door.left.hand.open"),
                    .keyValueRow(key: "Opener", value: "Men I Trust · 8:00", iconSystemName: "music.mic"),
                    .keyValueRow(key: "Bag policy", value: "Small bags only", iconSystemName: "bag")
                ])
            )
        ]),
        actions: [HermesAction(id: "add-wallet", label: "Add to Wallet", systemImage: "wallet.pass.fill",
                               deepLinkURL: "hermesshare://action?id=add-wallet")]
    )

    /// Market card: two sparkline tiles, gain and loss, on the dark atmosphere.
    public static let marketPulse = HermesLayout(
        version: 1,
        title: "Morning positions",
        subtitle: "As of 9:42 AM ET",
        accentColorHex: "#30D158",
        background: HermesBackground(kind: .atmosphere),
        root: .vstack(spacing: 12, alignment: "leading", children: [
            .sparkline(HermesSparkline(
                label: "NVDA · NASDAQ", valueText: "$182.14", deltaText: "+3.2%",
                trend: .up,
                points: [164, 166, 163, 168, 171, 169, 174, 172, 177, 176, 180, 182],
                caption: "Past 30 days"
            )),
            .sparkline(HermesSparkline(
                label: "TSLA · NASDAQ", valueText: "$241.90", deltaText: "-1.8%",
                trend: .down,
                points: [259, 262, 255, 251, 254, 248, 246, 250, 243, 245, 240, 242],
                caption: "Past 30 days"
            ))
        ]),
        actions: [HermesAction(id: "full-watchlist", label: "Open full watchlist",
                               systemImage: "chart.line.uptrend.xyaxis",
                               deepLinkURL: "hermesshare://action?id=full-watchlist")]
    )

    /// Score card: scoreBoard hero + a shooting-splits bar chart.
    public static let gameFinal = HermesLayout(
        version: 1,
        title: "Late one at Crypto.com",
        subtitle: "NBA · last night",
        accentColorHex: "#FFD60A",
        background: HermesBackground(kind: .atmosphere, colorsHex: ["#552583"]),
        root: .vstack(spacing: 16, alignment: "leading", children: [
            .scoreBoard(HermesScoreBoard(
                homeName: "LAL", homeScore: "126", homeColorHex: "#FDB927",
                awayName: "BOS", awayScore: "121", awayColorHex: "#30D158",
                statusText: "Final · OT",
                detail: "Crypto.com Arena · Lakers lead series 3–2",
                winner: .home
            )),
            .card(padding: 16, cornerRadius: 16, backgroundHex: nil, child:
                .barChart(bars: [
                    HermesBar(label: "LAL FG%", value: 51, valueLabel: "51%", colorHex: "#FDB927"),
                    HermesBar(label: "BOS FG%", value: 46, valueLabel: "46%", colorHex: "#30D158"),
                    HermesBar(label: "LAL 3PT%", value: 42, valueLabel: "42%", colorHex: "#FDB927"),
                    HermesBar(label: "BOS 3PT%", value: 38, valueLabel: "38%", colorHex: "#30D158")
                ], maxValue: 60)
            )
        ]),
        actions: [HermesAction(id: "box-score", label: "Full box score", systemImage: "list.number",
                               deepLinkURL: "hermesshare://action?id=box-score")]
    )

    // MARK: (f) v3 showcase — timeline + dateBadge + checklist + tags + optionPicker

    public static let tripDayPlan = HermesLayout(
        version: 1,
        title: "Osaka — Day 2",
        subtitle: "Tuesday plan · pick tonight's dinner",
        accentColorHex: "#FF6B35",
        background: HermesBackground(kind: .plain),
        root: .vstack(spacing: 14, alignment: "leading", children: [
            .hstack(spacing: 12, alignment: "center", children: [
                .dateBadge(month: "Jul", day: "8", weekday: "Tue", colorHex: "#FF6B35"),
                .vstack(spacing: 4, alignment: "leading", children: [
                    .rating(value: 4.5, maxValue: 5, label: "Dotonbori area", colorHex: nil),
                    .tagRow(labels: ["Street food", "Neon", "River walk"], colorHex: nil)
                ])
            ]),
            .card(padding: 14, cornerRadius: 16, backgroundHex: nil, child:
                .timeline(entries: [
                    HermesTimelineEntry(time: "9:00", title: "Kuromon Market", subtitle: "Breakfast crawl", state: .past),
                    HermesTimelineEntry(time: "13:00", title: "Osaka Castle", subtitle: "Park + museum", state: .current),
                    HermesTimelineEntry(time: "19:00", title: "Dinner", subtitle: "Vote below", state: .future)
                ])
            ),
            .card(padding: 14, cornerRadius: 16, backgroundHex: nil, child:
                .vstack(spacing: 10, alignment: "leading", children: [
                    .text("Tonight's dinner — pick one", style: HermesTextStyle(role: .subheadline, weight: .semibold)),
                    .optionPicker(
                        options: [
                            HermesPickerOption(id: "okonomiyaki", label: "Okonomiyaki", sublabel: "Mizuno · 20 min wait", systemImage: "flame.fill", badge: "¥1,400"),
                            HermesPickerOption(id: "kushikatsu", label: "Kushikatsu", sublabel: "Daruma · no wait", systemImage: "fork.knife", badge: "¥2,000"),
                            HermesPickerOption(id: "ramen", label: "Late-night ramen", sublabel: "Ichiran · 24h", systemImage: "cup.and.saucer.fill", badge: "¥1,100")
                        ],
                        selectedId: nil,
                        confirmLabel: "Vote",
                        style: .list
                    )
                ])
            )
        ]),
        actions: nil
    )

    // MARK: (a) Package-tracking status card

    public static let packageTracking = HermesLayout(
        version: 1,
        title: "Package Out for Delivery",
        subtitle: "Order #HS-48213",
        accentColorHex: "#34C759",
        background: HermesBackground(kind: .plain),
        root: .card(
            padding: 16,
            cornerRadius: 18,
            backgroundHex: nil,
            child: .vstack(spacing: 14, alignment: "leading", children: [
                .hstack(spacing: 10, alignment: "center", children: [
                    .icon(systemName: "shippingbox.fill", sizePt: 22, colorHex: "#34C759"),
                    .statusBadge(label: "Out for delivery", colorHex: "#34C759"),
                    .spacer(minLength: nil),
                    .text("ETA 2:40 PM", style: HermesTextStyle(role: .subheadline, weight: .semibold))
                ]),
                .progressBar(value: 0.78, colorHex: "#34C759"),
                .divider,
                .keyValueRow(key: "Carrier", value: "UPS Ground"),
                .keyValueRow(key: "Tracking #", value: "1Z 999 AA1 01 2345 6784"),
                .keyValueRow(key: "From", value: "Reno, NV"),
                .keyValueRow(key: "To", value: "San Francisco, CA"),
                .keyValueRow(key: "Estimated arrival", value: "Today, 2:40 – 3:10 PM")
            ])
        ),
        actions: [
            HermesAction(id: "track", label: "View full tracking", systemImage: "location.fill",
                         deepLinkURL: "hermesshare://action?id=track&order=HS-48213"),
            HermesAction(id: "delivered", label: "Mark as delivered", systemImage: "checkmark.circle.fill",
                         deepLinkURL: "hermesshare://action?id=delivered&order=HS-48213")
        ]
    )

    // MARK: (b) Stat / dashboard card

    public static let statDashboard = HermesLayout(
        version: 1,
        title: "Deploy Health",
        subtitle: "photon-prod • last 24h",
        accentColorHex: "#0A84FF",
        background: HermesBackground(kind: .plain),
        root: .card(
            padding: 16,
            cornerRadius: 18,
            backgroundHex: nil,
            child: .hstack(spacing: 18, alignment: "center", children: [
                .progressRing(value: 0.992, label: "uptime", colorHex: "#30D158"),
                .vstack(spacing: 8, alignment: "leading", children: [
                    .keyValueRow(key: "Requests", value: "1.28M"),
                    .keyValueRow(key: "p95 latency", value: "142 ms"),
                    .keyValueRow(key: "Error rate", value: "0.08%"),
                    .keyValueRow(key: "Active pods", value: "6 / 6")
                ])
            ])
        ),
        actions: [
            HermesAction(id: "open-dash", label: "Open dashboard", systemImage: "chart.line.uptrend.xyaxis",
                         deepLinkURL: "hermesshare://action?id=open-dash&svc=photon-prod")
        ]
    )

    // MARK: (c) Map-preview card

    public static let mapPreview = HermesLayout(
        version: 1,
        title: "Driver Arriving",
        subtitle: "Hermes courier • 4 min away",
        accentColorHex: "#FF9F0A",
        background: HermesBackground(kind: .plain),
        root: .vstack(spacing: 12, alignment: "leading", children: [
            .mapPreview(latitude: 37.7793, longitude: -122.4192, label: "Civic Center, San Francisco"),
            .hstack(spacing: 10, alignment: "center", children: [
                .icon(systemName: "car.fill", sizePt: 20, colorHex: "#FF9F0A"),
                .keyValueRow(key: "Vehicle", value: "White Prius · 8KXJ221")
            ]),
            .keyValueRow(key: "Driver", value: "Marcus T. · ★ 4.96")
        ]),
        actions: [
            HermesAction(id: "call", label: "Contact driver", systemImage: "phone.fill",
                         deepLinkURL: "hermesshare://action?id=call&trip=T-90311")
        ]
    )

    // MARK: (d) Seat-chart card (two-step select-then-confirm interaction)
    //
    // No layout-level `actions` on purpose: the seat chart renders its own primary CTA
    // ("Confirm Seat X") that only enables once a seat is picked. A 3-3-3 economy layout
    // (aisles after seat indices 2 and 5), with exit-row and bulkhead metadata.

    public static let seatSelection = HermesLayout(
        version: 1,
        title: "Pick Your Seat",
        subtitle: "BR 26 · TPE → SFO · Economy",
        accentColorHex: "#00875A",
        background: HermesBackground(kind: .plain),
        root: .card(
            padding: 16,
            cornerRadius: 18,
            backgroundHex: nil,
            child: .vstack(spacing: 12, alignment: "leading", children: [
                .hstack(spacing: 10, alignment: "center", children: [
                    .icon(systemName: "airplane", sizePt: 20, colorHex: "#00875A"),
                    .statusBadge(label: "Check-in open", colorHex: "#00875A"),
                    .spacer(minLength: nil),
                    .text("Boeing 787-9", style: HermesTextStyle(role: .footnote, colorHex: "#8E8E93"))
                ]),
                .seatChart(rows: seatRows, selectedSeatId: nil)
            ])
        ),
        actions: nil
    )

    private static var seatRows: [HermesSeatRow] {
        // Realistic mixed availability: row 21 is bulkhead, row 22 is the exit row with
        // extra legroom, rows 23–25 standard.
        func row(_ number: Int, taken: Set<String>, isExitRow: Bool = false,
                 isBulkhead: Bool = false, hasExtraLegroom: Bool = false) -> HermesSeatRow {
            let letters = ["A", "B", "C", "D", "E", "F", "G", "H", "K"]
            return HermesSeatRow(
                rowNumber: number,
                seats: letters.map { letter in
                    HermesSeat(
                        id: "\(number)\(letter)",
                        letter: letter,
                        state: taken.contains(letter) ? .taken : .available
                    )
                },
                aisleAfterIndices: [2, 5],
                isExitRow: isExitRow,
                isBulkhead: isBulkhead,
                hasExtraLegroom: hasExtraLegroom
            )
        }
        return [
            row(21, taken: ["A", "C", "D", "K"], isBulkhead: true),
            row(22, taken: ["E"], isExitRow: true, hasExtraLegroom: true),
            row(23, taken: ["A", "B", "F", "G", "H"]),
            row(24, taken: ["C", "D", "E"]),
            row(25, taken: ["B", "K"])
        ]
    }

    // MARK: (e) Quick-reply card (one-tap chips, no confirm step)

    public static let quickReply = HermesLayout(
        version: 1,
        title: "Dinner Friday?",
        subtitle: "Hermes found a table at Kokkari, 7:30 PM",
        accentColorHex: "#BF5AF2",
        background: HermesBackground(kind: .plain),
        root: .card(
            padding: 16,
            cornerRadius: 18,
            backgroundHex: nil,
            child: .vstack(spacing: 12, alignment: "leading", children: [
                .keyValueRow(key: "Restaurant", value: "Kokkari Estiatorio"),
                .keyValueRow(key: "Time", value: "Friday, 7:30 PM"),
                .keyValueRow(key: "Party", value: "4 people"),
                .divider,
                .text("Tap to reply:", style: HermesTextStyle(role: .footnote, colorHex: "#8E8E93")),
                .quickReplyRow(options: [
                    HermesQuickReplyOption(id: "rsvp-yes", label: "I'm in", systemImage: "checkmark"),
                    HermesQuickReplyOption(id: "rsvp-no", label: "Can't make it", systemImage: "xmark"),
                    HermesQuickReplyOption(id: "rsvp-later", label: "Ask me later", systemImage: "clock")
                ])
            ])
        ),
        actions: nil
    )
}
