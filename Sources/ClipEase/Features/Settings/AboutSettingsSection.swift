import SwiftUI

private struct SupportQRCodeAssets {
    private func supportQRCode(
        name: String,
        extensionName: String,
        missingTitle: String,
        cropRect: CGRect,
        borderColor: Color,
        size: CGFloat
    ) -> some View {
        ZStack {
            if let image = supportImage(name: name, extensionName: extensionName, cropRect: cropRect) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
            } else {
                Text(L("未找到\(missingTitle)"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: size, height: size)
            }
        }
        .frame(width: size, height: size)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 4)
        }
    }

    static func supportQRCode(
        name: String,
        extensionName: String,
        missingTitle: String,
        cropRect: CGRect,
        borderColor: Color,
        size: CGFloat
    ) -> some View {
        Self().supportQRCode(
            name: name,
            extensionName: extensionName,
            missingTitle: missingTitle,
            cropRect: cropRect,
            borderColor: borderColor,
            size: size
        )
    }

    private func supportImage(name: String, extensionName: String, cropRect: CGRect) -> NSImage? {
        guard let url = Bundle.main.url(
            forResource: name,
            withExtension: extensionName,
            subdirectory: "Support"
        ) else {
            return nil
        }

        guard let image = NSImage(contentsOf: url),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let croppedImage = cgImage.cropping(to: cropRect) else {
            return NSImage(contentsOf: url)
        }

        let size = NSSize(width: cropRect.width, height: cropRect.height)
        return NSImage(cgImage: croppedImage, size: size)
    }
}

struct AboutSettingsSection: View {
    @ObservedObject var updateViewModel: SettingsUpdateViewModel

    let onOpenGitHub: () -> Void
    let onOpenSupportCommunity: () -> Void
    let onCopyVersion: () -> Void
    let onRevealDebugTools: () -> Void
    let onCheckForUpdates: () -> Void
    let onOpenRelease: (URL?) -> Void
    let onDownloadUpdate: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L("关于轻贴"))
                    .font(.system(size: 13, weight: .semibold))

                Text("ClipEase \(AppVersionInfo.displayVersion)")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
            }

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Label(L("简洁好用的 macOS 粘贴板历史助手"), systemImage: "info.circle")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button(L("打开 GitHub"), action: onOpenGitHub)
                        .buttonStyle(.bordered)

                    Button(L("复制版本号"), action: onCopyVersion)
                        .buttonStyle(.bordered)
                }
                .contentShape(Rectangle())
                .onTapGesture(perform: onRevealDebugTools)

                Divider()

                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("版本更新"))
                            .font(.system(size: 13, weight: .semibold))

                        Text(updateSubtitle)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.secondary)
                            .lineSpacing(4)
                    }

                    Spacer()

                    Toggle(L("自动检查"), isOn: $updateViewModel.isAutomaticCheckEnabled)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .font(.system(size: 12, weight: .regular))

                    Button(updateViewModel.state.isChecking ? L("检查中") : L("检查更新"), action: onCheckForUpdates)
                        .buttonStyle(.bordered)
                        .disabled(updateViewModel.state.isChecking)
                }

                updateStatusView

                Divider()

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("支持与交流"))
                            .font(.system(size: 13, weight: .semibold))

                        Text(L("加入交流群反馈问题，查看项目更新。"))
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button(L("加入交流群"), action: onOpenSupportCommunity)
                        .buttonStyle(.bordered)
                }

                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("赞赏支持"))
                            .font(.system(size: 13, weight: .semibold))

                        Text(L("感谢支持轻贴 ClipEase 的持续维护。"))
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.secondary)
                    }

                    GeometryReader { geometry in
                        let qrSize = max((geometry.size.width - 16) / 2, 170)
                        HStack(alignment: .top, spacing: 16) {
                            SupportQRCodeAssets.supportQRCode(
                                name: "Alipay",
                                extensionName: "jpg",
                                missingTitle: L("支付宝二维码"),
                                cropRect: CGRect(x: 190, y: 460, width: 635, height: 635),
                                borderColor: Color(red: 0.09, green: 0.52, blue: 0.96),
                                size: qrSize
                            )

                            SupportQRCodeAssets.supportQRCode(
                                name: "WeChat",
                                extensionName: "png",
                                missingTitle: L("微信二维码"),
                                cropRect: CGRect(x: 198, y: 115, width: 900, height: 900),
                                borderColor: Color(red: 0.12, green: 0.74, blue: 0.34),
                                size: qrSize
                            )
                        }
                    }
                    .aspectRatio(2.05, contentMode: .fit)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var updateSubtitle: String {
        updateViewModel.isAutomaticCheckEnabled
            ? L("每天静默检查一次 GitHub 最新正式 Release。")
            : L("已关闭自动检查，你仍然可以手动检查更新。")
    }

    @ViewBuilder
    private var updateStatusView: some View {
        switch updateViewModel.state {
        case .idle:
            EmptyView()
        case .checking:
            updateStatusCard(
                iconName: "arrow.triangle.2.circlepath",
                title: L("正在检查更新"),
                message: L("正在连接 GitHub 获取最新正式 Release。"),
                tint: Color(red: 0.82, green: 0.52, blue: 0.12)
            ) {
                EmptyView()
            }
        case .upToDate(let version):
            updateStatusCard(
                iconName: "checkmark.circle",
                title: L("已是最新版"),
                message: L("当前版本 \(version) 已是 GitHub 最新正式 Release。"),
                tint: Color(red: 0.18, green: 0.55, blue: 0.28)
            ) {
                Button(L("打开 Release")) {
                    onOpenRelease(nil)
                }
                .buttonStyle(.bordered)
            }
        case .updateAvailable(let info):
            updateStatusCard(
                iconName: "arrow.down.circle",
                title: L("发现新版本 ClipEase \(info.version)"),
                message: updateAvailableMessage(for: info),
                tint: Color(red: 0.18, green: 0.48, blue: 0.86)
            ) {
                if let downloadURL = info.downloadURL {
                    Button(L("下载 DMG")) {
                        onDownloadUpdate(downloadURL)
                    }
                    .buttonStyle(.borderedProminent)
                }

                Button(L("打开 Release")) {
                    onOpenRelease(info.releaseURL)
                }
                .buttonStyle(.bordered)
            }
        case .failed:
            updateStatusCard(
                iconName: "exclamationmark.circle",
                title: L("检查失败，稍后重试"),
                message: L("可能是网络或 GitHub 暂时不可用。你可以稍后重新检查，也可以打开 GitHub 自行下载。"),
                tint: Color(red: 0.78, green: 0.24, blue: 0.18)
            ) {
                Button(L("重新检查"), action: onCheckForUpdates)
                    .buttonStyle(.borderedProminent)

                Button(L("打开 Release")) {
                    onOpenRelease(nil)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func updateAvailableMessage(for info: AppUpdateInfo) -> String {
        if let publishedAt = info.publishedAt {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return L("当前版本为 \(AppVersionInfo.shortVersion)。GitHub 最新正式 Release 发布于 \(formatter.string(from: publishedAt))。")
        }

        return L("当前版本为 \(AppVersionInfo.shortVersion)。GitHub 有新的正式 Release。")
    }

    private func updateStatusCard<Actions: View>(
        iconName: String,
        title: String,
        message: String,
        tint: Color,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 7) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))

                Text(message)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)

                HStack(spacing: 8) {
                    actions()
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.1))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(tint.opacity(0.24), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
