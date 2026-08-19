import SwiftUI

struct HistoryRetentionSettingsMenu: View {
    @ObservedObject var store: ClipboardHistoryStore
    let onShowStatus: (String) -> Void

    var body: some View {
        Menu(L("保存期限")) {
            ForEach(HistoryRetentionPolicy.allCases) { policy in
                Button {
                    store.retentionPolicy = policy
                    onShowStatus(L("保存期限：\(policy.shortTitle)"))
                } label: {
                    HStack {
                        Text(policy.title)
                        if store.retentionPolicy == policy {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }
    }
}

struct HistoryPauseMenu: View {
    let primaryTitle: String
    let onTogglePause: () -> Void
    let onPauseFor: (TimeInterval, String) -> Void
    let onPauseUntilEndOfToday: () -> Void

    var body: some View {
        Button(primaryTitle) {
            onTogglePause()
        }

        Button(L("暂停 15 分钟")) {
            onPauseFor(15 * 60, L("已暂停 15 分钟"))
        }

        Button(L("暂停 30 分钟")) {
            onPauseFor(30 * 60, L("已暂停 30 分钟"))
        }

        Button(L("暂停 1 小时")) {
            onPauseFor(60 * 60, L("已暂停 1 小时"))
        }

        Button(L("暂停 3 小时")) {
            onPauseFor(3 * 60 * 60, L("已暂停 3 小时"))
        }

        Button(L("暂停 6 小时")) {
            onPauseFor(6 * 60 * 60, L("已暂停 6 小时"))
        }

        Button(L("截止到今日")) {
            onPauseUntilEndOfToday()
        }
    }
}
