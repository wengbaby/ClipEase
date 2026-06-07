# ClipEase 发布后工程质量加固计划

> **执行约束**：后续每一轮必须先读本文件，再按阶段顺序执行。每次修改后必须编译、测试、运行新版 App、递增版本号并本地提交。当前计划不包含 Apple notarization、Developer ID 或任何付费发布能力。

## 1. 当前排查结论

当前版本 `2.3.126 (260608.0030)` 已完成阶段性重构并发布。复审确认 `main` 与 `origin/main` 同步，当前 tag 为 `v2.3.126-260608.0030`，GitHub Release 和本地 DMG 产物一致，`swift build` 与 `swift test` 通过。

项目现在可以继续作为稳定版本使用。数据安全、剪贴板写入、SQLite DAO、搜索/预览/视口/分组外观协调器、设置页 ViewModel、诊断日志和发布脚本都比重构前明显更好。

但项目还没有完全达到顶级工程标准，主要短板是：

- `Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift` 仍有 8000 行以上，真实键盘、焦点、滚动、预览、AppKit bridge 仍集中在一个 View。
- `Sources/ClipEase/Core/Storage/ClipboardHistoryStore.swift` 仍有 2000 行以上，仍承担 OCR、链接元数据、保存队列、导入导出清洗、文件副作用等协调职责。
- `Sources/ClipEase/Core/Storage/SQLiteClipboardStore.swift` 虽已拆 DAO，但仍保留 schema 创建、连接包装和 repository 编排。
- `Sources/ClipEase/Features/Settings/SettingsView.swift` 虽已拆 section/view model，但仍有部分设置动作、文件面板、弹窗和状态提示耦合。
- 当前测试很多是 policy/coordinator/unit 测试，缺少完整 UI 事件链 smoke 保护，真实 SwiftUI/AppKit first responder 问题仍可能漏测。
- `scripts/release.sh` 验证强，但发布网络 fallback 仍依赖人工处理。

## 2. 总体原则

- 不改变现有 UI。
- 不改变用户现有业务流程。
- 不改变搜索、预览、滚动、分组、设置页的交互习惯。
- 每轮只解决一个清晰边界的问题。
- 先补测试保护，再迁移逻辑。
- 不为了拆文件而拆文件。
- 不做一次性大重写。
- 不提前做后续阶段内容。
- 每轮完成必须：`swift build`、`swift test`、`./scripts/build-app.sh`、结束旧 App、启动新版 App、本地提交。
- 每轮如发现高风险数据问题，先停止并报告，不直接扩大范围。

## 3. 阶段路线图

### 阶段 5-A：主窗口关键交互回归保护

目标：先把过去最容易反复出 bug 的主窗口交互链用测试保护起来，避免后续拆分时回归。

允许修改：

- `Tests/ClipEaseTests/HistoryKeyboardShortcutPolicyTests.swift`
- `Tests/ClipEaseTests/HistoryPreviewViewportCoordinatorTests.swift`
- 必要时新增 `Tests/ClipEaseTests/HistoryInteractionRegressionTests.swift`
- 必要时新增纯 policy 文件
- `docs/engineering-quality-hardening-plan.md`
- 版本号文件

禁止修改：

- 主窗口 UI 布局
- 卡片样式
- 搜索框视觉
- SQLite schema
- Store 大结构
- 设置页视觉
- 发布脚本

必须覆盖的回归点：

- 搜索框聚焦时，Backspace/Space/Command+A 等输入类操作不能落到卡片。
- 搜索框通过 Tab/方向键/Enter 交接到卡片后，Space 可以预览。
- 预览打开后，左右移动卡片时预览锚点可以跟随当前卡片。
- 分组颜色与图标弹窗首次打开必须等待 anchor 稳定。

验收：

- 新增或增强的测试先能表达风险，再通过。
- `swift build` 通过。
- `swift test` 通过。
- 新版 App 构建并启动。
- 本地提交。

### 阶段 5-B：主窗口输入与焦点路由拆分

目标：把 `HistoryWindowView.swift` 中键盘输入、搜索框焦点、卡片焦点、文本输入保护相关逻辑进一步收口到独立协调器。

建议新增：

