//
//  ContentView.swift
//  CollectionThing
//
//  Created by Christopher Liscio on 2019-11-17.
//  Copyright © 2019 Christopher Liscio. All rights reserved.
//

import SwiftUI

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

struct ContentView: View {
    @ObservedObject private var store = Store()

    var body: some View {
        FastCollection(items: store.value, columns: 8, buffer: 100, itemHeight: 80) { item in
            ItemView(item: item)
        }
    }
}

final class Store: ObservableObject {
    @Published var value: [Item]
    init() {
        self.value = (0 ..< 50000).map { Item(title: "\($0)") }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
