# 轻贴 ClipEase

轻贴 ClipEase 是一款轻量的 macOS 菜单栏剪贴板历史工具，在本地保存近期剪贴板内容，支持快速搜索、预览和粘贴，适合在日常工作中快速找回复制过的文字、图片、链接、颜色、富文本和文件。

## 功能

- **菜单栏常驻**：紧凑的历史记录窗口，随时呼出查看
- **多类型记录**：支持文字、图片、链接、颜色、富文本和文件
- **快速搜索**：全文搜索，快速定位历史记录
- **灵活筛选**：按分组、类型、收藏筛选历史记录
- **预览与编辑**：支持内容预览、富文本编辑和删除
- **多种粘贴方式**：双击、回车、快捷键均可粘贴
- **分组管理**：自定义分组、颜色标记和排序
- **暂停记录**：临时暂停剪贴板监听，保护隐私
- **忽略指定 App**：设置忽略名单，不记录特定应用的内容
- **全局快捷键**：自定义快捷键快速打开历史窗口
- **数据本地存储**：SQLite 本地存储，支持导出、导入和备份
- **声音反馈**：复制和粘贴时的音效提示

## 系统要求

- macOS 13.0 或更高版本
- 从源码构建需要 Swift 6.1 或更高版本

## 安装

从 [Releases](https://github.com/wengbaby/ClipEase/releases) 页面下载最新的 DMG 文件，打开后将 ClipEase 拖入 Applications 文件夹即可。

首次运行时，建议在系统设置中授予辅助功能权限，以启用自动粘贴功能。

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
│   ├── Sounds/
│   └── Support/
├── Sources/
│   └── ClipEase/
│       ├── App/            # 应用入口与生命周期
│       ├── Core/           # 核心模型、存储、服务与工具
│       │   ├── Models/     # 数据模型
│       │   ├── Recording/  # 录制控制
│       │   ├── Services/   # OCR 等服务
│       │   ├── Settings/   # 设置项
│       │   ├── Storage/    # SQLite 存储与持久化
│       │   └── Utilities/  # 工具类
│       └── Features/       # 功能模块
│           ├── ClipboardMonitor/  # 剪贴板监听
│           ├── GlobalHotKey/      # 全局快捷键
│           ├── Help/              # 帮助窗口
│           ├── HistoryWindow/     # 历史记录主窗口
│           ├── PasteExecutor/     # 粘贴执行器
│           ├── RichTextEditor/    # 富文本编辑器
│           └── Settings/          # 设置窗口
├── Tests/
│   └── ClipEaseTests/
└── scripts/
    ├── build-app.sh
    └── bump_version.py
```

## 支持与交流

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

## 许可证

本项目仅供学习和个人使用。