- `Sources/ClipEase/Features/HistoryWindow/HistoryInputFocusCoordinator.swift`
- `Sources/ClipEase/Features/HistoryWindow/HistoryKeyboardActionRouter.swift`
- `Tests/ClipEaseTests/HistoryInputFocusCoordinatorTests.swift`

要求：

- 只迁移决策逻辑，不改 UI。
- 不改变快捷键行为。
- 不改变搜索框交接规则。
- 不改变预览触发规则。

### 阶段 5-C：ClipboardHistoryStore 保存与异步副作用拆分

目标：继续降低 `ClipboardHistoryStore.swift` 的职责密度。

建议拆分：

- `ClipboardHistorySaveWriter.swift`
- `HistoryOCRCoordinator.swift`
- `HistoryLinkMetadataCoordinator.swift`

要求：

- Store 保留协调入口。
- 先抽测试覆盖明确的纯逻辑和 actor/task 生命周期边界。
- 不改变剪贴板入库、去重、OCR、链接标题更新行为。

### 阶段 5-D：SQLite schema/connection 收口

目标：在已有 DAO 基础上继续拆 SQLite 的 schema 和连接包装。

建议拆分：

- `SQLiteSchemaManager.swift`
- `SQLiteConnection.swift`

要求：

- 先补旧库 fixture。
- 不改变 schema。
- 不改变 migration 行为。
- 不改变搜索排序和分页。

### 阶段 5-E：设置页动作协调器拆分

目标：继续降低 `SettingsView.swift` 的动作和 AppKit 面板耦合。

建议新增：

- `SettingsHistoryDataActionCoordinator.swift`
- `SettingsImportExportCoordinator.swift`

要求：

- 不改设置页视觉结构。
- 不改按钮文案。
- 不改导入、导出、恢复、清理流程。

### 阶段 5-F：免费发布流程 fallback

目标：增强当前免费 GitHub Release 流程的可恢复性。

允许改：

- `scripts/release.sh`
- `Tests/ClipEaseTests/ReleaseScriptPolicyTests.swift`
- `docs/releases/release-checklist.md`

要求：

- 不引入 Apple notarization。
- 不引入 Developer ID。
- 不引入任何付费发布能力。
- 只考虑 GitHub CLI、GitHub API、SSH 443 fallback、hash 校验和失败恢复说明。

## 4. 执行顺序

1. 阶段 5-A：补主窗口关键交互回归测试。
2. 阶段 5-B：拆输入与焦点路由。
3. 阶段 5-C：拆 Store 保存与异步副作用。
4. 阶段 5-D：拆 SQLite schema/connection。
5. 阶段 5-E：拆设置页动作协调器。
6. 阶段 5-F：增强免费发布流程 fallback。

每个阶段完成后必须更新本文件的进度记录。

## 5. 禁止事项

- 禁止一次性重写 `HistoryWindowView.swift`。
- 禁止一次性重写 `ClipboardHistoryStore.swift`。
- 禁止修改 UI 来掩盖状态问题。
- 禁止跳过测试直接改业务逻辑。
- 禁止改 SQLite schema 后不补 migration fixture。
- 禁止把发布脚本改成依赖付费 Apple 能力。
- 禁止只更新文档不验证真实代码。

## 6. 进度记录

### 阶段 5-A：主窗口关键交互回归保护

- 状态：已完成
- 计划开始：2026-06-08
- 入口条件：当前 release 已发布，工作区干净，`swift build` 和 `swift test` 已通过。
- 本阶段不改 UI，不改 Store，不改 SQLite，不改 release 脚本。
- 完成记录：
  - 2026-06-08：新增 `Tests/ClipEaseTests/HistoryInteractionRegressionTests.swift`，覆盖搜索框编辑键隔离、搜索到卡片的焦点交接、交接后空格预览、回到搜索框后的 Backspace/Space 保护、预览 fallback anchor 跟随和分组外观弹窗首开延迟策略。
  - 2026-06-08：本轮未修改生产业务代码、主窗口 UI、Store、SQLite、设置页或发布脚本。
  - 2026-06-08：定向验证 `swift test --filter HistoryInteractionRegression` 通过，5 个测试全部通过。
  - 2026-06-08：验证 `swift build` 通过；验证 `swift test` 通过，172 个测试全部通过。
  - 2026-06-08：执行 `./scripts/build-app.sh`，版本从 `2.3.126 (260608.0030)` 递增到 `2.3.127 (260608.0126)`。
  - 2026-06-08：已结束旧进程并启动新版 `.build/ClipEase.app`，进程路径为 `/Users/wpc/code/codex/ClipboardHistory/.build/ClipEase.app/Contents/MacOS/ClipEase`。
  - 阶段 5-B 入口条件：阶段 5-A 本地提交完成，并由用户确认继续后，按顺序只允许进入主窗口输入与焦点路由拆分。

