# 第二版技术方案草案

## 0. 2026-05-14 新基线覆盖说明

本节覆盖本文后续早期技术方案中与当前基线冲突的内容：

- 当前技术基线为 SQLite-only。
- 旧 JSON 数据代码、JSON Repository、JSON 到 SQLite 迁移代码不再作为运行时能力维护；旧数据不重要。
- 收藏字段、收藏 UI、收藏快捷键和收藏筛选已移除，不得恢复。
- 管理模式、多选和批量操作已移除，不得恢复。
- 分组、置顶、搜索、备份导入安全和单条操作继续保留。
- 后续任何 schema、备份包格式、导入策略、附件生命周期、保存期限清理或删除语义变化，都必须单独走红线任务。
- 本文中关于 `is_favorite`、收藏、JSON 迁移、JSON 回退、迁移失败清空重建的旧描述只作为历史方案背景，不作为后续实现依据。
- 主控 Agent 不写业务代码、不亲自修 bug；架构、schema、Repository、性能问题必须交给架构守门 Agent + 原开发 Agent。
- 每个阶段开始前必须先由 V2 测试计划 Agent 检查测试 / 验收门禁；每次 bug、返工或新增功能前必须读取 `docs/V2_FEEDBACK_AND_GUARDS.md`。

## 1. 技术目标

第二版技术目标是为长期使用做底层升级：

- 从 JSON 历史索引迁移到 SQLite。
- 支持更大规模历史数据。
- 支持分组、置顶、单条操作和更强搜索。
- 为未来 iCloud 同步预留数据结构，但不在第二版第一阶段直接实现同步。

## 2. 数据库方向

第二版建议使用 SQLite 作为主存储。

原因：

- 历史记录会增长到几千、几万条。
- 搜索、筛选、排序和分组更适合由数据库索引支撑。
- JSON 整文件读写在大数据量下风险更高。
- SQLite 后续更容易做数据迁移和同步预研。

## 3. 建议表结构

### 3.1 clipboard_items

保存所有历史和长期内容的主记录。

建议字段：

- `id`
- `type`
- `plain_text`
- `source_app_name`
- `source_bundle_id`
- `source_icon_file_name`
- `header_color`
- `created_at`
- `updated_at`
- `last_used_at`
- `is_pinned`
- `is_deleted`
- `retention_exempt`
- `last_edited_at`
- `group_sort_order`
- `content_hash`

### 3.2 item_assets

保存图片、缩略图、富文本等附件引用。

建议字段：

- `id`
- `item_id`
- `asset_type`
- `file_name`
- `original_file_name`
- `width`
- `height`
- `byte_size`
- `created_at`

### 3.3 groups

保存分组。

建议字段：

- `id`
- `name`
- `color_hex`
- `icon_name`
- `sort_order`
- `created_at`
- `updated_at`

第二版第一阶段建议只做单层分组。

### 3.4 group_items

保存内容和分组的关系。

如果第二版坚持“类似文件夹，一个内容只属于一个分组”，可以用 `clipboard_items.group_id` 简化。

建议保留关系表的原因：

- 未来可以平滑升级到标签或多分组。
- 不影响当前“一个内容只属于一个分组”的产品规则。

第一阶段可以通过业务规则限制每个 item 只有一条有效分组关系。

### 3.5 saved_searches

暂缓实现，但可预留。

未来用于保存常用搜索条件，例如“Chrome 最近 7 天链接”。

## 4. 迁移策略

状态：历史方案，已被 SQLite-only 新基线覆盖。后续不再维护 JSON 到 SQLite 迁移作为运行时路径；旧 JSON 数据不重要。

### 4.1 当前决策

- SQLite 迁移验证直接切换 App 主存储。
- 首次升级时从 `history.json` 导入 SQLite。
- 迁移前不额外备份 `history.json`。
- 迁移失败后清空数据重建。
- 迁移成功后删除原 JSON。
- 数据库文件名为 `ClipEase.sqlite`。
- 迁移过程需要显示进度。
- 设置页保留最近 5 次迁移结果。
- 第二版数据健康检查优先支持 SQLite。
- 第二版导入导出默认使用 SQLite 备份包。
- SQLite 备份包扩展名为 `.clipeasebackup`。
- 导出备份包时由用户选择是否包含图片、富文本等附件。
- 导出备份包时，“包含附件”默认勾选。
- 导出备份成功后显示提示，用户点击“显示”后再在 Finder 中定位文件。
- 导入备份包遇到重复记录时弹窗让用户选择处理方式。
- 导入备份包遇到重复记录时，弹窗默认推荐“跳过重复”。
- 数据健康检查发现问题后提供“一键修复”。
- 数据健康检查“一键修复”前每次都确认，完成后生成简短报告。
- 1,000 / 10,000 条测试数据入口移到设置页隐藏入口。
- 测试数据入口通过在设置页连点版本号 5 次显示。

### 4.2 建议流程

1. 启动时检查 SQLite 数据库是否存在。
2. 如果不存在，读取现有 `history.json`。
3. 创建 SQLite 表。
4. 将历史记录、图片附件、富文本附件导入数据库。
5. 导入完成后写入迁移标记。
6. 删除原 JSON 文件。

### 4.3 回滚策略

- SQLite 初始化失败：清空数据重建。
- 单条记录迁移失败：按迁移失败处理，进入清空重建流程。
- 迁移失败清空重建前不做二次确认，直接重建。
- 迁移失败直接清空重建时显示短提示。
- 附件缺失：保留主记录，标记附件缺失。

## 5. 搜索性能策略

第二版搜索建议分层：

- 普通文本字段使用 SQLite 查询。
- 来源 App、类型、时间、分组使用索引过滤。
- 高亮仍在 UI 层处理。
- 输入搜索继续防抖，避免每个键都触发过重查询。

