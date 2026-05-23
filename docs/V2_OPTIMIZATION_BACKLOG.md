# 第二版优化 Backlog

本文用于归档审查和验收中发现的非阻塞优化项。未来可以同步到 GitHub Issues，但本文是统一归档来源。

当前状态：发布前必做人工 UI 验收项已由用户确认通过；旧阻塞状态已收口，剩余条目均为后续专项或非阻塞优化。

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
当前状态：已通过用户人工确认；不再阻塞最终发布。
建议处理阶段：最终发布前 / 完整验收前
是否阻塞当前阶段：否
是否阻塞最终发布：否
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
当前状态：已通过用户人工确认；不再阻塞最终发布。
建议处理阶段：最终发布前 / 完整验收前
是否阻塞当前阶段：否
是否阻塞最终发布：否
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
是否阻塞最终发布：否；当前 1,000 / 10,000 条自动基准未触发 SQLite LIKE / FTS / schema 改造门槛，后续仅作为独立搜索性能专项保留。
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
升级状态：实现完成；Product Rules Agent `V2-PRODUCT-S7-RICH-TEXT-EDIT-MUST-001` 已确认富文本编辑应提升为阶段 7 编辑闭环必需项，Architecture Gatekeeper `V2-ARCH-S7-RICH-TEXT-EDIT-ROUNDTRIP-001` 已确认最小安全方案。后续 Test / Review / 架构范围裁定已 PASS，旧阻塞状态已收口。
开发 / Bugfix 调度：`V2-S7-RICH-TEXT-EDIT-ROUNDTRIP-001`
实现状态：已完成；后续 JSON Save HOLD 修复、Test / Review 重跑和架构范围裁定已 PASS。
问题描述：阶段 7 必须补齐富文本再次编辑闭环；富文本编辑不再作为后续普通增强。最小安全方案已落地：读取原 RTF 到 `RichTextEditorController`，保存时原子覆盖原 RTF，保持 `richTextFileName` 不变，更新纯文本摘要和 recentHashes，不改 schema / migration。
影响范围：富文本剪切板记录、编辑入口显示策略、富文本附件 / attributed content 回写、保存后的预览一致性。
建议处理阶段：已按第二版阶段 7 必修缺口完成并收口
是否阻塞当前阶段：否；实现、修复和范围裁定已完成
是否阻塞阶段 7 第一批：否；历史上曾从后续普通增强提升为阶段 7 必修缺口，当前已完成收口
修改文件：`RichTextEditorController.swift`、`HistoryWindowView.swift`、`ClipboardHistoryStore.swift`、`ClipboardHistoryPersistence.swift`、`AppMenuController.swift`
禁止范围：SQLite schema / migration / Repository 查询下沉 / LIKE / FTS；backup / import-export 语义；批量删除 / 撤销 / 导出；版本 / 发布 / 打包脚本。
后续门禁：已完成；后续只做回归守卫，不再作为当前阶段阻塞项。
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