### 阶段 5-B：主窗口输入与焦点路由拆分

- 状态：已完成
- 计划开始：2026-06-08
- 本阶段不改 UI，不改 Store，不改 SQLite，不改设置页，不改发布脚本。
- 完成记录：
  - 2026-06-08：新增 `Sources/ClipEase/Features/HistoryWindow/HistoryInputFocusCoordinator.swift`，收口搜索框聚焦、搜索到卡片交接、搜索关闭和搜索文本框是否恢复焦点的决策入口。
  - 2026-06-08：新增 `Sources/ClipEase/Features/HistoryWindow/HistoryKeyboardActionRouter.swift`，收口文本输入键盘路由、历史快捷键允许策略和主窗口 Space 预览判断入口。
  - 2026-06-08：新增 `Tests/ClipEaseTests/HistoryInputFocusCoordinatorTests.swift`，覆盖搜索交接、无结果保持搜索聚焦、编辑快捷键留在输入框、交接后 Space 可预览。
  - 2026-06-08：`HistoryWindowView.swift` 只做最小接入，搜索焦点 transition 改由 `HistoryInputFocusCoordinator` 生成；搜索文本框 AppKit bridge 改由协调器判断是否恢复焦点。
  - 2026-06-08：`HistoryKeyboardEventTap.swift` 和 `HistoryWindowController.swift` 改由 `HistoryKeyboardActionRouter` 统一做键盘路由判断；未改变任何快捷键规则。
  - 2026-06-08：定向验证 `swift test --filter HistoryInputFocusCoordinator` 通过，4 个测试全部通过；`swift test --filter HistoryInteractionRegression` 通过，5 个测试全部通过。
  - 2026-06-08：验证 `swift build` 通过；验证 `swift test` 通过，176 个测试全部通过。
  - 2026-06-08：执行 `./scripts/build-app.sh`，版本从 `2.3.127 (260608.0126)` 递增到 `2.3.128 (260608.0147)`。
  - 2026-06-08：已结束旧进程并启动新版 `.build/ClipEase.app`，进程路径为 `/Users/wpc/code/codex/ClipboardHistory/.build/ClipEase.app/Contents/MacOS/ClipEase`。
  - 阶段 5-C 入口条件：阶段 5-B 本地提交完成，并由用户确认继续后，按顺序只允许进入 `ClipboardHistoryStore` 保存与异步副作用拆分。

### 阶段 5-C：ClipboardHistoryStore 保存与异步副作用拆分

