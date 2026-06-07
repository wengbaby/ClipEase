# 轻贴工程重构规划文档

> 本文档是后续所有工程重构、稳定性修复、性能优化和发布流程优化的唯一执行依据。后续任何代码修改都必须先读取本文档，判断当前阶段，只执行当前阶段允许的任务，不允许跳阶段、扩大范围或做临时补丁式修复。

## 当前文档状态

- 创建日期：2026-06-07
- 当前执行阶段：阶段 2-A，DuplicateResolver 纯逻辑拆分已完成，用户手工验证通过，等待本地提交
- 当前禁止事项：禁止直接进入主窗口大拆分，禁止直接重写 Store，禁止直接修改 SQLite 结构而不做备份和迁移测试
- 当前优先目标：提交阶段 2-A；提交后等待用户确认是否继续阶段 2-B
- 版本要求：每次后续代码修改完成后，必须编译、运行验证，并按项目版本规则递增版本号

---

## 1. 项目当前工程质量总结

### 1.1 当前真实状态

项目当前可以正常使用，近期针对主窗口卡顿、搜索卡顿、渲染窗口、预览、搜索焦点、性能日志分库、数据库压缩和发布流程做过多轮修复，整体可用性比之前明显提升。

但项目现在已经进入高风险维护阶段。主要问题不是单个 bug，而是核心模块边界不清、状态过度集中、业务逻辑与 UI 拼装混在一起，导致每次小修都容易影响相邻状态。

### 1.2 当前最主要的技术债

1. `Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift`
   - 文件约 8551 行。
   - 同时负责主窗口 UI、搜索、卡片渲染窗口、滚动定位、预览弹窗、分组外观弹窗、键盘焦点、搜索框状态、预热任务、缓存、AppKit bridge。
   - 之前反复出现“卡片不显示”“滚动后才显示”“搜索后空白”“预览不在卡片上方”“搜索框聚焦但按键作用到卡片”等问题，本质上都和这个文件里的状态边界混乱有关。

2. `Sources/ClipEase/Core/Storage/ClipboardHistoryStore.swift`
   - 文件约 2267 行。
   - 同时负责历史数据、分组、去重、跳过自身复制、OCR、链接元数据、分页、搜索入口、保存调度、导入数据合并。
   - 这是核心业务入口，但承担了太多具体业务能力，后续新增功能会继续堆叠。

3. `Sources/ClipEase/Core/Storage/SQLiteClipboardStore.swift`
   - 文件约 1755 行。
   - 同时负责 schema、迁移判断、DAO、FTS 搜索、row mapping、批量写入、压缩策略。
   - 当前 `user_version < currentSchemaVersion` 时存在直接删除旧数据库文件的路径，这是数据安全最高风险。

4. `Sources/ClipEase/Features/Settings/SettingsView.swift`
   - 文件约 2249 行。
   - 设置页 UI、历史数据统计、清理、压缩、导入导出、备份恢复、日志配置、目录打开等逻辑混在 View 中。
   - 这会导致设置页面视觉调整和真实 IO 操作互相影响。

5. `scripts/release.sh`
   - 发布流程已有版本一致性、DMG、GitHub release 相关逻辑，但还没有形成完整 CI gate、notarization、dry-run、asset hash 二次校验的自动化闭环。

### 1.3 为什么不能继续只做小修小补

继续小修小补会造成三个后果：

1. 根因没有消失，只是在现有状态机上继续叠加条件判断。
2. 每次修复都会增加 `HistoryWindowView.swift`、`ClipboardHistoryStore.swift` 里的隐式状态组合。
3. 后续 bug 会更难复现，因为状态分散在 `@State`、`@AppStorage`、单例、Task、AppKit responder、UserDefaults 中。

例如主窗口渲染问题不是单一布局问题，而是搜索结果、渲染窗口、滚动偏移、焦点恢复、预览跟随之间互相影响。继续加临时 `if/else` 只会扩大状态机复杂度。

### 1.4 为什么不能一次性大重构

不能一次性大重构，原因如下：

1. 主窗口交互细节非常多，包含键盘、鼠标、搜索、预览、分组、滚动、粘贴等多条路径。
2. 当前项目没有足够完整的 UI 自动化测试覆盖，无法支撑一次性重写核心窗口。
3. 历史数据和 SQLite 存储涉及用户真实数据，任何大范围存储层改动都必须先有备份和迁移验证。
4. 用户明确要求不改变 UI、不改变交互、不改变功能，因此只能按边界逐步迁移。

### 1.5 最容易引发连锁 bug 的核心模块

1. 主窗口状态链路
   - 文件：`HistoryWindowView.swift`
   - 风险：搜索、卡片显示、滚动、焦点、预览、分组弹窗互相影响。

2. 历史 Store 业务链路
   - 文件：`ClipboardHistoryStore.swift`
   - 风险：新增、删除、去重、分页、保存、跳过自身复制、链接元数据互相影响。

3. SQLite 存储链路
   - 文件：`SQLiteClipboardStore.swift`
   - 风险：schema、迁移、FTS、DAO、压缩、备份恢复互相影响。

4. 设置页 IO 链路
   - 文件：`SettingsView.swift`
   - 风险：UI 布局调整可能影响历史数据统计、压缩、清理、导入导出任务。

5. 发布链路
   - 文件：`scripts/build-app.sh`、`scripts/release.sh`、`docs/releases/release-checklist.md`
   - 风险：版本号、DMG、tag、release notes、远端 asset 不一致。

### 1.6 问题之间的因果关系

主窗口承担过多状态，导致搜索和渲染窗口问题频发；Store 承担过多业务，导致 UI 修复常常需要理解保存、分页、去重和自身复制；SQLite 层没有清晰迁移边界，导致任何存储优化都可能触碰数据安全；设置页把 IO 放在 View 中，导致页面调整容易影响真实数据操作；发布脚本没有完全自动化 gate，导致版本、DMG、release 内容需要反复人工确认。

因此后续顺序必须是：先守住数据安全和稳定性，再拆状态边界，再拆业务服务，再工程化 SQLite，最后优化设置页和发布流程。

---

## 2. 总体重构原则

后续所有修改必须遵守以下原则：

