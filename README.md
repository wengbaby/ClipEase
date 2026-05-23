# 轻贴 ClipEase

轻贴 ClipEase 是一款轻量的 macOS 菜单栏剪贴板历史工具。

它会在本地保存近期剪贴板内容，支持快速搜索、预览和粘贴，适合在日常工作中快速找回复制过的文字、图片、链接、颜色、富文本和文件。

## 功能

- 菜单栏常驻，提供紧凑的历史记录窗口
- 支持文字、图片、链接、颜色、富文本和文件记录
- 支持搜索、筛选、收藏、分组、预览、编辑和删除
- 支持双击、回车和快捷键快速粘贴
- 支持暂停记录和忽略指定 App
- 数据本地存储，支持导出、导入和备份

## 系统要求

- macOS 13.0 或更高版本
- 从源码构建需要 Swift 6.1 或更高版本

## 构建

构建 Swift Package：

```bash
swift build -c release --product ClipEase
```

构建 macOS App bundle：

```bash
scripts/build-app.sh --bump none
```

构建并启动 App：

```bash
scripts/build-app.sh --bump none --run
```

构建产物位于 `.build/ClipEase.app`。

## 仓库结构

```text
.
├── Package.swift
├── README.md
├── Resources/
│   ├── ClipEase.icns
│   ├── Info.plist
│   └── Sounds/
├── Sources/
│   └── ClipEase/
├── docs/
│   ├── README.md
│   ├── README_zh.md
│   └── images/
└── scripts/
    ├── build-app.sh
    └── bump_version.py
```

## 文档

目录结构说明见 [docs/README_zh.md](docs/README_zh.md)，也可切换到 [English](docs/README.md)。

## 交流与支持

欢迎扫码加入 轻贴ClipEase 交流群，反馈问题、交流使用体验或提出新功能建议：

<p>
  <img src="docs/images/WechatQun.png" alt="轻贴ClipEase 交流群" width="260">
</p>

可以请我喝杯咖啡，或者随手赞赏支持一下，谢谢！

<table>
  <tr>
    <td align="center">
      <img src="docs/images/Alipay.jpg" alt="支付宝赞赏" width="260">
    </td>
    <td align="center">
      <img src="docs/images/WeChat.png" alt="微信赞赏" width="260">
    </td>
  </tr>
  <tr>
    <td align="center">支付宝赞赏</td>
    <td align="center">微信赞赏</td>
  </tr>
</table>

## License

本仓库暂未发布开源许可证。
