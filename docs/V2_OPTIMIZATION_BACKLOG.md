# 第二版优化 Backlog

本文用于归档审查和验收中发现的非阻塞优化项。未来可以同步到 GitHub Issues，但本文是统一归档来源。

当前状态：存在发布前必做、但不阻塞当前阶段性放行的人工 UI 验收项。

主控规则：任何阶段推进、bug 修复、返工、测试计划检查、审查或验收中发现的非阻塞项，必须写入本文；不得只保留在会话上下文或 Agent 口头结论中。

## 模板

```text
优化任务 ID：
来源任务卡：
来源 Agent：
风险等级：
问题描述：
影响范围：
建议处理阶段：
是否阻塞当前阶段：
验收建议：
```

## Backlog 条目

```text
优化任务 ID：V2-OPT-OFFICE-PREVIEW-FORMAT-SELECTION-001
来源任务卡：用户反馈 / 2026-05-21 Office 预览收口
来源 Agent：Codex 主控 Agent
风险等级：中 / 高
问题描述：用户期望 Office / 表格类文件在轻贴统一预览窗口内同时保留原始格式，并支持像 Finder 空格预览一样的内容选择、复制和右键操作。当前公开嵌入式 `QLPreviewView` 能保留格式，但无法稳定强制提供 Finder Quick Look 面板级别的内容选择能力；此前尝试私有 Quick Look 激活接口已导致崩溃。
影响范围：文件预览、Office / 表格 / CSV / RTF / iWork 文件、预览窗口交互、复制体验、崩溃稳定性。
当前结论：当前版本保留格式优先，Office / 表格类走嵌入式 Quick Look；内容选择 / 复制能力按系统实际支持 best-effort，不再使用私有接口。
建议处理阶段：第三版后续文档预览专项 / 独立技术 spike
是否阻塞当前阶段：否
是否阻塞当前稳定性验收：否；但需用户人工确认当前取舍可接受
验收建议：
- 后续若必须同时满足“保留格式 + 统一预览窗口 + 内容稳定可选复制”，需评估 HTML 转换、PDF 转换、WebView 渲染或第三方文档渲染方案。
- 方案评估必须覆盖 `doc/docx/xls/xlsx/csv/ppt/pptx/rtf`、大文件性能、格式保真度、复制语义、离线可用性、外部依赖和崩溃回退。
- 不得再调用 Quick Look 私有激活接口。
```

```text
优化任务 ID：V2-OPT-UI-GROUP-APPEARANCE-POPOVER-MANUAL-ACCEPTANCE-001
来源任务卡：V2-BUGFIX-GROUP-APPEARANCE-POPOVER-001
来源 Agent：验收 Agent Jason / Codex 主控 Agent
风险等级：低
问题描述：分组外观 popover 的关键 UI 行为尚未完成人工实机验收；自动门禁已通过，但最终发布 / 完整验收前必须确认实际交互表现。
影响范围：主窗口分组右键菜单“颜色与图标”popover；全部剪切板按钮选中 / 未选中视觉；扩展颜色和图标选择器。
建议处理阶段：最终发布前 / 完整验收前
是否阻塞当前阶段：否
是否阻塞最终发布：是
验收建议：
- 实际右键打开“颜色与图标”，输入不同搜索词确认 popover 屏幕位置不变。
- 确认“全部剪切板”选中 / 未选中视觉。
- 确认扩展颜色 / 图标滚动、点击、搜索、显示正常。
```

