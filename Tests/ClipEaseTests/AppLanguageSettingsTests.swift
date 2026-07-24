import Foundation
import Testing
@testable import ClipEase

@Test func followsChineseSystemLanguage() {
    #expect(AppLanguage.resolve(preference: .system, preferredLanguages: ["zh-Hans-CN"]) == .simplifiedChinese)
}

@Test func followsNonChineseSystemLanguageWithEnglishFallback() {
    #expect(AppLanguage.resolve(preference: .system, preferredLanguages: ["fr-FR"]) == .english)
}

@Test func explicitLanguageOverridesSystemLanguage() {
    #expect(AppLanguage.resolve(preference: .english, preferredLanguages: ["zh-Hans-CN"]) == .english)
    #expect(AppLanguage.resolve(preference: .simplifiedChinese, preferredLanguages: ["en-US"]) == .simplifiedChinese)
}

@Test func translatesKnownInterfaceTextOnlyForEnglish() {
    #expect(AppLocalization.text("通用", preference: .english, preferredLanguages: ["zh-Hans"]) == "General")
    #expect(AppLocalization.text("通用", preference: .system, preferredLanguages: ["zh-Hans"]) == "通用")
}

@Test func translatesDynamicCardMetadataForEnglish() {
    #expect(AppLocalization.text("12 个字符", preference: .english, preferredLanguages: ["en-US"]) == "12 characters")
    #expect(AppLocalization.text("7 分钟前", preference: .english, preferredLanguages: ["en-US"]) == "7 min ago")
    #expect(AppLocalization.text("2 小时前", preference: .english, preferredLanguages: ["en-US"]) == "2 hr ago")
    #expect(AppLocalization.text("3 天前", preference: .english, preferredLanguages: ["en-US"]) == "3 days ago")
    #expect(AppLocalization.text("来自 ChatGPT", preference: .english, preferredLanguages: ["en-US"]) == "From ChatGPT")
    #expect(AppLocalization.text("2 个分组，9 条内容", preference: .english, preferredLanguages: ["en-US"]) == "2 groups, 9 items")
}

@Test func translatesEditorAndRuntimeStatusForEnglish() {
    let language: AppLanguage = .english
    let preferredLanguages = ["en-US"]
    #expect(AppLocalization.text("新建文本", preference: language, preferredLanguages: preferredLanguages) == "New Text")
    #expect(AppLocalization.text("创建纯文本", preference: language, preferredLanguages: preferredLanguages) == "Create Plain Text")
    #expect(AppLocalization.text("保存更改？", preference: language, preferredLanguages: preferredLanguages) == "Save Changes?")
    #expect(AppLocalization.text("00:15 恢复", preference: language, preferredLanguages: preferredLanguages) == "Resume at 00:15")
}

@Test func translatesDynamicSettingsSummariesForEnglish() {
    let language: AppLanguage = .english
    let preferredLanguages = ["en-US"]

    #expect(AppLocalization.text("最近 69 条，平均 49.5 ms，最高 2572.4 ms，CPU 7.9%，内存 217.8 MB", preference: language, preferredLanguages: preferredLanguages) == "Latest 69: avg 49.5 ms, max 2572.4 ms, CPU 7.9%, memory 217.8 MB")
    #expect(AppLocalization.text("最近 69 条采样事件", preference: language, preferredLanguages: preferredLanguages) == "69 recent sampled events")
    #expect(AppLocalization.text("Text 296.1KB/82条", preference: language, preferredLanguages: preferredLanguages) == "Text 296.1KB/82 items")
    #expect(AppLocalization.text("共 138 条，占用 50.1 MB\nText 296.1KB/82 items\nPinned 0b/0 items", preference: language, preferredLanguages: preferredLanguages) == "138 items, using 50.1 MB\nText 296.1KB/82 items\nPinned 0b/0 items")
    #expect(AppLocalization.text("当前版本 2.4.0 已是 GitHub 最新正式 Release。", preference: language, preferredLanguages: preferredLanguages) == "Version 2.4.0 is the latest stable release on GitHub.")
}

