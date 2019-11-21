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
        let id: [Item.ID]
        let frame: CGRect
        let items: ArraySlice<Item>

        init(frame: CGRect, items: ArraySlice<Item>) {
            self.id = items.map { $0.id }
            self.frame = frame
            self.items = items
        }

        func width(_ width: CGFloat) -> Row {
            return Row(frame: CGRect(x: frame.origin.x, y: frame.origin.y, width: width, height: frame.size.height), items: items)
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
        self.rows = (0..<rowCount).map { Row(frame: rowFrames[$0], items: items[rangeForRow($0)]) }

        self.columns = columns
        self.contentSize = CGSize(width: 1, height: rowFrames.map { $0.height }.reduce(0, +))
    }

    struct LayoutItem: Identifiable {
        var id: Item.ID { item.id }
        let item: Item
        let frame: CGRect
    }

    func rows(in rect: CGRect) -> [Row] {
        var returnValue = [Row]()
        let minY = rect.minY
        let maxY = rect.maxY
        for row in rows {
            if row.frame.maxY >= minY {
                returnValue.append(row.width(rect.width))
            }

            if row.frame.minY > maxY {
                // This is an optimization. If we've already gone far enough, there's no point in keeping checking.
                return returnValue
            }
        }

        return returnValue
    }
}

public struct FastCollection<T: Identifiable, V: View>: View {
    public let viewForItem: (T) -> V
    public let buffer: CGFloat
    private let layout: WrappedLayout<T>

    @State private var fixedBounds: CGRect = .zero
    @State private var lastQueryRect: CGRect = .zero

    private var visibleRows: [WrappedLayout<T>.Row] {
        let queryRectWithBuffer = CGRect(x: lastQueryRect.minX,
                                         y: lastQueryRect.minY - self.buffer,
                                         width: lastQueryRect.width,
                                         height: lastQueryRect.height + 2 * self.buffer)
        return self.layout.rows(in: queryRectWithBuffer)
    }


    public init(items: [T], columns: Int = 1, buffer: CGFloat = 0, itemHeight: CGFloat, viewForItem: @escaping (T) -> V) {
        self.init(items: items, columns: columns, buffer: buffer, heightForItem: { _ in itemHeight }, viewForItem: viewForItem)
    }

    public init(items: [T], columns: Int = 1, buffer: CGFloat = 0, heightForItem: (T) -> CGFloat, viewForItem: @escaping (T) -> V) {
        self.layout = WrappedLayout<T>(items: items, columns: columns, heightForItem: heightForItem)
        self.viewForItem = viewForItem
        self.buffer = buffer
    }

    public var body: some View {
        // Calculate these once per body call as they could be expensive calls
        let visibleRows = self.visibleRows
        let visibleRowBounds = (visibleRows.first?.frame ?? .zero).union(visibleRows.last?.frame ?? .zero)

        return ScrollView {
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
                    ForEach(visibleRows) { row in
                        HStack(spacing: 0) {
                            ForEach(row.items) { item in
                                self.viewForItem(item)
                            }
                        }
                    }
                }
                .frame(
                    width: self.fixedBounds.width,
                    height: visibleRowBounds.height,
                    alignment: .topLeading
                )
                    .position(
                        x: self.fixedBounds.midX,
                        y: visibleRowBounds.midY
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