```text
优化任务 ID：V2-OPT-HISTORY-110K-WINDOWED-RAIL-MEMORY-001
标题：11 万条历史数据窗口化渲染与内存释放专项
来源：用户反馈 / 性能日志 `PerformanceLogs/*.jsonl` / Codex 主控 Agent
风险等级：高；涉及历史窗口核心滚动、搜索、筛选、预览定位和缓存生命周期
当前状态：工作态已修正至 `2.3.16 (260523.1337)`，已确认解决 2.3.13 主窗口打开卡死回归，并将 11 万条主窗口数据构建从用户打开路径前移到 App 启动后预热；关闭主窗口后保留主列表数据，避免二次打开空白或重新慢加载。
问题描述：
- 11 万条数据下，搜索按钮、筛选按钮、筛选 chip、卡片点击和预览入口本身耗时很低，不是主要卡点。
- `search.filter` 有局部优化空间，部分筛选到 `369ms - 510ms`，但最大卡点是 SwiftUI 列表刷新。
- `history-open.preview-items-ready` 曾出现 `19.7s / 12.1s / 9.1s`。
- `history-open.filtered-items-ready` 曾出现 `6.1s / 4.3s / 4.2s` 等秒级耗时。
- 内存曾从约 `323MB` 上升到约 `1.78GB`，说明全量卡片渲染、全量预览缓存和全量资源预热带来明显内存压力。
影响范围：
- `HistoryWindowView` 横向卡片轨道渲染。
- 搜索 / 筛选结果应用后的 SwiftUI diff / layout。
- 卡片点击、右键、预览弹层定位、键盘跳转、最新剪贴板聚焦和程序化滚动。
- `previewItemCache`、图片 / 富文本 / 来源图标资源预热和整体内存占用。
已实施工作态方案：
- 历史卡片轨道改为窗口化渲染：SwiftUI 不再 `ForEach` 全量 11 万条，只渲染当前可见区域加前后缓冲。
- 保留完整横向内容宽度和原横向滚动体验，不新增滚动条。
- 滚动坐标、预览定位和程序跳转仍基于完整 `filteredItems` 索引计算。
- 后台资源预热从全量结果改为窗口附近条目。
- `previewItemCache` 不再先构建 11 万条再在主线程裁剪，改为后台构建时只保存可见区附近、选中项、预览项和跳转项；日志新增 `cacheStored`。
- App 启动后通过 `HistoryWindowController.preloadHistoryDataAfterLaunch()` 创建主窗口宿主但不显示，触发后台预热并记录 `history.preload.start`。
- 主窗口隐藏后不再释放 `allPreviewItems / filteredPreviewItems`，改为记录 `history.hidden.keepWarm` 并保留主列表数据；`previewItemCache` 仍只保留小缓存规模。
- 如果真实 `store.items` 非空但预览列表仍在构建，UI 显示“正在加载历史”，避免误判为暂无内容。
回归与修正记录：
- `2.3.13 (260523.1313)` 出现主窗口打开直接卡死：最新日志停在 `preview.rebuild.apply`，未进入 `history-open.preview-items-ready`。
- 卡死进程 PID `88682` 约 `100%` CPU，RSS 约 `913MB`。
- 系统采样 `/tmp/clipease-hang-sample-88682.txt` 指向 `HistoryWindowView.trimPreviewItemCacheAroundActiveItems()`，根因是主线程裁剪 11 万条 `@State previewItemCache` 字典，触发 Swift Dictionary copy / release / deinit。
- `2.3.14` 删除该主线程裁剪路径，改为后台构建时限制缓存规模；`2.3.15` 追加隐藏窗口释放大数组和缓存。
- `2.3.15` 暴露新的体验问题：第一次打开仍在用户路径上构建 11 万条数据；关闭后释放主列表导致同一窗口复用时后续打开无卡片。`2.3.16` 改为启动预热和隐藏保温。
验证记录：
- `swift build` 通过。
- `python3 scripts/verify_history_window_animation_performance.py` 通过。
- `python3 scripts/verify_history_search_performance_guards.py` 通过。
- `git diff --check` 通过。
- `./scripts/build-app.sh --bump patch --run` 通过，当前运行版本 `2.3.16 (260523.1337)`，PID `6012`。
- 最新验证日志 `/Users/wpc/Library/Application Support/ClipEase/PerformanceLogs/2026-05-23_13-28-48.jsonl` 已覆盖真实打开和关闭主窗口：
  - `preview.rebuild.background`：约 `1033ms`，`cacheStored=320`。
  - `preview.rebuild.apply`：约 `0.16ms`，`cacheStored=320`。
  - 已进入 `history-open.preview-items-ready count=110190` 与 `history-open.filtered-items-ready count=110190`。
  - 关闭后已记录 `history.hidden.releaseCaches` 和资源采样。
- `2.3.16` 最新验证日志 `/Users/wpc/Library/Application Support/ClipEase/PerformanceLogs/2026-05-23_13-38-19.jsonl` 已覆盖启动预热、打开、关闭、二次打开：
  - 启动后记录 `history.preload.start`。
  - 预热阶段 `preview.rebuild.background` 约 `1346ms`，`cacheStored=320`，`animated=false`。
  - 用户真实打开主窗口只记录 `history-open.start` 和 `history-open.panel-ordered`，没有再次触发全量 `preview.rebuild.background`。
  - 关闭后记录 `history.hidden.keepWarm`，`resultCount=110191`、`cacheStored=320`。
  - 二次打开同样没有全量重建，避免空白和慢加载。
待复测验收：
- 用户按同一套启动、搜索、筛选、点击、预览、关闭流程复测。
- 主窗口不应再卡死在 `preview.rebuild.apply` 后。
- 内存不应再因全量 `previewItemCache` 涨到 `1GB+`；关闭窗口后应出现 `history.hidden.keepWarm` 记录，并保持二次打开有卡片。
- 4K 屏幕约 14 张卡片可见时，不应出现空白卡片、错位、额外滚动条或动画效果退化。
后续待办：
- 如果启动后预热 CPU / 内存峰值仍不可接受，下一阶段应把 `allPreviewItems / filteredPreviewItems` 改为索引化或窗口化数据源，避免一次性构建 11 万条 `HistoryPreviewItem`。
- 如果 `search.filter` 仍在筛选组合下超过 300ms，再推进索引化过滤或 normalized 字段预计算。
- 如窗口化复测仍有卡顿，继续拆 SwiftUI layout、scroll offset update 和 preview frame follow 的主线程耗时。
后续方案分析：
- 最新日志 `/Users/wpc/Library/Application Support/ClipEase/PerformanceLogs/2026-05-23_13-41-05.jsonl` 显示，启动预热后用户打开主窗口已经不再触发全量构建；真实打开只记录 `panel-ordered` 约 `90ms`。
- 新增一条历史后仍触发 `preview.rebuild.background` 全量重建 `110192` 条，约 `1034ms`，内存峰值约 `718MB`。这说明剩余瓶颈从 SwiftUI 渲染转移到 `allPreviewItems / filteredPreviewItems` 的全量数据模型重建。
- 推荐第一步做增量 preview 数组维护：新增 / 更新 / 删除时只重建变化项，复用旧 `HistoryPreviewItem`，优先消除“新增一条触发 11 万条重建”。
- 推荐第二步做索引化 / 惰性 preview 数据源：长期只保存轻量 ID / index / search index，可见窗口再生成 `HistoryPreviewItem`，从根上降低启动预热 CPU 和常驻内存。
- 搜索索引下沉作为第三步：当前无查询搜索约 `30ms`，不是最大瓶颈；若真实查询 / 筛选继续超过 `300ms`，再做专门索引或 Repository 查询下沉。
增量构建第一阶段结果：
- `2.3.19 (260523.1353)` 已实现顶部新增 fast path：新增少量记录时只构建新增 `HistoryPreviewItem`，旧数组元素复用；功能、动画、搜索和筛选语义不变。
- 验证日志 `/Users/wpc/Library/Application Support/ClipEase/PerformanceLogs/2026-05-23_13-54-38.jsonl` 显示新增一条后 `preview.rebuild.background` 约 `138ms`，`cacheHits=110198`，`cacheMisses=1`，较此前约 `1034ms` 明显下降。
- 剩余问题是内存峰值仍约 `672MB - 712MB`，因为 `allPreviewItems / filteredPreviewItems` 仍是两份 11 万条完整 struct 数组，数组更新时会出现新旧数组并存。
增量构建第二阶段结果：
- 顶部少量新增时，后台不再拼出完整 11 万条 `previewItems` 数组，改为返回 `PreviewRebuildResult.prepend`，只携带新增 `HistoryPreviewItem` 和小规模 `nextCache`。
- 主线程仍使用原 `withTransaction` 和原动画参数，只在现有 `allPreviewItems` 头部插入新增项，保留功能和动画语义。
- 空搜索、无筛选、全部分组时，`filterItems` 直接返回原数组，避免 11 万条扫描和完整结果数组复制。
- 日志通过 `preview.rebuild.background` 的 `mode=incrementalPrepend/full` 区分增量和全量路径。
- `swift build`、`verify_history_window_animation_performance.py`、`verify_history_search_performance_guards.py`、`verify_maint8_history_runtime_scroll.py` 已通过。
- 真实运行 `2.3.20 (260523.1404)` 验证：
  - 启动预热全量 `preview.rebuild.background` 约 `1204ms`，空搜索 / 无筛选 `search.filter` 约 `0.053ms`。
  - 新增一条历史后 `preview.rebuild.background` 约 `42.4ms`，`mode=incrementalPrepend`，`cacheHits=110203`，`cacheMisses=1`。
  - 新增后的内存采样峰值约 `615MB`，低于第一阶段约 `672MB - 712MB`。
增量签名削峰：
- 新增 `previewSignatureUpdate(sourceItems:currentSourceSignature:)`，顶部新增 1-8 条时只构造新增条目签名，并通过 `HistoryPreviewSourceSignature.matches(item:)` 验证旧签名可复用。
- 非顶部新增、删除、排序、编辑和批量变化继续回退全量签名和全量重建，保证功能正确。
- `swift build`、三个性能 / 滚动守卫脚本已通过。
- 真实运行 `2.3.21 (260523.1408)` 验证：
  - 启动预热 `preview.rebuild.background` 约 `1168ms`，启动空搜索 / 无筛选 `search.filter` 约 `0.047ms`。
  - 新增一条历史后 `preview.rebuild.background` 约 `45.0ms`，`mode=incrementalPrepend`，`cacheHits=110204`，`cacheMisses=1`。
  - 新增一条历史后 `preview.rebuild.apply` 约 `12.3ms`，`search.filter` 约 `0.048ms`。
  - 新增后的资源采样峰值约 `568MB`，低于 `2.3.20` 的约 `615MB`，也低于第一阶段的约 `672MB - 712MB`。
下一阶段判断：
- 编译运行 App 后新增一条历史，确认 `preview.rebuild.background` 命中 `mode=incrementalPrepend`，并对比新增后的内存峰值是否低于第一阶段 `672MB - 712MB`。
- 如果内存峰值仍高，应进入索引化 / 惰性 preview 数据源专项，而不是继续调小动画或卡片 UI。
```

```text
优化任务 ID：V2-OPT-100K-HISTORY-STORE-INDEX-001
来源任务卡：用户性能专项审查 / 2026-05-23 10 万+ 历史记录不卡顿
来源 Agent：Codex
风险等级：中
问题描述：
- `ClipboardHistoryStore` 已有 `itemIndexByID`，但多个热路径仍使用 `items.firstIndex(where:)`、`groups.firstIndex(where:)`、`groups.contains(where:)` 和 `items.lazy.filter`。
- 分组悬停数量、分组删除确认、复制 / 粘贴后的 `markUsed`、OCR 状态回写、链接 metadata 回写、单条删除等操作在 10 万+ 数据下会落到主线程 O(n) 扫描。
- 单条删除和分组删除后会调用 `rebuildRecentHashes()`，导致删除路径额外全量重建去重哈希。
已实施工作态方案：
- `ClipboardHistoryStore` 新增 `groupIndexByID`、`itemCountByGroupID`。
- `item(with:)`、置顶、移动分组、移出分组、`markUsed`、编辑、OCR 回写、链接 metadata 回写改为通过索引查找。
- `group(with:)`、分组重命名、分组外观更新、富文本新增默认分组校验改为通过分组索引。
- `itemCount(inGroup:)` 改为读取缓存，不再每次扫描全量历史。
- 单条删除、分组删除、批量分组删除改为删除后维护索引，并对 `recentHashes / itemIDsByHash` 做删除项增量维护。
- 新增 `scripts/verify_store_index_performance_guards.py`，防止 Store 热路径回退到全量扫描。
影响范围：
- 新增、删除、置顶、标记使用、分组数量显示、移动分组、链接 metadata、OCR 状态回写、去重哈希。
行为影响：
- 不改变现有功能语义；只改变查找和计数的数据结构。
- 单条删除仍立即持久化；批量分组删除仍保持现有同步持久化策略，本轮未改变事务 / UI 乐观更新语义。
已知剩余问题：
- `ClipboardHistoryStore.init` 仍同步 `persistence.loadSnapshot()`，启动会加载全量 10 万+ metadata 和关联资产 / OCR / 文件引用。
- `SQLiteClipboardStore.loadSnapshot()` 仍先查主表，再对每条记录 N+1 查询 assets、file references、OCR；需要下一阶段改为首屏分页 + 批量 JOIN / 字典组装。
- `replaceAllItems` 仍用于保存快照，新增 / 删除后持久化仍可能写全量表；需要下一阶段 Repository 增量 upsert / batch delete。
- `HistoryWindowView` 仍维护 `allPreviewItems / filteredPreviewItems` 两份完整数组；若内存峰值继续不可接受，应进入索引化 / 惰性 preview 数据源专项。
建议处理阶段：
- 第一阶段已完成 Store 热路径索引化。
- 第二阶段处理 Repository 增量写入、SQLite 批量加载和启动分页。
- 第三阶段处理搜索索引下沉或惰性 preview 数据源。
验收建议：
- 运行 `swift build`。
- 运行 `python3 scripts/verify_store_index_performance_guards.py`。
- 运行 `python3 scripts/verify_history_search_performance_guards.py`、`python3 scripts/verify_card_click_performance_guards.py`、`python3 scripts/verify_preview_window_performance_guards.py`。
- 使用 10 万+ 历史记录实测新增、单条删除、分组数量悬停、置顶、复制 / 粘贴触发 `markUsed`、OCR / 链接 metadata 回写。
- 查看 `PerformanceLogs/*.jsonl` 中 `preview.rebuild.background`、`preview.rebuild.apply`、`search.filter`、`preview.show`、`paste.item`、资源采样和主线程 latency。
是否阻塞当前阶段：否；作为 10 万+ 性能专项第一批低风险修复。
```

```text
优化任务 ID：V2-OPT-HISTORY-IDLE-CPU-PULSE-001
来源任务卡：用户性能专项继续优化 / 运行后 CPU 采样
来源 Agent：Codex
风险等级：中
问题描述：
- `2.3.26` 修复崩溃后，历史窗口打开观察时仍出现较长时间 `40% - 50%` CPU。
- `sample` 显示主要栈在主线程 SwiftUI / Accessibility 图更新和布局。
- 未授权状态下顶部“请授权”按钮使用 `.repeatForever` 脉冲动画，窗口常驻时持续触发 SwiftUI 刷新。
- 搜索过滤虽然在 detached task，但 `HistorySearchFilterResult` 的 ID Set 和 `id -> index` 构建仍在等待任务一侧执行，会放大 11 万条结果应用压力。
已实施方案：
- 移除 `authorizationPulse` 状态和“请授权”按钮无限动画，改为静态高可见度提示，保留点击授权行为。
- 将 `HistorySearchFilterResult(items:)` 构建移进 `Task.detached`，搜索结果 ID Set / `id -> index` 在后台构建，主线程只应用结果。
- `scripts/verify_history_visible_window_range_guards.py` 禁止 `.repeatForever(` 回归。
- `scripts/verify_history_search_performance_guards.py`、`scripts/verify_history_filtered_index_guards.py` 要求搜索结果索引在 detached task 内构建。
验证结果：
- `swift build` 通过。
- `python3 scripts/verify_history_visible_window_range_guards.py` 通过。
- `python3 scripts/verify_history_search_performance_guards.py` 通过。
- `python3 scripts/verify_sqlite_snapshot_bulk_load_guards.py` 通过。
- `python3 scripts/verify_history_filtered_index_guards.py` 通过。
- `python3 scripts/verify_store_index_performance_guards.py` 通过。
- `python3 scripts/verify_card_click_performance_guards.py` 通过。
- `python3 scripts/verify_preview_window_performance_guards.py` 通过。
- `python3 scripts/benchmark_history_search_performance.py` 通过。
- `./scripts/build-app.sh --bump patch --run` 通过，最终运行 `2.3.27 (260523.1641)`，PID `40447`。
- 运行观察：`ps -p 40447` 在稳定窗口从约 `4.3%` 降到 `0.0%` CPU；`sample 40447 3` physical footprint 约 `463.5MB`，peak 约 `475.3MB`；运行后未生成新的 `ClipEase-*.ips`。
行为影响：
- 不改变授权入口、搜索结果语义、列表行为、SQLite schema 或备份格式。
- “请授权”提示不再脉冲闪烁，改为静态按钮。
剩余问题：
- 外部 App 持续写剪贴板时仍会触发新增记录、增量 preview 和搜索同步。
- 启动全量 preview 构建仍约 `1.2s`，后续进入首屏分页 / 惰性 preview 数据源专项。
是否阻塞当前阶段：否；作为窗口空闲 CPU 收口修复。
```

```text
优化任务 ID：V2-OPT-100K-HISTORY-VISIBLE-WINDOW-RANGE-CRASH-001
来源任务卡：用户性能专项继续优化 / 软件崩溃自动结束
来源 Agent：Codex
风险等级：高
问题描述：
- 用户反馈 App 崩溃、进程自动结束。
- 崩溃报告 `/Users/wpc/Library/Logs/DiagnosticReports/ClipEase-2026-05-23-160737.ips` 显示 `EXC_BREAKPOINT / SIGTRAP`，Swift runtime failure：`Range requires lowerBound <= upperBound`。
- 崩溃栈落在 `HistoryWindowView.historyRailVisibleWindow.getter` 与 `schedulePreheatVisibleAssets()`。
- 10 万+ 列表曾滚动到很大的横向 offset；搜索 / 分组状态切换后结果缩小到 1 条时，旧 `cardRailVisibleRect` 仍被用来计算可见窗口，`start` 没有夹紧到 item count 内，形成非法 `Range` 并崩溃。
已实施方案：
- 新增 `clampedHistoryRailWindow(itemCount:visibleRect:bufferItemCount:)`，统一处理列表渲染窗口和预览缓存保留窗口。
- 空列表返回 `0..<0`；非空列表将 `rawStart` 夹紧到 `0...(itemCount - 1)`，保证 `Range` 可用于数组切片。
- 新增 `scripts/verify_history_visible_window_range_guards.py`，覆盖“超大旧偏移 + 1 条结果”的回归场景，并禁止恢复旧的未夹紧 range 计算。
- 运行 `2.3.25 (260523.1614)` 后，同类 `search.filter resultCount=1` 状态切换不再崩溃。
验证结果：
- `python3 scripts/verify_history_visible_window_range_guards.py` 先失败后通过。
- `swift build` 通过。
- `python3 scripts/verify_history_search_performance_guards.py` 通过。
- `python3 scripts/verify_history_filtered_index_guards.py` 通过。
- `python3 scripts/verify_store_index_performance_guards.py` 通过。
- `python3 scripts/verify_card_click_performance_guards.py` 通过。
- `python3 scripts/verify_preview_window_performance_guards.py` 通过。
- `python3 scripts/benchmark_history_search_performance.py` 通过。
- `git diff --check` 通过。
- `./scripts/build-app.sh --bump patch --run` 通过，最终运行 `2.3.26 (260523.1625)`。
- 崩溃报告检查：最新 `ClipEase-*.ips` 仍为 `2026-05-23 16:07:38` 的旧报告，运行新包后未新增 crash report，PID `27308` 在观察窗口后仍存活。
行为影响：
- 不改变搜索、分组、列表 UI、预览语义、SQLite schema 或备份格式。
- 当旧横向偏移超出当前结果数量时，渲染 / 预热窗口夹紧到有效范围，避免崩溃。
剩余问题：
- `PerformanceLogs/2026-05-23_16-26-22.jsonl` 显示启动仍有 `history.store.loadSnapshot` 约 `741ms` 和 `history.store.rebuildHashes` 约 `185ms` 主线程成本。
是否阻塞当前阶段：已修复；作为崩溃阻塞项完成。
```

```text
优化任务 ID：V2-OPT-100K-HISTORY-STARTUP-SNAPSHOT-ORDER-001
来源任务卡：用户性能专项继续优化 / PerformanceLogs 2026-05-23
来源 Agent：Codex
风险等级：中
问题描述：
- 第二批优化后，启动日志仍显示 `history.store.sort` 约 `108.66ms`。
- SQLite snapshot 已经按列表展示顺序读取 11 万+ 条数据，但 `ClipboardHistoryStore.init` 又在主线程对 `items` 调用 `sortItems()`，导致额外 O(n log n) 排序和索引重建。
已实施方案：
- 将 `SQLiteClipboardStore.loadSnapshot()` 的主表 `ORDER BY` 对齐 Swift `sortItems()`：`is_pinned DESC, created_at DESC, COALESCE(pinned_at, created_at) DESC`。
- `ClipboardHistoryStore.init` 读取 snapshot 后不再对 items 二次排序，改为只 `rebuildItemIndexes()` 并继续 `sortGroups()`。
- `history.store.sort` 埋点新增 `mode=snapshotOrder.indexOnly`，用于确认启动命中索引重建路径。
- `scripts/verify_sqlite_snapshot_bulk_load_guards.py` 新增守卫：要求 SQLite 顺序与 Swift 排序一致，并禁止初始化阶段恢复 `sortItems()`。
验证结果：
- `python3 scripts/verify_sqlite_snapshot_bulk_load_guards.py` 先失败后通过。
- `swift build` 通过。
- `./scripts/build-app.sh --bump patch --run` 通过，最终运行 `2.3.26 (260523.1625)`。
- 最终日志 `/Users/wpc/Library/Application Support/ClipEase/PerformanceLogs/2026-05-23_16-26-22.jsonl`：
  - `history.store.sort` 约 `38.94ms`，`mode=snapshotOrder.indexOnly`。
  - `history.store.initialize` 约 `965.46ms`。
- 对比上一轮 `/Users/wpc/Library/Application Support/ClipEase/PerformanceLogs/2026-05-23_14-50-07.jsonl`：
  - `history.store.sort` 从约 `108.66ms` 降到约 `38.94ms`。
  - `history.store.initialize` 从约 `1034.08ms` 降到约 `965.46ms`。
行为影响：
- 不改变列表排序语义；只是让 SQLite 输出顺序与 Swift 当前排序一致，避免二次排序。
- 不改变 SQLite schema、备份格式或远程 `.gitignore` 规则。
剩余问题：
- 启动仍同步加载全量 metadata；首屏分页 / 懒加载尚未实现。
- 去重哈希仍在主线程同步重建，下一阶段需要结合剪贴板监听启动时机分阶段处理。
是否阻塞当前阶段：否；作为低风险启动削峰修复。
```

```text
优化任务 ID：V2-OPT-100K-HISTORY-SQLITE-BULK-STARTUP-001
来源任务卡：用户性能专项审查 / PerformanceLogs 2026-05-23
来源 Agent：Codex
风险等级：中
问题描述：
- 最新日志显示 Store 热路径索引化后，启动仍有明显主线程阻塞。
- `/Users/wpc/Library/Application Support/ClipEase/PerformanceLogs/2026-05-23_14-42-37.jsonl` 中 `history.store.loadSnapshot` 约 `742ms`，但 `history.store.initialize` 约 `2961ms`，启动主线程 latency 约 `3029ms`。
- `SQLiteClipboardStore.loadSnapshot()` 原本按主表 rows 循环，对每条记录分别查询 assets、file references、OCR，10 万+ 数据会放大为 N+1 查询。
- `ClipboardHistoryStore.init` 在没有过期数据变化时仍无条件 `saveImmediately()`，导致启动阶段同步全量重写。
- 搜索结果应用阶段在主线程为 11 万条结果构建 Set / Dictionary，`search.applyResults` 曾约 `43ms - 47ms`。
已实施方案：
- `SQLiteClipboardStore.loadSnapshot()` 改为批量读取 assets、file references、OCR，再按 itemID 字典组装，去掉快照加载内的 N+1 查询。
- `ClipboardHistoryStore.pruneExpiredItems()` 返回是否真实剪裁；启动时只有剪裁发生才同步保存，避免无变化全量写库。
- 增加 `history.store.loadSnapshot`、`history.store.sort`、`history.store.rebuildHashes`、`history.store.initialize` 埋点。
- `HistoryWindowView` 为过滤结果维护 `filteredPreviewItemIDs` 和 `filteredPreviewItemIndexByID`，快捷键、粘贴、滚动定位、预览跟随等路径不再扫描 11 万条结果数组。
- 搜索后台任务返回 `HistorySearchFilterResult`，在后台构建结果 ID Set 和 id->index；主线程 `search.applyResults` 只应用结果。
- 新增 `scripts/verify_sqlite_snapshot_bulk_load_guards.py` 与 `scripts/verify_history_filtered_index_guards.py`，更新 `scripts/verify_history_search_performance_guards.py`。
验证结果：
- `swift build` 通过。
- `python3 scripts/verify_store_index_performance_guards.py` 通过。
- `python3 scripts/verify_sqlite_snapshot_bulk_load_guards.py` 通过。
- `python3 scripts/verify_history_filtered_index_guards.py` 通过。
- `python3 scripts/verify_history_search_performance_guards.py` 通过。
- `python3 scripts/verify_card_click_performance_guards.py` 通过。
- `python3 scripts/verify_preview_window_performance_guards.py` 通过。
- `python3 scripts/benchmark_history_search_performance.py` 通过，10k 常见查询约 `1.22ms`，10k 中文查询约 `1.86ms`。
- `./scripts/build-app.sh --bump patch --run` 通过，最终运行 `2.3.24 (260523.1449)`，PID `68093`。
- 最终日志 `/Users/wpc/Library/Application Support/ClipEase/PerformanceLogs/2026-05-23_14-50-07.jsonl`：
  - `history.store.loadSnapshot` 约 `734.78ms`。
  - `history.store.initialize` 约 `1034.08ms`。
  - `history.store.sort` 约 `108.66ms`。
  - `history.store.rebuildHashes` 约 `189.31ms`。
  - `search.applyResults` 约 `0.14ms`。
  - 启动主线程 latency 约 `1080.74ms`。
行为影响：
- 不改变现有 UI、搜索结果语义、预览行为、SQLite schema、备份格式或远程 ignore 规则。
- 启动时如果保留策略确实剪裁过期历史，仍会保存剪裁后的快照；无剪裁时不再无条件全量写库。
剩余问题：
- 启动仍同步加载 11 万+ 条完整 metadata；首屏分页 / 懒加载尚未实现。
- `preview.rebuild.background` 全量预热仍约 `1.15s`，下一阶段应进入索引化 / 惰性 preview 数据源，减少一次性构建 11 万个 `HistoryPreviewItem`。
- `replaceAllItems` 仍是全量快照写入，新增 / 删除持久化层还需要后续 Repository 增量 upsert / batch delete。
是否阻塞当前阶段：否；作为第二批低风险性能削峰修复。
```