1. 不改变现有 UI。
2. 不改变用户现有业务流程。
3. 不破坏已有功能。
4. 每次只解决一个清晰边界的问题。
5. 每个阶段都必须可编译、可运行、可回滚。
6. 优先修复数据安全和稳定性问题。
7. 再拆分状态和业务边界。
8. 最后再做架构级优化。
9. 禁止为了重构而重构。
10. 禁止无依据的大范围改动。
11. 禁止只改表面、不解决根因。
12. 禁止在没有测试或验证脚本的情况下修改存储迁移逻辑。
13. 禁止用新的全局单例替代旧的全局状态污染。
14. 后续每次代码修改后必须编译、运行验证，并记录结果。
15. 后续每次发布前必须确认版本号、DMG 文件、tag、release notes 一致。

---

## 3. 风险分级与优先级

### P0：旧 schema 升级可能清库

- 风险等级：P0
- 涉及文件：`Sources/ClipEase/Core/Storage/SQLiteClipboardStore.swift`
- 当前表现：`resetLegacyDatabaseIfNeeded()` 在 `user_version < currentSchemaVersion` 时调用 `removeExistingDatabaseFiles()`。
- 根本原因：没有真正的逐版本 migration，旧库被当作 legacy 数据直接删除。
- 可能造成的后果：用户升级后历史记录、分组、搜索索引、附件引用丢失。
- 推荐解决方案：新增 `SQLiteSchemaMigrator` 和 `SQLiteBackupManager`；升级前自动备份；migration 失败保留原库；禁止直接删除旧库。
- 是否允许立即修改：允许。
- 是否需要用户确认后再修改：需要。因为涉及真实用户数据迁移策略。

### P1：HistoryWindowView 过大导致状态边界混乱

- 风险等级：P1
- 涉及文件：`Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift`
- 当前表现：同一文件内管理搜索、渲染窗口、焦点、预览、滚动、分组弹窗和 AppKit bridge。
- 根本原因：View 同时承担 UI、状态机和业务协调。
- 可能造成的后果：修复搜索可能影响卡片显示，修复预览可能影响滚动定位，修复焦点可能影响粘贴快捷键。
- 推荐解决方案：按状态域拆出 `HistoryWindowViewModel`、`HistorySearchCoordinator`、`HistoryViewportStore`、`HistoryPreviewCoordinator`、`GroupAppearanceCoordinator`。
- 是否允许立即修改：不允许在阶段 0 修改；阶段 1 才允许。
- 是否需要用户确认后再修改：需要。

### P1：ClipboardHistoryStore 职责过载

- 风险等级：P1
- 涉及文件：`Sources/ClipEase/Core/Storage/ClipboardHistoryStore.swift`
- 当前表现：Store 同时负责历史记录、分组、去重、分页、OCR、链接元数据、保存、自身复制忽略。
- 根本原因：业务服务没有拆分，Store 变成所有历史业务的聚合大文件。
- 可能造成的后果：新增功能会牵动保存、搜索、分页、去重等链路，回归风险高。
- 推荐解决方案：阶段 2 拆出 `DuplicateResolver`、`GroupService`、`ClipboardSelfWriteGuard`、`HistoryPagingService`、`HistoryRetentionService`、`LinkMetadataService`。
- 是否允许立即修改：阶段 0 只允许修改自身复制和持久化错误相关最小范围；完整拆分必须等阶段 2。
- 是否需要用户确认后再修改：需要。

### P1：SQLiteClipboardStore 同时承担 schema、DAO、FTS、迁移

- 风险等级：P1
- 涉及文件：`Sources/ClipEase/Core/Storage/SQLiteClipboardStore.swift`
- 当前表现：schema 创建、版本记录、数据读写、FTS 索引、row mapping、压缩调度混在一个文件。
- 根本原因：SQLite 访问层没有分层。
- 可能造成的后果：搜索、迁移、压缩、导入导出互相影响，任何存储改动都难以验证。
- 推荐解决方案：阶段 3 拆成 `SQLiteSchemaMigrator`、`SQLiteItemDAO`、`SQLiteGroupDAO`、`SQLiteSearchIndexDAO`、`SQLiteDatabaseCompactor`、`SQLiteRowMapper`、`SQLiteBackupManager`。
- 是否允许立即修改：阶段 0 只允许先做迁移保护和备份；完整 DAO 拆分必须等阶段 3。
- 是否需要用户确认后再修改：需要。

### P1：图片复制绕过统一写入入口

- 风险等级：P1
- 涉及文件：`Sources/ClipEase/Features/PasteExecutor/PasteExecutor.swift`、`Sources/ClipEase/Core/Services/ClipboardWriteCoordinator.swift`
- 当前表现：`copyImageToPasteboard(_ image:skipText:)` 直接写 `NSPasteboard`，没有完整走统一写入协调。
- 根本原因：不同复制路径历史上逐步增加，未完全收口。
- 可能造成的后果：自身复制忽略不完整，图片复制或预览复制可能被重新采集。
- 推荐解决方案：所有文本、富文本、图片、文件写入都经 `ClipboardWriteCoordinator`；新增或抽出 `ClipboardSelfWriteGuard` 统一跳过逻辑。
- 是否允许立即修改：允许，属于阶段 0。
- 是否需要用户确认后再修改：需要。

### P1：持久化失败只 NSLog，用户不可见

- 风险等级：P1
- 涉及文件：`Sources/ClipEase/Core/Storage/ClipboardHistoryStore.swift`、`Sources/ClipEase/Core/Utilities/PerformanceDiagnosticsService.swift`
- 当前表现：保存、upsert、delete 失败只写 `NSLog`。
- 根本原因：缺少统一错误事件和诊断入口。
- 可能造成的后果：用户以为保存成功，实际数据库写入失败；后续排查缺少证据。
- 推荐解决方案：新增持久化错误事件，写入诊断数据库或诊断面板可见区域；保留 `NSLog` 作为补充。
- 是否允许立即修改：允许，属于阶段 0。
- 是否需要用户确认后再修改：需要。

### P1：搜索链路仍在 View 内拼装