```text
优化任务 ID：V2-OPT-UI-SEARCH-AUTH-ESC-MANUAL-ACCEPTANCE-001
来源任务卡：V2-BUGFIX-SEARCH-AUTH-ESC-001 / REWORK
来源 Agent：验收 Agent Lovelace / Codex 主控 Agent
风险等级：低
问题描述：搜索 / 授权 / ESC bugfix 的关键 UI 行为尚未完成人工实机验收；自动门禁和静态验证已通过，但最终发布前必须确认实际交互表现。
影响范围：HistoryWindow 搜索展开 / 收起、分组导航点击、授权提示和状态刷新、ESC 端到端关闭顺序。
建议处理阶段：最终发布前 / 完整验收前
是否阻塞当前阶段：否
是否阻塞最终发布：是
验收建议：
- 隐藏 / 重开主窗口时确认空搜索会关闭。
- 搜索展开时左右键点击全部剪切板 / 置顶 / 收藏 / 用户分组，确认会关闭 / 清空搜索且原点击行为正常。
- 确认搜索框全区域可点击，且 x/y 按钮位置在搜索框左侧并可正常操作。
- 分别在未授权 / 已授权状态下确认提示闪烁和授权状态实时刷新表现正确。
- 端到端确认 ESC 顺序：先关闭所有弹窗层，再清空搜索内容，再关闭搜索框，再关闭主窗口。
```

```text
优化任务 ID：V2-OPT-SEARCH-SQLITE-LIKE-FTS-INDEXED-PERF-001
来源任务卡：V2-BUGFIX-SEARCH-GROUP-PERF-001 / V2-BUGFIX-SEARCH-GROUP-PERF-001-REWORK
来源 Agent：Architecture Gatekeeper / Codex 主控 Agent
风险等级：中
问题描述：当前搜索分组与输入性能 bugfix 先限定在 UI / View 层处理取消传播和快速输入堆积问题，不把搜索下沉到 Repository / SQLite。大历史量搜索仍需要评估 SQLite LIKE、FTS 或索引化搜索方案，以降低全量内存扫描对输入体验的影响。
影响范围：HistoryWindow 搜索输入体验、大历史量剪切板搜索性能、Repository 查询 API、SQLite schema / 索引 / 迁移策略。
路由澄清：本任务不是正式阶段 7 主线。正式阶段 7 主线仍按 `docs/V2_DEVELOPMENT_PLAN.md` 定义推进编辑、快捷键和批量管理；本任务仅作为可与阶段 7 并行预研的搜索性能专项。
架构结论：V2-ARCH-STAGE6-SEARCH-INDEXED-PERF-001 结论为阶段 6 不阻塞；SQLite LIKE / FTS / 索引化搜索不建议作为阶段 6 或阶段 7 主线必须实施。实施前需独立评审 schema version、FTS 表、迁移、备份恢复、发布流程、Repository 查询 API 和回滚策略等数据红线。
建议处理阶段：第二版阶段 7 并行预研 / 后续搜索性能专项
当前状态：第二阶段已落地；`2.2.0(260523.0302)` 先采用无 schema 风险的搜索签名轻量化，`2.3.0(260523.0333)` 补充 1,000 / 10,000 条混合历史搜索基准。当前基准未触发 SQLite LIKE / FTS / schema 改造门槛，SQLite LIKE / FTS 仍保留为后续独立 schema 方案。
是否阻塞当前阶段：否
是否阻塞阶段 6：否
是否阻塞阶段 7 主线：否
是否阻塞最终发布：待产品 / 架构评估
实施门禁：独立门禁和红线确认通过前，不修改 schema / Repository / migration，不将搜索性能专项并入阶段 7 主线验收。
可接受阈值：
- 1,000 条历史记录搜索无明显卡顿。
- 10,000 条历史记录允许轻微延迟，但中文 IME 不可卡死。
- 搜索耗时持续超过 150-250ms，或搜索任务堆积时触发本优化专项。
验收建议：
- 由产品和架构确认搜索语义是否允许 LIKE / FTS / token 化差异。
- 评估 Repository 查询 API、SQLite 索引或 FTS schema、迁移和回滚风险。
- 第一阶段验收：搜索结果语义不变；快速输入时请求签名不再比较全部卡片的长 `normalizedSearchText`，改用每条卡片预生成的 `searchFingerprint`。
- 第二阶段验收：新增 `scripts/benchmark_history_search_performance.py`，固定验证 1,000 / 10,000 条混合历史样本、中文查询、类型 / 来源过滤、分组排序和 10k source signature 构造；当前结果均低于阈值。
- 后续如真实用户数据或自动基准持续超过 150-250ms，再进入 SQLite LIKE / FTS / token 化语义评审。
- 明确搜索性能专项的性能指标、迁移门禁和回滚策略，并与阶段 7 主线测试报告分开归档。
```

