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
    private let container: ModelContainer

    init() {
        let schema = Schema([ScannedDocument.self, Folder.self])
        #if DEBUG
        if UITestSeed.isActive {
            container = try! ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            UITestSeed.seed(container.mainContext)
            return
        }
        #endif
        do {
            container = try ModelContainer(for: schema)
        } catch {
            fatalError("Couldn't open the document store: \(error)")
        }
    }

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
                .tint(.brand)
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            if phase == .background && store.isPurchased {
                appLock.lock()
            }
        }
    }
}
