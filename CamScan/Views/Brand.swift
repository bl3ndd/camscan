import SwiftUI
import UIKit

extension Color {
    /// The app's accent: deep indigo, lighter in dark mode. Defined in code rather than
    /// only in the asset catalog, so it applies everywhere regardless of build settings.
    static let brand = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.506, green: 0.549, blue: 0.973, alpha: 1)
            : UIColor(red: 0.310, green: 0.275, blue: 0.898, alpha: 1)
    })
}
