// HermesLayoutCodable.swift
// Hand-written Codable conformance for the associated-value `HermesNode` enum and for
// `HermesTextStyle` (lenient defaults so Hermes can omit role/weight). The wire format for
// a node is a JSON object with a `"type"` string discriminator plus that case's payload keys:
//
//   { "type": "text", "text": "Hi", "style": { "role": "headline" } }
//   { "type": "vstack", "spacing": 8, "children": [ ... ] }
//
// This keeps the JSON compact and human-authorable while staying a strict, fixed vocabulary.

import Foundation
import CoreGraphics

// MARK: - HermesNode

extension HermesNode {
    private enum CodingKeys: String, CodingKey {
        case type
        case spacing, alignment, children
        case text, style
        case systemName, sizePt, colorHex
        case label
        case value
        case minLength
        case key
        case latitude, longitude
        case url, aspectRatio, cornerRadius
        case padding, backgroundHex, child
        case rows, selectedSeatId
        case options
        // v3
        case iconSystemName
        case items, entries
        case maxValue
        case headers
        case urls, heightPt
        case labels
        case month, day, weekday
        case name, detail, imageUrl
        case subtitle
        case bars
        case selectedId, confirmLabel, pickerStyle
        // v4 scene/instrument payloads
        case board, dish, gauges
        // v5 scene payloads
        case arc, sky, ticket, spark, score
        // media list
        case mediaItems
        // photo catalog
        case catalogItems, initialExpandedId
        case sectionId, initiallyExpanded
        case title, badge
    }