- 风险等级：P1
- 涉及文件：`Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift`、`Sources/ClipEase/Features/HistoryWindow/HistorySearchController.swift`
- 当前表现：View 内拼装 repository 搜索、内存过滤、分页、结果选择、焦点交接。
- 根本原因：搜索控制器只承担部分纯逻辑，搜索状态机仍在 View。
- 可能造成的后果：搜索输入、筛选、Tab、方向键、空格预览容易互相影响。
- 推荐解决方案：阶段 1 新建 `HistorySearchCoordinator`，统一管理搜索请求、分页、结果状态、搜索焦点交接。
- 是否允许立即修改：阶段 0 不允许；阶段 1 允许。
- 是否需要用户确认后再修改：需要。

### P2：SettingsView 设置页过大

- 风险等级：P2
- 涉及文件：`Sources/ClipEase/Features/Settings/SettingsView.swift`
- 当前表现：设置 UI、历史数据统计、清理、压缩、导入导出、日志配置混在一个 View。
- 根本原因：缺少 Settings ViewModel 和 Section 拆分。
- 可能造成的后果：布局修复可能误伤 IO 逻辑，设置页继续膨胀。
- 推荐解决方案：阶段 4 拆成多个 Section，并把 IO 任务移入 ViewModel。
- 是否允许立即修改：当前不允许，阶段 4 再做。
- 是否需要用户确认后再修改：需要。

### P2：自动访问剪贴板 URL 的隐私说明不足

- 风险等级：P2
- 涉及文件：`Sources/ClipEase/Core/Utilities/LinkTitleFetcher.swift`
- 当前表现：链接类型会请求 URL 页面标题和预览图。
- 根本原因：功能默认启用，但没有单独隐私说明或可关闭入口。
- 可能造成的后果：用户复制私密链接时，应用可能主动访问该 URL。
- 推荐解决方案：阶段 4 增加设置项和说明；默认策略需用户确认，不在重构中擅自改变。
- 是否允许立即修改：当前不允许，阶段 4 再做。
- 是否需要用户确认后再修改：需要，因为可能影响用户体验和默认行为。

### P2：发布流程缺少完整 CI / notarization / 校验闭环

- 风险等级：P2
- 涉及文件：`scripts/build-app.sh`、`scripts/release.sh`、`docs/releases/release-checklist.md`
- 当前表现：本地脚本已覆盖较多 release 操作，但缺少完整 CI、notarization、dry-run、asset hash 二次校验闭环。
- 根本原因：发布自动化仍依赖本地环境和人工确认。
- 可能造成的后果：版本号、DMG、tag、release notes 或远端 asset 不一致。
- 推荐解决方案：阶段 4 增加 dry-run、测试 gate、DMG verify、版本一致性校验、GitHub asset hash 校验和 Apple notarization 预留。
- 是否允许立即修改：当前不允许，阶段 4 再做。
- 是否需要用户确认后再修改：需要。

### P3：AppDelegate 初始化顺序存在隐式依赖

- 风险等级：P3
- 涉及文件：`Sources/ClipEase/App/AppDelegate.swift`
- 当前表现：`requireHistoryStore()` 在初始化顺序错误时会 `fatalError`。
- 根本原因：服务创建依赖手动顺序，没有统一依赖容器。
- 可能造成的后果：后续重构时若调整初始化顺序，可能启动崩溃。
- 推荐解决方案：阶段 4 或后续新增轻量 `AppContainer`，显式构造核心服务。
- 是否允许立即修改：当前不允许。
- 是否需要用户确认后再修改：需要。

---

## 4. 分阶段重构路线图

### 阶段 0：数据安全与稳定性底线修复

目标：先解决可能造成用户数据丢失、复制状态污染、错误不可见的问题。

范围：

1. SQLite 迁移保护。
2. 升级前自动备份。
3. 禁止 `user_version < currentSchemaVersion` 时直接清库。
4. 图片、文本、文件复制统一走 `ClipboardWriteCoordinator`。
5. 新建或抽出 `ClipboardSelfWriteGuard`，统一自身复制忽略逻辑。
6. 持久化失败进入统一错误日志和诊断面板。

要求：

1. 不改 UI。
2. 不改业务流程。
3. 不做大规模架构拆分。
4. 只修数据安全和稳定性问题。
5. 必须补充必要测试或验证脚本。
6. 必须保证 migration 失败时原库仍可保留。

### 阶段 1：主窗口状态边界拆分

目标：降低 `HistoryWindowView.swift` 的复杂度，但不改变 UI。

范围：

1. 新建 `HistoryWindowViewModel`。
2. 新建 `HistorySearchCoordinator`。
3. 新建 `HistoryViewportStore`。
4. 新建 `HistoryPreviewCoordinator`。
5. 新建 `GroupAppearanceCoordinator`。
6. View 只负责渲染，不再拼装复杂业务逻辑。
7. 搜索、滚动、预览、分组外观等状态逐步迁出 View。

要求：

1. 每次只迁移一个独立状态域。
2. 每迁移一个模块都必须编译运行。
3. 不允许一次性把 8551 行全部重写。
4. 不允许改变 UI 视觉和交互习惯。

### 阶段 2：ClipboardHistoryStore 职责拆分

目标：把 Store 中的业务能力拆成独立服务。

范围：

1. `ClipboardHistoryDomainStore`
2. `DuplicateResolver`
3. `GroupService`
4. `ClipboardSelfWriteGuard`
5. `HistoryPagingService`
6. `HistoryRetentionService`
7. `LinkMetadataService`

要求：

1. Store 保留协调入口。
2. 具体业务逻辑下沉到独立服务。
3. 先抽纯逻辑，再替换调用。
4. 避免影响现有数据结构和 UI。

### 阶段 3：SQLite 存储层工程化拆分

目标：让 SQLite 层从“大文件”变成清晰的数据访问层。

范围：

1. `SQLiteSchemaMigrator`
2. `SQLiteItemDAO`
3. `SQLiteGroupDAO`
4. `SQLiteSearchIndexDAO`
5. `SQLiteDatabaseCompactor`
6. `SQLiteRowMapper`
7. `SQLiteBackupManager`

要求：

1. 先补旧库 fixture。
2. 再做逐版本 migration。
3. 再拆 DAO。
4. 最后拆压缩和 FTS。
5. 禁止没有测试的迁移改动。