当前决策：

- SQLite FTS5 全文搜索。
- 普通 `LIKE` 查询。

规则：

- 第二版第一阶段同时准备普通索引 + `LIKE` 和 FTS5 方案。
- 默认搜索路径根据实际性能动态决定。

## 6. 附件策略

图片、缩略图、富文本仍保存在 Application Support 目录。

数据库只保存附件索引，不把大文件直接塞进 SQLite。

原因：

- 避免数据库膨胀。
- 附件导入导出更清晰。
- 后续 iCloud 或备份包处理更灵活。

## 7. 分组技术规则

状态：本章旧收藏规则已废弃；只保留分组、置顶和编辑相关规则。

- 分组删除默认一并删除组内内容，必须执行明确确认流程。
- 有内容分组删除确认弹窗的危险按钮文案为“删除分组和内容”。
- 置顶和分组是两个不同维度，不互相替代。
- 普通历史执行“加入分组 / 移动到分组”时，只建立或更新分组关系，不复制新记录，不引入收藏语义。
- 普通历史编辑提交后更新原记录内容，不新增记录；分组和置顶状态保持不变。
- 编辑记录时更新 `updated_at` 和 `last_edited_at`，并重新计算搜索文本、预览摘要和内容 hash。
- 编辑记录不保留编辑前版本历史。
- 分组需要保存颜色和图标，用于顶部 Pinboard 样式分组按钮。
- 顶部分组栏需要支持横向滚动。
- 新建分组默认名称为“新分组”，默认颜色来自固定预设色板，默认图标为随机图标，创建后立即允许用户修改名称、颜色和图标。
- 分组图标来源为系统图标 + 轻贴内置图标库，暂不支持自定义图片。
- 分组重命名支持右键分组按钮和双击分组按钮。
- 分组颜色和图标修改支持右键分组按钮和分组管理面板。
- 分组颜色允许使用系统取色器自定义。
- 分组图标允许搜索。
- 空分组删除不需要确认；有内容分组删除需要普通确认弹窗，并显示删除内容数量和不可恢复提示。
- 分组支持拖拽排序，排序结果写入 `sort_order`。
- 分组顶部按钮默认不显示数量，悬停时显示数量。
- 分组内容按加入分组时间倒序排列。
- 新建分组后不自动进入新分组，主窗口仍停留在当前分组。
- 顶部分组栏横向滚动，并在右侧提供更多分组入口。
- 更多分组入口点击右侧“更多”按钮弹出菜单。
- 更多分组超过 10 个时显示分组搜索。
- 分组管理窗口的批量删除不进入当前基线；如未来恢复，必须单独走删除安全任务。

## 8. 富文本卡片技术规则

第二版富文本卡片需要在主窗口内显示基础格式。

建议：

- 富文本附件仍保存在 `RichTexts` 目录。
- SQLite 主表保存纯文本摘要，用于搜索和快速列表构建。
- 卡片显示时读取轻量富文本摘要或缓存，不直接在主线程解析完整 RTF。
- 富文本卡片尽量按复制时的格式显示，包括字体样式、字号、文字颜色和背景色等可安全渲染的格式。
- 搜索高亮应叠加在富文本显示层上，不能破坏原始富文本附件。
- 富文本编辑保存后尽量保留原富文本格式。

风险：

- 大量富文本卡片同时渲染会影响主窗口动画。
- 需要建立富文本预览缓存，或限制卡片级富文本渲染范围。

## 9. 文件卡片和系统级预览

第二版需要支持复制本地文件时记录文件卡片。本节为 Stage 9 开工前架构 preflight；未完成本节红线确认前，不进入业务代码实现。

### 9.1 Schema 和数据模型

结论：需要新增 schema version。文件卡片不是纯文本或现有附件记录，必须显式建模，不能把多个路径拼进 `plain_text` 作为长期方案。

最小 schema 方向：

- `clipboard_items.type` 增加 `file` 类型。
- `clipboard_items.plain_text` 保存用于列表和搜索的轻量摘要，例如首个文件名、文件数量和换行路径摘要；不得作为文件元数据唯一来源。
- 新增 `clipboard_item_files` 表，按 item 保存 1 个或多个本地文件引用。
- `clipboard_item_files` 最小字段：`id`、`item_id`、`display_order`、`file_path`、`file_name`、`file_extension`、`uti_or_content_type`、`byte_size`、`modified_at`、`is_directory`、`is_alias`、`path_status`、`last_checked_at`、`created_at`。
- `path_status` 至少区分 `unknown`、`available`、`missing`、`permission_denied`、`placeholder`。
- 不保存文件内容，不把原文件复制进附件目录，不把文件二进制放入 SQLite。
- 不记录 security-scoped bookmark，不新增长期文件访问授权模型。
- 多文件卡片必须保存 `display_order`，捕获顺序作为首批排序规则。
- 置顶和分组继续使用现有 item 维度能力；文件子表不承载分组或置顶字段。

迁移 / 重建策略：

- Stage 9 schema 变更必须走 schema version 升级任务，先验证新库创建，再验证旧 SQLite 最小迁移。
- 迁移只新增表 / 索引 / 类型识别，不改写既有文本、图片、富文本记录语义。
- SQLite-only 基线不恢复 JSON 迁移路径。
- 如果开发期数据库无法迁移，可以按当前 V2 规则清空重建；发布后必须保留 SQLite schema upgrade 路径。
- 备份包格式如包含新表，需要单独更新导入导出测试；备份仍只包含路径元数据，不包含原文件副本。

### 9.2 Clipboard 捕获

捕获入口：