    private enum Kind: String, Codable {
        case vstack, hstack, text, icon, statusBadge, progressRing, progressBar
        case divider, spacer, keyValueRow, mapPreview, image, card
        case seatChart, quickReplyRow
        case checklist, timeline, rating, table, gallery, tagRow, stat
        case dateBadge, person, barChart, optionPicker
        case flightBoard, platedDish, gaugeCluster
        case journeyArc, skyScene, eventTicket, sparkline, scoreBoard
        case mediaList
        case photoCatalog
        case collapsible
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Unknown discriminators become a visible `.unsupported` node instead of failing the
        // whole card — so a build can receive cards using vocabulary added after it shipped
        // and still render everything it does understand, with the gap named on screen.
        let typeName = try c.decode(String.self, forKey: .type)
        guard let kind = Kind(rawValue: typeName) else {
            self = .unsupported(typeName: typeName)
            return
        }
        switch kind {
        case .vstack:
            self = .vstack(
                spacing: try c.decodeIfPresent(CGFloat.self, forKey: .spacing) ?? 8,
                alignment: try c.decodeIfPresent(String.self, forKey: .alignment),
                children: try c.decodeIfPresent([HermesNode].self, forKey: .children) ?? []
            )
        case .hstack:
            self = .hstack(
                spacing: try c.decodeIfPresent(CGFloat.self, forKey: .spacing) ?? 8,
                alignment: try c.decodeIfPresent(String.self, forKey: .alignment),
                children: try c.decodeIfPresent([HermesNode].self, forKey: .children) ?? []
            )
        case .text:
            self = .text(
                try c.decode(String.self, forKey: .text),
                style: try c.decodeIfPresent(HermesTextStyle.self, forKey: .style) ?? HermesTextStyle()
            )
        case .icon:
            self = .icon(
                systemName: try c.decode(String.self, forKey: .systemName),
                sizePt: try c.decodeIfPresent(CGFloat.self, forKey: .sizePt) ?? 20,
                colorHex: try c.decodeIfPresent(String.self, forKey: .colorHex)
            )
        case .statusBadge:
            self = .statusBadge(
                label: try c.decode(String.self, forKey: .label),
                colorHex: try c.decode(String.self, forKey: .colorHex)
            )
        case .progressRing:
            self = .progressRing(
                value: try c.decode(Double.self, forKey: .value),
                label: try c.decodeIfPresent(String.self, forKey: .label),
                colorHex: try c.decodeIfPresent(String.self, forKey: .colorHex)
            )
        case .progressBar:
            self = .progressBar(
                value: try c.decode(Double.self, forKey: .value),
                colorHex: try c.decodeIfPresent(String.self, forKey: .colorHex)
            )
        case .divider:
            self = .divider
        case .spacer:
            self = .spacer(minLength: try c.decodeIfPresent(CGFloat.self, forKey: .minLength))
        case .keyValueRow:
            // The documented wire key is "iconSystemName"; "systemName" is also accepted for
            // backward compatibility (the first shipped decoder mistakenly read only it).
            self = .keyValueRow(
                key: try c.decode(String.self, forKey: .key),
                value: try c.decode(String.self, forKey: .value),
                iconSystemName: try c.decodeIfPresent(String.self, forKey: .iconSystemName)
                    ?? c.decodeIfPresent(String.self, forKey: .systemName)
            )
        case .mapPreview:
            self = .mapPreview(
                latitude: try c.decode(Double.self, forKey: .latitude),
                longitude: try c.decode(Double.self, forKey: .longitude),
                label: try c.decodeIfPresent(String.self, forKey: .label)
            )
        case .image:
            self = .image(
                url: try c.decode(String.self, forKey: .url),
                aspectRatio: try c.decodeIfPresent(Double.self, forKey: .aspectRatio),
                cornerRadius: try c.decodeIfPresent(CGFloat.self, forKey: .cornerRadius)
            )
        case .card:
            self = .card(
                padding: try c.decodeIfPresent(CGFloat.self, forKey: .padding) ?? 16,
                cornerRadius: try c.decodeIfPresent(CGFloat.self, forKey: .cornerRadius) ?? 16,
                backgroundHex: try c.decodeIfPresent(String.self, forKey: .backgroundHex),
                child: try c.decode(HermesNode.self, forKey: .child)
            )
        case .seatChart:
            self = .seatChart(
                rows: try c.decode([HermesSeatRow].self, forKey: .rows),
                selectedSeatId: try c.decodeIfPresent(String.self, forKey: .selectedSeatId)
            )
        case .quickReplyRow:
            self = .quickReplyRow(
                options: try c.decode([HermesQuickReplyOption].self, forKey: .options)
            )
        case .checklist:
            self = .checklist(items: try c.decode([HermesChecklistItem].self, forKey: .items))
        case .timeline:
            self = .timeline(entries: try c.decode([HermesTimelineEntry].self, forKey: .entries))
        case .rating:
            self = .rating(
                value: try c.decode(Double.self, forKey: .value),
                maxValue: try c.decodeIfPresent(Int.self, forKey: .maxValue) ?? 5,
                label: try c.decodeIfPresent(String.self, forKey: .label),
                colorHex: try c.decodeIfPresent(String.self, forKey: .colorHex)
            )
        case .table:
            self = .table(
                headers: try c.decodeIfPresent([String].self, forKey: .headers),
                rows: try c.decode([[String]].self, forKey: .rows)
            )
        case .gallery:
            self = .gallery(
                urls: try c.decode([String].self, forKey: .urls),
                heightPt: try c.decodeIfPresent(CGFloat.self, forKey: .heightPt),
                cornerRadius: try c.decodeIfPresent(CGFloat.self, forKey: .cornerRadius)
            )
        case .tagRow:
            self = .tagRow(
                labels: try c.decode([String].self, forKey: .labels),
                colorHex: try c.decodeIfPresent(String.self, forKey: .colorHex)
            )
        case .stat:
            self = .stat(
                value: try c.decode(String.self, forKey: .value),
                label: try c.decode(String.self, forKey: .label),
                iconSystemName: try c.decodeIfPresent(String.self, forKey: .iconSystemName),
                colorHex: try c.decodeIfPresent(String.self, forKey: .colorHex)
            )
        case .dateBadge:
            self = .dateBadge(
                month: try c.decode(String.self, forKey: .month),
                day: try c.decode(String.self, forKey: .day),
                weekday: try c.decodeIfPresent(String.self, forKey: .weekday),
                colorHex: try c.decodeIfPresent(String.self, forKey: .colorHex)
            )
        case .person:
            self = .person(
                name: try c.decode(String.self, forKey: .name),
                detail: try c.decodeIfPresent(String.self, forKey: .detail),
                imageUrl: try c.decodeIfPresent(String.self, forKey: .imageUrl),
                colorHex: try c.decodeIfPresent(String.self, forKey: .colorHex)
            )
        case .barChart:
            self = .barChart(
                bars: try c.decode([HermesBar].self, forKey: .bars),
                maxValue: try c.decodeIfPresent(Double.self, forKey: .maxValue)
            )
        case .optionPicker:
            self = .optionPicker(
                options: try c.decode([HermesPickerOption].self, forKey: .options),
                selectedId: try c.decodeIfPresent(String.self, forKey: .selectedId),
                confirmLabel: try c.decodeIfPresent(String.self, forKey: .confirmLabel),
                style: try c.decodeIfPresent(HermesPickerStyle.self, forKey: .pickerStyle) ?? .list
            )
        case .flightBoard:
            self = .flightBoard(try c.decode(HermesFlightBoard.self, forKey: .board))
        case .platedDish:
            self = .platedDish(try c.decode(HermesPlatedDish.self, forKey: .dish))
        case .gaugeCluster:
            self = .gaugeCluster(gauges: try c.decode([HermesGauge].self, forKey: .gauges))
        case .journeyArc:
            self = .journeyArc(try c.decode(HermesJourneyArc.self, forKey: .arc))
        case .skyScene:
            self = .skyScene(try c.decode(HermesSkyScene.self, forKey: .sky))
        case .eventTicket:
            self = .eventTicket(try c.decode(HermesEventTicket.self, forKey: .ticket))
        case .sparkline:
            self = .sparkline(try c.decode(HermesSparkline.self, forKey: .spark))
        case .scoreBoard:
            self = .scoreBoard(try c.decode(HermesScoreBoard.self, forKey: .score))
        case .mediaList:
            self = .mediaList(items: try c.decode([HermesMediaItem].self, forKey: .mediaItems))
        case .photoCatalog:
            self = .photoCatalog(
                items: try c.decode([HermesCatalogItem].self, forKey: .catalogItems),
                initialExpandedId: try c.decodeIfPresent(String.self, forKey: .initialExpandedId),
                confirmLabel: try c.decodeIfPresent(String.self, forKey: .confirmLabel)
            )
        case .collapsible:
            self = .collapsible(
                id: try c.decode(String.self, forKey: .sectionId),
                title: try c.decode(String.self, forKey: .title),
                subtitle: try c.decodeIfPresent(String.self, forKey: .subtitle),
                imageUrl: try c.decodeIfPresent(String.self, forKey: .imageUrl),
                badge: try c.decodeIfPresent(String.self, forKey: .badge),
                initiallyExpanded: try c.decodeIfPresent(Bool.self, forKey: .initiallyExpanded) ?? false,
                child: try c.decode(HermesNode.self, forKey: .child)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .vstack(spacing, alignment, children):
            try c.encode(Kind.vstack, forKey: .type)
            try c.encode(spacing, forKey: .spacing)
            try c.encodeIfPresent(alignment, forKey: .alignment)
            try c.encode(children, forKey: .children)
        case let .hstack(spacing, alignment, children):
            try c.encode(Kind.hstack, forKey: .type)
            try c.encode(spacing, forKey: .spacing)
            try c.encodeIfPresent(alignment, forKey: .alignment)
            try c.encode(children, forKey: .children)
        case let .text(value, style):
            try c.encode(Kind.text, forKey: .type)
            try c.encode(value, forKey: .text)
            try c.encode(style, forKey: .style)
        case let .icon(systemName, sizePt, colorHex):
            try c.encode(Kind.icon, forKey: .type)
            try c.encode(systemName, forKey: .systemName)
            try c.encode(sizePt, forKey: .sizePt)
            try c.encodeIfPresent(colorHex, forKey: .colorHex)
        case let .statusBadge(label, colorHex):
            try c.encode(Kind.statusBadge, forKey: .type)
            try c.encode(label, forKey: .label)
            try c.encode(colorHex, forKey: .colorHex)
        case let .progressRing(value, label, colorHex):
            try c.encode(Kind.progressRing, forKey: .type)
            try c.encode(value, forKey: .value)
            try c.encodeIfPresent(label, forKey: .label)
            try c.encodeIfPresent(colorHex, forKey: .colorHex)
        case let .progressBar(value, colorHex):
            try c.encode(Kind.progressBar, forKey: .type)
            try c.encode(value, forKey: .value)
            try c.encodeIfPresent(colorHex, forKey: .colorHex)
        case .divider:
            try c.encode(Kind.divider, forKey: .type)
        case let .spacer(minLength):
            try c.encode(Kind.spacer, forKey: .type)
            try c.encodeIfPresent(minLength, forKey: .minLength)
        case let .keyValueRow(key, value, iconSystemName):
            try c.encode(Kind.keyValueRow, forKey: .type)
            try c.encode(key, forKey: .key)
            try c.encode(value, forKey: .value)
            try c.encodeIfPresent(iconSystemName, forKey: .iconSystemName)
        case let .mapPreview(latitude, longitude, label):
            try c.encode(Kind.mapPreview, forKey: .type)
            try c.encode(latitude, forKey: .latitude)
            try c.encode(longitude, forKey: .longitude)
            try c.encodeIfPresent(label, forKey: .label)
        case let .image(url, aspectRatio, cornerRadius):
            try c.encode(Kind.image, forKey: .type)
            try c.encode(url, forKey: .url)
            try c.encodeIfPresent(aspectRatio, forKey: .aspectRatio)
            try c.encodeIfPresent(cornerRadius, forKey: .cornerRadius)
        case let .card(padding, cornerRadius, backgroundHex, child):
            try c.encode(Kind.card, forKey: .type)
            try c.encode(padding, forKey: .padding)
            try c.encode(cornerRadius, forKey: .cornerRadius)
            try c.encodeIfPresent(backgroundHex, forKey: .backgroundHex)
            try c.encode(child, forKey: .child)
        case let .seatChart(rows, selectedSeatId):
            try c.encode(Kind.seatChart, forKey: .type)
            try c.encode(rows, forKey: .rows)
            try c.encodeIfPresent(selectedSeatId, forKey: .selectedSeatId)
        case let .quickReplyRow(options):
            try c.encode(Kind.quickReplyRow, forKey: .type)
            try c.encode(options, forKey: .options)
        case let .checklist(items):
            try c.encode(Kind.checklist, forKey: .type)
            try c.encode(items, forKey: .items)
        case let .timeline(entries):
            try c.encode(Kind.timeline, forKey: .type)
            try c.encode(entries, forKey: .entries)
        case let .rating(value, maxValue, label, colorHex):
            try c.encode(Kind.rating, forKey: .type)
            try c.encode(value, forKey: .value)
            try c.encode(maxValue, forKey: .maxValue)
            try c.encodeIfPresent(label, forKey: .label)
            try c.encodeIfPresent(colorHex, forKey: .colorHex)
        case let .table(headers, rows):
            try c.encode(Kind.table, forKey: .type)
            try c.encodeIfPresent(headers, forKey: .headers)
            try c.encode(rows, forKey: .rows)
        case let .gallery(urls, heightPt, cornerRadius):
            try c.encode(Kind.gallery, forKey: .type)
            try c.encode(urls, forKey: .urls)
            try c.encodeIfPresent(heightPt, forKey: .heightPt)
            try c.encodeIfPresent(cornerRadius, forKey: .cornerRadius)
        case let .tagRow(labels, colorHex):
            try c.encode(Kind.tagRow, forKey: .type)
            try c.encode(labels, forKey: .labels)
            try c.encodeIfPresent(colorHex, forKey: .colorHex)
        case let .stat(value, label, iconSystemName, colorHex):
            try c.encode(Kind.stat, forKey: .type)
            try c.encode(value, forKey: .value)
            try c.encode(label, forKey: .label)
            try c.encodeIfPresent(iconSystemName, forKey: .iconSystemName)
            try c.encodeIfPresent(colorHex, forKey: .colorHex)
        case let .dateBadge(month, day, weekday, colorHex):
            try c.encode(Kind.dateBadge, forKey: .type)
            try c.encode(month, forKey: .month)
            try c.encode(day, forKey: .day)
            try c.encodeIfPresent(weekday, forKey: .weekday)
            try c.encodeIfPresent(colorHex, forKey: .colorHex)
        case let .person(name, detail, imageUrl, colorHex):
            try c.encode(Kind.person, forKey: .type)
            try c.encode(name, forKey: .name)
            try c.encodeIfPresent(detail, forKey: .detail)
            try c.encodeIfPresent(imageUrl, forKey: .imageUrl)
            try c.encodeIfPresent(colorHex, forKey: .colorHex)
        case let .barChart(bars, maxValue):
            try c.encode(Kind.barChart, forKey: .type)
            try c.encode(bars, forKey: .bars)
            try c.encodeIfPresent(maxValue, forKey: .maxValue)
        case let .optionPicker(options, selectedId, confirmLabel, style):
            try c.encode(Kind.optionPicker, forKey: .type)
            try c.encode(options, forKey: .options)
            try c.encodeIfPresent(selectedId, forKey: .selectedId)
            try c.encodeIfPresent(confirmLabel, forKey: .confirmLabel)
            try c.encode(style, forKey: .pickerStyle)
        case let .flightBoard(board):
            try c.encode(Kind.flightBoard, forKey: .type)
            try c.encode(board, forKey: .board)
        case let .platedDish(dish):
            try c.encode(Kind.platedDish, forKey: .type)
            try c.encode(dish, forKey: .dish)
        case let .gaugeCluster(gauges):
            try c.encode(Kind.gaugeCluster, forKey: .type)
            try c.encode(gauges, forKey: .gauges)
        case let .journeyArc(arc):
            try c.encode(Kind.journeyArc, forKey: .type)
            try c.encode(arc, forKey: .arc)
        case let .skyScene(sky):
            try c.encode(Kind.skyScene, forKey: .type)
            try c.encode(sky, forKey: .sky)
        case let .eventTicket(ticket):
            try c.encode(Kind.eventTicket, forKey: .type)
            try c.encode(ticket, forKey: .ticket)
        case let .sparkline(spark):
            try c.encode(Kind.sparkline, forKey: .type)
            try c.encode(spark, forKey: .spark)
        case let .scoreBoard(score):
            try c.encode(Kind.scoreBoard, forKey: .type)
            try c.encode(score, forKey: .score)
        case let .mediaList(items):
            try c.encode(Kind.mediaList, forKey: .type)
            try c.encode(items, forKey: .mediaItems)
        case let .photoCatalog(items, initialExpandedId, confirmLabel):
            try c.encode(Kind.photoCatalog, forKey: .type)
            try c.encode(items, forKey: .catalogItems)
            try c.encodeIfPresent(initialExpandedId, forKey: .initialExpandedId)
            try c.encodeIfPresent(confirmLabel, forKey: .confirmLabel)
        case let .collapsible(id, title, subtitle, imageUrl, badge, initiallyExpanded, child):
            try c.encode(Kind.collapsible, forKey: .type)
            try c.encode(id, forKey: .sectionId)
            try c.encode(title, forKey: .title)
            try c.encodeIfPresent(subtitle, forKey: .subtitle)
            try c.encodeIfPresent(imageUrl, forKey: .imageUrl)
            try c.encodeIfPresent(badge, forKey: .badge)
            if initiallyExpanded { try c.encode(true, forKey: .initiallyExpanded) }
            try c.encode(child, forKey: .child)
        case let .unsupported(typeName):
            // Round-trips the marker only; the original payload was never decoded.
            try c.encode(typeName, forKey: .type)
        }
    }
}

// MARK: - v3 payload structs (lenient: enum states and flags may be omitted)

extension HermesChecklistItem {
    private enum CodingKeys: String, CodingKey { case text, detail, state, iconSystemName }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            text: try c.decode(String.self, forKey: .text),
            detail: try c.decodeIfPresent(String.self, forKey: .detail),
            state: try c.decodeIfPresent(State.self, forKey: .state) ?? .none,
            iconSystemName: try c.decodeIfPresent(String.self, forKey: .iconSystemName)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(text, forKey: .text)
        try c.encodeIfPresent(detail, forKey: .detail)
        try c.encode(state, forKey: .state)
        try c.encodeIfPresent(iconSystemName, forKey: .iconSystemName)
    }
}

