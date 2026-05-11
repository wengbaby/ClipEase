# 技术方案

本文是轻贴 ClipEase 第一版的正式技术方案。第一版优先保证稳定、可验证、可持续扩展，不追求一次性完成所有高级功能。

## 1. 技术结论

第一版采用原生 macOS 技术栈：

- 语言：Swift
- UI：SwiftUI
- 系统集成：AppKit
- 菜单栏：`NSStatusItem`
- 底部浮窗：自定义 `NSPanel`
- 剪贴板：`NSPasteboard`
- 自动粘贴：Accessibility API + `CGEvent`
- 开机启动：`SMAppService`
- 本地存储：SQLite，后续可封装为 Repository
- 图片文件：Application Support 目录
- 全局快捷键：优先使用 KeyboardShortcuts Swift Package

不采用 Electron、Tauri 或 Web 技术作为第一版主方案。原因是本项目核心依赖 macOS 系统能力，原生实现更稳定、权限更清晰、资源占用更低。

## 2. macOS 版本策略

第一版建议最低支持：

- macOS 13 Ventura

原因：

- `SMAppService` 适合用于现代 Login Item。
- SwiftUI 与 AppKit 混合开发能力更成熟。
- 降低旧系统兼容成本。

后续如果需要支持 macOS 12 或更早版本，需要单独评估开机启动、窗口行为和权限提示实现。

## 3. 工程结构建议

建议目录：

```text
ClipEase/
  App/
    ClipEaseApp.swift
    AppDelegate.swift
    StatusBarController.swift
  Features/
    HistoryWindow/
    ClipboardMonitor/
    PasteExecutor/
    Settings/
    Preview/
  Core/
    Models/
    Storage/
    Permissions/
    AppInfo/
    Utilities/
  Resources/
    Assets.xcassets
    Localizable.xcstrings
  Tests/
```

原则：

- `Features` 放用户功能。
- `Core` 放可复用底层能力。
- UI 与系统能力分开，避免所有逻辑堆在 SwiftUI View 里。
- 数据访问统一走 Store/Repository，不让界面直接操作 SQLite。

## 4. 核心模块

### 4.1 AppShell

职责：

- App 生命周期。
- 菜单栏入口。
- 设置入口。
- 退出 App。
- 协调全局快捷键和底部窗口显示。

关键对象：

- `ClipEaseApp`
- `AppDelegate`
- `StatusBarController`

### 4.2 HistoryWindow

职责：

- 管理底部横向窗口。
- 根据当前屏幕计算窗口位置。
- 响应菜单栏点击和快捷键呼出。
- 处理 `Esc` 关闭。
- 搜索结果数量展示。
- 文字和链接卡片中的第一处匹配内容高亮。
- 选中卡片支持 `Command + C` 复制和 `Delete` 删除。
- 选中卡片支持 `Command + P` 置顶或取消置顶。
- 搜索框支持一键清空。
- 顶部图钉按钮可快速进入或退出置顶筛选。
- 顶部展示记录状态按钮，可暂停或恢复记录。
- 顶部展示保存期限菜单，可快速切换保存策略。
- 筛选菜单显示当前选中项。
- 按住 `Command` 时，前 9 张可见卡片右下角显示序号。
- `Command + 1-9` 可快速选中当前可见的前 9 张卡片；搜索框输入时数字键保留为文本输入。

实现：

- 使用 `NSPanel` 作为外层窗口。
- 使用 `NSHostingView` 承载 SwiftUI 内容。
- 窗口宽度等于当前屏幕可见区域宽度。
- 窗口固定在屏幕底部。
- 多屏时优先显示在鼠标所在屏幕。

### 4.3 ClipboardMonitor

职责：

- 监听系统剪贴板变化。
- 判断是否暂停。
- 判断来源 App 是否被忽略。
- 识别文字、图片、链接。
- 识别十六进制颜色值。
- 做基础去重。
- 将新记录交给 Store 保存。

实现：

- 使用 `NSPasteboard.general.changeCount` 轮询。
- 默认每 0.75 秒检查一次。
- 只在 `changeCount` 变化时读取剪贴板。
- App 自己写回剪贴板时，要标记一次内部写入，避免再次记录。

### 4.4 ClipboardStore

职责：

- 保存历史记录。
- 查询历史记录。
- 搜索和筛选。
- 置顶、删除、清空。
- 保存期限清理。

目标方案使用 SQLite：