### 阶段 4：设置页、诊断页、发布流程优化

目标：提升长期维护、诊断和发布质量。

范围：

1. `SettingsView` 拆分成多个 Section。
2. 设置页 IO 逻辑进入 ViewModel。
3. 诊断日志可观测性增强。
4. `release.sh` 增加 dry-run。
5. 发布前测试 gate。
6. DMG 校验。
7. 版本一致性校验。
8. GitHub release asset hash 校验。
9. Apple notarization 预留选项。

---

## 5. 每个阶段的验收标准

### 阶段 0 验收标准

修改目标：

- 旧 schema 升级不会删除用户数据库。
- 升级前会生成备份。
- migration 失败会保留原库。
- 图片复制、文本复制、文件复制都走统一写入入口。
- 自身复制不会被重新采集。
- 持久化失败可以在日志或诊断入口看到。

允许修改的文件范围：

- `Sources/ClipEase/Core/Storage/SQLiteClipboardStore.swift`
- `Sources/ClipEase/Core/Storage/ClipboardHistoryStore.swift`
- `Sources/ClipEase/Core/Storage/ClipboardHistoryPersistence.swift`
- `Sources/ClipEase/Core/Services/ClipboardWriteCoordinator.swift`
- `Sources/ClipEase/Features/PasteExecutor/PasteExecutor.swift`
- `Sources/ClipEase/Core/Utilities/PerformanceDiagnosticsService.swift`
- `Tests/ClipEaseTests/*`

不允许修改的内容：

- 主窗口 UI 布局。
- 卡片样式。
- 搜索交互。
- 设置页视觉结构。
- 现有快捷键行为。

编译要求：

- 必须执行 `swift build`。
- 必须执行 `swift test`。

运行验证步骤：

1. 启动应用。
2. 复制文本，确认记录正常出现。
3. 双击粘贴、回车粘贴、纯文本粘贴，确认自身复制不被重新采集。
4. 复制图片，确认图片复制不会被重新采集。
5. 使用旧 schema fixture 启动迁移，确认原库不被删除。
6. 人为制造持久化失败验证诊断事件可见。

回归测试点：

- 文本、链接、图片、文件记录。
- 搜索。
- 分组。
- 粘贴。
- 数据库压缩。
- 备份导入导出。

失败回滚方案：

- 保留升级前备份。
- 如果 migration 失败，继续使用原数据库。
- 如果统一写入入口导致复制异常，回滚该次提交，不允许在主窗口中加临时绕过。

完成后如何更新文档状态：

- 将“当前执行阶段”更新为“阶段 1，未开始”。
- 在阶段 0 下新增完成记录：提交号、版本号、验证命令、验证结果。

### 阶段 1 验收标准

修改目标：

- 主窗口 View 逐步瘦身。
- 搜索、滚动、预览、分组外观状态开始有明确边界。

允许修改的文件范围：

- `Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift`
- `Sources/ClipEase/Features/HistoryWindow/HistorySearchController.swift`
- `Sources/ClipEase/Features/HistoryWindow/HistoryWindowInputState.swift`
- 新增 `Sources/ClipEase/Features/HistoryWindow/ViewModels/*`
- 新增 `Sources/ClipEase/Features/HistoryWindow/Search/*`
- 新增 `Sources/ClipEase/Features/HistoryWindow/Viewport/*`
- 新增 `Sources/ClipEase/Features/HistoryWindow/Preview/*`
- 新增 `Sources/ClipEase/Features/HistoryWindow/Groups/*`
- `Tests/ClipEaseTests/*`

不允许修改的内容：

- UI 视觉。
- 卡片大小。
- 搜索框视觉。
- 分组外观。
- 快捷键语义。

编译要求：

- 每迁移一个状态域，执行 `swift build`。
- 阶段完成时执行 `swift test`。

运行验证步骤：

1. 打开主窗口，卡片首屏必须立即显示。
2. 搜索输入、删除、筛选、Esc、Tab、方向键行为保持一致。
3. 空格预览、左右移动预览位置保持正确。
4. 分组右键颜色与图标弹窗位置保持正确。
5. 1000 条数据下主窗口打开和搜索保持流畅。

失败回滚方案：

- 每次只迁移一个状态域。
- 单个状态域失败时回滚该状态域提交，不影响已完成阶段 0。

完成后如何更新文档状态：

- 将“当前执行阶段”更新为“阶段 2，未开始”。
- 写入已迁移状态域、测试结果和残留风险。

### 阶段 2 验收标准

修改目标：

- `ClipboardHistoryStore` 从业务大文件变成协调入口。
- 去重、分组、分页、保留策略、链接元数据、自身复制忽略有独立服务。

允许修改的文件范围：

- `Sources/ClipEase/Core/Storage/ClipboardHistoryStore.swift`
- 新增 `Sources/ClipEase/Core/History/*`
- 新增 `Sources/ClipEase/Core/Clipboard/*`
- `Tests/ClipEaseTests/*`

不允许修改的内容：

- 数据模型字段。
- SQLite schema。
- UI。
- 用户业务流程。

编译要求：

- 每抽一个服务执行 `swift build`。
- 阶段完成时执行 `swift test`。

运行验证步骤：

- 新增、删除、置顶、分组、搜索、分页加载、链接标题获取、OCR、复制粘贴均保持现有行为。

失败回滚方案：

- 先抽纯逻辑，不改调用。
- 再逐个替换调用。
- 任一替换失败只回滚该服务接入。

完成后如何更新文档状态：

- 将“当前执行阶段”更新为“阶段 3，未开始”。
- 写入 Store 缩减行数、抽出的服务、测试结果。

### 阶段 3 验收标准

修改目标：

- SQLite 层拆成清晰数据访问层。
- 迁移、DAO、FTS、压缩、备份恢复职责分离。

允许修改的文件范围：

- `Sources/ClipEase/Core/Storage/SQLiteClipboardStore.swift`
- 新增 `Sources/ClipEase/Core/Storage/SQLite/*`
- `Sources/ClipEase/Core/Utilities/HistoryExportService.swift`
- `Tests/ClipEaseTests/*`

不允许修改的内容：

- 未经 migration 测试的 schema 修改。
- 未备份数据库的升级逻辑。
- UI 和用户流程。