extension HermesTimelineEntry {
    private enum CodingKeys: String, CodingKey { case time, title, subtitle, state, iconSystemName }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            time: try c.decodeIfPresent(String.self, forKey: .time),
            title: try c.decode(String.self, forKey: .title),
            subtitle: try c.decodeIfPresent(String.self, forKey: .subtitle),
            state: try c.decodeIfPresent(State.self, forKey: .state) ?? .future,
            iconSystemName: try c.decodeIfPresent(String.self, forKey: .iconSystemName)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(time, forKey: .time)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(subtitle, forKey: .subtitle)
        try c.encode(state, forKey: .state)
        try c.encodeIfPresent(iconSystemName, forKey: .iconSystemName)
    }
}

extension HermesPickerOption {
    private enum CodingKeys: String, CodingKey { case id, label, sublabel, systemImage, imageUrl, badge, disabled }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decode(String.self, forKey: .id),
            label: try c.decode(String.self, forKey: .label),
            sublabel: try c.decodeIfPresent(String.self, forKey: .sublabel),
            systemImage: try c.decodeIfPresent(String.self, forKey: .systemImage),
            imageUrl: try c.decodeIfPresent(String.self, forKey: .imageUrl),
            badge: try c.decodeIfPresent(String.self, forKey: .badge),
            disabled: try c.decodeIfPresent(Bool.self, forKey: .disabled) ?? false
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(label, forKey: .label)
        try c.encodeIfPresent(sublabel, forKey: .sublabel)
        try c.encodeIfPresent(systemImage, forKey: .systemImage)
        try c.encodeIfPresent(imageUrl, forKey: .imageUrl)
        try c.encodeIfPresent(badge, forKey: .badge)
        if disabled { try c.encode(true, forKey: .disabled) }
    }
}

