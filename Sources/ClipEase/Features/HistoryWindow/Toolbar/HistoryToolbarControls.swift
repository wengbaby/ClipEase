import SwiftUI

struct HistoryResultCountBadge: View {
    let filteredCount: Int
    let totalCount: Int
    let foregroundStyle: Color

    var body: some View {
        Text("\(filteredCount) / \(totalCount)")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(foregroundStyle)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.45))
            .clipShape(Capsule())
            .help(L("当前筛选结果数量 / 全部数量"))
    }
}

struct HistoryAuthorizationButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.lock")
                    .font(.system(size: 12, weight: .semibold))

                Text(L("请授权"))
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(Color(red: 0.78, green: 0.36, blue: 0.08))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.76))
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(
                        Color(red: 0.78, green: 0.36, blue: 0.08).opacity(0.55),
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .historyRailControlStyle()
        .help(L("点击打开辅助功能权限设置"))
    }
}