- 优先识别 `NSPasteboard.PasteboardType.fileURL` / Finder 写入的文件 URL 数据。
- 只记录本地 `file://` URL；非本地 URL、网络下载 URL 或无法转换为本地路径的条目首批不记录为文件卡片。
- 支持 1 个或多个文件 URL；多文件保留 Finder / pasteboard 顺序。
- 目录也按文件引用记录，`is_directory = true`，展示使用系统目录图标。

边界处理：

- alias / symlink 首批不解析到最终目标，只记录用户复制时的路径，并标记 `is_alias` 或通过文件属性在预览前提示；不得静默改写为目标路径。
- 网络盘路径可以记录完整路径，但预览 / 粘贴 / 拖出前必须重新校验存在性和权限。
- iCloud 占位文件可以记录路径；预览前如果发现未下载或读取失败，标记为 `placeholder` 或 `permission_denied`，不主动触发大文件下载作为首批能力。
- 权限失败时保留历史记录，`path_status = permission_denied`，卡片和预览显示不可访问状态。
- 捕获时读取元数据失败不应导致整个剪贴板记录失败；至少保留路径、文件名和 `unknown` 状态。
- 不新增设置开关，文件卡片默认记录。

### 9.3 Repository / API 边界

UI 不直接读取 SQLite，也不直接拼 SQL 查询文件元数据。

建议边界：

- Repository 对外返回统一 `ClipboardItem` / view model 所需的文件摘要，例如文件数量、首个文件名、首个路径、失效数量。
- 文件详情通过 Repository 方法按 item id 获取，例如 `files(for itemID:) -> [ClipboardFileReference]`。
- 文件状态刷新通过服务层完成，例如 `FileReferenceResolver` / `FileMetadataProvider`，由 Repository 持久化状态结果。
- UI 可以请求文件图标、缩略图和 Quick Look item，但不能绕过 Repository 更新数据库字段。
- Clipboard monitor 捕获到文件 URL 后，通过 Repository 的新增文件项 API 写入 item 和文件子表，不能由 monitor 直接写 SQLite。
- Paste executor 和 drag provider 从 Repository 或内存 view model 取得文件引用，不从 SQLite 裸读。

### 9.4 Quick Look 技术方案

首批建议复用现有 preview window 的窗口生命周期，并在文件类型预览内容区域接入 Quick Look，而不是直接让全局 `QLPreviewPanel` 替代现有预览窗口。

方案裁定：

- 优先采用现有 `HistoryPreviewWindowController` 作为宿主，文件项内部使用 Quick Look 可预览能力；如 SwiftUI / AppKit 嵌入受限，再评估 `QLPreviewPanel`。
- `QLPreviewPanel` 是全局共享面板，容易和主窗口焦点、Esc 关闭、窗口层级产生竞争；若使用，必须单独封装 coordinator，明确 `acceptsPreviewPanelControl`、data source、delegate 和失焦关闭规则。
- 现有预览窗口必须始终在主窗口前方，但不抢走粘贴目标 App 的最终自动粘贴焦点。
- Space 打开预览、Esc 关闭预览；预览打开时 Esc 不应直接关闭主窗口。
- 主窗口关闭时同步关闭文件预览和 Quick Look 控制器。
- 选中项切换时刷新预览数据源；文件路径失效或权限失败时显示文件图标、基础信息和错误状态。
- Quick Look 加载和缩略图生成不能阻塞主窗口动画；首批可先显示系统图标和加载态。
- 多文件预览首批以文件列表 + 当前选中文件 Quick Look 预览为主；不要在一个窗口内同时实例化多个重型预览。

### 9.5 粘贴和拖出

粘贴策略：

- 文件卡片执行粘贴时，向 `NSPasteboard` 写入文件 URL 类型，优先使用 `writeObjects(_:)` 写入 `[NSURL]` 或等价 `fileURL` pasteboard representation。
- 多文件卡片一次写入全部可用文件 URL，顺序使用 `display_order`。
- 粘贴前重新校验路径；失效或无权限的文件不写入文件 URL。
- 如果全部文件都不可用，fallback 写入文件名或路径文本，并显示短提示。
- 如果目标 App 不支持文件引用，系统通常不会给出可靠同步回执；首批 fallback 只能在执行前发现不可用时触发，或提供“复制路径 / 文件名”菜单，不能承诺精确检测目标 App 支持度。

拖出策略：

- 文件卡片支持拖出时，drag pasteboard 写入文件 URL 类型。
- 拖出前同样校验路径；部分失效时只拖出可用项，并在 UI 标记失效数量。
- 不支持拖出原文件副本，不创建临时副本，不修改原文件。

### 9.6 搜索策略

首批只做内存搜索文件名和路径。

规则：

- Repository 列表加载时返回文件摘要，搜索层在现有内存过滤链路中匹配文件名和路径。
- 不为 Stage 9 首批新增 LIKE / FTS / 拼音索引 / schema 搜索索引。
- 文件搜索只覆盖文件名和完整路径；拼音搜索延后到搜索性能专项。
- 如果大量文件卡片导致性能问题，再单独开搜索下沉任务，不能混入 Quick Look 首批实现。

### 9.7 安全与隐私

- 文件卡片必须记录完整路径，不允许只记录文件名。
- UI 首批不隐藏用户名；完整路径会进入 SQLite 和备份包元数据。
- 不记录 security-scoped bookmark，不长期持有用户授权，不绕过系统权限。
- 删除历史记录只删除 ClipEase 里的记录，不删除、不移动、不重命名原文件。
- 备份包只包含文件路径和元数据，不包含原文件副本。
- 文件卡片不参与敏感遮罩首批逻辑；如未来纳入，必须单独做隐私方案。
- “在 Finder 中显示”“打开文件”“系统分享”都基于当前路径即时校验，失败只提示，不清理原历史。

