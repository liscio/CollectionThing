//
//  FastCollection.swift
//  CollectionThing
//
//  Created by Peter Livesey on 11/20/19.
//  Copyright © 2019 Christopher Liscio. All rights reserved.
//

import SwiftUI
import Combine

fileprivate struct WrappedLayout<Item: Identifiable> {
    /// The items to be laid out
    let items: [Item]

    /// The (maximum) number of items to be placed in a row
    let columns: Int

    /// A model representing the row of items
    struct Row: Identifiable {
        let id: Int
        let frame: CGRect
        let items: ArraySlice<Item>

        func translatingY(_ y: CGFloat) -> Row {
            return Row(id: id, frame: frame.offsetBy(dx: 0, dy: y), items: items)
        }

        func width(_ width: CGFloat) -> Row {
            return Row(id: id, frame: CGRect(x: frame.origin.x, y: frame.origin.y, width: width, height: frame.size.height), items: items)
        }
    }

    let contentSize: CGSize
    let rows: [Row]

    init(items: [Item], columns: Int, heightForItem: (Item) -> CGFloat) {
        func rangeForRow(_ index: Int) -> Range<Int> {
            return ((index * columns) ..< ((index + 1) * columns)).clamped(to: items.indices)
        }

        var offset: CGFloat = 0
        let rowFrames: [CGRect] = items.map { item in
            let y = offset
            let height = heightForItem(item)
            offset += height
            return CGRect(x: 0, y: y, width: 1, height: height)
        }

        let (quotient, remainder) = items.count.quotientAndRemainder(dividingBy: columns)
        let rowCount = (remainder > 0) ? quotient + 1 : quotient

        self.items = items
        self.rows = (0 ..< rowCount).map { Row(id: $0, frame: rowFrames[$0], items: items[rangeForRow($0)]) }
        self.columns = columns
        self.contentSize = CGSize(width: 1, height: rowFrames.map { $0.height }.reduce(0, +))
    }

    struct LayoutItem: Identifiable {
        var id: Item.ID { item.id }
        let item: Item
        let frame: CGRect
    }

    func rows(in rect: CGRect) -> [Row] {
        return rows.filter { $0.frame.intersects(rect) }.map { $0.width(rect.width) }
    }
}

public struct FastCollection<T: Identifiable, V: View>: View {
    public let viewForItem: (T) -> V
    public let buffer: CGFloat
    private let layout: WrappedLayout<T>

    @State private var fixedBounds: CGRect = .zero
    @State private var lastQueryRect: CGRect = .zero
    @State private var visibleRowBounds: CGRect = .zero
    @State private var visibleRows: [WrappedLayout<T>.Row] = []

    public init(items: [T], columns: Int = 1, buffer: CGFloat = 0, itemHeight: CGFloat, viewForItem: @escaping (T) -> V) {
        self.init(items: items, columns: columns, buffer: buffer, heightForItem: { _ in itemHeight }, viewForItem: viewForItem)
    }
    
    public init(items: [T], columns: Int = 1, buffer: CGFloat = 0, heightForItem: (T) -> CGFloat, viewForItem: @escaping (T) -> V) {
        self.layout = WrappedLayout<T>(items: items, columns: columns, heightForItem: heightForItem)
        self.viewForItem = viewForItem
        self.buffer = buffer
    }

    public var body: some View {
        ScrollView {
            ZStack(alignment: .top) {
                MovingView()
                    .frame(height: 0)

                Color.clear
                    .frame(
                        width: layout.contentSize.width,
                        height: layout.contentSize.height
                )
                    .hidden()

                VStack(spacing: 0) {
                    ForEach(self.visibleRows) { row in
                        HStack(spacing: 0) {
                            ForEach(row.items) { item in
                                self.viewForItem(item)
                            }
                        }
                    }
                }
                .frame(
                    width: self.fixedBounds.width,
                    height: self.visibleRowBounds.height,
                    alignment: .topLeading
                )
                    .position(
                        x: self.fixedBounds.midX,
                        y: self.visibleRowBounds.midY
                )
            }
        }
        .background(FixedView().edgesIgnoringSafeArea(.all))
        .onPreferenceChange(ViewFrames.self) { values in
            let fixedBounds = values[.fixedView] ?? .zero
            let movingBounds = values[.movingView] ?? .zero
            let boundsDirty = fixedBounds != self.fixedBounds
            if boundsDirty {
                self.fixedBounds = values[.fixedView] ?? .zero
            }

            #if os(iOS)
            let visibleRect = CGRect(
                x: movingBounds.origin.x,
                y: (fixedBounds.origin.y - movingBounds.origin.y),
                width: fixedBounds.width,
                height: fixedBounds.height)
            #else
            let visibleRect = CGRect(
                x: movingBounds.origin.x,
                y: movingBounds.origin.y - fixedBounds.height,
                width: fixedBounds.width,
                height: fixedBounds.height)
            #endif

            let queryRect = visibleRect.insetBy(dx: 0, dy: -(visibleRect.height / 8))

            if boundsDirty || self.lastQueryRect.isEmpty || self.lastQueryRect.intersection(queryRect).height < (visibleRect.height * 1.2) {
                self.lastQueryRect = queryRect

                let queryRectWithBuffer = CGRect(x: queryRect.minX,
                                                 y: queryRect.minY - self.buffer,
                                                 width: queryRect.width,
                                                 height: queryRect.height + 2 * self.buffer)
                let rows = self.layout.rows(in: queryRectWithBuffer)
                let bounds = (rows.first?.frame ?? .zero).union(rows.last?.frame ?? .zero)

                if rows.map({ $0.id }) != self.visibleRows.map({ $0.id }) {
                    self.visibleRows = rows
                    self.visibleRowBounds = bounds
                }
            }
        }
    }

    private struct MovingView: View {
        var body: some View {
            GeometryReader { proxy in
                Color.clear.hidden().preference(key: ViewFrames.self, value: [.movingView: proxy.frame(in: .global)])
            }.frame(height: 0)
        }
    }

    private struct FixedView: View {
        var body: some View {
            GeometryReader { proxy in
                Color.clear.hidden().preference(key: ViewFrames.self, value: [.fixedView: proxy.frame(in: .global)])
            }
        }
    }
}

// Since this view uses a static var, it cannot be contained within FastCollection
fileprivate struct ViewFrames: PreferenceKey {
    enum ViewType: Int {
        case movingView
        case fixedView
    }

    static var defaultValue: [ViewType:CGRect] = [:]

    static func reduce(value: inout [ViewType:CGRect], nextValue: () -> [ViewType:CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { old, new in new })
    }

    typealias Value = [ViewType:CGRect]
}
