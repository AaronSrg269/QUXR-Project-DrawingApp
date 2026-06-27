import SwiftUI

enum Theme {
    static let background    = Color(hex: "#0D0F1A")
    static let accent        = Color(hex: "#00C8D4")
    static let buttonBlue    = Color(hex: "#1A6BFF")
    static let buttonBluePressed  = Color(hex: "#1A6BD1")
    static let buttonPink    = Color(hex: "#FF66CC")
    static let buttonPinkPressed  = Color(hex: "#FF44BB")
    static let textPrimary   = Color.white
    static let textError     = Color(hex: "#FF6B61")
    static let strokeCommitted = Color(hex: "#000000")
    static let strokeCurrent   = Color(hex: "#EB2E33")
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: Double
        switch hex.count {
        case 6:
            r = Double((int >> 16) & 0xFF) / 255
            g = Double((int >>  8) & 0xFF) / 255
            b = Double( int        & 0xFF) / 255
        default:
            r = 0; g = 0; b = 0
        }
        self.init(red: r, green: g, blue: b)
    }
}
