import Foundation

enum SearchFieldLayoutPolicy {
    static func inputWidth(
        availableWidth: CGFloat,
        hasTokens: Bool
    ) -> CGFloat {
        hasTokens ? max(72, availableWidth * 0.5) : max(24, availableWidth - 3)
    }
}