### 9.8 文件锁和禁改范围

文件锁：

- 文件被其他 App 占用、锁定、只读或不可写，不影响 ClipEase 记录路径。
- Stage 9 首批不写入原文件，不修改扩展属性，不解析或修复 alias，不下载 iCloud 占位文件。
- 打开、预览、粘贴、拖出都按只读引用处理。

禁改范围：

- 不恢复收藏、收藏字段、收藏 UI 或收藏快捷键。
- 不恢复管理模式、多选、批量操作或批量导出。
- 不恢复 JSON 迁移运行时路径。
- 不改变现有删除 / 撤销 / 附件清理 / 保存期限清理语义。
- 不把文件原件纳入附件生命周期或备份附件包。
- 不在 Stage 9 首批引入搜索 LIKE / FTS / 拼音索引。

### 9.9 实施阶段拆分建议

1. Schema preflight：新增 schema version、`clipboard_item_files` 表、Repository DTO 和迁移 / 重建测试。
2. Capture preflight：Clipboard monitor 识别 Finder 文件 URL、多个文件、目录、alias / symlink、权限失败和 iCloud 占位状态。
3. Card read model：UI 通过 Repository 获取文件摘要，卡片展示系统图标、标题、路径和失效状态。
4. Preview spike：在现有 preview window 中验证 Quick Look 嵌入；如不可控，再切 `QLPreviewPanel` coordinator 方案。
5. Paste / drag spike：验证 `NSPasteboard` 文件 URL 写入、多文件顺序、失效 fallback 和目标 App 不支持时的文案。
6. Search minimal：文件名 / 路径内存搜索，不做 SQL 搜索下沉。
7. Backup / privacy verification：确认备份只包含路径元数据，删除历史不影响原文件。

风险：

- 文件路径可能被移动、重命名、删除、锁定、未下载或因权限不可读，需要在预览、粘贴和拖出前校验。
- Quick Look 预览不能阻塞主窗口动画。
- `QLPreviewPanel` 的全局面板行为可能打破现有窗口层级和 Esc 规则，必须先 spike。
- 完整路径进入数据库和备份包，属于明确隐私边界。

## 10. 窗口、快捷键和提示层

### 10.1 新历史后的滚动位置

需要记录历史列表的“数据版本”。

规则：

- 如果 Store 新增了剪贴板历史，下次打开主窗口时滚动到第一条。
- 如果没有新增历史，继续恢复用户上次横向滚动位置。

### 10.2 快捷键注册

第二版需要统一菜单快捷键来源，避免右键菜单、系统菜单和更多菜单显示不一致。

建议：

- 建立统一的 `CommandRegistry` 或等价结构。
- 每个命令定义标题、快捷键、适用内容类型、执行动作。
- 右键菜单、系统菜单和主界面更多菜单都从同一命令定义生成。
- 主窗口右侧 `...` 菜单和菜单栏图标右键菜单必须复用同一套命令定义。
- 卡片右键菜单必须展示对应快捷键，并通过分割线按粘贴、复制、管理、危险操作分组。

已确认快捷键：

- `Command + ,`：打开设置。
- `Command + E`：编辑当前文本或链接卡片。
- `Command + T`：暂停 / 恢复轻贴记录。
- `Command + D`：删除当前选中记录。
- `Command + M`：不注册管理模式命令。

链接卡片编辑规则：

- `Command + E` 编辑链接时，编辑对象是 URL 地址。
- 链接编辑窗口只编辑 URL，不增加标题和备注字段。
- 链接编辑窗口底部显示当前 URL。
- “在 默认浏览器 中打开”按钮文案需要从系统默认浏览器读取，例如 Chrome、Edge 或 Safari。
- 链接 URL 编辑保存后，后台重新抓取网页标题和图标。
- 链接 URL 编辑保存后，立即复制新 URL 到剪贴板。
- 链接 URL 编辑保存后显示全局提示“链接已更新并复制”。

卡片右键菜单快捷键显示规则：

- 使用 macOS 符号格式，例如 `⌘C`、`⇧⌘C`、`⏎`。

### 10.3 隐私和敏感遮罩

规则：

- 敏感内容是否记录原内容由用户按规则选择。
- 敏感遮罩验证使用系统密码或 Touch ID。
- 验证通过后，被遮罩内容显示 30 秒。

### 10.4 搜索和筛选弹层

规则：

- 筛选按钮放在搜索框右侧。
- 搜索框未展开时，按 `Command + F` 展开搜索框并聚焦。
- 搜索框打开后，再次按 `Command + F` 弹出筛选面板。
- 筛选面板打开时，再次按 `Command + F` 关闭筛选面板并聚焦搜索框。
- 筛选面板使用独立悬浮层，位置锚定搜索框右侧筛选按钮。
- 筛选面板需要支持类型、来源 App、日期和设备等分组。
- 来源 App 按最近使用排序。
- 类型筛选在筛选面板中为单选。
- 搜索框需要支持多个筛选 token 并存，例如类型、来源 App 和日期。
- 筛选 token 支持关闭按钮删除，也支持 Backspace 删除。
- 多个筛选 token 在搜索框内横向展示，超出宽度时横向滚动。
- 搜索框横向滚动时，输入光标必须保持可见。
- 筛选 token 不支持拖拽排序，按固定顺序展示：类型、App、日期、分组。
- 固定顺序中如果没有某一类筛选条件，后续 token 前移，保持紧凑。
- 筛选 token 点击本体无动作，只能通过关闭按钮、Backspace 或筛选面板修改。
- 筛选面板不长期保存上次打开位置和滚动位置。
- 筛选面板每次打开回到顶部。
- 筛选面板顶部不显示已选条件摘要。
- 设备筛选默认不显示，只有未来同步预研相关功能开启后才显示。
- 筛选条件变化不能阻塞搜索输入。