编译要求：

- 每拆一个 DAO 执行 `swift build`。
- 阶段完成时执行 `swift test`。

运行验证步骤：

- 旧库迁移。
- FTS 搜索。
- 分组加载。
- 图片、富文本、文件附件引用。
- 数据库压缩。
- 备份导入导出。

失败回滚方案：

- 保留旧库 fixture。
- 每个 DAO 独立提交。
- 任何 migration 失败必须保留原库并停止升级。

完成后如何更新文档状态：

- 将“当前执行阶段”更新为“阶段 4，未开始”。
- 写入拆分后的 SQLite 文件清单和 migration 覆盖范围。

### 阶段 4 验收标准

修改目标：

- 设置页、诊断页、发布流程更易维护。

允许修改的文件范围：

- `Sources/ClipEase/Features/Settings/SettingsView.swift`
- 新增 `Sources/ClipEase/Features/Settings/Sections/*`
- 新增 `Sources/ClipEase/Features/Settings/ViewModels/*`
- `Sources/ClipEase/Core/Utilities/PerformanceDiagnosticsService.swift`
- `scripts/build-app.sh`
- `scripts/release.sh`
- `docs/releases/*`
- `Tests/ClipEaseTests/*`

不允许修改的内容：

- 设置页视觉大改。
- 默认隐私行为变更，除非用户确认。
- 发布格式随意变更。

编译要求：

- 设置页拆分后执行 `swift build`。
- 发布脚本改动后执行 dry-run。
- 阶段完成时执行 `swift test`。

运行验证步骤：

- 设置页各分类显示正常。
- 历史数据统计、清理、压缩、导入导出、日志配置正常。
- 发布脚本 dry-run 可检查版本、DMG、tag、release notes。

失败回滚方案：

- UI Section 拆分逐个提交。
- 发布脚本保留旧路径，新增校验先以 dry-run 方式运行。

完成后如何更新文档状态：

- 将“当前执行阶段”更新为“维护完成，进入按需优化”。
- 写入最终验证结果和发布流程说明。

---

## 6. 具体文件改造清单

### 阶段 0

新增文件：

- `Sources/ClipEase/Core/Storage/SQLite/SQLiteSchemaMigrator.swift`
- `Sources/ClipEase/Core/Storage/SQLite/SQLiteBackupManager.swift`
- `Sources/ClipEase/Core/Clipboard/ClipboardSelfWriteGuard.swift`
- `Tests/ClipEaseTests/SQLiteMigrationSafetyTests.swift`
- `Tests/ClipEaseTests/ClipboardSelfWriteGuardTests.swift`

修改文件：

- `Sources/ClipEase/Core/Storage/SQLiteClipboardStore.swift`
- `Sources/ClipEase/Core/Storage/ClipboardHistoryStore.swift`
- `Sources/ClipEase/Core/Storage/ClipboardHistoryPersistence.swift`
- `Sources/ClipEase/Core/Services/ClipboardWriteCoordinator.swift`
- `Sources/ClipEase/Features/PasteExecutor/PasteExecutor.swift`
- `Sources/ClipEase/Core/Utilities/PerformanceDiagnosticsService.swift`

保留文件：

- `Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift`
- `Sources/ClipEase/Features/Settings/SettingsView.swift`
- `scripts/release.sh`

禁止修改：

- 主窗口 UI 布局。
- 卡片样式。
- 设置页视觉结构。
- 现有快捷键行为。

### 阶段 1

新增文件：

- `Sources/ClipEase/Features/HistoryWindow/ViewModels/HistoryWindowViewModel.swift`
- `Sources/ClipEase/Features/HistoryWindow/Search/HistorySearchCoordinator.swift`
- `Sources/ClipEase/Features/HistoryWindow/Viewport/HistoryViewportStore.swift`
- `Sources/ClipEase/Features/HistoryWindow/Preview/HistoryPreviewCoordinator.swift`
- `Sources/ClipEase/Features/HistoryWindow/Groups/GroupAppearanceCoordinator.swift`
- `Tests/ClipEaseTests/HistorySearchCoordinatorTests.swift`
- `Tests/ClipEaseTests/HistoryViewportStoreTests.swift`
- `Tests/ClipEaseTests/HistoryPreviewCoordinatorTests.swift`

修改文件：

- `Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift`
- `Sources/ClipEase/Features/HistoryWindow/HistorySearchController.swift`
- `Sources/ClipEase/Features/HistoryWindow/HistoryWindowInputState.swift`

保留文件：

- `Sources/ClipEase/Core/Storage/SQLiteClipboardStore.swift`
- `Sources/ClipEase/Core/Storage/ClipboardHistoryStore.swift`

禁止修改：

- SQLite schema。
- 数据模型字段。
- 设置页视觉结构。
- 发布脚本。

### 阶段 2

新增文件：

- `Sources/ClipEase/Core/History/ClipboardHistoryDomainStore.swift`
- `Sources/ClipEase/Core/History/DuplicateResolver.swift`
- `Sources/ClipEase/Core/History/GroupService.swift`
- `Sources/ClipEase/Core/History/HistoryPagingService.swift`
- `Sources/ClipEase/Core/History/HistoryRetentionService.swift`
- `Sources/ClipEase/Core/History/LinkMetadataService.swift`
- `Sources/ClipEase/Core/Clipboard/ClipboardSelfWriteGuard.swift`，如果阶段 0 未创建
- `Tests/ClipEaseTests/DuplicateResolverTests.swift`
- `Tests/ClipEaseTests/GroupServiceTests.swift`
- `Tests/ClipEaseTests/HistoryPagingServiceTests.swift`
- `Tests/ClipEaseTests/HistoryRetentionServiceTests.swift`

修改文件：

- `Sources/ClipEase/Core/Storage/ClipboardHistoryStore.swift`
- `Sources/ClipEase/Core/Storage/ClipboardHistoryPersistence.swift`
- `Sources/ClipEase/Core/Utilities/LinkTitleFetcher.swift`

保留文件：

- `Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift`
- `Sources/ClipEase/Core/Storage/SQLiteClipboardStore.swift`

禁止修改：

- UI。
- SQLite schema。
- 发布脚本。

### 阶段 3

