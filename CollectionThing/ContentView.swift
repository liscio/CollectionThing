//
//  ContentView.swift
//  CollectionThing
//
//  Created by Christopher Liscio on 2019-11-17.
//  Copyright © 2019 Christopher Liscio. All rights reserved.
//

import SwiftUI
import Combine

struct WrappedLayout<Item: Identifiable> {
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
    let rowHeight: CGFloat
    
    init(items: [Item], columns: Int) {
        let rowHeight: CGFloat = 80
        
        func rangeForRow(_ index: Int) -> Range<Int> {
            return ((index * columns) ..< ((index + 1) * columns)).clamped(to: items.indices)
        }
        
        func frameForRow(_ index: Int) -> CGRect {
            return CGRect(x: 0, y: CGFloat(index) * rowHeight, width: 1, height: rowHeight)
        }
        
        let (quotient, remainder) = items.count.quotientAndRemainder(dividingBy: columns)
        let rowCount = (remainder > 0) ? quotient + 1 : quotient
        
        self.items = items
        self.rows = (0 ..< rowCount).map { Row(id: $0, frame: frameForRow($0), items: items[rangeForRow($0)]) }
        self.columns = columns
        self.contentSize = CGSize(width: 1, height: CGFloat(rowCount) * rowHeight)
        self.rowHeight = rowHeight
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

struct Item: Identifiable {
    let id = UUID()
    let title: String
}

struct ItemView: View {
    let title: String
    init(item: Item) {
        title = item.title
    }
    
    var body: some View {
        Color(.purple)
            .overlay(Text(title)
                .font(.system(.headline))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity), alignment: .center)
    }
}

final class Store: ObservableObject {
    @Published var value: WrappedLayout<Item>
    init() {
        self.value = WrappedLayout(items: (0 ..< 50000).map { Item(title: "\($0)") }, columns: 8)
    }
}

struct ContentView: View {
    
    @ObservedObject var store: Store
    init() {
        self.store = Store()
    }
    
    @State var fixedBounds: CGRect = .zero
    @State var lastQueryRect: CGRect = .zero
    @State var visibleRowBounds: CGRect = .zero
    @State var visibleRows: [WrappedLayout<Item>.Row] = []
    
    var body: some View {
        VStack {
            ScrollView {
                ZStack(alignment: .top) {
                    MovingView()
                        .frame(height: 0)
                    
                    Color.clear
                        .frame(
                            width: self.store.value.contentSize.width,
                            height: self.store.value.contentSize.height
                        )
                        .hidden()
                    
                    VStack(spacing: 0) {
                        ForEach(self.visibleRows) { row in
                            HStack(spacing: 0) {
                                ForEach(row.items) { item in
                                    ItemView(item: item)
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
                    
                    let rows = self.store.value.rows(in: queryRect)
                    let bounds = (rows.first?.frame ?? .zero).union(rows.last?.frame ?? .zero)
                    
                    if rows.map({ $0.id }) != self.visibleRows.map({ $0.id }) {
                        self.visibleRows = rows
                        self.visibleRowBounds = bounds
                    }
                }
            }
        }
    }
    
    struct MovingView: View {
        var body: some View {
            GeometryReader { proxy in
                Color.clear.hidden().preference(key: ViewFrames.self, value: [.movingView: proxy.frame(in: .global)])
            }.frame(height: 0)
        }
    }
    
    struct FixedView: View {
        var body: some View {
            GeometryReader { proxy in
                Color.clear.hidden().preference(key: ViewFrames.self, value: [.fixedView: proxy.frame(in: .global)])
            }
        }
    }
    
    struct ViewFrames: PreferenceKey {
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
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