### 10.5 窗口层级

规则：

- 主窗口显示时保持在前方。
- 预览窗口必须显示在主窗口前方。
- 新建文本、设置、帮助窗口与主窗口关闭逻辑分离。
- 从主窗口更多菜单打开新建文本时，先隐藏主窗口，再显示新建文本窗口。

### 10.6 全局提示层

建议实现为独立轻量 `NSPanel`。

要求：

- 层级高于主窗口和预览窗口。
- 无边框。
- 不抢焦点。
- 内容显示来源 App 图标和短提示。
- 全局提示层始终显示来源 App 图标。
- 支持淡入淡出和约 1 秒自动关闭。

需要避免：

- 不在主窗口内部显示提示，避免受主窗口布局和层级影响。
- 不用于危险操作确认。

### 10.7 主窗口顶部简化

规则：

- 主窗口顶部不再常驻展示可在设置中操作的状态项，例如自动粘贴、记录中、永久记录。
- 主窗口右侧更多按钮只显示 `...`。
- 搜索框、筛选按钮、顶部字体和图标尺寸需要比第一版更大。
- 默认只显示搜索图标，点击搜索图标或直接输入后展开搜索框。
- 搜索框展开后自动聚焦，光标停在末尾，不选中已有内容。
- 搜索框中筛选 token 在前，关键词在后。
- 点击搜索框清空按钮时，同时清空关键词和全部筛选 token。
- 搜索框清空按钮在有关键词或筛选 token 时显示。
- 点击清空按钮后保持搜索框展开并聚焦。
- Esc 处理顺序为：关闭筛选面板、清空搜索内容和筛选 token、关闭搜索框、关闭主窗口。
- 搜索框展开后，点击主窗口内其他区域时搜索框保持展开。
- 筛选面板打开时，点击主窗口卡片先关闭筛选面板，再选中卡片。
- 搜索框展开且没有关键词和筛选 token 时，点击主窗口外部直接关闭主窗口。
- 筛选面板打开时，点击主窗口外部同时关闭筛选面板和主窗口。
- 搜索框聚焦时，左右方向键优先移动文本光标，上下方向键按系统文本框默认行为处理。
- 搜索框聚焦时，按回车进入卡片选择。
- 搜索框光标位于文本末尾时，按方向右键或方向下键进入卡片选择。
- 进入卡片选择后，搜索框保持展开，卡片显示选中态。
- 从卡片选择返回搜索框的方式为点击搜索框或按 `Command + F`。
- 搜索框聚焦时按 Tab 进入卡片列表；卡片列表中再次按 Tab 返回搜索框，光标回到原位置。
- 卡片列表中按 `Shift + Tab` 反向切换卡片。
- 搜索框有中文输入法候选时，回车优先确认候选词；没有候选框时，回车进入卡片选择。
- 卡片选择状态下继续输入文字，会回到搜索框并追加输入。
- 卡片选择状态下继续输入文字后，保留当前卡片选中态，直到搜索结果更新。
- 搜索结果更新后，自动选中第一条结果。
- 卡片选择状态下按 Delete 或 Backspace 删除选中卡片。
- Delete / Backspace 删除卡片不弹确认，直接删除。
- 删除当前卡片后选中右侧下一张。
- 删除卡片后显示全局提示“已删除”，并提供撤销入口。
- 撤销提示持续 8 秒。
- 撤销后卡片恢复到原位置。
- 批量删除和逐条撤销动画不进入当前基线；如未来恢复，必须单独走删除 / 撤销安全任务。
- 删除分组里的内容时，从所有地方彻底删除。
- 删除图片卡片时立即删除本地图片附件。
- 撤销图片删除时需要恢复已删除的本地图片附件。
- 点击清空按钮后不显示全局提示。
- 默认剪切板历史分组代表全部剪切板内容。

## 11. iCloud 同步预留

第二版不直接实现 iCloud 同步，但数据结构要避免未来重做：

- 所有主表使用稳定 UUID。
- 记录 `created_at`、`updated_at`。
- 软删除字段 `is_deleted` 为未来冲突处理预留。
- 附件用独立表管理。

未来同步需要继续评估：

- 冲突合并策略。
- 附件同步和断点恢复。
- 隐私和加密。
- 多设备删除同步。

### 11.1 Stage 10 iCloud 同步预研架构结论

任务卡：`V2-ARCH-S10-ICLOUD-SYNC-PREFLIGHT-001`

结论：Stage 10 可以继续做同步预研，但不得进入 runtime 实现。当前 SQLite-only 基线具备部分同步友好字段，但还不足以直接承载可靠多设备同步；任何 CloudKit / iCloud 实现前都必须先完成 schema gap 清单、用户确认和独立 spike 拆分。

本轮只允许文档结论：

- 不改 SQLite schema。
- 不新增 soft delete / device table / sync state table。
- 不新增 iCloud entitlements、CloudKit container、CloudKit runtime、同步 UI 或设备筛选 UI。
- 不实现附件上传下载、冲突合并、端到端加密或跨设备删除同步。
- 不恢复 JSON runtime、收藏或管理模式。

### 11.2 当前 SQLite schema / model 对同步的预留情况

已具备的基础：