- 一张 `clipboard_items` 表保存索引和文字内容。
- 图片文件保存在 Application Support 下的 `Images` 目录。

当前实现备注：

- 阶段 4 先使用 `~/Library/Application Support/ClipEase/history.json` 保存历史索引。
- 图片文件保存在 `~/Library/Application Support/ClipEase/Images`。
- 来源 App 图标缓存到 `~/Library/Application Support/ClipEase/AppIcons`，历史记录保存图标文件名。
- 来源 App 标题栏颜色优先取真实 App 图标中心点颜色并加深，失败时回退到默认规则。
- JSON 方案已覆盖文字、链接、图片、置顶、删除、排序和保存期限。
- 保存期限清理在启动和策略变更时执行，清理后会立即写回历史文件。
- 设置页可查看 Application Support 目录占用，并打开数据目录、图片目录和图标缓存目录。
- 设置页可将历史记录导出为 JSON 文件，导出后在 Finder 中定位文件。
- 设置页可导入轻贴导出的 JSON 文件，采用追加合并方式写入 Store。
- 当前 JSON 导入只恢复文字、链接和颜色记录；图片和富文本附件需要后续备份包格式承载实际文件。
- `history.json` 读取失败时，会移动备份为 `history-corrupt-YYYYMMDD-HHMMSS.json` 后空历史启动，避免损坏文件被覆盖。
- 批量数据、复杂搜索和发布稳定后，再迁移到 SQLite 表结构。

### 4.5 PasteExecutor

职责：

- 将历史记录写回系统剪贴板。
- 在有权限时自动粘贴到当前 App。
- 无权限时提示用户手动粘贴。

流程：

1. 关闭或隐藏轻贴底部窗口。
2. 将选中记录写入 `NSPasteboard.general`。
3. 如果允许自动粘贴，发送 `Command + V`。
4. 如果未授权，只保留剪贴板内容并提示。

右键增强：

- 文字、链接和颜色记录支持粘贴为纯文本，写入剪贴板时不携带 RTF。
- 链接记录支持用默认浏览器打开。
- 链接记录支持复制原始 URL。
- 链接记录支持复制为 Markdown 链接，格式为 `[标题](URL)`。
- 图片记录支持用系统默认图片查看器打开。
- 图片记录支持复制本地图片文件路径。
- 颜色记录支持复制 HEX 和 `rgb(r, g, b)` 格式。

### 4.6 PreviewPopover

职责：

- 空格键触发预览。
- 在当前卡片上方显示预览层。
- 图片按比例展示。
- 文本可滚动。

第一版只做查看与复制，编辑放到第二版。

### 4.7 Settings

职责：

- 保存期限。
- 全局快捷键。
- 开机自动启动。
- 暂停记录。
- 忽略 App。
- 清空历史。
- 权限状态。
- 全局快捷键录制、持久化和恢复默认。
- 历史导入、导出、数据目录入口。
- 关于轻贴、版本号、GitHub 项目入口。

设置存储：

- 简单偏好使用 `UserDefaults`。
- 忽略 App 列表可使用 JSON 或 SQLite 表。
- 当前实现将忽略 App 列表存入 `UserDefaults`，键名为 `ignoredApps`，每项包含 `bundleID` 和 `name`。
- 设置页使用 `NSOpenPanel` 选择 `.app`，通过 `Bundle(url:)` 读取 Bundle ID 和应用名称后加入忽略列表。
- 当前实现将全局快捷键存入 `UserDefaults`，键名为 `globalShortcut.keyCode` 和 `globalShortcut.modifiers`，修改后会重新注册 Carbon HotKey。

## 5. 数据模型

### 5.1 ClipboardItem

字段：

- `id`: UUID 字符串
- `type`: text、image、link
- `contentText`: 文字内容，图片可为空
- `plainText`: 用于搜索的纯文本
- `imagePath`: 图片文件路径，非图片为空
- `createdAt`: 创建时间
- `updatedAt`: 更新时间
- `sourceAppName`: 来源 App 名称
- `sourceBundleId`: 来源 App Bundle ID
- `sourceIconPath`: 来源 App 图标缓存路径
- `sourceColorHex`: 从来源 App 图标提取的标题栏颜色
- `isPinned`: 是否置顶
- `pinnedAt`: 置顶时间
- `characterCount`: 字符数
- `imageWidth`: 图片宽度
- `imageHeight`: 图片高度
- `contentHash`: 内容哈希，用于去重

### 5.2 排序规则

查询列表时：

