import SwiftUI
import AppKit

@MainActor
struct ScrollRequest {
    let offsetX: CGFloat
    let animated: Bool
    let suppressUserOffsetSave: Bool
}