- 稳定 UUID：`clipboard_items`、`item_assets`、`clipboard_item_files`、`groups`、`group_items` 均使用 `TEXT` UUID 主键；`ClipboardItem`、`ClipboardFileReference`、`ClipboardGroup` 模型也使用 UUID。
- 时间字段：`clipboard_items` 有 `created_at`、`updated_at`、`last_used_at`、`pinned_at`、`last_edited_at`；`groups` 有 `created_at`、`updated_at`；`item_assets`、`clipboard_item_files`、`group_items` 有 `created_at`。
- 软删除预留：`clipboard_items.is_deleted` 存在，列表读取使用 `WHERE is_deleted = 0`。
- 来源信息：`source_app_name`、`source_bundle_id`、`source_icon_name`、`source_icon_file_name` 已记录来源 App 和图标文件名。
- 附件表：`item_assets` 独立保存图片 / 富文本等附件索引，SQLite 不直接保存大二进制。
- 文件卡片表：`clipboard_item_files` 独立保存多个本地文件引用、顺序、路径、文件名、类型、大小、目录 / alias、路径状态和检查时间。
- 分组关系：`groups` 独立建模，`group_items` 用 `UNIQUE(item_id)` 保持当前单分组规则，同时保留未来多分组 / 标签升级空间。
- 备份包：`.clipeasebackup` 以 SQLite 为核心，并可复制 `Images` / `RichTexts` 附件；文件卡片只带路径元数据，不复制原文件。

同步前缺口：

- `updated_at` 当前在 insert 时等于 `created_at`，许多后续本地状态变化依赖全量 snapshot 重写；缺少可靠的逐字段修改时间或变更版本。
- `is_deleted` 目前只是字段预留，不是完整 tombstone 机制；没有 `deleted_at`、`deleted_by_device_id`、删除保留期限或远端清理策略。
- 没有 device / source-of-change 维度：缺少 `device_id`、`origin_device_id`、`modified_by_device_id`、本机安装实例 ID 和设备显示名。
- 没有同步游标 / zone change token / per-record sync state；无法增量拉取、断点恢复或区分本地脏数据与已上传数据。
- 没有 record change tag / server version；CloudKit 冲突无法映射回本地 record 版本。
- `ClipboardItem` model 未暴露 `updatedAt`、`isDeleted`、`lastEditedAt` 等字段，Repository API 也没有面向增量同步的变更读写接口。
- `item_assets` 缺少附件内容 hash、mime / uti、加密元数据、远端 asset id、上传状态和本地缓存状态。
- App icon 只有本地 `source_icon_file_name` 引用，没有纳入备份附件目录，也没有同步策略；可重建时应优先从 bundle id / 系统图标重取，而不是作为首批同步资产。
- `clipboard_item_files.file_path` 是本机绝对路径，跨设备不可用；当前设计也不保存 security-scoped bookmark 或原文件副本。
- `group_items` 当前只有加入时间和 sort_order；未来若恢复多分组或跨设备排序，需要明确同一 item 多关系冲突和排序合并规则。

### 11.3 CloudKit / iCloud 方案候选

候选 A：CloudKit private database。

- 优点：每个用户私有数据库天然按 Apple ID 隔离；支持 record zone、增量变更、server change token、CKAsset、订阅推送和系统级账号状态；适合历史条目、分组、置顶和轻量附件元数据。
- 缺点：需要 CloudKit container / entitlement / record schema / zone migration；冲突、删除 tombstone、离线重试和配额仍需 App 自己设计；不是自动端到端加密承诺，不能把“private DB”表述成“只有用户设备可解密”。
- 适用判断：未来正式同步首选候选，但 Stage 10 只能做设计和 spike 拆分，不能接入 runtime。

候选 B：iCloud Drive 文件同步。

- 优点：可把备份包或导出文件放入 iCloud Drive，用户可见、可手动管理；对完整 SQLite 包 / 附件目录的迁移理解成本低。
- 缺点：不适合作为多设备实时数据库；SQLite/WAL 文件并发同步风险高，容易产生冲突副本；无法细粒度合并记录、删除和附件状态；同步时机不可控。
- 适用判断：可作为手动备份 / 手动迁移方向，不建议作为 ClipEase 历史实时同步主方案。

候选 C：混合方案。

- 优点：CloudKit private DB 同步结构化元数据，较大附件未来用 CKAsset 或用户可选择的 iCloud Drive/本地缓存策略；可以分阶段打开文本 / 分组，再评估图片 / 富文本。
- 缺点：两套存储的一致性、引用生命周期、失败恢复和隐私文案更复杂；用户容易误解“文件卡片路径已同步”等同于“原文件已同步”。
- 适用判断：中长期较稳妥，但第一批正式能力仍建议只考虑 CloudKit private DB + 文本 / 元数据，不上传原文件。

### 11.4 冲突策略候选

last-write-wins：

- 优点：实现最简单，适合低价值偏好字段和局部状态，例如非敏感设置、某些置顶布尔值。
- 缺点：会静默覆盖历史编辑、分组重命名、置顶顺序和删除；必须依赖可靠 `updated_at` / server time / device id，否则不可审计。
- 判断：可作为 spike 的最小冲突策略，但不应直接用于删除和附件。

field-level merge：

- 优点：可以分别合并 `plain_text`、`is_pinned`、`group_id`、分组名称 / 颜色 / 图标等字段，减少误覆盖。
- 缺点：需要 per-field modified time 或 operation metadata；文本 / 富文本编辑、分组删除和排序仍会出现难解释冲突。
- 判断：适合未来正式同步的主要候选，但必须先补数据字典和字段级冲突规则。

append-only event log：

- 优点：可审计、可回放，适合删除、移动分组、置顶排序等操作语义；对多设备离线更可解释。
- 缺点：实现和存储成本最高，需要 compaction、幂等、事件版本、隐私清理和错误恢复策略。
- 判断：适合作为后续高级 spike，不建议作为第一批 runtime。

删除 tombstone 风险：

