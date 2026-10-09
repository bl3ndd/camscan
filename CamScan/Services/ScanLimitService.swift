import Foundation

struct ScanLimitService {
    private static let dailyLimit = 3
    private static let scansKey = "daily_scans"
    private static let dateKey = "daily_scans_date"

    static var isPro: Bool {
        UserDefaults.standard.bool(forKey: "is_pro_user")
    }

    static func canScan() -> Bool {
        if isPro { return true }
        resetIfNewDay()
        return todayScans() < dailyLimit
    }

    static var remainingScans: Int {
        if isPro { return .max }
        resetIfNewDay()
        return max(0, dailyLimit - todayScans())
    }

    static func recordScan() {
        resetIfNewDay()
        let current = todayScans()
        UserDefaults.standard.set(current + 1, forKey: scansKey)
        UserDefaults.standard.set(todayString(), forKey: dateKey)
    }

    static func unlockPro() {
        UserDefaults.standard.set(true, forKey: "is_pro_user")
    }

    // MARK: - Private

    private static func todayScans() -> Int {
        UserDefaults.standard.integer(forKey: scansKey)
    }

    private static func resetIfNewDay() {
        let saved = UserDefaults.standard.string(forKey: dateKey) ?? ""
        if saved != todayString() {
            UserDefaults.standard.set(0, forKey: scansKey)
            UserDefaults.standard.set(todayString(), forKey: dateKey)
        }
    }

    private static func todayString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