// MARK: - v4 scene/instrument payloads (lenient defaults)

extension HermesFlightBoard {
    private enum CodingKeys: String, CodingKey {
        case origin, destination, originCity, destinationCity, flightCode
        case departTime, arriveTime, gate, status, statusColorHex, progress
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            origin: try c.decode(String.self, forKey: .origin),
            destination: try c.decode(String.self, forKey: .destination),
            originCity: try c.decodeIfPresent(String.self, forKey: .originCity),
            destinationCity: try c.decodeIfPresent(String.self, forKey: .destinationCity),
            flightCode: try c.decodeIfPresent(String.self, forKey: .flightCode),
            departTime: try c.decodeIfPresent(String.self, forKey: .departTime),
            arriveTime: try c.decodeIfPresent(String.self, forKey: .arriveTime),
            gate: try c.decodeIfPresent(String.self, forKey: .gate),
            status: try c.decodeIfPresent(String.self, forKey: .status) ?? "",
            statusColorHex: try c.decodeIfPresent(String.self, forKey: .statusColorHex),
            progress: try c.decodeIfPresent(Double.self, forKey: .progress)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(origin, forKey: .origin)
        try c.encode(destination, forKey: .destination)
        try c.encodeIfPresent(originCity, forKey: .originCity)
        try c.encodeIfPresent(destinationCity, forKey: .destinationCity)
        try c.encodeIfPresent(flightCode, forKey: .flightCode)
        try c.encodeIfPresent(departTime, forKey: .departTime)
        try c.encodeIfPresent(arriveTime, forKey: .arriveTime)
        try c.encodeIfPresent(gate, forKey: .gate)
        try c.encode(status, forKey: .status)
        try c.encodeIfPresent(statusColorHex, forKey: .statusColorHex)
        try c.encodeIfPresent(progress, forKey: .progress)
    }
}