- 只用 `is_deleted` 不足以同步删除；必须补 `deleted_at`、删除来源设备、保留期限、恢复策略和远端清理策略。
- tombstone 过早清理会导致旧设备重新上传已删除记录；永不清理会增加隐私和存储负担。
- 分组删除当前可连带删除组内内容，未来跨设备同步前必须拆清“删除分组”与“删除内容”的操作语义。
- Stage 10 不得把现有本机删除扩展为跨设备删除。

### 11.5 附件同步策略

图片：

- 当前通过 `item_assets` 引用 `Images` 附件，备份包可选择包含。
- 未来可评估 CKAsset 上传图片原件或缩略图，但首批同步建议只同步图片记录元数据 / 摘要，不默认上传图片二进制。

富文本：

- 当前通过 `item_assets` 引用 `RichTexts` 文件，主表保存纯文本摘要。
- 未来需区分纯文本摘要同步、RTF 附件同步和富文本编辑冲突；首批不做 RTF 附件上传下载。

App icon：

- 当前 `source_icon_file_name` 指向本地 `AppIcons` 缓存，图标可由 bundle id / 系统信息重建。
- 首批不同步 App icon 文件；未来若同步，也应作为可丢弃缓存，而不是历史记录关键数据。

文件卡片：

- 当前 `clipboard_item_files` 只保存原文件路径和元数据，不保存 security-scoped bookmark，不复制原文件。
- 第一批同步不得上传文件卡片指向的原文件，不复制原文件到附件目录，不把原文件二进制放入 SQLite、CloudKit 或 iCloud Drive。
- 可同步的最多是“原设备路径记录”和文件摘要；在其他设备上必须显示为不可访问 / 原设备路径，不得暗示文件已随历史同步。
- 未来若考虑原文件副本，必须另开隐私、配额、授权、加密、清理和用户确认任务。

### 11.6 隐私 / 加密和用户信任边界

- 剪贴板历史默认视为高敏感数据；可能包含密码、验证码、个人文件路径、图片、合同、代码、聊天内容和内部链接。
- CloudKit private database 表示数据存放在用户 iCloud 私有数据库并按 Apple ID 隔离，但不等同于 App 自己实现的端到端加密承诺。
- 若产品要求“只有用户设备能解密”，需要额外设计客户端加密、密钥生成 / 存储 / 恢复、多设备密钥同步、换机恢复和忘记密钥处理。
- 敏感内容遮罩是本机展示层能力，不应被误认为上传前加密；未来同步前必须确认敏感遮罩是否影响上传、搜索索引和远端预览。
- 用户信任边界：任何把剪贴板历史上传到 iCloud 的功能都必须显式 opt-in，说明同步范围、附件范围、删除语义、加密边界和关闭同步后的数据处理。

### 11.7 Stage 10 推荐产物和后续 spike 拆分

Stage 10 推荐只产出：

- 风险矩阵：隐私、CloudKit 配额 / 失败、冲突、删除 tombstone、附件、文件路径跨设备、迁移、用户误解。
- Schema gap 清单：device、sync state、record version、tombstone、field modified time、asset hash / remote id、settings sync scope。
- 同步数据字典：哪些字段可同步、不可同步、本机派生、可重建、敏感、需要加密、需要用户确认；当前产物记录在 `docs/V2_S10_SYNC_DATA_DICTIONARY.md`。
- 用户确认问题：是否接受只同步文本 / 元数据、是否要求端到端加密、是否允许删除同步、附件是否默认排除、文件路径跨设备如何展示、哪些设置可同步。
- 后续 spike 拆分：CloudKit zone / record mapping spike、schema migration spike、conflict fixture spike、tombstone lifecycle spike、attachment CKAsset spike、privacy copy / consent spike。

架构建议：

- PASS 进入 Stage 10 预研文档和 spike 设计。
- HOLD 任何 CloudKit runtime、schema 迁移、同步 UI、附件上传下载、端到端加密和跨设备删除实现。

### 11.8 Stage 10 iCloud 同步风险矩阵

任务卡：`V2-S10-ICLOUD-RISK-MATRIX-001`

风险矩阵文档：`docs/V2_S10_ICLOUD_RISK_MATRIX.md`

结论：

- PASS 产出 Stage 10 iCloud 同步风险矩阵。
- HOLD 任何正式同步、CloudKit runtime、entitlement、record schema、SQLite schema 迁移、同步 UI、附件上传下载、跨设备删除传播、冲突合并 runtime 和端到端加密 runtime。

用户已确认的风险边界：

- Stage 10 只做预研。
- CloudKit private database 是未来正式同步首选候选。
- E2EE 是正式同步前置门槛。
- 附件 / 图片 / 富文本附件同步暂缓。
- 删除同步暂缓。
- 文件卡片只同步路径历史，不上传原文件。

阻塞正式同步的核心风险：

- 隐私 / 敏感内容 / 用户信任：剪贴板历史默认高敏感，同步必须默认关闭，正式同步前必须有 E2EE 方案和清晰 opt-in 文案。
- iCloud 可用性 / 账号 / 配额 / 离线：必须设计账号状态机、离线队列、错误分类、幂等重试和断点恢复。
- CloudKit schema / record 演进：必须先完成同步数据字典、版本化 record、兼容迁移和回滚策略。
- 冲突与时钟偏差：last-write-wins 不可直接用于删除、附件、历史编辑和分组语义；需要 server version / change tag / 字段级策略。
- 删除 tombstone：删除同步继续暂缓；正式前必须设计 deleted_at、删除来源设备、保留期限、远端清理和旧设备复活防护。
- 附件 / 图片 / 富文本 / 文件路径历史：附件暂缓；文件卡片只同步原设备路径历史，跨设备不得暗示原文件已同步。
- 备份恢复与同步状态交叉、关闭同步 / 数据残留、法务 / 用户告知 / 默认关闭均为正式同步阻塞项。

条件阻塞风险：