- 状态：阶段 5-C-3 已完成，保存队列、链接元数据协调器和 OCR 协调器已拆出
- 计划开始：2026-06-08
- 本阶段当前小步不改 UI，不改 SQLite schema，不改剪贴板入库、去重、OCR 或链接标题更新行为。
- 完成记录：
  - 2026-06-08：新增 `Sources/ClipEase/Core/Storage/ClipboardHistorySaveWriter.swift`。
  - 2026-06-08：将 `ClipboardHistorySaveWriter` 从 `ClipboardHistoryStore.swift` 移到独立文件，保持 `saveAsync`、`upsertAsync`、`insertItemsAsync`、`deleteAsync`、`deleteAllAsync`、`saveSync`、压缩调度和诊断记录逻辑不变。
  - 2026-06-08：`ClipboardHistoryStore.swift` 继续保留 Store 协调入口、OCR task、link metadata task、导入清洗和文件副作用，避免一次性扩大拆分范围。
  - 2026-06-08：验证 `swift build` 通过；验证 `swift test` 通过，176 个测试全部通过。
  - 2026-06-08：执行 `./scripts/build-app.sh`，版本从 `2.3.128 (260608.0147)` 递增到 `2.3.129 (260608.0205)`。
  - 2026-06-08：已结束旧进程并启动新版 `.build/ClipEase.app`，进程路径为 `/Users/wpc/code/codex/ClipboardHistory/.build/ClipEase.app/Contents/MacOS/ClipEase`。
  - 2026-06-08：新增 `Sources/ClipEase/Core/History/HistoryLinkMetadataCoordinator.swift`，收口链接元数据 Task 字典、generation、取消任务、清空任务和并发 limiter。
  - 2026-06-08：新增 `Tests/ClipEaseTests/HistoryLinkMetadataCoordinatorTests.swift`，覆盖按条目取消和全部取消时 in-flight 状态会正确清理。
  - 2026-06-08：`ClipboardHistoryStore.swift` 不再直接持有 `linkMetadataTaskByItemID`、`LinkMetadataService` 和 `LinkMetadataFetchLimiter`；Store 继续保留真实元数据应用、旧图片删除和持久化 upsert 入口。
  - 2026-06-08：本轮未改变链接标题/预览图抓取顺序、并发限制、图片保存、元数据应用条件或持久化行为。
  - 2026-06-08：定向验证 `swift test --filter HistoryLinkMetadataCoordinator` 通过，1 个测试通过；`swift test --filter LinkMetadataService` 通过，4 个测试通过。
  - 2026-06-08：验证 `swift build` 通过；验证 `swift test` 通过，177 个测试全部通过。
  - 2026-06-08：执行 `./scripts/build-app.sh`，版本从 `2.3.129 (260608.0205)` 递增到 `2.3.130 (260608.0218)`。
  - 2026-06-08：已结束旧进程并启动新版 `.build/ClipEase.app`，进程路径为 `/Users/wpc/code/codex/ClipboardHistory/.build/ClipEase.app/Contents/MacOS/ClipEase`。
  - 2026-06-08：新增 `Sources/ClipEase/Core/History/HistoryOCRCoordinator.swift`，收口 OCR Task 字典、取消任务、交互节流、并发 limiter 和识别调度生命周期。
  - 2026-06-08：新增 `Tests/ClipEaseTests/HistoryOCRCoordinatorTests.swift`，覆盖 OCR 任务按条目/全部取消、缺失源文件时失败结果回写和 in-flight 状态清理。
  - 2026-06-08：`ClipboardHistoryStore.swift` 不再直接持有 OCR task 字典和 `ClipboardOCRConcurrencyLimiter`；Store 继续保留 OCR 源文件路径解析、状态应用、OCR 结果写回和持久化 upsert 入口。
  - 2026-06-08：本轮未改变 OCR 识别逻辑、OCR 状态语义、源文件查找顺序、持久化行为、UI、SQLite schema 或发布脚本。
  - 2026-06-08：定向验证 `swift test --filter HistoryOCRCoordinator` 通过，2 个测试全部通过。
  - 2026-06-08：验证 `swift build` 通过；验证 `swift test` 通过，179 个测试全部通过。
  - 2026-06-08：执行 `./scripts/build-app.sh`，版本从 `2.3.130 (260608.0218)` 递增到 `2.3.131 (260608.0239)`。
  - 2026-06-08：已结束旧进程并启动新版 `.build/ClipEase.app`，进程路径为 `/Users/wpc/code/codex/ClipboardHistory/.build/ClipEase.app/Contents/MacOS/ClipEase`。
  - 2026-06-08：完成阶段 5-C 收尾复核。`ClipboardHistoryStore.swift` 当前约 1660 行，原计划内的保存队列、链接元数据 task 生命周期和 OCR task 生命周期均已拆出。
  - 2026-06-08：复核确认 Store 仍保留剪贴板入库编排、导入/备份清洗、文件引用构造、外部资源删除、分页加载和状态协调职责；这些职责不属于本阶段已承诺的三个拆分目标，继续硬拆会扩大风险。
  - 2026-06-08：阶段 5-C 到此关闭。剩余 Store 职责作为后续可选优化记录，不在本轮继续拆分。
  - 阶段 5-D 入口条件：阶段 5-C 收尾提交完成，并由用户确认继续后，只允许进入 SQLite schema/connection 收口。
