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
    @StateObject private var store = StoreService()
    @StateObject private var appLock = AppLock()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            DocumentListView()
                .overlay {
                    // Also hides documents in the app switcher snapshot.
                    if store.isPurchased && (appLock.isLocked || (AppLock.isEnabled && scenePhase != .active)) {
                        LockScreen()
                    }
                }
                .environmentObject(store)
                .environmentObject(appLock)
        }
        .modelContainer(for: [ScannedDocument.self, Folder.self])
        .onChange(of: scenePhase) { _, phase in
            if phase == .background && store.isPurchased {
                appLock.lock()
            }
        }
    }
}