extension HermesPlatedDish {
    private enum CodingKeys: String, CodingKey {
        case title, caption, foodColorHex, garnishColorHex, seed, steam
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            title: try c.decodeIfPresent(String.self, forKey: .title),
            caption: try c.decodeIfPresent(String.self, forKey: .caption),
            foodColorHex: try c.decodeIfPresent(String.self, forKey: .foodColorHex),
            garnishColorHex: try c.decodeIfPresent(String.self, forKey: .garnishColorHex),
            seed: try c.decodeIfPresent(Int.self, forKey: .seed),
            steam: try c.decodeIfPresent(Bool.self, forKey: .steam) ?? true
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(title, forKey: .title)
        try c.encodeIfPresent(caption, forKey: .caption)
        try c.encodeIfPresent(foodColorHex, forKey: .foodColorHex)
        try c.encodeIfPresent(garnishColorHex, forKey: .garnishColorHex)
        try c.encodeIfPresent(seed, forKey: .seed)
        try c.encode(steam, forKey: .steam)
    }
}

extension HermesGauge {
    private enum CodingKeys: String, CodingKey { case label, value, valueText, colorHex }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            label: try c.decode(String.self, forKey: .label),
            value: try c.decodeIfPresent(Double.self, forKey: .value) ?? 0,
            valueText: try c.decodeIfPresent(String.self, forKey: .valueText),
            colorHex: try c.decodeIfPresent(String.self, forKey: .colorHex)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(label, forKey: .label)
        try c.encode(value, forKey: .value)
        try c.encodeIfPresent(valueText, forKey: .valueText)
        try c.encodeIfPresent(colorHex, forKey: .colorHex)
    }
}

extension HermesCatalogRoom {
    private enum CodingKeys: String, CodingKey { case id, imageUrl, name, price }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decode(String.self, forKey: .id),
            imageUrl: try c.decodeIfPresent(String.self, forKey: .imageUrl),
            name: try c.decode(String.self, forKey: .name),
            price: try c.decodeIfPresent(String.self, forKey: .price)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(imageUrl, forKey: .imageUrl)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(price, forKey: .price)
    }
}

