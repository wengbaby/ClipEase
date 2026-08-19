import SwiftUI

struct HistoryAllEmptyStateView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 42, weight: .regular))
                .foregroundStyle(Color(red: 0.18, green: 0.55, blue: 1.0))

            Text(L("复制一段文字后会显示在这里"))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 32)
    }
}

struct HistoryEmptyContentStateView: View {
    let isSearchActive: Bool
    let isSelectedGroupPinned: Bool
    let selectedGroupIDIsNotNil: Bool
    let pinnedSystemGroupColor: Color

    private var message: String {
        if !isSearchActive {
            if isSelectedGroupPinned {
                return L("暂无置顶内容")
            }

            if selectedGroupIDIsNotNil {
                return L("暂无内容")
            }
        }

        return L("没有找到匹配的历史")
    }

    private var iconName: String {
        if !isSearchActive,
           isSelectedGroupPinned {
            return "pin"
        }

        if !isSearchActive,
           selectedGroupIDIsNotNil {
            return "tray"
        }

        return "magnifyingglass"
    }

    private var tint: Color {
        if !isSearchActive,
           isSelectedGroupPinned {
            return pinnedSystemGroupColor
        }

        return Color(red: 0.18, green: 0.55, blue: 1.0)
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 38, weight: .regular))
                .foregroundStyle(tint)

            Text(message)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 32)
    }
}

struct HistoryLoadingContentStateView: View {
    var body: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)

            Text(L("正在加载历史"))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 32)
    }
}