1. 置顶内容排最左侧。
2. 置顶内容内部按 `pinnedAt` 或 `createdAt` 倒序。
3. 普通内容按 `createdAt` 倒序。
4. 删除当前选中项后，优先选中原位置的下一张卡片；没有下一张时选中前一张。

### 5.3 去重规则

第一版采用保守去重：

- 相同 `contentHash` 且短时间内重复出现，不重复保存。
- 用户从历史记录中再次粘贴导致剪贴板变化时，不重复保存。

不做激进去重，避免误删用户确实重复复制的内容。

### 5.4 保存期限

当前保存期限使用 `UserDefaults` 保存，键名为 `history.retentionPolicy`。

支持选项：

- 1 天
- 3 天
- 5 天
- 7 天
- 30 天
- 永久保存

规则：

- 普通历史超过期限后自动清理。
- 置顶内容不自动清理。
- 图片历史被清理时，同时删除对应本地图片文件。
- 修改保存期限后立即执行一次清理并写回历史文件。

## 6. SQLite 表设计

### 6.1 clipboard_items

```sql
CREATE TABLE clipboard_items (
  id TEXT PRIMARY KEY,
  type TEXT NOT NULL,
  content_text TEXT,
  plain_text TEXT,
  image_path TEXT,
  created_at REAL NOT NULL,
  updated_at REAL NOT NULL,
  source_app_name TEXT,
  source_bundle_id TEXT,
  source_icon_path TEXT,
  source_color_hex TEXT,
  is_pinned INTEGER NOT NULL DEFAULT 0,
  pinned_at REAL,
  character_count INTEGER,
  image_width INTEGER,
  image_height INTEGER,
  content_hash TEXT NOT NULL
);
```

索引：

```sql
CREATE INDEX idx_clipboard_items_created_at ON clipboard_items(created_at);
CREATE INDEX idx_clipboard_items_is_pinned ON clipboard_items(is_pinned);
CREATE INDEX idx_clipboard_items_type ON clipboard_items(type);
CREATE INDEX idx_clipboard_items_content_hash ON clipboard_items(content_hash);
```

### 6.2 ignored_apps

```sql
CREATE TABLE ignored_apps (
  bundle_id TEXT PRIMARY KEY,
  app_name TEXT NOT NULL,
  created_at REAL NOT NULL
);
```

## 7. 文件存储

根目录：

```text
~/Library/Application Support/ClipEase/
  ClipEase.sqlite
  Images/
  AppIcons/
```

图片保存：

- 优先保存 PNG，保证再次复制质量。
- 文件名使用记录 id。
- 数据库只保存相对路径或完整路径。

App 图标缓存：

- 从来源 App 提取图标后缓存。
- 用于卡片右上角图标和颜色提取。

## 8. 剪贴板读取策略

读取顺序：

1. 检查暂停状态。
2. 检查 `changeCount` 是否变化。
3. 获取当前前台 App。
4. 检查来源 App 是否在忽略列表。
5. 优先识别图片。
6. 再识别文字。
7. 判断文字是否链接。
8. 生成哈希。
9. 保存记录。

图片类型：

- 优先读取 `NSImage`。
- 保存图片尺寸。
- 生成缩略图时不能覆盖原图。
- 原图保存到 `Images` 目录。
- 卡片专用缩略图保存到 `Thumbnails` 目录，目标尺寸不超过 `500 × 360` 像素。
- 新复制图片保存时同步生成缩略图；旧图片首次显示卡片时按需补生成缩略图。
- 再次复制或粘贴图片必须继续读取原图，不能使用缩略图。

文字类型：

- 第一版保存纯文本。
- 富文本保留放到后续版本评估。

链接类型：

- 第一版从文字中识别 URL。
- 不抓取网页内容。

## 9. 来源 App 与标题栏颜色

来源 App：

- 使用 `NSWorkspace.shared.frontmostApplication`。
- 保存 App 名称、Bundle ID、图标。

标题栏颜色：

- 从 App 图标提取主色。
- 过滤过白、过黑、透明区域。
- 提取失败时使用默认品牌蓝 `#2F8CFF`。
- 标题文字根据背景亮度自动使用白色或深色。

## 10. 权限方案

### 10.1 剪贴板

读取系统剪贴板使用 `NSPasteboard`。

### 10.2 辅助功能权限

自动粘贴需要 Accessibility 权限。

流程：