extension HermesCatalogItem {
    private enum CodingKeys: String, CodingKey {
        case id, heroImageUrl, title, subtitle, priceText, priceUnit, rooms, tags, detail, fallbackSystemImage
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decode(String.self, forKey: .id),
            heroImageUrl: try c.decodeIfPresent(String.self, forKey: .heroImageUrl),
            title: try c.decode(String.self, forKey: .title),
            subtitle: try c.decodeIfPresent(String.self, forKey: .subtitle),
            priceText: try c.decodeIfPresent(String.self, forKey: .priceText),
            priceUnit: try c.decodeIfPresent(String.self, forKey: .priceUnit),
            rooms: try c.decodeIfPresent([HermesCatalogRoom].self, forKey: .rooms) ?? [],
            tags: try c.decodeIfPresent([String].self, forKey: .tags),
            detail: try c.decodeIfPresent(String.self, forKey: .detail),
            fallbackSystemImage: try c.decodeIfPresent(String.self, forKey: .fallbackSystemImage)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(heroImageUrl, forKey: .heroImageUrl)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(subtitle, forKey: .subtitle)
        try c.encodeIfPresent(priceText, forKey: .priceText)
        try c.encodeIfPresent(priceUnit, forKey: .priceUnit)
        if !rooms.isEmpty { try c.encode(rooms, forKey: .rooms) }
        try c.encodeIfPresent(tags, forKey: .tags)
        try c.encodeIfPresent(detail, forKey: .detail)
        try c.encodeIfPresent(fallbackSystemImage, forKey: .fallbackSystemImage)
    }
}

extension HermesMediaItem {
    private enum CodingKeys: String, CodingKey {
        case rank, imageUrl, title, subtitle, trailing, trailingSub, fallbackSystemImage
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            rank: try c.decodeIfPresent(Int.self, forKey: .rank),
            imageUrl: try c.decodeIfPresent(String.self, forKey: .imageUrl),
            title: try c.decode(String.self, forKey: .title),
            subtitle: try c.decodeIfPresent(String.self, forKey: .subtitle),
            trailing: try c.decodeIfPresent(String.self, forKey: .trailing),
            trailingSub: try c.decodeIfPresent(String.self, forKey: .trailingSub),
            fallbackSystemImage: try c.decodeIfPresent(String.self, forKey: .fallbackSystemImage)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(rank, forKey: .rank)
        try c.encodeIfPresent(imageUrl, forKey: .imageUrl)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(subtitle, forKey: .subtitle)
        try c.encodeIfPresent(trailing, forKey: .trailing)
        try c.encodeIfPresent(trailingSub, forKey: .trailingSub)
        try c.encodeIfPresent(fallbackSystemImage, forKey: .fallbackSystemImage)
    }
}

// MARK: - HermesBackground (lenient kind — same forward-compat guarantee as unknown nodes)

extension HermesBackground {
    private enum CodingKeys: String, CodingKey { case kind, colorsHex }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // A background kind this build doesn't know degrades to .plain instead of failing
        // the whole layout — the synthesized strict enum decode was the one remaining spot
        // where future vocabulary could still brick an entire card.
        let raw = try c.decodeIfPresent(String.self, forKey: .kind)
        self.init(
            kind: raw.flatMap(Kind.init(rawValue:)) ?? .plain,
            colorsHex: try c.decodeIfPresent([String].self, forKey: .colorsHex)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        try c.encodeIfPresent(colorsHex, forKey: .colorsHex)
    }
}

// MARK: - v5 scene payloads (lenient defaults)

extension HermesJourneyArc {
    private enum CodingKeys: String, CodingKey {
        case originLabel, destinationLabel, carrier, vehicleSystemName
        case status, statusColorHex, progress, etaText, detail
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            originLabel: try c.decode(String.self, forKey: .originLabel),
            destinationLabel: try c.decode(String.self, forKey: .destinationLabel),
            carrier: try c.decodeIfPresent(String.self, forKey: .carrier),
            vehicleSystemName: try c.decodeIfPresent(String.self, forKey: .vehicleSystemName),
            status: try c.decodeIfPresent(String.self, forKey: .status) ?? "",
            statusColorHex: try c.decodeIfPresent(String.self, forKey: .statusColorHex),
            progress: try c.decodeIfPresent(Double.self, forKey: .progress),
            etaText: try c.decodeIfPresent(String.self, forKey: .etaText),
            detail: try c.decodeIfPresent(String.self, forKey: .detail)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(originLabel, forKey: .originLabel)
        try c.encode(destinationLabel, forKey: .destinationLabel)
        try c.encodeIfPresent(carrier, forKey: .carrier)
        try c.encodeIfPresent(vehicleSystemName, forKey: .vehicleSystemName)
        try c.encode(status, forKey: .status)
        try c.encodeIfPresent(statusColorHex, forKey: .statusColorHex)
        try c.encodeIfPresent(progress, forKey: .progress)
        try c.encodeIfPresent(etaText, forKey: .etaText)
        try c.encodeIfPresent(detail, forKey: .detail)
    }
}

