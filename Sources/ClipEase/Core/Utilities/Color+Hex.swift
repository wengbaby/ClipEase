import SwiftUI

extension Color {
    static func clipeaseHex(_ hex: String) -> Color {
        guard let components = ClipEaseColorComponents(hex: hex) else {
            return Color(red: 0.18, green: 0.55, blue: 1.0)
        }

        return Color(red: components.red, green: components.green, blue: components.blue)
    }
}

struct ClipEaseColorComponents {
    let red: Double
    let green: Double
    let blue: Double

    init?(hex: String) {
        let trimmed = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard trimmed.count == 6,
              let value = Int(trimmed, radix: 16) else {
            return nil
        }

        self.red = Double((value >> 16) & 0xFF) / 255.0
        self.green = Double((value >> 8) & 0xFF) / 255.0
        self.blue = Double(value & 0xFF) / 255.0
    }

    var readableTextColor: Color {
        let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        return luminance > 0.58 ? Color(red: 0.12, green: 0.14, blue: 0.17) : .white
    }
}