1. 用户第一次触发自动粘贴时检查权限。
2. 未授权时展示说明。
3. 引导打开系统设置。
4. 用户授权后再次尝试自动粘贴。

实现：

- 使用 `AXIsProcessTrustedWithOptions` 检查和请求辅助功能权限。
- 使用 `CGEvent` 发送 `Command + V`。

### 10.3 开机启动

使用 `SMAppService`。

设置中提供：

- 开启开机自动启动
- 关闭开机自动启动

### 10.4 iCloud

第一版不实现 iCloud 同步。设置页可显示“未来支持”，但不放不可用的复杂配置。

## 11. 全局快捷键

默认：

- `Command + Shift + V`

第一版建议使用 KeyboardShortcuts Swift Package。

原因：

- 快捷键录制和持久化成本低。
- 避免自己维护 Carbon Hot Key 边界问题。
- 便于用户修改快捷键。

如果依赖引入遇到问题，退回 Carbon Hot Key API。

## 12. 设置项存储

`UserDefaults` 保存：

- 保存期限
- 是否暂停
- 暂停到期时间
- 是否开机启动
- 快捷键配置，由快捷键库管理
- 是否启用自动粘贴

SQLite 保存：

- 忽略 App 列表
- 历史记录

## 13. 清理策略

触发时机：

- App 启动时执行一次。
- App 运行中每小时执行一次。
- 用户修改保存期限时执行一次。

规则：

- 永久保存：不自动清理。
- 置顶内容：不自动清理。
- 普通内容：超过保存期限则删除数据库记录和对应图片文件。

## 14. 窗口与交互实现

底部窗口：

- `NSPanel`
- 非全屏普通 App 窗口。
- 使用视觉效果背景。
- 固定高度。
- 当前屏幕底部对齐。

卡片列表：

- SwiftUI `ScrollView(.horizontal)`。
- 卡片尺寸固定。
- 选中项由 ViewModel 管理。
- 鼠标滚轮需要转换为横向滚动时，必要时使用 AppKit 包装。

键盘：

- 左右方向键切换卡片。
- 回车粘贴。
- 空格预览。
- `Esc` 关闭。

右键菜单：

- 第一版可用 SwiftUI `contextMenu`。
- 如需更接近 macOS 原生菜单行为，再改用 AppKit menu。

## 15. 测试与验证

每个阶段必须有手动验证记录，后续逐步补自动测试。

优先验证：

- App 是否能启动。
- 菜单栏是否出现。
- 底部窗口位置是否正确。
- 复制文字是否记录。
- 复制图片是否记录。
- 重启后数据是否存在。
- 双击和回车是否能粘贴。
- 无辅助功能权限时是否降级为复制。
- 置顶排序是否正确。
- 保存期限清理是否正确。

## 16. 第一版暂缓事项

第一版不做：

- iCloud 同步
- OCR 图片文字搜索
- 敏感内容自动识别
- 历史记录加密
- 富文本完整保留
- 多选粘贴
- 收藏贴板
- 编辑文字内容

其中“编辑文字内容”必须在第二版实现，第一版需要预留入口和数据结构空间。

## 17. 主要风险

### 17.1 自动粘贴权限

风险：

- 用户未开启 Accessibility 权限时无法自动粘贴。

处理：

- 先复制到剪贴板。
- 明确提示用户手动粘贴。
- 在设置页显示权限状态。

### 17.2 剪贴板重复记录

风险：

- App 自己写回剪贴板时被再次记录。

处理：

- PasteExecutor 写入前设置内部写入标记。
- ClipboardMonitor 在下一次变化时跳过对应内容。

### 17.3 图片占用空间

风险：

- 图片历史可能快速占用磁盘。

处理：

- 保存期限清理。
- 未来提供存储占用显示。
- 第一版保留清空全部。

### 17.4 多屏窗口位置

风险：

- 多显示器下窗口显示到错误屏幕。

处理：

- 优先使用鼠标所在屏幕。
- 找不到时使用主屏幕。
- 阶段 10 专门打磨。

## 18. 官方 API 参考

- `NSPasteboard`：https://developer.apple.com/documentation/appkit/nspasteboard
- `NSPanel`：https://developer.apple.com/documentation/appkit/nspanel
- `SMAppService`：https://developer.apple.com/documentation/servicemanagement/smappservice
- Accessibility Trust：https://developer.apple.com/documentation/applicationservices/1462083-axisprocesstrustedwithoptions
- `CGEvent`：https://developer.apple.com/documentation/coregraphics/cgevent