新增文件：

- `Sources/ClipEase/Core/Storage/SQLite/SQLiteSchemaMigrator.swift`，如果阶段 0 未创建
- `Sources/ClipEase/Core/Storage/SQLite/SQLiteItemDAO.swift`
- `Sources/ClipEase/Core/Storage/SQLite/SQLiteGroupDAO.swift`
- `Sources/ClipEase/Core/Storage/SQLite/SQLiteSearchIndexDAO.swift`
- `Sources/ClipEase/Core/Storage/SQLite/SQLiteDatabaseCompactor.swift`
- `Sources/ClipEase/Core/Storage/SQLite/SQLiteRowMapper.swift`
- `Sources/ClipEase/Core/Storage/SQLite/SQLiteBackupManager.swift`，如果阶段 0 未创建
- `Tests/ClipEaseTests/SQLiteSchemaMigratorTests.swift`
- `Tests/ClipEaseTests/SQLiteItemDAOTests.swift`
- `Tests/ClipEaseTests/SQLiteSearchIndexDAOTests.swift`

修改文件：

- `Sources/ClipEase/Core/Storage/SQLiteClipboardStore.swift`
- `Sources/ClipEase/Core/Storage/ClipboardHistoryRepository.swift`
- `Sources/ClipEase/Core/Utilities/HistoryExportService.swift`

保留文件：

- `Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift`
- `Sources/ClipEase/Features/Settings/SettingsView.swift`

禁止修改：

- UI。
- 用户交互。
- 没有测试覆盖的 migration。

### 阶段 4

新增文件：

- `Sources/ClipEase/Features/Settings/Sections/SettingsHistoryDataSection.swift`
- `Sources/ClipEase/Features/Settings/Sections/SettingsDiagnosticsSection.swift`
- `Sources/ClipEase/Features/Settings/Sections/SettingsGroupsSection.swift`
- `Sources/ClipEase/Features/Settings/ViewModels/SettingsHistoryDataViewModel.swift`
- `Sources/ClipEase/Features/Settings/ViewModels/SettingsDiagnosticsViewModel.swift`
- `Tests/ClipEaseTests/ReleaseScriptValidationTests.swift`

修改文件：

- `Sources/ClipEase/Features/Settings/SettingsView.swift`
- `Sources/ClipEase/Core/Utilities/PerformanceDiagnosticsService.swift`
- `scripts/build-app.sh`
- `scripts/release.sh`
- `docs/releases/release-checklist.md`
- `docs/releases/release-notes-template.md`

保留文件：

- `Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift`
- `Sources/ClipEase/Core/Storage/SQLiteClipboardStore.swift`

禁止修改：

- 主窗口 UI。
- 卡片交互。
- 数据库 schema。
- 默认隐私行为，除非用户确认。

---

## 7. 执行顺序

后续修复必须严格按以下顺序执行。

### 阶段 0 执行顺序

1. 读取本文档，确认当前阶段是阶段 0。
2. 检查 `git status`，确认当前工作区状态。
3. 为当前数据库升级逻辑增加升级前备份保护。
4. 移除 `user_version < currentSchemaVersion` 时直接 `removeExistingDatabaseFiles()` 的升级路径。
5. 新增 `SQLiteBackupManager`。
6. 新增 `SQLiteSchemaMigrator` 的最小实现。
7. 补充 migration 安全测试，覆盖旧库不会被直接删除。
8. 收口 `ClipboardWriteCoordinator`，确认文本、富文本、图片、文件都从统一入口写入。
9. 新增或抽出 `ClipboardSelfWriteGuard`。
10. 修复 `PasteExecutor.copyImageToPasteboard(_ image:skipText:)` 绕过统一入口的问题。
11. 接入持久化错误日志和诊断事件。
12. 执行 `swift build`。
13. 执行 `swift test`。
14. 启动应用运行基础验证。
15. 递增版本号。
16. 更新本文档阶段 0 状态。
17. 提交 git。

### 阶段 1 执行顺序

1. 确认阶段 0 已完成。
2. 先抽 `HistorySearchCoordinator`。
3. 编译、运行、验证搜索输入、筛选、Esc、Tab、方向键、Enter、空格预览。
4. 再抽 `HistoryViewportStore`。
5. 编译、运行、验证首屏显示、滚动、方向键左右移动。
6. 再抽 `HistoryPreviewCoordinator`。
7. 编译、运行、验证预览位置、左右移动、空格预览。
8. 再抽 `GroupAppearanceCoordinator`。
9. 编译、运行、验证颜色与图标弹窗首次位置、外部点击关闭、新建分组 Enter 确认。
10. 最后新增 `HistoryWindowViewModel`，只承接已稳定的状态域。
11. 执行 `swift test`。
12. 递增版本号。
13. 更新本文档阶段 1 状态。
14. 提交 git。

### 阶段 2 执行顺序

1. 确认阶段 1 已完成。
2. 先抽 `DuplicateResolver`，只迁移纯逻辑。
3. 编译、测试。
4. 再抽 `GroupService`。
5. 编译、测试。
6. 再抽 `HistoryPagingService`。
7. 编译、测试。
8. 再抽 `HistoryRetentionService`。
9. 编译、测试。
10. 再抽 `LinkMetadataService`。
11. 编译、测试。
12. 确认 `ClipboardHistoryStore` 只保留协调入口。
13. 运行核心业务验证。
14. 递增版本号。
15. 更新本文档阶段 2 状态。
16. 提交 git。

### 阶段 3 执行顺序

1. 确认阶段 2 已完成。
2. 先补旧库 fixture。
3. 编写 migration 测试。
4. 完成逐版本 migration。
5. 编译、测试。
6. 拆 `SQLiteRowMapper`。
7. 编译、测试。
8. 拆 `SQLiteItemDAO`。
9. 编译、测试。
10. 拆 `SQLiteGroupDAO`。
11. 编译、测试。
12. 拆 `SQLiteSearchIndexDAO`。
13. 编译、测试。
14. 拆 `SQLiteDatabaseCompactor`。
15. 编译、测试。
16. 拆 `SQLiteBackupManager` 的完整职责。
17. 验证备份导入导出、FTS、压缩、迁移。
18. 递增版本号。
19. 更新本文档阶段 3 状态。
20. 提交 git。