```text
优化任务 ID：V2-OPT-HISTORY-PREVIEW-REBUILD-GENERATION-GUARD-001
来源任务卡：V2-REVIEW-SEARCH-GROUP-PERF-001-REWORK
来源 Agent：Review Agent / Codex 主控 Agent
风险等级：P2 / 中低
当前状态：已由 V2-BUGFIX-PREVIEW-REBUILD-STALE-GUARD-001 完成并归档；Test / Review / Acceptance 均 PASS。
问题描述：HistoryWindowView.swift 的 preview rebuild 后台任务已补充取消传播，但在极窄时序下仍可能在 MainActor.run 等待窗口写入旧 allPreviewItems。后续已通过 V2-BUGFIX-PREVIEW-REBUILD-STALE-GUARD-001 为 preview rebuild 增加 generation / stale guard，和 search result 写回的 generation guard 保持一致。
影响范围：HistoryWindow preview rebuild、allPreviewItems 写回、快速搜索 / 分组切换时的预览快照一致性。
建议处理阶段：已在阶段 6 后续搜索 / 预览一致性收口中处理；Acceptance Agent `V2-ACCEPT-PREVIEW-REBUILD-STALE-GUARD-001` 已 PASS，已归档关闭。
是否阻塞当前阶段：否
是否阻塞当前 bugfix：否
验收建议：
- 确认 preview rebuild 调度和 MainActor 写回 generation / stale guard 已保持。
- 使用快速搜索输入、快速清空搜索、快速切换分组的场景验证旧 preview 快照不会覆盖新状态。
- 确认当前 search result 写回 generation guard 行为不回退。
```

```text
优化任务 ID：V2-OPT-STAGE7-RICH-TEXT-ROUNDTRIP-EDIT-001
来源任务卡：V2-DOCS-STAGE7-FIRST-BATCH-CONFIRM-DISPATCH-001
来源 Agent：用户确认 / Codex 主控 Agent
风险等级：中
用户规则纠正：用户已明确要求富文本应允许再次编辑，尤其“新建文本”产生的内容也应允许再次编辑；本任务不应再作为普通后续增强处理。
升级状态：实现完成，进入 Test / Review 门禁；Product Rules Agent `V2-PRODUCT-S7-RICH-TEXT-EDIT-MUST-001` 已确认富文本编辑应提升为阶段 7 编辑闭环必需项，Architecture Gatekeeper `V2-ARCH-S7-RICH-TEXT-EDIT-ROUNDTRIP-001` 已确认最小安全方案。
开发 / Bugfix 调度：`V2-S7-RICH-TEXT-EDIT-ROUNDTRIP-001`
实现状态：开发 Agent `V2-S7-RICH-TEXT-EDIT-ROUNDTRIP-001` 已完成；主控已调度 Test Agent `V2-TEST-S7-RICH-TEXT-EDIT-ROUNDTRIP-001` 和 Review Agent `V2-REVIEW-S7-RICH-TEXT-EDIT-ROUNDTRIP-001`。
问题描述：阶段 7 必须补齐富文本再次编辑闭环；富文本编辑不再作为后续普通增强。最小安全方案已落地：读取原 RTF 到 `RichTextEditorController`，保存时原子覆盖原 RTF，保持 `richTextFileName` 不变，更新纯文本摘要和 recentHashes，不改 schema / migration。
影响范围：富文本剪切板记录、编辑入口显示策略、富文本附件 / attributed content 回写、保存后的预览一致性。
建议处理阶段：当前第二版阶段 7 必修缺口；实现完成，进入 Test / Review 门禁
是否阻塞当前阶段：是；阶段 7 编辑闭环必修缺口
是否阻塞阶段 7 第一批：已从后续普通增强提升为阶段 7 必修缺口，不再按普通后续增强口径处理
修改文件：`RichTextEditorController.swift`、`HistoryWindowView.swift`、`ClipboardHistoryStore.swift`、`ClipboardHistoryPersistence.swift`、`AppMenuController.swift`
禁止范围：SQLite schema / migration / Repository 查询下沉 / LIKE / FTS；backup / import-export 语义；批量删除 / 撤销 / 导出；版本 / 发布 / 打包脚本。
后续门禁：Test / Review / Acceptance 通过后，再 build-run 供用户人工测试。
验收建议：
- 明确富文本编辑是否保留样式、链接、附件引用和纯文本 fallback。
- 覆盖富文本编辑保存后预览、复制回剪切板、搜索命中和历史记录状态保留。
- 与阶段 7 第一批文本 / 链接 / 颜色编辑验收分开归档。
```