- 多设备重复记录 / 去重：需要 origin id、content hash、device id 和幂等上传策略。
- 性能 / 大量历史：需要批处理、分页、速率限制、增量游标和性能预算。

### 11.9 Stage 10 iCloud 同步 Schema Gap 清单

任务卡：`V2-S10-ICLOUD-SCHEMA-GAP-001`

Schema gap 文档：`docs/V2_S10_SCHEMA_GAP.md`

结论：

- PASS 产出未来同步 schema gap 清单。
- HOLD 任何新增表 / 字段 / schema version / migration、CloudKit runtime、entitlement、同步 UI、附件上传下载、跨设备删除传播、冲突合并 runtime 和端到端加密 runtime。

当前已具备的同步基础：

- 稳定 UUID：主记录、附件、文件引用、分组和分组关系均已有 UUID。
- 时间字段：已有 `created_at` / `updated_at` 预留，以及置顶、分组关系、附件和文件引用相关时间。
- 分组和置顶：已有 `groupID` / `group_items`、`isPinned` / `pinnedAt`。
- 来源 App：已有 `source_app_name`、`source_bundle_id`、图标名称和本地图标文件引用。
- 附件 / 文件引用：已有 `item_assets`、`clipboard_item_files`、图片 / 富文本附件路径和文件卡片路径元数据。
- 删除预留：SQLite 有 `is_deleted`，但当前不是完整 tombstone。

正式同步前必须补齐或明确暂缓的 schema gap：

- soft delete / tombstone、`deletedAt`、删除来源设备、保留期限和远端清理策略。
- device identity：`deviceID`、`originDeviceID`、`modifiedByDeviceID`、`deletedByDeviceID` 和设备显示名。
- sync version / vector clock、record change tag / server version、remote record id / zone id。
- sync state / dirty flag、zone change token / sync cursor、断点恢复状态。
- field-level modified metadata 和 conflict status。
- attachment manifest、attachment checksum、remote asset id、upload / cache state。
- encryption metadata：加密版本、key id、nonce / salt、算法版本和密文校验。
- settings sync scope：哪些设置可同步、哪些保持本机私有。
- file path availability per device：文件卡片原设备路径、当前设备路径状态和最后检查信息。

文件卡片路径历史结论：

- 文件卡片未来最多同步路径历史和摘要，不上传原文件。
- 其他设备默认应显示“原设备路径 / 本机不可访问”语义，除非本机重新检查后确认路径可访问。
- 相同绝对路径不等于同一文件；未设计 checksum / file id / 用户确认策略前，不得自动视为可打开。
- 文件路径可能暴露用户名、项目名、客户名或内部目录结构；同步数据字典必须标为敏感字段，并纳入 E2EE 范围。

### 11.10 Stage 10 iCloud 同步数据字典

任务卡：`V2-S10-ICLOUD-SYNC-DATA-DICTIONARY-001`

数据字典文档：`docs/V2_S10_SYNC_DATA_DICTIONARY.md`

结论：

- PASS 产出未来同步数据字典和用户语义说明。
- HOLD 任何业务代码、SQLite schema / migration、CloudKit / iCloud runtime、entitlement、同步 UI、附件上传下载、跨设备删除传播、冲突合并 runtime 和端到端加密 runtime。

首轮正式同步候选：

- 历史条目：text / link / color 可作为首轮核心候选；image / richText 第一轮只评估记录元数据 / 摘要，附件暂缓；file 只同步路径历史和摘要。
- 分组：可作为首轮结构化数据候选，但必须处理重名、重命名、排序和删除语义。
- 置顶状态：可作为首轮轻量状态候选，但置顶顺序需要独立版本 / 冲突策略。
- 保存期限 / 少量低风险设置：仅限不会暴露隐私规则、本机状态或敏感内容的设置。

明确不进入首轮正式同步：

- 图片附件和富文本附件暂缓；不得上传图片二进制或 RTF 文件。
- 原文件副本不上传，不复制到 CloudKit，不复制到 iCloud Drive，不写入 SQLite。
- 忽略 App / 敏感遮罩配置默认不作为首轮同步，必须用户单独确认。
- App icon、搜索派生数据、缩略图、运行缓存和备份包状态不作为同步数据；需要时每台设备本地重建或独立处理。

文件卡片用户语义：

- 文件卡片只同步原设备路径历史、文件名、类型、大小、修改时间和捕获顺序等摘要。
- 跨设备路径不可用时只显示不可用 / 原设备路径状态，不暗示文件已随历史同步。
- 路径可能暴露用户名、项目名、客户名或内部目录结构，属于敏感字段，正式同步前必须纳入 E2EE 和用户告知。

## 12. 风险

- SQLite-only 数据读写、备份导入和附件索引必须非常谨慎。
- 大量历史查询不能阻塞主线程。
- 分组、保存期限和删除语义会影响清理逻辑，必须避免误删附件。
- 数据库结构一旦发布，后续迁移成本变高。
- 富文本卡片渲染和提示层动画不能影响主窗口弹出关闭流畅度。
- 旧迁移决策已被 SQLite-only 新基线覆盖；不得恢复 JSON 迁移运行时路径。

## 13. 待确认技术问题

- 分组关系是否第一阶段就使用关系表。
- 是否恢复任何批量删除、批量移动或批量导出能力；如恢复，必须先做独立安全方案。
- 默认浏览器名称获取方式需要兼容 Chrome、Edge、Safari 和其他浏览器。
- 多文件卡片文件列表的排序规则。
- 多文件卡片预览列表里是否显示每个文件大小。
- 文件卡片“打开文件”失败时的提示文案。
- 文件卡片系统分享失败时的回退行为。
- 文件卡片拼音搜索是否只支持文件名，还是文件路径也支持。
