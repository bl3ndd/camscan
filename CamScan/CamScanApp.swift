//
//  CamScanApp.swift
//  CamScan
//
//  Created by Evgeny Varzin on 28.03.2026.
//

import SwiftUI
import SwiftData

@main
struct CamScanApp: App {
    var body: some Scene {
        WindowGroup {
            DocumentListView()
        }
        .modelContainer(for: ScannedDocument.self)
    }
}