```text
优化任务 ID：V2-OPT-STAGE7-BULK-MANAGEMENT-EXPORT-001
来源任务卡：V2-DOCS-STAGE7-FIRST-BATCH-CONFIRM-DISPATCH-001
来源 Agent：用户确认 / Codex 主控 Agent
风险等级：中
问题描述：阶段 7 第一批不做批量导出；批量导出放入后续批量管理增强专项，需单独确认导出格式、附件包含策略、权限 / 保存面板交互、进度反馈和失败恢复。
影响范围：批量选择、批量操作菜单、导出格式、图片 / 富文本附件导出、文件写入权限和用户确认流程。
建议处理阶段：第二版阶段 7 后续“批量管理增强”
是否阻塞当前阶段：否
是否阻塞阶段 7 第一批：否
验收建议：
- 明确批量导出的格式、命名、重复文件处理和附件包含策略。
- 覆盖多选导出、取消导出、部分失败提示、权限拒绝和空选择状态。
- 不与阶段 7 第一批单条编辑闭环混合验收。
```

```text
优化任务 ID：V2-OPT-STAGE7-BULK-UNDO-PER-ITEM-ANIMATION-001
来源任务卡：V2-DOCS-STAGE7-FIRST-BATCH-CONFIRM-DISPATCH-001
来源 Agent：用户确认 / Codex 主控 Agent
风险等级：低 / 中
问题描述：阶段 7 第一批不做逐条撤销动画；批量删除及其撤销表现不进入第一批。逐条撤销动画放入后续体验打磨专项，需在批量操作语义稳定后再评估动画节奏、可访问性和性能影响。
影响范围：批量删除、撤销提示、列表动画、选择状态恢复、可访问性 reduce motion。
建议处理阶段：第二版阶段 7 后续“批量撤销体验打磨”
是否阻塞当前阶段：否
是否阻塞阶段 7 第一批：否
验收建议：
- 先确认批量删除 / 撤销的产品语义，再设计逐条动画。
- 覆盖大量条目撤销、快速连续撤销、动画中切换分组 / 搜索和 reduce motion。
- 与阶段 7 第一批文本 / 链接 / 颜色编辑验收分开归档。
```