### 阶段 4 执行顺序

1. 确认阶段 3 已完成。
2. 先拆 `SettingsHistoryDataSection` 和对应 ViewModel。
3. 编译、运行设置页。
4. 再拆 `SettingsDiagnosticsSection` 和对应 ViewModel。
5. 编译、运行设置页。
6. 再拆 `SettingsGroupsSection`。
7. 编译、运行设置页。
8. 增强诊断日志可观测性。
9. 增加 `release.sh` dry-run。
10. 增加发布前测试 gate。
11. 增加 DMG 校验。
12. 增加版本一致性校验。
13. 增加 GitHub release asset hash 校验。
14. 预留 Apple notarization 选项。
15. 执行 `swift build`。
16. 执行 `swift test`。
17. 执行 release dry-run。
18. 递增版本号。
19. 更新本文档阶段 4 状态。
20. 提交 git。

---

## 8. 禁止事项

1. 禁止一次性大范围重写 `HistoryWindowView.swift`。
2. 禁止未备份数据库就修改迁移逻辑。
3. 禁止为了拆文件而拆文件。
4. 禁止改变 UI 和用户习惯。
5. 禁止跳过编译验证。
6. 禁止只改 MD 文档不改真实代码，除非当前任务明确只要求写文档。
7. 禁止用临时 `if/else` 掩盖状态机问题。
8. 禁止引入新的全局单例污染。
9. 禁止没有回滚方案的存储层修改。
10. 禁止跨阶段修改后续阶段的文件。
11. 禁止在阶段 0 修改主窗口 UI。
12. 禁止在阶段 1 修改 SQLite schema。
13. 禁止在阶段 2 改变数据模型字段。
14. 禁止在阶段 3 没有旧库 fixture 的情况下修改 migration。
15. 禁止在阶段 4 改变 release notes 既有格式，除非用户确认。

---

## 9. Codex 后续执行协议

以后用户说“按规划继续修复”“继续下一步”“继续执行工程重构”时，Codex 必须：

1. 先读取 `docs/engineering-refactor-plan.md`。
2. 判断当前应该执行哪个阶段。
3. 只执行当前阶段允许的任务。
4. 修改前先列出本轮计划。
5. 修改代码。
6. 编译或运行对应验证。
7. 总结修改文件、修改原因、验证结果。
8. 更新 `docs/engineering-refactor-plan.md` 中该阶段的进度。
9. 不允许跳到后续阶段。
10. 如发现规划外严重问题，必须先报告，不得直接扩大修改范围。
11. 每次代码修改后必须检查 `git status`。
12. 每次阶段完成后必须递增版本号。
13. 每次阶段完成后必须说明是否需要发布 DMG 和 GitHub Release。

---

## 10. 阶段进度记录

### 阶段 0：数据安全与稳定性底线修复

- 状态：收尾验证完成，等待提交确认
- 负责人：Codex
- 目标版本：`2.3.98 (260607.1702)` -> `2.3.98 (260607.1826)`
- 计划修改：SQLite 迁移保护、统一复制写入入口、自身复制忽略、持久化错误可观测
- 验证要求：`swift build`、`swift test`、应用运行基础验证
- 完成记录：
  - 2026-06-07：新增 SQLite 低版本库升级保护，`user_version < currentSchemaVersion` 不再直接删除数据库文件。
  - 2026-06-07：新增升级前 SQLite 备份基础结构，备份主库、`-wal`、`-shm`、`-journal`。
  - 2026-06-07：新增 `SQLiteSchemaMigrator` 基础结构，本阶段只做保守建表/补列/记录版本，不做 DAO 拆分。
  - 2026-06-07：新增 `ClipboardSelfWriteGuard`，统一文本、图片 hash、文件 URL 的自身复制忽略逻辑。
  - 2026-06-07：`PasteExecutor.copyImageToPasteboard` 不再直接 `pasteboard.clearContents()` / `writeObjects`，改为走 `ClipboardWriteCoordinator`。
  - 2026-06-07：持久化失败除 `NSLog` 外，会记录到 `PerformanceDiagnosticsService` 的错误事件。
  - 2026-06-07：新增测试覆盖旧 schema 不清库、升级前备份 sidecar、自身文件复制不入库、图片 hash 写入入口、诊断错误事件 metadata。
  - 2026-06-07：验证通过：`swift build` 成功。
  - 2026-06-07：验证通过：`swift test`，92 个测试通过。
  - 2026-06-07：App 构建并启动成功，`.build/ClipEase.app` 进程已运行。
  - 2026-06-07：自动手工验证通过：文本复制入库，记录数 `710 -> 711`。
  - 2026-06-07：自动手工验证通过：图片复制入库，最新类型为 `image`。
  - 2026-06-07：自动手工验证通过：文件复制入库，最新类型为 `file`。
  - 2026-06-07：自动手工验证通过：数据库存在且未清空，未删除记录数为 `710`，`PRAGMA user_version = 4`。
  - 2026-06-07：`docs/engineering-refactor-plan.md` 已通过 `.gitignore` 例外允许 Git 跟踪。
  - 遗留风险：Computer Use 读取轻贴窗口超时，搜索、预览和主窗口视觉需要用户进行一次人工点击验证；本轮没有进入阶段 1。
  - 是否允许进入阶段 1：阶段 0 提交后，需用户明确确认才允许进入。

### 阶段 1：主窗口状态边界拆分