@Test func translatesAppearanceEnumTitlesForEnglish() {
    let language: AppLanguage = .english
    let preferredLanguages = ["en-US"]

    #expect(AppLocalization.text("霜雾", preference: language, preferredLanguages: preferredLanguages) == "Frosted")
    #expect(AppLocalization.text("紫外光", preference: language, preferredLanguages: preferredLanguages) == "Ultraviolet")
    #expect(AppLocalization.text("窗口标题", preference: language, preferredLanguages: preferredLanguages) == "Window Title")
    #expect(AppLocalization.text("半粗", preference: language, preferredLanguages: preferredLanguages) == "Semibold")
}

@Test func translatesScreenshotRegressionPromptsForEnglish() {
    let language: AppLanguage = .english
    let preferredLanguages = ["en-US"]

    #expect(AppLocalization.text("正在记录新的剪贴板内容", preference: language, preferredLanguages: preferredLanguages) == "Recording new clipboard content")
    #expect(AppLocalization.text("发现数据问题", preference: language, preferredLanguages: preferredLanguages) == "Data Issues Found")
    #expect(AppLocalization.text("清空图标缓存？", preference: language, preferredLanguages: preferredLanguages) == "Clear Icon Cache?")
    #expect(AppLocalization.text("此操作只会删除来源 App 图标缓存，不会删除历史记录。后续新复制内容会重新生成图标缓存。", preference: language, preferredLanguages: preferredLanguages) == "This only removes source-app icon cache files. It does not delete history. New copied items will recreate the icon cache.")
    #expect(AppLocalization.text("已打开诊断数据目录", preference: language, preferredLanguages: preferredLanguages) == "Diagnostics folder opened")
    #expect(AppLocalization.text("已按当前策略清理诊断日志", preference: language, preferredLanguages: preferredLanguages) == "Diagnostic logs cleaned using the current policy")
    #expect(AppLocalization.text("只看置顶", preference: language, preferredLanguages: preferredLanguages) == "Showing pinned items only")
    #expect(AppLocalization.text("缺失图片：0\n缺失富文本：0\n孤立附件：184\n孤立附件占用：28 MB", preference: language, preferredLanguages: preferredLanguages) == "Missing images: 0\nMissing rich-text files: 0\nOrphaned attachments: 184\nOrphaned attachment storage: 28 MB")
    #expect(AppLocalization.text("保存期限已改为：Keep Forever", preference: language, preferredLanguages: preferredLanguages) == "Retention period changed to: Keep Forever")
    #expect(AppLocalization.text("Pinned 0b/0条", preference: language, preferredLanguages: preferredLanguages) == "Pinned 0b/0 items")
    #expect(AppLocalization.text("此操作只会删除没有被当前历史记录引用的图片、缩略图和富文本文件，不会删除历史记录。", preference: language, preferredLanguages: preferredLanguages) == "This only removes images, thumbnails, and rich-text files that are not referenced by current history. It does not delete history records.")
    #expect(AppLocalization.text("此操作会删除所有普通和置顶记录，以及已保存的图片文件。", preference: language, preferredLanguages: preferredLanguages) == "This will delete all regular and pinned items, along with saved image files.")
}

@Test func translatesHelpContentAndShortcutAccessibilityForEnglish() {
    let language: AppLanguage = .english
    let preferredLanguages = ["en-US"]

    #expect(AppLocalization.text("快速开始", preference: language, preferredLanguages: preferredLanguages) == "Quick Start")
    #expect(AppLocalization.text("选中卡片后按空格，可预览文字、图片、链接和文件。", preference: language, preferredLanguages: preferredLanguages) == "Press Space on a selected card to preview text, images, links, and files.")
    #expect(AppLocalization.text("复制 / 复制纯文本", preference: language, preferredLanguages: preferredLanguages) == "Copy / Copy Plain Text")
    #expect(AppLocalization.text("没有新记录", preference: language, preferredLanguages: preferredLanguages) == "No New Records")
    #expect(AppLocalization.text("快捷键 ⌘W", preference: language, preferredLanguages: preferredLanguages) == "Shortcut ⌘W")
}