extension HermesSkyScene {
    private enum CodingKeys: String, CodingKey {
        case condition, isNight, tempText, hiLoText, location, caption, seed
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Unknown condition strings degrade to .clear rather than failing the card.
        let rawCondition = try c.decodeIfPresent(String.self, forKey: .condition)
        self.init(
            condition: rawCondition.flatMap(Condition.init(rawValue:)) ?? .clear,
            isNight: try c.decodeIfPresent(Bool.self, forKey: .isNight) ?? false,
            tempText: try c.decodeIfPresent(String.self, forKey: .tempText),
            hiLoText: try c.decodeIfPresent(String.self, forKey: .hiLoText),
            location: try c.decodeIfPresent(String.self, forKey: .location),
            caption: try c.decodeIfPresent(String.self, forKey: .caption),
            seed: try c.decodeIfPresent(Int.self, forKey: .seed)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(condition, forKey: .condition)
        try c.encode(isNight, forKey: .isNight)
        try c.encodeIfPresent(tempText, forKey: .tempText)
        try c.encodeIfPresent(hiLoText, forKey: .hiLoText)
        try c.encodeIfPresent(location, forKey: .location)
        try c.encodeIfPresent(caption, forKey: .caption)
        try c.encodeIfPresent(seed, forKey: .seed)
    }
}

extension HermesEventTicket {
    private enum CodingKeys: String, CodingKey {
        case kicker, title, venue, dateText, timeText, seatText, code, accentColorHex, seed
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            kicker: try c.decodeIfPresent(String.self, forKey: .kicker),
            title: try c.decode(String.self, forKey: .title),
            venue: try c.decodeIfPresent(String.self, forKey: .venue),
            dateText: try c.decodeIfPresent(String.self, forKey: .dateText),
            timeText: try c.decodeIfPresent(String.self, forKey: .timeText),
            seatText: try c.decodeIfPresent(String.self, forKey: .seatText),
            code: try c.decodeIfPresent(String.self, forKey: .code),
            accentColorHex: try c.decodeIfPresent(String.self, forKey: .accentColorHex),
            seed: try c.decodeIfPresent(Int.self, forKey: .seed)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(kicker, forKey: .kicker)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(venue, forKey: .venue)
        try c.encodeIfPresent(dateText, forKey: .dateText)
        try c.encodeIfPresent(timeText, forKey: .timeText)
        try c.encodeIfPresent(seatText, forKey: .seatText)
        try c.encodeIfPresent(code, forKey: .code)
        try c.encodeIfPresent(accentColorHex, forKey: .accentColorHex)
        try c.encodeIfPresent(seed, forKey: .seed)
    }
}

extension HermesSparkline {
    private enum CodingKeys: String, CodingKey {
        case label, valueText, deltaText, trend, colorHex, points, caption
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawTrend = try c.decodeIfPresent(String.self, forKey: .trend)
        self.init(
            label: try c.decode(String.self, forKey: .label),
            valueText: try c.decode(String.self, forKey: .valueText),
            deltaText: try c.decodeIfPresent(String.self, forKey: .deltaText),
            trend: rawTrend.flatMap(Trend.init(rawValue:)) ?? .flat,
            colorHex: try c.decodeIfPresent(String.self, forKey: .colorHex),
            points: try c.decodeIfPresent([Double].self, forKey: .points) ?? [],
            caption: try c.decodeIfPresent(String.self, forKey: .caption)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(label, forKey: .label)
        try c.encode(valueText, forKey: .valueText)
        try c.encodeIfPresent(deltaText, forKey: .deltaText)
        try c.encode(trend, forKey: .trend)
        try c.encodeIfPresent(colorHex, forKey: .colorHex)
        // JSONEncoder throws on non-finite doubles; the view drops them anyway, so drop
        // them here too rather than letting one NaN point fail base64URLPayload()/store.
        try c.encode(points.filter(\.isFinite), forKey: .points)
        try c.encodeIfPresent(caption, forKey: .caption)
    }
}

extension HermesScoreBoard {
    private enum CodingKeys: String, CodingKey {
        case homeName, homeScore, homeColorHex, awayName, awayScore, awayColorHex
        case statusText, detail, winner
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawWinner = try c.decodeIfPresent(String.self, forKey: .winner)
        self.init(
            homeName: try c.decode(String.self, forKey: .homeName),
            homeScore: try c.decode(String.self, forKey: .homeScore),
            homeColorHex: try c.decodeIfPresent(String.self, forKey: .homeColorHex),
            awayName: try c.decode(String.self, forKey: .awayName),
            awayScore: try c.decode(String.self, forKey: .awayScore),
            awayColorHex: try c.decodeIfPresent(String.self, forKey: .awayColorHex),
            statusText: try c.decodeIfPresent(String.self, forKey: .statusText),
            detail: try c.decodeIfPresent(String.self, forKey: .detail),
            winner: rawWinner.flatMap(Winner.init(rawValue:)) ?? .none
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(homeName, forKey: .homeName)
        try c.encode(homeScore, forKey: .homeScore)
        try c.encodeIfPresent(homeColorHex, forKey: .homeColorHex)
        try c.encode(awayName, forKey: .awayName)
        try c.encode(awayScore, forKey: .awayScore)
        try c.encodeIfPresent(awayColorHex, forKey: .awayColorHex)
        try c.encodeIfPresent(statusText, forKey: .statusText)
        try c.encodeIfPresent(detail, forKey: .detail)
        if winner != .none { try c.encode(winner, forKey: .winner) }
    }
}

// MARK: - HermesSeat / HermesSeatRow (lenient: state and row flags may be omitted)

extension HermesSeat {
    private enum CodingKeys: String, CodingKey { case id, letter, state }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decode(String.self, forKey: .id),
            letter: try c.decode(String.self, forKey: .letter),
            state: try c.decodeIfPresent(State.self, forKey: .state) ?? .available
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(letter, forKey: .letter)
        try c.encode(state, forKey: .state)
    }
}

extension HermesSeatRow {
    private enum CodingKeys: String, CodingKey {
        case rowNumber, seats, aisleAfterIndices, isExitRow, isBulkhead, hasExtraLegroom
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            rowNumber: try c.decode(Int.self, forKey: .rowNumber),
            seats: try c.decode([HermesSeat].self, forKey: .seats),
            aisleAfterIndices: try c.decodeIfPresent([Int].self, forKey: .aisleAfterIndices) ?? [],
            isExitRow: try c.decodeIfPresent(Bool.self, forKey: .isExitRow) ?? false,
            isBulkhead: try c.decodeIfPresent(Bool.self, forKey: .isBulkhead) ?? false,
            hasExtraLegroom: try c.decodeIfPresent(Bool.self, forKey: .hasExtraLegroom) ?? false
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(rowNumber, forKey: .rowNumber)
        try c.encode(seats, forKey: .seats)
        if !aisleAfterIndices.isEmpty { try c.encode(aisleAfterIndices, forKey: .aisleAfterIndices) }
        if isExitRow { try c.encode(true, forKey: .isExitRow) }
        if isBulkhead { try c.encode(true, forKey: .isBulkhead) }
        if hasExtraLegroom { try c.encode(true, forKey: .hasExtraLegroom) }
    }
}

// MARK: - HermesTextStyle (lenient: role/weight may be omitted)

extension HermesTextStyle {
    private enum CodingKeys: String, CodingKey {
        case role, weight, colorHex, alignment
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            role: try c.decodeIfPresent(Role.self, forKey: .role) ?? .body,
            weight: try c.decodeIfPresent(Weight.self, forKey: .weight) ?? .regular,
            colorHex: try c.decodeIfPresent(String.self, forKey: .colorHex),
            alignment: try c.decodeIfPresent(String.self, forKey: .alignment)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(role, forKey: .role)
        try c.encode(weight, forKey: .weight)
        try c.encodeIfPresent(colorHex, forKey: .colorHex)
        try c.encodeIfPresent(alignment, forKey: .alignment)
    }
}

// MARK: - Convenience JSON codecs

public extension HermesLayout {
    /// Decode a `HermesLayout` from raw JSON data.
    static func decode(from data: Data) throws -> HermesLayout {
        try JSONDecoder().decode(HermesLayout.self, from: data)
    }

