import SwiftUI
import LocalAuthentication

/// Face ID / passcode lock (Pro). Locks when the app goes to the background.
@MainActor
final class AppLock: ObservableObject {
    static let enabledKey = "appLockEnabled"

    @Published private(set) var isLocked: Bool

    init() {
        isLocked = UserDefaults.standard.bool(forKey: Self.enabledKey)
    }

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    func lock() {
        if Self.isEnabled {
            isLocked = true
        }
    }

    func unlock() async {
        guard isLocked else { return }
        let context = LAContext()
        let success = (try? await context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: "Unlock your documents"
        )) ?? false
        if success {
            isLocked = false
        }
    }

    /// Asks for Face ID before turning the lock on, so nobody locks themselves out by accident.
    func setEnabled(_ enabled: Bool) async -> Bool {
        if enabled {
            let context = LAContext()
            let success = (try? await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Turn on app lock"
            )) ?? false
            guard success else { return false }
        }
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
        return true
    }
}

struct LockScreen: View {
    @EnvironmentObject private var appLock: AppLock

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("CamScan is locked")
                .font(.title2.bold())
            Button("Unlock") {
                Task { await appLock.unlock() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .task { await appLock.unlock() }
    }
}
