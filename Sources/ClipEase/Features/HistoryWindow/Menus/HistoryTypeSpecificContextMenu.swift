import SwiftUI

struct HistoryTypeSpecificContextMenu: View {
    let item: HistoryPreviewItem
    let onOpenLink: (ClipboardItem.ID?) -> Void
    let onCopyLinkURL: (ClipboardItem.ID?) -> Void
    let onCopyMarkdownLink: (ClipboardItem.ID?) -> Void
    let onCopyColorHex: (ClipboardItem.ID?) -> Void
    let onCopyColorRGB: (ClipboardItem.ID?) -> Void
    let onOpenImage: (ClipboardItem.ID?) -> Void
    let onCopyImage: (ClipboardItem.ID?) -> Void
    let onCopyImagePath: (ClipboardItem.ID?) -> Void
    let onRevealImageInFinder: (ClipboardItem.ID?) -> Void
    let onOpenFile: (ClipboardItem.ID?) -> Void
    let onCopyFile: (ClipboardItem.ID?) -> Void
    let onCopyFilePaths: (ClipboardItem.ID?) -> Void
    let onRevealFilesInFinder: (ClipboardItem.ID?) -> Void

    var body: some View {
        switch item.type {
        case .link:
            Button(L("打开链接")) {
                onOpenLink(item.id)
            }

            Button(L("复制链接地址")) {
                onCopyLinkURL(item.id)
            }

            Button(L("复制为 Markdown 链接")) {
                onCopyMarkdownLink(item.id)
            }

            Divider()
        case .color:
            Button(L("复制 HEX")) {
                onCopyColorHex(item.id)
            }

            Button(L("复制 RGB")) {
                onCopyColorRGB(item.id)
            }

            Divider()
        case .image:
            Button(L("打开图片")) {
                onOpenImage(item.id)
            }

            Button(L("复制图像")) {
                onCopyImage(item.id)
            }

            Button(L("复制图片路径")) {
                onCopyImagePath(item.id)
            }

            Button(L("在 Finder 中显示")) {
                onRevealImageInFinder(item.id)
            }

            Divider()
        case .file:
            Button(L("打开文件")) {
                onOpenFile(item.id)
            }

            Button(L("复制文件")) {
                onCopyFile(item.id)
            }

            Button(L("复制路径")) {
                onCopyFilePaths(item.id)
            }

            Button(L("在 Finder 中显示")) {
                onRevealFilesInFinder(item.id)
            }

            Divider()
        case .text:
            EmptyView()
        }
    }
}