    /// Decode from a JSON string.
    static func decode(fromJSONString string: String) throws -> HermesLayout {
        guard let data = string.data(using: .utf8) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Not UTF-8"))
        }
        return try decode(from: data)
    }

    /// Encode to pretty-printed JSON data.
    func encoded(pretty: Bool = false) throws -> Data {
        let enc = JSONEncoder()
        if pretty { enc.outputFormatting = [.prettyPrinted, .sortedKeys] }
        return try enc.encode(self)
    }

    // MARK: URL-embedded transport (used by the iMessage extension)

    /// Base64url-encode the compact JSON so it survives inside an `MSMessage.url` query item.
    func base64URLPayload() throws -> String {
        let data = try encoded()
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Query item name that carries the base64url layout payload inside a message URL.
    static var messagePayloadQueryItem: String { "p" }

    /// Decode the embedded layout from an MSMessage's URL. Lives in the package (not the
    /// extension) so the EXACT wire shapes real senders produce are unit-testable — the
    /// Photon delivery gap proved that transport-shape coverage can't stop at
    /// base64URLPayload round-trips. Supported shapes:
    ///   1. hermesshare://card?p=<base64url>          (our own scheme)
    ///   2. https://any.host/anything?x=1&p=<base64url> (Photon customizedMiniApp — https
    ///      only; the payload rides in the query string, extra query items are ignored)
    ///   3. data:application/json;base64,<b64>        (Linq's imessage_app part)
    static func decode(fromMessageURL url: URL) -> HermesLayout? {
        // Shape 3: data: URL — the payload is everything after the first comma, already
        // base64 (standard or base64url; decode() handles both).
        if url.scheme == "data" {
            let raw = url.absoluteString
            guard let commaIndex = raw.firstIndex(of: ",") else { return nil }
            let payload = String(raw[raw.index(after: commaIndex)...])
            guard !payload.isEmpty else { return nil }
            return try? HermesLayout.decode(base64URLPayload: payload)
        }

        // Shapes 1 & 2: any scheme/host with a `p` query item.
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let payload = components.queryItems?.first(where: { $0.name == messagePayloadQueryItem })?.value,
              !payload.isEmpty
        else { return nil }
        return try? HermesLayout.decode(base64URLPayload: payload)
    }

    /// Inverse of `base64URLPayload()`.
    static func decode(base64URLPayload payload: String) throws -> HermesLayout {
        var b64 = payload
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        // Restore padding.
        while b64.count % 4 != 0 { b64.append("=") }
        guard let data = Data(base64Encoded: b64) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Bad base64url payload"))
        }
        return try decode(from: data)
    }
}
