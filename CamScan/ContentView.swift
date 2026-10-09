//
//  ContentView.swift
//  CamScan
//
//  Created by Evgeny Varzin on 28.03.2026.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        DocumentListView()
    }
}

#Preview {
    ContentView()
        .modelContainer(for: ScannedDocument.self, inMemory: true)
}