- 状态：阶段 1-A 已完成，等待用户手工验证和本地提交确认；不得直接进入阶段 1-B。
- 完成记录：
  - 2026-06-07 阶段 1-A 搜索链路拆分与最小迁移：
    - 新增 `Sources/ClipEase/Features/HistoryWindow/HistorySearchCoordinator.swift`。
    - 新增 `Tests/ClipEaseTests/HistorySearchCoordinatorTests.swift`。
    - `HistoryWindowView.swift` 不再直接维护搜索 Task、搜索 generation、请求签名、搜索分页计数和加载更多 Task。
    - `HistorySearchCoordinator` 接管搜索请求去重、异步仓库搜索、仓库结果与当前预览数据合并、搜索分页状态、加载更多分页合并。
    - `HistoryWindowView.swift` 暂时保留搜索框 UI 状态、结果应用、卡片选择、滚动视口、预览跟随和诊断记录，因为这些仍与主窗口视觉和交互强耦合。
    - 验证：`swift build` 通过；`swift test` 通过，95 个测试全部通过。
    - 遗留风险：需要用户手工验证搜索输入、筛选、Tab/方向键交接、搜索结果滚动加载、预览弹窗位置没有回归。
    - 阶段 1-B 入口条件：阶段 1-A 手工验证正常，并完成本地 Git 提交后，再由用户明确确认继续。
  - 2026-06-07 阶段 1-B / 1-C 预览协调器与滚动视口状态边界拆分：
    - 新增 `Sources/ClipEase/Features/HistoryWindow/HistoryPreviewCoordinator.swift`。
    - 新增 `Sources/ClipEase/Features/HistoryWindow/PreviewAssetPreheater.swift`。
    - 新增 `Sources/ClipEase/Features/HistoryWindow/HistoryViewportStore.swift`。
    - 新增 `Sources/ClipEase/Features/HistoryWindow/RenderWindowCoordinator.swift`。
    - 新增 `Tests/ClipEaseTests/HistoryPreviewViewportCoordinatorTests.swift`。
    - `HistoryWindowView.swift` 不再直接维护预览跟随 Task、预览跟随 pending item、滚动视口可见矩形和视口模式。
    - 预览资源预热的范围计算、后台缩略图/icon/rich text 预热逻辑迁入 `PreviewAssetPreheater`。
    - 渲染窗口内容宽度、视口上下文、窗口切片和卡片文档 frame 纯计算迁入 `RenderWindowCoordinator`。
    - `HistoryWindowView.swift` 暂时保留 `showPreview` / `closePreview`、真实滚动执行、选中/焦点恢复、预览内容获取，因为这些仍直接依赖 `store`、`inputState`、`onPreview`、`onClosePreview` 和 `HistoryScrollCoordinator`。
    - 验证：`swift build` 通过；`swift test` 通过，104 个测试全部通过；用户已手工确认方向键滚动闪动问题修复。
    - 遗留风险：需要用户手工验证预览位置跟随、方向键左右切换、鼠标点击卡片、搜索后滚动加载、首次打开主窗口卡片渲染没有回归。
    - 阶段 1-D 入口条件：阶段 1-B / 1-C 手工验证正常，并完成本地 Git 提交后，再由用户明确确认继续。
  - 2026-06-07 阶段 1-D 分组外观弹窗协调器拆分：
    - 新增 `Sources/ClipEase/Features/HistoryWindow/GroupAppearanceCoordinator.swift`。
    - 新增 `Sources/ClipEase/Features/HistoryWindow/SystemHistoryGroup.swift`，将非 UI 的系统分组模型从 `HistoryWindowView.swift` 迁出。
    - 新增 `Tests/ClipEaseTests/GroupAppearanceCoordinatorTests.swift`。
    - `HistoryWindowView.swift` 不再直接维护分组外观目标、系统分组目标、颜色、图标、图标搜索文本和弹窗窗口引用。
    - `GroupAppearanceCoordinator` 接管普通分组/系统分组打开、共享弹窗状态、图标搜索 Escape 行为、关闭弹窗和关闭整层状态。
    - `HistoryWindowView.swift` 暂时保留弹窗 UI、颜色面板关闭、`store.updateGroupAppearance` 和系统分组 `@AppStorage` 写入，因为这些直接影响 UI 渲染和持久化入口。
    - 验证：`swift build` 通过；`swift test` 通过，105 个测试全部通过。
    - 手工验证：用户已确认阶段 1-D 验证无问题。
    - 遗留风险：阶段 1-D 暂未发现已知回归；后续阶段 1 收尾仍需继续保持不改变 UI 和交互。
    - 阶段 1 收尾入口条件：阶段 1-D 手工验证正常，并完成本地 Git 提交后，再由用户明确确认继续。

### 阶段 2：ClipboardHistoryStore 职责拆分

- 状态：阶段 2-A 已完成，等待用户手工验证和本地提交确认；不得直接进入阶段 2-B。
- 完成记录：
  - 2026-06-07 阶段 2-A DuplicateResolver 纯逻辑拆分：
    - 新增 `Sources/ClipEase/Core/History/DuplicateResolver.swift`。
    - 新增 `Tests/ClipEaseTests/DuplicateResolverTests.swift`。
    - `ClipboardHistoryStore.swift` 不再直接维护内容去重 key 计算、重复项合并、导入非重复过滤的纯逻辑。
    - `DuplicateResolver` 接管文本/链接/颜色、图片、文件的内容 key 生成；接管缓存重复项与持久化重复项合并；接管导入数据按 ID 和内容去重。
    - `ClipboardHistoryStore.swift` 暂时保留 `upsertClipboardItem` 中删除旧 rich text/image 文件、取消 OCR/链接任务、写入数据库、更新焦点和性能日志的副作用逻辑，因为这些仍依赖 Store 当前状态和持久化入口。
    - 测试稳定性：将 `historyPreviewCoordinatorClearsPendingFollowAfterRetries` 从固定 sleep 改为条件等待，避免完整并发测试中 MainActor 调度慢导致误报失败；未修改生产逻辑。
    - 验证：`swift build` 通过；`swift test` 通过，110 个测试全部通过。
    - App 构建：已运行 `./scripts/build-app.sh`，版本从 `2.3.101 (260607.1934)` 更新到 `2.3.102 (260607.1949)`，新版 `.build/ClipEase.app` 已启动。
    - 手工验证：用户已确认阶段 2-A 验证无问题。
    - 遗留风险：阶段 2-A 暂未发现已知回归；后续拆分 Store 仍需逐步迁移，避免改变入库、去重和持久化副作用。
    - 阶段 2-B 入口条件：阶段 2-A 手工验证正常，并完成本地 Git 提交后，再由用户明确确认继续。

### 阶段 3：SQLite 存储层工程化拆分

- 状态：等待阶段 2 完成
- 完成记录：尚无

### 阶段 4：设置页、诊断页、发布流程优化

- 状态：等待阶段 3 完成
- 完成记录：尚无
