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
                Text("未找到\(missingTitle)")
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
    let onOpenGitHub: () -> Void
    let onOpenSupportCommunity: () -> Void
    let onCopyVersion: () -> Void
    let onRevealDebugTools: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("关于轻贴")
                    .font(.system(size: 13, weight: .semibold))

                Text("ClipEase \(AppVersionInfo.displayVersion)")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
            }

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Label("简洁好用的 macOS 粘贴板历史助手", systemImage: "info.circle")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("打开 GitHub", action: onOpenGitHub)
                        .buttonStyle(.bordered)

                    Button("复制版本号", action: onCopyVersion)
                        .buttonStyle(.bordered)
                }
                .contentShape(Rectangle())
                .onTapGesture(perform: onRevealDebugTools)

                Divider()

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("支持与交流")
                            .font(.system(size: 13, weight: .semibold))

                        Text("加入交流群反馈问题，查看项目更新。")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("加入交流群", action: onOpenSupportCommunity)
                        .buttonStyle(.bordered)
                }

                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("赞赏支持")
                            .font(.system(size: 13, weight: .semibold))

                        Text("感谢支持轻贴 ClipEase 的持续维护。")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.secondary)
                    }

                    GeometryReader { geometry in
                        let qrSize = max((geometry.size.width - 16) / 2, 170)
                        HStack(alignment: .top, spacing: 16) {
                            SupportQRCodeAssets.supportQRCode(
                                name: "Alipay",
                                extensionName: "jpg",
                                missingTitle: "支付宝二维码",
                                cropRect: CGRect(x: 190, y: 460, width: 635, height: 635),
                                borderColor: Color(red: 0.09, green: 0.52, blue: 0.96),
                                size: qrSize
                            )

                            SupportQRCodeAssets.supportQRCode(
                                name: "WeChat",
                                extensionName: "png",
                                missingTitle: "微信二维码",
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
}