```text
优化任务 ID：V2-OPT-STAGE7-COLOR-EDITOR-PICKER-CONTRAST-001
来源任务卡：V2-DOCS-STAGE7-COLOR-EDITOR-ENHANCEMENT-PLAN-001
来源 Agent：用户反馈 / Codex 主控 Agent
风险等级：中
问题描述：阶段 7 第一批颜色编辑闭环仅保证颜色值可编辑和 HEX 规范化，尚未完整覆盖取色器、编辑中背景实时预览、目标颜色同步修改和自动文字对比色体验。后续需增强颜色编辑：增加取色器；编辑时背景实时显示 / 修改目标颜色；文字颜色根据背景亮度自动切换黑 / 白以保证可读性；保存后颜色卡片预览同步。
影响范围：颜色剪切板记录编辑入口、颜色编辑 UI、颜色背景预览、文字可读性、保存后颜色卡片预览刷新。
建议处理阶段：第二版阶段 7 后续“颜色编辑增强”
是否阻塞当前阶段：否
是否阻塞当前编辑输入框修复：否
是否阻塞阶段 7 第一批：否
不涉及范围：不涉及 schema / migration / backup / release。
实施门禁：
- Product 确认颜色编辑入口、取色器形态、实时预览语义、取消行为和保存语义。
- UX 确认浅色 / 深色 / 边界灰度下背景预览和文字黑 / 白自动切换表现。
- Implementation 确认仅限现有颜色编辑 UI 和预览同步范围，不引入数据结构或迁移变更。
- Test 覆盖浅色、深色、边界灰度、无效 HEX、系统取色器取消、保存后颜色卡片预览同步。
- Review 确认不破坏文本 / 链接编辑复用输入框行为，不扩大当前 bugfix 验收范围。
- Acceptance 作为阶段 7 后续增强独立放行，不与当前“复用新建文本输入框”bugfix 验收混合。
验收建议：
- 选择浅色时背景实时变浅，文字自动切换为黑色且可读。
- 选择深色时背景实时变深，文字自动切换为白色且可读。
- 边界灰度颜色使用明确阈值并保持文字可读。
- 输入无效 HEX 时保持现有校验 / 错误提示，不提交非法颜色。
- 打开系统取色器后取消，不应改变已保存颜色或造成预览状态错乱。
- 保存后颜色卡片预览与最终 HEX 值同步。
```

```text
优化任务 ID：V2-OPT-DATA-REPOSITORY-SCOPE-ARCHIVE-RISK-REVIEW-001
来源任务卡：V2-ARCH-S7-RICH-TEXT-EDIT-WORKTREE-SCOPE-RULING-001
来源 Agent：Architecture Gatekeeper / Codex 主控 Agent
风险等级：P2 / 中
问题描述：当前工作区存在 SQLite / Repository / backup-import-export / version bump 等数据层和发布边界相关变更，需要独立归档或风险复核，明确其归属任务卡、验收记录和合并边界，避免与阶段 7 富文本再次编辑 JSON Save 修复混合放行。
影响范围：SQLite 存储、Repository 抽象、backup / import-export 语义、版本号 / 发布元数据、数据迁移和回滚边界。
建议处理阶段：阶段 7 后续数据层范围收口 / 合并前风险复核
是否阻塞当前阶段：否
是否阻塞阶段 7 富文本再次编辑放行：否
是否阻塞富文本 JSON Save 修复验收：否
实施门禁：
- 明确 SQLite / Repository / backup-import-export / version bump 变更分别归属的任务卡或独立专项。
- 补齐或引用对应 Test / Review / Acceptance 验收记录。
- 明确哪些文件和行为属于富文本 JSON Save 修复，哪些属于数据层 / 发布边界变更。
- 合并前由主控确认未将未验收的数据层范围混入富文本再次编辑放行结论。
验收建议：
- 对照 git diff 列出 SQLite / Repository / backup-import-export / version bump 涉及文件。
- 为每个范围项补充归属、风险等级、验证命令或人工验收记录。
- 确认 Stage 7 富文本再次编辑 JSON Save 修复可独立验收和回归，不依赖上述数据层范围项。
```

```text
优化任务 ID：V2-OPT-STAGE7-BATCH-DELETE-UNDO-SAFETY-DESIGN-001
来源任务卡：V2-DOC-S7-NEXT-BATCH-DISPATCH-001 / V2-ARCH-S7-NEXT-BATCH-SCOPE-001
来源 Agent：Architecture Gatekeeper / Codex 主控 Agent
风险等级：高；涉及删除语义、附件清理和撤销恢复
问题描述：批量删除 + 一次性撤销需要独立安全设计。当前阶段 7 下一批批量管理 MVP 不包含危险删除实现，仅允许管理模式多选、批量收藏和批量移动等低风险操作；批量删除及其撤销恢复需在架构方案明确附件清理、数据恢复窗口、失败回滚、UI 提示和边界测试后再推进。
影响范围：批量管理操作、删除确认、撤销提示、附件生命周期、SQLite / Repository 删除路径、历史记录恢复语义、错误恢复和用户误操作保护。
建议处理阶段：第二版阶段 7 后续“批量删除安全专项”；需先完成 `V2-ARCH-S7-BATCH-DELETE-UNDO-SAFETY-001`
是否阻塞当前阶段：否
是否阻塞当前批量管理 MVP：否；当前 MVP 明确不包含危险删除实现
是否阻塞阶段 7 后续批量删除：是；架构方案和安全门禁通过前不得开发批量删除
实施门禁：
- Architecture Gatekeeper 明确批量删除是否软删、撤销窗口、附件清理延迟策略和失败回滚策略。
- Product Rules 确认删除确认文案、撤销入口、一次性撤销语义和超时后的不可恢复提示。
- Implementation 明确不修改 schema / migration / Repository / SQLite 查询 / 导入导出 / 打包脚本，除非另开红线确认任务。
- Test 覆盖空选择、跨分组选择、收藏 / 置顶状态、附件记录、撤销成功、撤销失败、超时后清理和应用重启边界。
- Review / Acceptance 将批量删除安全专项与当前批量管理 MVP 分开验收。
验收建议：
- 先验收当前批量管理 MVP 的多选、批量收藏和批量移动，不出现删除入口或危险删除行为。
- 架构方案通过后，再用独立任务实现批量删除 + 一次性撤销，并验证附件不会被提前永久清理。
- 确认取消、失败、重启、快速连续操作等边界不会造成历史记录或附件不可恢复丢失。
```

```text
优化任务 ID：V2-BACKLOG-S9-PREVIEW-COPY-TOAST-UNIFIED-001
标题：Stage 9 预览窗口复制按钮统一 toast / fallback 状态
来源任务卡：V2-REVIEW-S9-FILE-PASTE-FALLBACK-FIRST-BATCH-001
来源 Agent：Review Agent / Docs Backlog Agent
风险等级：低 / 非阻塞体验一致性
当前状态：已完成；`2.1.0(260523.0213)` 已纳入预览复制统一 toast / fallback 状态。
问题描述：Review `V2-REVIEW-S9-FILE-PASTE-FALLBACK-FIRST-BATCH-001` PASS，但记录非阻塞观察：预览窗口 header 的复制按钮仍直接丢弃 `copyToPasteboard` 结果，未展示 fallback 或失败状态；不影响本批 HistoryWindowView 状态分派和 pasteboard fallback 行为。
影响范围：HistoryPreviewPopoverView / HistoryWindowController 复制按钮状态反馈，特别是文件引用 fallback 文本、失败原因展示。
建议处理阶段：Stage 9 收口 polish 或后续统一 toast 体验专项。
是否阻塞当前阶段：否
是否阻塞 `V2-S9-FILE-PASTE-FALLBACK-FIRST-BATCH-001` 放行：否
验收建议：
- 预览 header 复制按钮对普通复制、文件引用复制、文件路径 fallback、失败结果均给出一致短提示。
完成记录：
- `HistoryWindowController.showPreview` 的预览复制回调现在根据 `PasteboardCopyResult` 分别显示 `copyStatus`、`copyFallbackTextStatus` 或失败原因。
- 新增 `scripts/verify_preview_copy_feedback.py` 守卫普通复制、文件 fallback 和失败提示，不改变 pasteboard 写入语义。
```
