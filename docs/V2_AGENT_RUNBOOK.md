# 第二版 Agent 调度 Runbook

本文记录第二版多 Agent 调度过程、沟通记录、文件锁、冲突处理和 Demo 演练结果。

当前状态：第二版阶段 1 已启动。用户已在主控 Agent 中明确发起“开始开发第二版”。

## 1. 调度记录模板

```text
调度 ID：
时间：
阶段：
任务卡 ID：
主控 Agent：
被调用 Agent：
风险等级：
文件锁：
用户确认：
调度目的：
交付摘要：
验证摘要：
后续动作：
```

## 248. Stage 10 iCloud 同步预研静态守卫落地

```text
任务卡：V2-TEST-S10-ICLOUD-PREFLIGHT-GUARDS-001
时间：2026-05-19
阶段：Stage 10 iCloud 同步预研 - 静态守卫落地
当前会话模式：ClipEase V2 Test / Docs Agent

范围边界：
- 只补 Stage 10 preflight 静态 / 文档门禁。
- 不接入真实 iCloud 账号。
- 不新增 CloudKit runtime、entitlement、同步 UI、schema migration、附件上传下载、冲突合并或端到端加密 runtime。
- 不修改业务代码。

新增门禁脚本：
- scripts/verify_stage10_icloud_preflight_docs.py
- scripts/verify_stage10_no_cloudkit_runtime.py
- scripts/verify_stage10_no_schema_change.py
- scripts/verify_stage10_no_attachment_upload.py
- scripts/verify_stage10_user_questions.py

验证结果：
- python3 scripts/verify_stage10_icloud_preflight_docs.py：PASS。
- python3 scripts/verify_stage10_no_cloudkit_runtime.py：PASS。
- python3 scripts/verify_stage10_no_schema_change.py：PASS。
- python3 scripts/verify_stage10_no_attachment_upload.py：PASS。
- python3 scripts/verify_stage10_user_questions.py：PASS。

结论：
- PASS。Stage 10 第一批预研产物已具备可重复执行的静态守卫。
- 后续若进入任何 Stage 10 spike，仍必须另开任务卡并重新限定文件锁、测试边界和验收标准。
```

## 240. 维修阶段第七轮 Test Agent 回归门禁记录

```text
任务卡：V2-TEST-MAINT7-HISTORY-LINK-FILE-CARD-REGRESSION-001
时间：2026-05-15
阶段：维修阶段 / 第七轮 Test Agent 回归
当前会话模式：ClipEase V2 Test Agent

范围：
- 读取 docs/V2_TEST_PLAN.md 6.6。
- 读取 docs/V2_FEEDBACK_AND_GUARDS.md 的 BUG-V2-MAINT7-HISTORY-LINK-FILE-CARD-20260515。
- 读取 docs/V2_AGENT_RUNBOOK.md 第 238-239 节。
- 不修改业务代码，不回退他人改动。

自动化门禁结果：
- swift build：PASS
- git diff --check：PASS
- python3 scripts/verify_history_window_interaction_toast.py：PASS
- python3 scripts/verify_history_card_scroll_alignment.py：PASS
  - 备注：脚本报告共享工作区存在大量非本任务 dirty 文件，按脚本说明不作为失败。
- python3 scripts/verify_no_management_no_favorite_ui.py：PASS
- python3 scripts/verify_stage9_file_capture_first_batch.py：PASS
- python3 scripts/verify_stage9_file_pasteboard_first_batch.py：PASS
- python3 scripts/verify_stage9_file_card_ui.py：PASS
- python3 scripts/verify_link_title_background_fetch.py：PASS
- python3 scripts/verify_maint7_card_visual_layout.py：PASS
- python3 scripts/verify_sqlite_only_baseline.py：PASS
  - 备注：为核对 no JSON runtime / SQLite-only 红线补跑。

源码核对：
1. 空搜索框内部点击不关闭：
   - HistoryWindowView 使用 SearchInteractionRegionRegistry 弱引用 live AppKit view，将 view.bounds 转 screen frame，并在 SearchOutsideWindowMouseDownObserver 中排除搜索控件、popover 和交互控件命中。
   - closeSearchFromOutsideClick 对有搜索内容 / token / filter 的状态保持搜索打开；closeSearch 不清空搜索条件；分组导航仍走 clearAndCloseSearch。
2. 半露卡片 reveal 使用真实 document frame / viewport：
   - CardDocumentFrameReader 通过 enclosingScrollView?.documentView 和 convert(bounds, to: documentView) 写入 cardFrames。
   - partialRevealTargetOffset 使用 HistoryScrollCoordinator.shared.visibleDocumentRect 与 cardDocumentFrame(for:) 计算左右 clipped card 的 absolute offset，并保留约 1/6 peek。
3. 新卡片加入覆盖旧 offset 并延迟清 pending：
   - syncLatestItemFocusIfNeeded 设置 pendingLatestFocusItemID、shouldResetHorizontalOffsetForPendingItemScroll，保存并滚动 offset 0。
   - fulfillPendingLatestFocusIfPossible 直接选中 pending 新卡片并 scrollToItemWhenRendered。
   - pendingItemScrollID 在测量成功后才清除，scheduleSecondPendingItemScrollIfNeeded 在下一 runloop 二次校准后再清 pendingLatestFocusItemID。
4. link 捕获后立即后台抓标题：
   - ClipboardHistoryStore.addText 插入 link item 并 scheduleSave 后立即 fetchLinkTitle(for:url:)。
   - fetchLinkTitle 使用 Task.detached + LinkTitleFetcher.title；updateLinkTitle 用 id + url 防 stale fetch 覆盖编辑后的 URL，并 scheduleSave。
5. README.md 等路径文本可以进入文件捕获，普通混合文本不会误吞：
   - ClipboardMonitor.localFileURLsFromPasteboard 合并 readObjects、filenames、fileURL string、item file types 和 pasteboard string。
   - fileURLs(fromPathText:) 要求解析出的所有 path 都存在并能转为 file URL，否则返回空数组，避免普通混合文本被部分误吞为文件。
6. 链接 / 文本 / 图片卡片布局和脚本一致：
   - HistoryCardView linkPreview 使用标题 + URL 紧凑 VStack，标题 lineLimit(2) tail、URL lineLimit(1) middle。
   - textPreview maxWidth/maxHeight 填满、topLeading、lineLimit(8)、tail truncation，并带底部 LinearGradient mask。
   - imagePreview 使用 resizable + scaledToFit + maxWidth/maxHeight，占满可用区域且不拉伸。
7. no favorite / no management / no JSON runtime 不回退：
   - verify_no_management_no_favorite_ui.py PASS。
   - verify_sqlite_only_baseline.py PASS，确认 SQLite-only schema/data 基线和 forbidden JSON/runtime 标记守卫。

未验证的真实 UI 人工项：
- 真实运行态空搜索框：输入区域、搜索图标区域、窗口空白、卡片、分组入口、窗口外部点击的焦点和开闭状态。
- 真实横向滚动动画：左右半露卡片点击后方向、完整露出和下一张约 1/6 peek 的视觉距离。
- 新卡片定位：在第 20 条附近、有无置顶 / 前置情况下复制文本、链接、普通文件、图片后的实际视口回位。
- 链接后台标题：真实网络、慢响应、无标题网页的更新速度、fallback 和日志表现。
- Finder 文件捕获：README.md、txt、rtf、PDF、多文件复制的真实 pasteboard 类型差异。
- 卡片视觉：对照用户参考图检查链接、文本、横图 / 竖图 / 方图在真实窗口尺寸下是否满意。

结论：PASS。
```

## 2. 沟通记录模板

```text
沟通 ID：
时间：
来源 Agent：
目标 Agent：
问题：
回答：
结论：
影响任务：
影响文件：
是否阻塞：
预计风险等级：
主控处理结果：
```

## 3. 文件锁记录模板

```text
锁 ID：
时间：
文件 / 目录：
持有 Agent：
任务卡 ID：
风险等级：
发放原因：
预计释放条件：
是否超时：
释放时间：
```

## 4. 冲突记录模板

```text
冲突 ID：
时间：
冲突类型：
涉及文档 / 文件：
风险等级：
发现 Agent：
处理方式：
是否需要用户确认：
最终结论：
```

## 5. Bug 反馈和修复记录模板

```text
Bug ID：
时间：
来源阶段：
反馈来源：
问题描述：
复现步骤：
期望结果：
实际结果：
风险等级：
归类：
关联历史反馈：
关联功能守卫：
受影响功能：
不得回归项：
主控处理：
负责 Agent：
修复任务卡 ID：
回归验证：
守卫回归验证：
审查结果：
验收结果：
最终状态：
```

## 6. 功能守卫记录模板

```text
守卫 ID：
时间：
来源阶段：
功能名称：
已确认行为：
涉及文件 / 模块：
不得回归：
最小回归测试：
关联测试计划：
主控处理结果：
```

## 7. 主控规则同步记录模板

```text
同步 ID：
时间：
同步范围：
规则来源：
主控执行边界：
Bug 分诊规则：
测试计划前置：
反馈守卫要求：
非阻塞项归档：
Runbook 记录要求：
是否修改业务代码：
后续默认执行方式：
```

## 8. 阶段 1 调度记录

```text
调度 ID：V2-S1-SCHED-001
时间：2026-05-13 14:24:16 CST
阶段：第二版阶段 1 SQLite 基础和迁移验证
任务卡 ID：V2-S1-DATA-001 / V2-S1-TEST-001
主控 Agent：Codex 主控 Agent
被调用 Agent：数据层开发 Agent、测试 Agent
风险等级：高；包含红线相关实现路径
文件锁：
- Sources/ClipEase/Core/Storage/：数据层开发 Agent，任务卡 V2-S1-DATA-001
- Sources/ClipEase/Core/Models/：数据层开发 Agent按需修改，任务卡 V2-S1-DATA-001
- docs/V2_TEST_PLAN.md：测试 Agent，任务卡 V2-S1-TEST-001
用户确认：用户已在主控 Agent 中明确发起“开始开发第二版”。本确认只允许开始阶段 1 开发和测试目录内迁移验证，不包含在真实用户 Application Support 上删除 JSON、删除附件或清空 SQLite。
调度目的：按协作规约进入阶段 1，建立 SQLite 基础、JSON 迁移验证和阶段测试门禁。
交付摘要：进行中。
验证摘要：基线 swift build 已通过；阶段 1 具体实现验证待数据层交付后执行。
后续动作：等待数据层实现交付；主控集成后执行 swift build 和迁移验证，再进入审查与验收门禁。
```

## 8. Demo 演练记录

暂无。

## 9. 数据层 Agent 执行记录

```text
调度 ID：V2-S1-DATA-001
时间：2026-05-13
阶段：第二版阶段 1 SQLite 基础和迁移验证
任务卡 ID：V2-S1-DATA-001
主控 Agent：用户指定任务卡
被调用 Agent：数据层开发 Agent
风险等级：高 / 红线相关
文件锁：
- Sources/ClipEase/Core/Storage/
- docs/V2_AGENT_RUNBOOK.md
用户确认：允许实现迁移逻辑；不允许在真实用户 Application Support 上执行破坏性迁移。
调度目的：实现 ClipEase.sqlite 基础 schema、JSON history 导入 SQLite、最近 5 次迁移结果和错误统计。
交付摘要：新增 SQLite 基础存储、schema 版本记录、迁移结果表、临时目录迁移验证路径；迁移成功删除 JSON 由显式参数控制，安全默认不删除。
验证摘要：swift build 通过；临时目录验证导入 3 条 JSON 记录成功；坏 JSON 触发空库重建且未删除源 JSON。
后续动作：交给测试 Agent 补充自动化测试；进入 Repository 抽象前由架构守门 Agent 复核 schema 和迁移接口。
```

## 8. 主控集成记录

```text
调度 ID：V2-S1-INTEGRATION-001
时间：2026-05-13 14:32:19 CST
阶段：第二版阶段 1 SQLite 基础和迁移验证
任务卡 ID：V2-S1-DATA-001
主控 Agent：Codex 主控 Agent
被调用 Agent：数据层开发 Agent、测试 Agent、架构守门 Agent、审查 Agent、验收 Agent
风险等级：高；红线相关真实操作未执行
文件锁：
- Sources/ClipEase/Core/Storage/ClipboardHistoryPersistence.swift：主控集成写入
- Sources/ClipEase/Core/Storage/SQLiteClipboardStore.swift：主控集成写入
用户确认：用户确认开始第二版开发；真实用户 Application Support 中删除 JSON、删除附件、清空 SQLite 仍需逐次红线确认。
调度目的：补齐数据层 Agent 交付后的主存储接入，使 App 读写路径进入 SQLite。
交付摘要：ClipboardHistoryPersistence 启动时优先迁移 / 初始化 SQLite，保存历史时写入 ClipEase.sqlite；迁移安全默认不删除源 JSON。SQLiteClipboardStore 增加读取接口，支持从 SQLite 还原 ClipboardItem 与图片 / 富文本附件索引。
验证摘要：swift build 通过；临时目录小样本迁移成功，2 条记录导入 SQLite，1 条图片附件索引，源 JSON 保留；坏 JSON 验证返回 failedRebuiltEmptyStore，错误数 1，空库记录数 0，源 JSON 保留。
后续动作：等待架构守门、审查和验收 Agent 报告；阶段 1 若不放行，按阻塞项返工。
```

## 9. 阶段 1 门禁返工记录

```text
调度 ID：V2-S1-REWORK-001
时间：2026-05-13
阶段：第二版阶段 1 SQLite 基础和迁移验证
触发来源：架构守门 Agent、审查 Agent、验收 Agent
问题：
- 迁移失败后空 SQLite 可能被当成可用主存储，用户历史显示为空且后续不再重试 JSON。
- 迁移结果记录失败可能落入同一 catch 并反向清空已导入数据。
- 失败重建缺少生产 / 测试边界。
处理：
- `SQLiteHistoryMigrationOptions.safeDefault` 改为失败不重建空库。
- 新增 `SQLiteHistoryMigrationOptions.testRebuildOnFailure`，仅供测试目录验证失败重建。
- 迁移失败且未重建时删除残留 SQLite / WAL / SHM，避免下次启动误判 SQLite 已可用。
- `ClipboardHistoryPersistence` 迁移失败时回落读取 legacy JSON，不把失败 SQLite 当主库。
- 成功导入后的迁移结果持久化改为尽力记录，失败不影响已导入数据。
验证：
- `swift build` 通过。
- 临时目录坏 JSON 验证：生产默认返回 `failed`，不留下 SQLite 主库；测试专用选项返回 `failedRebuiltEmptyStore`，空库记录数 0，源 JSON 保留。
剩余阻塞：
- 迁移进度 UI 未实现 / 未验证。
- 设置页最近 5 次迁移结果展示已实现并通过 `swift build`，仍待人工打开设置页验证。
- 阶段 1 自动化矩阵已补齐并通过脚本验证：小样本、空 JSON、重复记录、图片 / 富文本附件、测试目录删除 JSON、坏 JSON 保护、最近 5 次结果、1,000 / 10,000 条。
主控结论：阶段 1 不放行，继续返工。
```

## 10. 阶段 1 自动化验证记录

```text
任务卡 ID：V2-S1-VERIFY-001
测试样本：小样本、空 JSON、重复记录、图片附件、富文本附件、坏 JSON、1,000 条、10,000 条、连续 6 次迁移结果、测试目录删除 JSON
测试目录：由 `scripts/verify_sqlite_migration.py` 创建 `clipease-sqlite-verification-*` 临时目录；脚本断言不使用 `Application Support/ClipEase`
自动化命令：python3 scripts/verify_sqlite_migration.py
迁移前记录数：0 / 1 / 2 / 5 / 1,000 / 10,000，按样本分别验证
迁移后记录数：全部与样本记录数一致；坏 JSON 生产默认不留下 SQLite 主库，测试专用重建为空库
附件索引数：小样本 2；1,000 条样本 52；10,000 条样本 508
重复记录处理结果：阶段 1 暂不去重，重复样本 2 条均导入
最近 5 次迁移结果：sidecar 5 条，SQLite 表 5 条
JSON 删除验证范围：仅 `delete-json-test-only` 测试目录样本，删除后验证成功
红线操作确认：真实 Application Support 未执行删除 JSON、删除附件或清空 SQLite
通过项：全部自动化样本通过
失败项：无
未执行项和原因：迁移进度 UI 人工验证未执行；设置页最近 5 次结果人工打开验证未执行
日志或截图：命令输出记录在主控会话；最终摘要写入 dev log
```

## 11. 阶段 1 运行验证记录

```text
任务卡 ID：V2-S1-RUNTIME-001
测试样本：真实默认 Application Support 中现有 history.json
测试目录：~/Library/Application Support/ClipEase
自动化命令：
- open -n .build/ClipEase.app
- sqlite3 "$HOME/Library/Application Support/ClipEase/ClipEase.sqlite" "select count(*) ..."
迁移前记录数：152
迁移后记录数：152
附件索引数：16
重复记录处理结果：真实样本未单独判定重复策略
最近 5 次迁移结果：SQLite 表记录 `succeeded|152|152|0|0`
JSON 删除验证范围：真实目录只读确认；`history.json` 仍存在，大小 76448 字节
红线操作确认：未删除真实 JSON；未删除附件；未清空真实 SQLite
通过项：
- Bundle 方式启动成功
- 真实默认目录 SQLite 迁移成功
- `ClipEase.sqlite` 已创建，主记录数与源记录一致
- `deleted_source_json = 0`
失败项：无数据迁移失败
未执行项和原因：
- 设置页最近 5 次结果的视觉人工核对未完成：当前环境无法通过 AppleScript 控制菜单栏 App，`--show-settings` 调试参数未产生可见窗口截图。
日志或截图：`/tmp/clipease-run.log` 记录迁移成功；设置页截图未捕获到窗口，未作为通过依据。
```

## 12. 阶段 1 当前主控结论

```text
结论：建议阶段 1 数据层和迁移验证主体通过；进入下一阶段前仍建议由用户手动打开设置页确认最近 5 次迁移结果展示。
已完成：
- SQLite 基础和主存储接入
- JSON 到 SQLite 迁移
- 失败保护和测试专用失败重建
- 迁移结果最近 5 次记录
- 设置页迁移结果展示
- 自动化迁移矩阵和真实默认目录非删除迁移验证
未执行红线：
- 未删除真实 history.json
- 未删除附件
- 未清空真实 SQLite
建议下一步：用户手动核对设置页历史数据区后，主控可进入阶段 2 Repository 抽象。
```

## 13. 阶段 1 放行记录

```text
阶段：第二版阶段 1 SQLite 基础和迁移验证
时间：2026-05-13
用户确认：用户截图确认设置页 SQLite 迁移结果展示正常，显示迁移成功、来源 152 条、导入 152 条、错误 0 个。
主控结论：阶段 1 放行，允许进入阶段 2 Repository 抽象。
红线操作：真实 history.json 未删除，附件未删除，真实 SQLite 未清空。
```

## 14. 阶段 2 Repository 抽象记录

```text
调度 ID：V2-S2-INTEGRATION-001
时间：2026-05-13
阶段：第二版阶段 2 Repository 抽象
任务卡 ID：V2-S2-REPOSITORY-001
主控 Agent：Codex 主控 Agent
风险等级：中；存储边界改造
文件锁：
- Sources/ClipEase/Core/Storage/
调度目的：把 Store/UI 与 SQLite/JSON 存储细节隔离，并保留 JSON 后端开发验证能力。
交付摘要：
- 新增 `ClipboardHistoryRepository` 协议。
- 新增 `ClipboardHistoryRepositoryKind`，默认使用 SQLite，保留 JSON 开发开关。
- `SQLiteClipboardStore` 实现 Repository。
- `JSONClipboardHistoryRepository` 实现 Repository。
- `ClipboardHistoryPersistence` 改为附件管理 + Repository 门面，`ClipboardHistoryStore` 继续只依赖 Persistence。
- UI 层不直接引用 SQLite 存储实现；迁移结果通过 `ClipboardHistoryPersistence.recentMigrationResults()` 暴露。
验证摘要：
- `swift build` 通过。
- `python3 scripts/verify_sqlite_migration.py` 通过，覆盖 SQLite 迁移矩阵和 JSON Repository 保存 / 读取。
- `python3 scripts/smoke_check.py` 通过。
未验证项：
- 未通过 UI 开关切换 JSON / SQLite；当前 JSON 后端通过脚本 harness 验证。
主控结论：阶段 2 Repository 抽象完成，建议进入下一阶段前先由架构 / 审查 Agent 做一次轻量复核。
```

## 15. 阶段 3 SQLite 主存储记录

```text
调度 ID：V2-S3-INTEGRATION-001
时间：2026-05-13
阶段：第二版阶段 3 SQLite 成为主存储
任务卡 ID：V2-S3-SQLITE-PRIMARY-001
主控 Agent：Codex 主控 Agent
风险等级：高；包含真实 JSON 删除红线但本轮未执行
文件锁：
- Sources/ClipEase/Core/Storage/
- Sources/ClipEase/Core/Utilities/HistoryExportService.swift
- Sources/ClipEase/Features/Settings/SettingsView.swift
调度目的：巩固 SQLite 主存储路径，适配 SQLite 备份包导入导出，并处理备份包重复导入提示。
交付摘要：
- SQLite Repository 保持默认主存储。
- JSON Repository 保留为开发开关后端。
- SQLite 迁移成功后删除源 JSON 的代码路径改为显式开关 `history.deleteMigratedJSONAfterSQLiteSuccess` 控制，默认不删除真实 JSON。
- 备份包导出默认写入 `ClipEase.sqlite`，并保留 `history.json` manifest 兼容旧逻辑。
- 备份包导入优先读取 `ClipEase.sqlite`，不存在时回退旧 `history.json` manifest。
- 备份包导入遇到重复历史时弹窗提示，默认按钮为“跳过重复”。
验证摘要：
- `swift build` 通过。
- `python3 scripts/verify_sqlite_migration.py` 通过，新增 SQLite 备份包导出 / 导入验证。
- `python3 scripts/smoke_check.py` 通过。
后续补齐：
- 导出备份包“包含图片和富文本附件”勾选已接入，默认勾选。
- 数据健康检查发现孤立附件时提供“一键修复”，修复前二次确认，修复后显示报告。
- 设置页关于区连点版本号 5 次后显示历史数据页性能测试入口，支持生成 1,000 / 10,000 条和清理测试数据。
未验证项：
- 未执行真实 `history.json` 删除；需要用户单独红线确认。
主控结论：阶段 3 除真实 JSON 删除红线外已完成；真实删除需用户另行确认后执行。
```

## 16. 阶段 3 红线执行记录

```text
红线确认请求：
任务卡 ID：V2-S3-REDLINE-DELETE-JSON-001
操作：删除真实用户目录中的旧 JSON 历史文件
影响：删除 ~/Library/Application Support/ClipEase/history.json；不删除 SQLite；不删除图片、缩略图或富文本附件
可恢复性：未额外备份；SQLite 已作为主存储，删除后 JSON 不能直接恢复
替代方案：继续保留 history.json；或手动复制后再删除
自动化门禁：
- 删除前确认 ClipEase.sqlite 存在
- 删除前确认 SQLite 中 clipboard_items 记录数为 154
- 删除后确认 history.json 不存在
- 删除后确认 ClipEase.sqlite 仍存在且 clipboard_items 记录数为 154
需要用户确认的问题：是否删除真实 history.json
用户确认：用户回复“删除”
确认时间：2026-05-13 15:32:33 CST
操作人：Codex 主控 Agent
执行结果：已删除 history.json；SQLite 保留且记录数 154
```

## 17. 阶段 4 收藏 / 永久保存记录

```text
调度 ID：V2-S4-INTEGRATION-001
时间：2026-05-13
阶段：第二版阶段 4 收藏 / 永久保存
任务卡 ID：V2-S4-FAVORITES-001
主控 Agent：Codex 主控 Agent
风险等级：中；修改保存期限清理逻辑和收藏状态持久化
文件锁：
- Sources/ClipEase/Core/Models/ClipboardItem.swift
- Sources/ClipEase/Core/Storage/
- Sources/ClipEase/Core/Utilities/HistoryExportService.swift
- Sources/ClipEase/Features/HistoryWindow/
调度目的：为历史记录增加收藏状态，确保收藏项目跨 SQLite / JSON / 备份包保留，并在主窗口与预览中可操作和筛选。
交付摘要：
- `ClipboardItem` 新增 `isFavorite` 和 `favoritedAt`。
- SQLite 表新增 `is_favorite` 和 `favorited_at`，旧库启动时自动补列。
- JSON Repository、旧 manifest 导出 / 导入、SQLite 备份包导入 / 导出均保留收藏状态。
- Store 新增 `toggleFavorite`，收藏项不受普通保存期限清理；取消收藏后立即重新应用保存期限。
- 历史卡片显示收藏星标；置顶且收藏时同时显示图钉和星标。
- 右键菜单新增收藏 / 取消收藏。
- 预览浮层头部新增收藏按钮。
- 顶部筛选新增收藏快捷按钮和“收藏”筛选项；收藏筛选中置顶优先，其余按 `favoritedAt` 倒序。
验证摘要：
- `swift build` 通过。
- `python3 scripts/smoke_check.py` 通过。
- `python3 scripts/verify_sqlite_migration.py` 通过，验证脚本已覆盖收藏字段。
未验证项：
- 已由用户完成真实 UI 验收；右键收藏、预览星标、顶部收藏筛选、收藏星标和置顶 + 收藏双图标均通过。
主控结论：阶段 4 收藏 / 永久保存完成并通过人工 UI 验收。
```

## 18. 阶段 5 分组基础记录

```text
调度 ID：V2-S5-INTEGRATION-001
时间：2026-05-13
阶段：第二版阶段 5 分组基础
任务卡 ID：V2-S5-GROUPS-001
主控 Agent：Codex 主控 Agent
风险等级：中；新增分组持久化和分组删除逻辑
文件锁：
- Sources/ClipEase/Core/Models/
- Sources/ClipEase/Core/Storage/
- Sources/ClipEase/Features/HistoryWindow/
调度目的：建立单层分组基础能力，允许收藏内容进入分组，并在主窗口顶部提供 Pinboard 风格入口。
交付摘要：
- 新增 `ClipboardGroup` 模型。
- `ClipboardItem` 新增 `groupID` 和 `groupedAt`。
- Repository 改为保存 / 读取 `ClipboardHistorySnapshot`，同时包含 items 和 groups。
- JSON 后端新增 `groups.json`；SQLite 后端读取 / 写入 `groups` 和 `group_items`。
- Store 新增创建、重命名、修改颜色 / 图标、删除分组、收藏到分组、移出分组。
- 主窗口顶部新增分组栏：全部剪切板、横向分组按钮和 `+` 新建分组。
- 分组按钮支持右键重命名、改颜色、改图标、删除。
- 卡片右键支持“收藏到分组 / 移动到分组 / 移出分组”；普通历史进入分组时自动成为收藏。
- 选择分组后按 `groupedAt` 倒序显示内容。
验证摘要：
- `swift build` 通过。
- `python3 scripts/verify_sqlite_migration.py` 通过。
- `python3 scripts/smoke_check.py` 通过。
- `scripts/build-app.sh --bump none --run` 已打包并启动 `.build/ClipEase.app`，当前进程 23837。
未完成项：
- 分组拖拽排序未实现。
- 分组管理窗口、批量删除和更多分组搜索未实现。
- 自定义系统取色器和图标搜索未实现；当前先提供预设颜色和图标菜单。
主控结论：阶段 5 分组基础第一轮可进入人工 UI 验收。
```

## 19. 阶段 5 分组后续记录

```text
调度 ID：V2-S5-FOLLOWUP-001
时间：2026-05-13
阶段：第二版阶段 5 分组基础后续
任务卡 ID：V2-S5-GROUPS-FOLLOWUP-001
主控 Agent：Codex 主控 Agent
风险等级：中；增强分组管理与批量删除
交付摘要：
- 顶部分组栏只直接展示前 8 个分组，溢出分组进入右侧“更多”菜单。
- 更多分组超过 10 个时显示搜索框。
- 更多菜单和主窗口更多菜单均提供“分组管理”入口。
- 分组管理 sheet 支持查看分组、拖拽排序、新建分组、批量选择和批量删除。
- 分组删除仍使用“删除分组和内容”危险按钮。
- 分组颜色和图标编辑合并为“颜色与图标”面板。
- 颜色支持 `ColorPicker` 自定义。
- 图标库扩展并支持搜索。
验证摘要：
- `swift build` 通过。
- `python3 scripts/verify_sqlite_migration.py` 通过。
- `python3 scripts/smoke_check.py` 通过。
- `scripts/build-app.sh --bump none --run` 已打包并启动 `.build/ClipEase.app`，当前进程 54885。
主控结论：阶段 5 后续项可进入人工 UI 验收。
```

## 20. 阶段 5 分组 UI 返工记录

```text
调度 ID：V2-S5-UI-REWORK-001
时间：2026-05-13
阶段：第二版阶段 5 分组基础返工
用户反馈：
1. 分组应该放在搜索这一行，而不应该单独一行。
2. 分组的 “+” 和 “更多” 应该在最后一个分组后面，不应该在最右侧。
3. 分组新增 / 重命名应该直接在“新分组”上输入，而不是弹出对话框。
4. 分组颜色与图标修改应该悬浮在当前分组旁边。
5. 分组管理应该在“设置”里，而不是单独弹窗配置。
任务卡：
- V2-S5-UI-REWORK-001：主窗口分组栏返工，负责 Agent：UI / 交互开发 Agent。
- V2-S5-SETTINGS-GROUP-MANAGER-001：设置页分组管理迁移，负责 Agent：UI / 交互开发 Agent（设置页切片）。
风险等级：中；涉及主窗口核心交互和设置页聚合管理。
文件锁：
- Sources/ClipEase/Features/HistoryWindow/
- Sources/ClipEase/Features/Settings/SettingsView.swift
交付摘要：
- 主窗口分组栏已并入搜索 / 筛选同一行。
- “+” 和“更多”已移入分组横向区域，紧跟最后一个可见分组。
- 新建分组后直接进入分组按钮内联编辑；双击或右键重命名同样原位编辑。
- 颜色与图标修改改为当前分组按钮上的 popover。
- 主窗口移除独立“分组管理”入口。
- 设置页新增“分组”分类，集中提供新建、重命名、颜色、图标、拖拽排序、单个删除和批量删除。
验证摘要：
- 主窗口切片 Agent 执行 `swift build` 通过。
- 设置页切片 Agent 初次验证被主窗口中间态编译错误阻塞；主窗口切片完成后由主控重新验证。
- 主控执行 `swift build` 通过。
- 主控执行 `python3 scripts/verify_sqlite_migration.py` 通过。
- 主控执行 `python3 scripts/smoke_check.py` 通过。
- 主控执行 `scripts/build-app.sh --bump none --run` 并启动 `.build/ClipEase.app`，当前进程 83156，版本 `1.0.5(260513.1703)`。
未验证项：
- 仍需用户人工 UI 验收主窗口同排布局、内联编辑、popover 锚点和设置页分组管理。
主控结论：阶段 5 分组 UI 返工已完成自动验证，可进入人工 UI 验收。
```

## 21. 阶段 5 分组栏位置修正记录

```text
调度 ID：V2-S5-GROUPBAR-LAYOUT-002
时间：2026-05-13
阶段：第二版阶段 5 分组栏位置修正
用户反馈：分组布局仍有问题，分组应该在收藏后面，且不要出现分割线。
任务卡 ID：V2-S5-GROUPBAR-LAYOUT-002
负责 Agent：UI / 交互开发 Agent
风险等级：中；主窗口核心 toolbar 布局
允许修改：Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift
交付摘要：
- toolbar 行顺序调整为搜索、筛选、置顶、收藏、分组区域。
- 分组区域紧跟收藏按钮之后。
- 分组区域与收藏按钮之间没有 `Divider` 或视觉分割线。
- 保留内联新建 / 重命名和颜色图标 popover。
验证摘要：
- UI Agent 执行 `swift build` 通过。
- 主控执行 `swift build` 通过。
- 主控执行 `python3 scripts/verify_sqlite_migration.py` 通过。
- 主控执行 `python3 scripts/smoke_check.py` 通过。
- 主控执行 `scripts/build-app.sh --bump none --run` 并启动 `.build/ClipEase.app`，当前进程 92117，版本 `1.0.5(260513.1710)`。
主控结论：分组栏位置修正已完成，可进入人工 UI 验收。
```

## 22. 阶段 5 分组后续收口记录

```text
调度 ID：V2-S5-CLOSURE-001
时间：2026-05-13 18:09:19 CST
阶段：第二版阶段 5 分组基础后续收口
任务卡 ID：
- V2-S5-BACKUP-GROUPS-001
- V2-S5-GROUPS-POLISH-001
主控 Agent：Codex 主控 Agent
被调用 Agent：审查 Agent、数据往返开发 Agent、体验补齐开发 Agent
风险等级：中；备份导入导出影响分组数据完整性，未执行真实导入备份或删除操作
文件锁：
- Sources/ClipEase/Core/Utilities/HistoryExportService.swift
- Sources/ClipEase/Core/Storage/ClipboardHistoryStore.swift
- Sources/ClipEase/Core/Models/ClipboardGroup.swift
- Sources/ClipEase/Features/Settings/SettingsView.swift
- scripts/verify_sqlite_migration.py
调度目的：对照阶段 5 完成标准补齐分组备份往返、设置页图标搜索和默认随机图标。
交付摘要：
- 审查 Agent 确认阶段 5 主体已满足，发现备份包未保留 groups 的阻塞缺口，以及设置页图标搜索、默认随机图标等非阻塞缺口。
- `.clipeasebackup` 的 SQLite 和兼容 `history.json` manifest 现在会导出 groups。
- `HistoryExportService.importBackup` 返回 items + groups，缺附件行为保持原样。
- `ClipboardHistoryStore.importBackupItems` 支持保守合并分组，只保留可解析到有效分组的 item 分组归属。
- 设置页真实备份导入 / 导出路径已传递 `store.groups` 和 `importResult.groups`。
- 普通“导出历史”也会把 `store.groups` 写入 JSON。
- 新建分组默认图标改为从内置图标库随机选择，默认颜色仍来自固定预设色板。
- 设置页分组管理图标选择改为带搜索框的 popover 图标网格。
验证摘要：
- 主控执行 `swift build` 通过。
- 主控执行 `python3 scripts/verify_sqlite_migration.py` 通过，覆盖分组、item 入组、SQLite 备份导出 / 导入和 Store 合并后关系保留。
- 主控执行 `python3 scripts/smoke_check.py` 通过。
- 主控执行 `scripts/build-app.sh --bump none --run` 并启动 `.build/ClipEase.app`，当前进程 55969，版本 `1.0.5(260513.1809)`。
未验证项：
- 设置页图标搜索 popover、普通导出 JSON 中 groups 字段、备份包分组恢复仍建议人工 UI / 文件检查。
主控结论：阶段 5 后续收口自动门禁通过，可打包运行并进入人工验收。
```

## 23. 阶段 5 分组栏系统分组返工记录

```text
调度 ID：V2-S5-GROUPBAR-SYSTEM-GROUPS-001
时间：2026-05-13
阶段：第二版阶段 5 分组栏系统分组返工
用户反馈：
1. 主窗口顶部分组多的时候不要隐藏，要全部显示，占满顶部宽度，如果超出宽度可以使用滚轮横向滚动。
2. 主窗口顶部置顶 / 收藏也应该是分组，取消原图标按钮；置顶和收藏应该在全部剪切板后面固定，且不能删除、修改名字，但是可以自定义图标和颜色。
任务卡 ID：V2-S5-GROUPBAR-SYSTEM-GROUPS-001
负责 Agent：UI / 交互开发 Agent
风险等级：中；主窗口核心 toolbar / 筛选交互
允许修改：Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift
交付摘要：
- 移除主窗口顶部独立的置顶 / 收藏圆形图标筛选按钮。
- 顶部分组栏顺序调整为全部剪切板、置顶、收藏、用户分组、`+` 新建。
- 用户分组不再截断前 8 个，也不再进入更多菜单；全部在同一个横向滚动分组栏内展示。
- 分组栏使用横向 `ScrollView`，占满顶部可用宽度，超出宽度时横向滚动。
- 置顶 / 收藏作为固定系统分组参与筛选，重复点击回到全部。
- 置顶 / 收藏只提供颜色与图标自定义，不提供删除或重命名入口；外观使用 `@AppStorage` 持久化。
验证摘要：
- UI Agent 执行 `swift build` 通过。
- UI Agent 执行 `python3 scripts/smoke_check.py` 时因 RC 报告构建号未同步失败。
- 主控同步 `docs/RELEASE_CANDIDATE_REPORT.md` 到当前版本 `1.0.5(260513.1809)`。
- 主控执行 `swift build` 通过。
- 主控执行 `python3 scripts/verify_sqlite_migration.py` 通过。
- 主控执行 `python3 scripts/smoke_check.py` 通过。
- 主控执行 `scripts/build-app.sh --bump none --run` 并启动 `.build/ClipEase.app`，当前进程 92143，版本 `1.0.5(260513.1844)`。
未验证项：
- 仍需用户人工确认横向滚轮手感、置顶 / 收藏系统分组外观自定义、分组栏在大量分组下的实际布局。
主控结论：阶段 5 分组栏系统分组返工自动门禁通过，可打包运行并进入人工 UI 验收。
```

## 24. 阶段 5 分组栏居中修正记录

```text
调度 ID：V2-S5-GROUPBAR-CENTER-001
时间：2026-05-13
阶段：第二版阶段 5 分组栏布局微调
用户反馈：主窗口顶部搜索，分组要居中而不是左侧对齐。
任务卡 ID：V2-S5-GROUPBAR-CENTER-001
负责 Agent：UI / 交互开发 Agent
风险等级：低；主窗口 toolbar 布局微调
允许修改：Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift
交付摘要：
- 顶部搜索按钮、筛选菜单和分组横向滚动区放入居中宽度容器。
- 分组栏内容不足时在容器内居中，内容超出时继续横向滚动。
- 左侧关闭 / 标题 / 状态保持原位，右侧更多菜单仍独立贴右。
- 未恢复“更多分组”菜单，未恢复置顶 / 收藏圆形按钮。
验证摘要：
- UI Agent 执行 `swift build` 通过。
- 主控执行 `swift build` 通过。
- 主控执行 `python3 scripts/smoke_check.py` 通过。
- 主控执行 `scripts/build-app.sh --bump none --run` 并启动 `.build/ClipEase.app`，当前进程 1629，版本 `1.0.5(260513.1850)`。
未验证项：
- 仍需用户人工确认不同窗口宽度下的视觉居中效果和横向滚轮手感。
主控结论：阶段 5 分组栏居中修正自动验证通过，可打包运行并进入人工 UI 验收。
```

## 25. 阶段 5 顶部滚动轨道和分组记忆记录

```text
调度 ID：V2-S5-GROUPBAR-SCROLL-TRACK-001
时间：2026-05-13
阶段：第二版阶段 5 顶部滚动轨道返工
用户反馈：主窗口顶部搜索、分组要居中；新建分组自动加到最后；顶部整体占满后左侧搜索向左隐藏但可滚轮横向滚动；关闭主窗口后记住最后选中分组；`+` 永远在最后一个分组后面。
任务卡 ID：V2-S5-GROUPBAR-SCROLL-TRACK-001
负责 Agent：UI / 交互开发 Agent
风险等级：中；主窗口核心 toolbar / 状态恢复交互
允许修改：Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift
交付摘要：
- 顶部中间区改为同一条横向滚动轨道，包含搜索框 / 搜索按钮、筛选菜单、全部剪切板、置顶、收藏、全部用户分组和 `+`。
- 轨道内容不足时整体居中，超过可用宽度时可横向滚动，左侧搜索随滚动向左隐藏。
- 左侧关闭 / 标题 / 状态和右侧更多菜单保持固定，不进入滚动轨道。
- 新建分组追加到用户分组末尾，`+` 始终在最后一个用户分组后面，新分组进入内联命名并滚动到可见位置。
- 使用 `@AppStorage` 记住最后选中的全部、置顶、收藏或仍存在的用户分组；用户分组不存在时回到全部剪切板。
- 主控修正顶部轨道滚轮逻辑，避免复用卡片横向滚动记忆，防止顶部分组滚动污染卡片位置恢复。
验证摘要：
- UI Agent 执行 `swift build` 通过。
- 主控执行 `swift build` 通过。
- 主控执行 `python3 scripts/verify_sqlite_migration.py` 通过。
- 主控执行 `python3 scripts/smoke_check.py` 通过。
- 主控执行 `scripts/build-app.sh --bump none --run` 并启动 `.build/ClipEase.app`，当前进程 20156，版本 `1.0.5(260513.1906)`。
未验证项：
- 仍需用户人工确认大量分组下滚轮横向滚动、左侧搜索隐藏手感、关闭重开后分组恢复和 `+` 位置。
主控结论：阶段 5 顶部滚动轨道返工自动门禁通过，可打包运行并进入人工 UI 验收。
```

## 26. 阶段 6 搜索 / 筛选第一批记录

```text
调度 ID：V2-S6-SEARCH-UI-001
时间：2026-05-13
阶段：第二版阶段 6 更强搜索
任务卡 ID：
- V2-S6-SEARCH-ARCH-001
- V2-S6-SEARCH-UI-001
主控 Agent：Codex 主控 Agent
被调用 Agent：搜索架构 / 测试预研 Agent、UI / 交互开发 Agent
风险等级：中；主窗口核心搜索交互，未修改数据层
文件锁：
- Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift
- Sources/ClipEase/Features/HistoryWindow/HistoryPreviewItem.swift
调度目的：按阶段 6 开始搜索 / 筛选重构，先在现有内存搜索路径上建立搜索筛选状态、token 展示和筛选面板骨架。
架构预研摘要：
- 当前搜索仍是 UI 内存过滤，不是 SQLite 查询搜索。
- SQLite 已有类型、来源、置顶、收藏和时间相关普通索引，但没有 LIKE / FTS 搜索 API。
- 建议阶段 6 拆分为搜索状态模型、token / 面板 UI、SQLite LIKE、FTS 准备和搜索验证脚本。
交付摘要：
- 新增 `HistorySearchCriteria`，支持类型、来源 App、日期范围和分组组合条件。
- 搜索框内展示筛选 token，顺序固定为类型、App、日期、分组。
- token 支持关闭按钮移除；清空搜索会同时清空关键词和 token。
- 搜索框右侧新增筛选按钮和 popover 面板，面板按类型、来源 App、日期、分组分类展示；设备筛选未显示。
- `Command + F` 调整为三段行为：展开搜索并聚焦、打开筛选面板、关闭筛选面板并聚焦搜索框。
- 组合过滤逻辑已接入现有内存搜索路径，并与顶部分组轨道选择兼容。
- `HistoryPreviewItem` 透传 `createdAt` 并让 `HistoryPreviewType` 可比较，用于日期和类型筛选。
验证摘要：
- UI Agent 执行 `swift build` 通过。
- 主控执行 `swift build` 通过。
- 主控执行 `python3 scripts/verify_sqlite_migration.py` 通过。
- 主控执行 `python3 scripts/smoke_check.py` 通过。
- 主控执行 `scripts/build-app.sh --bump none --run` 并启动 `.build/ClipEase.app`，当前进程 38037，版本 `1.0.5(260513.1919)`。
未完成项：
- Backspace 删除 token 未实现。
- token 超出搜索框宽度时横向滚动和光标保持可见未实现。
- SQLite LIKE / FTS 查询下沉未实现。
- 搜索筛选 UI 仍需人工验证。
主控结论：阶段 6 第一批搜索 / 筛选 UI 自动门禁通过，可打包运行并进入人工 UI 验收；下一批建议推进 token 键盘交互或 SQLite LIKE 搜索准备。
```

## 27. 阶段 6 搜索 / 筛选交互收口记录

```text
调度 ID：V2-S6-SEARCH-UI-002
时间：2026-05-13
阶段：第二版阶段 6 更强搜索
任务卡 ID：V2-S6-SEARCH-UI-002
主控 Agent：Codex 主控 Agent
风险等级：中；主窗口核心搜索交互，未修改数据层
文件锁：
- Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift
调度目的：收口搜索筛选入口和 token 键盘体验，减少阶段 6 第一批遗留交互问题。
交付摘要：
- 移除顶部轨道旧“筛选”菜单，筛选入口统一收敛到搜索框右侧按钮。
- 搜索 token 区增加横向滚动容器，避免多个 token 挤压输入框。
- 搜索输入为空且存在 token 时，按 Backspace 会删除最后一个 token，并保持搜索框焦点。
- 删除未使用的旧 `HistoryFilter` 通道，组合筛选统一使用 `HistorySearchCriteria`。
验证摘要：
- 主控执行 `swift build` 通过。
- 主控执行 `python3 scripts/verify_sqlite_migration.py` 通过。
- 主控执行 `python3 scripts/smoke_check.py` 通过。
- 主控执行 `scripts/build-app.sh --bump none --run` 并启动 `.build/ClipEase.app`，当前进程 49901，版本 `1.0.5(260513.1926)`。
未完成项：
- SQLite LIKE / FTS 查询下沉未实现。
- 搜索筛选 UI 仍需人工验证。
主控结论：阶段 6 搜索筛选交互收口自动门禁通过，可打包运行并进入人工 UI 验收；下一批建议推进 SQLite LIKE 搜索准备。
```

## 28. 阶段 6 搜索 token 与分组外观编辑修复记录

```text
调度 ID：V2-S6-SEARCH-GROUP-UX-FIX-001
时间：2026-05-13
阶段：第二版阶段 6 更强搜索 / 阶段 5 分组体验补丁
用户反馈：
- 筛选面板点击选择不能关闭主窗口。
- 搜索框有筛选但无文字时不要显示背景“搜索”。
- 筛选 token 需要更像文字搜索的一部分，支持选中 token 后 Backspace 删除。
- 搜索框展开宽度需要加宽并带展开 / 关闭动画。
- 分组颜色 / 图标弹层操作不能关闭主窗口。
- 分组右键颜色 / 图标功能和设置页分组颜色 / 图标调整需要完善。
主控 Agent：Codex 主控 Agent
风险等级：中；主窗口关闭监控、搜索框键盘事件、分组外观编辑
文件锁：
- Sources/ClipEase/Features/HistoryWindow/HistoryWindowController.swift
- Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift
- Sources/ClipEase/Features/Settings/SettingsView.swift
交付摘要：
- 主窗口外部点击关闭监控会忽略 App 自身 popover / 面板窗口，修复搜索筛选和分组外观 popover 点击导致主窗口关闭的问题。
- 搜索框有 token 但无搜索文字时隐藏 placeholder。
- 搜索 token 视觉更靠近输入内容，并支持点击选中；空输入时 Backspace 第一次选中最后一个 token，第二次删除选中 token。
- 搜索框展开宽度从 360 提升到 520，并使用更明显的展开 / 关闭动画。
- 主窗口分组颜色与图标 popover 增加预设色块、实时预览、确认按钮，并修复选择图标后预览状态不刷新的问题。
- 设置页分组管理行改为“颜色与图标”完整 popover，支持颜色选择、预设色、图标搜索、图标持续选择和确认关闭。
验证摘要：
- 主控执行 `swift build` 通过。
- 主控执行 `python3 scripts/verify_sqlite_migration.py` 通过。
- 主控执行 `python3 scripts/smoke_check.py` 通过。
- 主控执行 `scripts/build-app.sh --bump none --run` 并启动 `.build/ClipEase.app`，当前进程 85989，版本 `1.0.5(260513.1955)`。
未完成项：
- 仍需用户人工确认 popover 点击不会关闭主窗口、token Backspace 两段式体验、设置页分组外观编辑手感。
主控结论：本轮搜索 token 和分组外观编辑反馈已完成自动门禁并打包运行，可进入人工 UI 验收。
```

## 29. 阶段 6 搜索框整体滚动与多选筛选面板记录

```text
调度 ID：V2-S6-SEARCH-OMNIBOX-FILTERS-001
时间：2026-05-13
阶段：第二版阶段 6 更强搜索
用户反馈：
- 搜索 token 不应占固定宽度，应与后方文字共同占用搜索框整体宽度，超出后横向滚动。
- 搜索框展开时分组按钮改为单图标形式并隐藏分组 `+`，关闭搜索框后恢复带文本和 `+`。
- 搜索筛选面板固定宽高，超出滚动。
- 筛选面板改为按钮形式，带小图标，App 来源使用 App 图标，并支持同类 token 多选。
- ESC 顺序：先关筛选面板，再清空搜索框内容，再关闭搜索框，再关闭主窗口。
主控 Agent：Codex 主控 Agent
风险等级：中；主窗口搜索交互和筛选状态模型
文件锁：
- Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift
交付摘要：
- 搜索框内 token 和文字输入合并为同一条横向滚动内容轨道，超出搜索框宽度时整体滚动。
- 搜索展开时全部 / 置顶 / 收藏 / 用户分组按钮切换为纯图标紧凑模式，并隐藏新建分组 `+`；关闭搜索后恢复文本按钮和 `+`。
- 搜索筛选 popover 固定为 `440 x 320`，内部筛选区固定为 `420 x 260` 并支持纵向滚动。
- 筛选面板改为按钮网格：类型、App、日期、分组均带图标；App 来源优先显示缓存 App 图标。
- 搜索筛选状态从单选改为同类多选集合，token 生成和过滤逻辑已同步支持多选。
- ESC 行为顺序调整为：关闭筛选面板、清空搜索文字与 token、关闭搜索框、关闭主窗口。
验证摘要：
- 主控执行 `swift build` 通过。
- 主控执行 `python3 scripts/verify_sqlite_migration.py` 通过。
- 主控执行 `python3 scripts/smoke_check.py` 通过。
- 主控执行 `scripts/build-app.sh --bump none --run` 并启动 `.build/ClipEase.app`，当前进程 49418，版本 `1.0.5(260513.2056)`。
未完成项：
- 仍需用户人工确认参考图 1 / 图 2 对齐程度、横向滚动手感和多选筛选组合结果。
主控结论：阶段 6 搜索框整体滚动、多选筛选面板和 ESC 顺序修复自动门禁通过，可进入人工 UI 验收。
```

## 30. 阶段 6 bugfix 调度记录

```text
调度 ID：V2-DOCS-BUGFIX-LOG-001
时间：2026-05-13
阶段：第二版阶段 6 / bugfix 调度记录
任务卡 ID：V2-DOCS-BUGFIX-LOG-001
主控 Agent：Codex 主控 Agent
被调用 Agent：Bugfix Agent
风险等级：低；本记录仅更新主控调度文档，不修改业务代码
用户反馈：
- 分组右键“颜色与图标”弹窗中搜索图标时弹窗位置不能变化。
- “全部剪切板”背景颜色要与选中背景颜色一致；选中时与其他分组一样显示白色外边框。
- 分组右键“颜色与图标”弹窗里颜色 / 图标样式要增加。
主控分诊：
- 按新规则判定为小范围 UI bug。
- 主控只负责分诊和调度记录，不亲自写代码。
Bugfix 任务：
- Bugfix 任务卡 ID：V2-BUGFIX-GROUP-APPEARANCE-POPOVER-001
- 风险等级：中
文件锁：
- Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift
- Sources/ClipEase/Core/Models/ClipboardGroup.swift（仅扩展预设颜色 / 图标）
调度目的：将分组外观 popover 位置稳定性、“全部剪切板”选中视觉一致性和预设颜色 / 图标扩展交由 Bugfix Agent 处理。
交付摘要：主控已完成 bug 反馈记录、分诊结论和 Bugfix Agent 调度记录；未修改业务代码。
验证摘要：文档记录已追加；未执行代码构建或 UI 验证。
后续门禁：Bugfix 完成后需要测试 Agent 验证、审查 Agent 审查、验收 Agent 放行。
```

## 31. 阶段 6 bugfix 测试通过与审查阻塞记录

```text
调度 ID：V2-DOCS-BUGFIX-REVIEW-BLOCK-001
时间：2026-05-13
阶段：第二版阶段 6 / bugfix 测试与审查门禁
任务卡 ID：V2-DOCS-BUGFIX-REVIEW-BLOCK-001
关联任务：V2-BUGFIX-GROUP-APPEARANCE-POPOVER-001
主控 Agent：Codex 主控 Agent
被调用 Agent：测试 Agent Meitner、审查 Agent Ampere、Bugfix Agent
风险等级：低；本记录仅更新 runbook，不修改业务代码
文件锁：
- docs/V2_AGENT_RUNBOOK.md
测试结果：
- 测试 Agent Meitner 完成 V2-TEST-GROUP-APPEARANCE-POPOVER-001。
- `swift build` 通过。
- `python3 scripts/smoke_check.py` 通过。
- `python3 scripts/verify_sqlite_migration.py` 通过。
- 静态验证通过：popover 固定尺寸；全部剪切板选中时显示白色边框；预设颜色 18 个；预设图标 92 个。
- 未执行手动 UI 验证。
审查结果：
- 审查 Agent Ampere 完成 V2-REVIEW-GROUP-APPEARANCE-POPOVER-001。
- 审查结论：block，暂不建议验收。
审查阻塞原因：
- 当前工作树存在大量历史未提交改动，无法从全局 diff 证明本次 bugfix 边界。
- `Sources/ClipEase/Core/Models/ClipboardGroup.swift` 是未跟踪完整模型文件，需要隔离说明本次只改默认颜色 / 图标。
- `Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift` 包含大量早前阶段功能，需要隔离说明本次只改局部 UI。
主控结论：
- 不放行验收。
- 要求 Bugfix Agent 做 rework / clarification。
- Bugfix Agent 需提供隔离改动清单，并重新运行 `swift build`。
后续动作：
- 等待 Bugfix Agent 补充隔离说明和重新构建结果。
- 补充完成后重新交给审查 Agent 判断是否解除 block。
```

## 32. 阶段 6 bugfix 最终门禁记录

```text
调度 ID：V2-DOCS-BUGFIX-FINAL-GATE-001
时间：2026-05-13
阶段：第二版阶段 6 / bugfix 最终门禁记录
任务卡 ID：V2-DOCS-BUGFIX-FINAL-GATE-001
关联任务：V2-BUGFIX-GROUP-APPEARANCE-POPOVER-001
主控 Agent：Codex 主控 Agent
被调用 Agent：Bugfix Agent、测试 Agent Meitner、初审 Agent Ampere、复审 Agent Hegel、验收 Agent Jason
风险等级：低；本记录仅更新 runbook 和优化 backlog，不修改业务代码
文件锁：
- docs/V2_AGENT_RUNBOOK.md
- docs/V2_OPTIMIZATION_BACKLOG.md
Bugfix 交付事实：
- Bugfix Agent 完成修复：分组外观 popover 固定尺寸；全部剪切板按钮选中时显示白色边框；预设颜色扩展到 18 个；预设图标扩展到 92 个。
测试结果：
- 测试 Agent Meitner 完成验证。
- `swift build` 通过。
- `python3 scripts/smoke_check.py` 通过。
- `python3 scripts/verify_sqlite_migration.py` 通过。
- 手动 UI 未执行。
初审结果：
- 初审 Agent Ampere 结论为 block。
- block 原因：要求隔离本任务 diff，说明当前工作树大量历史改动中哪些属于本次 bugfix。
Bugfix rework / clarification：
- Bugfix Agent 未再修改文件。
- Bugfix Agent 说明本次只改 `defaultColors` / `defaultIcons`，以及 `HistoryWindowView` 中外观常量、全部剪切板按钮、外观 popover 固定宽高和色板网格。
- Bugfix Agent 重新运行 `swift build` 并通过。
复审结果：
- 复审 Agent Hegel 通过复审。
- 复审建议进入验收，保留人工 UI 验收项。
验收结果：
- 验收 Agent Jason 阶段性放行。
- 人工 UI 未验收不阻塞阶段性放行，但阻塞最终发布 / 完整验收。
Backlog 归档：
- 已将“发布前人工 UI 验收分组外观 popover”归档到 `docs/V2_OPTIMIZATION_BACKLOG.md`。
主控结论：
- 本 bugfix 阶段性通过。
- 最终发布前必须完成人工 UI 验收。
未完成项：
- 人工实际右键打开“颜色与图标”，输入不同搜索词确认 popover 屏幕位置不变。
- 人工确认“全部剪切板”选中 / 未选中视觉。
- 人工确认扩展颜色 / 图标滚动、点击、搜索、显示正常。
```

## 33. 阶段 6 搜索 / 授权 / ESC bugfix 调度记录

```text
调度 ID：V2-DOCS-SEARCH-AUTH-ESC-BUGFIX-LOG-001
时间：2026-05-13
阶段：第二版阶段 6 / 搜索、授权状态和 ESC 逻辑 bugfix 调度记录
任务卡 ID：V2-DOCS-SEARCH-AUTH-ESC-BUGFIX-LOG-001
主控 Agent：Codex 主控 Agent
被调用 Agent：Bugfix Agent
风险等级：低；本记录仅更新 runbook，不修改业务代码
用户反馈：
1. 搜索框展开且无内容时，关闭 / 隐藏主窗口后再次打开应关闭搜索框。
2. 搜索框展开时只搜索全部剪切板；点击分组 / 收藏 / 置顶左键或右键应自动关闭搜索框。
3. 搜索框展开时搜索框内所有区域都应可点击。
4. 搜索框展开时最右侧 x/y 应移到搜索框左侧。
5. 未授权时主窗口要闪烁“请授权”，并时刻更新授权状态。
6. 无论是否授权，ESC 逻辑统一为：先关闭所有弹窗层，再清空搜索内容，再关闭搜索框，再关闭主窗口。
主控分诊：
- 按新规则判定为中风险小范围 UI / 权限状态 bug。
- 主控只负责分诊和调度记录，不亲自写代码。
Bugfix 任务：
- Bugfix 任务卡 ID：V2-BUGFIX-SEARCH-AUTH-ESC-001
- 风险等级：中
文件锁：
- Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift
- Sources/ClipEase/Features/HistoryWindow/HistoryWindowController.swift
- Sources/ClipEase/Features/HistoryWindow/HistoryWindowInputState.swift
- Sources/ClipEase/Core/Utilities/AccessibilityPermissionState.swift（权限策略不得改）
调度目的：将搜索框收起 / 点击区域 / x-y 位置、授权提示与授权状态刷新、统一 ESC 顺序交由 Bugfix Agent 处理。
用户要求：
- 用户已明确要求修复后主控构建运行 App。
- 主控将在测试 / 审查 / 验收后执行打包运行。
交付摘要：主控已记录 6 个 bug、分诊结论、Bugfix Agent 调度和文件锁；未修改业务代码。
验证摘要：文档记录已追加；未执行代码构建、测试或 UI 验证。
后续门禁：Bugfix 完成后需要测试 Agent 验证、审查 Agent 审查、验收 Agent 放行；通过后由主控构建并运行 App。
```

## 34. 阶段 6 搜索 / 授权 / ESC bugfix 测试通过与审查阻塞记录

```text
调度 ID：V2-DOCS-SEARCH-AUTH-ESC-REVIEW-BLOCK-001
时间：2026-05-13
阶段：第二版阶段 6 / 搜索、授权状态和 ESC 逻辑 bugfix 测试与审查门禁
任务卡 ID：V2-DOCS-SEARCH-AUTH-ESC-REVIEW-BLOCK-001
关联任务：V2-BUGFIX-SEARCH-AUTH-ESC-001
主控 Agent：Codex 主控 Agent
被调用 Agent：测试 Agent Halley、审查 Agent James、Bugfix Agent
风险等级：低；本记录仅更新 runbook，不修改业务代码
文件锁：
- docs/V2_AGENT_RUNBOOK.md
测试结果：
- 测试 Agent Halley 完成验证。
- `swift build` 通过。
- `python3 scripts/smoke_check.py` 通过。
- `python3 scripts/verify_sqlite_migration.py` 通过。
- 静态验证通过。
- 手动 UI 未执行。
审查结果：
- 审查 Agent James 结论为 block。
- 审查 Agent James 不建议进入验收。
审查阻塞原因：
- 搜索展开时点击“全部剪切板”不会关闭 / 清空搜索，`selectAllGroups()` 未调用 `closeSearchForGroupNavigation()`。
- 授权状态每秒刷新未显式限制在主窗口可见期间，隐藏后可能继续 refresh / pulse。
审查范围问题：
- 当前工作树历史脏，需 Bugfix Agent 提供隔离改动清单。
主控结论：
- 不放行。
- 不打包。
- 重新调度 Bugfix Agent 执行 `V2-BUGFIX-SEARCH-AUTH-ESC-001-REWORK`。
后续动作：
- Bugfix Agent 修复审查阻塞项。
- Bugfix Agent 提供隔离改动清单。
- Rework 后重新进入测试、审查和验收门禁。
```

## 35. 阶段 6 搜索 / 授权 / ESC bugfix 返工后最终门禁记录

```text
调度 ID：V2-DOCS-SEARCH-AUTH-ESC-FINAL-GATE-001
时间：2026-05-13
阶段：第二版阶段 6 / 搜索、授权状态和 ESC 逻辑 bugfix 返工后最终门禁
任务卡 ID：V2-DOCS-SEARCH-AUTH-ESC-FINAL-GATE-001
关联任务：V2-BUGFIX-SEARCH-AUTH-ESC-001 / REWORK
主控 Agent：Codex 主控 Agent
被调用 Agent：Bugfix Agent Avicenna、测试 Agent Halley、审查 Agent James、测试 Agent Erdos、复审 Agent Godel、验收 Agent Lovelace
风险等级：低；本记录仅更新 runbook 和优化 backlog，不修改业务代码
文件锁：
- docs/V2_AGENT_RUNBOOK.md
- docs/V2_OPTIMIZATION_BACKLOG.md
Bugfix 初修事实：
- Bugfix 初修完成，覆盖 6 个用户反馈：隐藏 / 重开空搜索、搜索展开时导航关闭搜索、搜索框全区域点击、x/y 位置调整、未授权提示闪烁和实时刷新、统一 ESC 顺序。
- 初修后 `swift build` 通过。
- 初修后 `python3 scripts/smoke_check.py` 通过。
初测结果：
- 测试 Agent Halley 初测通过。
- 手动 UI 未执行。
初审阻塞：
- Review Agent James 结论为 block。
- James block 两个实质问题：点击“全部剪切板”未关闭 / 清空搜索；授权 refresh 未 gated by window visible。
Bugfix rework：
- Bugfix Rework Agent Avicenna 修复上述两个问题。
- 全部剪切板选择路径补齐关闭 / 清空搜索。
- 授权 refresh / pulse 行为补齐窗口可见 gate。
- Rework 后 `swift build` 通过。
- Rework 后 `python3 scripts/smoke_check.py` 通过。
返工后测试：
- 测试 Agent Erdos 完成返工后验证。
- `swift build` 通过。
- `python3 scripts/smoke_check.py` 通过。
- `python3 scripts/verify_sqlite_migration.py` 通过。
- 静态确认全部剪切板关闭搜索。
- 静态确认权限刷新 gate。
- 静态确认 ESC 顺序。
- 静态确认搜索点击不吞按钮。
复审结果：
- Review Agent Godel 复审通过，无阻塞。
- 复审限制验收范围为 HistoryWindow 搜索 / 授权 gate / ESC 改动。
验收结果：
- Acceptance Agent Lovelace 阶段性放行。
- 手动 UI 未验收，不阻塞当前阶段。
- 手动 UI 验收阻塞最终发布。
Backlog 归档：
- 已将“发布前人工 UI 验收：搜索 / 授权 / ESC bugfix”归档到 `docs/V2_OPTIMIZATION_BACKLOG.md`。
主控结论：
- 本 bugfix 返工后阶段性通过。
- 最终发布前必须完成人工 UI 验收。
用户要求：
- 用户已要求修复后主控构建运行 App。
- 主控将在本记录后执行 build-app。
未完成项：
- 人工验证隐藏 / 重开空搜索。
- 人工验证搜索展开时左右键点击全部 / 置顶 / 收藏 / 用户分组。
- 人工验证搜索框全区域点击和按钮位置。
- 人工验证未授权 / 已授权提示闪烁和实时刷新。
- 人工验证 ESC 端到端顺序。
```

## 36. 阶段 6 搜索 / 授权 / ESC bugfix 构建运行记录

```text
调度 ID：V2-DOCS-SEARCH-AUTH-ESC-PACKAGE-001
时间：2026-05-13
阶段：第二版阶段 6 / 搜索、授权状态和 ESC 逻辑 bugfix 返工后测试包
任务卡 ID：V2-DOCS-SEARCH-AUTH-ESC-PACKAGE-001
关联任务：V2-BUGFIX-SEARCH-AUTH-ESC-001 / REWORK
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook，不修改业务代码
构建命令：scripts/build-app.sh --bump none --run
构建结果：
- 构建号从 `1.0.5(260513.2056)` 刷新到 `1.0.5(260513.2203)`。
- `.build/ClipEase.app` 已启动。
- 当前 PID：36250。
用户要求：
- 用户已明确要求“修复完bug，主控Agent需要进行构建运行App，让用户进行测试”。
主控结论：
- 这是 V2-BUGFIX-SEARCH-AUTH-ESC-001 / REWORK 阶段性放行后的用户测试包。
- 构建脚本刷新构建号属于本轮用户明确要求下的执行结果。
未完成项：
- 人工 UI 验收仍需用户侧确认，阻塞最终发布 / 完整验收。
```

## 37. 阶段 6 搜索分组与输入性能 bugfix 调度记录

```text
调度 ID：V2-DOCS-SEARCH-GROUP-PERF-BUGFIX-LOG-001
时间：2026-05-13 22:16:07 CST
阶段：第二版阶段 6 / 搜索分组与输入性能 bugfix 调度记录
任务卡 ID：V2-DOCS-SEARCH-GROUP-PERF-BUGFIX-LOG-001
主控 Agent：Codex 主控 Agent
被调用 Agent：Bugfix Agent
风险等级：低；本记录仅更新 runbook，不修改业务代码
文件锁：
- Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift：Bugfix Agent，任务卡 V2-BUGFIX-SEARCH-GROUP-PERF-001
- Sources/ClipEase/Features/HistoryWindow/HistoryWindowInputState.swift：Bugfix Agent 必要时可用，任务卡 V2-BUGFIX-SEARCH-GROUP-PERF-001
- Sources/ClipEase/Features/HistoryWindow/HistoryWindowController.swift：Bugfix Agent 必要时可用，任务卡 V2-BUGFIX-SEARCH-GROUP-PERF-001
- Sources/ClipEase/Features/HistoryWindow/HistoryPreviewItem.swift：Bugfix Agent 必要时可用，任务卡 V2-BUGFIX-SEARCH-GROUP-PERF-001
用户反馈：
- 当用户在分组里时，点击搜索后要切换到“全部剪切板”并选中。
- 搜索框展开时，搜索框最左侧应该是放大镜图标，最右侧是“x”和筛选按钮。
- 优化搜索框输入性能，用户中文打字时经常卡顿或输入法卡住。
主控判定：
- 归类为阶段 6 搜索交互 bug。
- 第 3 条涉及输入性能和中文输入法，风险中高。
- 先交 Bugfix Agent 做局部修复。
- 如需 SQLite LIKE / FTS 或 Repository 查询改造，则升级架构守门 Agent。
Bugfix 任务卡：
- V2-BUGFIX-SEARCH-GROUP-PERF-001
禁止范围：
- 禁止修改数据层。
- 禁止修改迁移逻辑。
- 禁止修改版本信息。
- 禁止修改构建脚本。
- 禁止修改发布流程。
调度目的：将分组内搜索切换全部剪切板、搜索框图标布局和中文输入性能问题交由 Bugfix Agent 处理。
交付摘要：主控已完成 3 个用户反馈、分诊结论、Bugfix Agent 调度、文件锁和禁改范围记录；未修改业务代码。
验证摘要：仅验证 runbook 写入；未执行构建、测试或 App 运行。
后续动作：Bugfix Agent 完成局部修复后进入测试、审查和验收门禁；若触及 SQLite LIKE / FTS 或 Repository 查询改造，升级架构守门 Agent。
```

## 38. 阶段 6 搜索分组与输入性能 bugfix 测试通过与审查阻塞记录

```text
调度 ID：V2-DOCS-SEARCH-GROUP-PERF-REVIEW-BLOCK-001
时间：2026-05-13
阶段：第二版阶段 6 / 搜索分组与输入性能 bugfix 测试与审查门禁
任务卡 ID：V2-DOCS-SEARCH-GROUP-PERF-REVIEW-BLOCK-001
关联任务：V2-BUGFIX-SEARCH-GROUP-PERF-001
主控 Agent：Codex 主控 Agent
被调用 Agent：测试 Agent Kuhn、审查 Agent Russell、架构守门 Agent、Bugfix Agent
风险等级：低；本记录仅更新 runbook，不修改业务代码
文件锁：
- docs/V2_AGENT_RUNBOOK.md：文档 / 日志 Agent，任务卡 V2-DOCS-SEARCH-GROUP-PERF-REVIEW-BLOCK-001
测试结果：
- Test Agent Kuhn 完成 V2-BUGFIX-SEARCH-GROUP-PERF-001 验证。
- build 通过。
- smoke 通过。
- verify_sqlite_migration 通过。
- 静态验证三条用户反馈通过。
- 未做手动中文 IME 实测。
审查结果：
- Review Agent Russell 不建议验收。
- Review Agent Russell 结论为 block。
审查阻塞原因：
- detached full-scan search work 不会结构化取消；大历史中文输入仍可能堆积 O(n) 扫描。
- Russell 建议升级架构守门 Agent 评估搜索任务取消 / 性能边界。
- 当前工作树存在历史脏改动，需要 Bugfix Agent 提供隔离 diff / 变更清单。
主控结论：
- 暂停验收。
- 暂停打包。
- 调度 Architecture Gatekeeper：V2-ARCH-SEARCH-PERF-CANCELLATION-001。
- 调度 Bugfix 澄清：V2-BUGFIX-SEARCH-GROUP-PERF-001-CLARIFY。
后续动作：
- 架构守门 Agent 评估 detached full-scan 搜索 work 的结构化取消和大历史输入性能风险。
- Bugfix Agent 提供本任务隔离 diff / 变更清单，澄清当前工作树历史脏改动中哪些属于 V2-BUGFIX-SEARCH-GROUP-PERF-001。
- 架构守门和 Bugfix 澄清完成后，再决定是否返工、复审、验收和打包。
未完成项：
- 手动中文 IME 端到端实测。
- 大历史中文输入性能实测。
- 隔离 diff / 变更清单确认。
- 架构守门结论。
```

## 39. 阶段 6 搜索分组与输入性能 bugfix 返工调度记录

```text
调度 ID：V2-DOCS-SEARCH-GROUP-PERF-REWORK-DISPATCH-001
时间：2026-05-13
阶段：第二版阶段 6 / 搜索分组与输入性能 bugfix 返工调度记录
任务卡 ID：V2-DOCS-SEARCH-GROUP-PERF-REWORK-DISPATCH-001
当前会话模式：ClipEase V2 主控 Agent 模式
主控 Agent：Codex 主控 Agent
被调用 Agent：Bugfix Agent
风险等级：低；本记录仅更新 runbook，不修改业务代码
用户本轮 bug：
- 用户在分组里点击搜索后应切到并选中“全部剪切板”。
- 搜索框展开时左侧为放大镜，右侧为 x 和筛选按钮。
- 优化搜索框输入性能，尤其中文输入法卡顿 / 卡住。
既有 bugfix 状态：
- Bugfix V2-BUGFIX-SEARCH-GROUP-PERF-001 已完成初修。
- Test Agent 基本通过。
- Review Agent 阻塞：Task.detached 重过滤不可被外层取消可靠控制，filterItems 缺取消检查，快速输入可能堆积 O(n) 扫描。
- Review Agent 另指出 dirty worktree 需要隔离变更说明。
Architecture Gatekeeper 结论：
- 取消传播问题是当前 bugfix 条件阻塞项。
- 本轮应先做局部 UI / View 层返工。
- 不改 Repository / SQLite / LIKE / FTS。
- 不改变搜索语义。
- SQLite LIKE / FTS 可作为阶段 6 后续架构优化 / 门禁项另行跟踪。
返工调度：
- 主控已调度 Bugfix Agent 执行 V2-BUGFIX-SEARCH-GROUP-PERF-001-REWORK。
文件锁：
- Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift：Bugfix Agent，任务卡 V2-BUGFIX-SEARCH-GROUP-PERF-001-REWORK
禁止范围：
- 禁止 Repository 修改。
- 禁止 SQLite / schema 修改。
- 禁止 LIKE / FTS 搜索下沉。
- 禁止 build / release 相关修改。
调度目的：按 Architecture Gatekeeper 结论先修复 UI / View 层取消传播和输入堆积风险，解除当前 bugfix 的审查阻塞。
交付摘要：主控已记录当前主控会话模式、用户本轮 3 个 bug、初修 / 测试 / 审查阻塞状态、架构守门结论、返工任务和文件锁；未修改业务代码。
验证摘要：仅验证 runbook 写入；未执行构建、测试或 App 运行。
后续动作：Bugfix Agent 完成 V2-BUGFIX-SEARCH-GROUP-PERF-001-REWORK 后进入复测和复审；SQLite LIKE / FTS / 索引化搜索另按阶段 6 后续优化项评估。
```

## 40. 阶段 6 搜索分组与输入性能 bugfix 返工完成记录

```text
调度 ID：V2-DOCS-SEARCH-GROUP-PERF-REWORK-COMPLETE-001
时间：2026-05-13
阶段：第二版阶段 6 / 搜索分组与输入性能 bugfix 返工完成记录
任务卡 ID：V2-DOCS-SEARCH-GROUP-PERF-REWORK-COMPLETE-001
关联任务：V2-BUGFIX-SEARCH-GROUP-PERF-001-REWORK
当前会话模式：ClipEase V2 文档 / 日志 Agent 模式
主控 Agent：Codex 主控 Agent
被调用 Agent：Bugfix Agent、Test Agent、Review Agent
风险等级：低；本记录仅更新 runbook，不修改业务代码
实际修改文件：
- Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift
返工完成状态：
- Bugfix Agent 已完成 V2-BUGFIX-SEARCH-GROUP-PERF-001-REWORK。
返工内容：
- 搜索调度增加 searchGeneration，防止 stale result 写入。
- 后台过滤通过 cancellation handler 显式取消内部任务。
- filterItems 在循环、排序前和返回前检查取消。
- preview rebuild 后台任务补充取消传播。
- 保留搜索切全部剪切板、搜索框左右按钮布局、IME composition 保护和搜索语义。
Bugfix Agent 自测：
- swift build 通过。
- python3 scripts/smoke_check.py 通过。
- 未运行 packaging。
当前门禁状态：
- 已调度 Test Agent V2-TEST-SEARCH-GROUP-PERF-001-REWORK，等待结果。
- 已调度 Review Agent V2-REVIEW-SEARCH-GROUP-PERF-001-REWORK，等待结果。
- Test Agent 和 Review Agent 通过后仍需 Acceptance Agent 放行。
后续动作：等待 V2-TEST-SEARCH-GROUP-PERF-001-REWORK 和 V2-REVIEW-SEARCH-GROUP-PERF-001-REWORK 结果；全部通过后进入 Acceptance Agent 放行。
```

## 41. 阶段 6 搜索分组与输入性能 bugfix 返工复测 / 复审记录

```text
调度 ID：V2-DOCS-SEARCH-GROUP-PERF-REVIEW-PASS-001
时间：2026-05-13
阶段：第二版阶段 6 / 搜索分组与输入性能 bugfix 返工复测和复审记录
任务卡 ID：V2-DOCS-SEARCH-GROUP-PERF-REVIEW-PASS-001
关联任务：V2-BUGFIX-SEARCH-GROUP-PERF-001-REWORK
当前会话模式：ClipEase V2 文档 / 日志 Agent 模式
主控 Agent：Codex 主控 Agent
被调用 Agent：Test Agent、Review Agent、Acceptance Agent
风险等级：低；本记录仅更新 runbook，不修改业务代码
Test Agent 结果：
- V2-TEST-SEARCH-GROUP-PERF-001-REWORK 通过。
- swift build 通过。
- python3 scripts/smoke_check.py 通过。
- python3 scripts/verify_sqlite_migration.py 通过。
- 静态检查通过：搜索时切到全部剪切板、搜索框布局、IME composition guard、search cancellation / stale guard。
- 未完成项：真实中文 IME 和 UI 点击视觉仍为人工待验。
Review Agent 结果：
- V2-REVIEW-SEARCH-GROUP-PERF-001-REWORK：PASS。
- 上一轮 search filtering 取消传播阻塞项已解决。
Review 非阻塞发现：
- P2：HistoryWindowView.swift 的 preview rebuild 仍可能在极窄 MainActor.run 等待窗口写入旧 allPreviewItems。
- 建议后续也为 preview rebuild 增加 generation / stale guard。
- 当前 search result 写回已有 generation guard；该 P2 不阻塞当前 bugfix。
当前门禁状态：
- 已调度 Acceptance Agent V2-ACCEPT-SEARCH-GROUP-PERF-001-REWORK，等待人工验收 / 放行结果。
后续动作：等待 V2-ACCEPT-SEARCH-GROUP-PERF-001-REWORK；真实中文 IME 和 UI 点击视觉需由人工实机验证。
```

## 42. 阶段 6 搜索分组与输入性能 bugfix 用户授权 build-run 记录

```text
调度 ID：V2-DOCS-SEARCH-GROUP-PERF-BUILD-RUN-001
时间：2026-05-13
阶段：第二版阶段 6 / 搜索分组与输入性能 bugfix 用户授权 build-run 记录
任务卡 ID：V2-DOCS-SEARCH-GROUP-PERF-BUILD-RUN-001
关联任务：V2-BUGFIX-SEARCH-GROUP-PERF-001-REWORK
当前会话模式：ClipEase V2 文档 / 日志 Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook，不修改业务代码
用户授权：
- 用户明确指令：“请构建运行App让我进行测试”。
门禁状态：
- V2-BUGFIX-SEARCH-GROUP-PERF-001-REWORK 已通过 Test / Review / Acceptance。
主控执行：
- 主控 Agent 已执行 scripts/build-app.sh --bump none --run，供用户进行人工 UI 验收。
build-run 结果：
- 版本 / 构建号：1.0.5 (260513.2203) -> 1.0.5 (260513.2234)
- 构建成功：Build of product 'ClipEase' complete!
- App 路径：/Users/wpc/code/codex/ClipboardHistory/.build/ClipEase.app
- 已启动进程：PID 76130
- 可执行文件：/Users/wpc/code/codex/ClipboardHistory/.build/ClipEase.app/Contents/MacOS/ClipEase
仍需人工验证项：
- 真实中文 IME 连续输入。
- 分组内点击搜索后选中“全部剪切板”。
- 搜索框左放大镜右 x/filter。
- 搜索筛选 popover / 清空 / Esc / Command-F 冒烟。
交付摘要：文档 Agent 已追加用户授权 build-run 记录；未修改业务代码，未运行构建，未回退任何改动。
```

## 43. 阶段 6 搜索分组与输入性能 bugfix 用户人工验收通过记录

```text
调度 ID：V2-DOCS-SEARCH-GROUP-PERF-USER-ACCEPTED-001
时间：2026-05-13
阶段：第二版阶段 6 / 搜索分组与输入性能 bugfix 用户人工验收通过记录
任务卡 ID：V2-DOCS-SEARCH-GROUP-PERF-USER-ACCEPTED-001
关联任务：V2-BUGFIX-SEARCH-GROUP-PERF-001-REWORK
当前会话模式：ClipEase V2 文档 / 日志 Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook，不修改业务代码
用户验收环境：
- 用户在运行 1.0.5 (260513.2234) 后完成本轮 build-run 人工 UI 测试。
用户反馈：
- 用户反馈：“没问题”。
门禁状态：
- V2-BUGFIX-SEARCH-GROUP-PERF-001-REWORK 已通过 Test / Review / Acceptance / 用户人工 UI 验收。
归档结论：
- 本轮搜索分组与中文输入性能 bugfix 可以归档为已完成。
非阻塞 backlog：
- preview rebuild generation / stale guard P2。
- SQLite LIKE / FTS / 索引化搜索评估。
交付摘要：文档 Agent 已追加用户人工 UI 验收通过记录；未修改业务代码，未运行构建，未回退任何改动。
```

## 44. 阶段 6 搜索能力收口继续推进调度记录

```text
调度 ID：V2-DOCS-STAGE6-SEARCH-CLOSEOUT-DISPATCH-001
时间：2026-05-13
阶段：第二版阶段 6 / 搜索能力收口继续推进
任务卡 ID：V2-DOCS-STAGE6-SEARCH-CLOSEOUT-DISPATCH-001
当前会话模式：ClipEase V2 文档 / 日志 Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook，不修改业务代码
推进背景：
- 用户确认上一轮搜索 bugfix 测试“没问题”后，指令“好的，请推进阶段6”。
- 阶段 6 继续推进，当前收口重点：搜索能力、搜索性能、分组 / 收藏 / 置顶联动稳定性。
已调度 Bugfix Agent：
- 任务 ID：V2-BUGFIX-PREVIEW-REBUILD-STALE-GUARD-001。
- 处理范围：P2 preview rebuild generation / stale guard。
- 文件锁：Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift。
- 禁止范围：Repository / SQLite / schema / build / release 修改。
已调度 Architecture Gatekeeper：
- 任务 ID：V2-ARCH-STAGE6-SEARCH-INDEXED-PERF-001。
- 评估范围：大历史量 SQLite LIKE / FTS / 索引化搜索是否阶段 6 必须实施。
- 当前约束：只评估，不改代码。
后续门禁：
- Bugfix 完成后需 Test / Review / Acceptance。
- 架构结论若涉及 schema / migration / repository，需用户确认红线后才能实施。
交付摘要：文档 Agent 已追加阶段 6 搜索能力收口继续推进调度记录；未修改业务代码，未运行构建，未回退任何改动。
```

## 45. 阶段 6 搜索能力收口结果记录

```text
调度 ID：V2-DOCS-STAGE6-SEARCH-CLOSEOUT-RESULTS-001
时间：2026-05-13
阶段：第二版阶段 6 / 搜索能力收口结果记录
任务卡 ID：V2-DOCS-STAGE6-SEARCH-CLOSEOUT-RESULTS-001
当前会话模式：ClipEase V2 文档 / 日志 Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook，不修改业务代码
关联 Bugfix 任务：
- V2-BUGFIX-PREVIEW-REBUILD-STALE-GUARD-001
Bugfix 完成事实：
- Bugfix Agent 已完成 V2-BUGFIX-PREVIEW-REBUILD-STALE-GUARD-001。
- 修改文件：Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift。
- 新增 previewBuildGeneration。
- 每次 preview rebuild 取消旧任务并递增 generation。
- 主线程写回 allPreviewItems 前检查 `!Task.isCancelled && previewBuildGeneration == generation`。
- 窗口消失取消 preview rebuild 时也递增 generation，避免旧任务在极窄时序下回写 stale preview。
Bugfix 验证记录：
- `swift build` 通过。
- `python3 scripts/smoke_check.py` 失败于 release candidate report 与当前版本 `1.0.5(260513.2234)` 不一致。
- smoke 失败归类：文档 / 发布报告对齐问题，不是本次业务代码失败。
Architecture Gatekeeper 结论：
- 任务 ID：V2-ARCH-STAGE6-SEARCH-INDEXED-PERF-001。
- SQLite LIKE / FTS / 索引化搜索可暂缓，不建议作为阶段 6 必须实施。
- 阶段 6 以 View 层搜索修复收口。
- 数据层索引搜索作为阶段 7 / 后续优化专项。
- 数据红线包括 schema version、FTS 表、迁移、备份恢复、发布流程等；进入实施前需单独评审并确认红线。
后续动作：
- 需先同步 release candidate report 到 `1.0.5(260513.2234)` 后复跑 smoke。
- V2-BUGFIX-PREVIEW-REBUILD-STALE-GUARD-001 仍需 Test / Review / Acceptance。
交付摘要：文档 Agent 已追加阶段 6 搜索能力收口结果记录；未修改业务代码，未运行构建，未回退任何改动。
```

## 46. Preview rebuild stale guard 测试与评审调度记录

```text
调度 ID：V2-DOCS-PREVIEW-REBUILD-GUARD-TEST-REVIEW-DISPATCH-001
时间：2026-05-13
阶段：第二版阶段 6 / preview rebuild stale guard 门禁推进
任务卡 ID：V2-DOCS-PREVIEW-REBUILD-GUARD-TEST-REVIEW-DISPATCH-001
当前会话模式：ClipEase V2 文档 / 日志 Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook，不修改业务代码
前置状态：
- RC report 已由文档 Agent 对齐到 `1.0.5(260513.2234)`，解除 preview guard bugfix smoke_check 的文档前置失败。
已调度 Test Agent：
- 任务 ID：V2-TEST-PREVIEW-REBUILD-STALE-GUARD-001。
- 验证范围：运行 `swift build`、`smoke_check.py`、`verify_sqlite_migration.py`。
- 静态检查 preview build generation / stale guard。
已调度 Review Agent：
- 任务 ID：V2-REVIEW-PREVIEW-REBUILD-STALE-GUARD-001。
- 审查 stale 写回窗口、generation / cancellation 逻辑、语义保持和越权修改。
后续门禁：
- Test / Review 通过后需 Acceptance Agent 放行。
交付摘要：文档 Agent 已追加 preview rebuild stale guard 测试与评审调度记录；未修改业务代码，未运行构建，未回退任何改动。
```

## 47. Preview rebuild stale guard 测试与评审结果记录

```text
调度 ID：V2-DOCS-PREVIEW-REBUILD-GUARD-TEST-REVIEW-RESULTS-001
时间：2026-05-13
阶段：第二版阶段 6 / preview rebuild stale guard 门禁结果
任务卡 ID：V2-DOCS-PREVIEW-REBUILD-GUARD-TEST-REVIEW-RESULTS-001
当前会话模式：ClipEase V2 文档 / 日志 Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook，不修改业务代码
关联 Bugfix 任务：
- V2-BUGFIX-PREVIEW-REBUILD-STALE-GUARD-001
Test Agent 结果：
- 任务 ID：V2-TEST-PREVIEW-REBUILD-STALE-GUARD-001。
- `swift build` 通过。
- `python3 scripts/smoke_check.py` 通过。
- `python3 scripts/verify_sqlite_migration.py` 通过。
- RC report 匹配 `1.0.5(260513.2234)`。
- 静态检查通过：`previewBuildGeneration`、写回前 stale guard、`.onDisappear` generation 失效。
- 未发现阻塞问题。
Review Agent 结果：
- 任务 ID：V2-REVIEW-PREVIEW-REBUILD-STALE-GUARD-001。
- 审查结论：PASS。
- stale preview 写回已关闭。
- 旧 source 不再触发搜索刷新。
- 未发现语义、排序、IME、searchGeneration 破坏。
- 工作区脏状态仍属 V2 主线背景，但未阻塞本修复。
主控调度：
- 主控已调度 Acceptance Agent `V2-ACCEPT-PREVIEW-REBUILD-STALE-GUARD-001`。
后续动作：
- 等待 Acceptance Agent 放行结果；通过后可将 preview rebuild stale guard 优化项归档关闭。
交付摘要：文档 Agent 已追加 preview rebuild stale guard 测试与评审结果记录；未修改业务代码，未运行构建，未回退任何改动。
```

## 48. Preview rebuild stale guard Acceptance PASS 与归档记录

```text
调度 ID：V2-DOCS-PREVIEW-REBUILD-GUARD-ACCEPTED-001
时间：2026-05-13
阶段：第二版阶段 6 / preview rebuild stale guard Acceptance PASS 与归档
任务卡 ID：V2-DOCS-PREVIEW-REBUILD-GUARD-ACCEPTED-001
当前会话模式：ClipEase V2 文档 / 日志 Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook，不修改业务代码
关联 Bugfix 任务：
- V2-BUGFIX-PREVIEW-REBUILD-STALE-GUARD-001
Acceptance Agent 结果：
- 任务 ID：V2-ACCEPT-PREVIEW-REBUILD-STALE-GUARD-001。
- 验收结论：PASS。
门禁结论：
- V2-BUGFIX-PREVIEW-REBUILD-STALE-GUARD-001 已通过 Test / Review / Acceptance。
- Preview rebuild P2 已完成，可从阶段 6 阻塞 / 待办中移除。
- 阶段 6 不再存在必须本阶段实施的搜索架构阻塞项。
归档结论：
- V2-BUGFIX-PREVIEW-REBUILD-STALE-GUARD-001 可归档完成。
- V2-OPT-HISTORY-PREVIEW-REBUILD-GENERATION-GUARD-001 更新为已完成 / 已归档。
后续归属：
- SQLite LIKE / FTS / Repository 查询下沉归入阶段 7 / 后续专项。
- 大历史量性能验证保留为非阻塞观察项。
交付摘要：文档 Agent 已追加 Acceptance PASS 与归档记录，并同步优化 Backlog 状态；未修改业务代码，未运行构建，未回退任何改动。
```

## 49. 阶段 6 总回归与放行检查调度记录

```text
调度 ID：V2-DOCS-STAGE6-CLOSEOUT-REGRESSION-DISPATCH-001
时间：2026-05-13
阶段：第二版阶段 6 / 总回归与放行检查
任务卡 ID：V2-DOCS-STAGE6-CLOSEOUT-REGRESSION-DISPATCH-001
当前会话模式：ClipEase V2 文档 / 日志 Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook，不修改业务代码
用户指令：
- “好的，请继续推进项目”。
主控状态：
- 主控进入阶段 6 总回归与放行检查。
当前阶段 6 搜索技术阻塞状态：
- 搜索分组 / 输入性能 bugfix 用户验收通过。
- Preview rebuild stale guard 已 Test / Review / Acceptance PASS 并归档。
- SQLite LIKE / FTS 不阻塞阶段 6，转阶段 7 / 后续专项。
已调度 Test Agent：
- 任务 ID：V2-TEST-STAGE6-SEARCH-CLOSEOUT-REGRESSION-001。
已调度 Review Agent：
- 任务 ID：V2-REVIEW-STAGE6-SEARCH-CLOSEOUT-001。
后续动作：
- 若 Test / Review 通过，将调度 Acceptance Agent 做阶段 6 放行判断。
- 若发现红线风险，则先向用户确认。
交付摘要：文档 Agent 已追加阶段 6 总回归与放行检查调度记录；未修改业务代码，未运行构建，未回退任何改动。
```

## 50. 阶段 6 总回归 Test PASS 但 Review HOLD 记录

```text
调度 ID：V2-DOCS-STAGE6-CLOSEOUT-HOLD-001
时间：2026-05-13
阶段：第二版阶段 6 / 总回归收口 HOLD
任务卡 ID：V2-DOCS-STAGE6-CLOSEOUT-HOLD-001
当前会话模式：ClipEase V2 文档 / 日志 Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook，不修改业务代码
总回归结果：
- Test Agent 阶段 6 总回归结论：PASS。
- Review Agent `V2-REVIEW-STAGE6-SEARCH-CLOSEOUT-001` 结论：HOLD。
Review HOLD 发现：
- HOLD / 红线确认：默认仓储已切到 SQLite，并会在启动时触发迁移。文件位置摘要：`Sources/ClipEase/Core/Storage/ClipboardHistoryRepository.swift` 中 `ClipboardHistoryRepository.current()` 默认 `.sqlite`；`Sources/ClipEase/Core/Storage/ClipboardHistoryPersistence.swift` 构造 `SQLiteClipboardStore`；`Sources/ClipEase/App/AppDelegate.swift` 启动检查迁移进度。风险：release/schema 红线；阶段 6 收口前必须确认这是已批准主线改动，否则不得放行。
- P1：异步 search completion 会覆盖合法 selection restore。文件位置摘要：`Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift`；preview rebuild 后先 schedule search update 再 restore selection，但 search task 完成后 `ensureSelectionInFilteredItems()` 总是重置到第一项，可能覆盖合法选中项。风险：用户可见的选中项恢复竞态与预览错位。
主控调度：
- 主控已调度 Bugfix Agent `V2-BUGFIX-STAGE6-SELECTION-RESTORE-RACE-001` 修复 P1。
- 文件锁：`Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift`。
- 禁止修改 Repository / SQLite / schema / release / build 相关内容。
红线处理：
- SQLite 默认仓储 / 启动迁移红线项需要主控核对文档并向用户确认。
- 用户确认前不得阶段 6 Acceptance 放行。
后续动作：
- 等待 Bugfix Agent 修复 P1 并通过对应 Test / Review。
- 等待主控完成 SQLite 默认仓储与启动迁移红线确认。
交付摘要：文档 Agent 已追加阶段 6 总回归 Test PASS 但 Review HOLD 记录；未修改业务代码，未运行构建，未回退任何改动。
```

## 51. 阶段 6 selection restore race Bugfix 完成与复核调度记录

```text
调度 ID：V2-DOCS-STAGE6-SELECTION-RESTORE-RACE-FIX-001
时间：2026-05-13
阶段：第二版阶段 6 / selection restore race Bugfix 完成与复核调度
任务卡 ID：V2-DOCS-STAGE6-SELECTION-RESTORE-RACE-FIX-001
当前会话模式：ClipEase V2 文档 / 日志 Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook，不修改业务代码
Bugfix Agent：
- 任务 ID：V2-BUGFIX-STAGE6-SELECTION-RESTORE-RACE-001。
- 结论：已完成。
修改文件：
- `Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift`。
修复内容：
- `ensureSelectionInFilteredItems()` 先检查当前 `selectedItemID` 是否仍在 `filteredItems`。
- 若当前选择仍存在，则保留当前选择并按需同步 preview。
- 若当前选择不存在，才回退到第一项。
- 未改搜索语义、排序、筛选、generation guard、IME 或快捷键。
Bugfix 自测：
- `swift build` 通过。
- `python3 scripts/smoke_check.py` 通过。
主控后续调度：
- 已调度 Test Agent `V2-TEST-STAGE6-SELECTION-RESTORE-RACE-001`。
- 已调度 Review Agent `V2-REVIEW-STAGE6-CLOSEOUT-HOLD-RECHECK-001`。
主控文档核对结论摘要：
- SQLite 默认主存储 / 启动迁移在 V2 阶段 1-3 runbook 和计划文档已有主线记录。
- 待 Review 复核是否足以解除本轮 HOLD。
交付摘要：文档 Agent 已追加 selection restore race Bugfix 完成与复核调度记录；未修改业务代码，未运行构建，未回退任何改动。
```

## 52. 阶段 6 closeout Acceptance 调度记录

```text
调度 ID：V2-DOCS-STAGE6-CLOSEOUT-ACCEPT-DISPATCH-001
时间：2026-05-13
阶段：第二版阶段 6 / closeout Acceptance 调度
任务卡 ID：V2-DOCS-STAGE6-CLOSEOUT-ACCEPT-DISPATCH-001
当前会话模式：ClipEase V2 文档 / 日志 Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook，不修改业务代码
Test Agent：
- 任务 ID：V2-TEST-STAGE6-SELECTION-RESTORE-RACE-001。
- 结论：PASS。
- `swift build` 通过。
- `smoke_check.py` 通过。
- `verify_sqlite_migration.py` 通过。
- selection restore race 静态验证通过。
Review Agent：
- 任务 ID：V2-REVIEW-STAGE6-CLOSEOUT-HOLD-RECHECK-001。
- 结论：PASS。
- P1 已解决。
- SQLite 默认仓储 / 启动迁移 HOLD 降级为既有 V2 主线已批准，阶段 6 放行报告需引用，不要求本轮当场再确认。
主控后续调度：
- 主控已调度 Acceptance Agent `V2-ACCEPT-STAGE6-SEARCH-CLOSEOUT-001` 做阶段 6 搜索能力放行判断。
交付摘要：文档 Agent 已追加阶段 6 closeout Acceptance 调度记录；未修改业务代码，未运行构建，未回退任何改动。
```

## 53. 阶段 6 Acceptance PASS 最终记录

```text
调度 ID：V2-DOCS-STAGE6-ACCEPTANCE-PASS-RC-SYNC-001
时间：2026-05-13
阶段：第二版阶段 6 / 搜索能力 Acceptance PASS 最终记录
任务卡 ID：V2-DOCS-STAGE6-ACCEPTANCE-PASS-RC-SYNC-001
当前会话模式：ClipEase V2 文档 / 日志 Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook 和 RC report，不修改业务代码
Acceptance Agent：
- 任务 ID：V2-ACCEPT-STAGE6-SEARCH-CLOSEOUT-001。
- 验收结论：PASS。
阶段 6 放行结论：
- 阶段 6 搜索能力已通过 Test / Review / Acceptance，可以按当前 RC 状态放行。
- 当前无阶段 6 搜索放行阻塞项。
- 当前无新增红线需用户额外确认。
- SQLite 默认仓储 / 启动迁移已按既有 V2 主线批准处理，不作为本轮阶段 6 搜索放行阻塞项。
后续归属：
- SQLite LIKE / FTS / Repository 查询下沉转入阶段 7 / 后续专项，不作为阶段 6 必须实施内容。
- 大历史量搜索性能仍保留为后续风险观察项，后续需结合真实历史量、索引化搜索方案和性能门禁继续评估。
RC 文档同步：
- `docs/RELEASE_CANDIDATE_REPORT.md` 需同步 preview rebuild stale guard 已通过 Test / Review / Acceptance 并归档。
- RC 报告只表达当前 RC 状态，不声称最终正式发布完成。
交付摘要：文档 Agent 已追加阶段 6 Acceptance PASS 最终记录，并同步 RC report 当前状态；未修改业务代码，未运行构建，未回退任何改动。
```

## 54. 阶段 6 PASS 后继续推进边界记录

```text
调度 ID：V2-DOCS-PROJECT-CONTINUE-AFTER-STAGE6-001
时间：2026-05-13
阶段：第二版阶段 6 PASS 后 / 后续专项规划前置记录
任务卡 ID：V2-DOCS-PROJECT-CONTINUE-AFTER-STAGE6-001
当前会话模式：ClipEase V2 文档 / 日志 Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook，不修改业务代码
用户指令：
- 用户在阶段 6 Acceptance PASS 后要求：“好的，继续推进项目”。
当前状态：
- 阶段 6 搜索能力已 Acceptance PASS / 可放行。
- 当前无阶段 6 搜索阻塞项。
- SQLite LIKE / FTS / Repository 查询下沉已转阶段 7 / 后续专项。
主控下一步：
- 核对计划文档中的阶段 7 / 后续专项边界。
- 调度架构、产品规则、测试计划 Agent 做预研。
- 任何 schema / migration / Repository 实施前，需先向用户确认红线。
交付摘要：文档 Agent 已追加阶段 6 PASS 后继续推进边界记录；未修改业务代码，未运行构建，未回退任何改动。
```

## 55. 阶段 7 主线路由澄清记录

```text
调度 ID：V2-DOCS-STAGE7-ROUTING-CLARIFY-001
时间：2026-05-13
阶段：第二版阶段 7 / 主线路由澄清
任务卡 ID：V2-DOCS-STAGE7-ROUTING-CLARIFY-001
当前会话模式：ClipEase V2 文档 / 日志 Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook、优化 backlog 和计划旁注，不修改业务代码
路由结论：
- 阶段 6 已 Acceptance PASS，正式主线进入 `docs/V2_DEVELOPMENT_PLAN.md` 中的阶段 7：编辑、快捷键和批量管理。
- `V2-OPT-SEARCH-SQLITE-LIKE-FTS-INDEXED-PERF-001` 不是正式阶段 7 主线任务。
- SQLite LIKE / FTS / Repository 查询下沉保留为搜索性能专项，可与阶段 7 并行预研，但分门禁管理。
- 搜索性能专项实施前必须独立确认 schema / Repository / migration / FTS / 回滚 / 发布流程等红线，不得抢占阶段 7 主线。
架构预研摘要：
- 阶段 7 主线不需要先改 Repository / SQLite schema。
- SQLite LIKE / FTS / 索引化搜索属于大历史量搜索性能方向，仍需结合查询语义、迁移策略、数据备份恢复和性能指标独立评审。
- 未经独立红线确认，不改 schema、Repository 查询 API 或 migration。
产品预研摘要：
- 阶段 7 第一批应围绕可编辑文本 / 链接 / 颜色、常用快捷键、管理模式和批量操作体验收口。
- 搜索性能专项不改变阶段 7 的产品定义，也不应将“阶段 7”命名为搜索专项。
- 批量删除、批量导出、撤销表现和颜色卡片快捷键覆盖范围仍需用户确认后再拆实施任务。
测试预研摘要：
- 阶段 7 主线测试重点应覆盖编辑保存后原记录状态保留、快捷键一致性、多选 / 批量操作确认与撤销、右键菜单显示和主窗口交互回归。
- 搜索性能专项若进入实施，需另起性能门禁，覆盖大历史量、中文 IME、取消传播、CPU 占用和迁移回滚验证。
- 两条线测试报告需分开归档，避免以搜索性能结果替代阶段 7 主线验收。
阶段 7 启动前仍需用户确认的产品问题：
- 富文本编辑是否进入阶段 7 首批。
- 批量导出是否进入阶段 7 首批。
- 批量删除撤销是否需要逐条动画。
- `Command + E` 是否覆盖颜色卡片。
文档同步：
- `docs/V2_OPTIMIZATION_BACKLOG.md` 已澄清 `V2-OPT-SEARCH-SQLITE-LIKE-FTS-INDEXED-PERF-001` 为并行搜索性能专项，而非正式阶段 7 主线。
- `docs/V2_DEVELOPMENT_PLAN.md` 阶段 7 已追加轻量旁注，避免阶段 7 与搜索性能专项命名混淆。
交付摘要：文档 Agent 已追加阶段 7 主线路由澄清记录，并同步优化 backlog / 开发计划旁注；未修改业务代码，未运行构建，未回退任何改动。
```

## 56. 阶段 7 第一批用户确认与启动记录

```text
调度 ID：V2-DOCS-STAGE7-FIRST-BATCH-CONFIRM-DISPATCH-001
时间：2026-05-13
阶段：第二版阶段 7 / 第一批编辑闭环启动
任务卡 ID：V2-DOCS-STAGE7-FIRST-BATCH-CONFIRM-DISPATCH-001
当前会话模式：ClipEase V2 文档 / 日志 Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook 和优化 backlog，不修改业务代码
用户确认：
- 用户已确认“按建议确认，开始阶段7第一批”。
- 用户追问“不进第一批你会放在哪里去做？”后，主控已明确后续归属。
阶段 7 第一批确认范围：
- 文本、链接、颜色单条编辑闭环。
- 图片不显示编辑入口。
- `Command + E` 覆盖文本、链接、颜色。
阶段 7 第一批禁改范围：
- 不做富文本编辑。
- 不做批量导出。
- 不做逐条撤销动画。
- 不做批量删除。
- 不做 schema / migration / backup / release。
后续专项归属：
- 富文本编辑：放入阶段 7 后续“富文本回编专项”。
- 批量导出：放入阶段 7 后续“批量管理增强”。
- 逐条撤销动画：放入阶段 7 后续“批量撤销体验打磨”。
- 搜索性能 LIKE / FTS / Repository 查询下沉：仍为并行搜索性能专项，独立门禁，不阻塞阶段 7 第一批。
主控调度：
- 主控已调度 `V2-S7-EDIT-MIN-CLOSED-LOOP-001` 进入阶段 7 第一批实施。
文件锁：
- `Sources/ClipEase/UI/HistoryWindow/`：阶段 7 第一批实现 Agent，任务卡 `V2-S7-EDIT-MIN-CLOSED-LOOP-001`，仅限文本 / 链接 / 颜色编辑入口、编辑态和快捷键相关视图改动。
- `Sources/ClipEase/Core/Models/`：阶段 7 第一批实现 Agent按需读取 / 最小修改，任务卡 `V2-S7-EDIT-MIN-CLOSED-LOOP-001`，不得引入 schema / migration 变更。
- `Sources/ClipEase/Core/Storage/`：默认只读锁；如需保存路径适配，必须限定在现有字段更新，不得改 schema、migration、backup 或 release 流程。
- `docs/V2_AGENT_RUNBOOK.md`、`docs/V2_OPTIMIZATION_BACKLOG.md`：文档 / 日志 Agent，任务卡 `V2-DOCS-STAGE7-FIRST-BATCH-CONFIRM-DISPATCH-001`。
门禁要求：
- Test Agent 需覆盖文本 / 链接 / 颜色单条编辑保存闭环、取消编辑、图片无编辑入口、`Command + E` 对三类可编辑项生效且不误触图片。
- Review Agent 需重点复核编辑保存是否保留原记录状态、是否越界修改富文本 / 图片 / 批量管理 / 数据 schema，以及快捷键路由是否与现有交互冲突。
- Acceptance Agent 需在 Test / Review PASS 后确认阶段 7 第一批范围放行；富文本回编、批量导出、逐条撤销动画和搜索性能专项不得混入第一批验收。
交付摘要：文档 Agent 已追加用户确认、阶段 7 第一批启动、主控调度、文件锁、禁改范围和后续 Test / Review / Acceptance 门禁记录；未修改业务代码，未运行构建，未回退任何改动。
```

## 57. 阶段 7 第一批编辑闭环开发完成记录

```text
调度 ID：V2-DOCS-S7-EDIT-MIN-CLOSED-LOOP-COMPLETE-001
时间：2026-05-13
阶段：第二版阶段 7 / 第一批编辑闭环开发完成
任务卡 ID：V2-DOCS-S7-EDIT-MIN-CLOSED-LOOP-COMPLETE-001
当前会话模式：ClipEase V2 文档 / 日志 Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook，不修改业务代码
开发任务状态：
- `V2-S7-EDIT-MIN-CLOSED-LOOP-001` 已完成开发。
修改文件：
- `ClipboardItem.swift`
- `ClipboardHistoryStore.swift`
- `HistoryWindowView.swift`
实现内容：
- 文本 / 链接 / 颜色支持单条编辑入口。
- 图片不可编辑。
- `Command + E` 覆盖文本 / 链接 / 颜色。
- Store 新增 `updateEditableContent(for:text:)`。
- 编辑更新原记录，不新增历史。
- 编辑保存保留原记录状态。
- 链接保存前执行 URL 校验，保存后复制。
- 颜色 HEX 执行规范化。
- 编辑后重建 `recentHashes`。
- 未新增 schema / `lastEditedAt`。
用户确认 deferred items 未实现：
- 富文本编辑。
- 批量导出。
- 批量删除 / 撤销。
- 逐条撤销动画。
开发自测：
- `swift build` 通过。
- `smoke_check.py` 通过。
- `verify_sqlite_migration.py` 通过。
后续调度：
- 主控已调度 Test Agent `V2-TEST-S7-EDIT-MIN-CLOSED-LOOP-001`。
- 主控已调度 Review Agent `V2-REVIEW-S7-EDIT-MIN-CLOSED-LOOP-001`。
交付摘要：文档 Agent 已追加阶段 7 第一批编辑闭环开发完成记录；未修改业务代码，未运行构建，未回退任何改动。
```

## 58. 阶段 7 第一批编辑闭环 Review HOLD 与返工调度记录

```text
调度 ID：V2-DOCS-S7-EDIT-COMMANDE-HOLD-001
时间：2026-05-13
阶段：第二版阶段 7 / 第一批编辑闭环 Review HOLD 与返工调度
任务卡 ID：V2-DOCS-S7-EDIT-COMMANDE-HOLD-001
当前会话模式：ClipEase V2 文档 / 日志 Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook，不修改业务代码
Test Agent 结果：
- Test Agent `V2-TEST-S7-EDIT-MIN-CLOSED-LOOP-001` 自动门禁通过。
- `swift build` 通过。
- `smoke_check.py` 通过。
- `verify_sqlite_migration.py` 通过。
- 功能静态检查通过。
- 因工作区存在既有禁止范围改动，按工作区归因 BLOCKED。
Review Agent 结果：
- Review Agent `V2-REVIEW-S7-EDIT-MIN-CLOSED-LOOP-001` 给出 HOLD。
- 真实 P1：`Command + E` 全局隐藏快捷键在搜索框或编辑 sheet 输入焦点中也会触发。
- 风险：输入焦点内误触 `Command + E` 可能重开编辑并丢弃未保存内容。
Review 非阻塞确认：
- 编辑更新原记录通过。
- 保存保留原记录状态通过。
- 富文本 / 图片排除通过。
- URL 校验通过。
- 链接异步标题 guard 通过。
- 颜色 HEX 规范化通过。
- 保存后复制链接通过。
- 工作区 dirty V2 主线改动按既有背景处理。
返工调度：
- 主控已调度 Bugfix Agent `V2-BUGFIX-S7-EDIT-COMMANDE-FOCUS-GUARD-001`。
- 文件锁：`HistoryWindowView.swift`。
- 禁止修改 Store / Model / schema / migration / backup / release 等范围。
后续门禁：
- Bugfix Agent 需修复 `Command + E` 在搜索框 / 编辑 sheet 输入焦点中的误触发问题。
- Test / Review 需复核快捷键焦点 guard，不扩大阶段 7 第一批范围。
交付摘要：文档 Agent 已追加阶段 7 第一批编辑闭环 Review HOLD、P1 原因、Test 门禁背景和 Bugfix 返工调度记录；未修改业务代码，未运行构建，未回退任何改动。
```

## 59. 阶段 7 第一批编辑闭环 Command+E 焦点 Guard Bugfix 完成记录

```text
调度 ID：V2-DOCS-S7-EDIT-COMMANDE-FOCUS-GUARD-COMPLETE-001
时间：2026-05-14
阶段：第二版阶段 7 / 第一批编辑闭环 Command+E 焦点 Guard Bugfix 完成
任务卡 ID：V2-DOCS-S7-EDIT-COMMANDE-FOCUS-GUARD-COMPLETE-001
当前会话模式：ClipEase V2 文档 / 日志 Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook，不修改业务代码
Bugfix Agent 结果：
- Bugfix Agent `V2-BUGFIX-S7-EDIT-COMMANDE-FOCUS-GUARD-001` 已完成。
修改文件：
- `HistoryWindowView.swift`
修复内容：
- `Command + E` 改走 `handleEditShortcut()`。
- `canEditSelectedItemFromShortcut` 限制主列表 / 卡片语境。
- 编辑 sheet、搜索框、筛选 popover、分组重命名、AppKit 文本编辑器聚焦时不触发编辑快捷键。
- `beginEditItem` 防重入，避免重置 `editText`。
开发自测：
- `swift build` 通过。
- `smoke_check.py` 通过。
后续调度：
- 主控已调度 Test Agent `V2-TEST-S7-EDIT-COMMANDE-FOCUS-GUARD-001`。
- 主控已调度 Review Agent `V2-REVIEW-S7-EDIT-COMMANDE-FOCUS-GUARD-001`。
交付摘要：文档 Agent 已追加阶段 7 第一批编辑闭环 Command+E 焦点 Guard Bugfix 完成记录；未修改业务代码，未运行构建，未回退任何改动。
```

## 60. 阶段 7 第一批编辑闭环 Command+E 焦点 Guard 复测 Review PASS 记录

```text
调度 ID：V2-DOCS-S7-EDIT-COMMANDE-RETEST-REVIEW-PASS-001
时间：2026-05-14
阶段：第二版阶段 7 / 第一批编辑闭环 Command+E 焦点 Guard 复测与 Review PASS
任务卡 ID：V2-DOCS-S7-EDIT-COMMANDE-RETEST-REVIEW-PASS-001
当前会话模式：ClipEase V2 文档 / 日志 Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook，不修改业务代码
Test Agent 结果：
- Test Agent `V2-TEST-S7-EDIT-COMMANDE-FOCUS-GUARD-001` PASS。
- `swift build` 通过。
- `smoke_check.py` 通过。
- `verify_sqlite_migration.py` 通过。
- Command+E guard 静态检查通过。
- 人工 UI 待验项保留。
Review Agent 结果：
- Review Agent `V2-REVIEW-S7-EDIT-COMMANDE-FOCUS-GUARD-001` PASS。
- 上一轮 P1 已解除。
- 未见 ESC / Command+F / Command+A / Command+C / Command+X / Command+V / Command+Z / Command+W 回归。
- `swift test` 因无 Tests 目录返回 no tests found。
后续调度：
- 主控已调度 Acceptance Agent `V2-ACCEPT-S7-EDIT-MIN-CLOSED-LOOP-001`。
交付摘要：文档 Agent 已追加阶段 7 第一批编辑闭环 Command+E 焦点 Guard 复测与 Review PASS 记录；未修改业务代码，未运行构建，未回退任何改动。
```


## 61. 阶段 7 第一批编辑闭环 Acceptance PASS 记录

```text
调度 ID：V2-DOCS-S7-EDIT-MIN-CLOSED-LOOP-ACCEPTED-001
时间：2026-05-14
阶段：第二版阶段 7 / 第一批编辑能力最小闭环 Acceptance PASS
任务卡 ID：V2-DOCS-S7-EDIT-MIN-CLOSED-LOOP-ACCEPTED-001
当前会话模式：ClipEase V2 文档 / 日志 Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook，不修改业务代码
Acceptance Agent 结果：
- Acceptance Agent `V2-ACCEPT-S7-EDIT-MIN-CLOSED-LOOP-001` PASS。
- 阶段 7 第一批“编辑能力最小闭环”可进入人工 UI 验收 / build-run。
自动门禁：
- `swift build` 通过。
- `smoke_check.py` 通过。
- `verify_sqlite_migration.py` 通过。
- `swift test` 因无 Tests 目录返回 no tests found，不阻塞。
关键能力：
- 文本 / 链接 / 颜色可编辑，图片不可编辑。
- `Command + E` 焦点 guard 已通过复核。
- 链接保存后复制并 skip。
- 颜色使用 HEX。
- 编辑更新原记录，不新增历史。
人工 UI 必测项：
- 文本编辑。
- 链接合法 / 非法 URL。
- 颜色 ColorPicker / HEX。
- 图片无编辑入口。
- `Command + E` 焦点保护。
- 取消 / ESC / 保存失败。
- 搜索 / 筛选 / 分组视图下编辑。
- 重启后持久化和历史数量不增加。
交付摘要：文档 Agent 已在 runbook 末尾追加阶段 7 第一批编辑能力最小闭环 Acceptance PASS 记录；未修改业务代码，未运行构建，未回退任何改动。
```

## 62. 阶段 7 第一批编辑功能用户授权 build-run 记录

```text
调度 ID：V2-DOCS-S7-EDIT-BUILD-RUN-260514-0008-001
时间：2026-05-14
阶段：第二版阶段 7 / 第一批编辑功能用户授权 build-run
任务卡 ID：V2-DOCS-S7-EDIT-BUILD-RUN-260514-0008-001
当前会话模式：ClipEase V2 文档 / 日志 Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook，不修改业务代码
用户授权：
- 用户明确指令：“构建运行 App，我测试阶段7编辑功能”。
- 本次 build-run 是用户明确授权后的操作。
前置门禁：
- 阶段 7 第一批“编辑能力最小闭环”已通过 Test / Review / Acceptance。
- 可进入用户人工 UI 验收。
主控已执行：
- `scripts/build-app.sh --bump none --run`
build-run 结果：
- 版本 / 构建号：`1.0.5 (260513.2234) -> 1.0.5 (260514.0008)`
- 构建成功：`Build of product 'ClipEase' complete!`
- App 路径：`/Users/wpc/code/codex/ClipboardHistory/.build/ClipEase.app`
- 已启动进程 PID：`96629`
- 可执行文件：`/Users/wpc/code/codex/ClipboardHistory/.build/ClipEase.app/Contents/MacOS/ClipEase`
人工 UI 测试重点：
- 文本编辑。
- 链接合法 / 非法 URL。
- 颜色 ColorPicker / HEX。
- 图片无编辑入口。
- `Command + E` 焦点保护。
- 取消 / ESC / 保存失败。
- 搜索 / 筛选 / 分组视图下编辑。
- 重启后持久化和历史数量不增加。
交付摘要：文档 Agent 已追加阶段 7 第一批编辑功能用户授权 build-run 记录；未修改业务代码，未运行构建，未回退任何改动。
```

## 63. 阶段 7 第一批编辑功能用户反馈 bug 记录

```text
调度 ID：V2-DOCS-S7-EDIT-REUSE-NEW-TEXT-EDITOR-BUG-001
时间：2026-05-14
阶段：第二版阶段 7 / 第一批编辑闭环 UI / 交互 bug
任务卡 ID：V2-DOCS-S7-EDIT-REUSE-NEW-TEXT-EDITOR-BUG-001
当前会话模式：ClipEase V2 文档 / 日志 Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook，不修改业务代码
用户反馈 bug：
- 文本编辑 / 链接编辑 / 颜色编辑，应该复用“新建文本”的文本输入框。
- 当复用“新建文本”的文本输入框时，所有系统快捷操作应该在此文本输入框窗口生效。
主控归类：
- 阶段 7 第一批编辑闭环 UI / 交互 bug。
- 范围较小，交给 Bugfix Agent 定点处理。
主控调度：
- Bugfix Agent：`V2-BUGFIX-S7-EDIT-REUSE-NEW-TEXT-EDITOR-001`。
文件锁：
- 优先允许修改 `HistoryWindowView.swift` 和现有“新建文本”输入框相关文件。
- 禁止修改 schema / migration / backup / release / build scripts。
- 禁止批量删除。
- 禁止引入富文本回编。
后续门禁：
- Bugfix 完成后需进入 Test / Review / Acceptance。
- Acceptance PASS 后再 build-run 给用户测试。
交付摘要：文档 Agent 已在 runbook 末尾追加阶段 7 第一批编辑功能用户反馈 bug、主控归类、Bugfix Agent 调度、文件锁和后续门禁记录；未修改业务代码，未运行构建，未回退任何改动。
```

## 64. 阶段 7 第一批编辑功能复用新建文本输入框修复完成记录

```text
调度 ID：V2-DOCS-S7-EDIT-REUSE-NEW-TEXT-EDITOR-COMPLETE-001
时间：2026-05-14
阶段：第二版阶段 7 / 第一批编辑闭环 UI / 交互 bugfix 完成
任务卡 ID：V2-DOCS-S7-EDIT-REUSE-NEW-TEXT-EDITOR-COMPLETE-001
当前会话模式：ClipEase V2 文档 / 日志 Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook，不修改业务代码
Bugfix Agent：
- `V2-BUGFIX-S7-EDIT-REUSE-NEW-TEXT-EDITOR-001` 已完成。
修改文件：
- `AppMenuController.swift`
- `HistoryWindowView.swift`
- `RichTextEditorController.swift`
修复内容：
- 文本 / 链接 / 颜色编辑复用“新建文本”的 `NSPanel + NSTextView` 输入窗口。
- `RichTextEditorController` 增加 create / edit mode。
- 编辑保存仍走 `updateEditableContent` 更新原记录。
- 链接 / 颜色校验规则保留。
- 图片 / 富文本不编辑。
快捷键说明：
- `Command + A` / `Command + C` / `Command + X` / `Command + V` / `Command + Z` / `Shift + Command + Z` 由 `NSTextView` 处理。
- 方向键等由 AppKit 默认行为处理。
- 打开编辑窗口时标记文本输入聚焦，关闭后恢复，避免历史窗口抢快捷键。
- `Command + E` guard 保留。
自测：
- `swift build` 通过。
- `smoke_check.py` 通过。
- 未运行 `verify_sqlite_migration.py`。
后续调度：
- 主控已调度 Test Agent：`V2-TEST-S7-EDIT-REUSE-NEW-TEXT-EDITOR-001`。
- 主控已调度 Review Agent：`V2-REVIEW-S7-EDIT-REUSE-NEW-TEXT-EDITOR-001`。
交付摘要：文档 Agent 已在 runbook 末尾追加阶段 7 第一批编辑功能复用新建文本输入框 bugfix 完成记录；未修改业务代码，未运行构建，未回退任何改动。
```

## 65. 阶段 7 第一批编辑功能复用新建文本输入框 Test PASS / Review HOLD / 返工调度记录

```text
调度 ID：V2-DOCS-S7-EDIT-REUSE-EDITOR-ESC-HOLD-001
时间：2026-05-14
阶段：第二版阶段 7 / 第一批编辑闭环 UI / 交互 bugfix 验证与返工
任务卡 ID：V2-DOCS-S7-EDIT-REUSE-EDITOR-ESC-HOLD-001
当前会话模式：ClipEase V2 文档 / 日志 Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook，不修改业务代码
Test Agent 结果：
- `V2-TEST-S7-EDIT-REUSE-NEW-TEXT-EDITOR-001` PASS。
- build / smoke / migration 通过。
- 静态验证通过。
Review Agent 结果：
- `V2-REVIEW-S7-EDIT-REUSE-NEW-TEXT-EDITOR-001` HOLD。
- HOLD 原因：编辑面板打开时，`Esc` 被 `HistoryWindow` 全局 close action 处理。
- 当前行为：只 reset edit state，没有关闭 `RichTextEditorController` panel。
- 风险影响：panel 残留，且 input focus 状态被错误清空。
主控返工调度：
- Bugfix Agent：`V2-BUGFIX-S7-EDIT-REUSE-EDITOR-ESC-CLOSE-001`。
文件锁：
- 允许修改 `HistoryWindowView.swift`。
- 允许修改 `RichTextEditorController.swift`。
- 必要时允许修改 `HistoryKeyboardEventTap.swift`。
- 禁止修改 Store / Model / schema / migration / backup / release / build scripts 等。
后续门禁：
- Bugfix 完成后需重新进入 Test / Review。
- Review HOLD 解除后再进入 Acceptance / build-run 用户测试链路。
交付摘要：文档 Agent 已在 runbook 末尾追加阶段 7 第一批编辑功能复用新建文本输入框 Test PASS、Review HOLD 和 Esc 关闭返工调度记录；未修改业务代码，未运行构建，未回退任何改动。
```

## 66. 阶段 7 第一批编辑功能复用新建文本输入框 Esc 关闭返工完成记录

```text
调度 ID：V2-DOCS-S7-EDIT-REUSE-EDITOR-ESC-CLOSE-COMPLETE-001
时间：2026-05-14
阶段：第二版阶段 7 / 第一批编辑闭环 UI / 交互 bugfix 返工完成
任务卡 ID：V2-DOCS-S7-EDIT-REUSE-EDITOR-ESC-CLOSE-COMPLETE-001
当前会话模式：ClipEase V2 文档 / 日志 Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook，不修改业务代码
Bugfix Agent：
- `V2-BUGFIX-S7-EDIT-REUSE-EDITOR-ESC-CLOSE-001` 已完成。
修改文件：
- `RichTextEditorController.swift`
- `HistoryKeyboardEventTap.swift`
修复内容：
- 编辑器 `NSTextView` delegate 增加 `cancelOperation`。
- `Esc` 直接 `panel.close()`，触发现有 `windowWillClose -> onClose -> resetEditState()`。
- 全局 event tap 文本输入聚焦时不再吞 `.close`。
- 搜索框 `Esc` 继续走自己的 `onCancel -> handleEscapeClose()`。
自测：
- `swift build` 通过。
- `smoke_check.py` 通过。
- 未运行 packaging。
后续调度：
- 主控已调度 Test Agent：`V2-TEST-S7-EDIT-REUSE-EDITOR-ESC-CLOSE-001`。
- 主控已调度 Review Agent：`V2-REVIEW-S7-EDIT-REUSE-EDITOR-ESC-CLOSE-001`。
交付摘要：文档 Agent 已在 runbook 末尾追加阶段 7 第一批编辑功能复用新建文本输入框 Esc 关闭返工完成记录；未修改业务代码，未运行构建，未回退任何改动。
```

## 67. 阶段 7 第一批编辑功能复用新建文本输入框 Esc 关闭返工 Test / Review PASS 记录

```text
调度 ID：V2-DOCS-S7-EDIT-REUSE-EDITOR-ESC-TEST-REVIEW-PASS-001
时间：2026-05-14
阶段：第二版阶段 7 / 第一批编辑闭环 UI / 交互 bugfix 验证与评审通过
任务卡 ID：V2-DOCS-S7-EDIT-REUSE-EDITOR-ESC-TEST-REVIEW-PASS-001
当前会话模式：ClipEase V2 文档 / 日志 Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook，不修改业务代码
Test Agent 结果：
- `V2-TEST-S7-EDIT-REUSE-EDITOR-ESC-CLOSE-001` PASS。
- `swift build` 通过。
- `smoke_check.py` 通过。
- `verify_sqlite_migration.py` 通过。
- 编辑 panel Esc 关闭链路静态检查通过。
- 搜索 Esc 顺序静态检查通过。
- create mode 静态检查通过。
- Command+E guard 静态检查通过。
Review Agent 结果：
- `V2-REVIEW-S7-EDIT-REUSE-EDITOR-ESC-CLOSE-001` PASS。
- P1 已解除。
- 真实 panel 和 edit state 一起收掉。
- 搜索 Esc 顺序未破坏。
- 新建文本 create mode 保持。
- 未见越权。
后续调度：
- 主控已调度 Acceptance Agent：`V2-ACCEPT-S7-EDIT-REUSE-NEW-TEXT-EDITOR-001`。
交付摘要：文档 Agent 已在 runbook 末尾追加阶段 7 第一批编辑功能复用新建文本输入框 Esc 关闭返工 Test PASS、Review PASS 和 Acceptance 调度记录；未修改业务代码，未运行构建，未回退任何改动。
```

## 68. 阶段 7 第一批编辑功能复用新建文本输入框 Acceptance PASS 最终记录

```text
调度 ID：V2-DOCS-S7-EDIT-REUSE-NEW-TEXT-EDITOR-ACCEPTED-001
时间：2026-05-14
阶段：第二版阶段 7 / 第一批编辑闭环 UI / Acceptance 最终通过
任务卡 ID：V2-DOCS-S7-EDIT-REUSE-NEW-TEXT-EDITOR-ACCEPTED-001
当前会话模式：ClipEase V2 文档 / 日志 Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook，不修改业务代码
Acceptance Agent 结果：
- `V2-ACCEPT-S7-EDIT-REUSE-NEW-TEXT-EDITOR-001` PASS。
- 用户反馈的两个 bug 已达到可交付 / 可 build-run 人工验收状态。
交付范围：
- 文本 / 链接 / 颜色编辑复用“新建文本”的 `NSPanel + NSTextView` 输入窗口。
- 系统快捷操作在该输入框窗口生效。
- `Esc` 关闭路径已修复。
验证链：
- `swift build` 通过。
- `smoke_check.py` 通过。
- `verify_sqlite_migration.py` 通过。
阻塞 / 红线 / 用户确认：
- 无阻塞项。
- 无新增红线。
- 无必须用户确认项。
人工 UI 必测项清单：
- 文本 `Command+E` 编辑。
- 链接合法 URL 编辑。
- 链接非法 URL 编辑。
- 颜色合法 HEX 编辑。
- 颜色非法 HEX 编辑。
- 图片不可编辑。
- 富文本不可编辑。
- 编辑 panel 内 `Command+A` / `Command+C` / `Command+X` / `Command+V` / `Command+Z` / `Shift+Command+Z` / `Command+W`。
- `Esc` 关闭编辑 panel。
- 搜索框 `Esc` 顺序。
下一步建议：
- 主控执行 build-run 供用户测试。
- build-run 需用户明确授权后执行。
交付摘要：文档 Agent 已在 runbook 末尾追加阶段 7 第一批编辑功能复用新建文本输入框 Acceptance PASS 最终记录；未修改业务代码，未运行构建，未回退任何改动。
```

## 69. 阶段 7 编辑输入框修复用户授权 build-run 记录

```text
调度 ID：V2-DOCS-S7-EDIT-REUSE-EDITOR-BUILD-RUN-260514-0035-001
时间：2026-05-14
阶段：第二版阶段 7 / 编辑输入框修复用户授权 build-run
任务卡 ID：V2-DOCS-S7-EDIT-REUSE-EDITOR-BUILD-RUN-260514-0035-001
当前会话模式：ClipEase V2 文档 / 日志 Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook，不修改业务代码
用户授权：
- 用户明确指令：“构建运行 App，我测试编辑输入框修”。
- 本次 build-run 是用户明确授权后的操作。
前置门禁：
- 阶段 7 编辑输入框复用修复已通过 Test / Review / Acceptance。
- 可进入用户人工 UI 验收。
主控已执行：
- `scripts/build-app.sh --bump none --run`
build-run 结果：
- 版本 / 构建号：`1.0.5 (260514.0008) -> 1.0.5 (260514.0035)`
- 构建成功：`Build of product 'ClipEase' complete!`
- App 路径：`/Users/wpc/code/codex/ClipboardHistory/.build/ClipEase.app`
- 已启动进程 PID：`38787`
- 可执行文件：`/Users/wpc/code/codex/ClipboardHistory/.build/ClipEase.app/Contents/MacOS/ClipEase`
人工 UI 测试重点：
- 文本 / 链接 / 颜色编辑复用新建文本输入框。
- 编辑输入框内 `Command+A` / `Command+C` / `Command+X` / `Command+V` / `Command+Z` / `Shift+Command+Z` / `Command+W`。
- 编辑输入框内方向键 / `Option` 跳转 / `Command` 跳转。
- `Esc` 关闭编辑 panel。
- 搜索框 `Esc` 顺序。
- 链接合法 / 非法 URL。
- 颜色合法 / 非法 HEX。
- 图片 / 富文本不可编辑。
交付摘要：文档 Agent 已追加阶段 7 编辑输入框修复用户授权 build-run 记录；未修改业务代码，未运行构建，未回退任何改动。
```

## 70. 阶段 7 颜色编辑增强需求归档记录

```text
调度 ID：V2-DOCS-STAGE7-COLOR-EDITOR-ENHANCEMENT-PLAN-001
时间：2026-05-14
阶段：第二版阶段 7 / 后续颜色编辑增强计划
任务卡 ID：V2-DOCS-STAGE7-COLOR-EDITOR-ENHANCEMENT-PLAN-001
当前会话模式：ClipEase V2 文档 / 日志 Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook 和优化 backlog，不修改业务代码
用户提出的颜色编辑增强需求：
- 颜色编辑是否需要增加取色器。
- 背景是否应对应显示并修改背景颜色。
- 字体是否应跟随背景颜色自动调整为白色 / 黑色。
主控答复与归类：
- 当前阶段 7 第一批编辑闭环只保证颜色值可编辑和规范化，不完整覆盖取色器、实时背景预览和自动对比色体验。
- 以上需求归类为阶段 7 后续颜色编辑增强。
- 不阻塞当前“复用新建文本输入框”bugfix 验收。
后续计划：
- 已在 `docs/V2_OPTIMIZATION_BACKLOG.md` 新增 `V2-OPT-STAGE7-COLOR-EDITOR-PICKER-CONTRAST-001`。
- 后续实现范围包括颜色编辑增加取色器、编辑时背景实时显示 / 修改目标颜色、文字颜色根据背景亮度自动切换黑 / 白、保存后颜色卡片预览同步。
后续门禁：
- Product 门禁：确认颜色编辑入口、取色器形态、取消行为、实时预览语义和保存语义。
- UX 门禁：确认背景预览、文字自动黑 / 白切换、边界灰度下的可读性和无效输入提示。
- Implementation 门禁：确认不引入 schema / migration / backup / release 变更，仅在现有颜色编辑 UI 和预览同步范围内实现。
- Test 门禁：覆盖浅色、深色、边界灰度、无效 HEX、系统取色器取消和保存后颜色卡片预览同步。
- Review 门禁：确认不扩大阶段 7 第一批已验收范围，不破坏文本 / 链接编辑复用输入框行为。
- Acceptance 门禁：独立于当前编辑输入框修复验收归档，作为阶段 7 后续增强单独放行。
交付摘要：文档 Agent 已追加阶段 7 颜色编辑增强需求归档记录，并同步优化 backlog；未修改业务代码，未运行构建，未回退任何改动。
```

## 71. 阶段 7 富文本编辑规则用户纠正记录

```text
调度 ID：V2-DOCS-S7-RICH-TEXT-EDIT-RULE-CORRECTION-001
时间：2026-05-14
阶段：第二版阶段 7 / 富文本编辑规则用户纠正
任务卡 ID：V2-DOCS-S7-RICH-TEXT-EDIT-RULE-CORRECTION-001
当前会话模式：ClipEase V2 文档 / 日志 Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook 和优化 backlog，不修改业务代码
用户明确反馈：
- “富文本为什么不可编辑？包括新建文本，都是允许再次编辑！”
用户纠正的阶段 7 编辑规则：
- 富文本应允许再次编辑。
- 尤其由“新建文本”产生的内容，也应允许再次编辑。
- 此规则修正此前“富文本不可编辑 / 富文本回编放入后续 backlog”的阶段 7 编辑口径。
主控承认：
- 此前将富文本回编放入后续 backlog，是基于实现风险、富文本 roundtrip 复杂度和第一批交付范围的取舍。
- 该取舍与当前用户明确产品规则冲突。
主控已调度：
- Product Rules Agent：`V2-PRODUCT-S7-RICH-TEXT-EDIT-MUST-001`
- Architecture Gatekeeper：`V2-ARCH-S7-RICH-TEXT-EDIT-ROUNDTRIP-001`
- 两个 Agent 需复核富文本编辑产品规则、roundtrip 架构边界，并准备后续任务卡。
当前处理策略：
- 当前不直接修改业务代码。
- 待 Product Rules Agent 和 Architecture Gatekeeper 给出结论后，再调度实现任务。
同步更新：
- 已更新 `docs/V2_OPTIMIZATION_BACKLOG.md` 中 `V2-OPT-STAGE7-RICH-TEXT-ROUNDTRIP-EDIT-001`。
- 该任务已标注为“用户已明确要求，不应作为普通后续增强；待产品 / 架构复核后提升为阶段 7 编辑闭环必需任务”。
交付摘要：文档 Agent 已追加阶段 7 富文本编辑规则用户纠正记录，并同步优化 backlog；未修改业务代码，未运行构建，未回退任何改动。
```

## 72. 阶段 7 富文本再次编辑必修缺口推进记录

```text
调度 ID：V2-DOCS-S7-RICH-TEXT-EDIT-DISPATCH-001
时间：2026-05-14
阶段：第二版阶段 7 / 富文本再次编辑必修缺口推进
任务卡 ID：V2-DOCS-S7-RICH-TEXT-EDIT-DISPATCH-001
当前会话模式：ClipEase V2 文档 / 日志 Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook 和优化 backlog，不修改业务代码
背景结论：
- 用户已明确纠正富文本编辑规则：“富文本为什么不可编辑？包括新建文本，都是允许再次编辑！”
- Product Rules Agent 已确认富文本编辑应提升为阶段 7 编辑闭环必需项。
- Architecture Gatekeeper 已给出最小安全方案：读取原 RTF 到 `RichTextEditorController`，保存时原子覆盖原 RTF，更新纯文本摘要和 recentHashes，不改 schema / migration。
主控推进决策：
- 主控将富文本再次编辑作为阶段 7 必修缺口推进。
- 该任务不再作为后续普通增强处理。
主控已调度开发 / Bugfix Agent：
- `V2-S7-RICH-TEXT-EDIT-ROUNDTRIP-001`
文件锁：
- `RichTextEditorController.swift`
- `HistoryWindowView.swift`
- `ClipboardHistoryStore.swift`
- `ClipboardHistoryPersistence.swift`
- 必要时 `ClipboardItem.swift`
禁止范围：
- SQLite schema / migration / Repository 查询下沉 / LIKE / FTS。
- backup / import-export 语义。
- 批量删除 / 撤销 / 导出。
- 版本 / 发布 / 打包脚本。
后续门禁：
- Test Agent 覆盖富文本读取原 RTF、编辑保存、原子覆盖、纯文本摘要更新、recentHashes 更新和既有文本 / 链接 / 颜色编辑回归。
- Review Agent 确认最小安全方案落地，不引入 schema / migration / Repository 查询下沉等禁改范围。
- Acceptance Agent 在 Test / Review PASS 后确认阶段 7 富文本再次编辑缺口放行。
- Acceptance PASS 后再 build-run，供用户人工测试。
同步更新：
- 已更新 `docs/V2_OPTIMIZATION_BACKLOG.md` 中 `V2-OPT-STAGE7-RICH-TEXT-ROUNDTRIP-EDIT-001`。
- 该任务已标注为当前阶段 7 必修进行中任务，不再作为后续普通增强。
交付摘要：文档 Agent 已追加阶段 7 富文本再次编辑必修缺口推进记录，并同步优化 backlog；未修改业务代码，未运行构建，未回退任何改动。
```

## 73. 阶段 7 富文本再次编辑实现完成记录

```text
调度 ID：V2-DOCS-S7-RICH-TEXT-EDIT-ROUNDTRIP-COMPLETE-001
时间：2026-05-14
阶段：第二版阶段 7 / 富文本再次编辑实现完成
任务卡 ID：V2-DOCS-S7-RICH-TEXT-EDIT-ROUNDTRIP-COMPLETE-001
当前会话模式：ClipEase V2 文档 / 日志 Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook 和优化 backlog，不修改业务代码
开发 Agent 完成：
- `V2-S7-RICH-TEXT-EDIT-ROUNDTRIP-001` 已完成。
修改文件：
- `RichTextEditorController.swift`
- `HistoryWindowView.swift`
- `ClipboardHistoryStore.swift`
- `ClipboardHistoryPersistence.swift`
- `AppMenuController.swift`
实现内容：
- 富文本 `.text + richTextFileName` 可编辑。
- 读取原 RTF 到同一个 `RichTextEditorController`。
- 保存时导出 RTF 并原子覆盖同名文件。
- 保持 `richTextFileName` 不变。
- 文件成功后更新 plain text 摘要、recentHashes、保存历史。
- 失败不改 item metadata。
未实现 / 非目标：
- 未改 schema / migration / Repository LIKE / FTS。
- 未改 backup / import-export。
- 未做批量功能。
- 未改发布 / 打包脚本。
自测：
- `swift build` 通过。
- `smoke_check.py` 通过。
- `verify_sqlite_migration.py` 通过。
主控已调度：
- Test Agent：`V2-TEST-S7-RICH-TEXT-EDIT-ROUNDTRIP-001`
- Review Agent：`V2-REVIEW-S7-RICH-TEXT-EDIT-ROUNDTRIP-001`
同步更新：
- 已更新 `docs/V2_OPTIMIZATION_BACKLOG.md` 中 `V2-OPT-STAGE7-RICH-TEXT-ROUNDTRIP-EDIT-001`。
- 该任务状态已标注为“实现完成，进入 Test / Review 门禁”，不再作为普通 backlog。
交付摘要：文档 Agent 已追加阶段 7 富文本再次编辑实现完成记录，并同步优化 backlog；未修改业务代码，未运行构建，未回退任何改动。
```

## 74. 阶段 7 富文本再次编辑 Review HOLD 记录

```text
调度 ID：V2-DOCS-S7-RICH-TEXT-EDIT-REVIEW-HOLD-001
时间：2026-05-14
阶段：第二版阶段 7 / 富文本再次编辑 Test PASS 与 Review HOLD
任务卡 ID：V2-DOCS-S7-RICH-TEXT-EDIT-REVIEW-HOLD-001
当前会话模式：ClipEase V2 文档 / 日志 Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook，不修改业务代码
Test Agent 结果：
- `V2-TEST-S7-RICH-TEXT-EDIT-ROUNDTRIP-001` PASS。
- `swift build` 通过。
- `smoke_check.py` 通过。
- `verify_sqlite_migration.py` 通过。
- 轻量静态断言通过。
Review Agent 结果：
- `V2-REVIEW-S7-RICH-TEXT-EDIT-ROUNDTRIP-001` HOLD。
HOLD 原因：
1. 工作区包含 SQLite / default repository / migration 相关大范围改动，需主控隔离归因；主控初判这些是 V2 阶段 1-3 已批准主线，不属于本轮富文本新增。
2. P1：RTF 覆盖与 item metadata 异步保存有半成功窗口。
3. P2：加载 RTF 后 `enforceBlackText()` 会覆盖全文颜色属性，导致带颜色 RTF roundtrip 丢颜色。
主控已调度：
- Architecture Gatekeeper：`V2-ARCH-S7-RICH-TEXT-EDIT-HOLD-RESOLUTION-001`
- 目标：评估最小安全修复方案。
后续：
- 架构结论后调度 Bugfix。
- 修复完成后重新 Test / Review / Acceptance。
交付摘要：文档 Agent 已追加阶段 7 富文本再次编辑 Test PASS 与 Review HOLD 记录；未修改业务代码，未运行构建，未回退任何改动。
```

## 75. 阶段 7 富文本再次编辑 HOLD 架构结论与 Bugfix 调度记录

```text
调度 ID：V2-DOCS-S7-RICH-TEXT-EDIT-HOLD-ARCH-RESULT-001
时间：2026-05-14
阶段：第二版阶段 7 / 富文本再次编辑 Review HOLD 架构结论与返工调度
任务卡 ID：V2-DOCS-S7-RICH-TEXT-EDIT-HOLD-ARCH-RESULT-001
当前会话模式：ClipEase V2 文档 / 日志 Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook，不修改业务代码
Architecture Gatekeeper 结果：
- `V2-ARCH-S7-RICH-TEXT-EDIT-HOLD-RESOLUTION-001` 已完成。
- SQLite / default repository / migration 相关大范围 dirty tree 应隔离归因为 V2 阶段 1-3 已批准主线，不归入本轮富文本新增。
- 后续放行报告需明确该隔离归因，避免将历史主线脏改动误算到阶段 7 富文本再次编辑任务。
- P1 半成功窗口成立，建议采用“新 RTF 文件 + metadata 同步保存成功后切换引用 + 清理旧文件；失败回滚并删除新文件”的方案。
- P2 应在已有 RTF edit mode 加载时跳过全文 `enforceBlackText()`，保留 `foregroundColor`。
- 禁止改 SQLite schema / migration / backup / import-export 等非本轮范围。
主控已调度：
- Bugfix Agent：`V2-BUGFIX-S7-RICH-TEXT-EDIT-HOLD-RESOLUTION-001`。
Bugfix 修复范围：
- 仅修复富文本再次编辑保存的 P1 半成功窗口。
- 仅修复已有 RTF edit mode 加载时 P2 颜色属性被覆盖问题。
- 保持阶段 7 富文本再次编辑 roundtrip 产品语义不扩大。
文件锁：
- `RichTextEditorController.swift`：Bugfix Agent 可改，仅限 RTF edit mode 加载颜色保留相关逻辑。
- `HistoryWindowView.swift`：Bugfix Agent 可改，仅限富文本编辑保存调用链必要调整。
- `ClipboardHistoryStore.swift`：Bugfix Agent 可改，仅限新 RTF 文件、metadata 同步保存、引用切换、旧文件清理和失败回滚。
- `ClipboardHistoryPersistence.swift`：Bugfix Agent 必要时可改，仅限复用现有保存语义，不得改 schema / migration。
- `ClipboardItem.swift`：Bugfix Agent 必要时可读 / 最小修改，仅限既有字段引用，不得新增持久化字段。
禁改范围：
- SQLite schema / migration / default repository 架构重写。
- backup / import-export 语义。
- Repository 查询下沉 / LIKE / FTS / 索引化搜索。
- 批量删除 / 撤销 / 导出。
- 版本 / 发布 / 打包脚本。
- 与本轮富文本再次编辑 HOLD 无关的 UI 重构。
后续 Test 门禁：
- 复测富文本读取原 RTF、再次编辑、保存后新 RTF 引用切换、旧 RTF 清理、失败回滚不污染 item metadata。
- 覆盖 metadata 保存失败时删除新 RTF 文件。
- 覆盖已有带颜色 RTF 进入 edit mode 后保留 `foregroundColor`，保存 roundtrip 不丢颜色。
- 回归既有文本 / 链接 / 颜色编辑闭环。
后续 Review 门禁：
- 确认 P1 使用 Architecture Gatekeeper 建议方案落地，消除 RTF 文件与 item metadata 半成功窗口。
- 确认 P2 仅在已有 RTF edit mode 跳过全文黑色强制，不影响新建文本编辑默认黑色策略。
- 确认 SQLite / default repository / migration dirty tree 已在放行报告中隔离归因，不归入本轮富文本新增。
- 确认未触碰 schema / migration / backup / import-export 等禁改范围。
后续 Acceptance 门禁：
- Test / Review PASS 后再调度 Acceptance Agent。
- Acceptance Agent 需确认阶段 7 富文本再次编辑 HOLD 已解除，且 dirty tree 隔离说明清楚。
- Acceptance PASS 后再进入 build-run / 用户人工测试。
交付摘要：文档 Agent 已追加阶段 7 富文本再次编辑 HOLD 架构结论、Bugfix Agent 调度、文件锁、禁改范围和后续 Test / Review / Acceptance 门禁记录；未修改业务代码，未运行构建，未回退任何改动。
```

## 76. 阶段 7 富文本再次编辑 HOLD Bugfix 完成记录

```text
调度 ID：V2-DOCS-S7-RICH-TEXT-EDIT-HOLD-RESOLUTION-COMPLETE-001
时间：2026-05-14
阶段：第二版阶段 7 / 富文本再次编辑 Review HOLD Bugfix 完成
任务卡 ID：V2-DOCS-S7-RICH-TEXT-EDIT-HOLD-RESOLUTION-COMPLETE-001
当前会话模式：ClipEase V2 文档 / 日志 Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook，不修改业务代码
Bugfix Agent 结果：
- `V2-BUGFIX-S7-RICH-TEXT-EDIT-HOLD-RESOLUTION-001` 已完成。
修改文件：
- `ClipboardHistoryPersistence.swift`
- `ClipboardHistoryStore.swift`
- `RichTextEditorController.swift`
- `AppMenuController.swift`
- `ClipboardItem.swift`
P1 修复：
- 新 RTF 文件 + metadata 同步保存成功后切换引用 + 清理旧文件。
- 失败恢复旧 item、rebuild hashes、删除新 RTF。
- metadata 保存前崩溃最多孤立新 RTF，不破坏旧引用。
P2 修复：
- 移除已有 RTF 全文黑化。
- 保留有色 RTF foregroundColor。
- 新建 / 新输入仍默认黑色 typing attributes。
自测：
- `swift build` 通过。
- `smoke_check.py` 通过。
- `verify_sqlite_migration.py` 通过。
- 轻量静态检查通过。
主控已调度：
- Test Agent：`V2-TEST-S7-RICH-TEXT-EDIT-HOLD-RESOLUTION-001`。
- Review Agent：`V2-REVIEW-S7-RICH-TEXT-EDIT-HOLD-RESOLUTION-001`。
交付摘要：文档 Agent 已追加阶段 7 富文本再次编辑 HOLD Bugfix 完成记录；未修改业务代码，未运行构建，未回退任何改动。
```

## 77. 阶段 7 富文本再次编辑 JSON Save HOLD 记录

```text
调度 ID：V2-DOCS-S7-RICH-TEXT-EDIT-JSON-SAVE-HOLD-001
时间：2026-05-14
阶段：第二版阶段 7 / 富文本再次编辑 JSON repository save HOLD
任务卡 ID：V2-DOCS-S7-RICH-TEXT-EDIT-JSON-SAVE-HOLD-001
当前会话模式：ClipEase V2 文档 / 日志 Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook，不修改业务代码
Test Agent 结果：
- `V2-TEST-S7-RICH-TEXT-EDIT-HOLD-RESOLUTION-001` PASS。
- build / smoke / migration 和静态断言通过。
- P2 颜色丢失已解除。
- 状态保留、create mode、text / link / color、Esc / Command 路径静态通过。
Review Agent 结果：
- `V2-REVIEW-S7-RICH-TEXT-EDIT-HOLD-RESOLUTION-001` 仍 HOLD。
- HOLD 原因：JSON repository path 中 `history.json` 写成功、`groups.json` 写失败时，rollback 删除新 RTF，会导致磁盘 history 指向不存在的新 RTF。
主控已调度：
- Architecture Gatekeeper：`V2-ARCH-S7-RICH-TEXT-EDIT-JSON-SAVE-HOLD-001`。
Architecture Gatekeeper 目标：
- 评估 JSON repository save 半成功窗口的最小修复方案。
- 避免扩大阶段 7 富文本再次编辑范围。
交付摘要：文档 Agent 已追加富文本再次编辑 Test PASS、Review HOLD 和 Architecture Gatekeeper 调度记录；未修改业务代码，未运行构建，未回退任何改动。
```

## 78. 阶段 7 富文本再次编辑 JSON Save HOLD 架构结论

```text
调度 ID：V2-DOCS-S7-RICH-TEXT-EDIT-JSON-SAVE-ARCH-RESULT-001
时间：2026-05-14
阶段：第二版阶段 7 / 富文本再次编辑 JSON repository save HOLD 架构结论
任务卡 ID：V2-DOCS-S7-RICH-TEXT-EDIT-JSON-SAVE-ARCH-RESULT-001
当前会话模式：ClipEase V2 文档 / 日志 Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook，不修改业务代码
Architecture Gatekeeper 结果：
- `V2-ARCH-S7-RICH-TEXT-EDIT-JSON-SAVE-HOLD-001` 已完成。
- JSON repository 的 `history.json` / `groups.json` 双文件保存非事务，Review 指出的 HOLD 成立。
架构结论：
- 推荐最小修复：`updateRichTextContent` 在 `saveImmediatelyOrThrow()` 失败回滚时不删除本次新写入 RTF。
- 该方案避免 metadata 部分落盘后指向缺失附件；最坏情况是留下孤立 RTF 文件。
- 成功路径仍删除旧 RTF。
禁改范围：
- 不改 JSON repository 全局提交协议。
- 不改 SQLite schema / migration。
- 不改 backup / import-export。
主控已调度：
- Bugfix Agent：`V2-BUGFIX-S7-RICH-TEXT-EDIT-JSON-SAVE-HOLD-001`。
后续门禁：
- Bugfix Agent 仅落地上述最小修复。
- 后续 Test / Review 需确认失败回滚不再删除本次新写入 RTF，成功路径仍清理旧 RTF，且未扩大到禁改范围。
交付摘要：文档 Agent 已追加阶段 7 富文本再次编辑 JSON Save HOLD 架构结论和 Bugfix Agent 调度记录；未修改业务代码，未运行构建，未回退任何改动。
```

## 79. 阶段 7 富文本再次编辑 JSON Save HOLD Bugfix 完成记录

```text
调度 ID：V2-DOC-S7-RICH-TEXT-EDIT-JSON-SAVE-HOLD-GATES-001
时间：2026-05-14
阶段：第二版阶段 7 / 富文本再次编辑 JSON repository save HOLD 门禁等待
任务卡 ID：V2-DOC-S7-RICH-TEXT-EDIT-JSON-SAVE-HOLD-GATES-001
当前会话模式：ClipEase V2 文档 / 日志 Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook，不修改业务代码
Bugfix Agent 结果：
- `V2-BUGFIX-S7-RICH-TEXT-EDIT-JSON-SAVE-HOLD-001` 已完成。
修复摘要：
- 保存失败回滚保留新 RTF，避免 metadata 半成功落盘后指向缺失附件。
- 回滚恢复内存 item / recentHashes。
- 成功路径仍删除旧 RTF。
- 新增 `scripts/verify_rich_text_edit_json_save_hold.py`。
主控已调度：
- Test Agent：`V2-TEST-S7-RICH-TEXT-EDIT-JSON-SAVE-HOLD-001`。
- Review Agent：`V2-REVIEW-S7-RICH-TEXT-EDIT-JSON-SAVE-HOLD-001`。
当前状态：
- 等待测试 / 审查门禁。
交付摘要：文档 Agent 已追加阶段 7 富文本再次编辑 JSON Save HOLD Bugfix 完成和门禁等待记录；未修改业务代码，未运行构建，未回退任何改动。
```

## 80. 阶段 7 富文本再次编辑 JSON Save HOLD 门禁重跑记录

```text
调度 ID：V2-DOC-S7-RICH-TEXT-EDIT-GATE-RERUN-001
时间：2026-05-14
阶段：第二版阶段 7 / 富文本再次编辑 JSON repository save HOLD 门禁重跑
任务卡 ID：V2-DOC-S7-RICH-TEXT-EDIT-GATE-RERUN-001
当前会话模式：ClipEase V2 文档 / 日志 Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook，不修改业务代码
门禁返回状态：
- Test Agent `V2-TEST-S7-RICH-TEXT-EDIT-JSON-SAVE-HOLD-001` 返回结束状态，但无可归档报告。
- Review Agent `V2-REVIEW-S7-RICH-TEXT-EDIT-JSON-SAVE-HOLD-001` 返回结束状态，但无可归档报告。
主控判定：
- 上述 Test / Review 门禁无可归档报告，视为门禁无效。
主控已重新调度：
- Test Agent：`V2-TEST-S7-RICH-TEXT-EDIT-JSON-SAVE-HOLD-001-RERUN`。
- Review Agent：`V2-REVIEW-S7-RICH-TEXT-EDIT-JSON-SAVE-HOLD-001-RERUN`。
当前状态：
- 等待替代测试 / 审查门禁。
交付摘要：文档 Agent 已追加阶段 7 富文本再次编辑 JSON Save HOLD 门禁重跑记录；未修改业务代码，未运行构建，未回退任何改动。
```

## 81. 阶段 7 富文本再次编辑 JSON Save HOLD 范围裁定等待记录

```text
调度 ID：V2-DOC-S7-RICH-TEXT-EDIT-TEST-HOLD-SCOPE-001
时间：2026-05-14
阶段：第二版阶段 7 / 富文本再次编辑 JSON repository save HOLD 范围裁定等待
任务卡 ID：V2-DOC-S7-RICH-TEXT-EDIT-TEST-HOLD-SCOPE-001
当前会话模式：ClipEase V2 文档 / 日志 Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook，不修改业务代码
替代 Test Agent 结果：
- `V2-TEST-S7-RICH-TEXT-EDIT-JSON-SAVE-HOLD-001-RERUN` 命令全部 PASS。
- 因当前工作区存在 SQLite/Repository、backup/import-export、Info.plist 等范围变更，Test Agent 给出 HOLD。
Review Agent 结果：
- `V2-REVIEW-S7-RICH-TEXT-EDIT-JSON-SAVE-HOLD-001-RERUN` 已 PASS。
主控已调度：
- Architecture Gatekeeper：`V2-ARCH-S7-RICH-TEXT-EDIT-WORKTREE-SCOPE-RULING-001`。
待裁定事项：
- 由 Architecture Gatekeeper 裁定该 Test HOLD 是否阻塞本次富文本修复放行。
当前状态：
- 等待 Architecture Gatekeeper 范围裁定。
交付摘要：文档 Agent 已追加阶段 7 富文本再次编辑 JSON Save HOLD 替代测试 PASS、审查 PASS 和范围 HOLD 架构裁定等待记录；未修改业务代码，未运行构建，未回退任何改动。
```

## 82. 阶段 7 富文本再次编辑 JSON Save HOLD 范围 PASS 裁定记录

```text
调度 ID：V2-DOC-S7-RICH-TEXT-EDIT-ARCH-PASS-BACKLOG-001
时间：2026-05-14
阶段：第二版阶段 7 / 富文本再次编辑 JSON repository save HOLD 范围裁定
任务卡 ID：V2-DOC-S7-RICH-TEXT-EDIT-ARCH-PASS-BACKLOG-001
当前会话模式：ClipEase V2 文档 / 日志 Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook，不修改业务代码
Architecture Gatekeeper 结果：
- `V2-ARCH-S7-RICH-TEXT-EDIT-WORKTREE-SCOPE-RULING-001` PASS。
- Test HOLD 降级为范围备注，不阻塞富文本 JSON Save 修复验收。
范围备注：
- 当前工作区存在 SQLite / Repository / backup-import-export / version bump 等范围变更，需要独立归属、验收记录和合并边界复核。
- 上述范围备注不并入阶段 7 富文本再次编辑 JSON Save 修复验收门禁。
Backlog 归档：
- 已在 `docs/V2_OPTIMIZATION_BACKLOG.md` 增加非阻塞 P2 数据层 / Repository 范围归档或风险复核任务。
主控已调度：
- Acceptance Agent：`V2-ACCEPT-S7-RICH-TEXT-EDIT-ROUNDTRIP-JSON-SAVE-001`。
当前状态：
- 等待 Acceptance Agent 对富文本 JSON Save 修复进行最终验收。
交付摘要：文档 Agent 已追加 Architecture Gatekeeper PASS、Test HOLD 降级范围备注、非阻塞 P2 backlog 归档和 Acceptance Agent 调度记录；未修改业务代码，未运行构建，未回退任何改动。
```

## 83. 阶段 7 第一批编辑闭环用户 PASS 与下一批范围调度记录

```text
调度 ID：V2-DOC-S7-RICH-TEXT-USER-PASS-AND-NEXT-SCOPE-001
时间：2026-05-14
阶段：第二版阶段 7 / 第一批编辑闭环用户 PASS 与下一批范围调度
任务卡 ID：V2-DOC-S7-RICH-TEXT-USER-PASS-AND-NEXT-SCOPE-001
当前会话模式：ClipEase V2 文档 / 日志 Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook，不修改业务代码
用户人工测试结果：
- 用户已测试富文本编辑，反馈“没问题”。
主控结论：
- Stage 7 第一批编辑闭环含富文本再次编辑已通过用户人工测试，可进入下一批推进。
主控已调度：
- Product Rules Agent：`V2-PRODUCT-S7-NEXT-BATCH-SCOPE-001`。
- Architecture Gatekeeper：`V2-ARCH-S7-NEXT-BATCH-SCOPE-001`。
调度目的：
- 拆分 Stage 7 下一批快捷键体系补全与多选/批量操作。
Backlog 状态：
- 颜色编辑增强、批量导出、逐条撤销动画、数据层范围归档仍保持非阻塞 backlog，除非用户另行指定。
当前状态：
- 等待 Product Rules Agent 与 Architecture Gatekeeper 返回下一批范围拆分结果。
交付摘要：文档 Agent 已追加阶段 7 第一批编辑闭环用户 PASS、下一批快捷键体系补全与多选/批量操作范围调度记录；未修改业务代码，未运行构建，未回退任何改动。
```

## 84. 阶段 7 下一批范围 PASS 与开发调度记录

```text
调度 ID：V2-DOC-S7-NEXT-BATCH-DISPATCH-001
时间：2026-05-14
阶段：第二版阶段 7 / 下一批主线范围确认与任务调度
任务卡 ID：V2-DOC-S7-NEXT-BATCH-DISPATCH-001
当前会话模式：ClipEase V2 文档 / 日志 Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook，不修改业务代码
Product Rules 结果：
- `V2-PRODUCT-S7-NEXT-BATCH-SCOPE-001` 已完成。
- 下一批主线建议为：批量管理 MVP + 快捷键 / 菜单一致性。
- 颜色取色器、批量导出、逐条撤销动画、搜索性能、数据层范围归档继续保留在 backlog。
Architecture Gatekeeper 结果：
- `V2-ARCH-S7-NEXT-BATCH-SCOPE-001` PASS with scope guard。
- 快捷键一致性、管理模式多选、批量收藏 / 移动可进入本批。
- 批量删除撤销因附件清理风险单独开架构卡，不混入当前开发。
主控已调度开发任务：
- `V2-S7-SHORTCUT-COMMAND-MAP-001`
- `V2-S7-MANAGEMENT-MODE-SELECTION-001`
主控已调度架构任务：
- `V2-ARCH-S7-BATCH-DELETE-UNDO-SAFETY-001`
文件锁与禁改范围：
- 不改 schema / migration / Repository / SQLite 查询 / 导入导出 / 打包脚本。
- 批量删除不混入当前开发。
当前状态：
- 下一批主线进入开发调度；批量删除 + 一次性撤销安全设计等待独立架构方案。
交付摘要：文档 Agent 已追加阶段 7 下一批 Product Rules 完成、Architecture Gatekeeper PASS with scope guard、开发 / 架构任务调度及文件锁禁改范围；未修改业务代码，未运行构建，未回退任何改动。
```

## 85. 阶段 7 快捷键与管理模式完成及批量操作调度记录

```text
调度 ID：V2-DOC-S7-SHORTCUT-MANAGEMENT-COMPLETE-AND-BATCH-DISPATCH-001
时间：2026-05-14
阶段：第二版阶段 7 / 快捷键与管理模式完成及批量操作调度
任务卡 ID：V2-DOC-S7-SHORTCUT-MANAGEMENT-COMPLETE-AND-BATCH-DISPATCH-001
当前会话模式：ClipEase V2 文档 / 日志 Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook，不修改业务代码
已完成任务：
- `V2-S7-SHORTCUT-COMMAND-MAP-001` 已完成。摘要：新增 HistoryCommand / ShortcutDescriptor，补齐快捷键与菜单一致性，焦点 guard，build 和脚本通过。
- `V2-S7-MANAGEMENT-MODE-SELECTION-001` 已完成。摘要：UI 会话层管理模式、多选、批量栏、选择交集清理、删除禁用，build 和脚本通过。
HOLD 任务：
- `V2-ARCH-S7-BATCH-DELETE-UNDO-SAFETY-001` HOLD 批量删除撤销，且不阻塞无删除 MVP；需要用户红线确认后另做。
主控已调度开发任务：
- `V2-S7-BATCH-FAVORITE-GROUP-MVP-001` 接入批量收藏 / 取消收藏 / 移动到分组。
主控已调度审查任务：
- `V2-REVIEW-S7-SHORTCUT-MANAGEMENT-INTEGRATION-001` 审查快捷键和管理模式集成。
当前状态：
- 快捷键命令映射和管理模式选择基础已完成；批量删除撤销保持 HOLD；批量收藏 / 分组 MVP 与集成审查已进入调度。
交付摘要：文档 Agent 已追加快捷键命令映射完成、管理模式选择完成、批量删除撤销 HOLD、批量收藏 / 分组 MVP 调度和集成审查调度记录；未修改业务代码，未运行构建，未回退任何改动。
```

## 86. 阶段 7 批量收藏分组完成、审查 HOLD 与后续调度记录

```text
调度 ID：V2-DOC-S7-BATCH-FAVORITE-HOLD-DISPATCH-001
时间：2026-05-14
阶段：第二版阶段 7 / 批量收藏分组完成、审查 HOLD 与后续调度
任务卡 ID：V2-DOC-S7-BATCH-FAVORITE-HOLD-DISPATCH-001
当前会话模式：ClipEase V2 文档 / 日志 Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook，不修改业务代码
已完成任务：
- `V2-S7-BATCH-FAVORITE-GROUP-MVP-001` 已完成。摘要：Store 增加 setFavorite/addItems 批量 API，管理模式批量收藏 / 取消收藏 / 移动到分组接真实业务，`⌘D` 管理模式优先批量处理，删除仍禁用。
HOLD 任务：
- Review Agent `V2-REVIEW-S7-SHORTCUT-MANAGEMENT-INTEGRATION-001` HOLD：P1 `⌘M` 更多菜单绕过 focus guard；P0 数据层范围归属待裁定。
主控已调度 Bugfix 任务：
- `V2-BUGFIX-S7-MANAGEMENT-SHORTCUT-GUARD-001` 修复 `⌘M` guard。
主控已调度 Architecture Gatekeeper：
- `V2-ARCH-S7-SHORTCUT-MANAGEMENT-WORKTREE-SCOPE-RULING-001` 裁定数据层范围 HOLD 是否阻塞本批。
当前状态：
- 批量收藏 / 分组 MVP 已完成；集成审查存在 `⌘M` guard 与数据层范围归属 HOLD；修复与架构裁定已进入调度。
交付摘要：文档 Agent 已追加批量收藏分组 MVP 完成、Review Agent HOLD、Bugfix Agent 调度和 Architecture Gatekeeper 范围裁定调度记录；未修改业务代码，未运行构建，未回退任何改动。
```

## 87. 阶段 7 快捷键管理批次门禁等待记录

```text
调度 ID：V2-DOC-S7-SHORTCUT-MANAGEMENT-BATCH-GATES-001
时间：2026-05-14
阶段：第二版阶段 7 / 快捷键管理批次门禁等待
任务卡 ID：V2-DOC-S7-SHORTCUT-MANAGEMENT-BATCH-GATES-001
当前会话模式：ClipEase V2 文档 / 日志 Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook，不修改业务代码
已完成任务：
- `V2-BUGFIX-S7-MANAGEMENT-SHORTCUT-GUARD-001` 已完成。摘要：`⌘M` 更多菜单 action 走 guard 路径，验证通过。
Architecture Gatekeeper 结果：
- `V2-ARCH-S7-SHORTCUT-MANAGEMENT-WORKTREE-SCOPE-RULING-001` PASS。
- data-layer P0 降级为范围备注，不阻塞本批无 schema 任务。
- data-layer 范围风险继续由 `V2-OPT-DATA-REPOSITORY-SCOPE-ARCHIVE-RISK-REVIEW-001` 跟踪。
主控已调度测试任务：
- Test Agent `V2-TEST-S7-SHORTCUT-MANAGEMENT-BATCH-FAVORITE-GROUP-001`
主控已调度审查任务：
- Review Agent `V2-REVIEW-S7-SHORTCUT-MANAGEMENT-BATCH-FAVORITE-GROUP-001`
当前状态：
- 等待测试 / 审查门禁。
交付摘要：文档 Agent 已追加 `⌘M` 更多菜单 guard 修复完成、快捷键管理 worktree 范围裁定 PASS、data-layer P0 降级范围备注、测试与审查门禁调度记录；未修改业务代码，未运行构建，未回退任何改动。
```

## 88. 阶段 7 RC 版本对齐与 Delete 快捷键 HOLD 记录

```text
调度 ID：V2-DOC-S7-RC-VERSION-ALIGN-AND-HOLD-001
时间：2026-05-14
阶段：第二版阶段 7 / RC 版本对齐与 Delete 快捷键 HOLD
任务卡 ID：V2-DOC-S7-RC-VERSION-ALIGN-AND-HOLD-001
当前会话模式：ClipEase V2 文档 / 日志 Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook 和 RC 报告，不修改业务代码
Test HOLD：
- `scripts/smoke_check.py` 失败，原因是 `docs/RELEASE_CANDIDATE_REPORT.md` 未对齐当前 `Resources/Info.plist` 版本 `1.0.6(260514.0301)`。
- 当前版本 `1.0.6(260514.0301)` 来自用户授权 build-run。
Review HOLD：
- P1：管理模式下 Delete 快捷键仍能删除单条记录，应由管理模式删除禁用 / 批量删除 HOLD 规则拦截。
主控已调度 Bugfix 任务：
- `V2-BUGFIX-S7-MANAGEMENT-DELETE-SHORTCUT-GUARD-001`
文档对齐：
- `docs/RELEASE_CANDIDATE_REPORT.md` 已同步当前 RC 版本 / 构建号到 `1.0.6(260514.0301)`。
- RC 报告已记录本包包含 Stage 7 下一批无删除 MVP：快捷键 / 菜单一致性、管理模式多选、批量收藏 / 取消收藏 / 移动到分组；批量删除仍 HOLD / 未放行。
当前状态：
- Test HOLD 的 smoke 版本不一致已完成文档对齐。
- Review HOLD 的 Delete 管理模式快捷键问题等待 Bugfix Agent 修复后重跑门禁。
交付摘要：文档 Agent 已追加 Test HOLD、Review HOLD、Bugfix 调度和 RC 版本对齐记录；未修改业务代码，未运行构建，未回退任何改动。
```

## 89. 阶段 7 Delete 快捷键 Guard 修复完成与重跑门禁等待记录

```text
调度 ID：V2-DOC-S7-DELETE-GUARD-RERUN-GATES-001
时间：2026-05-14
阶段：第二版阶段 7 / Delete 快捷键 Guard 修复完成与重跑门禁等待
任务卡 ID：V2-DOC-S7-DELETE-GUARD-RERUN-GATES-001
当前会话模式：ClipEase V2 文档 / 日志 Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook，不修改业务代码
已完成任务：
- `V2-BUGFIX-S7-MANAGEMENT-DELETE-SHORTCUT-GUARD-001` 已完成。摘要：管理模式 Delete 快捷键不再触发删除，非管理模式保持单条删除。
主控已重跑测试任务：
- Test Agent `V2-TEST-S7-SHORTCUT-MANAGEMENT-BATCH-FAVORITE-GROUP-001-RERUN`
主控已重跑审查任务：
- Review Agent `V2-REVIEW-S7-SHORTCUT-MANAGEMENT-BATCH-FAVORITE-GROUP-001-RERUN`
当前状态：
- 等待重跑门禁。
交付摘要：文档 Agent 已追加 Delete 快捷键 Guard 修复完成、测试与审查任务重跑记录；未修改业务代码，未运行构建，未回退任何改动。
```

## 90. 阶段 7 快捷键管理批次重跑门禁 PASS 与验收等待记录

```text
调度 ID：V2-DOC-S7-SHORTCUT-MANAGEMENT-BATCH-PASS-001
时间：2026-05-14
阶段：第二版阶段 7 / 快捷键管理批次重跑门禁 PASS 与验收等待
任务卡 ID：V2-DOC-S7-SHORTCUT-MANAGEMENT-BATCH-PASS-001
当前会话模式：ClipEase V2 文档 / 日志 Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook，不修改业务代码
Test Agent 重跑结果：
- `V2-TEST-S7-SHORTCUT-MANAGEMENT-BATCH-FAVORITE-GROUP-001-RERUN` PASS。
- `swift build` 通过。
- `python3 scripts/verify_history_shortcut_commands.py` 通过。
- `python3 scripts/verify_management_mode_selection.py` 通过。
- `python3 scripts/verify_batch_favorite_group_mvp.py` 通过。
- `python3 scripts/smoke_check.py` 通过。
Review Agent 重跑结果：
- `V2-REVIEW-S7-SHORTCUT-MANAGEMENT-BATCH-FAVORITE-GROUP-001-RERUN` PASS。
- Delete guard 通过。
- 焦点 guard 通过。
- 批量收藏 / 移动通过。
- 删除仍 HOLD 通过。
主控已调度 Acceptance Agent：
- `V2-ACCEPT-S7-SHORTCUT-MANAGEMENT-BATCH-FAVORITE-GROUP-001`
当前状态：
- 等待验收。
- 批量删除撤销仍为红线 HOLD / backlog，不属于本次放行。
交付摘要：文档 Agent 已追加 Test Agent 重跑 PASS、Review Agent 重跑 PASS、Acceptance Agent 调度和当前验收等待状态；未修改业务代码，未运行构建，未回退任何改动。
```

## 91. 阶段 7 快捷键管理批次 Acceptance PASS 与用户测试交接记录

```text
调度 ID：V2-DOC-S7-SHORTCUT-MANAGEMENT-BATCH-ACCEPT-PASS-001
时间：2026-05-14
阶段：第二版阶段 7 / 快捷键管理批次 Acceptance PASS 与用户测试交接
任务卡 ID：V2-DOC-S7-SHORTCUT-MANAGEMENT-BATCH-ACCEPT-PASS-001
当前会话模式：ClipEase V2 文档 / 日志 Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook，不修改业务代码
Acceptance Agent 结果：
- `V2-ACCEPT-S7-SHORTCUT-MANAGEMENT-BATCH-FAVORITE-GROUP-001` PASS。
当前放行结论：
- Stage 7 下一批“无删除 MVP”可交给用户人工测试。
放行范围：
- 快捷键 / 菜单一致性。
- 管理模式多选。
- 批量收藏 / 取消收藏。
- 批量移动到分组。
明确不放行范围：
- 批量删除。
- 删除撤销。
- 逐条撤销动画。
- 批量导出。
- 颜色取色器增强。
- 搜索性能专项。
- 数据层范围归档。
用户测试建议：
- 验证快捷键 / 菜单一致性。
- 验证管理模式进入 / 退出。
- 验证选择清理。
- 验证批量收藏 / 取消收藏。
- 验证移动分组。
- 验证管理模式 Delete 不删除。
- 验证批量删除按钮不可用。
交付摘要：文档 Agent 已追加快捷键管理批次 Acceptance PASS、无删除 MVP 用户测试交接、放行范围、不放行范围和用户测试建议；未修改业务代码，未运行构建，未回退任何改动。
```

## 92. 阶段 7 用户反馈管理模式收藏分组问题分流记录

```text
调度 ID：V2-DOC-S7-USER-BUGS-MANAGEMENT-FAVORITE-GROUP-001
时间：2026-05-14
阶段：第二版阶段 7 / 用户反馈管理模式、收藏和分组问题分流
任务卡 ID：V2-DOC-S7-USER-BUGS-MANAGEMENT-FAVORITE-GROUP-001
当前会话模式：ClipEase V2 文档 / 日志 Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook，不修改业务代码
用户反馈：
- 用户建议删除管理模式及批量移动 / 批量删除等后续所有管理模式范围。
- 用户建议删除收藏概念，认为分组相当于收藏。
- bug：卡片右键移到分组二级菜单闪烁。
- bug：新建分组 / 分组双击重命名输入字符会展开搜索框。
- bug：分组颜色与图标 popover 搜索图标时会展开搜索框。
- 风险检查：同名分组下移动到分组逻辑是否正确。
主控分流：
- Product Rules：`V2-PRODUCT-S7-SCOPE-REMOVE-MANAGEMENT-FAVORITE-001`
- Bugfix：`V2-BUGFIX-S7-GROUP-INPUT-FOCUS-AND-MENU-FLICKER-001`
- Architecture：`V2-ARCH-S7-SAME-NAME-GROUP-MOVE-LOGIC-001`
当前状态：
- 等待 Product Rules 裁定是否移除管理模式、批量管理范围和收藏概念。
- 等待 Bugfix Agent 处理右键分组二级菜单闪烁、分组命名输入焦点和 popover 搜索输入焦点问题。
- 等待 Architecture Agent 检查同名分组场景下移动到分组逻辑是否按稳定 group id 执行。
交付摘要：文档 Agent 已追加用户反馈、bug、风险检查和主控三路分流记录；未修改业务代码，未运行构建，未回退任何改动。
```

## 93. 阶段 7 红线确认删除管理模式收藏与 SQLite Only 记录

```text
调度 ID：V2-DOC-REDLINE-CONFIRM-REMOVE-MANAGEMENT-FAVORITE-SQLITE-ONLY-001
时间：2026-05-14
阶段：第二版阶段 7 / 红线级范围变更确认
任务卡 ID：V2-DOC-REDLINE-CONFIRM-REMOVE-MANAGEMENT-FAVORITE-SQLITE-ONLY-001
当前会话模式：ClipEase V2 Docs/Log Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：高 / 红线级；本记录仅更新 runbook，不修改业务代码
用户确认：
- 确认删除管理模式。
- 删除收藏字段和代码，旧数据可以完全清空。
- 原 JSON 数据代码和 SQLite 迁移代码都可以删除。
- 后续开发只使用 SQLite。
- 当前开发阶段数据库数据可以清空，数据库可以重写。
主控调度：
- Product Rules Agent：V2-PRODUCT-S7-REMOVE-MANAGEMENT-FAVORITE-SQLITE-RESET-001
- Architecture Gatekeeper：V2-ARCH-SQLITE-ONLY-RESET-REMOVE-FAVORITE-MANAGEMENT-001
主控门禁：
- 在 Product Rules Agent PASS 前，主控不调业务实现删除，避免无产品基线乱删。
- 在 Architecture Gatekeeper PASS 前，主控不调业务实现删除，避免无架构基线乱删。
- Product / Architecture 均 PASS 后，主控再根据明确基线拆分实现、测试、审查和验收任务。
交付摘要：文档 Agent 已追加用户红线级确认、Product Rules / Architecture Gatekeeper 调度和 PASS 前不调业务实现删除的主控门禁；未修改业务代码，未运行构建，未回退任何改动。
```

## 94. SQLite Only 数据基线完成与 UI 删除调度记录

```text
调度 ID：V2-DOC-SQLITE-ONLY-BASELINE-COMPLETE-AND-UI-DISPATCH-001
时间：2026-05-14
阶段：第二版阶段 7 / SQLite Only 数据基线完成与 UI 删除调度
任务卡 ID：V2-DOC-SQLITE-ONLY-BASELINE-COMPLETE-AND-UI-DISPATCH-001
当前会话模式：ClipEase V2 Docs/Log Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook，不修改业务代码
已完成任务：
- `V2-IMPL-SQLITE-ONLY-DATA-BASELINE-001` 已完成。
实现摘要：
- 删除 JSON repository / repositoryKind / JSON->SQLite migration / migration_results。
- 删除 favorite 字段和 SQLite favorite columns。
- SQLite schema version 2，旧低版本 DB 直接重写为空库。
- Store 删除 favorite API。
- 保存期限清理跳过分组和置顶。
- 备份当前 schema。
验证结果：
- `swift build` 通过。
- `verify_sqlite_only_baseline` 通过。
- `verify_sqlite_migration` wrapper 通过。
- smoke 因 RC 版本未对齐 `1.0.7(260514.0340)` 暂未通过。
主控后续调度：
- 主控已调度 `V2-IMPL-REMOVE-MANAGEMENT-FAVORITE-UI-GROUP-UNIQUE-001` 做 UI 删除管理模式 / 收藏和同名分组策略。
交付摘要：文档 Agent 已追加 SQLite Only 数据基线完成、验证结果、smoke 版本阻塞和 UI 删除管理模式 / 收藏及同名分组策略调度记录；未修改业务代码，未运行构建，未回退任何改动。
```

## 95. 移除管理模式收藏 UI 完成与门禁等待记录

```text
调度 ID：V2-DOC-UI-REMOVE-MANAGEMENT-FAVORITE-COMPLETE-GATES-001
时间：2026-05-14
阶段：第二版阶段 7 / 移除管理模式与收藏 UI 完成门禁
任务卡 ID：V2-DOC-UI-REMOVE-MANAGEMENT-FAVORITE-COMPLETE-GATES-001
当前会话模式：ClipEase V2 Docs/Log Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook，不修改业务代码
已完成任务：
- `V2-IMPL-REMOVE-MANAGEMENT-FAVORITE-UI-GROUP-UNIQUE-001` 已完成。
实现摘要：
- 移除管理模式 / 多选 / 批量操作 / Command+M。
- 移除收藏 UI / 星标 / 收藏文案，改为加入 / 移动分组。
- 保留置顶和单条删除。
- 分组默认唯一命名和重命名去重。
- 脚本更新。
验证结果：
- `swift build` 通过。
- `verify_no_management_no_favorite_ui` 通过。
- `verify_group_focus_and_menu_guard` 通过。
- `verify_sqlite_only_baseline` 通过。
- `verify_history_shortcut_commands` 通过。
主控后续调度：
- 主控已调度 Test Agent `V2-TEST-SQLITE-ONLY-NO-MANAGEMENT-NO-FAVORITE-001`。
- 主控已调度 Review Agent `V2-REVIEW-SQLITE-ONLY-NO-MANAGEMENT-NO-FAVORITE-001`。
当前状态：
- 等待门禁。
交付摘要：文档 Agent 已追加移除管理模式 / 收藏 UI 完成、验证结果、Test / Review Agent 调度和等待门禁状态记录；未修改业务代码，未运行构建，未回退任何改动。
```

## 96. SQLite Only RC 版本对齐与 JSON Import groupID HOLD 记录

```text
调度 ID：V2-DOC-RC-ALIGN-SQLITE-ONLY-HOLD-001
时间：2026-05-14
阶段：第二版阶段 7 / SQLite Only RC 版本对齐与门禁 HOLD
任务卡 ID：V2-DOC-RC-ALIGN-SQLITE-ONLY-HOLD-001
当前会话模式：ClipEase V2 Docs/Log Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook 和 RC 报告，不修改业务代码
当前 RC 版本：
- `Resources/Info.plist` 当前版本为 `1.0.7(260514.0340)`。
- `docs/RELEASE_CANDIDATE_REPORT.md` 已对齐到 `1.0.7(260514.0340)`。
Test 状态：
- Test 功能验证 PASS。
- smoke blocker 仅为 `docs/RELEASE_CANDIDATE_REPORT.md` 未对齐当前 Info.plist `1.0.7(260514.0340)`。
- 本次已完成 RC 版本对齐，后续需在 bugfix 后重跑 smoke / 门禁。
Review 状态：
- Review HOLD P1：JSON import 存在 orphan groupID 风险。
- 该问题不是最终放行状态，需等待 bugfix 后重跑 Test / Review / Acceptance 门禁。
主控调度：
- 主控已调度 Bugfix Agent：`V2-BUGFIX-SQLITE-ONLY-JSON-IMPORT-GROUPID-SANITIZE-001`。
本 RC 范围记录：
- SQLite-only 数据基线。
- 无收藏字段 / 无收藏 UI。
- 无管理模式 / 无多选 / 无批量操作。
- 分组唯一命名。
- 分组命名 / popover 输入焦点修复。
当前状态：
- RC 版本文档已对齐。
- Review 仍 HOLD，等待 JSON import groupID bugfix 完成并重跑门禁。
交付摘要：文档 Agent 已追加 Test 功能 PASS 但 smoke 版本 blocker、Review HOLD P1 JSON import orphan groupID、主控 Bugfix 调度和 RC 版本对齐记录；未修改业务代码，未运行构建，未回退任何改动。
```

## 97. JSON Import groupID 修复完成与重跑门禁等待记录

```text
调度 ID：V2-DOC-JSON-IMPORT-GROUPID-FIX-RERUN-GATES-001
时间：2026-05-14
阶段：第二版阶段 7 / JSON Import groupID 修复完成与重跑门禁
任务卡 ID：V2-DOC-JSON-IMPORT-GROUPID-FIX-RERUN-GATES-001
当前会话模式：ClipEase V2 Docs/Log Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook，不修改业务代码
已完成任务：
- `V2-BUGFIX-SQLITE-ONLY-JSON-IMPORT-GROUPID-SANITIZE-001` 已完成。
修复摘要：
- 普通 JSON import 清理无效 groupID/groupedAt。
- 有效 groupID 缺 groupedAt 时补 createdAt。
- 避免孤儿分组导致保存期限错误豁免。
主控后续调度：
- 主控已调度 Test Agent `V2-TEST-SQLITE-ONLY-NO-MANAGEMENT-NO-FAVORITE-001-RERUN`。
- 主控已调度 Review Agent `V2-REVIEW-SQLITE-ONLY-NO-MANAGEMENT-NO-FAVORITE-001-RERUN`。
当前状态：
- 等待重跑门禁。
交付摘要：文档 Agent 已追加 JSON import groupID 修复完成、修复摘要、Test / Review Agent 重跑调度和等待重跑门禁状态记录；未修改业务代码，未运行构建，未回退任何改动。
```

## 98. 保存期限清理有效分组校验 HOLD 记录

```text
调度 ID：V2-DOC-PRUNE-VALID-GROUP-HOLD-001
时间：2026-05-14
阶段：第二版阶段 7 / 保存期限清理有效分组校验门禁 HOLD
任务卡 ID：V2-DOC-PRUNE-VALID-GROUP-HOLD-001
当前会话模式：ClipEase V2 Docs/Log Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook，不修改业务代码
Test 状态：
- Test Agent `V2-TEST-SQLITE-ONLY-NO-MANAGEMENT-NO-FAVORITE-001-RERUN` PASS。
Review 状态：
- Review Agent `V2-REVIEW-SQLITE-ONLY-NO-MANAGEMENT-NO-FAVORITE-001-RERUN` HOLD P2：保存期限清理只看 groupID 非空，没有校验是否为有效分组，孤儿 groupID 可能被长期保留。
主控调度：
- 主控已调度 Bugfix Agent `V2-BUGFIX-PRUNE-VALID-GROUP-RETENTION-001`。
当前状态：
- Review HOLD，等待保存期限清理有效分组校验 bugfix 完成并重跑门禁。
交付摘要：文档 Agent 已追加 Test 重跑 PASS、Review HOLD P2 保存期限清理有效分组校验问题和主控 Bugfix Agent 调度记录；未修改业务代码，未运行构建，未回退任何改动。
```

## 99. 保存期限清理有效分组修复完成与最终门禁等待记录

```text
调度 ID：V2-DOC-PRUNE-VALID-GROUP-FIX-FINAL-GATES-001
时间：2026-05-14
阶段：第二版阶段 7 / 保存期限清理有效分组修复完成与最终门禁等待
任务卡 ID：V2-DOC-PRUNE-VALID-GROUP-FIX-FINAL-GATES-001
当前会话模式：ClipEase V2 Docs/Log Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook，不修改业务代码
已完成任务：
- `V2-BUGFIX-PRUNE-VALID-GROUP-RETENTION-001` 已完成。
修复摘要：
- pruneExpiredItems 使用 validGroupIDs，只豁免置顶和有效分组。
- 孤儿 groupID 过期项按普通历史清理。
主控后续调度：
- 主控已调度最终 Test Agent `V2-TEST-SQLITE-ONLY-NO-MANAGEMENT-NO-FAVORITE-002-FINAL`。
- 主控已调度最终 Review Agent `V2-REVIEW-SQLITE-ONLY-NO-MANAGEMENT-NO-FAVORITE-002-FINAL`。
当前状态：
- 等待最终门禁。
交付摘要：文档 Agent 已追加保存期限清理有效分组修复完成、修复摘要、最终 Test / Review Agent 调度和等待最终门禁状态记录；未修改业务代码，未运行构建，未回退任何改动。
```

## 100. 备份导入旧 SQLite schema 非破坏性修复重调度记录

```text
调度 ID：V2-DOC-BACKUP-IMPORT-HOLD-001-RERUN
时间：2026-05-14
阶段：第二版阶段 7 / 备份导入旧 SQLite schema 非破坏性修复重调度
任务卡 ID：V2-DOC-BACKUP-IMPORT-HOLD-001-RERUN
当前会话模式：ClipEase V2 Docs/Log Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook，不修改业务代码
Final Test 状态：
- Final Test Agent `V2-TEST-SQLITE-ONLY-NO-MANAGEMENT-NO-FAVORITE-002-FINAL` PASS。
Final Review 状态：
- Final Review Agent `V2-REVIEW-SQLITE-ONLY-NO-MANAGEMENT-NO-FAVORITE-002-FINAL` HOLD P1：备份导入会直接 load 用户备份包内 SQLite，旧 schema 时可能被 resetLegacyDatabaseIfNeeded 删除/重写。
调度异常：
- 上一轮 Bugfix/Docs 调度因服务 503 失败，无有效输出，主控重调度。
主控调度：
- 主控已调度 Bugfix Agent `V2-BUGFIX-BACKUP-IMPORT-NONDESTRUCTIVE-SQLITE-001-RERUN`。
当前状态：
- Review HOLD，等待备份导入旧 SQLite schema 非破坏性 bugfix 完成并重跑门禁。
交付摘要：文档 Agent 已追加 Final Test PASS、Final Review HOLD P1 备份导入旧 SQLite schema 可能被删除/重写、上一轮 Bugfix/Docs 503 失败和主控 Bugfix Agent 重调度记录；未修改业务代码，未运行构建，未回退任何改动。
```

## 101. 备份导入旧 SQLite schema 非破坏性修复完成与最终门禁重跑记录

```text
调度 ID：V2-DOC-BACKUP-IMPORT-FIX-FINAL-GATES-001
时间：2026-05-14
阶段：第二版阶段 7 / 备份导入旧 SQLite schema 非破坏性修复完成与最终门禁重跑
任务卡 ID：V2-DOC-BACKUP-IMPORT-FIX-FINAL-GATES-001
当前会话模式：ClipEase V2 Docs/Log Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook，不修改业务代码
已完成任务：
- `V2-BUGFIX-BACKUP-IMPORT-NONDESTRUCTIVE-SQLITE-001-RERUN` 已完成。
修复摘要：
- 备份导入复制 SQLite/wal/shm 到临时目录。
- 导入前检查 user_version。
- 旧 schema 抛 incompatibleSQLiteBackupSchema。
- 不再直接 load/reset 用户备份包。
主控后续调度：
- 主控已调度最终重跑 Test Agent `V2-TEST-SQLITE-ONLY-NO-MANAGEMENT-NO-FAVORITE-003-FINAL-RERUN`。
- 主控已调度最终重跑 Review Agent `V2-REVIEW-SQLITE-ONLY-NO-MANAGEMENT-NO-FAVORITE-003-FINAL-RERUN`。
当前状态：
- 等待最终重跑门禁。
交付摘要：文档 Agent 已追加备份导入旧 SQLite schema 非破坏性修复完成、修复摘要、最终重跑 Test / Review Agent 调度和等待最终重跑门禁状态记录；未修改业务代码，未运行构建，未回退任何改动。
```

## 102. 备份导入 symlink / 非普通文件隔离 HOLD 与修复调度记录

```text
调度 ID：V2-DOC-BACKUP-IMPORT-SYMLINK-HOLD-001
时间：2026-05-14
阶段：第二版阶段 7 / 备份导入 symlink 与非普通文件隔离门禁 HOLD
任务卡 ID：V2-DOC-BACKUP-IMPORT-SYMLINK-HOLD-001
当前会话模式：ClipEase V2 Docs/Log Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook，不修改业务代码
Final Test 状态：
- Final Test rerun PASS。
Final Review 状态：
- Final Review HOLD P2：备份导入复制 SQLite/wal/shm 到临时目录前未拒绝 symlink/非普通文件，临时隔离不完整。
主控调度：
- 主控已调度 Bugfix `V2-BUGFIX-BACKUP-IMPORT-REJECT-SYMLINKS-001`。
当前状态：
- Review HOLD，等待备份导入拒绝 symlink / 非普通文件 bugfix 完成并重跑门禁。
交付摘要：文档 Agent 已追加 Final Test rerun PASS、Final Review HOLD P2 备份导入 symlink / 非普通文件隔离问题和主控 Bugfix 调度记录；未修改业务代码，未运行构建，未回退任何改动。
```

## 103. 备份导入 symlink / 非普通文件修复完成与最终门禁重跑记录

```text
调度 ID：V2-DOC-BACKUP-SYMLINK-FIX-FINAL-GATES-001
时间：2026-05-14
阶段：第二版阶段 7 / 备份导入 symlink 与非普通文件修复完成与最终门禁重跑
任务卡 ID：V2-DOC-BACKUP-SYMLINK-FIX-FINAL-GATES-001
当前会话模式：ClipEase V2 Docs/Log Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook，不修改业务代码
已完成任务：
- `V2-BUGFIX-BACKUP-IMPORT-REJECT-SYMLINKS-001` 已完成。
修复摘要：
- 备份导入 copy 前后校验 SQLite/wal/shm 为 regular file。
- 拒绝 symlink、目录和特殊文件。
- 非法备份明确失败。
主控后续调度：
- 主控已调度最终重跑 Test `V2-TEST-SQLITE-ONLY-NO-MANAGEMENT-NO-FAVORITE-004-FINAL-RERUN`。
- 主控已调度最终重跑 Review `V2-REVIEW-SQLITE-ONLY-NO-MANAGEMENT-NO-FAVORITE-004-FINAL-RERUN`。
当前状态：
- 等待最终重跑门禁。
交付摘要：文档 Agent 已追加备份导入 symlink / 非普通文件修复完成、修复摘要、最终重跑 Test / Review 调度和等待最终重跑门禁状态记录；未修改业务代码，未运行构建，未回退任何改动。
```

## 104. 备份导入附件文件名路径穿越 HOLD 与修复调度记录

```text
调度 ID：V2-DOC-BACKUP-ATTACHMENT-PATH-HOLD-001
时间：2026-05-14
阶段：第二版阶段 7 / 备份导入附件文件名路径穿越门禁 HOLD
任务卡 ID：V2-DOC-BACKUP-ATTACHMENT-PATH-HOLD-001
当前会话模式：ClipEase V2 Docs/Log Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook，不修改业务代码
Final Test 状态：
- Final Test rerun PASS。
Final Review 状态：
- Final Review HOLD P1：备份导入附件文件名存在路径穿越风险，恶意 SQLite 可让 image/richText fileName 为 `../...`，导入/后续删除可能越过附件目录。
主控调度：
- 主控已调度 Bugfix `V2-BUGFIX-BACKUP-IMPORT-ATTACHMENT-PATH-SAFETY-001`。
当前状态：
- Review HOLD，等待备份导入附件路径安全 bugfix 完成并重跑门禁。
交付摘要：文档 Agent 已追加 Final Test rerun PASS、Final Review HOLD P1 备份导入附件文件名路径穿越风险和主控 Bugfix 调度记录；未修改业务代码，未运行构建，未回退任何改动。
```

## 105. 备份导入附件路径安全修复完成与最终门禁重跑记录

```text
调度 ID：V2-DOC-BACKUP-ATTACHMENT-PATH-FIX-FINAL-GATES-001
时间：2026-05-14
阶段：第二版阶段 7 / 备份导入附件路径安全修复完成与最终门禁重跑
任务卡 ID：V2-DOC-BACKUP-ATTACHMENT-PATH-FIX-FINAL-GATES-001
当前会话模式：ClipEase V2 Docs/Log Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook，不修改业务代码
已完成任务：
- `V2-BUGFIX-BACKUP-IMPORT-ATTACHMENT-PATH-SAFETY-001` 已完成。
修复摘要：
- 附件 basename 校验。
- source/destination containment。
- image/richText/thumbnail safe path helper。
- 非普通附件拒绝。
- 删除侧防越界。
主控后续调度：
- 主控已调度最终重跑 Test `V2-TEST-SQLITE-ONLY-NO-MANAGEMENT-NO-FAVORITE-005-FINAL-RERUN`。
- 主控已调度最终重跑 Review `V2-REVIEW-SQLITE-ONLY-NO-MANAGEMENT-NO-FAVORITE-005-FINAL-RERUN`。
当前状态：
- 等待最终重跑门禁。
交付摘要：文档 Agent 已追加备份导入附件路径安全修复完成、修复摘要、最终重跑 Test / Review 调度和等待最终重跑门禁状态记录；未修改业务代码，未运行构建，未回退任何改动。
```

## 106. 备份附件目录 symlink HOLD 与修复调度记录

```text
调度 ID：V2-DOC-BACKUP-ATTACHMENT-DIR-SYMLINK-HOLD-001
时间：2026-05-14
阶段：第二版阶段 7 / 备份附件目录 symlink 门禁 HOLD
任务卡 ID：V2-DOC-BACKUP-ATTACHMENT-DIR-SYMLINK-HOLD-001
当前会话模式：ClipEase V2 Docs/Log Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook，不修改业务代码
Final Test 状态：
- Final Test rerun PASS。
Final Review 状态：
- Final Review HOLD P1：备份附件目录 Images/RichTexts 或 live attachment 目录若为 symlink，可绕过 standardized path containment。
主控调度：
- 主控已调度 Bugfix `V2-BUGFIX-BACKUP-IMPORT-ATTACHMENT-DIR-SYMLINK-SAFETY-001`。
当前状态：
- Review HOLD，等待备份导入附件目录 symlink safety bugfix 完成并重跑门禁。
交付摘要：文档 Agent 已追加 Final Test rerun PASS、Final Review HOLD P1 备份附件目录 Images/RichTexts 或 live attachment 目录 symlink 绕过 standardized path containment 风险和主控 Bugfix 调度记录；未修改业务代码，未运行构建，未回退任何改动。
```

## 107. 备份附件目录 symlink 安全修复完成与最终门禁重跑记录

```text
调度 ID：V2-DOC-BACKUP-DIR-SYMLINK-FIX-FINAL-GATES-001
时间：2026-05-14
阶段：第二版阶段 7 / 备份附件目录 symlink 安全修复完成与最终门禁重跑
任务卡 ID：V2-DOC-BACKUP-DIR-SYMLINK-FIX-FINAL-GATES-001
当前会话模式：ClipEase V2 Docs/Log Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook，不修改业务代码
已完成任务：
- `V2-BUGFIX-BACKUP-IMPORT-ATTACHMENT-DIR-SYMLINK-SAFETY-001` 已完成。
修复摘要：
- 拒绝备份附件目录 symlink/非目录。
- live attachment dirs 拒绝 symlink/非目录并校验 resolved containment。
- source/destination 使用 resolved containment。
主控后续调度：
- 主控已调度最终重跑 Test `V2-TEST-SQLITE-ONLY-NO-MANAGEMENT-NO-FAVORITE-006-FINAL-RERUN`。
- 主控已调度最终重跑 Review `V2-REVIEW-SQLITE-ONLY-NO-MANAGEMENT-NO-FAVORITE-006-FINAL-RERUN`。
当前状态：
- 等待最终重跑门禁。
交付摘要：文档 Agent 已追加备份附件目录 symlink 安全修复完成、修复摘要、最终重跑 Test / Review 调度和等待最终重跑门禁状态记录；未修改业务代码，未运行构建，未回退任何改动。
```

## 108. SQLite-only baseline 最终门禁通过与验收等待记录

```text
调度 ID：V2-DOC-SQLITE-ONLY-BASELINE-ACCEPT-WAIT-001
时间：2026-05-14
阶段：第二版阶段 7 / SQLite-only baseline 最终门禁通过与验收等待
任务卡 ID：V2-DOC-SQLITE-ONLY-BASELINE-ACCEPT-WAIT-001
当前会话模式：ClipEase V2 Docs/Log Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook，不修改业务代码
Final Test 状态：
- Final Test `V2-TEST-SQLITE-ONLY-NO-MANAGEMENT-NO-FAVORITE-006-FINAL-RERUN` PASS。
- 全部 11 项命令通过：
  1. `swift build`
  2. `python3 scripts/smoke_check.py`
  3. `python3 scripts/verify_sqlite_migration.py`
  4. `python3 scripts/verify_sqlite_only_baseline.py`
  5. `python3 scripts/verify_no_management_no_favorite_ui.py`
  6. `python3 scripts/verify_history_shortcut_commands.py`
  7. `python3 scripts/verify_group_focus_and_menu_guard.py`
  8. `python3 scripts/verify_batch_favorite_group_mvp.py`
  9. `python3 scripts/verify_json_import_groupid_sanitize.py`
  10. `python3 scripts/verify_retention_valid_group_ids.py`
  11. `python3 scripts/verify_backup_import_nondestructive.py`
Final Review 状态：
- Final Review `V2-REVIEW-SQLITE-ONLY-NO-MANAGEMENT-NO-FAVORITE-006-FINAL-RERUN` PASS。
主控调度：
- 主控已调度 Acceptance `V2-ACCEPT-SQLITE-ONLY-NO-MANAGEMENT-NO-FAVORITE-001`。
当前状态：
- 等待验收。
交付摘要：文档 Agent 已追加 Final Test 006 FINAL RERUN PASS、全部 11 项命令通过、Final Review 006 FINAL RERUN PASS、Acceptance 调度和等待验收状态记录；未修改业务代码，未运行构建，未回退任何改动。
```

## 109. SQLite-only 新基线后加入分组二级菜单闪烁 bug 记录

```text
调度 ID：V2-DOC-MOVE-TO-GROUP-SUBMENU-FLICKER-001
时间：2026-05-14
阶段：第二版阶段 7 / SQLite-only 新基线后 UI 交互 bug
任务卡 ID：V2-DOC-MOVE-TO-GROUP-SUBMENU-FLICKER-001
当前会话模式：ClipEase V2 Docs/Log Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook，不修改业务代码
用户反馈 bug：
- 卡片右键菜单“加入分组”二级菜单“分组1/分组2...”一直闪烁（关闭/显示无限循环），无法点击。
归类：
- Stage 7 / SQLite-only 新基线后 UI 交互 bug。
- 小范围 Bugfix。
主控调度：
- 主控已调度 Bugfix Agent：`V2-BUGFIX-MOVE-TO-GROUP-SUBMENU-FLICKER-001`。
禁改范围：
- 不恢复收藏/管理模式。
- 不改 SQLite schema/repository/migration。
当前状态：
- 等待 Bugfix Agent 完成局部修复后进入对应 Test / Review / Acceptance 门禁。
交付摘要：文档 Agent 已追加卡片右键菜单“加入分组”二级菜单闪烁无法点击的用户反馈 bug、Stage 7 / SQLite-only 新基线后 UI 交互 bug 归类、Bugfix Agent 调度和禁改范围记录；未修改业务代码，未运行构建，未回退任何改动。
```

## 110. 加入分组二级菜单闪烁修复完成与门禁调度记录

```text
调度 ID：V2-DOC-MOVE-TO-GROUP-SUBMENU-FLICKER-FIX-GATES-001
时间：2026-05-14
阶段：第二版阶段 7 / SQLite-only 新基线后 UI 交互 bug 修复完成与门禁调度
任务卡 ID：V2-DOC-MOVE-TO-GROUP-SUBMENU-FLICKER-FIX-GATES-001
当前会话模式：ClipEase V2 Docs/Log Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook，不修改业务代码
已完成任务：
- `V2-BUGFIX-MOVE-TO-GROUP-SUBMENU-FLICKER-001` 已完成。
定位：
- 完整 `ClipboardGroup` 快照 + `store.groups` 变化时无条件写 `@State`，导致 SwiftUI 菜单重建闪烁。
修复摘要：
- 使用轻量 `MoveToGroupMenuEntry`。
- 仅内容变化时写 state。
- 菜单 body 不读 `store.groups`、不刷新 snapshot。
- `ForEach` 按 id。
- 不恢复收藏/管理模式。
主控后续调度：
- 主控已调度 Test `V2-TEST-MOVE-TO-GROUP-SUBMENU-FLICKER-001`。
- 主控已调度 Review `V2-REVIEW-MOVE-TO-GROUP-SUBMENU-FLICKER-001`。
当前状态：
- 等待 Test / Review 门禁结果。
交付摘要：文档 Agent 已追加加入分组二级菜单闪烁修复完成、定位、修复摘要、Test / Review 调度和等待门禁状态记录；未修改业务代码，未运行构建，未回退任何改动。
```

## 111. 加入分组二级菜单闪烁修复 RC 版本对齐记录

```text
调度 ID：V2-DOC-RC-ALIGN-MOVE-TO-GROUP-FLICKER-001
时间：2026-05-14
阶段：第二版阶段 7 / 加入分组二级菜单稳定性修复 RC 版本对齐
任务卡 ID：V2-DOC-RC-ALIGN-MOVE-TO-GROUP-FLICKER-001
当前会话模式：ClipEase V2 Docs/Log Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook 和 RC 报告，不修改业务代码
当前 RC 版本：
- `Resources/Info.plist` 当前版本为 `1.0.8(260514.1714)`。
- `docs/RELEASE_CANDIDATE_REPORT.md` 已对齐到 `1.0.8(260514.1714)`。
Test 状态：
- Test 对“加入分组”二级菜单闪烁修复的功能验证 PASS。
- smoke 因 `docs/RELEASE_CANDIDATE_REPORT.md` 未对齐当前 Info.plist `1.0.8(260514.1714)` HOLD。
Review 状态：
- Review PASS。
本 RC 范围记录：
- SQLite-only 新基线。
- 无收藏 / 无收藏 UI。
- 无管理模式 / 无多选 / 无批量操作。
- 备份导入安全修复。
- 加入分组二级菜单稳定性修复。
主控调度：
- 主控调度 RC 对齐已完成。
- 后续将重跑 Test，重新验证 smoke / 门禁。
当前状态：
- RC 版本文档已对齐。
- 等待 Test 重跑。
交付摘要：文档 Agent 已追加 Test 功能 PASS 但 smoke 版本 HOLD、Review PASS、主控调度 RC 对齐和后续重跑 Test 记录；未修改业务代码，未运行构建，未回退任何改动。
```

## 112. 加入分组二级菜单闪烁修复 Test 重跑等待结果记录

```text
调度 ID：V2-DOC-MOVE-TO-GROUP-RERUN-TEST-001
时间：2026-05-14
阶段：第二版阶段 7 / 加入分组二级菜单稳定性修复 Test 重跑
任务卡 ID：V2-DOC-MOVE-TO-GROUP-RERUN-TEST-001
当前会话模式：ClipEase V2 Docs/Log Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook，不修改业务代码
当前 RC 版本：
- RC report 已对齐 `1.0.8(260514.1714)`。
主控调度：
- 主控已重跑 Test `V2-TEST-MOVE-TO-GROUP-SUBMENU-FLICKER-001-RERUN`。
当前状态：
- 等待测试结果。
交付摘要：文档 Agent 已追加 RC report 对齐 `1.0.8(260514.1714)`、主控已重跑 Test 和等待测试结果记录；未修改业务代码，未运行构建，未回退任何改动。
```

## 113. 加入分组二级菜单闪烁修复验收等待记录

```text
调度 ID：V2-DOC-MOVE-TO-GROUP-FLICKER-ACCEPT-WAIT-001
时间：2026-05-14
阶段：第二版阶段 7 / 加入分组二级菜单稳定性修复验收等待
任务卡 ID：V2-DOC-MOVE-TO-GROUP-FLICKER-ACCEPT-WAIT-001
当前会话模式：ClipEase V2 Docs/Log Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook，不修改业务代码
Test 状态：
- Test rerun PASS。
Review 状态：
- Review PASS。
主控调度：
- 主控已调度 Acceptance `V2-ACCEPT-MOVE-TO-GROUP-SUBMENU-FLICKER-001`。
当前状态：
- 等待验收。
交付摘要：文档 Agent 已追加 Test rerun PASS、Review PASS、主控已调度 Acceptance `V2-ACCEPT-MOVE-TO-GROUP-SUBMENU-FLICKER-001` 和当前等待验收记录；未修改业务代码，未运行构建，未回退任何改动。
```

## 114. 加入分组二级菜单闪烁 bug 重开记录

```text
调度 ID：V2-DOC-MOVE-TO-GROUP-FLICKER-REOPEN-002
时间：2026-05-14
阶段：第二版阶段 7 / 加入分组二级菜单闪烁 bug 重开
任务卡 ID：V2-DOC-MOVE-TO-GROUP-FLICKER-REOPEN-002
当前会话模式：ClipEase V2 Docs/Log Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook，不修改业务代码
用户实机复测结果：
- 用户实机复测确认上一轮 `V2-BUGFIX-MOVE-TO-GROUP-SUBMENU-FLICKER-001` 未解决问题。
现象：
- 卡片右键悬停“加入分组”的下一级菜单依旧循环关闭 / 打开闪烁，无法点击。
主控判定：
- 上一轮静态门禁不足。
- bug 重开。
- 修复任务升级为 `V2-BUGFIX-MOVE-TO-GROUP-SUBMENU-FLICKER-002`。
新要求：
- 修复后主控自动构建并运行 App 给用户测试，不再等待用户说“构建运行 App”。
禁改范围：
- 不恢复收藏 / 管理模式。
- 不改 schema / repository / migration。
当前状态：
- 等待 Bugfix Agent 按 `V2-BUGFIX-MOVE-TO-GROUP-SUBMENU-FLICKER-002` 重新定位并修复。
交付摘要：文档 Agent 已追加用户实机复测确认上一轮修复未解决、二级菜单仍循环关闭 / 打开闪烁无法点击、主控判定静态门禁不足并重开升级为 `V2-BUGFIX-MOVE-TO-GROUP-SUBMENU-FLICKER-002`、修复后自动构建运行 App 给用户测试的新要求和禁改范围；未修改业务代码，未运行构建，未回退任何改动。
```

## 115. 加入分组选择器方案完成与门禁调度记录

```text
调度 ID：V2-DOC-MOVE-TO-GROUP-FLICKER-002-GATES-001
时间：2026-05-14
阶段：第二版阶段 7 / 加入分组选择器方案完成与门禁调度
任务卡 ID：V2-DOC-MOVE-TO-GROUP-FLICKER-002-GATES-001
当前会话模式：ClipEase V2 Docs/Log Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook，不修改业务代码
完成项：
- `V2-BUGFIX-MOVE-TO-GROUP-SUBMENU-FLICKER-002` 已完成。
根因：
- SwiftUI nested context submenu 在真实 macOS hover 下仍会重建闪烁。
新方案：
- 移除二级菜单。
- 右键一级项“加入分组...”/“移动到分组...”打开稳定 sheet 分组选择器。
- 按 group id 移动。
主控调度：
- 主控已调度 Test/Review。
- 修复通过后会自动构建运行 App。
当前状态：
- 等待 Test/Review 门禁结果。
交付摘要：文档 Agent 已追加 `V2-BUGFIX-MOVE-TO-GROUP-SUBMENU-FLICKER-002` 完成、真实 macOS hover 下 SwiftUI nested context submenu 重建闪烁根因、改为一级菜单打开稳定 sheet 分组选择器并按 group id 移动的新方案，以及主控已调度 Test/Review、修复通过后自动构建运行 App 的记录；未修改业务代码，未运行构建，未回退任何改动。
```

## 116. 加入分组 picker 方案 RC 版本对齐记录

```text
调度 ID：V2-DOC-RC-ALIGN-MOVE-TO-GROUP-PICKER-001
时间：2026-05-14
阶段：第二版阶段 7 / 加入分组 picker 方案 RC 版本对齐
任务卡 ID：V2-DOC-RC-ALIGN-MOVE-TO-GROUP-PICKER-001
当前会话模式：ClipEase V2 Docs/Log Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook 和 RC 报告，不修改业务代码
当前 RC 版本：
- `Resources/Info.plist` 当前版本为 `1.0.9(260514.1835)`。
- `docs/RELEASE_CANDIDATE_REPORT.md` 已对齐到 `1.0.9(260514.1835)`。
Test 状态：
- Test 对加入分组 picker 方案功能验证 PASS。
- smoke 因 `docs/RELEASE_CANDIDATE_REPORT.md` 未对齐当前 Info.plist `1.0.9(260514.1835)` HOLD。
Review 状态：
- Review PASS。
本 RC 范围记录：
- SQLite-only 新基线。
- 无收藏 / 无收藏 UI。
- 无管理模式 / 无多选 / 无批量操作。
- 备份导入安全修复。
- 加入分组 picker 替代闪烁二级菜单。
主控调度：
- 主控调度 RC 对齐已完成。
- 后续将重跑 Test。
当前状态：
- RC 版本文档已对齐。
- 等待 Test 重跑 smoke / 门禁。
交付摘要：文档 Agent 已追加 Test 功能 PASS 但 smoke 版本 HOLD、Review PASS、主控调度 RC 对齐和后续将重跑 Test 记录；未修改业务代码，未运行构建，未回退任何改动。
```

## 117. 加入分组 picker 方案验收等待记录

```text
调度 ID：V2-DOC-MOVE-TO-GROUP-PICKER-ACCEPT-WAIT-001
时间：2026-05-14
阶段：第二版阶段 7 / 加入分组 picker 方案验收等待
任务卡 ID：V2-DOC-MOVE-TO-GROUP-PICKER-ACCEPT-WAIT-001
当前会话模式：ClipEase V2 Docs/Log Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook，不修改业务代码
Test 状态：
- Test rerun PASS。
Review 状态：
- Review PASS。
主控调度 Acceptance：
- Acceptance 任务卡为 `V2-ACCEPT-MOVE-TO-GROUP-SUBMENU-FLICKER-002`。
- 验收 PASS 后，主控将自动构建并运行 App 给用户测试。
当前状态：
- 等待 Acceptance 验收结果。
交付摘要：文档 Agent 已追加 Test rerun PASS、Review PASS、主控调度 Acceptance `V2-ACCEPT-MOVE-TO-GROUP-SUBMENU-FLICKER-002`，以及验收 PASS 后主控将自动构建运行 App 的记录；未修改业务代码，未运行构建，未回退任何改动。
```

## 118. 历史卡片选择聚焦右键边框 bugfix 调度记录

```text
调度 ID：V2-DOC-HISTORY-SELECTION-FOCUS-RIGHTCLICK-BORDER-001
时间：2026-05-14
阶段：第二版阶段 7 / 历史卡片选择聚焦与选中边框 bugfix 调度
任务卡 ID：V2-DOC-HISTORY-SELECTION-FOCUS-RIGHTCLICK-BORDER-001
当前会话模式：ClipEase V2 Docs/Log Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook，不修改业务代码
用户反馈 bug：
- 用户复制新剪切板时，主窗口打开必须定位到新剪切板卡片。
- 卡片右键也要像左键一样更新选中外框，表示操作目标。
- 卡片选中时，主窗口顶部栏遮挡上边缘外框，需要修复。
主控分流：
- Bugfix Agent：`V2-BUGFIX-HISTORY-SELECTION-FOCUS-RIGHTCLICK-BORDER-001`
禁改范围：
- 不恢复收藏 / 管理模式。
- 不改 schema / repository / migration。
后续门禁：
- Bugfix 修复完成后需进入 Test / Review / Acceptance。
- Test / Review / Acceptance 通过后，主控需自动构建并运行 App，供用户实机测试。
当前状态：
- 等待 Bugfix Agent 按 `V2-BUGFIX-HISTORY-SELECTION-FOCUS-RIGHTCLICK-BORDER-001` 定位并修复。
交付摘要：文档 Agent 已追加用户关于新剪切板打开定位、右键更新选中外框、顶部栏遮挡选中上边缘外框的 bug 记录，完成主控分流、禁改范围和后续 Test / Review / Acceptance / 自动构建运行 App 门禁记录；未修改业务代码，未运行构建，未回退任何改动。
```

## 119. 历史卡片选择聚焦右键边框 bugfix 完成与 RC 对齐记录

```text
调度 ID：V2-DOC-HISTORY-SELECTION-FIX-RC-ALIGN-001
时间：2026-05-14
阶段：第二版阶段 7 / 历史卡片选择聚焦右键边框 bugfix 完成与 RC 版本对齐
任务卡 ID：V2-DOC-HISTORY-SELECTION-FIX-RC-ALIGN-001
当前会话模式：ClipEase V2 Docs/Log Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook 和 RC 报告，不修改业务代码
Bugfix 状态：
- `V2-BUGFIX-HISTORY-SELECTION-FOCUS-RIGHTCLICK-BORDER-001` 已完成。
修复范围：
- 新剪切板进入历史后，主窗口打开定位到最新剪切板卡片。
- 卡片右键与左键一致更新 selection / focus 外框，明确右键操作目标。
- 调整历史卡片选中边框展示，避免主窗口顶部栏遮挡上边缘外框。
当前 RC 版本：
- `Resources/Info.plist` 当前版本为 `1.0.10(260514.1852)`。
- `docs/RELEASE_CANDIDATE_REPORT.md` 已对齐到 `1.0.10(260514.1852)`。
本 RC 范围记录：
- SQLite-only 新基线。
- 无收藏 / 无收藏 UI。
- 无管理模式 / 无多选 / 无批量操作。
- 备份导入安全修复。
- 加入分组 picker 替代闪烁二级菜单。
- 历史卡片 selection / focus / right-click / border 修复。
门禁状态：
- smoke 此前仅因 RC report 未对齐当前 Info.plist `1.0.10(260514.1852)` HOLD。
- 完成本次 RC 对齐后，需由 Test 重跑 smoke / 门禁。
主控调度 Review：
- 主控调度 Review 已记录，需复核本次 bugfix 与 RC 对齐是否满足放行条件。
当前状态：
- RC 版本文档已对齐。
- 等待 Test 重跑 smoke / 门禁和主控调度 Review 结论。
交付摘要：文档 Agent 已追加 bugfix 完成、RC 版本对齐到 `1.0.10(260514.1852)`、本 RC 包含 SQLite-only 新基线 / 加入分组 picker / 历史卡片 selection-focus-right-click-border 修复，以及主控调度 Review 记录；未修改业务代码，未运行构建，未回退任何改动。
```

## 120. 历史卡片选择聚焦右键边框 bugfix 验收等待记录

```text
调度 ID：V2-DOC-HISTORY-SELECTION-FOCUS-RIGHTCLICK-BORDER-ACCEPT-WAIT-001
时间：2026-05-14
阶段：第二版阶段 7 / 历史卡片选择聚焦右键边框 bugfix 验收等待
任务卡 ID：V2-BUGFIX-HISTORY-SELECTION-FOCUS-RIGHTCLICK-BORDER-001
当前会话模式：ClipEase V2 Docs/Log Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook，不修改业务代码
Test Agent 结果：
- Test Agent 已完成 PASS。
- `smoke_check` 通过。
- `verify_history_selection_focus` 通过。
- `verify_no_management_no_favorite_ui` 通过。
- `verify_group_focus_and_menu_guard` 通过。
- `verify_move_to_group_menu_stability` 通过。
- `verify_sqlite_only_baseline` 通过。
- `swift build` 通过。
Review Agent 结果：
- Review Agent 已 PASS。
主控调度 Acceptance：
- Acceptance Agent 已调度：`V2-ACCEPT-HISTORY-SELECTION-FOCUS-RIGHTCLICK-BORDER-001`。
- 验收通过后，主控将构建并运行 App，供用户测试。
当前状态：
- 当前无 blocker。
- 等待 Acceptance Agent 验收结果。
交付摘要：文档 Agent 已追加 Test Agent 全量验证 PASS、Review Agent PASS、Acceptance Agent `V2-ACCEPT-HISTORY-SELECTION-FOCUS-RIGHTCLICK-BORDER-001` 已调度、当前无 blocker，以及等待验收后主控将构建运行 App 供用户测试的记录；未修改业务代码，未运行构建，未回退任何改动。
```

## 121. 历史卡片选择聚焦右键边框 bugfix 主控最终运行记录

```text
调度 ID：V2-DOC-HISTORY-SELECTION-FOCUS-RIGHTCLICK-BORDER-FINAL-RUN-001
时间：2026-05-14
阶段：第二版阶段 7 / 历史卡片选择聚焦右键边框 bugfix 主控最终运行
任务卡 ID：V2-BUGFIX-HISTORY-SELECTION-FOCUS-RIGHTCLICK-BORDER-001
当前会话模式：ClipEase V2 Docs/Log Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook，不修改业务代码
Acceptance Agent 结果：
- Acceptance Agent 已 PASS。
主控最终操作：
- 主控在 Acceptance Agent PASS 后执行构建并运行 App，供用户测试。
- 构建命令：`scripts/build-app.sh`
- 版本变化：`1.0.10 (260514.1852)` -> `1.0.11 (260514.1916)`
- 构建产物：`/Users/wpc/code/codex/ClipboardHistory/.build/ClipEase.app`
- 启动方式：`pkill -x ClipEase` 后 `open -n -a .build/ClipEase.app`
运行状态：
- 目标 App 运行进程：`/Users/wpc/code/codex/ClipboardHistory/.build/ClipEase.app/Contents/MacOS/ClipEase`
- PID：`464`
- 注意：`pgrep` 输出里还有 Xcode / `swift-frontend` index 进程，不是目标 App 运行进程。
用户待测点：
- 复制新剪切板后打开主窗口定位到新卡片。
- 右键卡片同步外边框选中。
- 选中卡片顶部外边框不被顶部栏遮挡。
当前状态：
- App 已构建并启动，等待用户实机测试反馈。
交付摘要：文档 Agent 已追加 Acceptance Agent PASS 后主控构建运行 App 的最终记录，包含构建命令、版本变化、构建产物、启动方式、目标运行进程 PID、`pgrep` 干扰进程提示，以及用户待测点；未修改业务代码，未运行构建，未回退任何改动。
```

## 122. SQLite-only 新基线文档漂移审计记录

```text
调度 ID：V2-DOC-TEST-S7-BASELINE-DRIFT-AUDIT-001
时间：2026-05-14 19:46:15 CST
阶段：第二版阶段 7 / SQLite-only 新基线文档漂移审计
任务卡 ID：V2-DOC-TEST-S7-BASELINE-DRIFT-AUDIT-001
当前会话模式：ClipEase V2 Docs/Log + Test Plan Agent
主控 Agent：Codex 主控 Agent
风险等级：低；本轮只更新文档，不修改业务代码
最新用户确认基线：
- SQLite-only；旧 JSON 数据代码和 SQLite 迁移代码可以删除，旧数据可清空。
- 无收藏字段 / 无收藏代码 / 无收藏 UI。
- 无管理模式 / 无多选 / 无批量操作。
- 置顶和分组保留。
- Bugfix Agent 已存在，主控只调度不写业务代码。
审计范围：
- docs/V2_DEVELOPMENT_PLAN.md
- docs/V2_PRODUCT_PLAN.md
- docs/V2_TECHNICAL_PLAN.md
- docs/V2_TEST_PLAN.md
- docs/V2_AGENT_RUNBOOK.md
- docs/V2_OPTIMIZATION_BACKLOG.md
已修正文档：
- docs/V2_DEVELOPMENT_PLAN.md：新增 2026-05-14 新基线覆盖说明；将阶段 7 从“编辑、快捷键和批量管理”改为“编辑、快捷键和单条操作”；明确不恢复收藏、管理模式、多选或批量操作。
- docs/V2_TEST_PLAN.md：新增 2026-05-14 新基线覆盖说明；将阶段 7 测试门禁改为 SQLite-only、无收藏/管理/批量、单条删除、单条移动分组、置顶和分组回归。
主要文档漂移：
- docs/V2_PRODUCT_PLAN.md 和 docs/V2_TECHNICAL_PLAN.md 仍有大量早期收藏、管理模式、多选、批量操作和 JSON 迁移策略描述，需后续集中重写或加顶层覆盖说明。
- docs/V2_DEVELOPMENT_PLAN.md 早期阶段 1-6 仍保留 JSON 迁移、旧 JSON 实现、收藏阶段和部分批量分组管理描述；本轮仅修正顶层覆盖说明和阶段 7 当前门禁。
- docs/V2_TEST_PLAN.md 阶段 1 和搜索专项仍保留 JSON 迁移样本、收藏筛选、批量删除等历史测试项；本轮仅修正顶层覆盖说明和阶段 7 当前门禁。
- docs/V2_OPTIMIZATION_BACKLOG.md 中部分历史 backlog 仍以批量管理增强、收藏筛选或旧阶段 7 范围描述为背景，后续需标注为旧基线项或归档关闭。
当前状态：
- 阶段 7 当前执行门禁已按新基线同步。
- 产品方案和技术方案仍存在非阻塞历史漂移，建议单独调度 Docs Agent 做全量基线重写。
交付摘要：文档 Agent 已完成六份文档漂移审计，修正开发计划和测试计划中阶段 7 最明显错误描述，并追加 runbook 调度记录；未修改业务代码，未运行构建，未回退任何改动。
```

## 123. 阶段 7 收口与阶段 8 第一批调度记录

```text
调度 ID：V2-DOC-S8-FIRST-BATCH-DISPATCH-001
时间：2026-05-14
阶段：第二版阶段 7 收口 / 阶段 8 第一批调度
任务卡 ID：V2-DOC-S8-FIRST-BATCH-DISPATCH-001
当前会话模式：ClipEase V2 Docs/Log Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook，不修改业务代码
阶段 7 收口结论：
- Product Rules、Architecture Gatekeeper、Docs/Test Plan 三方结论一致：阶段 7 可收口，允许进入阶段 8。
最新基线：
- SQLite-only。
- 无收藏。
- 无管理模式 / 多选 / 批量。
- 置顶和分组保留。
阶段 8 第一批范围：
- 第一批只限 UI / 焦点 / 窗口层级 / 全局提示低风险范围。
- 不进入 Core / Storage 数据层重构。
- 不变更模型、存储格式、导入导出、清理策略或搜索下沉。
阶段 8 第一批红线禁改：
- 禁改 schema。
- 禁改 SQLite 文件格式。
- 禁改备份 / 导入。
- 禁改附件路径 / 生命周期。
- 禁改保存期限清理。
- 禁止恢复收藏 / 管理 / 多选 / 批量。
- 禁止恢复 JSON Repository / JSON migration。
- 禁止 LIKE / FTS / Repository 查询下沉。
文件锁：
- `Sources/ClipEase/UI/HistoryWindow/HistoryWindowView.swift`：由 UI Agent 任务 `V2-S8-WINDOW-EXPERIENCE-FIRST-BATCH-001` 持有。
- `Sources/ClipEase/UI/HistoryWindow/HistoryWindowController.swift`：由 UI Agent 任务 `V2-S8-WINDOW-EXPERIENCE-FIRST-BATCH-001` 持有。
- `Sources/ClipEase/UI/HistoryWindow/HistoryCardView.swift`：由 UI Agent 任务 `V2-S8-WINDOW-EXPERIENCE-FIRST-BATCH-001` 持有。
- `Sources/ClipEase/UI/HistoryWindow/HistoryWindowInputState.swift`：由 UI Agent 任务 `V2-S8-WINDOW-EXPERIENCE-FIRST-BATCH-001` 持有。
- `Sources/ClipEase/Core/Storage/`：禁改。
- `Sources/ClipEase/Core/Models/ClipboardItem.swift`：禁改。
主控调度：
- 已调度 UI Agent：`V2-S8-WINDOW-EXPERIENCE-FIRST-BATCH-001`。
- 已调度 UX Agent：阶段 8 第一批 UI / 焦点 / 窗口层级 / 全局提示体验约束与验收建议。
后续门禁：
- 后续需调度 Test Agent 覆盖阶段 8 第一批 UI / 焦点 / 窗口层级 / 全局提示低风险范围。
- 后续需调度 Review Agent 复核红线禁改、文件锁和低风险范围。
- 后续需调度 Acceptance Agent 做阶段 8 第一批放行判断。
当前状态：
- 阶段 7 可收口。
- 阶段 8 第一批已进入 UI Agent / UX Agent 调度。
- 当前记录未修改业务代码，未运行构建。
交付摘要：文档 Agent 已追加阶段 7 收口、阶段 8 第一批调度、最新 SQLite-only 新基线、红线禁改、文件锁、UI Agent / UX Agent 已调度和后续 Test / Review / Acceptance 门禁记录；未修改业务代码，未运行构建，未回退任何改动。
```

## 124. 阶段 8 第一批完成与 RC 对齐记录

```text
调度 ID：V2-DOC-S8-FIRST-BATCH-COMPLETE-RC-ALIGN-001
时间：2026-05-14
阶段：第二版阶段 8 第一批完成 / RC 文档版本对齐
任务卡 ID：V2-DOC-S8-FIRST-BATCH-COMPLETE-RC-ALIGN-001
当前会话模式：ClipEase V2 Docs/Log Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新文档，不修改业务代码
Info.plist 版本检查：
- `Resources/Info.plist` 当前版本为 `1.0.11(260514.1916)`。
- `docs/RELEASE_CANDIDATE_REPORT.md` 此前仍停留在 `1.0.10(260514.1852)`。
- 本次仅做 RC 文档版本对齐，并加入 stage8 first batch 说明。
阶段 8 第一批完成状态：
- UI Agent `V2-S8-WINDOW-EXPERIENCE-FIRST-BATCH-001` 已完成。
- UX Agent 已完成阶段 8 第一批 UI / 焦点 / 窗口层级 / 全局提示体验约束与验收建议。
- 主控已调度 Test Agent 覆盖阶段 8 第一批 UI / 焦点 / 窗口层级 / 全局提示低风险范围。
- 主控已调度 Review Agent 复核红线禁改、文件锁和低风险范围。
实现摘要：
- 新剪切板定位只在真实新增顶部记录时触发。
- 无新历史按视图恢复横向位置。
- 用户分组 / 置顶下捕获普通新剪切板后，下次打开切到全部并定位新记录。
- 预览作为 child window，主窗口关闭 / 隐藏 / 失焦清理预览。
- 新建文本从主窗口更多菜单打开时隐藏主窗口，保存后打开并选中新记录，分组归属使用现有 API。
- 更多按钮为 `...`，未恢复收藏 / 管理 / 多选 / 批量入口。
RC 对齐：
- `docs/RELEASE_CANDIDATE_REPORT.md` 已对齐到 `1.0.11(260514.1916)`。
- RC 说明已加入 stage8 first batch：窗口体验第一批、预览 child window 生命周期、新建文本入口和无收藏 / 管理 / 多选 / 批量入口恢复。
后续动作：
- 等待 Test Agent 和 Review Agent 结果。
- Test / Review 通过后再进入 Acceptance Agent 放行判断。
- 当前记录未运行构建，未执行 smoke，未修改业务代码。
交付摘要：文档 Agent 已追加阶段 8 第一批 UI Agent 完成、UX Agent 完成、主控已调度 Test / Review、Info.plist 版本检查、RC 报告对齐到 `1.0.11(260514.1916)` 和 stage8 first batch 实现摘要；未修改业务代码，未运行构建，未回退任何改动。
```

## 125. 阶段 8 第一批 Test/Review HOLD 与返工调度记录

```text
调度 ID：V2-DOC-S8-FIRST-BATCH-HOLD-REWORK-001
时间：2026-05-14
阶段：第二版阶段 8 第一批 / Test 与 Review HOLD 返工调度
任务卡 ID：V2-DOC-S8-FIRST-BATCH-HOLD-REWORK-001
当前会话模式：ClipEase V2 Docs/Log Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新文档，不修改业务代码
Test HOLD / BLOCKED：
- `verify_sqlite_only_baseline` BLOCKED：命中 `scripts/verify_stage8_window_experience.py` 内 `isFavorite` 字符串。
- smoke 因 RC 版本未对齐 HOLD；Docs 已随后将 RC 文档对齐到 `1.0.11(260514.1916)`。
Review HOLD：
- P1：预览窗口内关闭按钮未同步 `previewState`。
- P1：新剪切板定位 / 筛选清理与无新历史恢复状态存在覆盖风险。
- P2：聚焦 item 后 `saveOffset(0)` 可能破坏按视图横向位置记忆。
- Storage 范围风险属于前序已接受改动，阶段 8 禁改仍有效。
主控返工调度：
- 已调度 Bugfix Agent：`V2-BUGFIX-S8-WINDOW-EXPERIENCE-HOLD-001`。
禁改范围不变：
- 禁改 Storage / schema / backup / import / attachment / retention / Repository / FTS / LIKE。
- 不恢复收藏 / 管理 / 多选 / 批量。
后续动作：
- 等待 Bugfix Agent 修复阶段 8 第一批窗口体验 HOLD。
- 修复完成后重跑 Test / Review 门禁。
- Review HOLD 解除后再进入 Acceptance Agent 放行判断。
当前状态：
- 阶段 8 第一批暂不放行。
- Test 存在 BLOCKED / HOLD，Review 存在 P1/P2 HOLD。
- 当前记录未修改业务代码，未运行构建，未回退任何改动。
交付摘要：文档 Agent 已追加阶段 8 第一批 Test BLOCKED / smoke HOLD、Review P1/P2 HOLD、Bugfix Agent 返工调度和禁改范围不变记录；未修改业务代码，未运行构建，未回退任何改动。
```

## 126. 阶段 8 第一批返工完成与重跑门禁调度记录

```text
调度 ID：V2-DOC-S8-FIRST-BATCH-REWORK-COMPLETE-GATES-001
时间：2026-05-14
阶段：第二版阶段 8 第一批 / Bugfix 返工完成与 Test/Review 重跑调度
任务卡 ID：V2-DOC-S8-FIRST-BATCH-REWORK-COMPLETE-GATES-001
当前会话模式：ClipEase V2 Docs/Log Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新文档，不修改业务代码
返工完成：
- Bugfix Agent `V2-BUGFIX-S8-WINDOW-EXPERIENCE-HOLD-001` 已完成。
修复摘要：
- 修复预览关闭状态同步，预览窗口关闭时同步清理 `previewState`。
- 修复新剪切板 pending 消费时机，避免筛选清理与无新历史恢复状态互相覆盖。
- 修复 `saveOffset(0)` 横向位置覆盖风险，避免聚焦 item 时破坏按视图横向位置记忆。
- 修复验证脚本禁词误触发，避免阶段 8 窗口体验验证脚本自身字符串导致 `verify_sqlite_only_baseline` BLOCKED。
主控重跑调度：
- 已调度 Test Agent 重跑：`V2-TEST-S8-WINDOW-EXPERIENCE-FIRST-BATCH-RERUN-001`。
- 已调度 Review Agent 重跑：`V2-REVIEW-S8-WINDOW-EXPERIENCE-FIRST-BATCH-RERUN-001`。
禁改范围不变：
- 禁改 Storage / schema / backup / import / attachment / retention / Repository / FTS / LIKE。
- 不恢复收藏 / 管理 / 多选 / 批量。
后续动作：
- 等待 Test Agent 重跑阶段 8 第一批窗口体验门禁。
- 等待 Review Agent 复核 HOLD 修复和红线禁改范围。
- Test / Review 通过后再进入 Acceptance Agent 放行判断。
当前状态：
- 阶段 8 第一批返工已完成，进入 Test / Review 重跑门禁。
- 当前记录未修改业务代码，未运行构建，未回退任何改动。
交付摘要：文档 Agent 已追加 `V2-BUGFIX-S8-WINDOW-EXPERIENCE-HOLD-001` 完成、预览关闭状态同步、新剪切板 pending 消费时机、`saveOffset(0)` 横向位置覆盖、验证脚本禁词误触发修复摘要，以及 Test / Review 重跑调度 `V2-TEST-S8-WINDOW-EXPERIENCE-FIRST-BATCH-RERUN-001` 和 `V2-REVIEW-S8-WINDOW-EXPERIENCE-FIRST-BATCH-RERUN-001`；未修改业务代码，未运行构建，未回退任何改动。
```

## 127. Dev-log 文档卫生修复记录

```text
调度 ID：V2-DOC-FIX-TRAILING-WHITESPACE-DEVLOG-001
时间：2026-05-14
阶段：第二版阶段 8 / 文档卫生修复
任务卡 ID：V2-DOC-FIX-TRAILING-WHITESPACE-DEVLOG-001
当前会话模式：ClipEase V2 Docs/Log Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；仅修复 dev-log 尾随空格并追加本记录，不修改业务代码
修复摘要：
- 已修复 `dev-logs/2026-05-13.md` 第 204 行尾随空格。
门禁状态：
- Test 业务门禁已除 `git diff --check` 外全部 PASS。
- Review 业务门禁已 PASS。
后续动作：
- 主控将重跑 Test / Acceptance。
当前状态：
- 文档卫生修复完成。
```

## 128. 阶段 8 第一批最终 Test/Acceptance 调度记录

```text
调度 ID：V2-DOC-S8-FIRST-BATCH-FINAL-GATES-001
时间：2026-05-14
阶段：第二版阶段 8 第一批 / 最终 Test 与 Acceptance 调度
任务卡 ID：V2-DOC-S8-FIRST-BATCH-FINAL-GATES-001
当前会话模式：ClipEase V2 Docs/Log Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新文档，不修改业务代码
前置状态：
- Dev-log trailing whitespace 已由 `V2-DOC-FIX-TRAILING-WHITESPACE-DEVLOG-001` 修复。
- `git diff --check` PASS。
- Review 已 PASS。
主控最终门禁调度：
- 已调度最终 Test：`V2-TEST-S8-WINDOW-EXPERIENCE-FIRST-BATCH-FINAL-001`。
- 已调度 Acceptance：`V2-ACCEPT-S8-WINDOW-EXPERIENCE-FIRST-BATCH-001`。
后续动作：
- 等待最终 Test / Acceptance 完成。
- 最终 Test / Acceptance 通过后，由主控构建运行 App。
当前状态：
- 阶段 8 第一批进入最终 Test / Acceptance 等待状态。
- 当前记录未修改业务代码，未运行构建，未回退任何改动。
交付摘要：文档 Agent 已追加阶段 8 第一批最终 Test / Acceptance 调度记录，确认 dev-log trailing whitespace 已由 `V2-DOC-FIX-TRAILING-WHITESPACE-DEVLOG-001` 修复、`git diff --check` PASS、Review 已 PASS，并记录最终 Test `V2-TEST-S8-WINDOW-EXPERIENCE-FIRST-BATCH-FINAL-001` 与 Acceptance `V2-ACCEPT-S8-WINDOW-EXPERIENCE-FIRST-BATCH-001` 已调度；未修改业务代码，未运行构建，未回退任何改动。
```

## 129. 阶段 8 第一批最终 PASS 记录

```text
调度 ID：V2-DOC-S8-FIRST-BATCH-FINAL-PASS-RUN-001
时间：2026-05-14
阶段：第二版阶段 8 第一批 / 最终 Test 与 Acceptance PASS
任务卡 ID：V2-DOC-S8-FIRST-BATCH-FINAL-PASS-RUN-001
当前会话模式：ClipEase V2 Docs/Log Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新文档，不修改业务代码
最终 Test：
- `V2-TEST-S8-WINDOW-EXPERIENCE-FIRST-BATCH-FINAL-001` PASS。
- `swift build` PASS。
- `verify_stage8_window_experience` PASS。
- `verify_no_management_no_favorite_ui` PASS。
- `verify_history_shortcut_commands` PASS。
- `verify_group_focus_and_menu_guard` PASS。
- `verify_history_selection_focus` PASS。
- `verify_sqlite_only_baseline` PASS。
- `smoke_check` PASS。
- `git diff --check` PASS。
Acceptance：
- `V2-ACCEPT-S8-WINDOW-EXPERIENCE-FIRST-BATCH-001` PASS。
- 阶段 8 第一批可放给用户实机测试。
- 本 PASS 不等同正式发布。
Review：
- Review 已 PASS。
后续动作：
- 主控将执行 `build-app.sh` 构建运行 App。
当前状态：
- 阶段 8 第一批最终 Test / Acceptance / Review 门禁已通过。
- 当前记录未修改业务代码，未运行构建，未回退任何改动。
交付摘要：文档 Agent 已追加阶段 8 第一批最终 PASS 记录，确认最终 Test `V2-TEST-S8-WINDOW-EXPERIENCE-FIRST-BATCH-FINAL-001`、Acceptance `V2-ACCEPT-S8-WINDOW-EXPERIENCE-FIRST-BATCH-001` 和 Review 已 PASS；记录可放给用户实机测试但不等同正式发布；主控下一步将执行 `build-app.sh` 构建运行 App；未修改业务代码，未运行构建，未回退任何改动。
```

## 130. 阶段 8 第一批主控构建运行记录

```text
调度 ID：V2-DOC-S8-FIRST-BATCH-BUILD-RUN-001
时间：2026-05-14
阶段：第二版阶段 8 第一批 / 主控构建运行
任务卡 ID：V2-DOC-S8-FIRST-BATCH-BUILD-RUN-001
当前会话模式：ClipEase V2 Docs/Log Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新文档，不修改业务代码
前置状态：
- Acceptance Agent `V2-ACCEPT-S8-WINDOW-EXPERIENCE-FIRST-BATCH-001` 已 PASS。
- 阶段 8 第一批最终 Test / Acceptance / Review 门禁已通过。
主控执行：
- Acceptance PASS 后，主控执行 `scripts/build-app.sh`。
- 版本变化：`1.0.11 (260514.1916)` -> `1.0.12 (260514.2015)`。
- 构建产物：`/Users/wpc/code/codex/ClipboardHistory/.build/ClipEase.app`。
- 启动方式：`pkill -x ClipEase` 后 `open -n -a .build/ClipEase.app`。
- 运行进程：PID `82965`，路径 `/Users/wpc/code/codex/ClipboardHistory/.build/ClipEase.app/Contents/MacOS/ClipEase`。
用户待测点：
- 新剪切板定位 / 无新历史恢复横向位置。
- 分组 / 置顶下普通新剪切板下次打开切全部并定位。
- 预览关闭 / 主窗口关闭隐藏时状态不残留。
- 主窗口更多菜单新建文本隐藏主窗口、保存后打开并选中新记录。
- 更多按钮为 `...` 且无收藏 / 管理 / 多选 / 批量入口。
当前状态：
- App 已由主控构建并启动，等待用户实机测试反馈。
- 当前记录未修改业务代码，未运行构建，未回退任何改动。
交付摘要：文档 Agent 已追加阶段 8 第一批 Acceptance PASS 后主控构建运行记录，包含 `scripts/build-app.sh` 执行、版本变化 `1.0.11 (260514.1916)` -> `1.0.12 (260514.2015)`、构建产物、启动方式、运行进程 PID 和用户待测点；未修改业务代码，未运行构建，未回退任何改动。
```

## 131. 阶段 8 第二批范围调度记录

```text
调度 ID：V2-DOC-S8-SECOND-BATCH-SCOPE-DISPATCH-001
时间：2026-05-14
阶段：第二版阶段 8 第二批 / 范围裁定调度
任务卡 ID：V2-DOC-S8-SECOND-BATCH-SCOPE-DISPATCH-001
当前会话模式：ClipEase V2 Docs/Log Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新文档，不修改业务代码
前置状态：
- 阶段 8 第一批已 Test / Review / Acceptance PASS。
- 阶段 8 第一批已由主控 build / run，当前运行版本为 `1.0.12 (260514.2015)`。
主控准备推进：
- 阶段 8 第二批候选方向为顶部状态简化 + 全局短提示层。
候选范围：
- 移除主窗口顶部常驻状态项。
- 保留授权入口。
- 统一 `showStatus` 到短提示层。
- 明确短提示层位置、层级和自动消失行为。
- 本批不实现删除撤销。
红线禁改：
- 禁改 Storage / schema / backup / import / attachment / retention / Repository / FTS / LIKE。
- 禁止恢复收藏 / 管理 / 多选 / 批量入口或能力。
- 禁止修改删除 / 撤销语义。
主控已调度：
- 已调度 UX Agent 做阶段 8 第二批顶部状态简化 + 全局短提示层范围裁定。
- 已调度 Architecture Gatekeeper 做阶段 8 第二批技术边界、红线禁改和实现风险裁定。
后续动作：
- UX Agent 与 Architecture Gatekeeper 裁定 PASS 后，再调度 UI Agent 进入实现。
- UI Agent 未调度前，不应修改业务代码。
当前状态：
- 阶段 8 第二批处于范围裁定等待状态。
- 当前记录未修改业务代码，未运行构建，未回退任何改动。
交付摘要：文档 Agent 已追加阶段 8 第二批范围调度记录，确认阶段 8 第一批已 Test / Review / Acceptance PASS 并 build / run `1.0.12 (260514.2015)`；记录顶部状态简化 + 全局短提示层候选范围、红线禁改、UX Agent 与 Architecture Gatekeeper 已调度，以及裁定 PASS 后再调 UI Agent；未修改业务代码，未运行构建，未回退任何改动。
```

## 132. 阶段 8 第二批用户确认与 UI Agent 调度记录

```text
调度 ID：V2-DOC-S8-SECOND-BATCH-CONFIRM-AND-USER-UPDATES-001
时间：2026-05-14
阶段：第二版阶段 8 第二批 / 用户确认与 UI Agent 调度
任务卡 ID：V2-DOC-S8-SECOND-BATCH-CONFIRM-AND-USER-UPDATES-001
当前会话模式：ClipEase V2 Docs/Log + Product Rules Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新文档，不修改业务代码
用户确认：
- 用户已确认阶段 8 第二批低风险口径。
- 短提示采用 `HistoryWindowView` 内 overlay toast，不新建独立 toast window。
- 主窗口顶部移除“记录中”“已暂停”“自动粘贴”“永久记录”等常驻状态。
- 剪贴板未授权时，主窗口顶部只保留轻量“请授权”入口。
用户新增要求：
- 复制新内容后打开主窗口必须定位并选中新记录；有置顶卡片时不能选中置顶条目；无置顶时选中左侧第一个卡片且左侧间隔区域要显示。
- 搜索框打开后，点击其他非搜索区域关闭搜索框。
- 顶部最右侧更多按钮精确显示为 `...`，不要带其他字符。
产品规则同步：
- `docs/V2_DEVELOPMENT_PLAN.md` 阶段 8 搜索框点击行为已从“点击主窗口内其他区域时搜索框保持展开”改为“点击其他非搜索区域关闭搜索框”。
- `docs/V2_PRODUCT_PLAN.md` 搜索交互规则已同步为“点击其他非搜索区域关闭搜索框”。
主控已调度：
- 已调度 UI Agent：`V2-S8-TOAST-TOPBAR-SEARCH-SELECTION-001`。
UI Agent 禁改范围：
- 禁改 Storage / schema / backup / import / attachment / retention / Repository / FTS / LIKE。
- 禁止恢复收藏 / 管理 / 多选 / 批量入口或能力。
后续动作：
- 等待 UI Agent 按用户确认口径实现阶段 8 第二批低风险 UI / 焦点 / 选择行为。
- UI Agent 完成后再进入 Test / Review / Acceptance 门禁。
当前状态：
- 阶段 8 第二批用户口径已确认，产品规则已同步，UI Agent 已调度。
- 当前记录未修改业务代码，未运行构建，未回退任何改动。
交付摘要：文档 Agent 已追加阶段 8 第二批用户确认、三点新增要求、搜索框点击关闭规则同步和 UI Agent `V2-S8-TOAST-TOPBAR-SEARCH-SELECTION-001` 调度记录；未修改业务代码，未运行构建，未回退任何改动。
```

## 133. 阶段 8 第二批 UI Agent 完成与门禁调度记录

```text
调度 ID：V2-DOC-S8-SECOND-BATCH-COMPLETE-GATES-001
时间：2026-05-14 20:53:14 CST
阶段：第二版阶段 8 第二批 / UI Agent 完成与 Test / Review 门禁调度
任务卡 ID：V2-DOC-S8-SECOND-BATCH-COMPLETE-GATES-001
当前会话模式：ClipEase V2 Docs/Log Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新文档，不修改业务代码
前置状态：
- 阶段 8 第二批用户口径已确认。
- UI Agent `V2-S8-TOAST-TOPBAR-SEARCH-SELECTION-001` 已由主控调度。
UI Agent 完成状态：
- UI Agent `V2-S8-TOAST-TOPBAR-SEARCH-SELECTION-001` 已完成。
涉及文件：
- `Sources/ClipEase/Features/History/HistoryWindowView.swift`
- `scripts/verify_stage8_window_experience.py`
实现摘要：
- 在 `HistoryWindowView.swift` 实现主窗口内 toast overlay。
- 简化主窗口顶部状态展示。
- 未授权时保留轻量授权入口。
- 修正新剪切板打开主窗口后的定位和选中行为。
- 支持搜索框打开后点击其他非搜索区域关闭。
- 顶部最右侧更多按钮精确显示为 `...`。
- 在 `verify_stage8_window_experience.py` 中补充 / 调整对应验证覆盖。
主控已调度：
- Test Agent：`V2-TEST-S8-TOAST-TOPBAR-SEARCH-SELECTION-001`
- Review Agent：`V2-REVIEW-S8-TOAST-TOPBAR-SEARCH-SELECTION-001`
后续动作：
- 等待 Test / Review 门禁结果。
- Test / Review PASS 后再进入 Acceptance / 构建运行安排。
当前状态：
- 阶段 8 第二批 UI Agent 已完成，Test / Review 已调度。
- 当前记录未修改业务代码，未运行构建，未回退任何改动。
交付摘要：文档 Agent 已追加阶段 8 第二批 UI Agent `V2-S8-TOAST-TOPBAR-SEARCH-SELECTION-001` 完成记录，确认其修改 `HistoryWindowView.swift` 和 `verify_stage8_window_experience.py`，实现 toast overlay、顶部状态简化、未授权轻量入口、新剪切板定位修正、搜索外点关闭、更多按钮精确 `...`；记录主控已调度 Test `V2-TEST-S8-TOAST-TOPBAR-SEARCH-SELECTION-001` 和 Review `V2-REVIEW-S8-TOAST-TOPBAR-SEARCH-SELECTION-001`；未修改业务代码，未运行构建，未回退任何改动。
```

## 134. 阶段 8 第二批 Test / Review HOLD 与主控处理记录

```text
调度 ID：V2-DOC-S8-SECOND-BATCH-HOLD-RULING-001
时间：2026-05-14
阶段：第二版阶段 8 第二批 / Test / Review HOLD 与主控处理
任务卡 ID：V2-DOC-S8-SECOND-BATCH-HOLD-RULING-001
当前会话模式：ClipEase V2 Docs/Log Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新文档，不修改业务代码
前置状态：
- 阶段 8 第二批 UI Agent `V2-S8-TOAST-TOPBAR-SEARCH-SELECTION-001` 已完成。
- Test Agent `V2-TEST-S8-TOAST-TOPBAR-SEARCH-SELECTION-001` 与 Review Agent `V2-REVIEW-S8-TOAST-TOPBAR-SEARCH-SELECTION-001` 已完成阶段性检查。
Test 结论：
- 业务静态验证 PASS。
- smoke 仅因 RC report 未对齐 `1.0.12(260514.2015)` HOLD。
Review 结论：
- 实现看起来 OK。
- 但因当前工作树为 V2 累积大 diff，Review 无法证明本批只改两文件，范围 HOLD。
主控处理：
- 主控已调度 Docs RC 对齐：`V2-DOC-RC-ALIGN-S8-SECOND-BATCH-001`。
- 主控已调度 Architecture scope ruling：`V2-ARCH-S8-SECOND-BATCH-WORKTREE-SCOPE-RULING-001`。
禁改范围：
- 禁改 Storage / schema / backup / import / attachment / retention / Repository / FTS / LIKE 仍有效。
- 禁止恢复收藏 / 管理 / 多选 / 批量入口或能力仍有效。
- 未经主控新调度，不得扩大阶段 8 第二批业务改动范围。
后续动作：
- 等待 Docs RC 对齐完成后解除 smoke HOLD。
- 等待 Architecture scope ruling 对当前 V2 累积大 diff 与阶段 8 第二批两文件范围进行裁定。
- HOLD 未解除前，不进入 Acceptance / 构建运行安排。
当前状态：
- 阶段 8 第二批处于 Test smoke HOLD 与 Review scope HOLD。
- 当前记录未修改业务代码，未运行构建，未回退任何改动。
交付摘要：文档 Agent 已追加阶段 8 第二批 Test / Review HOLD 与主控处理记录，确认 Test 业务静态验证 PASS、smoke 仅因 RC report 未对齐 `1.0.12(260514.2015)` HOLD；Review 认为实现看起来 OK，但因当前工作树为 V2 累积大 diff，无法证明本批只改两文件而范围 HOLD；记录主控已调度 Docs RC 对齐 `V2-DOC-RC-ALIGN-S8-SECOND-BATCH-001` 与 Architecture scope ruling `V2-ARCH-S8-SECOND-BATCH-WORKTREE-SCOPE-RULING-001`；禁改范围仍有效；未修改业务代码，未运行构建，未回退任何改动。
```

## 135. 阶段 8 第二批 RC 对齐记录

```text
调度 ID：V2-DOC-RC-ALIGN-S8-SECOND-BATCH-001
时间：2026-05-14
阶段：第二版阶段 8 第二批 / RC 文档版本对齐
任务卡 ID：V2-DOC-RC-ALIGN-S8-SECOND-BATCH-001
当前会话模式：ClipEase V2 Docs/Log Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新 runbook 和 RC 报告，不修改业务代码
前置状态：
- Test Agent 对 `V2-S8-TOAST-TOPBAR-SEARCH-SELECTION-001` 的业务验证通过。
- smoke_check HOLD 原因为 `docs/RELEASE_CANDIDATE_REPORT.md` 未对齐当前 Info.plist `1.0.12(260514.2015)`。
- Review HOLD 为脏工作树范围无法证明。
- 主控已调度架构范围裁定。
当前 RC 版本：
- `Resources/Info.plist` 当前版本为 `1.0.12(260514.2015)`。
- `docs/RELEASE_CANDIDATE_REPORT.md` 已对齐到 `1.0.12(260514.2015)`。
本 RC 范围记录：
- Stage 8 第二批 `V2-S8-TOAST-TOPBAR-SEARCH-SELECTION-001` 已纳入 RC 修复记录。
- 范围包括 HistoryWindow 内 overlay toast。
- 范围包括顶部状态简化。
- 范围包括剪贴板未授权时轻量授权入口。
- 范围包括新剪切板打开主窗口选中新记录且不误选置顶。
- 范围包括搜索框打开后点击其他非搜索区域关闭。
- 范围包括顶部最右侧更多按钮精确显示为 `...`。
门禁状态：
- Test 业务命令除 smoke 版本对齐项外均 PASS。
- smoke 版本 HOLD 已通过本次 RC 文档对齐处理；本轮已执行 `python3 scripts/smoke_check.py` 并 PASS。
- Review HOLD 原因为脏工作树范围无法证明，需等待主控调度的架构范围裁定。
当前状态：
- RC 版本文档已对齐。
- `python3 scripts/smoke_check.py` 已通过。
- 当前记录未修改业务代码，未运行构建，未回退任何改动。
交付摘要：文档 Agent 已将 `docs/RELEASE_CANDIDATE_REPORT.md` 对齐到 `1.0.12(260514.2015)`，追加 Stage 8 第二批 overlay toast、顶部状态简化、未授权轻量入口、新剪切板选中新记录不误选置顶、搜索外点关闭、更多按钮精确 `...` 的 RC 修复记录，并记录 Test 业务命令除 smoke 版本外均 PASS、Review HOLD 是脏工作树范围无法证明、主控已调度架构范围裁定；已执行 `python3 scripts/smoke_check.py` 且 PASS；未修改业务代码，未运行构建，未回退任何改动。
```

## 136. 阶段 8 第二批最终门禁调度记录

```text
调度 ID：V2-DOC-S8-SECOND-BATCH-FINAL-GATES-001
时间：2026-05-14
阶段：第二版阶段 8 第二批 / 最终 Test / Review / Acceptance 门禁调度
任务卡 ID：V2-DOC-S8-SECOND-BATCH-FINAL-GATES-001
当前会话模式：ClipEase V2 Docs/Log Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新文档，不修改业务代码
前置状态：
- RC report 已对齐 `1.0.12(260514.2015)`。
- `python3 scripts/smoke_check.py` 已 PASS。
- Architecture scope ruling PASS with residual risk。
- Review scope HOLD 已降级为范围备注，不再阻塞最终门禁调度。
主控处理：
- 主控已调度最终 Test：`V2-TEST-S8-TOAST-TOPBAR-SEARCH-SELECTION-FINAL-001`。
- 主控已调度最终 Review：`V2-REVIEW-S8-TOAST-TOPBAR-SEARCH-SELECTION-FINAL-001`。
- 主控已调度 Acceptance：`V2-ACCEPT-S8-TOAST-TOPBAR-SEARCH-SELECTION-001`。
禁改范围：
- 禁改 Storage / schema / backup / import / attachment / retention / Repository / FTS / LIKE 仍有效。
- 禁止恢复收藏 / 管理 / 多选 / 批量入口或能力仍有效。
- 未经主控新调度，不得扩大阶段 8 第二批业务改动范围。
当前状态：
- 阶段 8 第二批已进入最终 Test / Review / Acceptance 门禁。
- 当前记录未修改业务代码，未运行构建，未回退任何改动。
交付摘要：文档 Agent 已追加阶段 8 第二批最终门禁调度记录，确认 RC report 已对齐 `1.0.12(260514.2015)` 且 smoke_check PASS；Architecture scope ruling PASS with residual risk；Review scope HOLD 已降级为范围备注；记录主控已调度最终 Test `V2-TEST-S8-TOAST-TOPBAR-SEARCH-SELECTION-FINAL-001`、最终 Review `V2-REVIEW-S8-TOAST-TOPBAR-SEARCH-SELECTION-FINAL-001`、Acceptance `V2-ACCEPT-S8-TOAST-TOPBAR-SEARCH-SELECTION-001`；未修改业务代码，未运行构建，未回退任何改动。
```

## 137. 阶段 8 第二批最终 PASS 记录

```text
调度 ID：V2-DOC-S8-SECOND-BATCH-FINAL-PASS-RUN-001
时间：2026-05-14
阶段：第二版阶段 8 第二批 / 最终 Test / Review / Acceptance PASS
任务卡 ID：V2-DOC-S8-SECOND-BATCH-FINAL-PASS-RUN-001
当前会话模式：ClipEase V2 Docs/Log Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新文档，不修改业务代码
前置状态：
- 阶段 8 第二批已完成最终 Test / Review / Acceptance 门禁。
- Architecture scope residual risk 已降级为范围备注，不阻塞本批放行。
最终 Test 结论：
- `V2-TEST-S8-TOAST-TOPBAR-SEARCH-SELECTION-FINAL-001` PASS。
- `swift build` PASS。
- `verify_stage8_window_experience` PASS。
- `verify_no_management_no_favorite_ui` PASS。
- `verify_history_selection_focus` PASS。
- `verify_group_focus_and_menu_guard` PASS。
- `verify_sqlite_only_baseline` PASS。
- `smoke_check` PASS。
- `git diff --check` PASS。
最终 Review 结论：
- `V2-REVIEW-S8-TOAST-TOPBAR-SEARCH-SELECTION-FINAL-001` PASS。
Acceptance 结论：
- `V2-ACCEPT-S8-TOAST-TOPBAR-SEARCH-SELECTION-001` PASS。
范围备注：
- Scope residual risk 仅作为当前 V2 累积工作树范围备注保留。
- 该 residual risk 不阻塞阶段 8 第二批最终 PASS，不阻塞主控构建运行 App 给用户测试。
后续动作：
- 主控将执行 `scripts/build-app.sh` 构建并运行 App，供用户测试。
当前状态：
- 阶段 8 第二批 toast / topbar / search / selection 范围已最终 PASS。
- 当前记录未修改业务代码，未运行构建，未回退任何改动。
交付摘要：文档 Agent 已追加阶段 8 第二批最终 PASS 记录，确认最终 Test `V2-TEST-S8-TOAST-TOPBAR-SEARCH-SELECTION-FINAL-001`、最终 Review `V2-REVIEW-S8-TOAST-TOPBAR-SEARCH-SELECTION-FINAL-001`、Acceptance `V2-ACCEPT-S8-TOAST-TOPBAR-SEARCH-SELECTION-001` 均 PASS；记录 `swift build`、`verify_stage8_window_experience`、`verify_no_management_no_favorite_ui`、`verify_history_selection_focus`、`verify_group_focus_and_menu_guard`、`verify_sqlite_only_baseline`、`smoke_check`、`git diff --check` 全部通过；Scope residual risk 已降级为范围备注且不阻塞；主控下一步将执行 `scripts/build-app.sh` 构建运行 App 给用户测试；未修改业务代码，未运行构建，未回退任何改动。
```

## 138. 阶段 8 第二批主控构建运行记录

```text
调度 ID：V2-DOC-S8-SECOND-BATCH-BUILD-RUN-001
时间：2026-05-14
阶段：第二版阶段 8 第二批 / 主控构建运行
任务卡 ID：V2-DOC-S8-SECOND-BATCH-BUILD-RUN-001
当前会话模式：ClipEase V2 Docs/Log Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新文档，不修改业务代码
前置状态：
- 阶段 8 第二批 Acceptance 已 PASS。
- 主控在 Acceptance PASS 后执行 `scripts/build-app.sh`。
版本变化：
- 构建前版本：`1.0.12 (260514.2015)`。
- 构建后版本：`1.0.13 (260514.2108)`。
构建产物：
- `/Users/wpc/code/codex/ClipboardHistory/.build/ClipEase.app`
启动方式：
- `pkill -x ClipEase`
- `open -n -a .build/ClipEase.app`
运行进程：
- PID：`49334`
- 路径：`/Users/wpc/code/codex/ClipboardHistory/.build/ClipEase.app/Contents/MacOS/ClipEase`
用户待测点：
- 置顶存在时复制新内容后选中新记录。
- 无置顶时选中左侧第一卡且左侧间隔显示。
- 搜索打开后点击其他区域关闭搜索。
- 顶部状态简化和未授权轻量入口。
- toast overlay。
- 更多按钮精确 `...`。
当前状态：
- 阶段 8 第二批主控构建已完成并已启动构建产物。
- App 已运行，等待用户按待测点进行手动验证。
- 当前记录未修改业务代码，未运行额外构建，未回退任何改动。
交付摘要：文档 Agent 已追加阶段 8 第二批主控构建运行记录，确认 Acceptance PASS 后主控执行 `scripts/build-app.sh`，版本由 `1.0.12 (260514.2015)` 升至 `1.0.13 (260514.2108)`；构建产物为 `/Users/wpc/code/codex/ClipboardHistory/.build/ClipEase.app`；主控通过 `pkill -x ClipEase` 后 `open -n -a .build/ClipEase.app` 启动；运行进程 PID `49334`，路径 `/Users/wpc/code/codex/ClipboardHistory/.build/ClipEase.app/Contents/MacOS/ClipEase`；记录用户待测点包括置顶存在时复制新内容后选中新记录、无置顶时选中左侧第一卡且左侧间隔显示、搜索打开后点击其他区域关闭搜索、顶部状态简化和未授权轻量入口、toast overlay、更多按钮精确 `...`；未修改业务代码，未回退任何改动。
```

## 139. 阶段 8 第二批后续范围裁定调度记录

```text
调度 ID：V2-DOC-S8-POST-SECOND-BATCH-NEXT-SCOPE-001
时间：2026-05-14
阶段：第二版阶段 8 第二批后 / 下一步范围裁定
任务卡 ID：V2-DOC-S8-POST-SECOND-BATCH-NEXT-SCOPE-001
当前会话模式：ClipEase V2 Docs/Log Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新文档，不修改业务代码
前置状态：
- 阶段 8 第二批最终 Test / Review / Acceptance 已 PASS。
- 主控已完成 `scripts/build-app.sh` 并启动构建产物。
- 当前运行版本为 `1.0.13 (260514.2108)`。
当前基线：
- SQLite-only。
- no favorite。
- no management。
- no multi-select。
- no batch。
Stage 8 已完成范围：
- 第一批和第二批低风险 UI / 窗口 / toast / search 交互已完成。
- 第二批范围包括 toast overlay、顶部状态简化、未授权轻量入口、新剪切板定位修正、搜索外点关闭、更多按钮精确 `...`。
红线与禁开发项：
- Stage 8 剩余文档项中删除 / 撤销 / 附件生命周期属于红线。
- 未经用户和主控明确确认前，不得开发删除 / 撤销 / 附件生命周期相关能力。
- 禁止恢复收藏 / 管理 / 多选 / 批量入口或能力仍有效。
下一步范围裁定：
- 主控已调度 Product Rules：`V2-PRODUCT-S8-REMAINING-OR-S9-SCOPE-001`。
- 主控已调度 Architecture Gatekeeper：`V2-ARCH-S8-REMAINING-OR-S9-SCOPE-001`。
- 目标是裁定 Stage 8 剩余低风险项是否继续推进，或进入 Stage 9 范围。
Stage 9 预备约束：
- Stage 9 文件卡片 / Quick Look 如进入，需要先做方案。
- Stage 9 文件卡片 / Quick Look 如进入，需要先做测试计划。
- 未形成方案和测试计划前，不直接进入业务代码开发。
当前状态：
- 主控在 Stage 8 第二批 PASS / build-run `1.0.13` 后，已开始下一步范围裁定。
- 当前记录未修改业务代码，未运行构建，未回退任何改动。
交付摘要：文档 Agent 已追加 Stage 8 第二批 PASS / build-run `1.0.13` 后的下一步范围裁定记录，确认当前基线为 SQLite-only / no favorite / no management / no multi-select / no batch；Stage 8 已完成两批低风险 UI / 窗口 / toast / search 交互；Stage 8 剩余文档项中删除 / 撤销 / 附件生命周期属于红线，未确认前不开发；记录主控已调度 Product Rules `V2-PRODUCT-S8-REMAINING-OR-S9-SCOPE-001` 和 Architecture Gatekeeper `V2-ARCH-S8-REMAINING-OR-S9-SCOPE-001`；Stage 9 文件卡片 / Quick Look 如进入，需要先做方案和测试计划；未修改业务代码，未运行构建，未回退任何改动。
```

## 140. 阶段 8 剩余范围与阶段 9 前置方案裁定记录

```text
调度 ID：V2-PRODUCT-S8-REMAINING-OR-S9-SCOPE-001
时间：2026-05-14
阶段：第二版阶段 8 收口 / 阶段 9 前置方案裁定
任务卡 ID：V2-PRODUCT-S8-REMAINING-OR-S9-SCOPE-001
当前会话模式：ClipEase V2 Product Rules Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本轮只更新产品 / 计划文档，不修改业务代码
前置状态：
- 最新基线为 SQLite-only、无收藏、无管理模式 / 多选 / 批量，置顶和分组保留。
- 阶段 8 第一批已完成新剪切板定位、无新历史恢复横向位置、预览层级、新建文本入口与保存后选中新记录、更多按钮等。
- 阶段 8 第二批已完成 HistoryWindow 内 overlay toast、顶部状态简化、未授权轻量入口、新内容选中新记录不误选置顶、搜索外点关闭、更多按钮精确 `...`。
- 阶段 8 第二批已 PASS 并 build / run `1.0.13 (260514.2108)`。
阶段 8 剩余低风险项裁定：
- 如继续阶段 8，只允许搜索框和筛选面板现有行为的文案 / 验证对齐。
- 允许已实现窗口体验的人工验收补测和文档同步。
- 允许 Stage 8 / Stage 9 边界文档清理，避免后续任务误把删除撤销带入 UI 收口。
HOLD / 移出阶段 8：
- 搜索框聚焦、卡片选择、方向键、Tab、中文输入法候选等完整键盘导航细节，移入后续独立 Keyboard UX 小批次。
- Delete / Backspace 删除卡片、删除不弹确认、删除后选中右侧下一张。
- 删除 toast 的“撤销”入口、8 秒持续时间、撤销后恢复原位置。
- 删除分组里的内容时从所有地方彻底删除。
- 删除图片 / 富文本等附件时立即清理本地附件。
- 撤销删除时恢复已删除附件。
- 任何保存期限清理、数据健康修复、附件清理策略、Repository 删除路径或批量删除 / 逐条撤销动画。
产品建议：
- 建议阶段 8 收口。
- 建议下一步进入阶段 9 文件卡片 / Quick Look 前置方案，而不是继续扩大阶段 8。
下一批建议任务卡：
- 小批次 1：`V2-PRODUCT-S9-FILE-CARD-QUICKLOOK-PREFLIGHT-001`，只做产品 + 架构前置，不写业务代码；明确文件路径记录、Quick Look 边界、路径失效、粘贴文件引用、拖出、删除历史不影响原文件和安全作用域不记录等规则。
- 小批次 2：`V2-DOC-S8-SCOPE-CLOSEOUT-KEYBOARD-DELETE-HOLD-001`，只做文档 / 测试计划清理；把 Stage 8 键盘导航细节和删除 / 撤销 / 附件生命周期从执行范围中标注 HOLD。
是否需要用户确认：
- 需要用户确认是否正式收口 Stage 8 并进入 Stage 9 前置方案。
- 如用户仍希望继续 Stage 8，只建议执行小批次 2 文档清理，不建议再做业务实现。
已更新文档：
- `docs/V2_DEVELOPMENT_PLAN.md`
- `docs/V2_PRODUCT_PLAN.md`
- `docs/V2_AGENT_RUNBOOK.md`
交付摘要：Product Rules Agent 已裁定阶段 8 第二批后原则上收口，仅保留文档 / 验证对齐等低风险项；明确 Delete / Backspace 删除、删除撤销、附件清理和附件恢复等红线全部 HOLD / 移出阶段 8；建议进入阶段 9 文件卡片 / Quick Look 前置方案；未修改业务代码，未运行构建，未回退任何改动。
```

## 141. 阶段 8 正式收口与阶段 9 文件卡片 / Quick Look 前置调度记录

```text
调度 ID：V2-DOC-S8-CLOSEOUT-S9-PREFLIGHT-DISPATCH-001
时间：2026-05-14
阶段：第二版阶段 8 正式收口 / 阶段 9 文件卡片与 Quick Look 前置调度
任务卡 ID：V2-DOC-S8-CLOSEOUT-S9-PREFLIGHT-DISPATCH-001
当前会话模式：ClipEase V2 Docs/Log Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新文档，不修改业务代码
用户确认：
- 用户已确认正式收口 Stage 8。
- 用户已确认进入 Stage 9 文件卡片 / Quick Look 前置方案。
Stage 8 完成状态：
- Stage 8 已完成两批。
- 第一批为窗口体验相关小批次。
- 第二批为 toast / topbar / search / new-selection 相关小批次。
- 两批均已完成 Test / Review / Acceptance PASS。
- 两批已 build / run 到 `1.0.13`。
Stage 8 HOLD 状态：
- Stage 8 剩余删除 / 撤销 / 附件生命周期 / 深层键盘交互全部 HOLD。
- 上述 HOLD 项不作为 Stage 8 普通 UI 批次继续开发。
- 禁止把 Delete / Backspace 删除、删除 toast 撤销、附件清理、附件恢复、深层键盘导航等内容继续并入 Stage 8 普通 UI 收口。
Stage 9 preflight 调度：
- Stage 9 先做 preflight，不直接进入业务代码开发。
- Product Rules 调度任务卡：`V2-PRODUCT-S9-FILE-CARD-QUICKLOOK-PREFLIGHT-001`。
- Architecture Gatekeeper 调度任务卡：`V2-ARCH-S9-FILE-CARD-QUICKLOOK-PREFLIGHT-001`。
- Test Plan 调度任务卡：`V2-TESTPLAN-S9-FILE-CARD-QUICKLOOK-PREFLIGHT-001`。
已完成的 preflight 子任务：
- Test Plan Agent 已完成 `V2-TESTPLAN-S9-FILE-CARD-QUICKLOOK-PREFLIGHT-001`。
- Test Plan Agent 已更新 `docs/V2_TEST_PLAN.md`。
强制禁令：
- 禁止直接写业务代码。
- 禁止修改 schema / model / repository / clipboard monitor / paste executor / Quick Look 实现。
- 在 preflight 和用户红线确认通过前，不得启动 Stage 9 文件卡片 / Quick Look 的业务实现。
当前状态：
- Stage 8 已正式收口。
- Stage 9 当前处于文件卡片 / Quick Look preflight 调度阶段。
- 当前记录未修改业务代码，未运行构建，未回退任何改动。
交付摘要：Docs/Log Agent 已追加 Stage 8 正式收口与 Stage 9 文件卡片 / Quick Look 前置调度记录；确认 Stage 8 两批窗口体验与 toast / topbar / search / new-selection 均 Test / Review / Acceptance PASS 并 build / run 到 `1.0.13`；确认删除 / 撤销 / 附件生命周期 / 深层键盘交互全部 HOLD 且不作为 Stage 8 普通 UI 批次继续开发；记录 Stage 9 preflight 三路调度任务卡 `V2-PRODUCT-S9-FILE-CARD-QUICKLOOK-PREFLIGHT-001`、`V2-ARCH-S9-FILE-CARD-QUICKLOOK-PREFLIGHT-001`、`V2-TESTPLAN-S9-FILE-CARD-QUICKLOOK-PREFLIGHT-001`；记录 Test Plan Agent 已完成对应任务并更新 `docs/V2_TEST_PLAN.md`；明确 preflight 和用户红线确认通过前禁止直接写业务代码，禁止修改 schema / model / repository / clipboard monitor / paste executor / Quick Look 实现。
```

## 142. Stage 9 文件卡片 / Quick Look 第一批红线确认与数据层调度记录

```text
调度 ID：V2-DOC-S9-USER-REDLINE-CONFIRM-DISPATCH-001
时间：2026-05-14
阶段：第二版 Stage 9 文件卡片 / Quick Look 第一批红线确认与数据层调度
任务卡 ID：V2-DOC-S9-USER-REDLINE-CONFIRM-DISPATCH-001
当前会话模式：ClipEase V2 Docs/Log Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新文档，不修改业务代码
用户确认口径：
- 文件卡片记录完整路径。
- 文件卡片显示用户名。
- 不记录 security-scoped bookmark。
- 备份不包含原文件副本。
- 删除历史永不删除原文件。
- 不做删除撤销。
- 不改附件清理语义。
- 默认记录文件卡片。
- 不做 FTS / 拼音 / SQLite 文件路径索引。
- 不主动下载 iCloud 占位文件。
- 不自动解析 alias 并改写路径。
主控调度：
- 用户已确认 Stage 9 文件卡片 / Quick Look 第一批红线口径。
- 主控已调度 `V2-S9-FILE-CARD-DATA-FOUNDATION-001` 做 Stage 9 文件卡片数据层实现。
- 第一批实现范围限定为数据层基础，不进入 UI / Quick Look 实现。
禁改范围：
- 禁改 UI。
- 禁改 Quick Look。
- 禁改 PasteExecutor。
- 禁改 ClipboardMonitor。
- 禁改删除撤销。
- 禁改原文件操作。
- 禁改 security scoped bookmark。
- 禁改 FTS LIKE。
- 禁改收藏管理批量 JSON migration runtime。
后续门禁：
- `V2-S9-FILE-CARD-DATA-FOUNDATION-001` 完成后需调度 Test Agent 覆盖数据层、备份不含原文件副本、删除历史不影响原文件、iCloud placeholder / alias 不主动解析等红线。
- `V2-S9-FILE-CARD-DATA-FOUNDATION-001` 完成后需调度 Review Agent 复核禁改范围和 Stage 9 第一批数据层边界。
- Test / Review PASS 后再进入 Acceptance；未通过前不得调度 UI / Quick Look 实现。
当前状态：
- Stage 9 文件卡片 / Quick Look 第一批红线口径已由用户确认。
- Stage 9 第一批业务实现已由主控限定调度到数据层基础任务 `V2-S9-FILE-CARD-DATA-FOUNDATION-001`。
- 当前记录未修改业务代码，未运行构建，未回退任何改动。
交付摘要：Docs/Log Agent 已追加 Stage 9 文件卡片 / Quick Look 第一批用户红线确认记录，明确完整路径、显示用户名、不记录 security-scoped bookmark、备份不含原文件副本、删除历史永不删除原文件、不做删除撤销、不改附件清理语义、默认记录文件卡片、不做 FTS / 拼音 / SQLite 文件路径索引、不主动下载 iCloud 占位文件、不自动解析 alias 改写路径；记录主控已调度 `V2-S9-FILE-CARD-DATA-FOUNDATION-001` 做数据层实现；记录禁改 UI / Quick Look / PasteExecutor / ClipboardMonitor / 删除撤销 / 原文件操作 / security scoped bookmark / FTS LIKE / 收藏管理批量 JSON migration runtime；未修改业务代码，未运行构建，未回退任何改动。
```

## 143. Stage 9 文件卡片数据层完成与编译 HOLD 记录

```text
调度 ID：V2-DOC-S9-DATA-FOUNDATION-COMPLETE-COMPILE-HOLD-001
时间：2026-05-14
阶段：第二版 Stage 9 文件卡片数据层完成与编译接线 HOLD
任务卡 ID：V2-DOC-S9-DATA-FOUNDATION-COMPLETE-COMPILE-HOLD-001
当前会话模式：ClipEase V2 Docs/Log Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新文档，不修改业务代码
数据层完成状态：
- `V2-S9-FILE-CARD-DATA-FOUNDATION-001` 已完成 Stage 9 文件卡片数据层基础。
- 新增 `.file` 内容类型。
- 新增 `ClipboardFileReference`。
- SQLite schema 升级到 v3。
- 新增 `clipboard_item_files`。
验证结果：
- `stage9 data foundation` 通过。
- `sqlite_only_baseline` 通过。
- `no_management_no_favorite_ui` 通过。
- `git diff --check` 通过。
- `smoke` 因 RC 版本未对齐 HOLD。
- `swift build` 因 UI / Preview / Paste / RichTextEditor 等 switch 未补 `.file` 分支失败。
主控判定：
- 当前问题不是回退数据层。
- 当前问题是新增 `.file` 后需要最小编译接线。
- 数据层基础保持完成状态，不因编译接线缺口回退。
Bugfix 调度：
- 主控已调度 Bugfix Agent `V2-BUGFIX-S9-FILE-TYPE-COMPILE-WIRING-001`。
- Bugfix 范围限定为最小编译接线，补齐 `.file` 分支以恢复构建。
禁改范围：
- 不实现 Quick Look。
- 不捕获剪贴板文件。
- 不改 Storage / schema / model / repository。
- 不删除 / 移动 / 复制原文件。
- 不记录 security scoped bookmark。
- 不实现删除撤销。
- 不恢复收藏 / 管理 / 多选 / 批量。
当前状态：
- Stage 9 文件卡片数据层基础已完成。
- Stage 9 当前处于最小编译接线 HOLD。
- 等待 Bugfix Agent 完成 `V2-BUGFIX-S9-FILE-TYPE-COMPILE-WIRING-001` 后重新验证。
- 当前记录未修改业务代码，未运行构建，未回退任何改动。
交付摘要：Docs/Log Agent 已追加 Stage 9 文件卡片数据层完成与编译 HOLD 记录，确认 `V2-S9-FILE-CARD-DATA-FOUNDATION-001` 已完成 `.file`、`ClipboardFileReference`、SQLite schema v3 和 `clipboard_item_files`；记录 stage9 data foundation、sqlite_only_baseline、no_management_no_favorite_ui、git diff --check 通过，smoke 因 RC 版本未对齐 HOLD，swift build 因 UI / Preview / Paste / RichTextEditor 等 switch 未补 `.file` 分支失败；记录主控判定不是回退数据层而是需要最小编译接线，且已调度 Bugfix Agent `V2-BUGFIX-S9-FILE-TYPE-COMPILE-WIRING-001`；明确禁改 Quick Look、剪贴板文件捕获、Storage / schema / model / repository、原文件删除移动复制、security scoped bookmark、删除撤销、收藏 / 管理 / 多选 / 批量；未修改业务代码，未运行构建，未回退任何改动。
```

## 144. Stage 9 文件卡片数据层完成与编译 HOLD 重派记录

```text
调度 ID：V2-DOC-S9-DATA-FOUNDATION-COMPLETE-COMPILE-HOLD-001-RERUN
时间：2026-05-14
阶段：第二版 Stage 9 文件卡片数据层完成与编译接线 HOLD / Docs 重派
任务卡 ID：V2-DOC-S9-DATA-FOUNDATION-COMPLETE-COMPILE-HOLD-001-RERUN
当前会话模式：ClipEase V2 Docs/Log Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新文档，不修改业务代码
重派背景：
- 上一轮 Bugfix / Docs 调度因 503 失败，无有效交付。
- 主控已重派本 Docs 记录任务。
数据层完成状态：
- `V2-S9-FILE-CARD-DATA-FOUNDATION-001` 数据层基础已完成。
- 已新增 `.file` 内容类型。
- 已新增 `ClipboardFileReference`。
- SQLite schema 已升级到 v3。
- 已新增 `clipboard_item_files`。
验证结果：
- `stage9 data foundation` 通过。
- `sqlite_only_baseline` 通过。
- `no_management_no_favorite_ui` 通过。
- `git diff --check` 通过。
- `smoke` 因 RC 版本未对齐 HOLD。
- `swift build` 因 UI / Preview / Paste / RichTextEditor 等 switch 未补 `.file` 分支失败。
主控判定：
- 当前不是回退数据层。
- 当前需要最小编译接线。
- 数据层基础保持完成状态，不因 `.file` 分支接线缺口回退。
Bugfix 调度：
- 主控已调度 Bugfix Agent `V2-BUGFIX-S9-FILE-TYPE-COMPILE-WIRING-001-RERUN`。
- Bugfix 范围限定为最小编译接线，补齐 `.file` 分支以恢复构建。
禁改范围：
- 不实现 Quick Look。
- 不捕获剪贴板文件。
- 不改 Storage / schema / model / repository。
- 不删除 / 移动 / 复制原文件。
- 不记录 security scoped bookmark。
- 不实现删除撤销。
- 不恢复收藏 / 管理 / 多选 / 批量。
当前状态：
- Stage 9 文件卡片数据层基础已完成。
- Stage 9 当前处于最小编译接线 HOLD。
- 等待 Bugfix Agent 完成 `V2-BUGFIX-S9-FILE-TYPE-COMPILE-WIRING-001-RERUN` 后重新验证。
- 当前记录未修改业务代码，未运行构建，未回退任何改动。
交付摘要：Docs/Log Agent 已追加 Stage 9 文件卡片数据层完成与编译 HOLD 重派记录，确认 `V2-S9-FILE-CARD-DATA-FOUNDATION-001` 数据层基础已完成，新增 `.file`、`ClipboardFileReference`、SQLite schema v3 和 `clipboard_item_files`；记录 stage9 data foundation、sqlite_only_baseline、no_management_no_favorite_ui、git diff --check 通过，smoke 因 RC 版本未对齐 HOLD，swift build 因 UI / Preview / Paste / RichTextEditor 等 switch 未补 `.file` 分支失败；记录上一轮 Bugfix / Docs 调度因 503 失败且主控已重派；记录主控判定这不是回退数据层，而是需要最小编译接线；记录主控已调度 Bugfix Agent `V2-BUGFIX-S9-FILE-TYPE-COMPILE-WIRING-001-RERUN`；明确禁改 Quick Look、剪贴板文件捕获、Storage / schema / model / repository、原文件删除移动复制、security scoped bookmark、删除撤销、收藏 / 管理 / 多选 / 批量；未修改业务代码，未运行构建，未回退任何改动。
```

## 145. Stage 9 文件卡片数据层编译接线完成与门禁调度记录

```text
调度 ID：V2-DOC-S9-DATA-FOUNDATION-COMPILE-WIRING-COMPLETE-GATES-001
时间：2026-05-14
阶段：第二版 Stage 9 文件卡片数据层 / 最小编译接线完成与门禁调度
任务卡 ID：V2-DOC-S9-DATA-FOUNDATION-COMPILE-WIRING-COMPLETE-GATES-001
当前会话模式：ClipEase V2 Docs/Log Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新文档，不修改业务代码
前置状态：
- `V2-S9-FILE-CARD-DATA-FOUNDATION-001` 数据层基础已完成。
- `.file`、`ClipboardFileReference`、SQLite schema v3 和 `clipboard_item_files` 已作为 Stage 9 数据基础进入当前工作树。
- 上一轮编译 HOLD 原因为新增 `.file` 后 UI / Preview / Paste / RichTextEditor 等非数据层 switch 尚未补最小 fallback。
Bugfix Agent 完成状态：
- Bugfix Agent `V2-BUGFIX-S9-FILE-TYPE-COMPILE-WIRING-001-RERUN` 已完成。
- Bugfix 范围限定为 `.file` 最小编译接线。
- Bugfix 已补齐 `.file` 最小编译 fallback，使 `swift build` 通过。
fallback 清单：
- 历史卡片 / 列表显示层对 `.file` 使用最小占位展示，不实现完整文件卡片 UI。
- 预览相关 switch 对 `.file` 使用最小 fallback，不实现 Quick Look。
- 粘贴相关 switch 对 `.file` 使用最小 fallback，不实现文件粘贴捕获或文件引用粘贴执行。
- 富文本编辑相关 switch 对 `.file` 使用最小 fallback，不提供文件内容编辑入口。
- 其他新增 `.file` switch 缺口只做构建恢复所需的保守分支，不扩展 Stage 9 第一批数据层范围。
验证结果：
- Bugfix Agent 已重新运行 `swift build` 并通过。
- 数据层基础保持完成状态。
- 当前记录不代表 Quick Look、文件捕获、文件粘贴执行或文件卡片完整 UI 已进入实现。
主控已调度门禁：
- Test Agent：`V2-TEST-S9-FILE-CARD-DATA-FOUNDATION-001`
- Review Agent：`V2-REVIEW-S9-FILE-CARD-DATA-FOUNDATION-001`
- Architecture Gatekeeper：`V2-ARCH-S9-FILE-CARD-DATA-FOUNDATION-REVIEW-001`
禁改范围：
- 禁改 Quick Look 实现。
- 禁改剪贴板文件捕获。
- 禁改 PasteExecutor 文件粘贴执行语义。
- 禁改 Storage / schema / model / repository。
- 禁改原文件删除 / 移动 / 复制。
- 禁改 security scoped bookmark。
- 禁改删除撤销。
- 禁改收藏 / 管理 / 多选 / 批量。
- 禁改 FTS / LIKE / 文件路径索引。
- 禁改 JSON migration runtime。
后续门禁：
- Test Agent 需覆盖 Stage 9 数据层、`.file` 最小 fallback 编译接线、备份不含原文件副本、删除历史不影响原文件、iCloud placeholder / alias 不主动解析等红线。
- Review Agent 需复核 Bugfix 是否只做最小编译 fallback，未越界实现 UI / Quick Look / PasteExecutor / ClipboardMonitor / Storage schema 追加改动。
- Architecture Gatekeeper 需复核 Stage 9 第一批数据基础与后续 Quick Look / UI 批次之间的边界是否保持清晰。
- Test / Review / Architecture 通过后，再由主控决定是否进入 Acceptance 或下一批 Stage 9 UI / Quick Look 前置调度。
当前状态：
- `V2-BUGFIX-S9-FILE-TYPE-COMPILE-WIRING-001-RERUN` 已完成。
- Stage 9 文件卡片数据层基础已从编译 HOLD 进入 Test / Review / Architecture 门禁。
- 当前记录未修改业务代码，未运行构建，未回退任何改动。
交付摘要：Docs/Log Agent 已追加 Stage 9 文件卡片数据层最小编译接线完成记录，确认 Bugfix Agent `V2-BUGFIX-S9-FILE-TYPE-COMPILE-WIRING-001-RERUN` 已完成并补齐 `.file` 最小编译 fallback，使 `swift build` 通过；记录 fallback 清单包含历史卡片 / 列表、预览、粘贴、富文本编辑和其他 switch 缺口的保守分支；记录主控已调度 Test `V2-TEST-S9-FILE-CARD-DATA-FOUNDATION-001`、Review `V2-REVIEW-S9-FILE-CARD-DATA-FOUNDATION-001`、Architecture `V2-ARCH-S9-FILE-CARD-DATA-FOUNDATION-REVIEW-001`；明确禁改 Quick Look、剪贴板文件捕获、PasteExecutor 文件粘贴执行、Storage / schema / model / repository、原文件删除移动复制、security scoped bookmark、删除撤销、收藏 / 管理 / 多选 / 批量、FTS / LIKE / 文件路径索引、JSON migration runtime；未修改业务代码，未运行构建，未回退任何改动。
```

## 146. Stage 9 文件卡片数据基础 RC 对齐与 Test HOLD 解除准备记录

```text
调度 ID：V2-DOCS-S9-RC-RUNBOOK-ALIGN-001
时间：2026-05-14
阶段：第二版 Stage 9 文件卡片数据基础 / RC 报告对齐
任务卡 ID：V2-DOCS-S9-RC-RUNBOOK-ALIGN-001
当前会话模式：ClipEase V2 Docs/Log Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新文档，不修改业务代码，不运行构建
当前 Info.plist：
- 当前版本：`1.0.13`
- 当前构建号：`260514.2108`
- 当前 build/run：`1.0.13 (260514.2108)`
门禁状态：
- Stage 9 文件卡片数据基础已完成。
- `.file` 最小编译 fallback 已完成。
- Architecture Gatekeeper：PASS。
- Review Agent：PASS。
- Test Agent：除 smoke RC 对齐外 PASS。
- Test HOLD 唯一原因：`docs/RELEASE_CANDIDATE_REPORT.md` 未同步当前 Info.plist `1.0.13 (260514.2108)`。
本次 Docs 对齐：
- 已更新 `docs/RELEASE_CANDIDATE_REPORT.md` 当前 RC 包信息到 `1.0.13` / `260514.2108`。
- 已追加 Stage 9 数据基础与 `.file` fallback 门禁状态。
- 已明确 `.file` 的 HistoryWindow / Preview / PasteExecutor / RichTextEditor 处理只是最小编译 fallback。
范围边界：
- 这不是 Quick Look 正式实现。
- 这不是文件捕获正式实现。
- 这不是文件粘贴执行正式实现。
- 这不是文件卡片完整 UI 正式实现。
- HistoryWindow / PasteExecutor 对 `.file` 的处理仅用于编译 fallback 和保守占位，不代表 Stage 9 后续 UI / Quick Look / Paste 语义已放行。
后续门禁：
- 主控需调度 Test Agent 重跑 smoke。
- smoke 通过后继续 Acceptance。
- Test / Acceptance 通过前，不得把 `.file` fallback 解释为 Quick Look、文件捕获或文件粘贴正式能力。
当前状态：
- RC 文档对齐已完成。
- 等待 Test Agent 重跑 smoke / 门禁。
- 等待 Acceptance Agent 复核放行。
- 当前记录未修改业务代码，未运行构建，未回退任何改动。
交付摘要：Docs/Log Agent 已根据 `V2-DOCS-S9-RC-RUNBOOK-ALIGN-001` 对齐 `docs/RELEASE_CANDIDATE_REPORT.md` 与当前 Info.plist `1.0.13 (260514.2108)`；记录 Stage 9 文件卡片数据基础与 `.file` 最小编译 fallback 已完成，Architecture PASS、Review PASS、Test 除 smoke RC 对齐外 PASS；记录 Test HOLD 唯一原因为 RC 报告未同步当前版本；明确 HistoryWindow / PasteExecutor 等 `.file` 处理只是编译 fallback，不是 Quick Look、文件捕获、文件粘贴或完整 UI 正式实现；后续需重跑 Test / smoke 和 Acceptance；未修改业务代码，未运行构建。
```

## 147. Stage 9 文件卡片数据基础 Acceptance PASS 记录

```text
调度 ID：V2-ACCEPT-S9-FILE-CARD-DATA-FOUNDATION-001
时间：2026-05-14
阶段：第二版 Stage 9 文件卡片数据基础 / Acceptance
任务卡 ID：V2-ACCEPT-S9-FILE-CARD-DATA-FOUNDATION-001
当前会话模式：ClipEase V2 Acceptance Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅追加验收结论，不修改业务代码
验收输入：
- Stage 9 文件卡片数据基础已完成。
- `.file` 最小编译 fallback 已完成。
- Architecture Gatekeeper：PASS。
- Review Agent：PASS。
- `swift build`：PASS，由前置门禁确认。
- `python3 scripts/smoke_check.py`：PASS，RC 已对齐 `1.0.13(260514.2108)`。
- `python3 scripts/verify_stage9_file_card_data_foundation.py`：PASS。
- `python3 scripts/verify_sqlite_only_baseline.py`：PASS。
- `python3 scripts/verify_no_management_no_favorite_ui.py`：PASS。
- `python3 scripts/verify_stage8_window_experience.py`：PASS。
本次 Acceptance 复核：
- 已复核 `python3 scripts/smoke_check.py`，PASS。
- 已复核 `python3 scripts/verify_stage9_file_card_data_foundation.py`，PASS。
- 已复核 `python3 scripts/verify_sqlite_only_baseline.py`，PASS。
- 已复核 `python3 scripts/verify_no_management_no_favorite_ui.py`，PASS。
- 已复核 `python3 scripts/verify_stage8_window_experience.py`，PASS。
Acceptance 结论：
- PASS。
- Stage 9 文件卡片数据基础可以放行到下一批。
- 下一批可按主控节奏进入 ClipboardMonitor 文件捕获、文件卡片 UI、Quick Look spike 的独立小批次调度。
当前放行范围：
- 仅放行 Stage 9 文件卡片数据基础。
- 仅放行 `.file` 最小编译 fallback。
- `.file` fallback 仅用于保守占位、编译恢复和后续批次接线前的最小兼容。
明确不包含：
- 不包括正式 Quick Look。
- 不包括 ClipboardMonitor 文件捕获。
- 不包括文件 pasteboard 粘贴。
- 不包括文件卡片完整 UI。
- 不包括文件删除 / 移动 / 复制。
- 不包括 security-scoped bookmark。
- 不包括 FTS / 拼音 / SQLite 路径索引。
后续建议：
- ClipboardMonitor 文件捕获、文件卡片 UI、Quick Look spike 应拆成独立任务卡分别进入 Architecture / Test / Review / Acceptance。
- 每个后续任务继续保留 SQLite-only、no favorite、no management、no multi-select、no batch 基线门禁。
- 文件捕获批次需继续验证备份不包含原文件副本、删除历史不影响原文件、iCloud placeholder 和 alias 不主动解析。
- Quick Look spike 需单独确认只读预览边界，不引入文件写入、移动、复制、删除或 security-scoped bookmark 持久化。
当前状态：
- Stage 9 文件卡片数据基础 Acceptance PASS。
- 可进入下一批 Stage 9 文件捕获 / 文件卡片 UI / Quick Look spike 前置调度。
- 当前记录未修改业务代码，未回退任何改动。
交付摘要：Acceptance Agent 已完成 `V2-ACCEPT-S9-FILE-CARD-DATA-FOUNDATION-001` 验收；复核 smoke、stage9 file card data foundation、sqlite-only baseline、no-management/no-favorite、stage8 window experience 均 PASS；确认前置 Architecture / Review / swift build 门禁已 PASS；结论为 Stage 9 数据基础与 `.file` 最小编译 fallback 可放行到下一批；明确本次不包含正式 Quick Look、文件捕获、文件 pasteboard 粘贴、文件卡片完整 UI、文件删除 / 移动 / 复制、security-scoped bookmark、FTS / 拼音 / SQLite 路径索引；仅更新本 runbook 记录，未修改业务代码。
```

## 148. Stage 9 文件卡片数据基础 Acceptance PASS 后主控 build/run 记录

```text
调度 ID：V2-DOCS-S9-BUILDRUN-1014-RC-ALIGN-001
时间：2026-05-14
阶段：第二版 Stage 9 文件卡片数据基础 / Acceptance PASS 后 build/run
任务卡 ID：V2-DOCS-S9-BUILDRUN-1014-RC-ALIGN-001
当前会话模式：ClipEase V2 Docs/Log Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新文档和日志，不修改业务代码
触发背景：
- Stage 9 文件卡片数据基础 Acceptance PASS。
- 主控随后执行 `scripts/build-app.sh`。
- 构建脚本自动从 `1.0.13 (260514.2108)` 提升到 `1.0.14 (260514.2215)`。
build/run 结果：
- 构建产物：`/Users/wpc/code/codex/ClipboardHistory/.build/ClipEase.app`
- 当前运行版本：`1.0.14 (260514.2215)`
- 当前运行 PID：`38068`
当前包范围：
- 仍仅为 Stage 9 文件卡片数据基础可测包。
- 仍仅包含 `.file` 最小编译 fallback。
- `.file` fallback 仅用于保守占位、编译恢复和后续批次接线前的最小兼容。
明确不代表：
- 不代表正式 Quick Look 已完成。
- 不代表 ClipboardMonitor 文件捕获已完成。
- 不代表文件 pasteboard 粘贴已完成。
- 不代表完整文件卡片 UI 已完成。
- 不代表文件删除 / 移动 / 复制、security-scoped bookmark、FTS / 拼音 / SQLite 路径索引已放行。
文档更新：
- 已更新 `docs/RELEASE_CANDIDATE_REPORT.md` 当前 RC 包信息到 `1.0.14` / `260514.2215`。
- 已追加 `1.0.14(260514.2215)` build/run 记录。
当前状态：
- `.build/ClipEase.app` 已由主控 build/run 启动，PID `38068`。
- 当前记录未修改业务代码，未运行构建，未回退任何改动。
交付摘要：Docs/Log Agent 已记录 Stage 9 文件卡片数据基础 Acceptance PASS 后主控 build/run；确认构建脚本自动从 `1.0.13 (260514.2108)` 提升到 `1.0.14 (260514.2215)`，产物 `/Users/wpc/code/codex/ClipboardHistory/.build/ClipEase.app` 已启动，PID `38068`；明确当前包仍只是 Stage 9 数据基础与 `.file` 最小编译 fallback 的可测包，不代表正式 Quick Look、文件捕获、文件 pasteboard 粘贴或完整文件卡片 UI 完成；仅更新文档，未修改业务代码，未运行构建。
```

## 149. Stage 9 文件卡片 ClipboardMonitor 文件捕获第一批调度记录

```text
调度 ID：V2-S9-FILE-CAPTURE-FIRST-BATCH-001
时间：2026-05-14
阶段：第二版 Stage 9 文件卡片 / ClipboardMonitor 文件捕获第一批
任务卡 ID：V2-S9-FILE-CAPTURE-FIRST-BATCH-001
当前会话模式：ClipEase V2 Docs/Log Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：高；涉及 ClipboardMonitor 捕获路径与历史记录写入，但本记录仅追加文档，不修改业务代码，不运行构建
触发背景：
- Stage 9 文件卡片数据基础已 Acceptance PASS。
- 主控已 build/run 到 `1.0.14 (260514.2215)`，运行 PID `38068`。
- Stage 9 下一批进入 ClipboardMonitor 文件捕获。
目标范围：
- 识别剪贴板中的本地 `file://` 文件 URL。
- 为识别出的本地文件 URL 生成 `.file` 类型历史记录。
- 保存完整文件路径与必要元数据。
- 写入必须走 `ClipboardHistoryStore` / repository 既有路径。
- 不允许绕过 store / repository 直接写入 UI 或直接构造 UI 状态。
允许修改文件：
- `Sources/ClipEase/Features/ClipboardMonitor/ClipboardMonitor.swift`
- `Sources/ClipEase/Core/Storage/ClipboardHistoryStore.swift`
- 必要的 Stage 9 验证脚本
禁止修改文件 / 范围：
- 禁止修改 Quick Look。
- 禁止修改 PasteExecutor 文件粘贴执行。
- 禁止实现完整文件卡片 UI。
- 禁止修改 schema / model，除非发现阻塞并先回报主控。
- 禁止恢复收藏 / 管理模式 / 多选 / 批量。
- 禁止恢复 JSON migration runtime。
红线：
- 不下载 iCloud placeholder。
- 不解析 alias 并改写路径。
- 不记录 security-scoped bookmark。
- 不复制、移动或删除原文件。
- 不新增 FTS / LIKE / 拼音 / SQLite 文件路径索引。
- 不恢复收藏 / 管理模式 / 多选 / 批量 / JSON migration runtime。
实现要求：
- ClipboardMonitor 仅负责识别并提交 `.file` 历史记录数据。
- 文件引用应保留用户剪贴板提供的本地文件路径语义，不主动改写成其他解析结果。
- iCloud placeholder、alias、权限受限文件和失效路径只允许保守记录或保守跳过，具体策略如遇阻塞必须回报主控。
- 任何历史写入都必须复用现有 store / repository 路径，保证 SQLite-only 基线和后续门禁可验证。
后续门禁：
- 实现完成后必须进入 Test / Review / Acceptance。
- Test 需覆盖本地 `file://` 捕获、`.file` 历史记录生成、完整路径与元数据保存、store / repository 写入路径、iCloud placeholder 不下载、alias 不解析改写、删除历史不影响原文件、无 FTS / LIKE / 拼音 / SQLite 文件路径索引新增。
- Review 需复核实现未越界到 Quick Look、PasteExecutor 文件粘贴执行、完整文件卡片 UI、schema / model、security-scoped bookmark、文件复制 / 移动 / 删除、收藏 / 管理 / 多选 / 批量、JSON migration runtime。
- Acceptance 通过后才可放行进入后续文件卡片 UI / Quick Look / PasteExecutor 独立批次。
- 构建运行由主控执行，开发 Worker 不执行最终 build/run 放行。
当前状态：
- `V2-S9-FILE-CAPTURE-FIRST-BATCH-001` 已调度。
- 等待开发 Worker 按文件锁和红线实现 ClipboardMonitor 文件捕获第一批。
- 当前记录未修改业务代码，未运行构建，未回退任何改动。
交付摘要：Docs/Log Agent 已追加 Stage 9 文件卡片 ClipboardMonitor 文件捕获第一批调度记录；调度 ID 为 `V2-S9-FILE-CAPTURE-FIRST-BATCH-001`；明确范围为识别剪贴板本地 `file://` 文件 URL，生成 `.file` 历史记录，保存完整路径与元数据，并通过 `ClipboardHistoryStore` / repository 既有路径写入；文件锁允许修改 ClipboardMonitor、ClipboardHistoryStore 和必要验证脚本；禁止修改 Quick Look、PasteExecutor 文件粘贴执行、完整文件卡片 UI、schema / model 除非阻塞回报主控；红线包括不下载 iCloud placeholder、不解析 alias 改写路径、不记录 security-scoped bookmark、不复制 / 移动 / 删除原文件、不新增 FTS / LIKE / 拼音 / SQLite 文件路径索引、不恢复收藏 / 管理模式 / 多选 / 批量 / JSON migration runtime；实现后必须 Test / Review / Acceptance，构建运行由主控执行；仅更新文档，未修改业务代码，未运行构建。
```

## 150. Stage 9 文件卡片 ClipboardMonitor 文件捕获第一批测试记录

```text
调度 ID：V2-TEST-S9-FILE-CAPTURE-FIRST-BATCH-001
时间：2026-05-14 23:20:30 CST
阶段：第二版 Stage 9 文件卡片 / ClipboardMonitor 文件捕获第一批
任务卡 ID：V2-TEST-S9-FILE-CAPTURE-FIRST-BATCH-001
当前会话模式：ClipEase V2 Test Agent
主控 Agent：用户指定任务卡
被调用 Agent：ClipEase V2 Test Agent
风险等级：高；涉及 ClipboardMonitor 捕获优先级、文件引用元数据、SQLite-only 基线和红线回归
文件锁：
- docs/V2_AGENT_RUNBOOK.md：测试结论追加
测试范围：
- 独立验证开发 Worker 已完成的 `V2-S9-FILE-CAPTURE-FIRST-BATCH-001`。
- 确认 ClipboardMonitor 优先捕获本地 `file://` URL，先于图片和文字捕获。
- 确认只记录本地 file URL。
- 确认不记录 bookmark、不下载 iCloud、不解析 alias 改写路径。
- 确认删除历史仍不删除原文件。
- 确认不恢复收藏 / 管理模式 / 多选 / 批量 / JSON migration runtime。
执行命令：
- `swift build`：通过。
- `python3 scripts/smoke_check.py`：通过；版本 `1.0.14(260514.2215)` 合法，RC 报告匹配当前版本，未出现 RC 报告版本不匹配 HOLD。
- `python3 scripts/verify_stage9_file_capture_first_batch.py`：通过。
- `python3 scripts/verify_stage9_file_card_data_foundation.py`：通过。
- `python3 scripts/verify_sqlite_only_baseline.py`：通过。
- `python3 scripts/verify_no_management_no_favorite_ui.py`：通过。
- `python3 scripts/verify_stage8_window_experience.py`：通过。
- `git diff --check`：通过。
验证摘要：
- `ClipboardMonitor.poll()` 中 `localFileURLsFromPasteboard()` 调用顺序早于 `NSImage` 读取和 `.string` 文本读取，并在捕获到文件 URL 后调用 `store.addFiles(...)` 后返回。
- `localFileURLsFromPasteboard()` 使用 `.urlReadingFileURLsOnly` 并过滤 `url.isFileURL`，同时处理 Finder `.fileURL` pasteboard item。
- `ClipboardHistoryStore.addFiles(...)` 通过 `ClipboardItem.file(...)` 生成历史记录，执行去重、排序、retention 和保存。
- 文件引用元数据读取包含 content type、size、modified date、directory、alias 标记、pathStatus 和 lastCheckedAt。
- iCloud `.notDownloaded` 仅保守标记为 `.placeholder`；未发现下载触发。
- Store 未发现 alias resolving 或 bookmark 创建；Stage 9 首批未引入 Quick Look 或文件 pasteboard 粘贴执行。
- 删除历史路径 `deleteExternalFiles(for:)` 仅清理 ClipEase 自管图片和富文本附件，不删除 `.file` 原始路径引用。
- 管理模式 / 收藏 UI / 多选 / 批量 / JSON migration runtime 回归脚本通过。
结论：PASS。
剩余风险：
- 本次主要为构建和静态 / 脚本验证，未执行真实 Finder 剪贴板端到端人工复制文件验证。
- 当前范围明确不包含 Quick Look、文件 pasteboard 粘贴执行、完整文件卡片 UI；这些仍需后续批次独立测试。
后续动作：
- 可进入 Review / Acceptance；如需更强信心，建议后续在运行包上补一次 Finder 复制本地文件的人工端到端验证。
```

## 151. Stage 9 文件卡片 ClipboardMonitor 文件捕获第一批验收记录

```text
调度 ID：V2-ACCEPT-S9-FILE-CAPTURE-FIRST-BATCH-001
时间：2026-05-14 23:35:00 CST
阶段：第二版 Stage 9 文件卡片 / ClipboardMonitor 文件捕获第一批
任务卡 ID：V2-ACCEPT-S9-FILE-CAPTURE-FIRST-BATCH-001
当前会话模式：ClipEase V2 Acceptance Agent
主控 Agent：用户指定任务卡
被调用 Agent：ClipEase V2 Acceptance Agent
风险等级：高；涉及 ClipboardMonitor 文件 URL 捕获、SQLite metadata 写入和 Stage 9 后续人工 build/run 放行
文件锁：
- docs/V2_AGENT_RUNBOOK.md：验收结论追加
验收依据：
- Worker 已完成 `V2-S9-FILE-CAPTURE-FIRST-BATCH-001`。
- Review PASS：无阻断 / HOLD。
- Test PASS：`swift build`、`smoke_check`、`verify_stage9_file_capture_first_batch.py`、Stage 9 数据基础、SQLite-only、no management/no favorite、Stage 8 window、`git diff --check` 全部通过。
放行结论：PASS。
是否放行：
- 放行 Stage 9 文件捕获第一批进入 build/run 用户人工测试。
放行范围：
- ClipboardMonitor 捕获本地 `file://` 文件 URL。
- 通过 Store 生成 `.file` 历史记录。
- 写入 SQLite metadata。
- 支持单文件和多文件。
- 完整路径和文件元数据采用保守记录策略。
明确不包含：
- 正式 Quick Look。
- 文件 pasteboard 粘贴执行。
- 完整文件卡片 UI。
- 文件删除 / 移动 / 复制能力。
- security-scoped bookmark。
- FTS / 拼音 / SQLite 路径索引。
- 收藏 / 管理模式 / 多选 / 批量能力。
- JSON migration runtime。
剩余风险：
- 尚未完成真实 Finder 复制文件到剪贴板后的人工端到端测试。
- 需 build/run 后由用户验证真实 Finder 文件复制、单文件 / 多文件进入历史记录、metadata 展示或诊断路径符合预期。
后续动作：
- 主控可安排 build/run。
- 用户人工测试通过后，再进入 Stage 9 文件卡片 UI、Quick Look、PasteExecutor 文件粘贴等后续独立批次。
- 如人工测试发现 Finder pasteboard 类型差异、权限差异或 metadata 缺失，应新开缺陷任务，不扩大本批次范围。
交付摘要：Acceptance Agent 已追加 `V2-ACCEPT-S9-FILE-CAPTURE-FIRST-BATCH-001` 验收记录；结论 PASS，放行 Stage 9 文件捕获第一批进入 build/run 用户人工测试；放行范围限定为 ClipboardMonitor 捕获本地 `file://` 文件 URL、Store `.file` 历史记录、SQLite metadata、单 / 多文件和保守路径 / 元数据记录；明确不包含 Quick Look、文件 pasteboard 粘贴执行、完整文件卡片 UI、文件删除 / 移动 / 复制、security-scoped bookmark、FTS / 拼音 / SQLite 路径索引、收藏 / 管理模式 / 多选 / 批量、JSON migration runtime；剩余风险为尚未完成真实 Finder 复制文件到剪贴板后的人工端到端测试，需 build/run 后由用户测试。
```

## 152. Stage 9 文件卡片 ClipboardMonitor 文件捕获第一批主控 build/run 记录

```text
调度 ID：V2-DOCS-S9-FILE-CAPTURE-BUILDRUN-1015-RC-ALIGN-001
时间：2026-05-14
阶段：第二版 Stage 9 文件卡片 / ClipboardMonitor 文件捕获第一批 Acceptance PASS 后 build/run
任务卡 ID：V2-DOCS-S9-FILE-CAPTURE-BUILDRUN-1015-RC-ALIGN-001
当前会话模式：ClipEase V2 Docs/Log Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；本记录仅更新文档和日志，不修改业务代码，不运行构建
触发背景：
- Stage 9 ClipboardMonitor 文件捕获第一批 Acceptance PASS。
- 主控随后执行 `scripts/build-app.sh`。
- 构建脚本自动从 `1.0.14 (260514.2215)` 提升到 `1.0.15 (260514.2323)`。
build/run 结果：
- 构建产物：`/Users/wpc/code/codex/ClipboardHistory/.build/ClipEase.app`
- 当前运行版本：`1.0.15 (260514.2323)`
- 当前运行 PID：`7935`
当前包范围：
- 包含 Stage 9 文件捕获第一批。
- ClipboardMonitor 捕获本地 file URL。
- 通过 Store 生成 `.file` 历史记录。
- 写入 SQLite metadata。
- 当前包用于用户人工测试真实 Finder 复制文件到剪贴板的端到端路径。
明确不包含：
- 正式 Quick Look。
- 文件 pasteboard 粘贴执行。
- 完整文件卡片 UI。
- 文件操作。
- security-scoped bookmark。
- FTS / 拼音 / SQLite 路径索引。
后续动作：
- 由用户执行 Finder 文件复制人工端到端测试。
- 人工测试重点为真实 Finder 复制本地文件、单文件 / 多文件进入历史记录、metadata 展示或诊断路径符合预期。
- 如人工测试发现 Finder pasteboard 类型差异、权限差异或 metadata 缺失，应新开缺陷任务，不扩大本批次范围。
文档更新：
- 已更新 `docs/RELEASE_CANDIDATE_REPORT.md` 当前 RC 包信息到 `1.0.15` / `260514.2323`。
- 已追加 `1.0.15(260514.2323)` build/run 记录。
- 已记录后续由用户做 Finder 文件复制人工端到端测试。
当前状态：
- `.build/ClipEase.app` 已由主控 build/run 启动，PID `7935`。
- 当前记录未修改业务代码，未运行构建，未回退任何改动。
交付摘要：Docs/Log Agent 已记录 Stage 9 ClipboardMonitor 文件捕获第一批 Acceptance PASS 后主控 build/run；确认构建脚本自动从 `1.0.14 (260514.2215)` 提升到 `1.0.15 (260514.2323)`，产物 `/Users/wpc/code/codex/ClipboardHistory/.build/ClipEase.app` 已启动，PID `7935`；当前包包含 ClipboardMonitor 捕获本地 file URL -> Store `.file` -> SQLite metadata，用于用户人工测试真实 Finder 复制文件到剪贴板的端到端路径；明确不包含正式 Quick Look、文件 pasteboard 粘贴执行、完整文件卡片 UI、文件操作、security-scoped bookmark、FTS / 拼音 / SQLite 路径索引；仅更新文档，未修改业务代码，未运行构建。
```

## 153. Stage 9 文件卡片 UI 第一批调度记录

```text
调度 ID：V2-S9-FILE-CARD-UI-FIRST-BATCH-001
时间：2026-05-14
阶段：第二版 Stage 9 文件卡片 UI 第一批
任务卡 ID：V2-DOCS-S9-FILE-CARD-UI-DISPATCH-001
当前会话模式：ClipEase V2 Docs/Log Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：中；涉及主窗口历史卡片展示层，但本记录仅更新文档，不修改业务代码，不运行构建
触发背景：
- Stage 9 文件捕获第一批已通过用户人工测试。
- 用户回复“没问题，请继续”。
- 主控进入下一批：文件卡片 UI 第一批。
主控调度：
- 主控已调度 `V2-S9-FILE-CARD-UI-FIRST-BATCH-001` 做 Stage 9 文件卡片 UI 第一批实现。
范围：
- 主窗口卡片层展示 `.file` 类型，不再映射成纯文本 fallback。
- 展示文件图标、文件名、完整路径。
- 展示单文件 / 多文件数量。
- 对目录、缺失、placeholder、权限等状态使用保守文案。
- 搜索仍使用内存 `searchText`，不新增 SQLite 索引。
文件锁：
- 可修改 `Sources/ClipEase/Features/HistoryWindow/HistoryPreviewItem.swift`。
- 可修改 `Sources/ClipEase/Features/HistoryWindow/HistoryCardView.swift`。
- 必要时可小范围修改 `Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift` 的 search token / type 映射。
- 可新增验证脚本。
禁止修改：
- `ClipboardMonitor`。
- `PasteExecutor` 文件粘贴执行。
- Quick Look。
- Storage schema / model / repository。
红线：
- 不实现 Quick Look。
- 不实现文件 pasteboard 粘贴。
- 不复制 / 移动 / 删除原文件。
- 不新增 security-scoped bookmark。
- 不新增 FTS / LIKE / 拼音 / SQLite 路径索引。
- 不恢复收藏 / 管理 / 多选 / 批量 / JSON migration runtime。
后续门禁：
- 实现完成后必须调度 Test Agent。
- Test PASS 后必须调度 Review Agent。
- Review PASS 后必须调度 Acceptance Agent。
- Acceptance PASS 后由主控执行 build/run。
当前状态：
- `V2-S9-FILE-CARD-UI-FIRST-BATCH-001` 已调度。
- Stage 9 文件卡片 UI 第一批进入实现前记录完成。
- 当前记录未修改业务代码，未运行构建，未回退任何改动。
交付摘要：Docs/Log Agent 已追加 Stage 9 文件卡片 UI 第一批调度记录；调度 ID 为 `V2-S9-FILE-CARD-UI-FIRST-BATCH-001`；明确范围为主窗口卡片层展示 `.file` 类型，不再映射成纯文本 fallback，显示文件图标、文件名、完整路径、单 / 多文件数量，并对目录 / 缺失 / placeholder / 权限等状态使用保守文案；搜索仍使用内存 `searchText`，不新增 SQLite 索引；文件锁允许修改 HistoryPreviewItem、HistoryCardView、必要时小范围修改 HistoryWindowView 的 search token / type 映射，并可新增验证脚本；禁止修改 ClipboardMonitor、PasteExecutor 文件粘贴执行、Quick Look、Storage schema / model / repository；红线包括不实现 Quick Look、不实现文件 pasteboard 粘贴、不复制 / 移动 / 删除原文件、不新增 security-scoped bookmark、不新增 FTS / LIKE / 拼音 / SQLite 路径索引、不恢复收藏 / 管理 / 多选 / 批量 / JSON migration runtime；后续必须 Test / Review / Acceptance，主控 build/run；仅更新文档，未修改业务代码，未运行构建。
```

## 154. Stage 9 文件卡片 UI 第一批测试记录

```text
调度 ID：V2-TEST-S9-FILE-CARD-UI-FIRST-BATCH-001
时间：2026-05-14
阶段：第二版 Stage 9 文件卡片 UI 第一批
任务卡 ID：V2-TEST-S9-FILE-CARD-UI-FIRST-BATCH-001
当前会话模式：ClipEase V2 Test Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：中；涉及主窗口历史卡片展示、搜索 token 和 Stage 9 文件卡片 UI 边界

验证命令：
- `swift build`：PASS
- `python3 scripts/smoke_check.py`：PASS
- `python3 scripts/verify_stage9_file_card_ui.py`：PASS
- `python3 scripts/verify_stage9_file_capture_first_batch.py`：PASS
- `python3 scripts/verify_stage9_file_card_data_foundation.py`：PASS
- `python3 scripts/verify_sqlite_only_baseline.py`：PASS
- `python3 scripts/verify_no_management_no_favorite_ui.py`：PASS
- `python3 scripts/verify_stage8_window_experience.py`：PASS
- `git diff --check`：PASS

关键验证结论：
- `.file` 已作为 `HistoryPreviewType.file` 独立 preview type 映射，未继续映射成 `.text` fallback。
- `HistoryPreviewItem` 新增轻量文件展示 DTO `HistoryFilePreviewReference`，由 `item.fileReferences` 映射出展示所需的文件名、完整路径、目录标记和路径状态；未直接向 UI 暴露 storage DTO。
- `HistoryCardView` 已为 `.file` 走专用 `filePreview`，展示文件图标、主文件名、完整路径、单文件 / 文件夹 / 多项目数量，并包含 `缺失`、`无权限`、`占位`、`未确认` 等保守状态文案。
- 内存搜索文本包含文件 displayName 和完整 path；SQLite-only 验证与 file card UI 验证均通过，未发现新增文件名 / 路径 SQLite 搜索索引。
- Type filter 已新增 File token，标题为 `文件`，图标为 `doc`，并映射到 `HistoryPreviewType.file`。
- 本批未实现 Quick Look，未实现文件 pasteboard 粘贴执行，未实现 Finder 操作，未新增原文件复制 / 移动 / 删除，未新增 security-scoped bookmark。
- smoke 未出现 RC 版本 HOLD，本轮不是文档版本问题。

风险与后续：
- 本轮为静态脚本 + 编译验证，未做真实 Finder 文件复制后的人工 UI 视觉验收；建议 Acceptance 后由主控 build/run，再做真实单文件 / 多文件卡片展示人工确认。
- 文件卡片当前最多展示前三条路径摘要，属于 UI 展示取舍；若后续产品要求完整多文件展开，需要进入独立批次。
- Quick Look、文件粘贴执行、Finder 操作、bookmark 仍为后续独立范围，不能由本批测试 PASS 推导为已完成。

当前状态：
- 结论：PASS。
- 当前记录只追加 `docs/V2_AGENT_RUNBOOK.md` 测试记录。
- 未修改业务代码，未回退任何改动。
交付摘要：Test Agent 已完成 `V2-TEST-S9-FILE-CARD-UI-FIRST-BATCH-001` 独立验证；`swift build`、smoke、Stage 9 文件卡片 UI、文件捕获第一批、文件卡片数据基础、SQLite-only baseline、no management/no favorite、Stage 8 window experience 和 `git diff --check` 全部 PASS；确认 `.file` 已独立映射到 `HistoryPreviewType.file`，文件卡片展示文件名、完整路径、数量和保守状态，内存搜索包含文件名 / 完整路径且未新增 SQLite 文件路径索引，File type token 可匹配 `.file`；确认未实现 Quick Look、文件粘贴执行、Finder 操作、原文件复制 / 移动 / 删除、security-scoped bookmark；smoke 未因 RC 版本 HOLD；仅追加 runbook 记录，未修改业务代码。
```

## 155. Stage 9 文件卡片 UI 第一批验收记录

```text
调度 ID：V2-ACCEPT-S9-FILE-CARD-UI-FIRST-BATCH-001
时间：2026-05-14
阶段：第二版 Stage 9 文件卡片 UI 第一批
任务卡 ID：V2-ACCEPT-S9-FILE-CARD-UI-FIRST-BATCH-001
当前会话模式：ClipEase V2 Acceptance Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：中；本批进入 build/run 后仍需用户真实视觉验收

验收依据：
- Worker 已完成 `.file` 独立 preview type、文件卡片 UI、File type token、内存搜索路径 / 文件名。
- Review PASS，无 HOLD / BLOCK。
- Test PASS：`swift build`、`smoke_check`、`verify_stage9_file_card_ui.py`、文件捕获、数据基础、SQLite-only、no management/no favorite、Stage8 window、`git diff --check` 全 PASS。

放行结论：
- PASS。
- 放行 Stage 9 文件卡片 UI 第一批进入 build/run 用户人工视觉测试。

放行范围：
- 主窗口文件卡片展示文件图标。
- 主窗口文件卡片展示文件名。
- 主窗口文件卡片展示完整路径。
- 主窗口文件卡片展示单文件 / 多文件数量。
- 主窗口文件卡片展示保守路径状态。
- File type token。
- 内存搜索按文件名 / 完整路径命中。

明确不包含：
- 正式 Quick Look。
- 文件 pasteboard 粘贴执行。
- Finder 操作。
- 原文件复制 / 移动 / 删除。
- security-scoped bookmark。
- FTS / 拼音 / SQLite 路径索引。
- 收藏 / 管理 / 多选 / 批量 / JSON migration runtime。

剩余风险：
- 尚未做真实运行包的单文件 / 多文件 UI 视觉人工验收。
- 需要 build/run 后由用户测试文件卡片视觉展示，包括单文件、多文件、缺失 / 无权限 / 占位 / 未确认等保守状态是否符合预期。

下一步建议：
- 主控执行 build/run，交由用户进行 Stage 9 文件卡片 UI 第一批人工视觉测试。
- 人工测试仅覆盖本批放行范围，不将 Quick Look、文件粘贴执行、Finder 操作、bookmark、SQLite 路径索引或管理类能力纳入本批验收。

当前状态：
- 结论：PASS。
- 当前记录只追加 `docs/V2_AGENT_RUNBOOK.md` 验收记录。
- 未修改业务代码，未运行构建，未回退任何改动。
交付摘要：Acceptance Agent 已验收 `V2-ACCEPT-S9-FILE-CARD-UI-FIRST-BATCH-001`；基于 Worker 完成项、Review PASS 和 Test 全 PASS，放行 Stage 9 文件卡片 UI 第一批进入 build/run 用户人工视觉测试；放行范围为主窗口文件卡片展示文件图标、文件名、完整路径、单 / 多文件数量、保守路径状态，File type token，以及内存搜索按文件名 / 完整路径；明确不包含 Quick Look、文件 pasteboard 粘贴执行、Finder 操作、原文件复制 / 移动 / 删除、security-scoped bookmark、FTS / 拼音 / SQLite 路径索引、收藏 / 管理 / 多选 / 批量 / JSON migration runtime；剩余风险是真实运行包的单文件 / 多文件 UI 视觉人工验收尚未完成，需 build/run 后由用户测试。
```

## 156. Stage 9 文件卡片 UI 第一批主控 build/run 记录

```text
调度 ID：V2-DOCS-S9-FILE-CARD-UI-BUILDRUN-1016-RC-ALIGN-001
时间：2026-05-14
阶段：第二版 Stage 9 文件卡片 UI 第一批 Acceptance PASS 后 build/run
任务卡 ID：V2-DOCS-S9-FILE-CARD-UI-BUILDRUN-1016-RC-ALIGN-001
当前会话模式：ClipEase V2 Docs/Log Agent 模式
主控 Agent：Codex 主控 Agent

背景：
- Stage 9 文件卡片 UI 第一批 Acceptance PASS。
- 主控执行 `scripts/build-app.sh`。
- 构建脚本自动从 `1.0.15 (260514.2323)` 提升到 `1.0.16 (260514.2340)`。

build/run 结果：
- 构建产物：`/Users/wpc/code/codex/ClipboardHistory/.build/ClipEase.app`
- 当前运行版本：`1.0.16 (260514.2340)`
- 当前运行 PID：`34910`
- 包含 Stage 9 文件卡片 UI 第一批。

本包包含：
- 主窗口文件卡片展示文件图标。
- 主窗口文件卡片展示文件名。
- 主窗口文件卡片展示完整路径。
- 主窗口文件卡片展示单 / 多文件数量。
- 主窗口文件卡片展示保守路径状态。
- File type token。
- 内存搜索按文件名 / 路径命中。

明确不包含：
- 正式 Quick Look。
- 文件 pasteboard 粘贴执行。
- Finder 操作。
- 原文件复制 / 移动 / 删除。
- security-scoped bookmark。
- FTS / 拼音 / SQLite 路径索引。

后续人工验收：
- 当前包用于用户人工视觉测试单文件 / 多文件文件卡片 UI。
- 用户重点确认主窗口文件卡片图标、文件名、完整路径、数量、保守路径状态、File type token 与内存搜索展示是否符合预期。
- 人工验收不扩大到 Quick Look、文件粘贴执行、Finder 操作、原文件操作、bookmark 或 SQLite 路径索引。

当前状态：
- 已更新 `docs/RELEASE_CANDIDATE_REPORT.md` 当前 RC 包信息到 `1.0.16` / `260514.2340`。
- 已追加 `1.0.16(260514.2340)` build/run 记录。
- 已追加本 runbook build/run 记录。
- `.build/ClipEase.app` 已由主控 build/run 启动，PID `34910`。
- 仅修改文档，未修改业务代码，未运行构建，未回退任何改动。
交付摘要：Docs/Log Agent 已记录 Stage 9 文件卡片 UI 第一批 Acceptance PASS 后主控 build/run；确认构建脚本自动从 `1.0.15 (260514.2323)` 提升到 `1.0.16 (260514.2340)`，产物 `/Users/wpc/code/codex/ClipboardHistory/.build/ClipEase.app` 已启动，PID `34910`；当前包包含主窗口文件卡片展示文件图标、文件名、完整路径、单 / 多文件数量、保守路径状态、File type token，以及内存搜索按文件名 / 路径，用于用户人工视觉测试单文件 / 多文件文件卡片 UI；明确不包含正式 Quick Look、文件 pasteboard 粘贴执行、Finder 操作、原文件复制 / 移动 / 删除、security-scoped bookmark、FTS / 拼音 / SQLite 路径索引；仅更新文档，未修改业务代码，未运行构建。
```

## 157. Stage 9 HistoryWindow 主窗口卡片滚动 / 选中体验 bugfix 调度记录

```text
调度 ID：V2-BUGFIX-HISTORY-CARD-SCROLL-ALIGN-001
时间：2026-05-15
阶段：Stage 9 继续推进期间的 HistoryWindow 主窗口滚动 / 选中体验 bugfix
任务卡 ID：V2-DOCS-HISTORY-CARD-SCROLL-ALIGN-DISPATCH-001
当前会话模式：ClipEase V2 Docs/Log Agent 模式
主控 Agent：Codex 主控 Agent

背景：
- 用户在 2026-05-15 反馈主窗口卡片滚动 / 选中体验问题。
- 用户要求“继续推进整体项目，将以下内容一并在下一次修改代码时候进行修复”。
- 主控决定将该问题纳入下一次代码修改批次处理。
- 对应 Bugfix 任务卡：V2-BUGFIX-HISTORY-CARD-SCROLL-ALIGN-001。

用户问题：
- 只要有新剪切板卡片加入，无置顶时主窗口打开必须滚动到最左侧并选中新卡片，且新卡片左侧间距要显示。
- 有置顶时主窗口打开也必须选中新卡片，不能误选置顶；新卡片应平移到第一位，并显示左侧上一张卡片约 1/6 外漏。
- 当前视图左右两端的卡片若未完整展示，点击后应左右平移动画，让该卡片完整显示，并额外露出下一张约 1/6，便于用户再次点击同位置继续移出下一张。

主控调度：
- 主控已将该问题登记为下一次代码修改批次 bugfix。
- Bugfix Agent：V2-BUGFIX-HISTORY-CARD-SCROLL-ALIGN-001。
- 后续实现必须保持 Stage 9 当前功能边界，不扩大到文件捕获 / 文件卡片数据逻辑或其他业务模块。

文件锁：
- 可修改 `Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift`。
- 可新增或修改必要验证脚本。
- 必要时可小范围查看 `Sources/ClipEase/Features/HistoryWindow/HistoryWindowController.swift`。
- 不允许修改业务外模块。

禁止范围：
- 不改 Stage 9 文件捕获 / 文件卡片数据逻辑。
- 不改 ClipboardMonitor。
- 不改 PasteExecutor。
- 不改 Quick Look。
- 不改 Storage schema / model / repository。
- 不恢复收藏 / 管理 / 多选 / 批量 / JSON migration runtime。

后续门禁：
- Bugfix Agent 完成后必须进入 Test。
- Test PASS 后必须进入 Review。
- Review PASS 后必须进入 Acceptance。
- Acceptance PASS 后由主控执行 build/run。

当前状态：
- V2-BUGFIX-HISTORY-CARD-SCROLL-ALIGN-001 已登记为下一次代码修改批次。
- 本记录仅追加 `docs/V2_AGENT_RUNBOOK.md` 调度记录。
- 未修改业务代码，未运行构建，未回退任何改动。
交付摘要：Docs/Log Agent 已追加 Stage 9 继续推进期间 HistoryWindow 主窗口卡片滚动 / 选中体验 bugfix 调度记录；调度 ID 为 `V2-BUGFIX-HISTORY-CARD-SCROLL-ALIGN-001`；记录用户反馈的无置顶新卡片滚动到最左并选中、有置顶时选中新卡片且显示左侧约 1/6 外漏、边缘未完整卡片点击后平移完整显示并额外露出下一张约 1/6；文件锁限定为 `HistoryWindowView.swift`、必要验证脚本，必要时只小范围查看 `HistoryWindowController.swift`；明确禁止修改 Stage 9 文件捕获 / 文件卡片数据逻辑、ClipboardMonitor、PasteExecutor、Quick Look、Storage schema / model / repository，以及收藏 / 管理 / 多选 / 批量 / JSON migration runtime；后续必须 Test / Review / Acceptance，主控 build/run；仅更新文档，未修改业务代码，未运行构建。
```

## 158. Stage 9 HistoryWindow 主窗口卡片滚动 / 选中体验 bugfix 测试记录

```text
调度 ID：V2-TEST-HISTORY-CARD-SCROLL-ALIGN-001
时间：2026-05-15 00:45:50 CST
阶段：Stage 9 继续推进期间的 HistoryWindow 主窗口滚动 / 选中体验 bugfix 测试
任务卡 ID：V2-TEST-HISTORY-CARD-SCROLL-ALIGN-001
当前会话模式：ClipEase V2 Test Agent 模式
主控 Agent：Codex 主控 Agent

测试对象：
- Bugfix Worker 已完成 `V2-BUGFIX-HISTORY-CARD-SCROLL-ALIGN-001`。
- 目标验证新剪切板卡片打开主窗口时选中 / 滚动正确。
- 目标验证边缘未完整卡片点击后动画平移，并露出下一张约 1/6。

执行命令：
- `swift build`：PASS，Build complete! (0.25s)。
- `python3 scripts/smoke_check.py`：PASS，Smoke check passed；版本 `1.0.16(260514.2340)` 有效，RC report 与当前版本匹配。
- `python3 scripts/verify_history_card_scroll_alignment.py`：PASS，history card scroll alignment static checks。
- `python3 scripts/verify_history_selection_focus.py`：PASS，覆盖窗口可见性、新 latest item focus、清空隐藏新卡片的筛选、测量后滚动、右键选中、选中边框顶部间距。
- `python3 scripts/verify_stage9_file_card_ui.py`：PASS，Stage 9 file card UI checks passed。
- `python3 scripts/verify_stage9_file_capture_first_batch.py`：PASS，Stage 9 file capture first batch checks passed。
- `python3 scripts/verify_stage8_window_experience.py`：PASS，stage 8 window experience static checks。
- `python3 scripts/verify_no_management_no_favorite_ui.py`：PASS，no management mode or removed saved-item UI tokens。
- `git diff --check`：PASS，无 whitespace error 输出。

测试关注结论：
1. 新剪切板卡片加入后，无置顶时主窗口打开滚到最左侧并选中新卡片，左侧 padding 可见：PASS。
   - `verify_history_card_scroll_alignment.py` 断言 first card 使用 dedicated offset path，且 `targetScrollOffsetForFocusedItem` 可 `return 0` 并保留 `horizontalContentPadding`。
   - `verify_history_selection_focus.py` 断言 pending latest item 直接成为 `selectedItemID`，并通过 measured offset hook 滚动。
2. 有置顶 / 前置卡片时，仍选中新卡片，不误选置顶；目标卡片完整显示并露出左侧上一张约 1/6：PASS。
   - 静态验证断言 latest focus 不 fallback 到 `filteredItems.first?.id`，而是直接选择 `pendingLatestFocusItemID`。
   - 静态验证断言 offset 计算包含 `leadingPeekWidth`、`oneSixthPeekWidth` 与 `horizontalCardSpacing + leadingPeek`。
3. 点击左右边缘未完整卡片时，通过动画滚动让卡片完整显示并额外露出下一张约 1/6：PASS。
   - 静态验证断言 `revealPartiallyVisibleCardIfNeeded` 同时处理 `frame.minX < leftVisibleEdge` 和 `frame.maxX > rightVisibleEdge`。
   - 静态验证断言边缘 reveal 使用 `HistoryScrollCoordinator.shared.currentOffset` 计算 absolute target，并调用 `scrollToOffset(targetOffset, animated: true)`。
   - 静态验证断言 reveal 计算包含 `trailingPeekWidth` 与 `leadingPeekWidth`，分别为左右边缘保留约 1/6 相邻卡片可见区域。
4. 禁改范围：本 Test Agent 未修改业务代码，仅追加本 runbook 测试记录。
   - 当前共享工作区在测试前已存在多处未提交改动，包含 `ClipboardMonitor`、`PasteExecutor`、Storage schema / model / repository 等禁改范围文件；测试未回退、未修改这些文件。
   - `verify_history_card_scroll_alignment.py` 的 owned path 检查限定本 bugfix 自有路径为 `HistoryWindowView.swift` 与 `scripts/verify_history_card_scroll_alignment.py`。
   - 因为共享脏树已有历史改动，禁改范围只能确认“本测试未新增触碰”，不能从全局 `git status` 推断所有禁区文件均未被其他任务触碰。
5. smoke RC 版本状态：PASS，无 HOLD；当前版本文档与 app bundle 均为 `1.0.16(260514.2340)`。

风险：
- 本轮验证以静态脚本和构建为主，未进行人工视觉点击验收或运行中 UI 截图验证。
- 工作区是共享脏树，存在大量历史未提交改动；禁改范围风险需由 Review / Acceptance 结合任务归属继续确认。

最终状态：PASS。
交付摘要：Test Agent 已独立执行 `swift build`、smoke、HistoryWindow 卡片滚动对齐、latest selection focus、Stage 9 文件卡片 UI、Stage 9 文件捕获第一批、Stage 8 窗口体验、禁用管理 / 收藏 UI 与 `git diff --check`；全部 PASS；smoke 无 RC HOLD，版本 `1.0.16(260514.2340)` 文档与 bundle 匹配；确认无置顶新卡片最左侧选中、有置顶 / 前置卡片不误选置顶并露出左侧约 1/6、边缘未完整卡片点击后动画滚动并露出相邻卡片约 1/6 的静态验证均通过；本 Test Agent 仅追加 runbook 测试记录，未修改业务代码，未回退任何改动；共享工作区已有禁改范围历史改动，作为 Review / Acceptance 风险提示。
```

## 159. Stage 9 HistoryWindow 主窗口卡片滚动 / 选中体验 bugfix 复测记录

```text
调度 ID：V2-TEST-HISTORY-CARD-SCROLL-ALIGN-RERUN-001
时间：2026-05-15 00:53:28 CST
阶段：Stage 9 继续推进期间的 HistoryWindow 主窗口滚动 / 选中体验 bugfix 复测
任务卡 ID：V2-TEST-HISTORY-CARD-SCROLL-ALIGN-RERUN-001
当前会话模式：ClipEase V2 Test Agent 模式
主控 Agent：Codex 主控 Agent

复测背景：
- Review HOLD 后 Bugfix Worker 已返修 coordinator scope、pending item scroll retry、edge click single-trigger guard、verifier 禁改检查。
- 本轮按主控要求重新执行构建、smoke、HistoryWindow 卡片滚动 / 选中体验、Stage 9 文件卡片、Stage 8 窗口体验、禁管理 / 收藏 UI 与 whitespace 门禁。
- 本 Test Agent 不修改业务代码；仅允许追加本 runbook 复测记录。

执行命令：
- `swift build`：PASS，Build complete! (0.19s)。
- `python3 scripts/smoke_check.py`：PASS，Smoke check passed；版本 `1.0.16(260514.2340)` 有效，RC report 与当前版本匹配，无 smoke 版本 HOLD。
- `python3 scripts/verify_history_card_scroll_alignment.py`：PASS，history card scroll alignment static checks。
- `python3 scripts/verify_history_selection_focus.py`：PASS，覆盖窗口可见性、新 latest item focus、清空隐藏新卡片的筛选、测量后滚动、右键选中、选中边框顶部间距。
- `python3 scripts/verify_stage9_file_card_ui.py`：PASS，Stage 9 file card UI checks passed。
- `python3 scripts/verify_stage9_file_capture_first_batch.py`：PASS，Stage 9 file capture first batch checks passed。
- `python3 scripts/verify_stage8_window_experience.py`：PASS，stage 8 window experience static checks。
- `python3 scripts/verify_no_management_no_favorite_ui.py`：PASS，no management mode or removed saved-item UI tokens。
- `git diff --check`：PASS，无 whitespace error 输出。

HOLD 四项复测结论：
1. coordinator scope：PASS。
   - `verify_history_card_scroll_alignment.py` 静态断言主卡片 rail 只有一个 `HorizontalScrollWheelRedirector(scope: .cardRail)`。
   - 静态断言 group/search rail 使用 `.auxiliaryRail`，且 auxiliary rails 不更新 / 保存 `HistoryScrollCoordinator` offsets。
2. pending item scroll retry：PASS。
   - 静态断言存在 `pendingItemScrollRetryCount`、`pendingItemScrollMaxRetryCount`、有限重试终止条件。
   - 静态断言 card frame preference 更新会调用 `applyPendingItemScrollIfMeasured(pendingItemScrollID)`，测量到 frame 后再对齐滚动。
3. edge click single-trigger guard：PASS。
   - 静态断言存在 `activeImmediateSelectionItemID`，用于 zero-distance drag selection 防止重复触发边缘 reveal 动画。
   - 静态断言 `immediateSelectionGesture` 的 `.onEnded` 会重置 guard。
4. verifier 禁改检查：PASS。
   - `verify_history_card_scroll_alignment.py` 的 owned scope 限定为 `HistoryWindowView.swift`、`verify_history_card_scroll_alignment.py`、`verify_history_selection_focus.py`。
   - 静态检查 owned files 不应包含 ClipboardMonitor、PasteExecutor、SQLiteClipboardStore、ClipboardHistoryRepository、ClipboardHistoryPersistence、Quick Look、JSON migration、docs 等禁区 token。
   - 当前共享工作区测试前已存在大量未提交业务改动；本 Test Agent 未修改业务代码，未回退任何改动，仅追加本 runbook 记录。

剩余风险：
- 本轮是构建 + 静态 verifier + smoke 复测，未进行人工运行时视觉点击验收或截图验收。
- 工作区为共享脏树，`git status --short` 显示已有大量业务与文档改动；禁改检查只能证明脚本覆盖和本轮测试未新增触碰，不能替代 Review / Acceptance 对历史改动归属的判断。

最终状态：PASS。
交付摘要：Test Agent 已完成 `V2-TEST-HISTORY-CARD-SCROLL-ALIGN-RERUN-001` 复测；指定命令全部 PASS；smoke 当前版本 `1.0.16(260514.2340)` 与 RC report 匹配，无版本 HOLD；Review HOLD 四项 coordinator scope、pending item scroll retry、edge click single-trigger guard、verifier 禁改检查均已由静态脚本覆盖或可静态验证；本轮仅追加 `docs/V2_AGENT_RUNBOOK.md` 复测记录，未修改业务代码。
```

## 160. HistoryWindow 主窗口卡片滚动 / 选中体验 Acceptance 放行记录

```text
调度 ID：V2-ACCEPT-HISTORY-CARD-SCROLL-ALIGN-001
时间：2026-05-15 01:05:21 CST
阶段：Stage 9 继续推进期间的 HistoryWindow 主窗口滚动 / 选中体验 bugfix Acceptance
任务卡 ID：V2-ACCEPT-HISTORY-CARD-SCROLL-ALIGN-001
当前会话模式：ClipEase V2 Acceptance Agent 模式
主控 Agent：Codex 主控 Agent

验收依据：
- Test PASS：`swift build`、`smoke_check`、`verify_history_card_scroll_alignment.py`、`verify_history_selection_focus.py`、`verify_stage9_file_card_ui.py`、`verify_stage9_file_capture_first_batch.py`、`verify_stage8_window_experience.py`、`verify_no_management_no_favorite_ui.py`、`git diff --check` 全部通过。
- Review PASS：前一轮 P1 HOLD 已解除；cardRail / auxiliaryRail guard、pending retry、cardFrames 重试、`activeImmediateSelectionItemID` 防重复 reveal 均已覆盖。
- Acceptance Agent 未重新执行测试命令；本记录基于已提供的 Test PASS 与 Review PASS 门禁摘要作最终放行判断。

放行结论：
- PASS，放行进入主控 build / run 用户人工测试。

放行范围：
1. 新剪切板卡片打开主窗口时正确选中并滚动到目标卡片。
2. 无置顶 / 无前置卡片时，最左侧 offset 归零，并显示左侧 padding。
3. 有置顶 / 前置卡片时，仍选中新卡片，并露出上一张约 1/6。
4. 左右边缘未完整卡点击后，动画 reveal 并露出下一张约 1/6。

明确不包含：
- Stage 9 Quick Look。
- 文件粘贴执行。
- Storage / ClipboardMonitor / PasteExecutor 改动。
- 收藏 / 管理 / 多选 / 批量 / JSON migration runtime。

剩余风险：
- 尚未做真实运行态人工视觉点击验收；需要主控 build / run 后由用户执行人工测试确认视觉滚动、点击 reveal 动画与选中状态符合预期。
- 当前工作区为共享脏树，Acceptance Agent 本轮未修改业务代码，仅追加本 runbook 验收记录。

下一步建议：
1. 主控执行 build / run，打开主窗口进行人工视觉点击验收。
2. 按放行范围逐项验证：新卡片 focus、无前置 offset 归零、有前置露出约 1/6、左右边缘卡片点击 reveal。
3. 若人工测试发现运行态偏差，再回派 Bugfix Worker；否则可继续 Stage 9 主线推进。

最终状态：PASS。
交付摘要：Acceptance Agent 确认 `V2-ACCEPT-HISTORY-CARD-SCROLL-ALIGN-001` 可进入主控 build / run 用户人工测试；放行范围限定为 HistoryWindow 主窗口卡片滚动 / 选中 / 边缘 reveal 行为；不包含 Stage 9 Quick Look、文件粘贴执行、Storage / ClipboardMonitor / PasteExecutor、收藏 / 管理 / 多选 / 批量 / JSON migration runtime；剩余风险为尚未完成真实运行态人工视觉点击验收。本轮仅追加 `docs/V2_AGENT_RUNBOOK.md`，未修改业务代码。
```

## 161. HistoryWindow 主窗口卡片滚动 / 选中体验主控 build/run 记录

```text
调度 ID：V2-DOCS-HISTORY-CARD-SCROLL-ALIGN-BUILDRUN-1017-RC-ALIGN-001
时间：2026-05-15
阶段：Stage 9 继续推进期间的 HistoryWindow 主窗口滚动 / 选中体验 bugfix Acceptance PASS 后 build/run
任务卡 ID：V2-DOCS-HISTORY-CARD-SCROLL-ALIGN-BUILDRUN-1017-RC-ALIGN-001
当前会话模式：ClipEase V2 Docs/Log Agent 模式
主控 Agent：Codex 主控 Agent

背景：
- `V2-BUGFIX-HISTORY-CARD-SCROLL-ALIGN-001` Acceptance PASS。
- 主控执行 `scripts/build-app.sh`。
- 构建脚本自动从 `1.0.16 (260514.2340)` 提升到 `1.0.17 (260515.0106)`。

build/run 结果：
- 构建产物：`/Users/wpc/code/codex/ClipboardHistory/.build/ClipEase.app`
- 当前运行版本：`1.0.17 (260515.0106)`
- 当前运行 PID：`30371`
- 包含 HistoryWindow 卡片滚动 / 选中 bugfix。

本包包含：
- 新剪切板卡片打开主窗口时选中并滚动。
- 无前置 offset 归零，并显示左侧 padding。
- 有置顶 / 前置时选中新卡片，并露出上一张约 1/6。
- 左右边缘未完整卡片点击后动画 reveal，并露出下一张约 1/6。

明确不包含：
- Stage 9 Quick Look。
- 文件粘贴执行。
- Storage / ClipboardMonitor / PasteExecutor 改动。
- 收藏 / 管理 / 多选 / 批量 / JSON migration runtime。

后续人工验收：
- 后续由用户做运行态人工视觉点击验收。
- 用户重点确认新剪切板卡片 focus、无前置 offset 归零与左侧 padding、有置顶 / 前置时上一张约 1/6 外露、左右边缘卡片点击 reveal 动画与下一张约 1/6 外露。
- 人工验收不扩大到 Quick Look、文件粘贴执行、Storage / ClipboardMonitor / PasteExecutor、收藏 / 管理 / 多选 / 批量 / JSON migration runtime。

当前状态：
- 已更新 `docs/RELEASE_CANDIDATE_REPORT.md` 当前 RC 包信息到 `1.0.17` / `260515.0106`。
- 已追加 `1.0.17(260515.0106)` build/run 记录。
- 已追加本 runbook build/run 记录。
- `.build/ClipEase.app` 已由主控 build/run 启动，PID `30371`。
- 仅修改文档，未修改业务代码，未运行构建，未回退任何改动。
交付摘要：Docs/Log Agent 已记录 `V2-BUGFIX-HISTORY-CARD-SCROLL-ALIGN-001` Acceptance PASS 后主控 build/run；确认构建脚本自动从 `1.0.16 (260514.2340)` 提升到 `1.0.17 (260515.0106)`，产物 `/Users/wpc/code/codex/ClipboardHistory/.build/ClipEase.app` 已启动，PID `30371`；当前包包含 HistoryWindow 卡片滚动 / 选中 bugfix，包括新剪切板卡片打开主窗口时选中 / 滚动、无前置 offset 归零显示左侧 padding、有置顶 / 前置时选中新卡片并露出上一张约 1/6、左右边缘未完整卡片点击后动画 reveal 并露出下一张约 1/6；明确不包含 Stage 9 Quick Look、文件粘贴执行、Storage / ClipboardMonitor / PasteExecutor 改动、收藏 / 管理 / 多选 / 批量 / JSON migration runtime；后续由用户做运行态人工视觉点击验收；仅更新文档，未修改业务代码，未运行构建。
```

## 162. Stage 9 Quick Look 文件预览 spike 第一批调度记录

```text
调度 ID：V2-S9-QUICKLOOK-SPIKE-FIRST-BATCH-001
时间：2026-05-15
阶段：Stage 9 文件卡片 / Quick Look 文件预览 spike 第一批
任务卡 ID：V2-DOCS-S9-QUICKLOOK-SPIKE-DISPATCH-001
当前会话模式：ClipEase V2 Docs/Log Agent 模式
主控 Agent：Codex 主控 Agent

背景：
- Stage 9 已完成文件数据基础。
- Stage 9 已完成文件捕获第一批。
- Stage 9 已完成文件卡片 UI 第一批。
- HistoryWindow 卡片滚动 bugfix 已完成并进入主控 build/run 人工验收。
- 主控现在推进 Stage 9 Quick Look / 文件预览 spike 第一批。

实现范围：
- 复用现有 `HistoryPreviewWindowController` / `HistoryPreviewPopoverView` 生命周期。
- 在 `.file` 预览内容区接入只读 Quick Look 或系统预览能力。
- 单文件优先。
- 多文件可先做列表 + 选择首个可预览文件。
- 失败或不可预览时回退到文件图标、完整路径、状态和路径文本。

文件锁：
- 可修改 `Sources/ClipEase/Features/HistoryWindow/HistoryPreviewWindowController.swift`。
- 可修改 `Sources/ClipEase/Features/HistoryWindow/HistoryPreviewPopoverView.swift`。
- 可修改必要验证脚本。
- 必要时可新增小型 AppKit / SwiftUI bridge 文件。
- 禁止修改 ClipboardMonitor、PasteExecutor、Storage schema/model/repository、文件卡片数据结构。
- 如发现必须触碰禁止范围才能推进，先回报主控，不得自行扩大改动范围。

红线：
- 不使用全局 `QLPreviewPanel` 替代现有窗口，除非 spike 证明必须并先回报主控。
- 不写入、复制、移动、删除原文件。
- 不新增 security-scoped bookmark。
- 不实现文件 pasteboard 粘贴。
- 不新增 Finder 操作入口。
- 不新增 FTS / 拼音 / SQLite 路径索引。
- 不恢复收藏 / 管理 / 多选 / 批量 / JSON migration runtime。

门禁：
- 实现后进入 Test / Review / Acceptance。
- 主控负责 build/run。
- Worker 不得在本任务中扩大到构建发布或运行态主控验收。

当前状态：
- 已完成 Quick Look 文件预览 spike 第一批调度记录。
- 等待 Worker 按文件锁与红线实现。
- 本轮仅修改文档，未修改业务代码，未运行构建。

交付摘要：Docs/Log Agent 已追加 `V2-S9-QUICKLOOK-SPIKE-FIRST-BATCH-001` 调度记录；范围限定为复用现有 `HistoryPreviewWindowController` / `HistoryPreviewPopoverView` 生命周期，在 `.file` 预览内容区接入只读 Quick Look 或系统预览能力，单文件优先，多文件可先做列表并选择首个可预览文件，失败 / 不可预览回退到文件图标、完整路径、状态和路径文本；文件锁允许修改两个 HistoryWindow preview 文件、必要验证脚本，并可新增小型 AppKit / SwiftUI bridge 文件；禁止修改 ClipboardMonitor、PasteExecutor、Storage schema/model/repository、文件卡片数据结构；红线明确不使用全局 `QLPreviewPanel` 替代现有窗口，除非 spike 证明必须并先回报主控，不写入 / 复制 / 移动 / 删除原文件，不新增 security-scoped bookmark，不实现文件 pasteboard 粘贴，不新增 Finder 操作入口，不新增 FTS / 拼音 / SQLite 路径索引，不恢复收藏 / 管理 / 多选 / 批量 / JSON migration runtime；实现后进入 Test / Review / Acceptance，主控 build/run。
```

## 163. Stage 9 Quick Look 文件预览 spike 第一批测试记录

```text
任务卡 ID：V2-TEST-S9-QUICKLOOK-SPIKE-FIRST-BATCH-001
时间：2026-05-15
阶段：Stage 9 文件卡片 / Quick Look 文件预览 spike 第一批
当前会话模式：ClipEase V2 Test Agent 模式
结论：PASS

测试命令：
- `swift build`：PASS，Build complete。
- `python3 scripts/smoke_check.py`：PASS，版本 `1.0.17(260515.0106)` 有效，RC report 匹配当前版本，App bundle 结构有效，Smoke check passed。
- `python3 scripts/verify_stage9_quicklook_spike.py`：PASS，Stage 9 Quick Look spike checks passed。
- `python3 scripts/verify_stage9_file_card_ui.py`：PASS，Stage 9 file card UI checks passed。
- `python3 scripts/verify_stage9_file_capture_first_batch.py`：PASS，Stage 9 file capture first batch checks passed。
- `python3 scripts/verify_history_card_scroll_alignment.py`：PASS，history card scroll alignment static checks；脚本提示共享工作树存在 non-owned dirty files，不作为本验证失败。
- `python3 scripts/verify_stage8_window_experience.py`：PASS，stage 8 window experience static checks。
- `python3 scripts/verify_no_management_no_favorite_ui.py`：PASS，single delete / pin / group picker / duplicate guard / no management or favorite UI tokens 均通过。
- `git diff --check`：PASS，无 whitespace error 输出。

测试关注验证：
- 嵌入式 Quick Look：`HistoryFileQuickLookPreviewView` 使用 `QLPreviewView` + `NSViewRepresentable`，未发现 `QLPreviewPanel`。
- `.file` preview：`.file` 分支进入 dedicated `filePreviewContent`，未在 `.file` case 中使用 `LazyPreviewTextView` 作为纯路径文本 fallback。
- 多文件行为：`previewableFileReference(from:)` 使用 `references.first(where: fileIsPreviewable) ?? references.first` 选择一个主预览；列表区域使用 `ForEach(references)` 展示文件列表，避免为多文件实例化多个重型预览。
- fallback：静态检查覆盖 `missing` / `permissionDenied` / `placeholder` / directory / empty path 等状态文本与图标 fallback；不可预览或不可读时进入 `fileFallbackPreview`。
- 范围红线：Quick Look spike 静态验证覆盖 preview controller / popover / bridge 内不出现 `PasteExecutor`、`ClipboardMonitor`、`SQLiteClipboardStore`、`ClipboardHistoryStore`、`ClipboardHistoryRepository`、security-scoped bookmark、pasteboard 写入、copy/move/remove 文件操作等禁止 token。
- smoke RC 状态：未出现 RC 版本 HOLD；当前 smoke 显示 `Resources/Info.plist` 与 `docs/RELEASE_CANDIDATE_REPORT.md` 版本匹配，不是仅文档版本问题。

风险与说明：
- 本轮测试只读业务代码，仅追加本 runbook 测试记录，未修改 Swift / Python 业务或验证脚本。
- 共享工作树在测试开始前已有大量未提交改动，其中包含 Stage 9 之前/并行阶段涉及的 ClipboardMonitor、PasteExecutor、Storage schema/model/repository 等文件改动；本任务未回退、未修改这些既有改动。Quick Look spike 自身的范围红线以相关 preview 文件和验证脚本静态检查为准。
- 本轮未做运行态人工 Quick Look 视觉验收；结论基于构建、静态脚本和代码抽查。

交付摘要：Test Agent 已独立运行指定门禁并全部 PASS；确认 Quick Look spike 第一批使用嵌入式 `QLPreviewView` bridge，不使用全局 `QLPreviewPanel`；`.file` preview 不再只是 `LazyPreviewTextView` 路径文本；多文件选择首个可预览文件并展示轻量列表；缺失 / 权限 / placeholder / 目录 / 不可预览状态有 fallback；smoke 未 HOLD，版本与 RC 文档匹配；仅追加 `docs/V2_AGENT_RUNBOOK.md` 测试记录，未修改业务代码。
```

## 164. Stage 9 Quick Look 文件预览 spike 第一批验收记录

```text
任务卡 ID：V2-ACCEPT-S9-QUICKLOOK-SPIKE-FIRST-BATCH-001
时间：2026-05-15
阶段：Stage 9 文件卡片 / Quick Look 文件预览 spike 第一批
当前会话模式：ClipEase V2 Acceptance Agent 模式
结论：PASS

验收结论：
- 放行 Stage 9 Quick Look / 文件预览 spike 第一批进入主控 build/run 用户人工测试。
- 本次放行基于 Worker 完成实现、Test Agent 门禁全 PASS、Review 首轮 P2 HOLD 已通过 cleanup bugfix 解除且 rerun PASS。
- 验收记录仅追加本文档；未修改业务代码、验证脚本或其他文档。

放行范围：
- `.file` 预览内容区使用 embedded `QLPreviewView` bridge。
- 复用现有 preview popover / child panel 生命周期。
- 不使用全局 `QLPreviewPanel`。
- 单文件优先预览。
- 多文件显示轻量列表，并只选择一个主文件预览。
- 路径缺失、权限不足、placeholder、目录、不可预览等场景进入 fallback。
- 关闭、切换或 SwiftUI/AppKit bridge 拆卸时执行 cleanup，将 `previewItem = nil`。

明确不包含：
- 不包含文件 pasteboard 粘贴执行。
- 不包含 Finder 操作。
- 不包含文件写入、复制、移动、删除。
- 不包含 security-scoped bookmark。
- 不包含 Storage / ClipboardMonitor / PasteExecutor 改动。
- 不包含 FTS / 拼音 / SQLite 路径索引。
- 不包含收藏、管理、多选、批量、JSON migration runtime。

剩余风险：
- 尚未做真实运行态 Quick Look 视觉验收。
- 需要主控 build/run 后，由用户人工测试单文件预览、多文件列表与单预览选择、不可预览 fallback、路径缺失 fallback、权限不足 fallback、placeholder fallback、目录 fallback，以及关闭/切换后的资源释放表现。

下一步建议：
- 主控进入 build/run，执行真实文件样本人工验收。
- 人工验收通过后，可将 Stage 9 Quick Look spike 第一批标记为用户验收通过。
- 若人工验收发现 Quick Look 空白、卡顿、焦点异常、资源未释放或 fallback 不清晰，应回流 Worker/Test/Review 针对性修复，不扩大到文件粘贴、Finder 操作或存储路径索引。

交付摘要：Acceptance Agent 放行 Stage 9 Quick Look / 文件预览 spike 第一批进入主控 build/run 用户人工测试；放行范围限定为 `.file` 内容区 embedded `QLPreviewView`、单文件优先、多文件轻量列表与单预览、各类不可预览 fallback、关闭/切换 cleanup；明确排除文件粘贴、Finder 操作、文件写入/复制/移动/删除、security-scoped bookmark、Storage/ClipboardMonitor/PasteExecutor、FTS/拼音/SQLite 路径索引、收藏/管理/多选/批量/JSON migration runtime；剩余风险为真实运行态 Quick Look 视觉验收未完成。
```

## 165. Stage 9 Quick Look 文件预览 spike 第一批主控 build/run 记录

```text
调度 ID：V2-DOCS-S9-QUICKLOOK-SPIKE-BUILDRUN-1018-RC-ALIGN-001
时间：2026-05-15
阶段：Stage 9 Quick Look / 文件预览 spike 第一批 Acceptance PASS 后 build/run
任务卡 ID：V2-DOCS-S9-QUICKLOOK-SPIKE-BUILDRUN-1018-RC-ALIGN-001
当前会话模式：ClipEase V2 Docs/Log Agent 模式
主控 Agent：Codex 主控 Agent

背景：
- Stage 9 Quick Look / 文件预览 spike 第一批 Acceptance PASS。
- 主控执行 `scripts/build-app.sh`。
- 构建脚本自动从 `1.0.17 (260515.0106)` 提升到 `1.0.18 (260515.0130)`。

build/run 结果：
- 构建产物：`/Users/wpc/code/codex/ClipboardHistory/.build/ClipEase.app`
- 当前运行版本：`1.0.18 (260515.0130)`
- 当前运行 PID：`67250`
- 包含 Stage 9 Quick Look / 文件预览 spike 第一批。

本包包含：
- `.file` 预览内容区 embedded `QLPreviewView`。
- 单文件优先预览。
- 多文件轻量列表，且只预览一个主文件。
- 不可预览、缺失、权限、placeholder、目录等 fallback。
- 关闭 / 切换 cleanup，将 `previewItem = nil`。

明确不包含：
- 文件 pasteboard 粘贴执行。
- Finder 操作。
- 文件写入 / 复制 / 移动 / 删除。
- security-scoped bookmark。
- Storage / ClipboardMonitor / PasteExecutor 改动。
- FTS / 拼音 / SQLite 路径索引。
- 收藏 / 管理 / 多选 / 批量 / JSON migration runtime。

后续人工验收：
- 后续由用户做真实运行态 Quick Look 视觉验收。
- 人工验收重点包括单文件预览、多文件列表与单预览选择、不可预览 fallback、路径缺失 fallback、权限不足 fallback、placeholder fallback、目录 fallback，以及关闭 / 切换后的资源释放表现。
- 人工验收不扩大到文件粘贴、Finder 操作、文件操作、bookmark、Storage / ClipboardMonitor / PasteExecutor、路径索引或收藏 / 管理 / 多选 / 批量 / JSON migration runtime。

文档更新：
- 已更新 `docs/RELEASE_CANDIDATE_REPORT.md` 当前 RC 包信息到 `1.0.18` / `260515.0130`。
- 已追加 `1.0.18(260515.0130)` build/run 记录。
- 已追加本 runbook build/run 记录。
- `.build/ClipEase.app` 已由主控 build/run 启动，PID `67250`。
- 仅修改文档，未修改业务代码，未运行构建，未回退任何改动。

交付摘要：Docs/Log Agent 已记录 Stage 9 Quick Look / 文件预览 spike 第一批 Acceptance PASS 后主控 build/run；确认构建脚本自动从 `1.0.17 (260515.0106)` 提升到 `1.0.18 (260515.0130)`，产物 `/Users/wpc/code/codex/ClipboardHistory/.build/ClipEase.app` 已启动，PID `67250`；当前包包含 `.file` 预览内容区 embedded `QLPreviewView`、单文件优先、多文件轻量列表且只预览一个、fallback、关闭 / 切换 cleanup `previewItem = nil`；明确不包含文件 pasteboard 粘贴执行、Finder 操作、文件写入 / 复制 / 移动 / 删除、security-scoped bookmark、Storage / ClipboardMonitor / PasteExecutor 改动、FTS / 拼音 / SQLite 路径索引、收藏 / 管理 / 多选 / 批量 / JSON migration runtime；后续由用户做真实运行态 Quick Look 视觉验收；仅更新文档，未修改业务代码，未运行构建。
```

## 166. Stage 9 Quick Look / 卡片 / 窗口体验 bugfix 批量调度记录

```text
调度 ID：V2-BUGFIX-S9-QUICKLOOK-CARD-WINDOW-BATCH-001
时间：2026-05-15 02:04:06 CST
阶段：Stage 9 Quick Look / 文件卡片 / 主窗口体验 bugfix 批量调度
任务卡 ID：V2-DOCS-S9-QUICKLOOK-CARD-WINDOW-BUGFIX-DISPATCH-001
当前会话模式：ClipEase V2 Docs/Log Agent 模式
主控 Agent：Codex 主控 Agent
被调用 Agent：
- Quick Look Worker
- Card UI Worker
- Window Interaction / Toast Worker
风险等级：中高；涉及 Quick Look 交互、主窗口卡片布局、滚动 / 选中行为和全局短提示窗口层级

背景：
- 用户反馈 9 个问题，含义已确认。
- 范围包括单文件卡片、多文件卡片、搜索外点清空、Quick Look 内容区交互 / 复制、主窗口横向滚动、新卡片默认选中与前置露出、全局短提示独立系统置顶窗口。
- 主控准备拆分三线调度，三线完成后统一 Test / Review / Acceptance，主控 build/run。

问题范围：
1. Quick Look 右侧多文件列表无法切换，内容区域无法点击 / 选中 / 复制。
2. Quick Look 内容区域底部灰色背景的文件名 / 路径重复，应删除；底部已有路径和文件名。
3. Quick Look 列表选中态要明显；文件名 / 路径超出范围用 `...` 截断。
4. 主窗口多文件卡片内容区只显示居中的堆叠多文件图标，底部删除路径。
5. 主窗口单文件卡片内容区只显示居中的单文件图标，底部路径最多 2 行，超出 `...` 截断。
6. 搜索框展开时，点击筛选分组 / 搜索框内容 / 筛选框内容不关闭搜索；只有点击外部区域如卡片、分组、标题关闭并清空。
7. 主窗口卡片无法鼠标滚轮横向滚动。
8. 新剪切板卡片加入后默认选中新卡片；无前置最左且保留 padding，有前置露出上一张约 1/6。
9. 全局短提示层改为独立全局窗口，位于 ClipEase 主窗口上方；即使切到其他 App 或主窗口未打开，也短暂系统置顶显示。

文件锁：
- Quick Look Worker：`Sources/ClipEase/Features/HistoryWindow/HistoryPreviewPopoverView.swift`、`Sources/ClipEase/Features/HistoryWindow/HistoryFileQuickLookPreviewView.swift`、必要验证脚本。
- Card UI Worker：`Sources/ClipEase/Features/HistoryWindow/HistoryCardView.swift`、`Sources/ClipEase/Features/HistoryWindow/HistoryPreviewItem.swift`、必要验证脚本。
- Window Interaction / Toast Worker：`Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift`、`Sources/ClipEase/Features/HistoryWindow/HistoryWindowController.swift`、必要新增 toast controller 文件、必要验证脚本。

Worker 分工：
- Quick Look Worker 负责问题 1、2、3：多文件列表切换、内容区可点击 / 可选中 / 可复制、删除重复底部灰底路径、增强列表选中态和路径截断。
- Card UI Worker 负责问题 4、5：主窗口文件卡片视觉收敛，多文件只显示堆叠图标，单文件只显示单文件图标，底部路径最多 2 行并截断。
- Window Interaction / Toast Worker 负责问题 6、7、8、9：搜索外点清空边界、鼠标滚轮横向滚动、新卡片默认选中和前置露出、全局短提示独立系统置顶窗口。

红线：
- 不能删除原有功能。
- 不实现文件 pasteboard 粘贴。
- 不实现 Finder 操作。
- 不执行原文件写入 / 复制 / 移动 / 删除。
- 不新增 security-scoped bookmark。
- 不修改 Storage schema / model / repository。
- 不恢复收藏 / 管理 / 多选 / 批量 / JSON migration runtime。
- 如必须触碰红线或扩大文件锁才能推进，Worker 必须先回报主控，不得自行扩大范围。

门禁：
- 三线完成后统一进入 Test / Review / Acceptance。
- 主控负责 build/run。
- 本调度记录仅追加文档；Docs/Log Agent 不修改业务代码，不运行构建。

当前状态：
- 已完成 bugfix 批量调度记录。
- 等待 Quick Look Worker、Card UI Worker、Window Interaction / Toast Worker 按文件锁和红线实现。

交付摘要：Docs/Log Agent 已追加 `V2-BUGFIX-S9-QUICKLOOK-CARD-WINDOW-BATCH-001` 调度记录；记录 9 项用户反馈问题范围，拆分 Quick Look、Card UI、Window Interaction / Toast 三线文件锁和职责；明确红线为不删除原有功能、不实现文件 pasteboard 粘贴 / Finder 操作 / 原文件写入复制移动删除 / security-scoped bookmark、不修改 Storage schema/model/repository、不恢复收藏 / 管理 / 多选 / 批量 / JSON migration runtime；三线完成后统一 Test / Review / Acceptance，主控 build/run；本轮仅修改文档，未修改业务代码，未运行构建。
```

## 167. Stage 9 Quick Look / 卡片 / 窗口体验批量测试记录

```text
测试 ID：V2-TEST-S9-QUICKLOOK-CARD-WINDOW-BATCH-001
时间：2026-05-15 02:20:51 CST
阶段：Stage 9 Quick Look / 文件卡片 / HistoryWindow / 全局 toast 批量验证
当前会话模式：ClipEase V2 Test Agent 模式
测试范围：独立验证 Quick Look 交互、主窗口文件卡片展示、HistoryWindow 交互 / 全局 toast，以及指定回归门禁
结论：PASS

命令结果：
- `swift build`：PASS，退出码 0，Build complete。
- `python3 scripts/smoke_check.py`：PASS，退出码 0；版本 `1.0.18(260515.0130)` valid；Release candidate report matches current version；App bundle structure is valid；Smoke check passed。
- `python3 scripts/verify_stage9_quicklook_interaction.py`：PASS，退出码 0；Stage 9 Quick Look interaction checks passed。
- `python3 scripts/verify_stage9_quicklook_spike.py`：PASS，退出码 0；Stage 9 Quick Look spike checks passed。
- `python3 scripts/verify_stage9_file_card_display.py`：PASS，退出码 0；Stage 9 file card display checks passed。
- `python3 scripts/verify_stage9_file_card_ui.py`：PASS，退出码 0；Stage 9 file card UI checks passed。
- `python3 scripts/verify_history_window_interaction_toast.py`：PASS，退出码 0；history window interaction toast static checks。
- `python3 scripts/verify_history_card_scroll_alignment.py`：PASS，退出码 0；history card scroll alignment static checks；脚本提示共享 worktree 存在 non-owned dirty files，但不作为失败。
- `python3 scripts/verify_stage9_file_capture_first_batch.py`：PASS，退出码 0；Stage 9 file capture first batch checks passed。
- `python3 scripts/verify_stage8_window_experience.py`：PASS，退出码 0；stage 8 window experience static checks。
- `python3 scripts/verify_no_management_no_favorite_ui.py`：PASS，退出码 0；single delete / pin / move group picker / duplicate guard / no management or removed saved-item UI tokens checks passed。
- `git diff --check`：PASS，退出码 0，无 whitespace error 输出。

9 个用户反馈点覆盖判断：
1. Quick Look 多文件右侧列表可切换、内容区可点击 / 选择 / 复制：由 Quick Look interaction / spike 静态检查覆盖，构建通过。
2. Quick Look 删除重复 caption / 底部灰底路径：由 Quick Look interaction 静态检查覆盖。
3. Quick Look 列表选中态明显、文件名 / 路径截断：由 Quick Look interaction 静态检查覆盖。
4. 主窗口多文件卡片只显示堆叠图标、删除内容区路径：由 file card display / UI 静态检查覆盖。
5. 主窗口单文件卡片只显示单图标、footer 最多 2 行并截断：由 file card display / UI 静态检查覆盖。
6. 搜索内部点击不关闭，外点关闭并清空：由 history window interaction toast 静态检查覆盖，并由 Stage 8 window experience 回归覆盖。
7. 主窗口卡片横向滚轮：由 history card scroll alignment 静态检查覆盖。
8. latest card selection 保持、前置露出 / padding：由 history card scroll alignment 静态检查覆盖。
9. 全局短提示独立窗口、主窗口上方 / App 切换场景短暂显示：由 history window interaction toast 静态检查覆盖，仍需真实运行态窗口层级人工验收。

原有功能 / 红线回归：
- Quick Look embedded 保留；未使用 `QLPreviewPanel` 的风险由 Quick Look spike / interaction 检查覆盖。
- 文件捕获 / 文件卡片 UI 保留；由 file capture first batch、file card display、file card UI 覆盖。
- 搜索 token / filter 保留；由 history window interaction toast 与 Stage 8 window experience 覆盖。
- 横向组 / 搜索滚轮不污染 card coordinator；由 history card scroll alignment 覆盖。
- `showStatus` 语义保留；由 history window interaction toast 覆盖。
- 不越界到 PasteExecutor 文件粘贴、Finder 操作、Storage schema/model/repository、bookmark、收藏 / 管理 / 多选 / 批量 / JSON migration runtime：本 Test Agent 未修改业务代码；no-management/no-favorite 回归通过；但共享 worktree 已存在多处非本轮业务改动，测试仅基于当前静态脚本和构建信号判断。

RC / smoke 判断：
- smoke 未出现 RC 版本 HOLD；当前版本 `1.0.18(260515.0130)` valid，RC report matches current version。

风险：
- 本轮为构建 + 静态脚本验证，未执行真实 UI 操作和视觉验收；Quick Look 内容区选择 / 复制、多文件切换体验、card footer 实际截断、横向滚轮手感、latest card 可视露出、全局 toast 系统置顶层级仍建议人工运行态确认。
- `verify_history_card_scroll_alignment.py` 明确提示共享 worktree 存在 non-owned dirty files；本测试未归因这些既有改动，也未回退。
- 仅追加本 runbook 测试记录，未修改业务代码。

交付摘要：Test Agent 已按 `V2-TEST-S9-QUICKLOOK-CARD-WINDOW-BATCH-001` 独立执行指定 12 项命令，全部退出码 0；9 个用户反馈点均被构建 / 静态脚本覆盖；smoke 未 HOLD；剩余风险集中在真实运行态 UI / 视觉 / 窗口层级人工验收和共享 worktree 既有脏改动归因。
```

## 168. Stage 9 Quick Look / 卡片 / 窗口体验批量验收记录

```text
验收 ID：V2-ACCEPT-S9-QUICKLOOK-CARD-WINDOW-BATCH-001
时间：2026-05-15 02:40:32 CST
阶段：Stage 9 Quick Look / 文件卡片 / HistoryWindow / 全局 toast 批量验收
当前会话模式：ClipEase V2 Acceptance Agent 模式
验收范围：基于三线修复完成、Test PASS、Review rerun PASS、Architecture / Scope Gatekeeper 对共享脏树归属 PASS 的记录，判断是否放行进入主控 build/run 用户人工测试
结论：PASS

放行判断：
- 放行进入主控 build/run 用户人工测试。
- 本次验收不代表真实运行态 UI 已完成最终确认；它表示当前构建、静态验证、Review rerun 与 Scope Gatekeeper 信号足以进入人工运行态验收。

放行范围：
- Quick Look 右侧多文件切换、选中态、截断、内容区点击 / 选择复制、删除重复 caption / footer。
- 主窗口单 / 多文件卡片图标展示与 footer 规则。
- 搜索框内部 / 筛选面板点击不关闭，外部点击关闭并清空。
- 主窗口卡片横向滚轮修复，latest card selection / peek 保持。
- 全局短提示独立 NSPanel，主窗口未打开 / 切到其他 App 也短暂置顶。

明确不包含：
- 文件 pasteboard 粘贴执行。
- Finder 操作。
- 原文件写入 / 复制 / 移动 / 删除。
- security-scoped bookmark。
- Storage schema / model / repository 新改动。
- 收藏 / 管理 / 多选 / 批量 / JSON migration runtime。

证据：
- Test 记录 `V2-TEST-S9-QUICKLOOK-CARD-WINDOW-BATCH-001`：`swift build`、smoke、Quick Look、file card、HistoryWindow / toast、scroll alignment、Stage 8 / Stage 9 回归、no-management/no-favorite、`git diff --check` 均 PASS。
- Review 首轮 HOLD 后，toast / footer 小修完成，Review rerun PASS。
- Architecture / Scope Gatekeeper 对共享脏树归属 PASS。
- Acceptance Agent 本轮仅追加本验收记录；未修改业务代码，未运行构建。

剩余风险：
- 尚未做真实运行态人工 UI 验收。
- Quick Look 实际多文件切换、内容区点击 / 选择 / 复制体验仍需人工确认。
- 主窗口横向滚轮手感、latest card selection / peek 可视露出仍需人工确认。
- 多屏环境下全局 toast 位置、层级、短暂置顶行为仍需人工确认。

下一步建议：
- 主控执行 build/run，进入用户人工 UI 测试。
- 人工测试优先覆盖 Quick Look 实际交互、主窗口横向滚轮手感、latest card selection / peek、多屏 toast 位置与切 App 置顶行为。
- 若人工测试发现问题，按对应三线归属回派；不得扩大到本记录明确不包含的红线范围。

交付摘要：Acceptance Agent 对 `V2-ACCEPT-S9-QUICKLOOK-CARD-WINDOW-BATCH-001` 给出 PASS；放行进入主控 build/run 用户人工测试；放行范围限定在 Quick Look 交互、文件卡片展示、HistoryWindow 搜索 / 滚轮 / latest selection、全局 toast；明确排除文件粘贴执行、Finder 操作、原文件操作、bookmark、Storage schema/model/repository、新增收藏 / 管理 / 多选 / 批量 / JSON migration runtime；剩余风险为未做真实运行态人工 UI 验收，尤其 Quick Look 实际交互、横向滚轮手感、多屏 toast 位置。
```

## 169. Stage 9 Quick Look / 卡片 / 窗口体验批量主控 build/run 记录

```text
记录 ID：V2-DOCS-S9-QUICKLOOK-CARD-WINDOW-BUILDRUN-1019-RC-ALIGN-001
时间：2026-05-15 02:41 CST
阶段：Stage 9 Quick Look / 文件卡片 / HistoryWindow / 全局 toast 批量 Acceptance PASS 后 build/run
当前会话模式：ClipEase V2 Docs/Log Agent 模式
任务卡 ID：V2-DOCS-S9-QUICKLOOK-CARD-WINDOW-BUILDRUN-1019-RC-ALIGN-001
结论：记录完成；仅更新文档，未修改业务代码，未运行构建。

背景：
- `V2-BUGFIX-S9-QUICKLOOK-CARD-WINDOW-BATCH-001` Acceptance PASS。
- 主控执行 `scripts/build-app.sh`。
- 构建脚本自动从 `1.0.18 (260515.0130)` 提升到 `1.0.19 (260515.0241)`。
- 产物 `/Users/wpc/code/codex/ClipboardHistory/.build/ClipEase.app` 已启动。
- 当前运行版本：`1.0.19 (260515.0241)`
- 当前运行进程：PID `52168`

本包包含：
- 用户 9 项反馈修复。
- Quick Look 右侧切换 / 选中 / 截断 / 可交互 / 无重复 caption。
- 主窗口单 / 多文件卡片展示。
- 搜索内部点击不关闭，外部点击清空。
- 卡片横向滚轮。
- latest card selection / peek。
- 全局独立 toast window。

明确不包含：
- 文件 pasteboard 粘贴执行。
- Finder 操作。
- 原文件写入 / 复制 / 移动 / 删除。
- security-scoped bookmark。
- Storage / ClipboardMonitor / PasteExecutor 新改动。
- 收藏 / 管理 / 多选 / 批量 / JSON migration runtime。

后续动作：
- 后续由用户做运行态人工验收。
- 人工验收优先覆盖 Quick Look 真实交互、主窗口单 / 多文件卡片视觉、搜索内外点击行为、横向滚轮手感、latest card selection / peek、全局 toast 独立窗口层级。
- 若人工验收发现问题，按 Quick Look / Card UI / Window Interaction / Toast 对应归属回派，不扩大到本记录明确不包含的红线范围。

文档更新：
- 已更新 `docs/RELEASE_CANDIDATE_REPORT.md` 当前 RC 包信息到 `1.0.19` / `260515.0241`。
- 已追加 `1.0.19(260515.0241)` build/run 记录。
- 已追加本 runbook build/run 记录。

验证：
- `git diff --check -- docs/RELEASE_CANDIDATE_REPORT.md docs/V2_AGENT_RUNBOOK.md`：待执行。

交付摘要：Docs/Log Agent 已记录 `V2-BUGFIX-S9-QUICKLOOK-CARD-WINDOW-BATCH-001` Acceptance PASS 后主控 build/run；确认构建脚本自动从 `1.0.18 (260515.0130)` 提升到 `1.0.19 (260515.0241)`，产物 `/Users/wpc/code/codex/ClipboardHistory/.build/ClipEase.app` 已启动，PID `52168`；当前包包含用户 9 项反馈修复：Quick Look 右侧切换 / 选中 / 截断 / 可交互 / 无重复 caption、主窗口单 / 多文件卡片展示、搜索内部点击不关闭且外部点击清空、卡片横向滚轮、latest card selection / peek、全局独立 toast window；明确不包含文件 pasteboard 粘贴执行、Finder 操作、原文件写入 / 复制 / 移动 / 删除、security-scoped bookmark、Storage / ClipboardMonitor / PasteExecutor 新改动、收藏 / 管理 / 多选 / 批量 / JSON migration runtime；后续由用户做运行态人工验收；仅更新文档，未修改业务代码，未运行构建。
```

## 170. Stage 9 文件引用 pasteboard 第一批调度记录

```text
调度 ID：V2-S9-FILE-PASTEBOARD-FIRST-BATCH-001
时间：2026-05-15 02:45 CST
阶段：Stage 9 文件卡片 / 文件引用 pasteboard 第一批调度
当前会话模式：ClipEase V2 Docs/Log Agent 模式
任务卡 ID：V2-DOCS-S9-FILE-PASTEBOARD-FIRST-BATCH-DISPATCH-001
风险等级：中高；涉及系统 NSPasteboard 写入与 ClipboardMonitor 自回录风险
结论：调度记录完成；仅更新文档，未修改业务代码，未运行构建。

当前阶段：
- Stage 9 active。
- 前序 Quick Look / 卡片 / Window 批量已 Acceptance PASS。
- 前序批量已由主控 build/run 到 `1.0.19 (260515.0241)`。

本批目标：
- 文件卡片执行复制 / 粘贴时，向 `NSPasteboard` 写入文件 URL 引用，而不是仅复制路径字符串。
- `copy plain text` 仍保留路径文本能力。
- 粘贴执行只改变 pasteboard 表达，不删除 / 移动 / 复制 / 写入原文件。

文件锁：
- `Sources/ClipEase/Features/PasteExecutor/PasteExecutor.swift`
- `Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift`（仅状态文案）
- 如为避免 ClipEase 自己复制文件引用后被 `ClipboardMonitor` 回录为新卡片，可窄幅修改：
  - `Sources/ClipEase/Core/Storage/ClipboardHistoryStore.swift`
  - `Sources/ClipEase/Features/ClipboardMonitor/ClipboardMonitor.swift`
- 上述 Storage / Monitor 窄幅修改仅限 skip / self-copy guard，不允许 schema / model / repository 改动。
- 可新增 `scripts/verify_stage9_file_pasteboard_first_batch.py`。
- 可更新 `scripts/verify_stage9_file_capture_first_batch.py` 与 `scripts/verify_stage9_file_card_ui.py` 中已过期的“禁止 pasteboard execution”断言。

红线：
- 不得删除 / 移动 / 复制 / 写入原文件。
- 不得新增 security-scoped bookmark。
- 不得新增 Finder 操作 / 打开文件 / 拖拽 provider。
- 不得改 schema / repository / model。
- 不得新增 FTS / 拼音 / SQLite 文件路径索引。
- 不得恢复收藏、管理模式、多选、批量、JSON runtime / migration。

主控调度：
- 主控正在推进 `V2-S9-FILE-PASTEBOARD-FIRST-BATCH-001`。
- 实现范围限定在文件引用 pasteboard 写入、状态文案和必要 self-copy guard。
- 任何超出文件锁或红线的需求必须先回报主控，不得自行扩大范围。

门禁：
- 实现后必须调度 Test Agent。
- Test PASS 后必须调度 Review Agent。
- Review PASS 后必须调度 Acceptance Agent。
- Acceptance PASS 后由主控执行 build/run。

交付摘要：Docs/Log Agent 已追加 `V2-S9-FILE-PASTEBOARD-FIRST-BATCH-001` 调度记录；当前 Stage 9 active，前序 Quick Look / 卡片 / Window 批量已 Acceptance PASS 并 build/run 到 `1.0.19 (260515.0241)`；本批目标为文件卡片复制 / 粘贴向 `NSPasteboard` 写入文件 URL 引用，`copy plain text` 保留路径文本；文件锁限定为 `PasteExecutor.swift`、`HistoryWindowView.swift` 状态文案、必要时 `ClipboardHistoryStore.swift` / `ClipboardMonitor.swift` 的窄幅 skip / self-copy guard，以及相关验证脚本；红线明确禁止原文件删除 / 移动 / 复制 / 写入、security-scoped bookmark、Finder 操作 / 打开文件 / 拖拽 provider、schema / repository / model、FTS / 拼音 / SQLite 文件路径索引、收藏 / 管理 / 多选 / 批量 / JSON runtime / migration；风险等级中高；后续必须 Test / Review / Acceptance 放行，再由主控 build/run；本轮仅修改文档，未修改业务代码，未运行构建。
```

## 171. Stage 9 文件引用 pasteboard 第一批 Test Agent 记录

```text
任务卡 ID：V2-TEST-S9-FILE-PASTEBOARD-FIRST-BATCH-001
时间：2026-05-15 03:21 CST
阶段：Stage 9 文件卡片 / 文件引用 pasteboard 第一批测试
当前会话模式：ClipEase V2 Test Agent 模式
结论：PASS

验证范围：
- 独立验证当前实现，不修改业务代码。
- 重点覆盖文件卡片普通复制 / 自动粘贴写入 file URL pasteboard 引用，而不是仅路径字符串。
- 覆盖纯文本复制仍保留路径字符串。
- 覆盖 ClipEase 自己复制文件引用不会被 ClipboardMonitor 回录成新文件卡片的 guard 存在且顺序正确。
- 覆盖旧 Stage 9 file capture / file card UI 脚本不再因过期的“禁止 pasteboard execution”断言失败。
- 覆盖红线：不删除 / 移动 / 复制 / 写入原文件；无 security-scoped bookmark；无 Finder 操作 / 拖拽 provider / schema / repository / model / search index / favorite / management / JSON runtime 回归。

命令结果：
- `python3 scripts/verify_stage9_file_pasteboard_first_batch.py`：PASS，输出 `OK Stage 9 file pasteboard first batch checks passed`。
- `python3 scripts/verify_stage9_file_capture_first_batch.py`：PASS，输出 `OK Stage 9 file capture first batch checks passed`。
- `python3 scripts/verify_stage9_file_card_ui.py`：PASS，输出 `OK Stage 9 file card UI checks passed`。
- `python3 scripts/verify_stage9_quicklook_interaction.py`：PASS，输出 `OK Stage 9 Quick Look interaction checks passed`。
- `python3 scripts/verify_stage9_file_card_display.py`：PASS，输出 `OK Stage 9 file card display checks passed`。
- `python3 scripts/verify_history_window_interaction_toast.py`：PASS，输出 `PASS: history window interaction toast static checks`。
- `python3 scripts/verify_no_management_no_favorite_ui.py`：PASS，输出 management / favorite UI 回归检查全部通过。
- `python3 scripts/verify_sqlite_only_baseline.py`：PASS，输出 `OK SQLite-only schema baseline verified` 与 `OK SQLite-only data baseline checks passed`。
- `swift build`：PASS，输出 `Build complete! (0.19s)`。
- `python3 scripts/smoke_check.py`：PASS，输出 `OK: Smoke check passed`，版本为 `1.0.19(260515.0241)`。
- `git diff --check`：PASS，无 whitespace error 输出。

风险残留：
- 本轮为脚本 / 静态验证与本地 debug build，未执行真实系统 pasteboard 的人工运行态复制 / 自动粘贴验收。
- 未对 Finder 或外部应用实际接收 file URL pasteboard 行为做端到端人工验收。
- 工作区存在大量其他 Agent / 用户既有未提交改动，本 Test Agent 未回退、未整理、未评审这些改动。

文档更新：
- 已追加本 Test Agent 记录到 `docs/V2_AGENT_RUNBOOK.md`。

交付摘要：Test Agent 已完成 `V2-TEST-S9-FILE-PASTEBOARD-FIRST-BATCH-001` 指定门禁；所有要求命令均 PASS；确认 file pasteboard 第一批静态覆盖、旧 Stage 9 脚本过期断言更新、Quick Look / file card / toast / no management no favorite / SQLite-only / smoke / build / diff check 均通过；本轮仅追加 runbook 测试记录，未修改业务代码；剩余风险为真实系统 pasteboard 与外部应用接收行为仍需后续人工运行态验收。
```

## 172. Stage 9 文件引用 pasteboard 第一批审查记录

```text
审查 ID：V2-REVIEW-S9-FILE-PASTEBOARD-FIRST-BATCH-001
时间：2026-05-15 03:21 CST
阶段：Stage 9 文件卡片 / 文件引用 pasteboard 第一批审查
当前会话模式：ClipEase V2 Review Agent 模式
任务卡 ID：V2-REVIEW-S9-FILE-PASTEBOARD-FIRST-BATCH-001
风险等级：中高；涉及系统 NSPasteboard 文件引用写入与 ClipboardMonitor self-copy guard
结论：PASS；未发现阻塞或需返工问题。本轮仅追加本审查记录，未修改业务代码。

Findings：
- PASS：未发现本批改动违反任务目标或红线的问题。

审查范围：
- `Sources/ClipEase/Features/PasteExecutor/PasteExecutor.swift`
- `Sources/ClipEase/Features/ClipboardMonitor/ClipboardMonitor.swift`
- `Sources/ClipEase/Core/Storage/ClipboardHistoryStore.swift`
- `Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift`
- `scripts/verify_stage9_file_pasteboard_first_batch.py`
- `scripts/verify_stage9_file_capture_first_batch.py`
- `scripts/verify_stage9_file_card_ui.py`

关键核查结果：
- `PasteExecutor.copyToPasteboard(_:)` 已对 `.file` 单独分支处理，使用 `pasteboard.writeObjects(fileURLs.map { $0 as NSURL })` 写入真实文件 URL 引用，不再把普通复制文件卡片降级为字符串路径。
- `.file` 分支复制前通过 `validLocalFileURLs(for:)` 从 `item.fileReferences` 构造 `URL(fileURLWithPath:)`，标准化后检查 `FileManager.default.fileExists(atPath:)`；目录未被排除，符合“目录允许”；无有效本地路径时返回 `未找到文件`。
- `copyPlainTextToPasteboard(_:)` 仍调用 `pasteboard.setString(pasteboardString(for: item), forType: .string)`；`.file` 的 `pasteboardString(for:)` 仍把 `fileReferences.map { $0.path }` 以换行连接，保留路径字符串能力。
- self-copy guard 范围足够窄：`PasteExecutor` 仅在文件引用写入成功后调用 `store.skipNextClipboardFiles(fileURLs)`；`ClipboardMonitor.poll()` 仅在读取到当前 pasteboard 文件 URL 集合后、`store.addFiles` 前调用 `consumeSkippedClipboardFiles(fileURLs)`；Store 内部只用内存 `Set<String>` 保存标准化路径集合并消费删除，没有持久状态、schema 或备份格式变化。
- 外部 App 文件复制捕获路径保留：Monitor 仍先读取文件 URL，未命中 skip 集合时继续 `store.addFiles(fileURLs, sourceApp: sourceApp)`；skip key 为整组标准化路径集合，只覆盖 ClipEase 刚写入的同一组文件 URL。
- HistoryWindow 状态文案已把文件普通复制、授权不足自动粘贴、自动粘贴成功分别表述为 `已复制文件引用`、`已复制文件引用，需授权后自动粘贴`、`已粘贴文件引用到当前 App`；纯文本复制 / 粘贴文案仍为纯文本。
- 新增 `verify_stage9_file_pasteboard_first_batch.py` 覆盖文件 pasteboard 写入、纯文本路径能力、self-copy guard、禁止 token；旧 `verify_stage9_file_capture_first_batch.py` 和 `verify_stage9_file_card_ui.py` 仍保留 file capture、metadata、无 bookmark、无 Quick Look / 文件索引等关键 redline 检查。

红线检查：
- 未在本批关键路径发现原文件 `copyItem` / `moveItem` / `removeItem` / 写入、Finder 打开 / 显示、Quick Look、drag provider、security-scoped bookmark。
- 未发现本批为文件 pasteboard 引用修改 SQLite schema / Repository / ClipboardItem model / 备份格式 / 搜索索引。
- 未发现本批恢复 favorite / management / multi-select / batch / JSON runtime / migration。
- 共享工作树内已有 Quick Look、图片 Finder 操作、SQLite / Repository / 分组等并行或前序改动；本审查未回退这些改动，结论仅针对本任务卡允许范围与本批文件引用 pasteboard 路径。

已运行验证：
- `python3 scripts/verify_stage9_file_pasteboard_first_batch.py`：PASS，输出 `OK Stage 9 file pasteboard first batch checks passed`。
- `python3 scripts/verify_stage9_file_capture_first_batch.py`：PASS，输出 `OK Stage 9 file capture first batch checks passed`。
- `python3 scripts/verify_stage9_file_card_ui.py`：PASS，输出 `OK Stage 9 file card UI checks passed`。

剩余风险：
- 本轮为静态代码审查与验证脚本检查，未做真实 Finder / 外部 App 文件复制粘贴的运行态人工验证。
- macOS 不同目标 App 对 `NSPasteboard.writeObjects([NSURL])` 的文件引用接收行为可能存在差异，建议 Acceptance / 主控 build 后覆盖 Finder、多文件、目录、缺失路径、外部 App 文件复制捕获不被误跳过等人工路径。
- self-copy guard 为内存一次性集合，若系统 pasteboard 对同一组文件 URL 产生多次 changeCount 或目标 App 重写等价 file URL，仍建议运行态观察是否产生重复文件卡片。

交付摘要：Review Agent 对 `V2-REVIEW-S9-FILE-PASTEBOARD-FIRST-BATCH-001` 给出 PASS；确认 `.file` 普通复制写入 `NSURL` file URL pasteboard 引用，纯文本复制仍写路径字符串，复制前只使用存在本地路径且允许目录，无有效路径失败；ClipboardMonitor / Store self-copy guard 为内存一次性、按标准化文件路径集合消费，不引入持久状态或 schema 变化；HistoryWindow 文件状态文案为“文件引用”；验证脚本已更新并保留关键红线；剩余风险为尚未做真实运行态外部 App / Finder 文件引用粘贴与捕获人工验证。本轮仅追加 `docs/V2_AGENT_RUNBOOK.md` 审查记录，未修改业务代码。
```

## 173. Stage 9 文件引用 pasteboard 第一批验收记录

```text
验收 ID：V2-ACCEPT-S9-FILE-PASTEBOARD-FIRST-BATCH-001
时间：2026-05-15 03:33 CST
阶段：Stage 9 文件卡片 / 文件引用 pasteboard 第一批验收
当前会话模式：ClipEase V2 Acceptance Agent 模式
任务卡 ID：V2-ACCEPT-S9-FILE-PASTEBOARD-FIRST-BATCH-001
风险等级：中高；涉及系统 NSPasteboard 文件引用写入、自动粘贴 pasteboard 表达和 ClipboardMonitor self-copy guard
结论：PASS；允许主控 build/run 给用户做运行态人工测试。本轮仅追加本验收记录，未修改业务代码。

验收依据：
- 实现任务 `V2-S9-FILE-PASTEBOARD-FIRST-BATCH-001` 已完成。
- Test Agent `V2-TEST-S9-FILE-PASTEBOARD-FIRST-BATCH-001` 已 PASS：专项脚本、旧 Stage 9 回归脚本、Quick Look / file card / toast / no management no favorite / SQLite-only、`swift build`、`smoke_check`、`git diff --check` 全部通过。
- Review Agent `V2-REVIEW-S9-FILE-PASTEBOARD-FIRST-BATCH-001` 已 PASS：Findings PASS，未发现阻塞或需返工问题。
- Acceptance 复核当前代码关键词：`.file` 普通复制使用 `NSPasteboard.writeObjects(fileURLs.map { $0 as NSURL })` 写入 file URL pasteboard 引用；纯文本复制仍走字符串路径；`PasteExecutor` 写入成功后调用 `store.skipNextClipboardFiles(fileURLs)`；`ClipboardMonitor` 在 `store.addFiles` 前调用 `consumeSkippedClipboardFiles(fileURLs)`；状态文案包含“已复制文件引用”“已复制文件引用，需授权后自动粘贴”“已粘贴文件引用到当前 App”。

放行范围：
- 文件卡片普通复制写入 file URL pasteboard 引用。
- 文件卡片自动粘贴前写入 file URL pasteboard 引用。
- 纯文本复制继续保留文件路径文本。
- ClipEase 自写文件引用的 self-copy guard，避免刚写入的同一组文件 URL 被 ClipboardMonitor 回录为新文件卡片。
- 文件复制 / 自动粘贴状态文案调整为“文件引用”。
- 旧 Stage 9 file capture / file card UI 验证脚本的 pasteboard 边界断言更新。

排除范围：
- Finder 操作、打开文件、拖拽 provider。
- Quick Look 新能力。
- 原文件删除 / 移动 / 复制 / 写入。
- security-scoped bookmark。
- schema / repository / model / 备份格式 / 搜索索引改动。
- favorite / management / multi-select / batch / JSON runtime 回归。

红线复核：
- 未以本批文件引用 pasteboard 为目的引入原文件删除、移动、复制、写入。
- 未以本批文件引用 pasteboard 为目的引入 security-scoped bookmark。
- 未以本批文件引用 pasteboard 为目的修改 schema、repository、model、备份格式或搜索索引。
- 未恢复 favorite、management、multi-select、batch、JSON runtime / migration。
- 共享工作树存在其他 Agent / 用户既有未提交改动；本验收不回退、不归并、不裁定无关改动，结论仅针对本任务卡放行范围。

剩余风险：
- 真实 Finder / 外部 App 对 file URL pasteboard 引用的运行态人工验收尚未完成。
- macOS 不同目标 App 对 `NSPasteboard.writeObjects([NSURL])` 的接收行为可能存在差异，需主控 build/run 后覆盖 Finder、多文件、目录、缺失路径、外部 App 文件复制捕获不被误跳过等人工路径。

验收裁定：
- PASS。
- 允许主控 build/run 给用户人工测试。
- 若人工测试发现 Finder / 外部 App 接收、self-copy guard 或自动粘贴运行态问题，应按文件引用 pasteboard 批次回派 Bugfix；不得借机扩大到本记录排除范围。

交付摘要：Acceptance Agent 对 `V2-ACCEPT-S9-FILE-PASTEBOARD-FIRST-BATCH-001` 给出 PASS；放行文件卡片普通复制 / 自动粘贴写入 file URL pasteboard 引用、纯文本复制保留路径、ClipEase 自写文件引用 self-copy guard、状态文案“文件引用”和旧脚本边界更新；明确排除 Finder 操作、打开文件、拖拽 provider、Quick Look 新能力、原文件删除 / 移动 / 复制 / 写入、security-scoped bookmark、schema / repository / model / 备份格式 / 搜索索引、favorite / management / multi-select / batch / JSON runtime 回归；剩余风险为真实 Finder / 外部 App 对文件引用 pasteboard 的运行态人工验收尚未完成；允许主控 build/run 给用户人工测试。本轮仅追加 `docs/V2_AGENT_RUNBOOK.md`，未修改业务代码。
```

## 174. Stage 9 文件引用 pasteboard 第一批主控 build/run 后 RC 对齐记录

```text
调度 ID：V2-DOCS-S9-FILE-PASTEBOARD-BUILDRUN-1020-RC-ALIGN-001
时间：2026-05-15 03:26 CST
阶段：Stage 9 文件卡片 / 文件引用 pasteboard 第一批 Acceptance PASS 后主控 build/run
当前会话模式：ClipEase V2 Docs/Log Agent 模式
任务卡 ID：V2-DOCS-S9-FILE-PASTEBOARD-BUILDRUN-1020-RC-ALIGN-001
风险等级：低；仅同步 RC 文档与 runbook，不修改业务代码
结论：文档对齐完成；本轮仅修改 `docs/RELEASE_CANDIDATE_REPORT.md` 与 `docs/V2_AGENT_RUNBOOK.md`。

前置事实：
- `V2-ACCEPT-S9-FILE-PASTEBOARD-FIRST-BATCH-001` 已 PASS，允许主控 build/run。
- 主控已执行 `scripts/build-app.sh --run`。
- 构建脚本自动从 `1.0.19 (260515.0241)` 提升到 `1.0.20 (260515.0325)`。
- 产物：`/Users/wpc/code/codex/ClipboardHistory/.build/ClipEase.app`。
- 当前进程：PID `1508`。

构建 / 运行信息：
- 当前候选版本：`1.0.20`。
- 当前构建号：`260515.0325`。
- 当前 build/run：`1.0.20 (260515.0325)`。
- 当前运行进程：PID `1508`。

专项检查：
- `python3 scripts/verify_stage9_file_pasteboard_first_batch.py`：PASS。
- `python3 scripts/verify_stage9_file_capture_first_batch.py`：PASS。
- `python3 scripts/smoke_check.py`：当前仅因 `docs/RELEASE_CANDIDATE_REPORT.md` 未同步 `1.0.20(260515.0325)` HOLD；本次文档对齐即处理该 HOLD 原因。

本次 RC 对齐内容：
- `docs/RELEASE_CANDIDATE_REPORT.md` 当前结论、自动检查、RC 包信息和 RC 修复记录已推进到 `1.0.20 (260515.0325)`。
- 已记录本包包含 Stage 9 文件引用 pasteboard 第一批：文件卡片普通复制 / 自动粘贴写入 file URL pasteboard 引用，纯文本复制保留路径字符串，self-copy guard 避免 ClipEase 自写文件引用被 ClipboardMonitor 回录，toast / status 文案使用“文件引用”。
- 已明确本包不包含 Finder 操作、打开文件、拖拽 provider、原文件删除 / 移动 / 复制 / 写入、security-scoped bookmark、schema / repository / model / search index、收藏 / 管理 / 多选 / 批量 / JSON runtime。
- 已记录剩余风险：真实 Finder / 外部 App 文件引用 pasteboard 人工验收待用户测试。

后续建议：
- Test Agent 可在本次 RC 文档对齐后重跑 `python3 scripts/smoke_check.py`。
- 用户侧继续覆盖 Finder、多文件、目录、缺失路径、外部 App 文件复制捕获不被误跳过等运行态人工路径。

交付摘要：Docs/Log Agent 已完成 `V2-DOCS-S9-FILE-PASTEBOARD-BUILDRUN-1020-RC-ALIGN-001`；将主控 build/run 后的 `1.0.20 (260515.0325)`、PID `1508`、专项 PASS、smoke HOLD 原因和 RC 文档对齐动作记录到 `docs/RELEASE_CANDIDATE_REPORT.md` 与 `docs/V2_AGENT_RUNBOOK.md`；本轮未修改业务代码。
```

## 175. Stage 9 文件卡片基础操作第一批调度记录

```text
调度 ID：V2-DOCS-S9-FILE-BASIC-ACTIONS-DISPATCH-001
时间：2026-05-15
阶段：Stage 9 active；文件数据、捕获、卡片 UI、Quick Look、窗口反馈和文件引用 pasteboard 第一批已完成，并 build/run 到 `1.0.20 (260515.0325)`
当前会话模式：ClipEase V2 Docs/Log Agent 模式
任务卡 ID：V2-S9-FILE-BASIC-ACTIONS-FIRST-BATCH-001
主控 Agent：Codex 主控 Agent
被调用 Agent：Stage 9 文件卡片基础操作实现 / 测试 / 审查 / 验收 Agent
风险等级：中；涉及 Finder reveal 但为只读系统定位
结论：主控正在推进 `V2-S9-FILE-BASIC-ACTIONS-FIRST-BATCH-001`；本轮仅追加调度记录，未修改业务代码。

当前阶段：
- Stage 9 active。
- 文件数据、捕获、卡片 UI、Quick Look、窗口反馈和文件引用 pasteboard 第一批已完成。
- 主控已 build/run 到 `1.0.20 (260515.0325)`。

本批目标：
- 补齐文件卡片基础只读操作。
- 右键菜单和预览窗口 action menu 支持“复制路径”“在 Finder 中显示”。
- 多文件复制路径每行一个。
- Finder 显示优先选中有效文件，可用文件为空时给出提示。
- 路径失效只提示，不删除历史，不修改原文件。

文件锁：
- Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift
- Sources/ClipEase/Features/HistoryWindow/HistoryPreviewPopoverView.swift
- 必要时 Sources/ClipEase/Features/HistoryWindow/HistoryPreviewWindowController.swift（只传递已有 action 闭包，不改窗口架构）
- scripts/verify_stage9_file_basic_actions.py（新增）
- 可小范围更新相关 stage9 验证脚本，但不得删除红线检查。

红线：
- 不得删除、移动、复制或写入原文件。
- 不得新增打开文件操作。
- 不得新增拖拽 provider。
- 不得新增 security-scoped bookmark。
- 不得改 schema、repository、model、备份格式或搜索索引。
- 不得恢复收藏、管理模式、多选、批量或 JSON runtime。

门禁：
- 实现后进入 Test / Review / Acceptance。
- Acceptance PASS 后由主控 build/run。

交付摘要：Docs/Log Agent 已记录主控正在推进 `V2-S9-FILE-BASIC-ACTIONS-FIRST-BATCH-001`，明确当前 Stage 9 状态、本批只读基础操作目标、文件锁、红线、风险等级和 Test / Review / Acceptance / build-run 门禁；本轮仅修改 `docs/V2_AGENT_RUNBOOK.md`。
```

## 176. Stage 9 文件卡片基础操作第一批测试记录

```text
任务卡 ID：V2-TEST-S9-FILE-BASIC-ACTIONS-FIRST-BATCH-001
时间：2026-05-15
阶段：Stage 9 文件卡片基础操作第一批测试
当前会话模式：ClipEase V2 Test Agent 模式
风险等级：中；涉及 Finder reveal、剪贴板路径文本和预览窗口 action menu 连接
结论：HOLD。指定命令门禁均 PASS，但独立静态核对发现预览窗口 `.file` action menu 的回调仍未连接到文件路径 / Finder 行为。

命令结果：
- `python3 scripts/verify_stage9_file_basic_actions.py`：PASS，输出 `OK Stage 9 file basic action checks passed`。
- `python3 scripts/verify_stage9_file_pasteboard_first_batch.py`：PASS，输出 `OK Stage 9 file pasteboard first batch checks passed`。
- `python3 scripts/verify_stage9_quicklook_interaction.py`：PASS，输出 `OK Stage 9 Quick Look interaction checks passed`。
- `python3 scripts/verify_stage9_file_card_display.py`：PASS，输出 `OK Stage 9 file card display checks passed`。
- `python3 scripts/verify_stage9_file_card_ui.py`：PASS，输出 `OK Stage 9 file card UI checks passed`。
- `python3 scripts/verify_history_window_interaction_toast.py`：PASS，输出 `PASS: history window interaction toast static checks`。
- `python3 scripts/verify_no_management_no_favorite_ui.py`：PASS，输出 no management mode / removed saved-item UI tokens checks passed。
- `python3 scripts/verify_sqlite_only_baseline.py`：PASS，输出 `OK SQLite-only schema baseline verified` 与 `OK SQLite-only data baseline checks passed`。
- `swift build`：PASS，输出 `Build complete! (0.19s)`。
- `python3 scripts/smoke_check.py`：PASS，输出 `OK: Smoke check passed`；当前版本 `1.0.20(260515.0325)` 与 RC report 对齐。
- `git diff --check`：PASS，无输出。

已验证通过项：
- 文件卡片右键菜单 `.file` 包含“复制路径”和“在 Finder 中显示”，分别调用 `copyFilePaths(item.id)` 与 `revealFilesInFinder(item.id)`。
- `copyFilePaths` 从 `item.fileReferences.map(\.path)` 生成路径文本，多文件使用 `joined(separator: "\n")`，写入 `.string` 后调用 `store.skipNextClipboardText(pathsText)`，降低路径文本被回录风险。
- `revealFilesInFinder` 通过 `existingFileURLs(for:)` 过滤存在路径，路径无效只 `showStatus("未找到文件")`；有效路径只调用 `NSWorkspace.shared.activateFileViewerSelecting(urls)`，未发现删除 / 移动 / 复制 / 写入原文件。
- 文件引用 pasteboard 第一批仍保持：普通复制 `.file` 使用 `NSPasteboard.writeObjects(fileURLs.map { $0 as NSURL })` 写入文件引用；纯文本复制仍保留路径字符串并调用 `skipNextClipboardText`；ClipboardMonitor 在 `addFiles` 前消费 `skipNextClipboardFiles`。
- 本轮未修改业务代码；未新增打开文件操作、拖拽 provider、bookmark/schema/repository/model/search index；no-management/no-favorite 和 SQLite-only baseline 脚本均 PASS。

HOLD 原因：
- `HistoryPreviewPopoverView.actionMenu` 的 `.file` 分支确实显示 `Button("在 Finder 中显示", action: onReveal)` 与 `Button("复制路径", action: onCopyPath)`。
- 但 `HistoryWindowController.showPreview` 给预览窗口注入的 `onReveal` 仍调用 `revealPreviewItem(item)`，该函数只从 `imageURL(for:)` 取图片 URL；`imageURL(for:)` 要求 `item.type == .image`，所以 `.file` reveal 会直接 return，未连接到文件 Finder reveal。
- 同处 `onCopyPath` 仍调用 `copyPlainPreviewText(self?.imagePath(for: item))`；`imagePath(for:)` 仅返回图片路径，`.file` 会得到 nil，因此预览窗口 `.file` “复制路径”不会复制文件路径，也不会触发 `skipNextClipboardText`。
- 现有 `verify_stage9_file_basic_actions.py` 只校验 popover 菜单标签 / 闭包名，未校验 controller 注入闭包对 `.file` 的真实行为，存在脚本覆盖缺口。

风险残留：
- 主窗口右键文件基础操作静态核对通过，但预览窗口 `.file` action menu 实际行为不达任务卡要求，需实现 Agent 修复后重跑本记录中的全量门禁。
- 本轮未做真实 Finder / 系统剪贴板 / 外部 App 运行态人工测试；即使修复静态问题后，仍建议主控 build/run 后覆盖单文件、多文件、目录、缺失路径和外部 App 文件复制捕获不被误跳过。
- 共享 worktree 已存在大量非本轮改动与未跟踪文件；本 Test Agent 未回退、未归因，仅基于当前候选代码和指定门禁判断。

交付摘要：Test Agent 已完成 `V2-TEST-S9-FILE-BASIC-ACTIONS-FIRST-BATCH-001` 指定命令门禁，所有命令均 PASS；但独立源码核对发现预览窗口 `.file` 菜单回调仍接到图片 reveal / 图片路径逻辑，未连接文件路径 / Finder 行为，因此本任务卡测试结论为 HOLD；本轮仅追加 `docs/V2_AGENT_RUNBOOK.md` 测试记录，未修改业务代码。
```

## 176. Stage 9 文件卡片基础操作第一批审查记录

```text
调度 ID：V2-REVIEW-S9-FILE-BASIC-ACTIONS-FIRST-BATCH-001
时间：2026-05-15
阶段：Stage 9 文件卡片基础操作第一批审查
当前会话模式：ClipEase V2 Review Agent 模式
任务卡 ID：V2-REVIEW-S9-FILE-BASIC-ACTIONS-FIRST-BATCH-001
风险等级：中；涉及文件卡片只读 Finder reveal / 路径复制入口
结论：HOLD。主窗口卡片右键菜单与 helper 主路径基本符合要求，但预览窗口 action menu 的闭包传入链仍把 `.file` 的“在 Finder 中显示 / 复制路径”导向图片专用逻辑，导致文件预览窗口内两个操作不可用；验证脚本未覆盖该闭包链。

Findings：
1. [P1] 文件预览窗口 `.file` action menu 调用了 `onReveal` / `onCopyPath`，但 `HistoryWindowController.showPreview` 传入的闭包仍分别调用 `revealPreviewItem(item)` 和 `imagePath(for: item)`；这两条 helper 都只处理 `.image`，对 `.file` 会返回 nil / 直接 return。结果是在文件预览窗口点击“在 Finder 中显示”不会 reveal 文件，点击“复制路径”不会写入文件路径，也不会调用 `store.skipNextClipboardText(paths)`。涉及位置：`Sources/ClipEase/Features/HistoryWindow/HistoryPreviewPopoverView.swift:99`、`Sources/ClipEase/Features/HistoryWindow/HistoryWindowController.swift:282`、`Sources/ClipEase/Features/HistoryWindow/HistoryWindowController.swift:291`、`Sources/ClipEase/Features/HistoryWindow/HistoryWindowController.swift:321`、`Sources/ClipEase/Features/HistoryWindow/HistoryWindowController.swift:351`。
2. [P2] `scripts/verify_stage9_file_basic_actions.py` 当前会 PASS，但只验证 popover `.file` 分支按钮绑定 `onReveal` / `onCopyPath`，没有追踪 `HistoryWindowController` / `HistoryPreviewWindowController` 传入闭包是否针对 `.file` 分派到文件专用操作。因此脚本未覆盖本任务重点要求“不能只看 popover 局部”。涉及位置：`scripts/verify_stage9_file_basic_actions.py:123` 到 `scripts/verify_stage9_file_basic_actions.py:161`。

已复核通过的部分：
- 主窗口卡片右键菜单的 `.file` 分支新增“复制路径”和“在 Finder 中显示”，并与 text / image / link / color 的 type-specific 分支分离；未在 `.file` 菜单新增打开文件操作。
- `copyFilePaths` 基于 `item.fileReferences` 复制路径文本，多文件用换行拼接，并调用 `store.skipNextClipboardText(pathsText)`。
- `revealFilesInFinder` 通过 `existingFileURLs(for:)` 过滤存在的本地路径，仅对有效 URL 调用 `NSWorkspace.shared.activateFileViewerSelecting(urls)`；没有有效项时只提示“未找到文件”。
- 未发现本批 helper 引入原文件删除 / 移动 / 复制 / 写入、拖拽 provider、security-scoped bookmark、schema / repository / model / 备份格式 / 搜索索引改动。

已执行检查：
- `python3 scripts/verify_stage9_file_basic_actions.py`：PASS，输出 `OK Stage 9 file basic action checks passed`；但如上所述，该 PASS 未覆盖预览闭包传入链。

修复建议：
- 在 `HistoryWindowController.showPreview` 的 `onReveal` / `onCopyPath` 闭包或其下游 helper 中按 `item.type` 分派：`.image` 保持现有图片逻辑；`.file` 使用文件引用专用逻辑。
- 文件预览 reveal 应只选择存在的本地文件 / 目录；无有效项时提示，不修改历史和原文件。
- 文件预览复制路径应复制 `item.fileReferences` 的完整路径，多文件每行一个，并调用 `store.skipNextClipboardText(pathsText)`。
- 扩展 `scripts/verify_stage9_file_basic_actions.py`，覆盖 `HistoryWindowController.showPreview` 传入闭包与 file helper 分派，避免只验证 popover 局部。

交付摘要：Review Agent 对 `V2-REVIEW-S9-FILE-BASIC-ACTIONS-FIRST-BATCH-001` 给出 HOLD；主窗口文件右键菜单、路径复制 helper、Finder reveal helper 主路径基本符合要求，但预览窗口 action menu 的 `.file` 操作闭包链仍指向图片专用 reveal / path copy，且专项脚本漏测该重点路径；本轮仅追加 `docs/V2_AGENT_RUNBOOK.md`，未修改业务代码，未回退任何改动。
```

## 177. Stage 9 文件卡片基础操作第一批 HOLD 返工复测 PASS 记录

```text
任务卡 ID：V2-TEST-S9-FILE-BASIC-ACTIONS-FIRST-BATCH-RERUN-001
时间：2026-05-15
阶段：Stage 9 文件卡片基础操作第一批 HOLD 修复后复测
当前会话模式：ClipEase V2 Test Agent 模式
风险等级：中；涉及 Finder reveal、剪贴板路径文本和预览窗口 action menu 连接
结论：PASS。HOLD 点已解除：预览窗口 `.file` action menu 的 `onReveal` / `onCopyPath` 已按 `item.type` 分派到文件专用 helper，文件路径复制与 Finder reveal 逻辑均已接通，主窗口右键 file 操作仍有效，红线未破。

命令结果：
- `python3 scripts/verify_stage9_file_basic_actions.py`：PASS，输出 `OK Stage 9 file basic action checks passed`。
- `python3 scripts/verify_stage9_file_pasteboard_first_batch.py`：PASS，输出 `OK Stage 9 file pasteboard first batch checks passed`。
- `python3 scripts/verify_stage9_quicklook_interaction.py`：PASS，输出 `OK Stage 9 Quick Look interaction checks passed`。
- `python3 scripts/verify_stage9_file_card_display.py`：PASS，输出 `OK Stage 9 file card display checks passed`。
- `python3 scripts/verify_stage9_file_card_ui.py`：PASS，输出 `OK Stage 9 file card UI checks passed`。
- `python3 scripts/verify_history_window_interaction_toast.py`：PASS，输出 `PASS: history window interaction toast static checks`。
- `python3 scripts/verify_no_management_no_favorite_ui.py`：PASS，输出 no management mode / removed saved-item UI tokens checks passed。
- `python3 scripts/verify_sqlite_only_baseline.py`：PASS，输出 `OK SQLite-only schema baseline verified` 与 `OK SQLite-only data baseline checks passed`。
- `swift build`：PASS，输出 `Build complete! (0.20s)`。
- `python3 scripts/smoke_check.py`：PASS，输出 `OK: Smoke check passed`；当前版本 `1.0.20(260515.0325)` 与 RC report 对齐。
- `git diff --check`：PASS，无输出。

已复核通过项：
- 预览窗口 `.file` action menu 仍显示“在 Finder 中显示 / 复制路径”，但 `HistoryWindowController.showPreview` 注入的 `onReveal` / `onCopyPath` 现在分别进入 `revealPreviewItem(item)` 和 `copyPreviewPath(for: item)`，并在下游按 `item.type` 分派。
- `.file` reveal 只使用 `existingPreviewFileURLs(for:)` 过滤存在路径；无有效项只提示“未找到文件”，有效项只调用 `NSWorkspace.shared.activateFileViewerSelecting(urls)`。
- `.file` copy path 走 `copyPreviewFilePaths(for:)`，单 / 多文件路径按换行拼接，写入 `.string` 后调用 `store.skipNextClipboardText(pathsText)`。
- 主窗口右键 file 操作仍保持 `copyFilePaths(item.id)` 与 `revealFilesInFinder(item.id)`，且 helper 仍只处理文件引用、存在路径和 Finder reveal。
- 文件引用 pasteboard、Quick Look、file card display / UI、toast、no-management / no-favorite、SQLite-only baseline 全部维持 PASS。
- 本轮未修改业务代码；未新增打开文件操作、拖拽 provider、bookmark / schema / repository / model / search index。

交付摘要：Test Agent 已完成 `V2-TEST-S9-FILE-BASIC-ACTIONS-FIRST-BATCH-RERUN-001` 复测，所有命令均 PASS；确认预览窗口 `.file` action menu 的闭包链已按文件类型分派到文件专用 helper，HOLD 已解除，本轮仅追加 `docs/V2_AGENT_RUNBOOK.md` 测试记录，未修改业务代码。
```

## 177. Stage 9 文件卡片基础操作第一批复审记录

```text
调度 ID：V2-REVIEW-S9-FILE-BASIC-ACTIONS-FIRST-BATCH-RERUN-001
时间：2026-05-15
阶段：Stage 9 文件卡片基础操作第一批 HOLD 修复后复审
当前会话模式：ClipEase V2 Review Agent 模式
任务卡 ID：V2-REVIEW-S9-FILE-BASIC-ACTIONS-FIRST-BATCH-RERUN-001
风险等级：中；涉及文件卡片只读 Finder reveal / 路径复制入口
结论：PASS。P1 与 P2 均已修复；预览窗口 `.file` action menu 现在通过 controller 闭包链进入文件专用 reveal / copy-path helper，`verify_stage9_file_basic_actions.py` 也已覆盖 controller 传入闭包链。

Findings：
- 无阻塞问题。

已复核通过的部分：
- `HistoryWindowController.showPreview` 仍注入 `onReveal` / `onCopyPath`，但 `revealPreviewItem(_:)` 与 `copyPreviewPath(for:)` 现在按 `item.type` 分派：`.image` 保持旧图片逻辑，`.file` 分别走 `existingPreviewFileURLs(for:)` 和 `copyPreviewFilePaths(for:)`。
- `HistoryPreviewPopoverView` 的 `.file` action menu 仍绑定 `onReveal` / `onCopyPath`，但已正确落到 controller 的文件专用 helper。
- `scripts/verify_stage9_file_basic_actions.py` 已补上 `verify_controller_preview_file_callbacks`，直接核对 `showPreview`、`revealPreviewItem`、`copyPreviewPath`、`copyPreviewFilePaths` 与 `existingPreviewFileURLs` 的 file 分派链。
- 主窗口 file 右键菜单仍只提供“复制路径”和“在 Finder 中显示”，路径复制仍调用 `store.skipNextClipboardText(pathsText)`，Finder reveal 仍只做本地存在路径的只读定位。
- 未发现本轮引入原文件删除 / 移动 / 复制 / 写入、打开文件、drag provider、bookmark、schema / repository / model / search index / favorite / management / JSON runtime 回归。

已执行检查：
- `python3 scripts/verify_stage9_file_basic_actions.py`：PASS，输出 `OK Stage 9 file basic action checks passed`。

交付摘要：Review Agent 对 `V2-REVIEW-S9-FILE-BASIC-ACTIONS-FIRST-BATCH-RERUN-001` 给出 PASS；P1 与 P2 已确认修复，主窗口和预览窗口的 file 基础操作仍符合只读 Finder 定位与路径复制目标，本轮仅追加 `docs/V2_AGENT_RUNBOOK.md`，未修改业务代码，未回退任何改动。
```

## 178. Stage 9 文件卡片基础操作第一批验收记录

```text
验收 ID：V2-ACCEPT-S9-FILE-BASIC-ACTIONS-FIRST-BATCH-001
时间：2026-05-15
阶段：Stage 9 文件卡片基础操作第一批验收
当前会话模式：ClipEase V2 Acceptance Agent 模式
任务卡 ID：V2-ACCEPT-S9-FILE-BASIC-ACTIONS-FIRST-BATCH-001
风险等级：中；涉及文件卡片只读 Finder reveal / 路径复制入口
结论：PASS。Test / Review / Rerun / Review-Rerun 均已闭环，允许主控 build/run 给用户做运行态测试。

放行范围：
- 文件卡片右键菜单“复制路径”“在 Finder 中显示”。
- 文件预览窗口 `.file` action menu “在 Finder 中显示”“复制路径”，且 controller 闭包正确分派到文件 helper。
- 单文件完整路径复制；多文件路径每行一个；`skipNextClipboardText`。
- Finder reveal 只读定位存在文件 / 目录；无有效项只提示。

排除范围 / 红线：
- 不包含打开文件操作。
- 不包含拖出 / drag provider。
- 不删除 / 移动 / 复制 / 写入原文件。
- 不新增 security-scoped bookmark。
- 不改 schema / repository / model / 备份格式 / search index。
- 不恢复 favorite / management / multi-select / batch / JSON runtime。

已复核依据：
- `V2-TEST-S9-FILE-BASIC-ACTIONS-FIRST-BATCH-RERUN-001` PASS。
- `V2-REVIEW-S9-FILE-BASIC-ACTIONS-FIRST-BATCH-RERUN-001` PASS。
- 主窗口 file 右键菜单与 preview `.file` action menu 均已接通文件专用 helper，且验证脚本补上 controller 分派链覆盖。

交付摘要：Acceptance Agent 对 `V2-ACCEPT-S9-FILE-BASIC-ACTIONS-FIRST-BATCH-001` 给出 PASS；本批仅放行文件卡片基础只读操作与预览窗口 `.file` action menu 的文件分派链，明确允许主控后续 build/run 给用户做运行态测试；本轮仅追加 `docs/V2_AGENT_RUNBOOK.md`，未修改业务代码，未回退任何改动。
```

## 179. Stage 9 文件卡片基础操作第一批主控 build/run 后 RC 对齐记录

```text
调度 ID：V2-DOCS-S9-FILE-BASIC-ACTIONS-BUILDRUN-1021-RC-ALIGN-001
时间：2026-05-15
阶段：Stage 9 文件卡片基础操作第一批 Acceptance PASS 后主控 build/run
任务卡 ID：V2-DOCS-S9-FILE-BASIC-ACTIONS-BUILDRUN-1021-RC-ALIGN-001
主控 Agent：Codex 主控 Agent
被调用 Agent：Docs/Log Agent
风险等级：低；仅同步 RC 文档与 runbook，不修改业务代码

已知前提：
- `V2-ACCEPT-S9-FILE-BASIC-ACTIONS-FIRST-BATCH-001` 已 PASS，允许主控 build/run。
- 主控已执行 `scripts/build-app.sh --run`。
- 构建脚本自动从 `1.0.20 (260515.0325)` 提升到 `1.0.21 (260515.0351)`。
- 产物 `/Users/wpc/code/codex/ClipboardHistory/.build/ClipEase.app`。
- 当前进程 PID `36369`。
- `python3 scripts/verify_stage9_file_basic_actions.py` PASS。
- `python3 scripts/verify_stage9_file_pasteboard_first_batch.py` PASS。
- `python3 scripts/smoke_check.py` 当前仅因 `docs/RELEASE_CANDIDATE_REPORT.md` 未同步 `1.0.21(260515.0351)` HOLD。

本次 RC 对齐内容：
- 已将 `docs/RELEASE_CANDIDATE_REPORT.md` 当前结论、自动检查、RC 包信息和 RC 修复记录推进到 `1.0.21 (260515.0351)`。
- 已记录本包包含 Stage 9 文件卡片基础操作第一批：文件卡片右键菜单“复制路径”“在 Finder 中显示”；预览窗口 `.file` action menu “在 Finder 中显示”“复制路径”；controller 回调按 `.image/.file` 正确分派；单 / 多文件路径复制与 `skipNextClipboardText`；Finder reveal 只读定位存在文件 / 目录。
- 已明确排除打开文件、拖出 / drag provider、原文件删除 / 移动 / 复制 / 写入、security-scoped bookmark、schema / repository / model / search index、收藏 / 管理 / 多选 / 批量 / JSON runtime。
- 已记录剩余风险为真实 Finder 定位、预览窗口菜单、缺失路径等运行态人工验收待用户测试。

后续动作：
- Test Agent 可在本次 RC 文档对齐后重跑 `python3 scripts/smoke_check.py`。
- 用户侧继续覆盖真实 Finder 定位、预览窗口菜单和缺失路径等运行态人工路径。

交付摘要：Docs/Log Agent 已完成 `V2-DOCS-S9-FILE-BASIC-ACTIONS-BUILDRUN-1021-RC-ALIGN-001`；将主控 build/run 后的 `1.0.21 (260515.0351)`、PID `36369`、专项 PASS、smoke HOLD 原因和 RC 文档对齐动作记录到 `docs/RELEASE_CANDIDATE_REPORT.md` 与 `docs/V2_AGENT_RUNBOOK.md`；本轮未修改业务代码。
```

## 180. Stage 9 文件卡片拖出第一批调度记录

```text
调度 ID：V2-DOCS-S9-FILE-DRAGOUT-DISPATCH-001
时间：2026-05-15
阶段：Stage 9 active；文件数据、捕获、卡片 UI、Quick Look、文件引用 pasteboard、文件基础操作均已完成，并 build/run 到 `1.0.21 (260515.0351)`
当前会话模式：ClipEase V2 Docs/Log Agent 模式
任务卡 ID：V2-S9-FILE-DRAGOUT-FIRST-BATCH-001
主控 Agent：Codex 主控 Agent
被调用 Agent：Stage 9 文件卡片拖出实现 / 测试 / 审查 / 验收 Agent
风险等级：中高；涉及 SwiftUI/AppKit drag pasteboard 与 Finder / 外部 App 运行态差异
结论：主控正在推进 `V2-S9-FILE-DRAGOUT-FIRST-BATCH-001`；本轮仅追加调度记录，未修改业务代码。

当前阶段：
- Stage 9 active。
- 文件数据、捕获、卡片 UI、Quick Look、文件引用 pasteboard、文件基础操作均已完成。
- 主控已 build/run 到 `1.0.21 (260515.0351)`。

本批目标：
- 让文件卡片支持拖出到 Finder 或支持 file URL drag pasteboard 的 App。
- 单文件 / 多文件写入现有本地文件 URL。
- 拖出前校验路径存在。
- 部分失效时只拖出有效项，并给出保守反馈或静态可验证路径。
- 全部无效时不启动有效拖出，或只提示，不触发危险写入。

文件锁：
- Sources/ClipEase/Features/HistoryWindow/HistoryCardView.swift
- Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift（只做 drag source 接线和状态提示）
- 必要时 Sources/ClipEase/Features/HistoryWindow/HistoryPreviewItem.swift（只补 drag 所需轻量字段，不改 model/schema）
- scripts/verify_stage9_file_dragout_first_batch.py（新增）
- 可小范围更新 stage9 验证脚本，不得删除红线。

红线：
- 不得删除 / 移动 / 复制 / 写入原文件。
- 不得创建临时副本。
- 不得新增打开文件操作。
- 不得新增 security-scoped bookmark。
- 不得改 schema / repository / model / 备份格式 / search index。
- 不得恢复收藏 / 管理模式 / 多选 / 批量 / JSON runtime。

门禁：
- 实现后进入 Test / Review / Acceptance。
- Acceptance PASS 后主控 build/run。

交付摘要：Docs/Log Agent 已记录主控正在推进 `V2-S9-FILE-DRAGOUT-FIRST-BATCH-001`，明确当前 Stage 9 状态、本批拖出目标、文件锁、红线、风险等级和 Test / Review / Acceptance / build-run 门禁；本轮仅修改 `docs/V2_AGENT_RUNBOOK.md`。
```

## 181. Stage 9 文件卡片拖出第一批测试记录

```text
调度 ID：V2-TEST-S9-FILE-DRAGOUT-FIRST-BATCH-001
时间：2026-05-15
阶段：Stage 9 文件卡片拖出第一批测试
任务卡 ID：V2-TEST-S9-FILE-DRAGOUT-FIRST-BATCH-001
执行 Agent：Codex Test Agent
风险等级：中高；本轮为静态/构建/脚本验证，真实 Finder 或外部 App 拖放仍需人工运行态验收
结论：PASS

验证范围：
- `.file` 卡片拖出第一批静态结构、drag source 接线与非 `.file` 卡片不新增 drag-out。
- Drag pasteboard 使用 file URL / NSURL 引用，不写 `.string` 文本路径，不创建临时副本。
- 单文件 / 多文件拖出使用现有本地文件 URL，并在拖出前执行即时 `fileExists` 校验。
- 部分失效仅拖有效项；全部失效不启动有效拖出并提示。
- 点击、右键、横向滚动、Quick Look 预览、文件卡片显示与基础操作相关静态结构未被破坏。
- 红线复核：无 copyItem / moveItem / removeItem；无原文件写改；无 bookmark；无打开文件；无 schema / repository / model / search index 变更；无 favorite / management / JSON runtime 回归。

命令结果：
- `python3 scripts/verify_stage9_file_dragout_first_batch.py` PASS：OK Stage 9 file drag-out first batch checks passed
- `python3 scripts/verify_stage9_file_basic_actions.py` PASS：OK Stage 9 file basic action checks passed
- `python3 scripts/verify_stage9_file_pasteboard_first_batch.py` PASS：OK Stage 9 file pasteboard first batch checks passed
- `python3 scripts/verify_stage9_quicklook_interaction.py` PASS：OK Stage 9 Quick Look interaction checks passed
- `python3 scripts/verify_stage9_file_card_display.py` PASS：OK Stage 9 file card display checks passed
- `python3 scripts/verify_stage9_file_card_ui.py` PASS：OK Stage 9 file card UI checks passed
- `python3 scripts/verify_history_window_interaction_toast.py` PASS：PASS: history window interaction toast static checks
- `python3 scripts/verify_no_management_no_favorite_ui.py` PASS：no management mode or removed saved-item UI tokens
- `python3 scripts/verify_sqlite_only_baseline.py` PASS：OK SQLite-only schema baseline verified；OK SQLite-only data baseline checks passed
- `swift build` PASS：Build complete
- `python3 scripts/smoke_check.py` PASS：Smoke check passed；版本 `1.0.21(260515.0351)` 与 RC 报告匹配；App bundle 结构有效
- `git diff --check` PASS：无输出

边界说明：
- 本轮未修改业务代码。
- 本轮未启动真实 Finder / 外部 App 拖放运行态测试；该路径仍建议由用户侧在 `.build/ClipEase.app` 或后续 RC 包中人工覆盖。
- 工作区已有其他 Agent 与用户改动，本轮只追加 `docs/V2_AGENT_RUNBOOK.md` 测试记录，未回退任何改动。

交付摘要：Test Agent 已完成 `V2-TEST-S9-FILE-DRAGOUT-FIRST-BATCH-001`；指定专项脚本、SQLite baseline、`swift build`、`smoke_check.py` 与 `git diff --check` 全部 PASS；当前结论 PASS。
```

## 182. Stage 9 文件卡片拖出第一批审查记录

```text
调度 ID：V2-REVIEW-S9-FILE-DRAGOUT-FIRST-BATCH-001
时间：2026-05-15
阶段：Stage 9 文件卡片拖出第一批审查
任务卡 ID：V2-REVIEW-S9-FILE-DRAGOUT-FIRST-BATCH-001
执行 Agent：Codex Review Agent
风险等级：中高；涉及 SwiftUI/AppKit drag source bridge 与 Finder / 外部 App 运行态差异
结论：PASS

Findings：
- 未发现阻断问题。

审查范围：
- `Sources/ClipEase/Features/HistoryWindow/HistoryCardView.swift`
- `Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift`
- `Sources/ClipEase/Features/HistoryWindow/HistoryPreviewItem.swift`
- `Sources/ClipEase/Features/PasteExecutor/PasteExecutor.swift`
- `scripts/verify_stage9_file_dragout_first_batch.py`

人工复核结果：
- `HistoryCardView` 通过 `FileCardDragSourceView` / `FileCardDragSourceNSView` 接入 AppKit drag source bridge；bridge 虽挂在卡片 background，但 drag 激活路径在 `leftMouseDown`、`leftMouseDragged` 和 `validFileDragURLs` 均检查 `.file`，非 `.file` 卡片不会新增有效拖出。
- bridge 的 `hitTest(_:)` 返回 `nil`，事件 local monitor 始终 `return event`；仅监听左键 down / dragged / up，不监听右键和滚轮事件，未发现吞掉普通点击、右键菜单或滚动的实现。
- 拖出 pasteboard writer 使用 `NSDraggingItem(pasteboardWriter: url as NSURL)`；bridge 内未写 `.string`、`setString` 或 `NSItemProvider` 文本路径。
- 拖出前在 `validFileDragURLs` 中对 `URL(fileURLWithPath: reference.path).standardizedFileURL` 执行 `FileManager.default.fileExists(atPath: url.path)` 即时校验；无效引用被 drop。
- 部分失效时 `hasInvalidReferences` 触发 `onPartial?()`，仅用有效 `urls` 启动拖出；全部失效时 `guard !result.urls.isEmpty else` 触发 `onInvalid?()` 并返回，不启动有效 dragging session。
- 未发现本批 drag bridge 引入 `copyItem` / `moveItem` / `removeItem`、原文件删除 / 移动 / 复制 / 写入、临时副本、打开文件、security-scoped bookmark、schema / repository / model / 备份格式 / search index 改动。
- 相邻能力复核未发现文件卡片 UI、Quick Look、基础操作、pasteboard 逻辑被本批拖出改坏；本轮未回退或修改其他 Agent / 用户改动。

验证命令：
- `python3 scripts/verify_stage9_file_dragout_first_batch.py` PASS：OK Stage 9 file drag-out first batch checks passed
- `python3 scripts/verify_stage9_file_basic_actions.py` PASS：OK Stage 9 file basic action checks passed
- `python3 scripts/verify_stage9_file_pasteboard_first_batch.py` PASS：OK Stage 9 file pasteboard first batch checks passed
- `python3 scripts/verify_stage9_quicklook_interaction.py` PASS：OK Stage 9 Quick Look interaction checks passed
- `python3 scripts/verify_no_management_no_favorite_ui.py` PASS：no management mode or removed saved-item UI tokens

验证脚本覆盖评价：
- `scripts/verify_stage9_file_dragout_first_batch.py` 覆盖 bridge 存在、AppKit `NSViewRepresentable` / `NSDraggingSource`、`.file` 限定、即时 `fileExists`、标准化 file URL、NSURL pasteboard writer、禁止 `.string` / SwiftUI drag provider、部分 / 全部失效路径和主要红线 token。
- 脚本配合文件基础操作、文件 pasteboard、Quick Look 交互和 no favorite / management 基线脚本，覆盖本批主要行为与红线。

剩余风险：
- 本轮为静态审查和脚本验证；真实 Finder / 外部 App 拖放接收、拖动中系统视觉和不同输入设备下的运行态表现仍建议在 RC 包中人工验收。

交付摘要：Review Agent 已完成 `V2-REVIEW-S9-FILE-DRAGOUT-FIRST-BATCH-001`；无 Findings，结论 PASS；本轮仅追加 `docs/V2_AGENT_RUNBOOK.md` 审查记录，未修改业务代码。
```

## 183. Stage 9 文件卡片拖出第一批验收记录

```text
验收 ID：V2-ACCEPT-S9-FILE-DRAGOUT-FIRST-BATCH-001
时间：2026-05-15
阶段：Stage 9 文件卡片拖出第一批验收
任务卡 ID：V2-ACCEPT-S9-FILE-DRAGOUT-FIRST-BATCH-001
执行 Agent：Codex Acceptance Agent
风险等级：中高；AppKit drag source bridge 与 Finder / 外部 App file URL drag pasteboard 接收仍需真实运行态人工验证
结论：PASS

验收依据：
- 实现任务 `V2-S9-FILE-DRAGOUT-FIRST-BATCH-001` 已完成。
- Test Agent `V2-TEST-S9-FILE-DRAGOUT-FIRST-BATCH-001` 已 PASS：专项脚本、相邻 Stage 9 回归、SQLite-only baseline、no management / no favorite、`swift build`、`smoke_check.py`、`git diff --check` 均通过。
- Review Agent `V2-REVIEW-S9-FILE-DRAGOUT-FIRST-BATCH-001` 已 PASS：Findings 无阻断，确认 drag source bridge、pasteboard writer、路径即时校验、部分 / 全部失效处理和红线约束均符合本批目标。

放行范围：
- `.file` 历史卡片支持拖出到 Finder / 支持 file URL drag pasteboard 的 App。
- AppKit drag source bridge 只对 `.file` 启用，非 `.file` 卡片不新增有效拖出。
- Drag pasteboard 仅写 `NSURL` file URL 引用，不写 `.string` 路径。
- 拖出前即时校验存在路径；部分失效只拖有效项并给出反馈；全部失效不启动拖出并提示。
- 普通点击、右键、滚动、Quick Look 预览交互不被本批 drag bridge 吞掉或替换。

排除范围 / 红线：
- 不包含创建临时副本。
- 不删除 / 移动 / 复制 / 写入原文件。
- 不包含打开文件操作。
- 不包含 security-scoped bookmark。
- 不改 schema / repository / model / 备份格式 / search index。
- 不恢复 favorite / management / multi-select / batch / JSON runtime。

剩余风险：
- 本批已通过静态脚本、构建、smoke、Test 与 Review 门禁；真实 Finder / 外部 App 拖放接收行为、系统拖动视觉、不同输入设备下的运行态手感仍需主控 build/run 后由用户人工覆盖。

放行裁定：
- PASS。
- 允许主控 build/run 给用户做运行态测试。

交付摘要：Acceptance Agent 对 `V2-ACCEPT-S9-FILE-DRAGOUT-FIRST-BATCH-001` 给出 PASS；放行 `.file` 历史卡片拖出到 Finder / 支持 file URL drag pasteboard 的 App，限定为现有本地文件 URL 引用拖出、即时存在性校验、部分失效只拖有效项、全部失效不启动拖出并提示；明确不包含临时副本、原文件删除 / 移动 / 复制 / 写入、打开文件、security-scoped bookmark、schema / repository / model / 备份格式 / search index 变更、favorite / management / multi-select / batch / JSON runtime 回归；允许主控 build/run 给用户做运行态测试。本轮仅追加 `docs/V2_AGENT_RUNBOOK.md`，未修改业务代码，未回退任何改动。
```

## 184. Stage 9 文件卡片拖出第一批主控 build/run 后 RC 对齐记录

```text
调度 ID：V2-DOCS-S9-FILE-DRAGOUT-BUILDRUN-1022-RC-ALIGN-001
时间：2026-05-15
阶段：Stage 9 文件卡片拖出第一批 Acceptance PASS 后主控 build/run
任务卡 ID：V2-DOCS-S9-FILE-DRAGOUT-BUILDRUN-1022-RC-ALIGN-001
当前会话模式：ClipEase V2 Docs/Log Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；仅同步 RC 文档与 runbook，不修改业务代码
结论：已记录 `1.0.22 (260515.0414)` 主控 build/run 与 RC 文档对齐动作；当前 smoke HOLD 唯一原因为 RC 报告版本未同步，本次文档对齐即处理该 HOLD 原因。

当前事实：
- `V2-ACCEPT-S9-FILE-DRAGOUT-FIRST-BATCH-001` 已 PASS，允许主控 build/run。
- 主控已执行 `scripts/build-app.sh --run`。
- 构建脚本自动从 `1.0.21 (260515.0351)` 提升到 `1.0.22 (260515.0414)`。
- 产物：`/Users/wpc/code/codex/ClipboardHistory/.build/ClipEase.app`。
- 当前进程：PID `67501`。

专项检查：
- `python3 scripts/verify_stage9_file_dragout_first_batch.py`：PASS。
- `python3 scripts/verify_stage9_file_basic_actions.py`：PASS。
- `python3 scripts/smoke_check.py`：当前仅因 `docs/RELEASE_CANDIDATE_REPORT.md` 未同步 `1.0.22(260515.0414)` HOLD；本次文档对齐即处理该 HOLD 原因。

本次 RC 对齐内容：
- 已将 `docs/RELEASE_CANDIDATE_REPORT.md` 当前结论、自动检查、RC 包信息和 RC 修复记录推进到 `1.0.22 (260515.0414)`。
- 已记录本包包含 Stage 9 文件卡片拖出第一批：`.file` 卡片 AppKit drag source bridge；drag pasteboard 仅写 `NSURL` file URL 引用；拖出前即时校验路径；部分失效只拖有效项；全部失效提示；不吞普通点击 / 右键 / 滚动 / 预览。
- 已记录本包明确不包含临时副本、打开文件、原文件删除 / 移动 / 复制 / 写入、security-scoped bookmark、schema / repository / model / search index、收藏 / 管理 / 多选 / 批量 / JSON runtime。
- 已记录剩余风险：真实 Finder / 外部 App 拖出运行态人工验收待用户测试。

后续：
- Test Agent 可在本次 RC 文档对齐后重跑 `python3 scripts/smoke_check.py`。
- 用户侧继续覆盖真实 Finder / 外部 App 拖出、系统拖动视觉和不同输入设备下的运行态手感。

交付摘要：Docs/Log Agent 已完成 `V2-DOCS-S9-FILE-DRAGOUT-BUILDRUN-1022-RC-ALIGN-001`；将主控 build/run 后的 `1.0.22 (260515.0414)`、PID `67501`、专项 PASS、smoke HOLD 原因和 RC 文档对齐动作记录到 `docs/RELEASE_CANDIDATE_REPORT.md` 与 `docs/V2_AGENT_RUNBOOK.md`；本轮未修改业务代码。
```

## 185. Stage 9 文件引用粘贴 fallback 收口调度记录

```text
调度 ID：V2-DOCS-S9-FILE-PASTE-FALLBACK-DISPATCH-001
时间：2026-05-15
阶段：Stage 9 active；文件卡片捕获 / 展示 / Quick Look / 文件引用 pasteboard / 基础操作 / 拖出均已完成并 build/run 到 `1.0.22 (260515.0414)`
任务卡 ID：V2-S9-FILE-PASTE-FALLBACK-FIRST-BATCH-001
当前会话模式：ClipEase V2 Docs/Log Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：中；涉及 pasteboard 结果语义和 UI toast 文案
结论：已记录主控正在推进 `V2-S9-FILE-PASTE-FALLBACK-FIRST-BATCH-001`；后续实现需进入 Test / Review / Acceptance 门禁，Acceptance PASS 后由主控 build/run。

背景：
- `docs/V2_TECHNICAL_PLAN.md` 9.5 写明：“如果全部文件都不可用，fallback 写入文件名或路径文本，并显示短提示”。
- 当前 `PasteExecutor.copyToPasteboard(.file)` 在没有有效本地路径时返回“未找到文件”，缺少 fallback。

本批目标：
- 当 `.file` 普通复制 / 自动粘贴发现没有任何有效本地文件 URL 时，不再只失败。
- 回退写入路径文本或文件名文本到剪贴板。
- UI 状态需明确显示“已复制/粘贴文件路径”或等价 fallback 文案，避免误报“文件引用”。
- 有效文件仍走 file URL pasteboard 引用。

文件锁：
- `Sources/ClipEase/Features/PasteExecutor/PasteExecutor.swift`
- `Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift`（仅状态文案 / 结果分派）
- `scripts/verify_stage9_file_paste_fallback.py`（新增）
- 可小范围更新 `scripts/verify_stage9_file_pasteboard_first_batch.py` 中过时的“无有效文件必须失败”断言。

红线：
- 不得删除 / 移动 / 复制 / 写入原文件。
- 不得创建临时副本。
- 不得新增打开文件 / Finder / drag 行为。
- 不得新增 security-scoped bookmark。
- 不得改 schema / repository / model / 备份格式 / search index。
- 不得恢复收藏 / 管理模式 / 多选 / 批量 / JSON runtime。

门禁：
- 实现后必须依次完成 Test / Review / Acceptance。
- Acceptance PASS 后主控 build/run。

交付摘要：Docs/Log Agent 已记录 Stage 9 文件引用粘贴 fallback 收口调度；主控正在推进 `V2-S9-FILE-PASTE-FALLBACK-FIRST-BATCH-001`，目标是在无有效本地 file URL 时 fallback 写入路径或文件名文本并给出明确 fallback UI 状态，同时保持有效文件继续使用 file URL pasteboard 引用；本轮仅修改 `docs/V2_AGENT_RUNBOOK.md`，未修改业务代码。
```

## 186. Stage 9 文件引用粘贴 fallback 收口测试记录

```text
调度 ID：V2-TEST-S9-FILE-PASTE-FALLBACK-FIRST-BATCH-001
时间：2026-05-15 06:59:06 CST
阶段：Stage 9 文件引用粘贴 fallback 收口测试
任务卡 ID：V2-TEST-S9-FILE-PASTE-FALLBACK-FIRST-BATCH-001
当前会话模式：ClipEase V2 Test Agent 模式
风险等级：中；涉及 NSPasteboard 文件引用优先级、全失效 fallback 文本结果、自动粘贴状态和 HistoryWindow toast 文案
结论：PASS。指定命令门禁全部通过；独立静态核对确认 `.file` 有效文件仍优先写 `NSURL` file URL pasteboard 引用，全失效时 fallback 写入路径 / 显示名 / item.text 文本并返回独立结果，自动粘贴和 toast 均能区分 fallback 文件路径结果；本轮未修改业务代码。

指定命令结果：
- `python3 scripts/verify_stage9_file_paste_fallback.py`：PASS，输出 `OK Stage 9 file paste fallback checks passed`。
- `python3 scripts/verify_stage9_file_pasteboard_first_batch.py`：PASS，输出 `OK Stage 9 file pasteboard first batch checks passed`。
- `python3 scripts/verify_stage9_file_basic_actions.py`：PASS，输出 `OK Stage 9 file basic action checks passed`。
- `python3 scripts/verify_stage9_file_dragout_first_batch.py`：PASS，输出 `OK Stage 9 file drag-out first batch checks passed`。
- `python3 scripts/verify_stage9_quicklook_interaction.py`：PASS，输出 `OK Stage 9 Quick Look interaction checks passed`。
- `python3 scripts/verify_no_management_no_favorite_ui.py`：PASS，输出 no management mode / removed saved-item UI tokens checks passed。
- `python3 scripts/verify_sqlite_only_baseline.py`：PASS，输出 `OK SQLite-only schema baseline verified` / `OK SQLite-only data baseline checks passed`。
- `swift build`：PASS，输出 `Build complete!`。
- `python3 scripts/smoke_check.py`：PASS，输出 `OK: Smoke check passed`；版本 `1.0.22(260515.0414)` 与 RC 报告匹配。
- `git diff --check`：PASS，无输出。

独立静态核对：
- `PasteExecutor.copyToPasteboard(_:)` 的 `.file` 分支先调用 `validLocalFileURLs(for:)`，存在有效项时仍执行 `pasteboard.writeObjects(fileURLs.map { $0 as NSURL })`，随后 `store.skipNextClipboardFiles(fileURLs)` 并返回 `.copied`。
- 全部文件 URL 无效时才调用 `fileFallbackText(for:)`；fallback 文本按 `reference.path` 优先、再 `reference.displayName`、最后 `item.text` 生成，多文件使用 `joined(separator: "\n")`。
- fallback 写入 `.string` 成功后调用 `store.skipNextClipboardText(fallbackText)`，并返回 `.copiedFallbackText`，未落入 generic failed；只有 fallback 文本也不可用时才返回 `未找到文件`。
- `pasteToFrontmostApp(_:)` 将 fallback 结果映射为 `.copiedFallbackTextOnly` 或 `.pastedFallbackText`，自动粘贴授权不足 / 成功路径均保留独立 fallback 语义。
- `HistoryWindowView.copyItem` / `pasteItem` 分别分派到 `copyFallbackTextStatus`、`copiedOnlyFallbackTextStatus`、`pastedFallbackTextStatus`；`.file` fallback toast 均包含“文件路径”，未误报为“文件引用”。
- `copyPlainTextToPasteboard(_:)` 仍写入 `pasteboardString(for:)`；`.file` 的 `pasteboardString(for:)` 仍从 `fileReferences` 输出路径 / 显示名并用换行连接，保留路径文本能力与 `skipNextClipboardText`。
- 本轮测试只追加 `docs/V2_AGENT_RUNBOOK.md`，未修改 `Sources/` 或脚本文件。

红线复核：
- fallback 相关路径未引入原文件 `copyItem` / `moveItem` / `removeItem`，未创建临时副本，未新增打开文件 / Finder / drag 行为。
- fallback 相关路径未新增 security-scoped bookmark、schema / repository / model / search index 改动。
- `verify_no_management_no_favorite_ui.py` 与 `verify_sqlite_only_baseline.py` 均 PASS，未发现 favorite / management / JSON runtime 回归。
- 共享工作区已有大量其他 Agent / 用户改动与未跟踪文件；本 Test Agent 未回退任何改动，结论限定于本任务卡验证范围。

交付摘要：Test Agent 已完成 `V2-TEST-S9-FILE-PASTE-FALLBACK-FIRST-BATCH-001`；所有指定命令 PASS，静态核对确认文件引用 pasteboard 优先、全失效 fallback 路径文本、多文件换行、fallback 独立结果、自动粘贴 copiedOnly / pasted fallback 状态、HistoryWindow fallback “文件路径” toast、`copyPlainTextToPasteboard` 路径文本能力和 `skipNextClipboardText` 均符合要求；红线未破。本轮仅追加 `docs/V2_AGENT_RUNBOOK.md`，未修改业务代码。
```

## 187. Stage 9 文件引用粘贴 fallback 收口审查记录

```text
调度 ID：V2-REVIEW-S9-FILE-PASTE-FALLBACK-FIRST-BATCH-001
时间：2026-05-15 07:12:00 CST
阶段：Stage 9 文件引用粘贴 fallback 收口审查
任务卡 ID：V2-REVIEW-S9-FILE-PASTE-FALLBACK-FIRST-BATCH-001
当前会话模式：ClipEase V2 Review Agent 模式
风险等级：中；涉及 NSPasteboard file URL 引用优先级、全失效 fallback 文本、PasteResult 语义和 UI 状态文案
结论：PASS。未发现阻塞 Findings；本轮仅追加 `docs/V2_AGENT_RUNBOOK.md` 审查记录，未修改业务代码，未回退任何已有改动。

Findings：
- 未发现阻塞问题。

审查范围：
- `Sources/ClipEase/Features/PasteExecutor/PasteExecutor.swift`
- `Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift`
- `Sources/ClipEase/Features/HistoryWindow/HistoryWindowController.swift` 相关调用点只读核对
- `Sources/ClipEase/Features/ClipboardMonitor/ClipboardMonitor.swift` self-write guard 相关路径只读核对
- `scripts/verify_stage9_file_paste_fallback.py`
- 相邻 Stage 9 / 基线验证脚本

核心核对结果：
- `PasteExecutor.copyToPasteboard(_:)` 的 `.file` 分支先计算 `validLocalFileURLs(for:)`，只要存在有效本地路径就执行 `pasteboard.writeObjects(fileURLs.map { $0 as NSURL })`，随后调用 `store.skipNextClipboardFiles(fileURLs)` 并返回 `.copied`；有效路径行为未回退到文本。
- 全部 file URL 无效时才进入 fallback；`fileFallbackText(for:)` 按 `reference.path` 优先、再 `reference.displayName`、最后 `item.text` 生成文本，多文件使用 `joined(separator: "\n")`。
- fallback 写入 `.string` 成功后调用 `store.skipNextClipboardText(fallbackText)`，返回 `.copiedFallbackText`；只有 fallback 文本也不可用时才返回 `未找到文件`。
- `PasteboardCopyResult` 新增 `.copiedFallbackText` 后，现有 switch 调用点均覆盖；`PasteResult` 新增 `.copiedFallbackTextOnly` / `.pastedFallbackText` 后，`HistoryWindowView` 与 `PasteExecutor` 内部 switch 均覆盖，`swift build` PASS。
- `HistoryWindowView.copyItem` / `pasteItem` 对 fallback copy / copiedOnly / pasted 分别走 `copyFallbackTextStatus`、`copiedOnlyFallbackTextStatus`、`pastedFallbackTextStatus`；`.file` 文案明确为“文件路径”，未误报“文件引用”。
- `copyPlainTextToPasteboard(_:)` 对 text / link / color 仍写入原 `item.text` 语义；对 `.file` 仍保留路径 / 显示名文本能力，并调用 `store.skipNextClipboardText`。
- `ClipboardMonitor` 仍先读 file URL，再走 image / text；文件引用自写由 `consumeSkippedClipboardFiles` 跳过，文本 fallback 自写由 `skipNextClipboardText` 覆盖。

验证命令：
- `swift build`：PASS，输出 `Build complete!`。
- `python3 scripts/verify_stage9_file_paste_fallback.py`：PASS，输出 `OK Stage 9 file paste fallback checks passed`。
- `python3 scripts/verify_stage9_file_pasteboard_first_batch.py`：PASS，输出 `OK Stage 9 file pasteboard first batch checks passed`。
- `python3 scripts/verify_stage9_file_basic_actions.py`：PASS，输出 `OK Stage 9 file basic action checks passed`。
- `python3 scripts/verify_stage9_file_dragout_first_batch.py`：PASS，输出 `OK Stage 9 file drag-out first batch checks passed`。
- `python3 scripts/verify_stage9_quicklook_interaction.py`：PASS，输出 `OK Stage 9 Quick Look interaction checks passed`。
- `python3 scripts/verify_no_management_no_favorite_ui.py`：PASS，输出 no management mode / removed saved-item UI tokens checks passed。
- `python3 scripts/verify_sqlite_only_baseline.py`：PASS，输出 `OK SQLite-only schema baseline verified` / `OK SQLite-only data baseline checks passed`。
- `python3 scripts/smoke_check.py`：PASS，输出 `OK: Smoke check passed`。
- `git diff --check`：PASS，无输出。

红线复核：
- 本批 fallback 路径未引入原文件删除 / 移动 / 复制 / 写入。
- 未创建临时副本。
- 未新增打开文件、Finder reveal 或 drag 行为。
- 未新增 security-scoped bookmark。
- 未改 schema / repository / model / 备份格式 / search index。
- 基线脚本确认未恢复 favorite / management；本审查未发现 multi-select / batch / JSON runtime 回归信号。

非阻塞观察：
- `HistoryWindowController.showPreview` 中预览窗口 header 的 `onCopy` 仍直接 `_ = pasteExecutor.copyToPasteboard(item)`，不会展示 copy fallback / failed 状态。该点不影响本卡要求的 `HistoryWindowView` copy / paste 状态分派，也不影响 pasteboard fallback 行为；建议后续若统一预览窗口 toast，再补充分派。

剩余风险：
- 本次主要为静态审查与脚本门禁；真实 Finder / 外部 App 接收 file URL 引用、无效路径 fallback 粘贴到不同目标 App 的运行态体验仍需用户人工覆盖。

交付摘要：Review Agent 已完成 `V2-REVIEW-S9-FILE-PASTE-FALLBACK-FIRST-BATCH-001`；审查确认 `.file` 有效路径仍优先写 `NSURL` file URL 引用，全失效 fallback 写路径 / 显示名 / `item.text` 文本并换行连接，fallback 文本写入会调用 `skipNextClipboardText`，新增结果 case 的 switch 调用点已覆盖，`HistoryWindowView` fallback 状态明确显示“文件路径”，`copyPlainTextToPasteboard` 既有文本能力未破坏，专项与相邻回归脚本、`swift build`、smoke、diff check 均 PASS；红线未破。最终裁定 PASS。
```

## 188. Stage 9 文件引用粘贴 fallback 收口验收记录

```text
调度 ID：V2-ACCEPT-S9-FILE-PASTE-FALLBACK-FIRST-BATCH-001
时间：2026-05-15 07:02:59 CST
阶段：Stage 9 文件引用粘贴 fallback 收口验收
任务卡 ID：V2-ACCEPT-S9-FILE-PASTE-FALLBACK-FIRST-BATCH-001
当前会话模式：ClipEase V2 Acceptance Agent 模式
风险等级：中；涉及文件引用 pasteboard 优先级、无效文件 fallback 文本、自写跳过和 HistoryWindow 状态文案
结论：PASS。基于已完成的实现、Test PASS 与 Review PASS 记录，本批满足放行范围；允许主控执行 build/run，并交给用户做运行态测试。本轮仅追加 `docs/V2_AGENT_RUNBOOK.md` 验收记录，未修改业务代码，未回退任何已有改动。

验收依据：
- 实现任务 `V2-S9-FILE-PASTE-FALLBACK-FIRST-BATCH-001` 已完成。
- Test 任务 `V2-TEST-S9-FILE-PASTE-FALLBACK-FIRST-BATCH-001` 已 PASS；指定命令均通过，包括 fallback 专项、Stage 9 相邻文件能力脚本、无管理/收藏 UI 基线、SQLite-only 基线、`swift build`、smoke 与 `git diff --check`。
- Review 任务 `V2-REVIEW-S9-FILE-PASTE-FALLBACK-FIRST-BATCH-001` 已 PASS；未发现阻塞 findings。

放行范围裁定：
- `.file` 普通复制 / 自动粘贴仍优先写 `NSURL` file URL 引用；只要存在有效本地文件 URL，不降级为文本。
- 全部文件 URL 无效时 fallback 写入路径 / 显示名 / `item.text` 文本，多文件使用换行连接。
- fallback 成功返回独立结果，自动粘贴路径保留 copied-only / pasted fallback 语义。
- `HistoryWindowView` toast 使用“文件路径”语义，不误报“文件引用”。
- fallback 文本写入调用 `store.skipNextClipboardText`，覆盖文本自写跳过。
- `copyPlainTextToPasteboard` 保留文件路径 / 显示名文本能力。

红线复核：
- 未删除 / 移动 / 复制 / 写入原文件；未创建临时副本。
- 未新增打开文件 / Finder / drag 行为。
- 未新增 security-scoped bookmark。
- 未改 schema / repository / model / 备份格式 / search index。
- 未恢复 favorite / management / multi-select / batch / JSON runtime。

非阻塞观察：
- 预览窗口 header 复制按钮仍丢弃 `copyToPasteboard` 结果，不展示 fallback / 失败状态；该点已另派 backlog 文档任务，不阻塞本批验收。

剩余风险：
- 本验收基于已通过的静态脚本、构建、smoke、Review 记录与 runbook 证据；真实 Finder / 外部 App 对 file URL 引用和无效路径 fallback 文本的运行态体验仍需主控 build/run 后交由用户人工覆盖。

交付摘要：Acceptance Agent 裁定 `V2-ACCEPT-S9-FILE-PASTE-FALLBACK-FIRST-BATCH-001` PASS；Stage 9 文件引用粘贴 fallback 第一批可放行，允许主控 build/run 给用户做运行态测试。本轮仅修改 `docs/V2_AGENT_RUNBOOK.md`，未修改业务代码。
```

## 189. Stage 9 文件引用粘贴 fallback 收口主控 build/run 后 RC 对齐记录

```text
调度 ID：V2-DOCS-S9-FILE-PASTE-FALLBACK-BUILDRUN-1023-RC-ALIGN-001
时间：2026-05-15
阶段：Stage 9 文件引用粘贴 fallback 收口 Acceptance PASS 后主控 build/run
任务卡 ID：V2-DOCS-S9-FILE-PASTE-FALLBACK-BUILDRUN-1023-RC-ALIGN-001
当前会话模式：ClipEase V2 Docs/Log Agent 模式
主控 Agent：Codex 主控 Agent
风险等级：低；仅同步 RC 文档与 runbook，不修改业务代码
结论：已记录 `1.0.23 (260515.0703)` 主控 build/run 与 RC 文档对齐动作；当前 smoke HOLD 原因为 RC 报告版本未同步，本次文档对齐即处理该 HOLD 原因。

当前事实：
- `V2-ACCEPT-S9-FILE-PASTE-FALLBACK-FIRST-BATCH-001` 已 PASS，允许主控 build/run。
- 主控已执行 `scripts/build-app.sh --run`。
- 构建脚本自动从 `1.0.22 (260515.0414)` 提升到 `1.0.23 (260515.0703)`。
- 产物：`/Users/wpc/code/codex/ClipboardHistory/.build/ClipEase.app`。
- 当前进程：PID `41016`。

专项检查：
- `python3 scripts/verify_stage9_file_paste_fallback.py`：PASS。
- `python3 scripts/verify_stage9_file_pasteboard_first_batch.py`：PASS。
- `python3 scripts/smoke_check.py`：当前仅因 `docs/RELEASE_CANDIDATE_REPORT.md` 未同步 `1.0.23(260515.0703)` HOLD；本次文档对齐即处理该 HOLD 原因。

本次 RC 对齐内容：
- 已将 `docs/RELEASE_CANDIDATE_REPORT.md` 当前结论、自动检查、RC 包信息和 RC 修复记录推进到 `1.0.23 (260515.0703)`。
- 已记录本包包含 Stage 9 文件引用粘贴 fallback 收口：有效文件仍优先写 `NSURL` file URL 引用；全部文件不可用时 fallback 写路径 / 显示名 / `item.text` 文本，多文件换行；fallback 结果有独立状态，toast 显示“文件路径”语义，不误报“文件引用”；fallback 调用 `skipNextClipboardText`。
- 已记录本包明确不包含原文件删除 / 移动 / 复制 / 写入、临时副本、打开文件 / Finder / drag 新增、security-scoped bookmark、schema / repository / model / search index、收藏 / 管理 / 多选 / 批量 / JSON runtime。
- 已记录剩余风险：真实外部 App 粘贴文件引用 / 路径 fallback、路径失效文件运行态人工验收待用户测试；预览 header 复制按钮统一 toast / fallback 状态已进入非阻塞 backlog。

后续：
- Test Agent 可在本次 RC 文档对齐后重跑 `python3 scripts/smoke_check.py`。
- 用户侧继续覆盖真实外部 App 粘贴、无效路径 fallback 和预览 header 复制按钮统一 toast 的运行态体验。

交付摘要：Docs/Log Agent 已完成 `V2-DOCS-S9-FILE-PASTE-FALLBACK-BUILDRUN-1023-RC-ALIGN-001`；将主控 build/run 后的 `1.0.23 (260515.0703)`、PID `41016`、专项 PASS、smoke HOLD 原因和 RC 文档对齐动作记录到 `docs/RELEASE_CANDIDATE_REPORT.md` 与 `docs/V2_AGENT_RUNBOOK.md`；本轮未修改业务代码。
```

## 190. Stage 9 文件卡片 / Quick Look 收口范围评估记录

```text
调度 ID：V2-PRODUCT-S9-CLOSEOUT-ASSESSMENT-001
时间：2026-05-15
阶段：Stage 9 文件卡片 / Quick Look 收口评估
当前会话模式：ClipEase V2 Product/Scope Agent 模式
风险等级：低；只做范围评估和文档建议，不修改业务代码
结论：PASS。Stage 9 第一批 MVP 产品范围已基本闭环；建议进入 Stage 9 收口 + 用户人工验收，不建议继续扩大 Stage 9 polish 主线。

评估依据：
- 已只读核对 `docs/V2_PRODUCT_PLAN.md`、`docs/V2_DEVELOPMENT_PLAN.md`、`docs/V2_TECHNICAL_PLAN.md`、`docs/V2_TEST_PLAN.md`、`docs/V2_OPTIMIZATION_BACKLOG.md` 和本 runbook。
- Stage 9 已 build/run 到 `1.0.23 (260515.0703)`。
- runbook 已记录文件数据 / schema、捕获、卡片 UI、Quick Look、用户 9 项反馈修复、文件引用 pasteboard、基础操作、drag-out、paste fallback 等 Test / Review / Acceptance PASS 与 build/run 记录。

已闭环的 Stage 9 第一批 MVP 范围：
- 文件数据建模与 SQLite-only 基线下的文件引用记录。
- Finder / pasteboard 本地文件 URL 捕获，覆盖单文件、多文件、目录、顺序和基础元数据。
- 文件卡片 UI：文件名 / 多文件数量、扩展名、系统图标 / 缩略图、路径展示、失效状态、来源 App 图标。
- Quick Look / 预览窗口：复用现有预览生命周期，支持可预览文件、不可预览 fallback、基础信息、多文件列表和选中文件预览。
- 文件卡片加入分组、置顶 / 分组 / no favorite / no management 基线回归。
- 文件名 / 完整路径的首批内存搜索；未引入 LIKE / FTS / 拼音 / schema 搜索索引。
- 文件引用复制 / 自动粘贴使用 `NSURL` file URL pasteboard；纯文本复制保留路径文本。
- 文件引用 paste fallback：全部文件不可用时 fallback 写路径 / 显示名 / `item.text` 文本，并用“文件路径”语义提示。
- 基础只读操作：主窗口和预览窗口提供“复制路径”“在 Finder 中显示”，无有效路径只提示。
- Drag-out 增量：支持拖出有效文件引用到 Finder / 支持 file URL drag pasteboard 的 App；部分失效只拖有效项，全部失效提示。
- 红线约束：未删除 / 移动 / 复制 / 写入原文件，未创建临时副本，未新增 security-scoped bookmark，未恢复收藏 / 管理 / 多选 / 批量 / JSON runtime，未把文件副本纳入备份或附件生命周期。

非阻塞 backlog / 后续专项建议：
- 文件预览窗口 header 复制按钮统一 toast / fallback / 失败状态已进入 `docs/V2_OPTIMIZATION_BACKLOG.md` 的 `V2-BACKLOG-S9-PREVIEW-COPY-TOAST-UNIFIED-001`，不阻塞收口。
- “打开文件”操作：开发计划列为第一批暂缓项，技术计划仍有失败文案待确认；建议归后续文件操作 polish，不阻塞 Stage 9 MVP。
- 系统分享：开发计划列为第一批暂缓项，技术计划仍有失败回退待确认；建议归后续系统集成 backlog。
- 文件卡片拼音搜索：开发计划明确本批不要求，技术计划要求延后到搜索性能专项；建议归搜索专项，不混入 Stage 9 收口。
- 文件路径 FTS、专用索引或 Repository 查询下沉：开发计划和技术计划均明确不属于首批；建议归性能 / 搜索下沉专项。
- 多文件列表排序自定义、多文件列表显示每个文件大小、路径隐私遮罩 / 用户名隐藏、security-scoped bookmark / 重新定位文件、文件副本导出、备份包包含文件副本，均为明确暂缓项或红线外能力。
- 真实 Finder / 外部 App 接收 file URL、drag-out、无效路径 fallback、Quick Look 多文件交互、多屏 toast 等仍需用户人工运行态验收；这是收口验收风险，不是继续开发阻塞项。

阻塞项判断：
- 未发现仍必须阻塞 Stage 9 收口的产品规则冲突或红线未确认。
- 文档中“测试计划覆盖拼音搜索、打开文件、系统分享”等属于广义测试覆盖 / 后续能力提醒；与 `docs/V2_DEVELOPMENT_PLAN.md` Stage 9 第一批暂缓项和 `docs/V2_TECHNICAL_PLAN.md` 首批不做拼音 / 索引的规则并不冲突。
- 唯一已知体验缺口为预览 header 复制按钮 toast 统一，已归非阻塞 backlog。

下一步建议：
- Stage 9 主线收口。
- 交给用户做人工验收，优先覆盖真实 Finder / 外部 App 文件引用粘贴、drag-out、无效路径 fallback、路径失效、Quick Look 多文件切换、预览菜单、toast 层级。
- 若人工验收发现 P0/P1 回归，再按 bugfix 小卡处理；否则不要继续扩大 Stage 9 polish，应转入下阶段或 backlog 消化。

交付摘要：Product/Scope Agent 完成 `V2-PRODUCT-S9-CLOSEOUT-ASSESSMENT-001`；结论 PASS，Stage 9 第一批 MVP 产品范围已基本闭环，建议 Stage 9 收口并进入用户人工验收；打开文件、系统分享、拼音搜索、路径索引、预览 header toast 等归非阻塞 backlog / 后续专项。本轮仅追加 `docs/V2_AGENT_RUNBOOK.md`，未修改业务代码。
```

## 191. Stage 9 文件卡片 / Quick Look 自动门禁收口评估记录

```text
任务卡 ID：V2-TEST-S9-CLOSEOUT-ASSESSMENT-001
时间：2026-05-15 13:04:21 CST
阶段：Stage 9 文件卡片 / Quick Look 收口评估
当前会话模式：ClipEase V2 Test/Release Gate Agent 模式
风险等级：低；只做测试门禁和收口评估，不修改业务代码
结论：PASS。Stage 9 自动门禁已通过，可以进入用户人工验收。

版本 / 范围核对：
- 当前版本：`1.0.23 (260515.0703)`。
- Product/Scope `V2-PRODUCT-S9-CLOSEOUT-ASSESSMENT-001` 已 PASS，建议 Stage 9 主线收口 + 用户人工验收。
- 本轮仅运行 / 核对门禁命令并追加 runbook 记录，未修改业务代码。

自动门禁结果：
- `python3 scripts/smoke_check.py`：PASS。
- `python3 scripts/verify_stage9_file_card_data_foundation.py`：PASS。
- `python3 scripts/verify_stage9_file_capture_first_batch.py`：PASS。
- `python3 scripts/verify_stage9_file_card_ui.py`：PASS。
- `python3 scripts/verify_stage9_file_card_display.py`：PASS。
- `python3 scripts/verify_stage9_quicklook_spike.py`：PASS。
- `python3 scripts/verify_stage9_quicklook_interaction.py`：PASS。
- `python3 scripts/verify_stage9_file_pasteboard_first_batch.py`：PASS。
- `python3 scripts/verify_stage9_file_basic_actions.py`：PASS。
- `python3 scripts/verify_stage9_file_dragout_first_batch.py`：PASS。
- `python3 scripts/verify_stage9_file_paste_fallback.py`：PASS。
- `python3 scripts/verify_sqlite_only_baseline.py`：PASS。
- `python3 scripts/verify_no_management_no_favorite_ui.py`：PASS。
- `swift build`：PASS，`Build complete! (0.21s)`。
- `git diff --check`：PASS，无 whitespace / conflict marker 输出。

剩余人工验收风险：
- 真实 Finder / 外部 App 接收 `NSURL` file URL pasteboard 的粘贴行为仍需用户在运行态确认。
- Drag-out 到 Finder / 支持 file URL drag pasteboard 的外部 App 仍需用户覆盖真实目标 App。
- 全部路径失效、部分路径失效、目录、多文件混合等边界场景的用户可感知提示仍需人工验收。
- Quick Look 多文件切换、不可预览文件 fallback、预览窗口菜单 / toast 层级仍需人工体验确认。
- 文件预览窗口 header 复制按钮 toast / fallback 状态统一已归非阻塞 backlog，不阻塞本次收口。

收口判断：
- 未发现自动门禁阻塞项。
- 未发现需要返工的 Stage 9 P0 / P1 风险。
- 建议 Stage 9 主线进入“自动门禁收口 / 用户人工验收”状态；若用户人工验收发现真实外部 App 兼容问题，再按 bugfix 小卡处理。

交付摘要：Test/Release Gate Agent 完成 `V2-TEST-S9-CLOSEOUT-ASSESSMENT-001`；指定自动门禁命令全部 PASS，结论 PASS，可以进入用户人工验收。本轮仅追加 `docs/V2_AGENT_RUNBOOK.md`，未修改业务代码。
```

## 192. Stage 9 文件卡片 / Quick Look 主线收口验收记录

```text
任务卡 ID：V2-ACCEPT-S9-CLOSEOUT-001
时间：2026-05-15 13:05:46 CST
阶段：Stage 9 文件卡片 / Quick Look 主线收口
当前会话模式：ClipEase V2 Acceptance Agent 模式
风险等级：低；只做阶段收口验收和文档记录，不修改业务代码
结论：PASS。Stage 9 主线可以收口，进入用户人工验收状态。

验收依据：
- Product/Scope `V2-PRODUCT-S9-CLOSEOUT-ASSESSMENT-001`：PASS。Stage 9 第一批 MVP 产品范围已基本闭环，建议 Stage 9 主线收口 + 用户人工验收。
- Test/Release Gate `V2-TEST-S9-CLOSEOUT-ASSESSMENT-001`：PASS。所有 Stage 9 专项 verify、smoke、SQLite-only、no management / no favorite、`swift build`、`git diff --check` 均通过。
- 当前运行包：`1.0.23 (260515.0703)`。
- 当前运行进程：PID `41016`。

验收裁定：
- Stage 9 文件卡片 / Quick Look 主线可以收口。
- 当前状态切换为“用户人工验收”。
- 自动门禁未发现阻塞项，不要求继续扩大 Stage 9 polish 主线。
- 若用户人工验收发现真实外部 App 兼容问题或 P0 / P1 回归，再按 bugfix 小卡处理；不作为本次自动门禁阻塞。

已完成能力：
- 文件数据建模与 SQLite-only 基线下的文件引用记录。
- Finder / pasteboard 本地文件 URL 捕获，覆盖单文件、多文件、目录、顺序和基础元数据。
- 文件卡片 UI：文件名 / 多文件数量、扩展名、系统图标 / 缩略图、路径展示、失效状态、来源 App 图标。
- Quick Look / 预览窗口：支持可预览文件、不可预览 fallback、基础信息、多文件列表和选中文件预览。
- 文件卡片加入分组、置顶 / 分组 / no favorite / no management 基线回归。
- 文件名 / 完整路径首批内存搜索；未引入 LIKE / FTS / 拼音 / schema 搜索索引。
- 文件引用复制 / 自动粘贴使用 `NSURL` file URL pasteboard；纯文本复制保留路径文本。
- 文件引用 paste fallback：全部文件不可用时 fallback 写路径 / 显示名 / `item.text` 文本，多文件换行，并用“文件路径”语义提示。
- 文件基础只读操作：主窗口和预览窗口支持“复制路径”“在 Finder 中显示”，无有效路径只提示。
- Drag-out：支持有效文件引用拖出到 Finder / 支持 file URL drag pasteboard 的 App；部分失效只拖有效项，全部失效提示。
- 红线约束保持：未删除 / 移动 / 复制 / 写入原文件，未创建临时副本，未新增 security-scoped bookmark，未恢复收藏 / 管理 / 多选 / 批量 / JSON runtime，未把文件副本纳入备份或附件生命周期。

排除 / 后续 backlog：
- 文件预览窗口 header 复制按钮统一 toast / fallback / 失败状态：已归 `V2-BACKLOG-S9-PREVIEW-COPY-TOAST-UNIFIED-001`，不阻塞收口。
- “打开文件”操作：归后续文件操作 polish。
- 系统分享：归后续系统集成 backlog。
- 文件卡片拼音搜索：归后续搜索专项。
- 文件路径 FTS、专用索引或 Repository 查询下沉：归性能 / 搜索下沉专项。
- 多文件列表排序自定义、多文件列表显示每个文件大小、路径隐私遮罩 / 用户名隐藏、security-scoped bookmark / 重新定位文件、文件副本导出、备份包包含文件副本：均不属于 Stage 9 第一批 MVP 收口范围。

剩余风险：
- 真实 Finder / 外部 App 接收 `NSURL` file URL pasteboard 的粘贴行为仍需用户在运行态确认。
- Drag-out 到 Finder / 支持 file URL drag pasteboard 的外部 App 仍需用户覆盖真实目标 App。
- 全部路径失效、部分路径失效、目录、多文件混合等边界场景的用户可感知提示仍需人工验收。
- Quick Look 多文件切换、不可预览文件 fallback、预览窗口菜单 / toast 层级仍需人工体验确认。
- 上述风险均属于用户人工验收范围，不阻塞自动门禁，不阻塞 Stage 9 主线收口。

交付摘要：Acceptance Agent 完成 `V2-ACCEPT-S9-CLOSEOUT-001`；裁定 Stage 9 文件卡片 / Quick Look 主线 PASS 收口并进入用户人工验收；已完成能力、排除 / backlog 和剩余人工验收风险已记录。本轮仅追加 `docs/V2_AGENT_RUNBOOK.md`，未修改业务代码。
```

## 193. Stage 10 iCloud 同步预研前置调度记录

```text
调度 ID：V2-DOCS-S10-PREFLIGHT-DISPATCH-001
时间：2026-05-15
阶段：Stage 10 iCloud 同步预研前置调度
当前会话模式：ClipEase V2 Docs/Log Agent 模式
主控 Agent：Codex 主控 Agent
被调用 Agent：Product/Scope Agent、Architecture Gatekeeper Agent、Test Plan Agent
风险等级：高；涉及未来同步、CloudKit、数据一致性、隐私和附件策略，但本轮仅做预研调度，不写业务代码
文件锁：
- docs/V2_AGENT_RUNBOOK.md：Docs/Log Agent 追加调度记录
用户确认：Stage 9 主线已通过 Product/Scope、Test/Release Gate、Acceptance 收口；当前 `1.0.23 (260515.0703)` 进入用户人工验收状态。Stage 10 本轮仅进入 iCloud 同步预研前置阶段；后续进入任何 Stage 10 实现或 spike 前，必须再取得用户确认。

Stage 9 收口事实：
- Product/Scope `V2-PRODUCT-S9-CLOSEOUT-ASSESSMENT-001`：PASS，Stage 9 第一批 MVP 产品范围已基本闭环，建议主线收口并进入用户人工验收。
- Test/Release Gate `V2-TEST-S9-CLOSEOUT-ASSESSMENT-001`：PASS，Stage 9 专项 verify、smoke、SQLite-only、no management / no favorite、`swift build`、`git diff --check` 均通过。
- Acceptance `V2-ACCEPT-S9-CLOSEOUT-001`：PASS，裁定 Stage 9 文件卡片 / Quick Look 主线可以收口。
- 当前运行包：`1.0.23 (260515.0703)`，状态为用户人工验收。

Stage 10 范围边界：
- 根据 `docs/V2_DEVELOPMENT_PLAN.md`，Stage 10 仅为 iCloud 同步预研。
- 本阶段不实现正式同步，只产出技术预研和风险结论。
- 本轮调度不代表 CloudKit、iCloud runtime、同步 UI 或数据 schema 变更已放行。

本轮前置卡调度：
- `V2-PRODUCT-S10-ICLOUD-SYNC-PREFLIGHT-001`
- `V2-ARCH-S10-ICLOUD-SYNC-PREFLIGHT-001`
- `V2-TESTPLAN-S10-ICLOUD-SYNC-PREFLIGHT-001`

红线：
- 不得写业务代码。
- 不得新增 iCloud runtime、CloudKit runtime、同步开关、schema 迁移、软删除字段、device filter UI、附件上传下载、端到端加密、冲突合并实现。
- 不得恢复收藏 / 管理模式 / JSON runtime。

输出目标：
- 产品边界。
- 架构风险。
- 数据 / 隐私 / 冲突 / 附件同步策略。
- 测试计划。
- 用户确认问题。

后续动作：
- Product/Scope Agent 输出 Stage 10 iCloud 同步预研的产品边界和用户确认问题。
- Architecture Gatekeeper Agent 输出 CloudKit / iCloud 适配性、数据一致性、隐私、冲突、附件同步和迁移风险结论。
- Test Plan Agent 输出仅面向预研和未来实现门禁的测试计划，不要求也不允许新增 runtime 测试实现。
- 用户确认前，不得进入任何 Stage 10 实现或 spike。

交付摘要：Docs/Log Agent 已追加 Stage 10 iCloud 同步预研前置调度记录；确认 Stage 9 已通过 Product/Scope、Test/Release Gate、Acceptance 收口，`1.0.23 (260515.0703)` 当前进入用户人工验收；记录本轮三张前置卡 `V2-PRODUCT-S10-ICLOUD-SYNC-PREFLIGHT-001`、`V2-ARCH-S10-ICLOUD-SYNC-PREFLIGHT-001`、`V2-TESTPLAN-S10-ICLOUD-SYNC-PREFLIGHT-001`；明确 Stage 10 当前仅做技术预研和风险结论，不实现正式同步，不写业务代码，不新增 iCloud / CloudKit runtime、同步开关、schema 迁移、软删除字段、device filter UI、附件上传下载、端到端加密或冲突合并实现，不恢复收藏 / 管理模式 / JSON runtime；后续需用户确认后才能进入任何 Stage 10 实现或 spike。
```

## 194. Stage 10 iCloud 同步预研产品前置方案

```text
任务卡：V2-PRODUCT-S10-ICLOUD-SYNC-PREFLIGHT-001
时间：2026-05-15
阶段：Stage 10 iCloud 同步预研产品前置
当前会话模式：ClipEase V2 Product Rules Agent
风险等级：高；涉及未来同步、隐私、CloudKit、附件、删除和冲突策略，但本轮仅更新产品 / 计划文档，不写业务代码
修改范围：
- docs/V2_PRODUCT_PLAN.md
- docs/V2_DEVELOPMENT_PLAN.md
- docs/V2_AGENT_RUNBOOK.md

核对文档：
- docs/V2_PRODUCT_PLAN.md
- docs/V2_DEVELOPMENT_PLAN.md
- docs/V2_TECHNICAL_PLAN.md
- docs/V2_TEST_PLAN.md
- docs/V2_OPTIMIZATION_BACKLOG.md

产品结论：PASS。

Stage 10 产品边界：
- Stage 10 第一批只做 iCloud 同步预研，不做正式同步功能。
- 不出现用户可见同步开关、设备筛选 UI、同步状态 UI 或 CloudKit / iCloud runtime。
- 不新增 schema 迁移、软删除字段、附件上传下载、端到端加密或冲突合并 runtime。
- 输出物限定为同步范围候选、暂缓范围、隐私 / 加密 / 附件 / 冲突 / 删除同步风险和用户确认问题。

可考虑同步的数据候选：
- 历史条目：未来核心候选，但剪贴板历史默认高敏感；需分别评估纯文本、链接、颜色、图片、富文本和文件卡片。
- 分组：可作为低复杂度候选；需评估 group id 稳定性、重命名冲突和删除语义。
- 置顶：可作为轻量候选；需评估跨设备置顶顺序和最后写入覆盖规则。
- 设置：仅评估非敏感偏好；快捷键、隐私忽略、敏感遮罩和本机窗口状态默认不建议同步。
- 附件 / 图片 / 富文本：只做策略评估；第一批不做真实上传、下载、断点恢复或清理语义变化。
- 文件卡片路径：只评估路径历史同步语义。当前文件卡片只记录本机路径，不上传原文件；跨设备路径不可用必须显示为“原设备路径记录 / 本机可能不可访问”，不得暗示文件已同步。

明确暂不实现：
- iCloud 正式同步。
- 端到端加密。
- 附件真实上传 / 下载 / 断点恢复。
- 跨设备删除同步。
- 设备筛选 UI。
- 冲突合并 runtime。
- 文件原件上传、复制、移动、删除或远端清理。

产品红线：
- 用户隐私优先，剪贴板历史默认视为高敏感数据。
- 默认不上传原文件，不上传文件卡片指向的本地文件内容。
- 文件卡片目前只记录路径；跨设备路径不可用必须有明确产品语义，不得伪装为可打开文件。
- 删除历史记录不得默认扩展为删除原文件或远端文件。
- 任何进入实现或 spike 的同步能力，都必须在用户再次确认后另开任务卡。

给主控下一步建议：
- 需要用户确认后再进入任何 Stage 10 架构 spike 或实现 spike。
- 建议确认：是否接受 Stage 10 只产出预研结论；未来第一批是否只考虑元数据 / 文本类数据；附件、图片原件、富文本附件和文件原件是否继续暂缓；文件卡片路径跨设备语义是否接受；删除同步是否继续暂缓；哪些设置可同步；端到端加密是否作为正式同步前置门槛。

交付摘要：Product Rules Agent 已补充 Stage 10 iCloud 同步预研产品边界、候选同步范围、明确暂缓范围、隐私 / 附件 / 冲突 / 删除红线和用户确认问题；本轮仅修改产品 / 计划 / runbook 文档，未修改业务代码，未运行构建。
```

## 195. Stage 10 iCloud 同步预研架构前置方案

```text
任务卡：V2-ARCH-S10-ICLOUD-SYNC-PREFLIGHT-001
时间：2026-05-15
阶段：Stage 10 iCloud 同步预研架构前置
当前会话模式：ClipEase V2 Architecture Gatekeeper Agent
风险等级：高；涉及未来同步、CloudKit、SQLite schema、删除 tombstone、隐私 / 加密和附件策略，但本轮只修改架构 / 计划文档，不写业务代码
修改范围：
- docs/V2_TECHNICAL_PLAN.md
- docs/V2_DEVELOPMENT_PLAN.md
- docs/V2_AGENT_RUNBOOK.md

只读核对：
- docs/V2_TECHNICAL_PLAN.md
- docs/V2_DEVELOPMENT_PLAN.md
- docs/V2_PRODUCT_PLAN.md
- Sources/ClipEase/Core/Storage/SQLiteClipboardStore.swift
- Sources/ClipEase/Core/Models/ClipboardItem.swift
- Sources/ClipEase/Core/Models/ClipboardGroup.swift
- Sources/ClipEase/Core/Storage/ClipboardHistoryRepository.swift
- Sources/ClipEase/Core/Utilities/HistoryExportService.swift
- Sources/ClipEase/Core/Utilities/HistoryDataHealthChecker.swift

架构结论：PASS 进入 Stage 10 预研文档和后续 spike 设计；HOLD 任何 CloudKit runtime、schema 迁移、同步 UI、附件上传下载、端到端加密和跨设备删除实现。

当前 SQLite schema / model 预留：
- 已有稳定 UUID：clipboard_items、item_assets、clipboard_item_files、groups、group_items 和 Swift model 均以 UUID 为主键 / 身份。
- 已有时间字段：clipboard_items.created_at / updated_at / last_used_at / pinned_at / last_edited_at，groups.created_at / updated_at，附件 / 文件引用 / 分组关系 created_at。
- 已有软删除预留：clipboard_items.is_deleted 存在，读取时过滤 is_deleted = 0。
- 已有来源信息：source_app_name、source_bundle_id、source_icon_name、source_icon_file_name。
- 已有附件表 item_assets；图片 / 富文本附件独立于 SQLite 大字段保存。
- 已有文件引用表 clipboard_item_files；记录路径、顺序、名称、类型、大小、目录 / alias、path_status 和 last_checked_at。
- 已有分组关系表 group_items，当前 UNIQUE(item_id) 保持单分组，未来可扩展多分组 / 标签。

同步前 schema / model 缺口：
- updated_at 当前不足以表达逐字段变更；缺少 per-field modified time / change version。
- is_deleted 不是完整 tombstone；缺少 deleted_at、deleted_by_device_id、保留期限和远端清理策略。
- 缺少 device_id、origin_device_id、modified_by_device_id、本机安装实例 ID 和设备显示名。
- 缺少 sync state、zone change token、record change tag、server version、dirty flag 和断点恢复状态。
- ClipboardItem / Repository API 未暴露同步所需的 updatedAt / isDeleted / lastEditedAt / 增量变更接口。
- item_assets 缺少内容 hash、远端 asset id、上传状态、加密元数据和缓存状态。
- App icon 当前是本地缓存引用，首批应视为可重建缓存，不作为关键同步资产。
- 文件卡片路径是本机绝对路径，无 bookmark / 原文件副本，跨设备默认不可访问。

CloudKit / iCloud 方案候选：
- CloudKit private DB：推荐作为未来正式同步首选候选，适合结构化记录、增量变更和 CKAsset；缺点是需要 container / entitlement / record schema，并且 private DB 不等同于 App 自己实现端到端加密。
- iCloud Drive 文件：适合手动备份 / 迁移，不适合作为实时 SQLite 多设备同步；SQLite / WAL 并发同步和冲突副本风险高。
- 混合方案：CloudKit private DB 同步文本 / 元数据，未来再评估 CKAsset 或用户选择的附件策略；复杂度较高，但中长期较稳妥。

冲突策略候选：
- last-write-wins：简单，适合低价值偏好；不适合删除、附件、历史编辑和分组删除。
- field-level merge：未来主候选；需要字段级修改时间 / 操作元数据。
- append-only event log：最可审计，适合删除 / 移动 / 排序语义；实现成本最高，只建议后续高级 spike。
- 删除 tombstone 风险：过早清理会导致旧设备复活记录，永不清理会增加隐私和存储负担；Stage 10 不得把本机删除扩展为跨设备删除。

附件同步策略：
- 图片：首批只评估元数据 / 摘要，不默认上传图片二进制。
- 富文本：首批不做 RTF 上传下载；需先区分摘要同步、附件同步和富文本编辑冲突。
- App icon：首批不同步图标文件，优先由 bundle id / 系统信息重建。
- 文件卡片：第一批明确不上传原文件，不复制原文件到附件目录，不把原文件二进制放入 SQLite、CloudKit 或 iCloud Drive；最多同步原设备路径记录和文件摘要。

隐私 / 加密结论：
- 剪贴板历史默认高敏感，任何上传到 iCloud 必须显式 opt-in。
- CloudKit private DB 表示 Apple ID 私有数据库隔离，但不能包装成 App 级端到端加密承诺。
- 若要求端到端加密，必须另行设计客户端密钥、恢复、多设备密钥同步、换机和忘记密钥策略。
- 敏感内容遮罩是本机展示层能力，不等于上传前加密。

Stage 10 推荐产物：
- 风险矩阵。
- schema gap 清单。
- 同步数据字典。
- 用户确认问题。
- 后续 spike 拆分：CloudKit zone / record mapping、schema migration、conflict fixture、tombstone lifecycle、attachment CKAsset、privacy consent。

红线：
- 本阶段不得改 schema，不得新增 soft delete / device table / sync state table。
- 不得新增 CloudKit runtime、iCloud entitlements、CloudKit 容器、同步开关、设备筛选 UI。
- 不得实现附件上传下载、端到端加密、冲突合并或跨设备删除。
- 不得写业务代码。

交付摘要：Architecture Gatekeeper Agent 已补充 Stage 10 iCloud 同步预研架构方案；核对当前 SQLite schema / model 的同步预留和缺口，比较 CloudKit private DB、iCloud Drive 文件和混合方案，列出冲突策略、删除 tombstone、附件同步、隐私 / 加密、schema 红线和推荐 Stage 10 产物；本轮仅修改架构 / 计划 / runbook 文档，未修改业务代码，未运行构建。
```

## 196. Stage 10 iCloud 同步预研测试计划前置

```text
任务卡：V2-TESTPLAN-S10-ICLOUD-SYNC-PREFLIGHT-001
时间：2026-05-15
阶段：Stage 10 iCloud 同步预研测试计划前置
当前会话模式：ClipEase V2 Test Plan Agent
风险等级：高；涉及未来同步、CloudKit、隐私、附件、删除和冲突策略，但本轮只允许修改测试 / 计划文档，不写业务代码
修改范围：
- docs/V2_TEST_PLAN.md
- docs/V2_AGENT_RUNBOOK.md

核对文档：
- docs/V2_TEST_PLAN.md
- docs/V2_PRODUCT_PLAN.md
- docs/V2_TECHNICAL_PLAN.md
- docs/V2_DEVELOPMENT_PLAN.md
- docs/V2_AGENT_RUNBOOK.md

测试计划结论：PASS 进入 Stage 10 预研文档和后续 spike 设计；HOLD 任何 runtime 同步、CloudKit / iCloud 接入、schema / entitlement / UI / 附件 / 删除 / 加密实现。

preflight 测试目标：
- 验证“没有实现 runtime 同步”的红线：不得引入 CloudKit runtime、iCloud entitlement、CloudKit container、同步开关、设备筛选 UI、同步状态 UI、附件上传下载、冲突合并 runtime、端到端加密 runtime 或跨设备删除实现。
- 验证 Stage 10 文档产物完整性：产品边界、架构结论、风险矩阵、schema gap 清单、同步数据字典、用户确认问题和后续 spike 拆分必须齐备。
- 验证 schema gap 清单覆盖 device id、sync state、record version、tombstone、field modified time、asset hash / remote id、settings sync scope 和文件路径跨设备语义。
- 验证风险矩阵覆盖隐私、CloudKit 配额 / 失败、冲突、删除 tombstone、附件、文件路径跨设备、迁移、用户误解、离线恢复和账号状态。
- 验证用户确认问题覆盖同步范围、文件路径跨设备语义、附件是否暂缓、删除同步是否暂缓、设置是否同步和 E2EE 是否前置。

当前阶段禁止测试 / 实现：
- 不得要求真实 iCloud 账号跨设备同步。
- 不得改 schema，不得新增 schema version、soft delete / device / sync state table 或 sync 字段。
- 不得新增 CloudKit container、entitlement、record schema、runtime、同步 scheduler、账号监听、推送订阅或重试队列。
- 不得上传附件、图片、富文本、文件卡片原文件或文件路径指向内容。
- 不得显示同步 UI、设备筛选 UI、账号状态 UI、冲突 UI 或同步错误 UI。
- 不得实现端到端加密、密钥管理、冲突合并、跨设备删除、远端清理、附件下载或断点恢复。
- 不得恢复收藏 / 管理模式 / 多选 / 批量操作 / JSON runtime。

后续 spike 若获用户确认需测试：
- CloudKit container / entitlement 沙盒隔离。
- mock sync 上传 / 下载 / 重试 / 幂等 / 断点恢复。
- 冲突样本：文本编辑、置顶、分组重命名、移动分组、分组删除、设置修改、删除后旧设备上线。
- 附件策略样本：图片、富文本、App icon、文件卡片路径、路径失效、部分失效、多文件、超大附件和 hash 不一致。
- 隐私 / 敏感内容：密码、验证码、敏感 App、敏感遮罩、完整路径含用户名、内部 URL、图片 / 富文本敏感内容和 opt-in 文案。
- 失败恢复：网络断开、CloudKit 配额不足、权限拒绝、账号切换、zone 不存在、partial failure、change token 失效、重复上传、远端删除、迁移失败和本地数据库损坏。
- 离线 / 重复 / 时钟偏差：离线多次编辑、重复提交、设备时钟偏差、服务端时间不一致、重复 record 和过期 tombstone。

手工验收清单：
- 用户确认未来同步范围。
- 用户确认文件路径跨设备语义。
- 用户确认附件是否暂缓。
- 用户确认删除同步是否暂缓。
- 用户确认设置是否同步。
- 用户确认 E2EE 是否作为正式同步前置。
- 用户确认 Stage 10 当前无可见同步功能、无真实 iCloud 跨设备演示要求。

自动化脚本方向：
- 仅推荐后续静态 / 文档检查脚本方向，不在本轮实现脚本。
- 建议方向包括 docs 完整性、no CloudKit runtime、no schema change、no attachment upload 和 user questions 覆盖检查。

交付摘要：Test Plan Agent 已补充 Stage 10 iCloud 同步预研测试计划前置；明确 preflight 测试目标、当前阶段禁止项、后续 spike 测试维度、手工验收清单和推荐后续自动化脚本方向；本轮仅修改测试 / runbook 文档，未修改业务代码，未实现脚本，未运行构建。
```

## 197. Stage 10 iCloud 同步预研前置验收

```text
任务卡：V2-ACCEPT-S10-ICLOUD-SYNC-PREFLIGHT-001
时间：2026-05-15
阶段：Stage 10 iCloud 同步预研前置验收
当前会话模式：ClipEase V2 Acceptance Agent
风险等级：高；涉及未来 runtime 同步、CloudKit、entitlement、schema、隐私、附件和 UI，但本轮仅做 preflight 验收和文档记录
修改范围：
- docs/V2_AGENT_RUNBOOK.md

只读核对：
- docs/V2_AGENT_RUNBOOK.md
- docs/V2_DEVELOPMENT_PLAN.md
- docs/V2_PRODUCT_PLAN.md
- docs/V2_TECHNICAL_PLAN.md
- docs/V2_TEST_PLAN.md
- Sources/
- Resources/
- Package.swift

依据：
- Docs/Log `V2-DOCS-S10-PREFLIGHT-DISPATCH-001`：PASS，已调度 Stage 10 仅做 iCloud 同步预研前置，不写业务代码。
- Product `V2-PRODUCT-S10-ICLOUD-SYNC-PREFLIGHT-001`：PASS，已明确产品边界、暂缓范围、候选同步范围、隐私 / 附件 / 删除红线和用户确认问题。
- Architecture `V2-ARCH-S10-ICLOUD-SYNC-PREFLIGHT-001`：PASS，已明确 CloudKit private DB、iCloud Drive 文件同步、混合方案、schema gap、冲突 / tombstone / 附件 / 加密风险和后续 spike 拆分。
- Test Plan `V2-TESTPLAN-S10-ICLOUD-SYNC-PREFLIGHT-001`：PASS，已明确 preflight 测试目标、当前禁止项、后续 spike 测试维度和手工验收清单。

验收核对：
- Stage 10 preflight 产物完整：产品边界、架构结论、测试计划、禁止项、用户确认问题和后续 spike 拆分均已记录。
- 当前阶段仍 HOLD 任何 runtime 同步、CloudKit / iCloud 接入、entitlement、schema / soft delete / device / sync state 变更、record schema、同步 UI、设备筛选 UI、同步状态 UI、附件上传下载、端到端加密、冲突合并和跨设备删除实现。
- 业务代码扫描未发现 CloudKit / CKContainer / CKRecord / iCloud entitlement / 同步开关 / 设备筛选 UI / 同步状态 UI 的新增入口；`sync` 命中仅为本地焦点或选择状态同步命名，`ubiquitousItemDownloadingStatus` 属于 Stage 9 文件卡片 iCloud placeholder 只读状态检查，不构成同步 runtime。
- 本轮未运行构建；验收目标是 preflight 文档完整性和越界实现检查，不要求 runtime 测试。

验收裁定：PASS。

允许状态：
- 允许进入“用户确认 Stage 10 预研问题”状态。
- 用户确认前，不得进入任何 Stage 10 runtime 实现或 spike；即便进入 spike，也必须单独开卡并重新限定文件锁、测试边界和验收标准。

主控需向用户确认的关键问题：
- 是否接受 Stage 10 当前只产出预研结论，不提供任何用户可见同步功能，也不要求真实 iCloud 跨设备演示。
- 未来若进入正式同步，第一批是否只考虑文本 / 元数据 / 分组 / 置顶等轻量数据，继续暂缓附件、图片原件、富文本附件和文件原件。
- 文件卡片路径跨设备时，是否接受“仅保留原设备路径记录；本机不可访问时显示失效 / 需回原设备打开”的产品语义。
- 删除历史是否继续保持本机优先，暂不做跨设备删除同步；若未来允许跨设备删除，是否需要撤销、回收站或二次确认机制。
- 是否需要同步设置；如需要，哪些设置可同步，哪些必须保持本机私有。
- 是否要求端到端加密作为未来正式同步前置门槛；若要求，需先追加客户端密钥、恢复、多设备密钥同步、换机和忘记密钥策略 spike。
- 是否接受未来推荐方向以 CloudKit private DB 为首选候选，iCloud Drive 仅作为手动备份 / 迁移方向，混合方案留作中长期评估。

交付摘要：Acceptance Agent 完成 `V2-ACCEPT-S10-ICLOUD-SYNC-PREFLIGHT-001`；裁定 Stage 10 iCloud 同步预研 preflight PASS，允许进入用户确认 Stage 10 预研问题状态；继续 HOLD runtime 同步、CloudKit / iCloud 接入、entitlement、schema、record mapping、同步 UI、附件上传下载、端到端加密、冲突合并和跨设备删除实现。本轮仅追加 `docs/V2_AGENT_RUNBOOK.md`，未修改业务代码，未运行构建。
```

## 198. Stage 10 iCloud 同步预研用户确认记录

```text
任务卡：V2-DOCS-S10-USER-CONFIRMATION-001
时间：2026-05-15
阶段：Stage 10 iCloud 同步预研用户确认记录
当前会话模式：ClipEase V2 Docs/Log Agent
风险等级：高；涉及未来 runtime 同步、CloudKit / iCloud 接入、entitlement、schema、同步 UI、附件、冲突、删除和端到端加密，但本轮仅允许修改文档
修改范围：
- docs/V2_AGENT_RUNBOOK.md

用户确认：
- Stage 10 第一批继续只做预研，不做任何用户可见同步功能。
- 未来同步范围候选先限定为历史条目、分组、置顶状态、少量设置。
- 文件卡片只同步“路径历史”，不上传原文件；跨设备路径不可用时只显示不可用状态。
- 图片 / 富文本附件在第一轮正式同步中暂缓。
- 删除同步暂缓，不做跨设备删除传播。
- 设置同步范围只评估少量低风险设置，不同步隐私敏感配置。
- 端到端加密作为未来正式同步前置门槛。
- CloudKit private database 作为未来首选候选方案。

继续 HOLD：
- HOLD 任何 runtime 同步实现。
- HOLD 任何 CloudKit / iCloud 接入。
- HOLD 任何 entitlement、CloudKit container、record schema 或账号状态接入。
- HOLD 任何 SQLite schema 迁移、sync state / device / tombstone / record version 字段或表。
- HOLD 任何同步 UI、设备筛选 UI、同步状态 UI、冲突 UI 或同步错误 UI。
- HOLD 任何附件上传下载、图片 / 富文本附件同步、文件卡片原文件上传下载或 CKAsset 实现。
- HOLD 任何冲突合并、跨设备删除传播、远端清理、端到端加密 runtime、密钥管理或同步调度实现。

主控后续调度：
- 主控将继续调度 Stage 10 三个只读预研产物：风险矩阵、schema gap、同步数据字典。
- 上述产物仅允许修改文档，不得写业务代码，不得改 schema，不得新增 entitlement，不得接入 CloudKit / iCloud runtime。

交付摘要：Docs/Log Agent 已记录 Stage 10 关键问题的用户确认结论；Stage 10 继续限定为只读预研阶段，未来首选候选为 CloudKit private database，正式同步前置门槛包含端到端加密；主控后续仅调度风险矩阵、schema gap、同步数据字典三个只读预研产物。
```

## 199. Stage 10 iCloud 同步风险矩阵

```text
任务卡：V2-S10-ICLOUD-RISK-MATRIX-001
时间：2026-05-15
阶段：Stage 10 iCloud 同步预研 - 风险矩阵
当前会话模式：ClipEase V2 Stage 10 Risk Matrix Agent
风险等级：高；涉及未来 runtime 同步、CloudKit / iCloud 接入、entitlement、schema、同步 UI、附件、冲突、删除、端到端加密和用户信任，但本轮仅允许修改文档
修改范围：
- docs/V2_S10_ICLOUD_RISK_MATRIX.md
- docs/V2_TECHNICAL_PLAN.md
- docs/V2_DEVELOPMENT_PLAN.md
- docs/V2_AGENT_RUNBOOK.md

用户确认边界：
- Stage 10 只做预研，不提供任何用户可见同步能力。
- CloudKit private database 是未来正式同步首选候选方案。
- E2EE 是正式同步前置门槛。
- 附件 / 图片 / 富文本附件同步暂缓。
- 删除同步暂缓。
- 文件卡片只同步路径历史，不上传原文件。

风险矩阵覆盖：
- 隐私 / 敏感内容 / 用户信任。
- iCloud 可用性、账号状态、配额、网络离线。
- CloudKit schema / record 演进。
- 冲突与时钟偏差。
- 删除同步 / tombstone。
- 附件 / 图片 / 富文本 / 文件路径历史。
- 多设备重复记录 / 去重。
- 备份恢复与同步状态交叉。
- 性能 / 大量历史。
- 回滚 / 关闭同步 / 数据残留。
- 法务 / 用户告知 / 默认关闭。

矩阵字段：
- 风险描述。
- 影响。
- 概率。
- 严重度。
- 触发条件。
- 缓解策略。
- 是否阻塞正式同步。
- 所需测试。

结论：
- PASS 产出 `docs/V2_S10_ICLOUD_RISK_MATRIX.md`。
- HOLD 任何正式同步、CloudKit runtime、entitlement、record schema、SQLite schema 迁移、同步 UI、附件上传下载、跨设备删除传播、冲突合并 runtime 和端到端加密 runtime。

阻塞正式同步的核心项：
- 隐私 / 敏感内容 / 用户信任。
- iCloud 可用性 / 账号状态 / 配额 / 离线。
- CloudKit schema / record 演进。
- 冲突与时钟偏差。
- 删除 tombstone。
- 附件 / 图片 / 富文本 / 文件路径历史。
- 备份恢复与同步状态交叉。
- 回滚 / 关闭同步 / 数据残留。
- 法务 / 用户告知 / 默认关闭。

条件阻塞项：
- 多设备重复记录 / 去重。
- 性能 / 大量历史。

交付摘要：Stage 10 Risk Matrix Agent 已新增 iCloud 同步风险矩阵文档，并在技术计划、开发计划和 runbook 中追加索引与门禁摘要；本轮仅修改文档，未修改业务代码，未新增 CloudKit runtime、entitlement、record schema、SQLite schema 迁移、同步 UI、附件上传下载、删除同步、冲突合并或 E2EE runtime。
```

## 200. Stage 10 iCloud 同步 Schema Gap 清单

```text
任务卡：V2-S10-ICLOUD-SCHEMA-GAP-001
时间：2026-05-15
阶段：Stage 10 iCloud 同步预研 - Schema gap 清单
当前会话模式：ClipEase V2 Stage 10 Schema Gap Agent
风险等级：高；涉及未来 runtime 同步、CloudKit / iCloud 接入、entitlement、schema、同步 UI、附件、冲突、删除、端到端加密和用户信任，但本轮仅允许修改文档
修改范围：
- docs/V2_S10_SCHEMA_GAP.md
- docs/V2_TECHNICAL_PLAN.md
- docs/V2_DEVELOPMENT_PLAN.md
- docs/V2_AGENT_RUNBOOK.md

只读核对范围：
- Sources/ClipEase/Core/Models/ClipboardItem.swift
- Sources/ClipEase/Core/Models/ClipboardGroup.swift
- Sources/ClipEase/Core/Storage/SQLiteClipboardStore.swift
- Sources/ClipEase/Core/Storage/ClipboardHistoryStore.swift
- Sources/ClipEase/Core/Storage/ClipboardHistoryPersistence.swift
- docs/V2_TECHNICAL_PLAN.md
- docs/V2_DEVELOPMENT_PLAN.md
- docs/V2_AGENT_RUNBOOK.md
- docs/V2_S10_ICLOUD_RISK_MATRIX.md

当前已具备：
- 稳定 UUID：item、group、asset、file reference 和 group item 均有 UUID 基础。
- 时间字段：已有 createdAt / updatedAt 预留，以及 pinnedAt、groupedAt、附件 / 文件引用 createdAt 等。
- 分组和置顶：已有 groupID / group_items、isPinned / pinnedAt。
- 来源 App：已有 sourceAppName、sourceBundleID、iconName、iconFileName。
- 附件和文件引用：已有 item_assets、clipboard_item_files、图片 / 富文本附件路径、文件卡片路径和 pathStatus。
- 删除预留：SQLite 有 is_deleted，加载时过滤 is_deleted = 0，但当前删除路径仍不是完整 tombstone。

Schema gap 覆盖：
- soft delete / tombstone、deletedAt、删除来源设备、保留期限和远端清理。
- deviceID、originDeviceID、modifiedByDeviceID、deletedByDeviceID 和设备显示名。
- sync version / vector clock、record change tag / server version、remote record id / zone id。
- sync state / dirty flag、zone change token / sync cursor、断点恢复状态。
- field-level modified metadata、conflict status。
- attachment manifest、attachment checksum、remote asset id、upload / cache state。
- encryption metadata：加密版本、key id、nonce / salt、算法版本和密文校验。
- settings sync scope。
- file path availability per device。

每个 gap 已说明：
- 用途。
- 当前影响。
- 是否必须在正式同步前补。
- schema 变更风险。
- 迁移 / 备份影响。
- 测试要求。

文件卡片路径历史结论：
- 文件卡片未来最多同步路径历史和摘要。
- 不上传原文件，不复制原文件到附件目录，不把原文件二进制放入 SQLite、CloudKit 或 iCloud Drive。
- 跨设备默认显示原设备路径 / 本机不可访问语义，除非本机重新检查确认路径可访问。
- 相同绝对路径不等于同一文件；未设计 checksum / file id / 用户确认策略前，不得自动视为可打开。
- 文件路径可能暴露用户名、项目名、客户名或内部目录结构，未来同步数据字典必须标为敏感字段并纳入 E2EE 范围。

结论：
- PASS 产出 docs/V2_S10_SCHEMA_GAP.md。
- HOLD 任何新增表 / 字段 / schema version / migration。
- HOLD 任何业务代码、CloudKit runtime、entitlement、record schema、同步 UI、设备筛选 UI、同步状态 UI。
- HOLD 任何附件上传下载、文件原件上传、跨设备删除传播、冲突合并 runtime 或 E2EE runtime。

交付摘要：Stage 10 Schema Gap Agent 已新增 iCloud 同步 schema gap 清单文档，并在技术计划、开发计划和 runbook 中追加索引与门禁摘要；本轮仅修改文档，未修改业务代码，未新增或修改 SQLite schema / migration / runtime。
```

## 201. Stage 10 iCloud 同步数据字典

```text
任务卡：V2-S10-ICLOUD-SYNC-DATA-DICTIONARY-001
时间：2026-05-15
阶段：Stage 10 iCloud 同步预研 - 同步数据字典 / 用户语义
当前会话模式：ClipEase V2 Stage 10 Sync Data Dictionary Agent
风险等级：高；涉及未来 runtime 同步、CloudKit / iCloud 接入、entitlement、schema、同步 UI、附件、冲突、删除、端到端加密和用户信任，但本轮仅允许修改文档
修改范围：
- docs/V2_S10_SYNC_DATA_DICTIONARY.md
- docs/V2_PRODUCT_PLAN.md
- docs/V2_TECHNICAL_PLAN.md
- docs/V2_DEVELOPMENT_PLAN.md
- docs/V2_AGENT_RUNBOOK.md

用户确认边界：
- Stage 10 只做预研，不提供任何用户可见同步能力。
- CloudKit private database 是未来正式同步首选候选方案。
- E2EE 是正式同步前置门槛。
- 附件 / 图片 / 富文本附件同步暂缓。
- 删除同步暂缓。
- 文件卡片只同步路径历史，不上传原文件。

数据字典覆盖：
- 历史条目：text / link / color / image / richText / file。
- 分组、置顶状态、保存期限 / 少量设置、忽略 App / 敏感遮罩配置。
- 图片附件、富文本附件、App icon、文件卡片路径历史、原文件副本。
- 来源 App 信息、时间戳、搜索派生数据、缩略图 / 缓存、备份包状态。

每类字段已说明：
- 是否候选同步。
- 是否第一轮正式同步候选。
- 用户可见语义。
- 隐私等级。
- 跨设备可用性。
- 冲突策略候选。
- 是否需要 E2EE。
- 是否需要 schema gap 支持。
- 测试要求。

首轮正式同步候选：
- 历史条目：text / link / color 可作为首轮核心候选；image / richText 仅评估记录元数据 / 摘要，附件暂缓；file 只同步路径历史和摘要。
- 分组。
- 置顶状态。
- 保存期限 / 少量低风险设置。

明确暂缓或不同步：
- 图片附件和富文本附件暂缓。
- 原文件副本不上传，不复制到 CloudKit，不复制到 iCloud Drive，不写入 SQLite。
- 文件卡片只同步路径历史，不上传原文件；跨设备路径不可用只显示不可用 / 原设备路径状态。
- 忽略 App / 敏感遮罩配置默认不作为首轮同步，需用户单独确认。
- 搜索索引、缩略图、App icon 缓存、运行缓存和备份包状态不作为同步数据。

结论：
- PASS 产出 docs/V2_S10_SYNC_DATA_DICTIONARY.md。
- HOLD 任何业务代码、SQLite schema / migration、CloudKit / iCloud runtime、entitlement、同步 UI、设备筛选 UI、同步状态 UI。
- HOLD 任何附件上传下载、图片 / 富文本附件同步、文件原件上传、原文件副本同步或 CKAsset 实现。
- HOLD 任何跨设备删除传播、冲突合并 runtime、端到端加密 runtime、密钥管理或同步调度实现。

交付摘要：Stage 10 Sync Data Dictionary Agent 已新增未来同步数据字典和用户语义说明，并在产品计划、技术计划、开发计划和 runbook 中追加索引与门禁摘要；本轮仅修改文档，未修改业务代码，未新增同步 UI / runtime / schema。
```

## 202. Stage 10 iCloud 同步预研产物收口验收

```text
任务卡：V2-ACCEPT-S10-ICLOUD-PREFLIGHT-ARTIFACTS-001
时间：2026-05-15 15:12:21 CST
阶段：Stage 10 iCloud 同步预研产物收口
当前会话模式：ClipEase V2 Acceptance Agent
风险等级：高；涉及未来 runtime 同步、CloudKit / iCloud 接入、entitlement、schema、同步 UI、附件、冲突、删除、端到端加密和用户信任，但本轮仅允许验收文档产物并追加 runbook 记录
修改范围：
- docs/V2_AGENT_RUNBOOK.md

验收依据：
- 用户已确认 Stage 10 关键问题，按建议确认。
- V2-S10-ICLOUD-RISK-MATRIX-001 PASS。
- V2-S10-ICLOUD-SCHEMA-GAP-001 PASS。
- V2-S10-ICLOUD-SYNC-DATA-DICTIONARY-001 PASS。

验收核对：
- docs/V2_S10_ICLOUD_RISK_MATRIX.md 存在，并覆盖隐私 / 敏感内容 / 用户信任、iCloud 可用性 / 账号 / 配额 / 离线、CloudKit schema / record 演进、冲突与时钟偏差、删除 tombstone、附件 / 图片 / 富文本 / 文件路径历史、多设备重复记录 / 去重、备份恢复与同步状态交叉、性能 / 大量历史、回滚 / 关闭同步 / 数据残留、法务 / 用户告知 / 默认关闭。
- docs/V2_S10_SCHEMA_GAP.md 存在，并覆盖 tombstone / deletedAt、device / origin / modified / deleted device、sync version / record change tag / remote id / sync state / zone cursor、field-level metadata、conflict status、attachment manifest / checksum / remote asset / upload state、encryption metadata、settings sync scope 和 file path availability per device。
- docs/V2_S10_SYNC_DATA_DICTIONARY.md 存在，并逐类说明是否候选同步、是否第一轮正式同步候选、用户可见语义、隐私等级、跨设备可用性、冲突策略候选、是否需要 E2EE、是否需要 schema gap 支持和测试要求。
- 静态扫描 Sources / Resources / Package.swift 未发现 CloudKit import、CKContainer、CKRecord、CKDatabase、CKAsset、iCloud entitlement、CloudKit container 或用户可见同步开关 / 设备筛选 UI / 同步状态 UI 的新增入口；sync 命中为本地焦点 / 选择状态同步和异步保存命名，不构成 iCloud runtime。

裁定：
- PASS：三个 Stage 10 docs-only 预研产物完整，可作为 Stage 10 用户审阅材料。
- HOLD：继续 HOLD 所有 runtime/schema/UI/CloudKit/附件上传/冲突合并/E2EE 实现。
- 允许进入“等待用户审阅 Stage 10 预研文档 / 决定下一步 spike”状态。

非阻塞 backlog 建议：
- 后续可单独开卡补 `verify_stage10_icloud_preflight_docs.py` 静态文档完整性检查。
- 后续可单独开卡补 `verify_stage10_no_cloudkit_runtime.py`、`verify_stage10_no_schema_change.py`、`verify_stage10_no_attachment_upload.py` 静态红线检查。
- 后续 spike 建议按 CloudKit record mapping、Tombstone lifecycle、Device identity、Conflict fixture、Attachment manifest、File path availability、E2EE metadata、Backup x sync 拆分，不得混入正式 runtime 实现。

交付摘要：Acceptance Agent 完成 `V2-ACCEPT-S10-ICLOUD-PREFLIGHT-ARTIFACTS-001` 收口验收；裁定 Stage 10 三个 docs-only 预研产物完整并 PASS，允许进入等待用户审阅 Stage 10 预研文档 / 决定下一步 spike 状态；继续 HOLD runtime、schema、UI、CloudKit / iCloud 接入、附件上传、冲突合并和 E2EE 实现。本轮仅追加 `docs/V2_AGENT_RUNBOOK.md`，未修改业务代码，未运行构建。
```

## 203. 维修阶段第一批用户反馈分诊与调度记录

```text
任务卡组：V2-MAINT-BATCH1-20260515
时间：2026-05-15
阶段：维修阶段 / Stage 9 用户人工验收后回归修复
当前会话模式：ClipEase V2 Main Controller Agent
主控边界：主控只记录、分诊、定级、发放文件锁和调度 Agent；不亲自写业务代码、不亲自修 bug。

用户反馈：
1. 系统内复制、剪切内容都必须记录，避免遗漏。
2. 搜索框展开时，搜索框内部、筛选按钮、筛选面板、清空按钮点击不收起；只有点击外部区域才收起并清空。
3. 预览卡片时，预览窗口左右偏移跳动。
4. 筛选面板内容选中后背景色应为蓝色。
5. 新剪切板卡片加入后，无论主窗口开关状态都默认选中新卡片；打开状态滚动到新卡片，无置顶时位于第一位并保留左侧间距，有置顶 / 前置时位于置顶右侧第一位并露出上一张约 1/6。
6. 主窗口左右边缘未完整显示卡片点击后，应动画平移到完整显示并额外露出下一张约 1/6。
7. 优化主窗口弹出 / 关闭、搜索框展开 / 关闭、预览框展开 / 关闭、卡片平移动画，降低卡顿和掉帧。
8. 全局提示层改为正方形，接近系统提示词视觉。
9. 筛选面板展开后左右偏移跳动。
10. 颜色与图标面板展开后左右偏移跳动。
11. 所有卡片支持拖动到其他 App；文本 / 颜色 / URL 以文本形式拖入；文件 / 多文件以文件形式拖入，不支持文件时粘贴“路径+文件名”文本，多文件每行一个。

分诊结论：
- 1 属于剪贴板捕获核心路径，高风险；先交 Clipboard / Architecture Bugfix Agent 定点修复，若涉及数据模型或 Repository 语义升级，必须回到主控升级架构门禁。
- 2、4、9、10 属于搜索 / 面板点击和定位 bug，中风险；交 UI Bugfix Agent。
- 3、5、6、7、8 属于主窗口 / 预览 / 动画 / toast 交互一致性，高风险；交 UI Interaction Agent 串行处理。
- 11 属于 drag-out 能力扩展，高风险；交 File Drag Bugfix Agent，禁止改变 pasteboard copy / paste 既有语义。

风险等级：
- 总体高风险：触及 ClipboardMonitor、HistoryWindowView、HistoryPreviewWindowController、HistoryCardView、GlobalStatusToastController 等主窗口核心交互与剪贴板通道。
- 无红线：本批不要求删除附件、清空 SQLite、导入备份、数据迁移、恢复 JSON、恢复收藏 / 管理模式、多选 / 批量、修改保存期限 / 分组删除逻辑、修改构建脚本或发布流程。
- 构建运行：修复通过 Test / Review / Acceptance 后，若需要打包运行且涉及修改版本号，按红线规则单独确认或使用当前允许的本地运行方式。

关联守卫：
- GUARD-V2-BASELINE-001：SQLite-only，不得恢复 JSON runtime / migration fallback。
- GUARD-V2-BASELINE-002：不得恢复收藏、管理模式、多选、批量操作。
- GUARD-V2-GROUP-001：不得破坏分组、置顶、搜索、备份导入安全和单条操作。
- GUARD-V2-SEARCH-001：搜索框、筛选 token、筛选 popover、Esc 和外部点击层级不得回归。
- GUARD-V2-UI-001：顶部搜索 / 分组轨道不得回归。
- Stage 9 文件卡片守卫：文件卡片、Quick Look、文件 pasteboard、文件拖出、fallback 文本路径能力不得因本批修复删除。

文件锁：
- Sources/ClipEase/Features/ClipboardMonitor/ClipboardMonitor.swift：Clipboard / Architecture Bugfix Agent，任务卡 V2-BUGFIX-MAINT-CLIPBOARD-CAPTURE-001。
- Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift：UI Interaction Agent，任务卡 V2-BUGFIX-MAINT-HISTORY-INTERACTION-STABILITY-001。
- Sources/ClipEase/Features/HistoryWindow/HistoryPreviewWindowController.swift：UI Interaction Agent，任务卡 V2-BUGFIX-MAINT-HISTORY-INTERACTION-STABILITY-001。
- Sources/ClipEase/Features/HistoryWindow/HistoryPreviewPopoverView.swift：UI Interaction Agent，任务卡 V2-BUGFIX-MAINT-HISTORY-INTERACTION-STABILITY-001。
- Sources/ClipEase/Features/HistoryWindow/GlobalStatusToastController.swift：UI Interaction Agent，任务卡 V2-BUGFIX-MAINT-HISTORY-INTERACTION-STABILITY-001。
- Sources/ClipEase/Features/HistoryWindow/HistoryCardView.swift：File Drag Bugfix Agent，任务卡 V2-BUGFIX-MAINT-ALL-CARD-DRAGOUT-001。
- Sources/ClipEase/Features/PasteExecutor/PasteExecutor.swift：File Drag Bugfix Agent 只读 / 必要时最小修改，任务卡 V2-BUGFIX-MAINT-ALL-CARD-DRAGOUT-001。

禁止修改：
- 不得恢复收藏 / 管理模式 / 多选 / 批量操作。
- 不得恢复 JSON Repository、JSON migration runtime 或 JSON fallback。
- 不得改 SQLite schema、执行数据迁移、清空数据库、删除附件。
- 不得修改构建脚本、发布流程、保存期限清理逻辑、分组删除逻辑。
- 不得删除 Stage 9 文件卡片 / Quick Look / pasteboard / fallback / drag-out 已完成功能。

任务卡 1：
- ID：V2-BUGFIX-MAINT-CLIPBOARD-CAPTURE-001
- 负责 Agent：Clipboard / Architecture Bugfix Agent
- 目标：修复系统内复制 / 剪切内容记录遗漏，确保支持现有类型 text / link / color / image / richText / file 的记录路径不被遗漏。
- 完成标准：明确遗漏类型与根因；修复后复制和剪切均可触发记录；不记录 ClipEase 自身 paste / copy 跳过项；不新增 JSON 或 schema 路径。
- 必须验证：复制文本、剪切文本、复制链接、复制图片、复制文件 / 多文件、ClipEase 自身复制跳过、`swift build`。

任务卡 2：
- ID：V2-BUGFIX-MAINT-HISTORY-INTERACTION-STABILITY-001
- 负责 Agent：UI Interaction Agent
- 目标：修复搜索外部点击、筛选 / 颜色图标 popover 跳动、预览窗口跳动、新卡片定位、边缘卡片平移、动画掉帧和 square toast 视觉。
- 完成标准：搜索内部点击不关闭；外部点击关闭并清空；筛选选中为蓝色；预览 / 筛选 / 颜色图标面板打开位置稳定；新卡片定位符合置顶 / 非置顶规则；边缘卡片点击带动画平移；toast 为近似系统提示词的正方形视觉；动画不引入明显卡顿。
- 必须验证：关联用户 2-10 的失败路径、GUARD-V2-SEARCH-001、GUARD-V2-UI-001、no favorite / no management 静态检查、`swift build`。

任务卡 3：
- ID：V2-BUGFIX-MAINT-ALL-CARD-DRAGOUT-001
- 负责 Agent：File Drag Bugfix Agent
- 目标：所有卡片支持拖动到其他 App；文本 / 颜色 / URL 以文本拖出；文件 / 多文件优先以 file URL 拖出，不支持文件接收时提供路径文本 fallback。
- 完成标准：不破坏普通点击、右键菜单、滚轮、预览和文件既有拖出；文件多文件路径文本 fallback 每行一个；无有效文件时使用路径 / 文件名文本；支持文本 / 颜色 / URL 的文本拖出。
- 必须验证：text/color/link/file/multi-file drag source、无效文件 fallback、Stage 9 文件拖出脚本、`swift build`。

后续门禁：
- 修复完成后必须调度 Test Agent 回归原失败路径和关联守卫。
- Test PASS 后调度 Review Agent 做阻塞风险审查。
- Review PASS 后调度 Acceptance Agent 放行。
- Acceptance PASS 后主控再构建 / 运行 App 给用户测试。
```

## 204. 维修阶段第一批实现 Agent 完成记录

```text
任务卡组：V2-MAINT-BATCH1-20260515
时间：2026-05-15
阶段：维修阶段 / 第一批实现完成
当前会话模式：ClipEase V2 Main Controller Agent

实现 Agent 结果：

1. V2-BUGFIX-MAINT-CLIPBOARD-CAPTURE-001
- 负责 Agent：Clipboard / Architecture Bugfix Agent
- 状态：needs_review
- 修改文件：
  - Sources/ClipEase/Features/ClipboardMonitor/ClipboardMonitor.swift
  - Sources/ClipEase/Core/Storage/ClipboardHistoryStore.swift
- 交付摘要：调整 pasteboard 读取顺序为 file URL -> RTF rich text -> image -> HTML rich text -> plain string；补齐富文本读取路径；保留 ClipEase 自身 copy / paste skip 逻辑，避免自我重复记录。
- 已验证：
  - python3 scripts/verify_stage9_file_capture_first_batch.py：PASS
  - python3 scripts/verify_stage9_file_pasteboard_first_batch.py：PASS
  - python3 scripts/verify_stage9_file_paste_fallback.py：PASS
- 未验证：真实 App 手动复制 / 剪切文本、链接、图片、单文件、多文件、ClipEase 自身复制跳过。
- 备注：Agent 的首次 `swift build` 后续被并行 UI / Drag 未完成改动干扰；最终统一门禁需重跑。

2. V2-BUGFIX-MAINT-HISTORY-INTERACTION-STABILITY-001
- 负责 Agent：UI Interaction Agent
- 状态：completed
- 修改文件：
  - Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift
  - Sources/ClipEase/Features/HistoryWindow/HistoryPreviewWindowController.swift
  - Sources/ClipEase/Features/HistoryWindow/GlobalStatusToastController.swift
- 交付摘要：修复搜索内部点击不收起、筛选选中蓝色、筛选 / 颜色图标 popover 固定尺寸、预览窗口稳定尺寸、新卡片 / 边缘卡片滚动定位、动画时长和 square toast。
- 已验证：
  - swift build：PASS
  - python3 scripts/verify_no_management_no_favorite_ui.py：PASS
  - git diff --check 允许修改文件：PASS
- 未验证：真实 App 手动验证用户反馈 2-10、多屏位置、动画手感、中文输入法 / token / Esc 运行态。

3. V2-BUGFIX-MAINT-ALL-CARD-DRAGOUT-001
- 负责 Agent：File Drag Bugfix Agent
- 状态：completed
- 修改文件：
  - Sources/ClipEase/Features/HistoryWindow/HistoryCardView.swift
- 交付摘要：所有卡片挂载统一 AppKit drag source；text / color / link 以 string 拖出；file / multi-file 优先 file URL 并同时提供文本 fallback；无有效文件 URL 时只拖出路径 / 文件名文本。
- 已验证：
  - swift build：PASS
  - python3 scripts/verify_stage9_file_dragout_first_batch.py：PASS
  - git diff --check -- Sources/ClipEase/Features/HistoryWindow/HistoryCardView.swift：PASS
- 未验证：真实 App 拖到外部应用的运行态兼容性。

统一门禁要求：
- Test Agent 必须覆盖用户反馈 1-11 的原失败路径。
- Review Agent 必须重点审查 pasteboard 类型优先级、skip 自我记录、搜索外部点击命中区、popover 锚点稳定、滚动定位状态、drag pasteboard 类型和 Stage 9 文件能力回归。
- Acceptance Agent 仅能在 Test / Review 均 PASS 后放行。
- Acceptance PASS 前不得构建运行给用户做人工测试。
```

## 205. 维修阶段第一批 Test / Review HOLD 与返工调度

```text
任务卡组：V2-MAINT-BATCH1-20260515
时间：2026-05-15
阶段：维修阶段 / 第一批门禁 HOLD
当前会话模式：ClipEase V2 Main Controller Agent

Test Agent 结果：HOLD / needs_fix

已通过：
- swift build：PASS
- git diff --check：PASS
- scripts/verify_stage9_file_capture_first_batch.py：PASS
- scripts/verify_stage9_file_pasteboard_first_batch.py：PASS
- scripts/verify_stage9_file_paste_fallback.py：PASS
- scripts/verify_stage9_file_dragout_first_batch.py：PASS
- scripts/verify_no_management_no_favorite_ui.py：PASS
- scripts/smoke_check.py：PASS
- scripts/verify_sqlite_only_baseline.py：PASS
- scripts/verify_stage9_quicklook_interaction.py：PASS
- scripts/verify_stage9_quicklook_spike.py：PASS
- scripts/verify_group_focus_and_menu_guard.py：PASS
- scripts/verify_history_selection_focus.py：PASS
- scripts/verify_move_to_group_menu_stability.py：PASS
- scripts/verify_stage9_file_basic_actions.py：PASS
- scripts/verify_stage9_file_card_data_foundation.py：PASS
- scripts/verify_stage9_file_card_display.py：PASS
- scripts/verify_stage9_file_card_ui.py：PASS
- scripts/verify_history_shortcut_commands.py：PASS
- scripts/verify_retention_valid_group_ids.py：PASS

阻塞失败：
1. scripts/verify_history_window_interaction_toast.py：FAIL
   - 失败信息：cards, empty states, and toolbar regions should close search on outside click。
   - 返工要求：SearchOutsideMouseDownObserver 覆盖卡片区、空状态、toolbar 等外部区域；搜索框内部、筛选按钮、筛选面板、清空按钮仍不得触发外部关闭。
2. scripts/verify_history_card_scroll_alignment.py：FAIL
   - 失败信息：leading peek must account for inter-card spacing。
   - 返工要求：新卡片 / 边缘卡片滚动公式必须使用 horizontalCardSpacing + leadingPeek / trailingPeek，满足无置顶、置顶、左右边缘和 1/6 peek 规则。

Review Agent 结果：HOLD / blocked

阻塞项：
1. P0：Sources/ClipEase/Features/HistoryWindow/GlobalStatusToastController.swift 是未跟踪新文件，但 HistoryWindowView 已引用；合入或归档时必须确保该新源文件纳入版本控制视角。
2. P1：Resources/Info.plist 存在版本号 / build 号改动，版本号修改属于红线；当前维修批次不得继续扩大版本号 / 构建脚本 / 发布流程改动。该项疑似历史 release/build 变更，主控不得擅自回退，后续 release/build 前需要用户确认或独立归档。

非阻塞风险：
- richText 重复捕获 guard 仍偏弱，后续可独立补充。
- 多文件 drag fallback 文本在部分目标 App 中可能被重复消费，需要真实外部 App 兼容性矩阵。
- 多屏 / 屏幕边缘固定尺寸面板和 square toast 仍需人工验证。

主控裁定：
- 暂停 Acceptance，不构建运行给用户测试。
- 返工只针对两个 Test 阻塞失败，交回 UI Interaction Agent。
- GlobalStatusToastController.swift 未跟踪问题进入最终集成 / 合入门禁，当前不由返工 Agent 处理 git staging。
- Resources/Info.plist 版本号红线作为历史发布边界遗留记录；不回退、不继续修改，后续需要单独确认。

返工任务卡：
- ID：V2-BUGFIX-MAINT-HISTORY-INTERACTION-STABILITY-001-REWORK
- 负责 Agent：UI Interaction Agent
- 允许修改：
  - Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift
- 禁止修改：
  - ClipboardMonitor.swift、ClipboardHistoryStore.swift、HistoryCardView.swift、GlobalStatusToastController.swift、HistoryPreviewWindowController.swift、Resources/Info.plist、构建脚本、SQLite schema、JSON / favorite / management 相关代码。
- 完成标准：
  - scripts/verify_history_window_interaction_toast.py：PASS
  - scripts/verify_history_card_scroll_alignment.py：PASS
  - swift build：PASS
  - git diff --check：PASS
  - 搜索内部点击和筛选面板点击不得回归。
  - 卡片滚动 peek 符合用户要求：新卡片和边缘卡片定位需保留左侧间距或露出上一张 / 下一张约 1/6，并把卡片间距纳入计算。

后续：
- Rework PASS 后重新调度 Test Agent 复测失败脚本 + 关键回归。
- 再调度 Review Agent 复审阻塞项。
- 再调度 Acceptance Agent。
```

## 206. 维修阶段第一批返工复测 / 复审记录

```text
任务卡组：V2-MAINT-BATCH1-20260515
时间：2026-05-15
阶段：维修阶段 / 第一批返工后门禁
当前会话模式：ClipEase V2 Main Controller Agent

返工任务：
- V2-BUGFIX-MAINT-HISTORY-INTERACTION-STABILITY-001-REWORK
- 负责 Agent：UI Interaction Agent
- 修改文件：
  - Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift
- 修复内容：
  - 补充卡片区、空状态和窗口内容根区域的 SearchOutsideMouseDownObserver 覆盖，确保 toolbar 等外部区域点击关闭并清空搜索。
  - 调整新卡片 / 边缘卡片定位公式，把 horizontalCardSpacing 纳入 leading / trailing peek 计算，满足 1/6 peek + 卡片间距规则。
- 自测：
  - python3 scripts/verify_history_window_interaction_toast.py：PASS
  - python3 scripts/verify_history_card_scroll_alignment.py：PASS
  - swift build：PASS
  - git diff --check -- Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift：PASS

Test Agent 复测：
- 任务卡：V2-TEST-MAINT-BATCH1-RETEST-20260515
- 结论：PASS，可进入 Review。
- 已执行并通过：
  - python3 scripts/verify_history_window_interaction_toast.py
  - python3 scripts/verify_history_card_scroll_alignment.py
  - swift build
  - git diff --check
  - python3 scripts/verify_no_management_no_favorite_ui.py
  - python3 scripts/verify_sqlite_only_baseline.py
  - python3 scripts/verify_stage9_file_capture_first_batch.py
  - python3 scripts/verify_stage9_file_pasteboard_first_batch.py
  - python3 scripts/verify_stage9_file_paste_fallback.py
  - python3 scripts/verify_stage9_file_dragout_first_batch.py
  - python3 scripts/verify_stage9_quicklook_interaction.py
- 未执行：真实 App 手动测试，由 Acceptance / 用户人工验收覆盖。

Review Agent 复审：
- 任务卡：V2-REVIEW-MAINT-BATCH1-REREVIEW-20260515
- 结论：can_enter_acceptance，未发现新的 P0 / P1 阻塞。
- 已确认：
  - 两个 Test 阻塞项已解除。
  - swift build：PASS
  - git diff --check：PASS
  - 未发现 JSON runtime / favorite / management 恢复。
  - 未发现分组 / 置顶 / 搜索定位被本次返工破坏的阻塞风险。
- 仍需 Acceptance / 用户人工验证：
  - 复制 / 剪切多类型捕获。
  - 搜索内部点击、外部点击、筛选面板、清空按钮、token、Esc、中文输入法。
  - 新卡片定位、边缘卡片动画平移。
  - 多屏 toast / popover / 预览窗口位置。
  - 外部 App drag-out 兼容性。

集成 / 红线遗留：
- Sources/ClipEase/Features/HistoryWindow/GlobalStatusToastController.swift 当前仍为 untracked 文件；Review 确认文件存在且 swift build 可编译。最终集成 / stage / commit 前必须确保该文件纳入版本控制视角。
- Resources/Info.plist 存在历史版本号 / build 号差异；修改版本号属于红线。本批不继续修改、不回退该历史差异；后续 release/build 版本变更需要用户确认或独立归档。

主控裁定：
- 允许调度 Acceptance Agent。
- Acceptance PASS 后允许主控以本地运行方式启动 App 给用户人工测试；如需修改版本号或正式打包发布，另走红线确认。
```

## 207. 维修阶段第一批验收放行记录

```text
任务卡：V2-ACCEPT-MAINT-BATCH1-20260515
时间：2026-05-15
阶段：维修阶段 / 第一批验收
当前会话模式：ClipEase V2 Acceptance Agent
结论：PASS

验收依据：
- 用户反馈 1-11 已在第 203 节分诊并映射到三张实现卡。
- 第 204 节记录实现完成。
- 第 205 节记录 Test / Review HOLD 和返工调度。
- 第 206 节记录返工复测 PASS 与复审 can_enter_acceptance。

Acceptance 重跑并通过：
- swift build
- git diff --check
- python3 scripts/verify_history_window_interaction_toast.py
- python3 scripts/verify_history_card_scroll_alignment.py
- python3 scripts/verify_sqlite_only_baseline.py
- python3 scripts/verify_no_management_no_favorite_ui.py
- python3 scripts/verify_stage9_file_capture_first_batch.py
- python3 scripts/verify_stage9_file_pasteboard_first_batch.py
- python3 scripts/verify_stage9_file_paste_fallback.py
- python3 scripts/verify_stage9_file_dragout_first_batch.py
- python3 scripts/verify_stage9_quicklook_interaction.py

放行范围：
- 允许主控使用当前本地运行方式启动 App 给用户做人工测试。
- 不允许借本次验收修改版本号、正式打包或发布；如需 release/build 版本变更，另走红线确认。

剩余人工验收项：
- 真实 App 内复制 / 剪切多类型捕获。
- 搜索内部 / 外部点击、筛选面板、清空按钮、token、Esc、中文输入法。
- 新卡片定位、边缘卡片动画平移、预览 / popover / toast 多屏位置。
- 外部 App drag-out 兼容性与文件 fallback 行为。

集成门禁遗留：
- Sources/ClipEase/Features/HistoryWindow/GlobalStatusToastController.swift 当前存在且 build 通过，但仍为 untracked；最终集成 / stage / commit 前必须纳入版本控制视角。
- Resources/Info.plist 版本号历史差异仍存在，属于后续红线确认 / 独立归档项；本批不继续修改、不回退。

交付摘要：维修阶段第一批用户反馈 1-11 已完成实现、返工、复测、复审和验收 PASS；允许主控本地运行 App 给用户人工测试。本轮未执行红线操作，未正式打包发布。
```

## 208. 维修阶段第二批用户运行态反馈与返工调度

```text
任务卡组：V2-MAINT-BATCH2-RUNTIME-20260515
时间：2026-05-15
阶段：维修阶段 / 第一批验收后用户运行态失败返工
当前会话模式：ClipEase V2 Main Controller Agent
风险等级：高
主控边界：主控只记录、分诊、定级、发放文件锁和调度 Agent；不亲自写业务代码、不亲自修 bug。

用户反馈原文摘要：
1. 某些文件复制还是没有记录。
2. 图片、文件预览窗口被调小；图片 / 文件预览窗口应根据用户分辨率展示。用户 4K 时，预览窗口内部最大 1920x1080；图片等比例缩小放入预览窗口内；图片宽度不够也要缩小窗口宽度，不要出现白边；内部窗口宽高由图片等比例缩放控制。
3. 搜索框问题仍未解决：搜索框展开时，搜索框内部、筛选按钮、筛选面板、清空按钮允许点击且不能关闭搜索框；只有点击搜索框外部区域才收起搜索框并清空内容。
4. 新卡片定位和边缘卡片平移 / 动画没有实现。
5. 全局提示层样式：四角要有弧度；位置始终固定；粘贴到其他 App 或其他提示时，不管主窗口打开 / 关闭，都在主窗口上方显示；背景带透明。
6. 新卡片定位：滚轮可能处于第二页 / 第三页时，只要新卡片加入，不管主窗口打开还是关闭，都要移到新卡片位置；无置顶时新卡片处于第一位且保留左侧间距；有置顶 / 前置时处于置顶卡片右侧第一位，并露出上一张约 1/6。

主控理解与确认：
- 已理解全部 6 点，无需追加澄清。
- 本批不是普通新需求，而是第一批维修在真实运行态验收失败后的返工。
- 静态脚本通过不能再作为充分放行条件；修复 Agent、Test Agent、Review Agent、Acceptance Agent 必须提供运行态或更接近运行态的验证路径。

分诊结论：
- 1 属于剪贴板文件捕获核心缺陷，高风险。交 Clipboard / Pasteboard Bugfix Agent。重点排查 Finder / iCloud / 桌面 / 文件夹 / 多文件 / path pasteboard / promised file / NSPasteboardItem 类型读取，避免只覆盖 `readObjects(forClasses: [NSURL.self])`。
- 2 属于预览窗口尺寸策略缺陷，高风险。交 UI Interaction / Preview Agent。需要恢复动态预览尺寸：按屏幕 visibleFrame 和内容像素比例计算，4K 时内部最大 1920x1080，非 4K 按屏幕约束缩放；图片不留白，窗口宽高跟随等比缩放结果。
- 3、4、6 属于主窗口搜索命中区与卡片定位/动画核心交互缺陷，高风险。交 UI Interaction Agent，并要求真实运行态验证，不再仅满足脚本断言。
- 5 属于全局 toast 层级 / 样式 / 定位缺陷，中高风险。交 UI Interaction Agent。必须在主窗口打开 / 关闭、粘贴到其他 App 后都显示在主窗口上方的固定位置；背景半透明、圆角。

关联守卫：
- GUARD-V2-BASELINE-001：SQLite-only，禁止恢复 JSON runtime / migration fallback。
- GUARD-V2-BASELINE-002：禁止恢复收藏、管理模式、多选、批量操作。
- GUARD-V2-GROUP-001：不得破坏分组、置顶和单条操作。
- GUARD-V2-SEARCH-001：搜索内部点击、筛选 popover、Esc、token 行为不得回归。
- GUARD-V2-UI-001：顶部轨道、分组滚动、卡片横向滚动不得污染。
- Stage 9 文件卡片 / Quick Look 守卫：文件卡片、Quick Look、文件 pasteboard、文件拖出、fallback 文本路径能力不得删除或退化。

文件锁：
- Sources/ClipEase/Features/ClipboardMonitor/ClipboardMonitor.swift：Clipboard / Pasteboard Bugfix Agent，任务卡 V2-BUGFIX-MAINT2-FILE-CAPTURE-RUNTIME-001。
- Sources/ClipEase/Core/Storage/ClipboardHistoryStore.swift：Clipboard / Pasteboard Bugfix Agent 必要时最小修改，任务卡 V2-BUGFIX-MAINT2-FILE-CAPTURE-RUNTIME-001。
- Sources/ClipEase/Features/HistoryWindow/HistoryPreviewWindowController.swift：UI Interaction / Preview Agent，任务卡 V2-BUGFIX-MAINT2-PREVIEW-SEARCH-SCROLL-TOAST-001。
- Sources/ClipEase/Features/HistoryWindow/HistoryPreviewPopoverView.swift：UI Interaction / Preview Agent，任务卡 V2-BUGFIX-MAINT2-PREVIEW-SEARCH-SCROLL-TOAST-001。
- Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift：UI Interaction / Preview Agent，任务卡 V2-BUGFIX-MAINT2-PREVIEW-SEARCH-SCROLL-TOAST-001。
- Sources/ClipEase/Features/HistoryWindow/HistoryWindowController.swift：UI Interaction / Preview Agent 必要时最小修改，任务卡 V2-BUGFIX-MAINT2-PREVIEW-SEARCH-SCROLL-TOAST-001。
- Sources/ClipEase/Features/HistoryWindow/GlobalStatusToastController.swift：UI Interaction / Preview Agent，任务卡 V2-BUGFIX-MAINT2-PREVIEW-SEARCH-SCROLL-TOAST-001。

禁止修改：
- 不得改 SQLite schema、数据迁移、清空数据库、删除附件。
- 不得恢复 JSON Repository、JSON migration runtime、JSON fallback。
- 不得恢复收藏 / 管理模式 / 多选 / 批量操作。
- 不得修改版本号、构建脚本、发布流程。
- 不得删除 Stage 9 文件卡片 / Quick Look / pasteboard / drag-out / fallback 已完成能力。

任务卡 1：
- ID：V2-BUGFIX-MAINT2-FILE-CAPTURE-RUNTIME-001
- 负责 Agent：Clipboard / Pasteboard Bugfix Agent
- 目标：修复“某些文件复制还是没有记录”。扩大文件 pasteboard 识别覆盖，保证 Finder / 多文件 / 文件夹 / iCloud 文件 / path pasteboard / file-url string / promised-file 相关常见类型不遗漏。
- 完成标准：
  - 明确当前漏记的 pasteboard 类型或读取顺序根因。
  - 文件 URL、文件夹、多文件、path 字符串、file URL 字符串能进入 `.file` 记录路径或合理 fallback。
  - 不把普通文本路径误判为文件，除非能确认本机路径存在并由文件复制语义触发。
  - ClipEase 自身复制 / 粘贴 skip 不回归。
- 必须验证：
  - swift build
  - Stage 9 file capture / pasteboard / fallback 脚本
  - 新增或临时诊断 pasteboard 类型说明
  - 手动验证矩阵：Finder 单文件、Finder 多文件、文件夹、桌面文件、iCloud 文件、本地路径字符串、ClipEase 自身文件复制跳过。

任务卡 2：
- ID：V2-BUGFIX-MAINT2-PREVIEW-SEARCH-SCROLL-TOAST-001
- 负责 Agent：UI Interaction / Preview Agent
- 目标：修复图片 / 文件预览尺寸、搜索内部点击、卡片定位 / 边缘平移动画、toast 圆角透明固定位置。
- 完成标准：
  - 图片预览按内容比例动态计算窗口尺寸；4K 屏幕内部最大 1920x1080；非 4K 按 visibleFrame 安全上限；图片不因固定窗口过大出现明显白边。
  - 文件 Quick Look 预览在屏幕约束下使用足够大窗口，不沿用过小固定尺寸；多文件列表不挤压主体预览。
  - 搜索框内部、筛选按钮、筛选面板、清空按钮点击不会关闭搜索；点击真正外部区域才关闭并清空。
  - 新卡片加入时，无论主窗口当前滚动在第几页、主窗口打开或关闭，都选中新卡片并滚动到目标位置；无置顶时作为第一张显示并保留左侧间距；有置顶 / 前置时在置顶右侧第一位并露出上一张约 1/6。
  - 点击左右边缘未完整卡片时，带动画平移到完整显示，并露出相邻卡片约 1/6。
  - 全局提示层四角圆角、背景半透明；主窗口打开 / 关闭、焦点在其他 App、粘贴到其他 App 后都显示在主窗口上方固定位置，不随提示内容或主窗口状态跳动。
- 必须验证：
  - swift build
  - git diff --check
  - 搜索/滚动/preview/toast 相关脚本若存在全部通过
  - 至少提供一组运行态验证步骤和观察结果，不能只写“静态通过”。

后续门禁：
- 两张修复卡完成后，调度 Test Agent 运行脚本 + 运行态验收清单。
- Test PASS 后调度 Review Agent 审查。
- Review PASS 后调度 Acceptance Agent 放行。
- Acceptance PASS 后主控本地运行 App 给用户测试。
```

## 209. 维修阶段第二批实现 Agent 完成记录

```text
任务卡组：V2-MAINT-BATCH2-RUNTIME-20260515
时间：2026-05-15
阶段：维修阶段 / 第二批实现完成
当前会话模式：ClipEase V2 Main Controller Agent

实现 Agent 结果：

1. V2-BUGFIX-MAINT2-FILE-CAPTURE-RUNTIME-001
- 负责 Agent：Clipboard / Pasteboard Bugfix Agent
- 状态：needs_review
- 修改文件：
  - Sources/ClipEase/Features/ClipboardMonitor/ClipboardMonitor.swift
- 交付摘要：
  - 扩大文件 pasteboard 捕获覆盖。
  - 保留 `NSURL readObjects` + `.urlReadingFileURLsOnly`。
  - 新增覆盖 `.fileURL`、`public.file-url`、`NSFilenamesPboardType`、`.URL`、file-url 字符串、promised-file URL / content / metadata 相关类型。
  - 多文件、文件夹按标准化 file path 去重后进入 `store.addFiles`。
- 已验证：
  - python3 scripts/verify_stage9_file_capture_first_batch.py：PASS
  - python3 scripts/verify_stage9_file_pasteboard_first_batch.py：PASS
  - python3 scripts/verify_stage9_file_paste_fallback.py：PASS
- 未完成：
  - Agent 运行 `swift build` 时被并行 UI 文件临时编译错误阻塞；需统一门禁重跑。
  - 未做真实 Finder / iCloud 手动运行态验证。

2. V2-BUGFIX-MAINT2-PREVIEW-SEARCH-SCROLL-TOAST-001
- 负责 Agent：UI Interaction / Preview Agent
- 状态：completed
- 修改文件：
  - Sources/ClipEase/Features/HistoryWindow/HistoryPreviewWindowController.swift
  - Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift
  - Sources/ClipEase/Features/HistoryWindow/HistoryWindowController.swift
  - Sources/ClipEase/Features/HistoryWindow/GlobalStatusToastController.swift
- 交付摘要：
  - 预览窗口按图片像素比例、screen visibleFrame 和内部最大 1920x1080 动态计算；文件 Quick Look 使用更大稳定窗口。
  - 搜索框、清空按钮、筛选按钮、筛选 popover 加入屏幕坐标白名单，外部点击 observer 不再把内部点击当外部点击。
  - 新卡片聚焦后强制选择并滚动到目标；边缘卡片点击使用绝对 offset 动画平移。
  - Toast 使用 borderless nonactivating panel、圆角、半透明背景；记录主窗口最近 frame，主窗口隐藏或其他 App 前台时按主窗口上方固定位置显示。
- 已验证：
  - swift build：PASS
  - git diff --check：PASS
  - python3 scripts/verify_history_window_interaction_toast.py：PASS
  - python3 scripts/verify_history_card_scroll_alignment.py：PASS
  - python3 scripts/verify_stage9_quicklook_interaction.py：PASS
  - python3 scripts/verify_no_management_no_favorite_ui.py：PASS
  - runtime launch smoke：PASS
- 未完成：
  - 未在真实 4K 屏幕人工确认图片白边 / 尺寸。
  - 未人工确认筛选 popover 点击保持。
  - 未人工确认跨 App 粘贴 Toast 位置。

主控裁定：
- 进入 Test / Review 门禁。
- Test Agent 必须运行脚本 + 尽量做真实运行态矩阵；若无法自动验证 4K / Finder / 外部 App，必须明确列为用户人工验收项，不得写成通过。
- Review Agent 必须重点审查是否又出现“脚本通过但真实行为未覆盖”的风险。
```

## 210. 维修阶段第二批 Test PASS / Review HOLD 与返工调度

```text
任务卡组：V2-MAINT-BATCH2-RUNTIME-20260515
时间：2026-05-15
阶段：维修阶段 / 第二批门禁 HOLD
当前会话模式：ClipEase V2 Main Controller Agent

Test Agent 结果：
- 任务卡：V2-TEST-MAINT2-RUNTIME-20260515
- 结论：自动化 + 静态 PASS，可进入 Review，但不可直接进入 Acceptance。
- 已通过：
  - swift build
  - git diff --check
  - python3 scripts/verify_stage9_file_capture_first_batch.py
  - python3 scripts/verify_stage9_file_pasteboard_first_batch.py
  - python3 scripts/verify_stage9_file_paste_fallback.py
  - python3 scripts/verify_history_window_interaction_toast.py
  - python3 scripts/verify_history_card_scroll_alignment.py
  - python3 scripts/verify_stage9_quicklook_interaction.py
  - python3 scripts/verify_no_management_no_favorite_ui.py
  - python3 scripts/verify_sqlite_only_baseline.py
- 已明确未验证：
  - Finder / iCloud / 桌面 / 文件夹真实复制捕获。
  - 4K 图片 / 文件预览视觉。
  - 真实点击搜索框 / 筛选按钮 / 筛选面板 / 清空按钮。
  - 真实边缘卡片平移动画手感。
  - 跨 App 粘贴 toast、主窗口开 / 关状态 toast 位置。
  - 新卡片在第二页 / 第三页滚动状态加入后的真实定位。

Review Agent 结果：
- 任务卡：V2-REVIEW-MAINT2-RUNTIME-20260515
- 结论：HOLD，不可进入 Acceptance。

Review 阻塞问题：
1. 新卡片在主窗口已打开时不会立即定位。
   - 原因：`store.items` 变化调用 `syncLatestItemFocusIfNeeded(... consumePendingForShow: false)`；窗口可见且 `consumePendingForShow == false` 时只记录 pending，不执行 `selectedItemID` / `scrollToItemWhenRendered`。
   - 用户影响：卡片列表已滚到第二页 / 第三页时复制新内容，主窗口已打开仍可能停在旧位置。
2. 搜索内部点击白名单存在坐标系错误。
   - 原因：白名单 frame 使用屏幕坐标，但 `SearchOutsideMouseDownObserver` 点击点为 observer 本地坐标，直接比较会导致主窗口不在屏幕原点或多屏时误判。
   - 用户影响：搜索框内部、清空按钮、筛选按钮仍可能被当作外部点击，导致搜索收起。
3. 图片预览仍可能产生固定最小窗口和白边。
   - 原因：图片尺寸计算强制 `max(220, ...)`，对小图 / 窄图窗口不会继续随图片缩小。
   - 用户影响：仍可能出现用户明确不接受的白边 / 空背景。
4. Resources/Info.plist 版本号差异触发红线门禁。
   - 主控裁定：这是历史发布边界遗留，当前返工不允许继续修改或回退；后续 release/build 前需要用户单独确认。
5. GlobalStatusToastController.swift 仍为 untracked 运行时代码。
   - 主控裁定：这是最终集成 / stage / commit 门禁。当前不在代码返工中用 git stage 处理；进入最终集成前必须解决。

非阻塞风险：
- Promised file 未使用 NSFilePromiseReceiver 真正解析，只识别语义并尝试现有 URL/path；真实 promised-file provider 仍需人工验证。
- 文件 Quick Look 在小屏可能超过可用屏幕约束，需后续验证。
- Toast 跨 App / hidden window frame 仍需真实验证。

主控裁定：
- Acceptance 继续 HOLD。
- 代码返工只处理 Review 阻塞 1-3，交 UI Interaction / Preview Agent。
- 阻塞 4 为红线集成事项，不由返工 Agent 修改。
- 阻塞 5 为集成/版本控制事项，不由返工 Agent stage；主控在最终集成前处理或请求用户确认。

返工任务卡：
- ID：V2-BUGFIX-MAINT2-PREVIEW-SEARCH-SCROLL-TOAST-001-REWORK
- 负责 Agent：UI Interaction / Preview Agent
- 允许修改：
  - Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift
  - Sources/ClipEase/Features/HistoryWindow/HistoryPreviewWindowController.swift
  - Sources/ClipEase/Features/HistoryWindow/HistoryPreviewPopoverView.swift（仅当去白边需要）
- 禁止修改：
  - Sources/ClipEase/Features/ClipboardMonitor/ClipboardMonitor.swift
  - Sources/ClipEase/Core/Storage/ClipboardHistoryStore.swift
  - Sources/ClipEase/Features/HistoryWindow/GlobalStatusToastController.swift
  - Resources/Info.plist
  - 构建脚本、发布流程、SQLite schema、JSON / favorite / management / multi / batch 相关代码
- 完成标准：
  - 主窗口打开且卡片列表滚到第二 / 第三页时，新剪切板加入会立即选中新卡片并滚动到目标位置。
  - 搜索内部点击白名单和外部点击 observer 使用一致坐标系，不能再混用屏幕坐标和本地坐标；搜索框、清空按钮、筛选按钮、筛选面板点击不关闭。
  - 图片预览尺寸取消不合理固定最小宽高；小图 / 窄图窗口跟随等比缩放结果，避免明显白边；仍受屏幕 visibleFrame 和 1920x1080 内部上限约束。
  - swift build、git diff --check、相关脚本 PASS。
  - 交付中必须说明运行态验证路径，不得只写脚本通过。

后续：
- Rework 完成后重新调度 Test Agent 做脚本 + 针对性静态 / 运行态复测。
- 再调度 Review Agent 复审阻塞 1-3。
- 版本号红线与 untracked source 集成门禁在 Acceptance 前单独裁定。
```

## 211. 维修阶段第二批 Review HOLD 返工完成记录

```text
任务卡：V2-BUGFIX-MAINT2-PREVIEW-SEARCH-SCROLL-TOAST-001-REWORK
时间：2026-05-15
阶段：维修阶段 / 第二批 Review HOLD 返工完成
当前会话模式：ClipEase V2 UI Interaction / Preview Agent
状态：completed

返工范围：
- 只处理 Review 阻塞 1-3。
- 未修改 ClipboardMonitor、ClipboardHistoryStore、GlobalStatusToastController、Resources/Info.plist、构建脚本、发布流程、SQLite schema、JSON / favorite / management / multi / batch 相关代码。

修改文件：
- Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift
- Sources/ClipEase/Features/HistoryWindow/HistoryPreviewWindowController.swift

修复内容：
1. 新卡片主窗口已打开时立即定位：
   - `store.items` 变化走即时消费路径。
   - 可见窗口下通过 `lastObservedNewestItemID != newestID` 触发新卡 focus。
   - 沿用 `pendingLatestFocusItemID`、`fulfillPendingLatestFocusIfPossible()`、`scrollToItemWhenRendered()` 和绝对 offset 逻辑。
   - 保留无置顶最左 padding / 有前置露出约 1/6 的规则。
2. 搜索内部点击白名单坐标系：
   - `SearchOutsideMouseDownObserver` 将事件点转换为屏幕坐标后再与 `searchInteractionScreenFrames` 比较。
   - 不再用 observer 本地坐标比较屏幕 frame。
   - 筛选 popover / popup 层白名单放行。
3. 图片预览最小尺寸白边：
   - 移除图片预览 `max(220, ...)` 固定最小宽高。
   - 图片窗口按图片等比缩放后的内容尺寸收缩，同时受 visibleFrame 和内部 1920x1080 上限约束。

验证结果：
- swift build：PASS
- git diff --check：PASS
- python3 scripts/verify_history_window_interaction_toast.py：PASS
- python3 scripts/verify_history_card_scroll_alignment.py：PASS
- python3 scripts/verify_stage9_quicklook_interaction.py：PASS

未验证：
- 真实 GUI 运行态 smoke 未执行。
- 主窗口滚到第二 / 第三页时复制新内容的即时定位。
- 多屏 / 窗口非原点下搜索框 / 清空 / 筛选 popover 点击不关闭搜索。
- 小图 / 窄图图片预览白边视觉。

后续：
- 调度 Test Agent 复测脚本和针对性静态核对，明确人工未验证项。
- 调度 Review Agent 复审 Review 阻塞 1-3 是否解除。
- 版本号红线与 untracked source 集成门禁仍需在 Acceptance 前裁定。
```

## 212. 维修阶段第二批二次复测 / 复审 HOLD 记录

```text
任务卡组：V2-MAINT-BATCH2-RUNTIME-20260515
时间：2026-05-15
阶段：维修阶段 / 第二批二次复测与复审
当前会话模式：ClipEase V2 Main Controller Agent

Test Agent 复测：
- 任务卡：V2-TEST-MAINT2-RUNTIME-RETEST-20260515
- 结论：Review 阻塞 1-3 的自动化 / 静态复测 PASS，可进入 Review；不可直接进入 Acceptance。
- 已通过：
  - swift build
  - git diff --check
  - python3 scripts/verify_history_window_interaction_toast.py
  - python3 scripts/verify_history_card_scroll_alignment.py
  - python3 scripts/verify_stage9_quicklook_interaction.py
  - python3 scripts/verify_stage9_file_capture_first_batch.py
  - python3 scripts/verify_stage9_file_pasteboard_first_batch.py
  - python3 scripts/verify_stage9_file_paste_fallback.py
  - python3 scripts/verify_no_management_no_favorite_ui.py
  - python3 scripts/verify_sqlite_only_baseline.py
- 静态核对：
  - store.items 即时 focus：PASS
  - SearchOutsideMouseDownObserver screen 坐标比较：PASS
  - image preview 移除固定 max(220)：PASS
- 仍需人工验证：
  - 第二 / 第三页复制新内容后的即时定位。
  - 多屏 / 非原点搜索点击。
  - 小图 / 窄图 / 4K 图片预览视觉。
  - Finder / iCloud 文件捕获。

Review Agent 复审：
- 任务卡：V2-REVIEW-MAINT2-RUNTIME-REREVIEW-20260515
- 结论：HOLD，不可进入 Acceptance。
- 已解除：
  - 新卡片主窗口已打开时选中并滚动：静态通过。
  - 搜索点击白名单坐标系：静态通过。
- 新阻塞：
  - 图片预览移除 `min 220` 后可能缩成不可用极小窗口。小图、窄图、1xN 图可能生成极窄窗口，按钮 / 内容区不可用。

主控裁定：
- Acceptance 继续 HOLD。
- 单点返工只处理图片预览尺寸下限策略。
- 目标不是恢复固定大窗口，而是在“无明显白边”和“窗口可用”之间设合理最小可用尺寸。
- 版本号红线与 untracked source 集成门禁仍单独保留，不由本返工 Agent 修改。

返工任务卡：
- ID：V2-BUGFIX-MAINT2-IMAGE-PREVIEW-USABLE-MIN-SIZE-001
- 负责 Agent：UI Interaction / Preview Agent
- 允许修改：
  - Sources/ClipEase/Features/HistoryWindow/HistoryPreviewWindowController.swift
  - Sources/ClipEase/Features/HistoryWindow/HistoryPreviewPopoverView.swift（仅当布局配合需要）
- 禁止修改：
  - Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift
  - Sources/ClipEase/Features/ClipboardMonitor/ClipboardMonitor.swift
  - Sources/ClipEase/Core/Storage/ClipboardHistoryStore.swift
  - Sources/ClipEase/Features/HistoryWindow/GlobalStatusToastController.swift
  - Resources/Info.plist
  - 构建脚本、发布流程、SQLite schema、JSON / favorite / management / multi / batch 相关代码
- 完成标准：
  - 图片预览保留等比缩放和 1920x1080 内部上限。
  - 小图 / 窄图不能生成极小不可用窗口；需有合理最小可用内容区尺寸。
  - 合理最小尺寸不得重新制造大面积白边；若图片本身极窄，应限制窗口宽度在“可操作但不夸张”的范围。
  - swift build、git diff --check、Quick Look / preview 相关脚本通过。
```

## 213. 图片预览可用最小尺寸返工完成记录

```text
任务卡：V2-BUGFIX-MAINT2-IMAGE-PREVIEW-USABLE-MIN-SIZE-001
时间：2026-05-15
阶段：维修阶段 / 第二批图片预览尺寸单点返工
当前会话模式：ClipEase V2 UI Interaction / Preview Agent
状态：completed

修改文件：
- Sources/ClipEase/Features/HistoryWindow/HistoryPreviewWindowController.swift

修复内容：
- 图片预览继续按图片比例、screen visibleFrame 和内部最大 1920x1080 计算。
- 新增 `imagePreviewMinimumContentSize = 180x140`，用于防止小图、窄图、1xN 图生成极小不可用窗口。
- 该下限低于旧 220pt 固定下限，目标是在“可操作内容区”和“不恢复夸张白边”之间取平衡。

验证结果：
- swift build：PASS
- git diff --check：PASS
- python3 scripts/verify_stage9_quicklook_interaction.py：PASS
- 未发现独立 image preview size 脚本。
- 额外运行 python3 scripts/verify_stage8_window_experience.py：FAIL，失败为 `could not locate toolbar body`；当前判断为旧静态脚本定位主窗口结构失效，非本返工允许文件引入，暂不作为本卡阻塞。

未验证：
- 1xN、Nx1、小图、普通大图、4K 大图的真实视觉人工验收。

后续：
- 调度 Test Agent 复测最小尺寸返工和关键脚本。
- 调度 Review Agent 复审图片预览尺寸阻塞是否解除。
```

## 214. 图片预览可用最小尺寸复测 / 复审记录

```text
任务卡组：V2-MAINT2-IMAGE-PREVIEW-MIN
时间：2026-05-15
阶段：维修阶段 / 第二批图片预览尺寸门禁
当前会话模式：ClipEase V2 Main Controller Agent

Test Agent：
- 任务卡：V2-TEST-MAINT2-IMAGE-PREVIEW-MIN-RETEST-20260515
- 结论：PASS，可进入 Review；真实视觉样本仍需人工验收。
- 已通过：
  - swift build
  - git diff --check
  - python3 scripts/verify_stage9_quicklook_interaction.py
  - python3 scripts/verify_history_window_interaction_toast.py
  - python3 scripts/verify_history_card_scroll_alignment.py
- 静态核对：
  - imagePreviewMinimumContentSize = 180x140：PASS
  - 保留内部 1920x1080 上限：PASS
  - 保持等比缩放：PASS
  - 未恢复旧 max(220, ...) 固定大下限：PASS
- 未执行：
  - 1xN、Nx1、小图、4K 大图真实视觉验收。

Review Agent：
- 任务卡：V2-REVIEW-MAINT2-IMAGE-PREVIEW-MIN-REREVIEW-20260515
- 结论：PASS_TO_ACCEPTANCE。
- 已确认：
  - 上一轮“极小不可用窗口”阻塞已解除。
  - 图片预览新增 180x140 内容区下限，避免小图、窄图、1xN 图得到 1px / 极窄不可操作内容区。
  - 未恢复旧 220pt 大固定窗口。
  - scoped diff 未发现本卡新阻塞。

剩余人工验收项：
- 1xN / Nx1 / 小图 / 普通大图 / 4K 大图预览视觉。
- Finder / iCloud 文件复制真实捕获。
- 搜索内部点击 / 筛选面板 / 清空按钮真实点击。
- 第二 / 第三页滚动状态下新卡片真实定位。
- 跨 App toast 位置和透明圆角视觉。

主控裁定：
- 允许调度 Acceptance Agent。
- Acceptance 只能放行“本地运行给用户人工测试”，不能放行正式发布或版本号修改。
- 版本号红线与 GlobalStatusToastController.swift untracked 集成门禁继续单独保留。
```

## 215. 维修阶段第二批最终验收放行记录

```text
任务卡：V2-ACCEPT-MAINT2-RUNTIME-20260515
时间：2026-05-15
阶段：维修阶段 / 第二批最终验收
当前会话模式：ClipEase V2 Acceptance Agent
结论：PASS_LOCAL_USER_TEST_ONLY

验收范围：
- 第二批用户运行态反馈 6 条。
- 文件复制漏记录。
- 图片 / 文件预览尺寸。
- 搜索框内部点击 / 外部点击。
- 新卡片定位和边缘卡片平移动画。
- 全局 toast 样式 / 位置。
- 第二 / 第三页滚动状态新卡片加入定位。

验收依据：
- 第 208 节记录用户运行态反馈和任务卡。
- 第 209 节记录实现 Agent 完成。
- 第 210 节记录 Test PASS / Review HOLD 和返工调度。
- 第 211 节记录 Review HOLD 返工完成。
- 第 212 节记录二次复测 / 复审 HOLD。
- 第 213 节记录图片预览可用最小尺寸返工。
- 第 214 节记录图片预览最小尺寸复测 / 复审 PASS_TO_ACCEPTANCE。

Acceptance 复核通过：
- swift build：PASS
- git diff --check：PASS
- python3 scripts/verify_stage9_quicklook_interaction.py：PASS
- python3 scripts/verify_history_window_interaction_toast.py：PASS
- python3 scripts/verify_history_card_scroll_alignment.py：PASS
- python3 scripts/verify_stage9_file_capture_first_batch.py：PASS
- python3 scripts/verify_stage9_file_pasteboard_first_batch.py：PASS
- python3 scripts/verify_stage9_file_paste_fallback.py：PASS
- python3 scripts/verify_sqlite_only_baseline.py：PASS
- python3 scripts/verify_no_management_no_favorite_ui.py：PASS

用户反馈覆盖：
1. 文件复制漏记录：ClipboardMonitor 扩大 file pasteboard 类型捕获，file capture / pasteboard / fallback 脚本通过。
2. 图片 / 文件预览尺寸：动态尺寸、内部 1920x1080 上限、180x140 可用最小内容区，Quick Look 脚本通过。
3. 搜索内部点击误关闭：白名单改为屏幕坐标一致比较，搜索 / toast 交互脚本通过。
4. 新卡片定位与边缘动画：即时 focus / scroll 与绝对 offset 逻辑，card scroll alignment 脚本通过。
5. 全局 toast 样式 / 固定位置：圆角、半透明、nonactivating panel、主窗口 frame 定位，toast 脚本通过。
6. 第二 / 第三页新卡片加入定位：store.items 变化即时消费 focus，滚动定位脚本通过。

剩余人工验收项：
- Finder / iCloud / 桌面 / 文件夹 / 多文件真实复制捕获。
- 1xN、Nx1、小图、普通大图、4K 大图预览视觉。
- 真实点击搜索框内部、清空按钮、筛选按钮、筛选面板时搜索不关闭；点击外部才关闭并清空。
- 主窗口滚到第二页 / 第三页时复制新内容，新卡片真实定位到目标位置。
- 边缘卡片点击后的平移动画手感。
- 跨 App 粘贴、主窗口打开 / 关闭状态下 toast 位置、圆角、透明视觉。

风险 / 集成门禁：
- Resources/Info.plist 存在历史版本号差异，版本号修改属于红线；本次只允许本地运行给用户测，不允许正式发布、不允许继续改版本号。
- Sources/ClipEase/Features/HistoryWindow/GlobalStatusToastController.swift 仍为 untracked 运行时代码；不阻塞本地运行测试，但阻塞最终集成、stage、commit、正式发布。
- 工作区为大脏树；本验收只裁定第二批维修运行态修复可进入用户本地测试，不裁定整仓发布状态。

主控裁定：
- 允许主控本地运行 App 给用户人工测试。
- 不允许正式发布 / 改版本号。
```

## 216. 维修阶段第三轮用户实测失败记录

```text
任务卡组：V2-MAINT3-HISTORY-RUNTIME-20260515
时间：2026-05-15
阶段：维修阶段 / 第二批本地运行后用户实测失败
当前会话模式：ClipEase V2 Main Controller Agent
风险等级：高
主控边界：主控只记录、分诊、定级、发放文件锁和调度 Agent；不亲自写业务代码、不亲自修 bug。

用户反馈：
- 主控要求测试的第 3、4、5 项没有解决：
  3. 搜索框内部、清空按钮、筛选按钮、筛选面板点击不能关闭搜索；只有外部点击关闭并清空。
  4. 滚到第二 / 第三页后复制新内容，新卡片没有立即定位到目标位置。
  5. 左右边缘卡片点击后的平移动画没有实现 / 没有达到用户预期。

主控判断：
- 这是第二批 PASS_LOCAL_USER_TEST_ONLY 后的真实用户实测失败。
- 静态脚本和坐标 / 公式修复已经不足以说明功能完成。
- 这三项合并为主窗口真实交互 P1 返工，交 UI Interaction Agent。
- 修复必须从真实交互结构入手：
  - 搜索：优先保证搜索内部和 popover 的点击事件不会落到 outside observer，不能只依赖脆弱 frame 判断。
  - 新卡片：必须由 store.items 新增事件触发显式选择和显式滚动命令，覆盖窗口打开、隐藏、当前滚动第二 / 第三页。
  - 边缘卡片：必须基于真实可见区域判断卡片是否未完整显示，并发起可观察动画滚动。

关联守卫：
- GUARD-V2-SEARCH-001：搜索内部点击、筛选 popover、Esc、token 行为不得回归。
- GUARD-V2-UI-001：顶部轨道和卡片横向滚动不得互相污染。
- GUARD-V2-GROUP-001：分组 / 置顶选择逻辑不得被新卡片定位破坏。
- GUARD-V2-BASELINE-001 / 002：不得恢复 JSON、收藏、管理模式、多选、批量操作。

文件锁：
- Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift：UI Interaction Agent，任务卡 V2-BUGFIX-MAINT3-HISTORY-RUNTIME-INTERACTION-001。
- Sources/ClipEase/Features/HistoryWindow/HistoryWindowController.swift：UI Interaction Agent 必要时最小修改。
- Sources/ClipEase/Features/HistoryWindow/HistoryWindowInputState.swift：UI Interaction Agent 必要时最小修改。

禁止修改：
- ClipboardMonitor.swift、ClipboardHistoryStore.swift、HistoryPreviewWindowController.swift、HistoryPreviewPopoverView.swift、GlobalStatusToastController.swift。
- Resources/Info.plist、构建脚本、发布流程。
- SQLite schema、JSON / favorite / management / multi / batch 相关代码。

任务卡：
- ID：V2-BUGFIX-MAINT3-HISTORY-RUNTIME-INTERACTION-001
- 负责 Agent：UI Interaction Agent
- 目标：修复搜索内部点击、新卡片定位、边缘卡片平移动画三个用户实测失败。
- 完成标准：
  1. 搜索展开时，搜索框内部、清空按钮、筛选按钮、筛选面板点击不关闭搜索；点击真正外部区域关闭并清空。修复应避免脆弱坐标转换，优先使用事件范围隔离、popover 窗口识别或内部点击消费。
  2. 主窗口滚到第二 / 第三页时，复制新内容后立即选中新卡片并滚动到目标位置；主窗口隐藏后再打开也定位新卡片；无置顶 / 有置顶规则保持。
  3. 点击左右边缘未完整显示卡片时，卡片平移动画可见，卡片完整展示并露出相邻卡片约 1/6；点击完整卡片不产生多余滚动。
- 必须验证：
  - swift build
  - git diff --check
  - python3 scripts/verify_history_window_interaction_toast.py
  - python3 scripts/verify_history_card_scroll_alignment.py
  - python3 scripts/verify_no_management_no_favorite_ui.py
  - 运行态说明：必须启动 App 或说明可观察验证路径；不能只用脚本 PASS 作为完成结论。

后续门禁：
- 修复后调度 Test Agent，要求针对这三项生成更严格的静态 / 运行态检查。
- Review Agent 需审查是否仍然只是“看起来满足脚本”。
- Acceptance 只允许在 Test / Review 均通过后本地运行给用户再测。
```

## 217. 维修阶段第三轮主窗口交互返工完成记录

```text
任务卡：V2-BUGFIX-MAINT3-HISTORY-RUNTIME-INTERACTION-001
时间：2026-05-15
阶段：维修阶段 / 第三轮主窗口真实交互返工
当前会话模式：ClipEase V2 UI Interaction Agent
状态：completed_local_static_and_smoke

修改文件：
- Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift

修复内容：
1. 搜索内部点击误关闭：
   - 移除覆盖整个 `VStack` 的根级 `SearchOutsideMouseDownObserver`。
   - outside observer 只挂在搜索下方内容区域，避免覆盖 toolbar / search 区域。
   - 搜索框、清空按钮、筛选按钮和筛选 popover 继续通过交互 frame / popover window 放行。
2. 新卡片定位：
   - 调整 latest pending focus 消费时序。
   - `fulfillPendingLatestFocusIfPossible()` 先选中新 item，再调用 `scrollToItemWhenRendered(pendingLatestFocusItemID)`，最后才清空 pending。
   - 窗口可见新增 newest item 会显式 selected + scroll；隐藏后打开也会消费 pending。
3. 边缘卡片平移动画：
   - `revealPartiallyVisibleCardIfNeeded` 改为基于 `HistoryScrollCoordinator.visibleRectInHistoryWindow` 计算真实可见区域。
   - 判断左右 clip 后调用 `scrollToOffset(..., animated: true)`。
   - 完整可见卡片不滚动；左右边缘未完整显示卡片按相邻卡片约 1/6 peek 动画平移。

验证结果：
- swift build：PASS
- git diff --check：PASS
- python3 scripts/verify_history_window_interaction_toast.py：PASS
- python3 scripts/verify_history_card_scroll_alignment.py：PASS
- python3 scripts/verify_no_management_no_favorite_ui.py：PASS
- App smoke：PASS，可启动。

未验证：
- 真实点击搜索框、清空、筛选按钮、筛选面板内容均不关闭。
- 主窗口滚到第二 / 第三页后复制新内容立即选中新卡并滚回目标。
- 点击左右边缘半露卡片时可见平移动画，完整可见卡片不滚。

后续：
- 调度 Test Agent 针对三项做专项复测。
- 调度 Review Agent 审查是否仍存在结构性运行态风险。
- Test / Review 均通过后再调度 Acceptance。
```

## 218. 维修阶段第三轮主窗口交互专项测试 / 审查记录

```text
任务卡组：V2-MAINT3-HISTORY-RUNTIME-20260515
时间：2026-05-15
阶段：维修阶段 / 第三轮主窗口真实交互门禁
当前会话模式：ClipEase V2 Main Controller Agent

Test Agent：
- 任务卡：V2-TEST-MAINT3-HISTORY-RUNTIME-INTERACTION-20260515
- 结论：自动化 + 静态复测 PASS，可进入 Review；真实点击 / 滚动仍需人工验收。
- 已通过：
  - swift build
  - git diff --check
  - python3 scripts/verify_history_window_interaction_toast.py
  - python3 scripts/verify_history_card_scroll_alignment.py
  - python3 scripts/verify_no_management_no_favorite_ui.py
  - App launch smoke：PASS
- 静态核对：
  - 搜索根级 / toolbar 祖先未挂 SearchOutsideMouseDownObserver：PASS
  - observer 仅挂在空状态、内容列表等搜索下方外部区域：PASS
  - store.items change path 触发 pending latest focus：PASS
  - fulfillPendingLatestFocusIfPossible 顺序为 selected -> scroll -> clear：PASS
  - edge reveal 使用 visibleRectInHistoryWindow 并 animated scroll：PASS

Review Agent：
- 任务卡：V2-REVIEW-MAINT3-HISTORY-RUNTIME-INTERACTION-20260515
- 结论：pass_with_runtime_acceptance_required。
- 未发现阻塞问题。
- 已确认三项用户实测失败均有结构性修复痕迹：
  - 搜索：根级 SearchOutsideMouseDownObserver 已移除，只挂在空态 / 内容滚动区域；popover 窗口本地 observer 识别并放行，Controller 也放行 App 内窗口。
  - 新卡片定位：store.items 变化和窗口重新可见都会进入 latest focus pending；pending 在 filtered items 可用后才消费，顺序 selected -> scroll -> clear。
  - 边缘卡片动画：点击选择走真实 card frame + HistoryScrollCoordinator.visibleRectInHistoryWindow，并调用 scrollToOffset(... animated: true)；完整可见时不滚。

非阻塞风险：
- 搜索关闭仍部分依赖局部 observer + screen frame exclusion + popover/window class/level 判断。
- toolbar 空白区点击是否应关闭搜索需要用户运行态确认；分组点击有 GroupMouseDownObserver，内容区点击会关闭。
- HistoryWindowView scoped diff 较大，回归面较大。

仍需人工验收：
- 搜索框、清空按钮、筛选按钮、筛选面板内部点击均不关闭；外部点击关闭并清空。
- 滚到第二 / 第三页后复制新内容，新卡片立即选中并滚到目标。
- 隐藏窗口后复制新内容，再打开能定位新卡片。
- 左右边缘半露卡片点击有可见平移动画，完整可见卡片不滚动。

主控裁定：
- 允许调度 Acceptance Agent。
- Acceptance 只可放行本地运行给用户做真实交互验收，不能写成人工验收已完成。
- 版本号红线与 untracked GlobalStatusToastController.swift 集成门禁继续保留。
```

## 219. 维修阶段第三轮主窗口交互本地测试放行记录

```text
任务卡：V2-ACCEPT-MAINT3-HISTORY-RUNTIME-INTERACTION-20260515
时间：2026-05-15
阶段：维修阶段 / 第三轮主窗口交互本地测试放行
当前会话模式：ClipEase V2 Acceptance Agent
结论：PASS_LOCAL_USER_TEST_ALLOWED

验收边界：
- 只允许主控本地运行 App，交给用户再次人工测试。
- 最终运行态验收仍未完成。
- 不允许正式发布。
- 不允许修改版本号。

依据：
- 第 216 节记录用户实测第 3 / 4 / 5 项仍失败。
- 第 217 节记录 UI Interaction Agent 完成结构性返工。
- 第 218 节记录 Test 自动化 / 静态 PASS，Review pass_with_runtime_acceptance_required。

必须由用户人工测试的三项：
1. 搜索框内部、清空按钮、筛选按钮、筛选面板内部点击均不关闭搜索；真正外部点击才关闭并清空。
2. 主窗口滚到第二 / 第三页后复制新内容，新卡片立即选中并滚到目标位置；窗口隐藏后复制，再打开也能定位新卡片。
3. 点击左右边缘半露卡片时有可见平移动画；点击完整可见卡片不产生多余滚动。

风险 / 集成门禁：
- Resources/Info.plist 当前仍有版本号红线差异；本轮不得发布、不得继续改版本号。
- Sources/ClipEase/Features/HistoryWindow/GlobalStatusToastController.swift 仍为 untracked；不阻塞本地运行测试，但阻塞最终集成、stage、commit、正式发布。

主控裁定：
- 允许本地运行 App 给用户测试上述三项。
```

## 220. 维修阶段第四轮搜索规则变更与主窗口交互返工调度

```text
任务卡组：V2-MAINT4-HISTORY-RUNTIME-20260515
时间：2026-05-15
阶段：维修阶段 / 第三轮本地运行后用户反馈
当前会话模式：ClipEase V2 Main Controller Agent
风险等级：高
主控边界：主控只记录、分诊、定级、发放文件锁和调度 Agent；不亲自写业务代码、不亲自修 bug。

用户反馈：
1. 搜索框展开 / 收起逻辑需要更新：
   - 搜索框展开后，无内容点击搜索框外部关闭搜索框。
   - 搜索框展开后，有内容点击普通外部区域不关闭搜索框，也不清空内容。
   - 搜索框有内容时点击其他分组，关闭搜索框并清空内容。
2. 用户滚动卡片列表后，有新剪切板内容加入，必须定位到新卡片位置且显示：
   - 无置顶卡片时，新卡片处于第一位且保留左侧间距。
   - 有置顶 / 有前置卡片时，新卡片处于置顶卡片右侧第一位，并露出上一张约 1/6。
3. 点击左右边缘半露卡片的问题依旧没有解决。

产品规则更新：
- 已更新 `docs/V2_FEEDBACK_AND_GUARDS.md` 的 GUARD-V2-SEARCH-001：
  - 无内容外点关闭搜索框。
  - 有内容普通外点不关闭、不清空。
  - 有内容点击其他分组关闭并清空。
- 该规则覆盖此前“外部点击统一关闭并清空”的旧验收口径。

分诊结论：
- 1 属于搜索产品规则变更 + 交互 bug，交 UI Interaction Agent。
- 2 属于主窗口滚动状态与新卡片定位核心交互 bug，交 UI Interaction Agent。
- 3 属于卡片可见性 / 滚动动画核心交互 bug，交 UI Interaction Agent。
- 三项都集中在 HistoryWindow 真实运行态，风险等级高。

文件锁：
- Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift：UI Interaction Agent，任务卡 V2-BUGFIX-MAINT4-HISTORY-RUNTIME-INTERACTION-001。
- Sources/ClipEase/Features/HistoryWindow/HistoryWindowInputState.swift：UI Interaction Agent 必要时最小修改。
- Sources/ClipEase/Features/HistoryWindow/HistoryWindowController.swift：UI Interaction Agent 必要时最小修改。

禁止修改：
- ClipboardMonitor.swift、ClipboardHistoryStore.swift、HistoryPreviewWindowController.swift、HistoryPreviewPopoverView.swift、GlobalStatusToastController.swift。
- Resources/Info.plist、构建脚本、发布流程。
- SQLite schema、JSON / favorite / management / multi / batch 相关代码。

任务卡：
- ID：V2-BUGFIX-MAINT4-HISTORY-RUNTIME-INTERACTION-001
- 负责 Agent：UI Interaction Agent
- 目标：按新搜索规则修复搜索展开 / 收起行为，并修复新卡片定位和边缘半露卡片动画。
- 完成标准：
  1. 搜索框展开且无内容时，点击普通外部区域关闭搜索框。
  2. 搜索框展开且有文字 / token / 筛选内容时，点击普通外部区域不关闭搜索框、不清空内容。
  3. 搜索框展开且有内容时，点击其他分组关闭搜索框并清空内容。
  4. 搜索框内部、清空按钮、筛选按钮、筛选面板内部点击不关闭搜索框，除非清空按钮本身执行清空动作。
  5. 卡片列表滚动到第二 / 第三页后，有新剪切板内容加入时，立即选中并滚动到新卡片目标位置；隐藏后再打开也定位。
  6. 无置顶时新卡片处于第一位且保留左侧间距；有置顶 / 前置时处于置顶右侧第一位，并露出上一张约 1/6。
  7. 点击左右边缘半露卡片时，能看到平移动画；点击完整可见卡片不滚动。
- 必须验证：
  - swift build
  - git diff --check
  - python3 scripts/verify_history_window_interaction_toast.py
  - python3 scripts/verify_history_card_scroll_alignment.py
  - python3 scripts/verify_no_management_no_favorite_ui.py
  - 必须给出针对 1-7 的运行态验证说明 / 未验证项，不能只写脚本 PASS。

后续门禁：
- UI Agent 完成后调度 Test Agent 和 Review Agent。
- Test Agent 必须更新旧验收口径，按新搜索规则验证。
- Review Agent 必须确认新搜索规则没有和 GUARD-V2-SEARCH-001 冲突。
- Acceptance 仅可放行本地运行给用户人工测试。
```

## 221. 维修阶段第四轮 UI 返工完成与测试口径冲突记录

```text
任务卡：V2-BUGFIX-MAINT4-HISTORY-RUNTIME-INTERACTION-001
时间：2026-05-15
阶段：维修阶段 / 第四轮主窗口交互返工完成
当前会话模式：ClipEase V2 UI Interaction Agent
状态：completed_with_test_rule_conflict

修改文件：
- Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift

修复内容：
1. 搜索无内容外点：
   - 外部普通区域点击只关闭搜索框，不走清空逻辑。
2. 搜索有内容外点：
   - 新增 / 复用 `hasSearchContent`，包含文字、token、筛选条件。
   - 有内容点击普通外部区域保持展开和内容。
3. 搜索有内容点击其他分组：
   - `closeSearchForGroupNavigation()` 保持 `clearAndCloseSearch()`。
4. 搜索内部点击：
   - 搜索框、清空按钮、筛选按钮、筛选面板继续通过 excluded frames / popover frame 排除外部点击。
5. 新卡片加入：
   - 新内容触发 latest focus 时额外 `HistoryScrollCoordinator.shared.saveOffset(0)`，避免第二 / 第三页旧 offset 盖住新卡片定位。
6. 边缘半露卡片：
   - reveal 判断改为同一 `historyWindow` 坐标系边界，点击左右半露卡片触发 animated absolute scroll，完整可见卡片不滚动。

验证结果：
- swift build：PASS
- git diff --check：PASS
- python3 scripts/verify_history_card_scroll_alignment.py：PASS
- python3 scripts/verify_no_management_no_favorite_ui.py：PASS
- python3 scripts/verify_history_window_interaction_toast.py：FAIL

测试失败原因：
- `verify_history_window_interaction_toast.py` 仍按旧规则要求 `outside click must clear search text, tokens, and filters`。
- 该断言与第 220 节和 `GUARD-V2-SEARCH-001` 最新规则冲突：
  - 搜索有内容时点击普通外部区域不得关闭搜索，也不得清空内容。
  - 搜索有内容时点击其他分组才关闭并清空。

主控裁定：
- 不因旧测试口径失败退回 UI。
- 调度 Test Agent 更新测试脚本 / 测试口径，按最新 GUARD-V2-SEARCH-001 验证。
- 更新测试脚本属于测试范围，不是业务代码修复。
- 更新后必须重跑相关脚本、swift build、git diff --check，并进入 Review / Acceptance。
```

## 222. 维修阶段第四轮测试口径更新与复测记录

```text
任务卡：V2-TEST-MAINT4-HISTORY-RUNTIME-INTERACTION-20260515
时间：2026-05-15
阶段：维修阶段 / 第四轮搜索新规则测试口径更新
当前会话模式：ClipEase V2 Test Agent
状态：PASS，可进入 Review

修改文件：
- scripts/verify_history_window_interaction_toast.py

修改范围：
- 仅更新测试脚本以匹配第 220 节和 GUARD-V2-SEARCH-001 最新搜索规则。
- 未修改业务代码。
- 未修改 docs/V2_TEST_PLAN.md。

新测试口径：
- closeSearchFromOutsideClick() 不再要求无条件 clearAndCloseSearch()。
- 无内容外点通过 closeSearch() 关闭。
- 有文字 / token / filter 时外点通过 hasSearchContent guard 保持展开和内容。
- 分组导航仍走 clearAndCloseSearch() 清空关闭。
- 搜索框内部、筛选面板、popover / excluded frames 不触发 outside close。

已执行并通过：
- python3 scripts/verify_history_window_interaction_toast.py
- python3 scripts/verify_history_card_scroll_alignment.py
- python3 scripts/verify_no_management_no_favorite_ui.py
- swift build
- git diff --check

静态核对通过：
- empty outside click closes only：PASS
- content outside click keeps search：PASS
- group navigation clears and closes：PASS
- search internal and filter panel excluded：PASS
- latest card positioning structure：PASS
- edge reveal animation structure：PASS

未执行：
- 真实 App 点击运行态验证。
- 真实第二 / 第三页新卡片定位验证。
- 真实左右半露卡片动画验证。

后续：
- 调度 Review Agent 审查业务逻辑和测试脚本是否共同符合最新搜索规则。
- Review PASS 后调度 Acceptance，仅允许本地运行给用户人工测试。
```

## 223. 维修阶段第四轮 Review HOLD 与返工调度

```text
任务卡组：V2-MAINT4-HISTORY-RUNTIME-20260515
时间：2026-05-15
阶段：维修阶段 / 第四轮 Review HOLD
当前会话模式：ClipEase V2 Main Controller Agent

Review Agent：
- 任务卡：V2-REVIEW-MAINT4-HISTORY-RUNTIME-INTERACTION-20260515
- 结论：HOLD，不可进入 Acceptance。

Review 阻塞项：
1. Resources/Info.plist 版本号差异命中红线：
   - 该差异为历史共享工作树 / 版本边界遗留。
   - 主控裁定：本轮返工不得修改或回退 Info.plist；该项继续作为最终集成 / release 前红线确认门禁保留。
   - 不将其交给 UI / Test Agent 处理。
2. 搜索“普通外部区域”覆盖不足：
   - 当前 outside observer 只在两个空态和卡片 ScrollView 背景挂载。
   - 未覆盖 toolbar / topTrack 外的普通空白区域。
   - 无内容搜索时点击这些区域可能不关闭搜索框。
3. 测试脚本覆盖不足：
   - `verify_history_window_interaction_toast.py` 使用 `view.count("SearchOutsideMouseDownObserver") >= 4` 判断覆盖，会把 struct 定义也计入，无法证明 toolbar / 普通外部区域被观察。

主控裁定：
- Acceptance 继续 HOLD。
- 返工只处理阻塞 2、3。
- 阻塞 1 继续作为红线集成门禁保留，不由本轮 Agent 修改或回退。

返工任务卡 A：
- ID：V2-BUGFIX-MAINT4-SEARCH-OUTSIDE-REGION-COVERAGE-001
- 负责 Agent：UI Interaction Agent
- 允许修改：
  - Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift
- 禁止修改：
  - Resources/Info.plist
  - ClipboardMonitor.swift、ClipboardHistoryStore.swift、HistoryPreviewWindowController.swift、HistoryPreviewPopoverView.swift、GlobalStatusToastController.swift
  - 构建脚本、发布流程、SQLite schema、JSON / favorite / management / multi / batch 相关代码
- 目标：
  - 在不覆盖搜索框内部 / 清空 / 筛选按钮 / 筛选面板的前提下，覆盖 toolbar / topTrack 普通外部空白区域。
  - 按最新规则：无内容外点关闭；有内容普通外点保持；分组导航清空关闭。
- 完成标准：
  - 普通外部区域 observer 覆盖有明确代码结构，不依赖计数凑脚本。
  - 搜索内部与 popover 点击仍不关闭。

返工任务卡 B：
- ID：V2-TEST-MAINT4-SEARCH-OUTSIDE-REGION-COVERAGE-001
- 负责 Agent：Test Agent
- 允许修改：
  - scripts/verify_history_window_interaction_toast.py
- 目标：
  - 修复脚本 overcount 问题，不把 struct 定义计入 observer coverage。
  - 增加对 toolbar / topTrack 普通外部区域 observer 覆盖的静态断言。
  - 保持新搜索三分支规则断言。

后续：
- A / B 完成后重跑 swift build、git diff --check、verify_history_window_interaction_toast.py、verify_history_card_scroll_alignment.py、verify_no_management_no_favorite_ui.py。
- 再调度 Review。
```

## 224. 维修阶段第四轮搜索外部区域覆盖返工完成记录

```text
任务卡组：V2-MAINT4-HISTORY-RUNTIME-20260515
时间：2026-05-15
阶段：维修阶段 / 第四轮返工完成待复核
当前会话模式：ClipEase V2 Main Controller Agent

UI 返工任务：
- ID：V2-BUGFIX-MAINT4-SEARCH-OUTSIDE-REGION-COVERAGE-001
- 负责 Agent：UI Interaction / Bugfix Agent
- 状态：COMPLETED，待 Test / Review / Acceptance 复核。

修改文件：
- Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift

完成内容：
- 在 toolbar 背景挂载 SearchOutsideMouseDownObserver，覆盖 toolbar 普通外部空白区域。
- 在 topTrack 横向轨道背景挂载 SearchOutsideMouseDownObserver，覆盖 topTrack 普通外部空白区域。
- 为 outside observer 增加 hitTest 跳过逻辑，避免搜索框内部、清空按钮、筛选按钮、其他按钮 / 文本输入被普通外点处理。
- 分组导航仍走 GroupMouseDownObserver，保持“搜索有内容时点击其他分组关闭并清空”。

Agent 自测通过：
- swift build
- git diff --check
- python3 scripts/verify_history_window_interaction_toast.py
- python3 scripts/verify_no_management_no_favorite_ui.py

仍需门禁：
- Test Agent 复测：搜索三分支规则、toolbar/topTrack 覆盖、新卡片定位、边缘半露卡片平移、禁用管理/收藏回归。
- Review Agent 审查：outside observer 不误覆盖搜索内部控件，分组导航清空关闭逻辑不被破坏，新卡片定位和边缘卡片动画逻辑没有回退。
- Acceptance Agent 放行后，主控执行本地构建运行 App 供用户人工测试。

红线状态：
- Resources/Info.plist 版本号差异仍为历史红线集成门禁；本轮不得修改或回退，最终集成 / release 前需用户确认。
```

## 225. 维修阶段第四轮最终测试通过与 Review HOLD 处理决策

```text
任务卡组：V2-MAINT4-HISTORY-RUNTIME-20260515
时间：2026-05-15
阶段：维修阶段 / 第四轮门禁复核
当前会话模式：ClipEase V2 Main Controller Agent

Test Agent：
- 任务卡：V2-TEST-MAINT4-FINAL-HISTORY-RUNTIME-INTERACTION-20260515
- 结论：PASS
- 修改文件：无
- 已执行并通过：
  - python3 scripts/verify_history_window_interaction_toast.py
  - python3 scripts/verify_history_card_scroll_alignment.py
  - python3 scripts/verify_no_management_no_favorite_ui.py
  - swift build
  - git diff --check

Review Agent：
- 任务卡：V2-REVIEW-MAINT4-FINAL-HISTORY-RUNTIME-INTERACTION-20260515
- 结论：HOLD
- 阻塞原因：
  - 搜索三分支逻辑静态符合 GUARD-V2-SEARCH-001。
  - toolbar / topTrack observer 静态结构已补齐。
  - 新卡片定位和半露卡片平移静态结构可触发。
  - 但 Review 认为当前测试仍为结构检查，无法证明 AppKit / SwiftUI 运行态 hitTest、toolbar/topTrack 空白点击、搜索内部控件、分组按钮互不干扰。

主控裁定：
- 本轮 HOLD 不是新的业务代码缺陷，而是运行态交互证明缺口。
- 不继续安排 Bugfix Agent 盲改业务代码，避免在未复现前扩大风险。
- 进入本地运行态人工验证：主控构建并运行 App，交由用户验证以下路径：
  1. 搜索无内容，点击搜索框外部普通区域，应关闭搜索框。
  2. 搜索有文字 / token / filter，点击普通外部区域，应不关闭、不清空。
  3. 搜索有内容，点击其他分组，应关闭并清空。
  4. 搜索框内部、清空按钮、筛选按钮、筛选面板点击不应触发外部关闭。
  5. 从第二 / 第三页滚动位置新增剪切板卡片后，应定位并显示新卡片。
  6. 点击左右边缘半露卡片，应动画平移到完整展示并露出下一张约 1/6。

红线状态：
- Resources/Info.plist 版本号 / build 差异继续作为最终集成 / release 红线门禁保留，本轮不修改、不回退。
```

## 226. 维修阶段第四轮本地构建运行记录

```text
任务卡组：V2-MAINT4-HISTORY-RUNTIME-20260515
时间：2026-05-15
阶段：维修阶段 / 用户运行态验证
当前会话模式：ClipEase V2 Main Controller Agent

构建：
- swift build：PASS

运行：
- 先尝试临时 .build/ClipEase.app bundle 运行，进程未驻留，未产生有效错误日志。
- 改用 SwiftPM debug 产物运行：
  - .build/arm64-apple-macosx/debug/ClipEase
  - PID：66626
  - 日志：/tmp/clipease-maint4.log

用户需重点测试：
- 搜索无内容时点击搜索框外部普通区域，应关闭搜索框。
- 搜索有内容时点击普通外部区域，应不关闭、不清空。
- 搜索有内容时点击其他分组，应关闭并清空。
- 搜索框内部、清空按钮、筛选按钮、筛选面板点击不应触发外部关闭。
- 从第二 / 第三页滚动位置新增剪切板卡片后，应定位并显示新卡片。
- 点击左右边缘半露卡片，应动画平移到完整展示并露出下一张约 1/6。

后续：
- 若用户仍复现问题，按具体复现路径拆分精确任务卡，避免继续泛化修复。
```

## 227. 维修阶段第五轮运行态复现与返工调度

```text
任务卡组：V2-MAINT5-HISTORY-RUNTIME-INTERACTION-20260515
时间：2026-05-15
阶段：维修阶段 / 第五轮运行态反馈
当前会话模式：ClipEase V2 Main Controller Agent

用户运行态复现：
1. 搜索框展开且无内容时，点击搜索框内部会关闭搜索框。
2. 搜索框展开且无内容时，点击搜索框内部关闭后，用户输入文字时搜索框没有展开。
3. 主窗口左右两侧半露卡片，点击时没有向左 / 右平移到完整露出选中卡片，并露出下一张约 1/6。
4. 新卡片加入后虽然被选中，但未强制平移到可见位置；若用户此前滚到第 20 条左右，新增卡片应选中新卡片并滚回该新卡片目标位置：
   - 无置顶 / 无前置：新卡片作为当前视口第一个卡片，左侧留白区域也显示，等价于向左滚动到头。
   - 有置顶 / 有前置：新卡片位于置顶 / 前置卡片右侧第一位，并露出上一张约 1/6。

问题归类：
- Bugfix / UI Interaction。
- 小范围主窗口交互缺陷，未涉及 schema / Repository / JSON / 数据迁移。

风险级别：
- P1：搜索框内部点击误关闭会直接破坏搜索输入。
- P1：新卡片定位和半露卡片平移为主窗口核心导航交互，用户连续复现。

任务卡：
- ID：V2-BUGFIX-MAINT5-HISTORY-RUNTIME-INTERACTION-001
- 负责 Agent：Bugfix Agent / UI Interaction Agent
- 允许修改：
  - Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift
  - 如必须补充静态守卫，可修改 scripts/verify_history_window_interaction_toast.py / scripts/verify_history_card_scroll_alignment.py
- 禁止修改：
  - Resources/Info.plist
  - SQLite schema / Repository / JSON fallback / 数据迁移
  - 管理模式、收藏、多选 / 批量相关功能
  - ClipboardMonitor / PasteExecutor / Quick Look / 全局提示层，除非明确证明为当前 bug 必需

修复目标：
1. 搜索框展开后，搜索框内部任意区域点击不得触发 outside close；无内容时也必须保持展开和焦点，用户继续输入时搜索框保持展开。
2. 保持最新规则：
   - 无内容点击真正外部区域：关闭搜索框。
   - 有内容点击普通外部区域：不关闭、不清空。
   - 有内容点击其他分组：关闭并清空。
3. 半露卡片点击时必须按点击侧向左 / 右平移动画滚动，使被点击卡片完整显示，并额外露出下一张约 1/6。
4. 新卡片加入时必须覆盖当前滚动 offset，强制滚动到新卡片目标位置；不能只更新选中状态。

完成标准：
- swift build PASS
- git diff --check PASS
- python3 scripts/verify_history_window_interaction_toast.py PASS 或说明脚本同步更新原因
- python3 scripts/verify_history_card_scroll_alignment.py PASS 或说明脚本同步更新原因
- python3 scripts/verify_no_management_no_favorite_ui.py PASS
- 给出运行态需人工验证路径。
```

## 228. 维修阶段第五轮 Bugfix 完成记录

```text
任务卡：V2-BUGFIX-MAINT5-HISTORY-RUNTIME-INTERACTION-001
时间：2026-05-15
阶段：维修阶段 / 第五轮 Bugfix 完成待复核
当前会话模式：ClipEase V2 Main Controller Agent

负责 Agent：
- Bugfix / UI Interaction Agent
- 状态：COMPLETED，待 Test / Review / Acceptance。

修改文件：
- Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift

修复内容：
- 新增 SearchInteractionScreenFrameReader，把搜索框真实屏幕区域加入 outside-click 白名单，避免搜索框展开且无内容时点击内部空白被误判为外部点击。
- 保留最新搜索三分支规则：
  - 无内容外部普通点击：关闭搜索框。
  - 有内容外部普通点击：不关闭、不清空。
  - 有内容点击其他分组：关闭并清空。
- 半露卡片 reveal 改用 HistoryScrollCoordinator.visibleRectInHistoryWindow 的真实可见区域计算左右裁切，并触发 animated absolute scroll。
- 新卡片 focus 时先覆盖旧 offset 并 scrollToOffset(0, animated: false)，测量后按目标卡片做绝对滚动；增加下一 runloop 二次校准，降低旧 offset 抢回视口风险。

Agent 自测通过：
- swift build
- git diff --check
- python3 scripts/verify_history_window_interaction_toast.py
- python3 scripts/verify_history_card_scroll_alignment.py
- python3 scripts/verify_no_management_no_favorite_ui.py

剩余风险：
- 半露卡片点击实际动画距离、新卡片加入后的运行态滚动位置仍需真机窗口人工验证。
- Resources/Info.plist 历史版本差异仍为最终集成红线门禁；本轮未修改。
```

## 229. 维修阶段第五轮测试与审查门禁记录

```text
任务卡组：V2-MAINT5-HISTORY-RUNTIME-INTERACTION-20260515
时间：2026-05-15
阶段：维修阶段 / 第五轮门禁复核
当前会话模式：ClipEase V2 Main Controller Agent

Test Agent：
- 任务卡：V2-TEST-MAINT5-HISTORY-RUNTIME-INTERACTION-20260515
- 结论：PASS
- 修改文件：无
- 已执行并通过：
  - python3 scripts/verify_history_window_interaction_toast.py
  - python3 scripts/verify_history_card_scroll_alignment.py
  - python3 scripts/verify_no_management_no_favorite_ui.py
  - swift build
  - git diff --check

Review Agent：
- 任务卡：V2-REVIEW-MAINT5-HISTORY-RUNTIME-INTERACTION-20260515
- 结论：PASS
- 阻塞问题：无

Review 关键结论：
- SearchInteractionScreenFrameReader 上报搜索框真实屏幕 frame，outside observer 排除该白名单区域，可覆盖搜索框内部空白、输入区、token、清空按钮、筛选按钮。
- 筛选 popover window frame 纳入可见 popover frame；popover 自身事件不会触发 outside close。
- 最新 GUARD-V2-SEARCH-001 三分支保持：
  - hasSearchContent 覆盖文字、token、active filters。
  - 普通外点仅在无内容时 closeSearch()。
  - 分组导航统一 clearAndCloseSearch()。
- 新卡片 focus 会先 saveOffset(0) 并 scrollToOffset(0, animated: false)，再等待目标测量后滚动并做一次 next-runloop 校准。
- 半露卡片 reveal 使用 visible rect 坐标：左裁切减小 absolute offset，右裁切增大 absolute offset，并 animated scroll。
- 未发现触碰 Info.plist、schema、Repository、JSON fallback、管理模式、收藏、多选 / 批量红线。

非阻塞风险：
- 真实运行态动画距离、popover window 识别、新卡片二次校准视觉稳定性仍需用户人工验收。

后续：
- 主控执行本地构建并运行 App，交由用户测试第五轮修复。
```

## 230. 维修阶段第五轮本地构建运行记录

```text
任务卡组：V2-MAINT5-HISTORY-RUNTIME-INTERACTION-20260515
时间：2026-05-15
阶段：维修阶段 / 用户运行态验证
当前会话模式：ClipEase V2 Main Controller Agent

构建：
- swift build：PASS

运行：
- 使用 SwiftPM debug 产物运行：
  - .build/arm64-apple-macosx/debug/ClipEase
  - PID：2117
  - 日志：/tmp/clipease-maint5.log

用户需验证：
1. 搜索框展开无内容时，点击搜索框内部不关闭，输入文字后仍保持展开。
2. 搜索框展开无内容时，点击真正外部区域关闭。
3. 搜索框有内容时，点击普通外部区域不关闭、不清空；点击其他分组关闭并清空。
4. 左右半露卡片点击后向对应方向平移，完整显示选中卡片并露出下一张约 1/6。
5. 用户滚到第 20 条左右后复制新内容，新卡片应被选中且强制滚动到目标位置：
   - 无置顶：滚到最左，左侧留白显示。
   - 有置顶 / 前置：新卡片位于置顶右侧第一位，并露出上一张约 1/6。
```

## 231. 维修阶段第五轮用户验收失败与第六轮返工调度

```text
任务卡组：V2-MAINT6-HISTORY-RUNTIME-INTERACTION-20260515
时间：2026-05-15
阶段：维修阶段 / 第六轮运行态反馈
当前会话模式：ClipEase V2 Main Controller Agent

用户验收结果：
- 第五轮第 1 项“搜索框内部点击不关闭”已视为改善。
- 第五轮第 2 / 3 / 4 项仍未修复。

仍复现问题：
1. 搜索框展开且无内容时，点击真正外部区域没有按要求关闭搜索框。
2. 主窗口左右两侧半露卡片，点击时没有向左 / 右平移到完整露出选中卡片，并露出下一张约 1/6。
3. 新卡片加入后虽然有选中状态，但没有强制平移显示出新卡片；如果用户此前滚动到第 20 条左右，新卡片加入后必须回到新卡片目标视口：
   - 无置顶 / 无前置：新卡片在当前视口第一张，左侧留白区域也显示，等价于滚到最左。
   - 有置顶 / 前置：新卡片在置顶 / 前置卡片右侧第一张，并露出上一张约 1/6。

主控复盘：
- 第五轮 Test / Review 均 PASS，但用户运行态验收失败。
- 当前问题不能继续用单纯结构字符串检查判定完成。
- 第六轮必须要求 Bugfix Agent 以运行态事件路径和可见滚动结果为目标，避免只更新 focus / selected 状态。

任务卡：
- ID：V2-BUGFIX-MAINT6-HISTORY-RUNTIME-INTERACTION-001
- 负责 Agent：Bugfix Agent / UI Interaction Agent
- 允许修改：
  - Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift
  - 如必须强化守卫，可修改 scripts/verify_history_window_interaction_toast.py / scripts/verify_history_card_scroll_alignment.py
- 禁止修改：
  - Resources/Info.plist
  - SQLite schema / Repository / JSON fallback / 数据迁移
  - 管理模式、收藏、多选 / 批量相关功能
  - ClipboardMonitor / PasteExecutor / Quick Look / 全局提示层，除非明确证明为当前 bug 必需并停止说明

修复要求：
1. 搜索框展开且无内容时，真正外部区域点击必须关闭搜索框；搜索框内部仍不得关闭。
   - 不得仅依赖不可靠的透明 background / NSViewRepresentable 命中。
   - 如 SwiftUI/AppKit hitTest 导致普通空白区域事件被吃掉，应改为更稳定的窗口级 local mouse monitor，并用 screen frame / popover frame / group click 规则分流。
2. 半露卡片点击必须基于当前可见 viewport 和卡片 frame 计算目标 offset，点击左侧半露卡片向左滚、点击右侧半露卡片向右滚。
   - 目标结果：被点击卡片完整展示，并额外露出下一张约 1/6。
   - 必须处理当前 offset、最大 offset、左侧留白、前置/置顶卡片。
3. 新卡片加入必须触发可见滚动，不只是选中。
   - 如果用户此前滚到第 20 条左右，新增卡片必须强制重置到新卡片位置。
   - 无置顶：目标 offset 为最左，左侧留白可见。
   - 有置顶 / 前置：目标 offset 应让新卡片位于前置卡片右侧，并露出上一张约 1/6。

完成标准：
- swift build PASS
- git diff --check PASS
- python3 scripts/verify_history_window_interaction_toast.py PASS 或同步更新说明
- python3 scripts/verify_history_card_scroll_alignment.py PASS 或同步更新说明
- python3 scripts/verify_no_management_no_favorite_ui.py PASS
- 必须给出“为什么第 2/3/4 项这次在运行态会生效”的代码级说明。
- 主控重启 App 后由用户再次验收；若仍失败，升级为 UI 架构缺陷分析，不再继续局部打补丁。
```

## 232. 维修阶段第六轮 Agent 中断与拆卡处理

```text
任务卡：V2-BUGFIX-MAINT6-HISTORY-RUNTIME-INTERACTION-001
时间：2026-05-15
阶段：维修阶段 / 第六轮返工中断
当前会话模式：ClipEase V2 Main Controller Agent

执行结果：
- Bugfix Agent 因 429 Too Many Requests 超过重试上限中断。
- 未返回完成报告、修改文件清单、验证结果。
- 主控不得将该任务视为完成。

主控检查：
- 当前 HistoryWindowView.swift 已存在 SearchOutsideWindowMouseDownObserver 等疑似半成品代码。
- 由于共享工作树本身差异很大，且 Agent 未完成报告，主控不回退、不归档为完成修复。

处理决策：
- 不继续使用大而全任务卡，避免再次超时或留下不可验收半成品。
- 拆分为串行小任务：
  1. V2-BUGFIX-MAINT6A-SEARCH-OUTSIDE-CLOSE-001：只修搜索真正外部区域点击关闭，搜索内部不关闭。
  2. V2-BUGFIX-MAINT6B-CARD-SCROLL-VISIBILITY-001：只修半露卡片点击平移和新卡片加入强制可见滚动。

任务卡 A：
- ID：V2-BUGFIX-MAINT6A-SEARCH-OUTSIDE-CLOSE-001
- 负责 Agent：Bugfix / UI Interaction Agent
- 允许修改：
  - Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift
  - scripts/verify_history_window_interaction_toast.py（仅当守卫需同步）
- 禁止修改：
  - Resources/Info.plist
  - SQLite schema / Repository / JSON fallback / 数据迁移
  - 管理模式、收藏、多选 / 批量相关功能
  - 卡片滚动逻辑，除非仅为避免编译错误
- 验收目标：
  - 搜索框展开且无内容，点击搜索框内部任意区域不关闭。
  - 搜索框展开且无内容，点击真正外部区域必须关闭。
  - 搜索框有内容，点击普通外部区域不关闭、不清空。
  - 搜索框有内容，点击其他分组关闭并清空。
```

## 233. 维修阶段第六轮小卡 A 搜索外部关闭完成记录

```text
任务卡：V2-BUGFIX-MAINT6A-SEARCH-OUTSIDE-CLOSE-001
时间：2026-05-15
阶段：维修阶段 / 第六轮拆卡 A 完成待复核
当前会话模式：ClipEase V2 Main Controller Agent

负责 Agent：
- Bugfix / UI Interaction Agent
- 状态：COMPLETED，待最终 Test / Review。

修改文件：
- Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift
- scripts/verify_history_window_interaction_toast.py

修复内容：
- 移除 / 不再使用旧区域级 SearchOutsideMouseDownObserver，保留单一窗口级 SearchOutsideWindowMouseDownObserver。
- 窗口级 observer 显式传入 hostWindow，避免依赖 NSViewRepresentable 自身 view.window 时机。
- updateNSView 持续同步 isEnabled、hostWindow、excludedFrames，并确保 local mouse monitor 存在。
- 搜索内部白名单改为仅使用真实 AppKit screen frame：
  - searchControlScreenFrame.standardized.insetBy(dx: -6, dy: -6)
  - 不再叠加 SwiftUI geometry frame，避免过宽 frame 包住真正外部区域。
- 筛选 popover frame 继续加入 excludedFrames。
- 同步 verify_history_window_interaction_toast.py，检查单一窗口级 observer 实现。

预期运行态效果：
- 搜索展开且无内容时，真正外部点击进入 closeSearchFromOutsideClick() 并关闭。
- 搜索内部、清空按钮、筛选按钮、筛选面板点击被 screen frame / popover frame 排除，不关闭。
- 搜索有内容普通外点仍被 hasSearchContent guard 保持。
- 分组点击仍由 GroupMouseDownObserver 走 closeSearchForGroupNavigation()，清空并关闭。

Agent 自测通过：
- swift build
- git diff --check
- python3 scripts/verify_history_window_interaction_toast.py
- python3 scripts/verify_no_management_no_favorite_ui.py

未覆盖：
- 真实 UI 人工点击仍需主控运行 App 后由用户验收。

任务卡 B：
- ID：V2-BUGFIX-MAINT6B-CARD-SCROLL-VISIBILITY-001
- 负责 Agent：Bugfix / UI Interaction Agent
- 允许修改：
  - Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift
  - scripts/verify_history_card_scroll_alignment.py（仅当守卫需同步）
- 禁止修改：
  - 搜索外部关闭逻辑，除非仅为避免编译错误
  - Resources/Info.plist
  - SQLite schema / Repository / JSON fallback / 数据迁移
  - 管理模式、收藏、多选 / 批量相关功能
- 验收目标：
  - 主窗口左右两侧半露卡片，点击时按方向平移到选中卡片完整可见，并露出下一张约 1/6。
  - 新卡片加入后强制滚动到新卡片目标位置，不只是 selected/focus。
```

## 234. 维修阶段第六轮小卡 B 卡片滚动可见完成记录

```text
任务卡：V2-BUGFIX-MAINT6B-CARD-SCROLL-VISIBILITY-001
时间：2026-05-15
阶段：维修阶段 / 第六轮拆卡 B 完成待复核
当前会话模式：ClipEase V2 Main Controller Agent

负责 Agent：
- Bugfix / UI Interaction Agent
- 状态：COMPLETED，待合并 Test / Review。

修改文件：
- Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift
- scripts/verify_history_card_scroll_alignment.py

修复内容：
- 半露卡片点击不再用 historyWindow / window 坐标叠加 currentOffset 推算。
- 改用 NSScrollView.contentView.bounds 的真实 document viewport。
- 新增 cardDocumentFrame(for:)，按 renderedItems index、horizontalContentPadding、historyCardWidth、horizontalCardSpacing 计算卡片在滚动文档里的绝对位置。
- 左侧半露点击目标 offset：
  - card document minX - 上一张约 1/6 peek + spacing
- 右侧半露点击目标 offset：
  - card document maxX + 下一张约 1/6 peek + spacing - viewport 宽度
- 目标 offset 通过真实 scrollToOffset(..., animated: true) 执行。
- 新卡片加入路径继续先 saveOffset(0) + scrollToOffset(0, animated: false) 覆盖旧 offset。
- frame 未就绪时通过 pendingItemScrollRetryCount < pendingItemScrollMaxRetryCount 有限重试，并在下一 runloop 做二次校准。
- 无前置时第一张目标 offset 为 0；有置顶 / 前置时目标 offset 让新卡片位于前置右侧第一张并露出上一张约 1/6。

Agent 自测通过：
- swift build
- git diff --check
- python3 scripts/verify_history_card_scroll_alignment.py
- python3 scripts/verify_no_management_no_favorite_ui.py

预期运行态效果：
- 半露卡片点击判断和目标 offset 都在 contentView.bounds 同一坐标系内，不再混用 SwiftUI named coordinate / window coordinate。
- 新卡片加入后直接覆盖旧 offset 并以 document absolute offset 对齐目标卡片，不只停留在 selected/focus 状态。

未覆盖：
- 真实 UI 动画距离和复制新内容后的视觉定位仍需用户运行态验收。
```

## 235. 维修阶段第六轮合并测试通过与运行准备

```text
任务卡组：V2-MAINT6-HISTORY-RUNTIME-INTERACTION-20260515
时间：2026-05-15
阶段：维修阶段 / 第六轮合并门禁通过待运行
当前会话模式：ClipEase V2 Main Controller Agent

Test Agent：
- 任务卡：V2-TEST-MAINT6-HISTORY-RUNTIME-INTERACTION-20260515
- 结论：PASS
- 修改文件：无
- 已执行并通过：
  - python3 scripts/verify_history_window_interaction_toast.py
  - python3 scripts/verify_history_card_scroll_alignment.py
  - python3 scripts/verify_no_management_no_favorite_ui.py
  - swift build
  - git diff --check

Review Agent：
- 任务卡：V2-REVIEW-MAINT6-HISTORY-RUNTIME-INTERACTION-20260515
- 结论：待回收 / 超时，未给出最终阻塞结论。

主控裁定：
- 目前可确认 A/B 的静态门禁已通过。
- 为避免旧 bundle 误导用户测试，主控将使用最新 SwiftPM debug 产物运行 App。
- 真实运行态仍需用户测试：
  1. 搜索无内容时真正外部点击是否关闭。
  2. 半露卡片点击是否真正滚到选中卡片完整可见。
  3. 新卡片加入后是否真正滚到新卡片目标位置，而不只改选中状态。
```

## 236. 维修阶段第六轮 Review HOLD 记录

```text
任务卡组：V2-MAINT6-HISTORY-RUNTIME-INTERACTION-20260515
时间：2026-05-15
阶段：维修阶段 / 第六轮审查 HOLD
当前会话模式：ClipEase V2 Main Controller Agent

Review Agent：
- 任务卡：V2-REVIEW-MAINT6-HISTORY-RUNTIME-INTERACTION-20260515
- 结论：HOLD

阻塞项：
- `Resources/Info.plist` 第 15 / 17 行仍在改 `CFBundleShortVersionString` 与 `CFBundleVersion`。
- 按 `docs/V2_AGENT_COLLABORATION.md` 红线规则，该项直接阻塞本轮放行。

非阻塞结论：
- 搜索外部关闭链路、半露卡片滚动链路、新卡片覆盖旧 offset 的代码级逻辑未见新的阻塞缺陷。
- 两个静态守卫脚本与当前代码一致并已通过。
- `verify_history_selection_focus.py` 有一条旧断言失败，但不作为本轮主阻塞。

主控裁定：
- 当前只剩版本 / 构建号红线门禁；等用户确认是否接受该集成差异后，再决定是否进入最终收口。
```

## 237. 主控协作规则同步记录

```text
同步 ID：V2-MAIN-CONTROLLER-RULES-SYNC-20260515-001
时间：2026-05-15
同步范围：ClipEase 第二版主控协作规则、bug 分诊闭环、测试计划前置、反馈守卫和 runbook 记录方式
规则来源：
- docs/PROJECT_GUIDE.md
- docs/V2_AGENT_COLLABORATION.md
- docs/agents/README.md
- docs/agents/main-controller-agent.md
- docs/agents/bugfix-agent.md
- docs/agents/v2-test-plan-agent.md
- docs/V2_FEEDBACK_AND_GUARDS.md
- docs/V2_AGENT_RUNBOOK.md
- docs/V2_OPTIMIZATION_BACKLOG.md
- docs/V2_PRODUCT_PLAN.md
- docs/V2_TECHNICAL_PLAN.md
- docs/V2_DEVELOPMENT_PLAN.md
- docs/V2_TEST_PLAN.md
主控执行边界：
- 主控 Agent 不写业务代码。
- 主控 Agent 不亲自修 bug。
- 用户反馈 bug 后，主控只负责记录、复现、归类、定级、生成 Bug 修复任务卡和调度。
Bug 分诊规则：
- 小范围 bug 交给 Bugfix Agent。
- 原模块核心逻辑缺陷退回原开发 Agent。
- 架构 / schema / Repository / 性能问题交给架构守门 Agent + 原开发 Agent。
- 产品规则冲突交给产品规则 Agent + 用户确认。
- 测试缺口交给测试 Agent。
测试计划前置：
- docs/V2_TEST_PLAN.md 的维护交给 V2 测试计划 Agent。
- 每次阶段开始前，先调用 V2 测试计划 Agent 检查测试 / 验收门禁是否完整。
反馈守卫要求：
- 每次处理 bug、返工或新增功能前，必须读取 docs/V2_FEEDBACK_AND_GUARDS.md。
- Bug 修复任务卡必须包含关联历史反馈、关联功能守卫、受影响功能、不得回归项和最小回归测试。
- 修复后测试 Agent 必须回归原失败路径和相关功能守卫。
非阻塞项归档：
- 非阻塞项写入 docs/V2_OPTIMIZATION_BACKLOG.md。
Runbook 记录要求：
- 调度、沟通、文件锁、冲突、bug 修复和功能守卫记录写入 docs/V2_AGENT_RUNBOOK.md。
是否修改业务代码：否。
后续默认执行方式：从本记录开始，主控 Agent 后续收到阶段推进或 bug 反馈时，默认按以上规则执行。
```

## 238. 维修阶段第七轮用户反馈分诊与调度

```text
Bug ID：V2-MAINT7-USER-FEEDBACK-20260515
时间：2026-05-15
来源阶段：维修阶段 / 第七轮运行态反馈
反馈来源：用户运行态反馈 + 两张参考图
当前会话模式：ClipEase V2 Main Controller Agent

主控边界：
- 主控只记录、复现意图、归类、定级、生成 Bug 修复任务卡和调度。
- 主控不写业务代码、不亲自修 bug。
- 本轮处理前已读取 docs/V2_FEEDBACK_AND_GUARDS.md 和相关 runbook 历史记录。

用户反馈：
1. 搜索框展开且无内容时，点击搜索框内部会关闭搜索框。
2. 主窗口左右两侧半露卡片，点击时应向左 / 右平移，露出选中的卡片，并露出下一张约 1/6。
3. 新卡片加入后当前只选中新卡片，但未强制平移显示新卡片；用户在第 20 条左右时，新卡片加入后必须滚回新卡片目标位置：
   - 无置顶 / 无前置：新卡片在当前视口第一张，左侧留白区域也显示，等价于滚到最左。
   - 有置顶 / 前置：新卡片在置顶 / 前置卡片右侧第一张，并露出上一张约 1/6。
4. 剪贴板获取链接卡片时，标题要后台立刻获取，而不是编辑卡片后点击保存才获取。
5. 链接卡片内容里标题离 URL 太远，不要有中间的大间隙；参考用户提供的链接卡片图。
6. 轻贴获取剪贴板内容时，不要忽略任何内容；所有文件、内容都应获取。目前复制 README.md 文件不会记录卡片。
7. 文本卡片内容参照用户提供的文本卡片图，内容要占满整个区域，下方有淡化效果，超出显示 “...”。
8. 图片卡片图片区域应按比例尽量占满上下或左右：竖长图上下占满、左右可留白；横长图左右占满、上下可留白；可正好占满时上下左右不留白。

历史反馈关联：
- 第 203-236 节多轮运行态反馈中，搜索内部 / 外部点击、新卡片定位、半露卡片平移已多次返工。
- 第 236 节仍因版本号红线 HOLD，但用户本轮继续确认 1-3 运行态失败。

风险等级：
- 1-3：高；HistoryWindow 真实运行态核心交互多轮返工未闭环，升级为 UI 交互核心缺陷，不再继续交普通 Bugfix Agent 盲改。
- 4 / 6：高；涉及 ClipboardMonitor、链接标题抓取、文件捕获和 Store 写入核心路径，交 Clipboard / Link Capture 原开发方向 + 架构守门复核。
- 5 / 7 / 8：中；卡片视觉布局和内容裁切，交 UI Card Layout Bugfix Agent，限定 HistoryCardView / 视觉脚本。

关联功能守卫：
- GUARD-V2-BASELINE-001：SQLite-only 运行时基线。
- GUARD-V2-BASELINE-002：收藏 / 管理模式移除基线。
- GUARD-V2-GROUP-001：分组能力保留。
- GUARD-V2-SEARCH-001：搜索筛选交互守卫。
- GUARD-V2-UI-001：顶部轨道和分组滚动守卫。

受影响功能：
- 搜索框展开 / 内外部点击命中。
- 主窗口横向滚动、半露卡片点击 reveal、新卡片定位。
- 链接剪贴板捕获、标题抓取、链接卡片展示。
- 文件剪贴板捕获，特别是 README.md 这类普通文件。
- 文本 / 链接 / 图片历史卡片视觉展示。

不得回归项：
- 不得恢复收藏、管理模式、多选、批量操作或 JSON 迁移运行时路径。
- 不得修改 SQLite schema / Repository / 备份包格式，除非架构守门 Agent 明确升级并回到主控请求用户确认。
- 文件卡片修复不得删除、移动、复制或写入原文件。
- 搜索有内容时普通外点不得关闭 / 清空；点击其他分组仍应关闭并清空。
- 分组、置顶、搜索、文件卡片、Quick Look、pasteboard fallback 不得回退。
- 不得修改版本号、构建脚本或发布流程。

最小回归测试：
- swift build。
- git diff --check。
- python3 scripts/verify_history_window_interaction_toast.py。
- python3 scripts/verify_history_card_scroll_alignment.py。
- python3 scripts/verify_no_management_no_favorite_ui.py。
- python3 scripts/verify_stage9_file_capture_first_batch.py。
- python3 scripts/verify_stage9_file_card_ui.py 或同等卡片布局守卫。
- python3 scripts/verify_stage9_file_pasteboard_first_batch.py。
- 若新增链接标题抓取守卫，必须补充或更新对应脚本。

任务卡 A：
- ID：V2-COREUI-MAINT7-HISTORY-RUNTIME-INTERACTION-001
- 负责 Agent：UI Interaction / 原开发 Agent
- 归类：原模块核心交互缺陷，不再作为普通小范围 bug。
- 允许修改：
  - Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift
  - Sources/ClipEase/Features/HistoryWindow/HistoryWindowController.swift（必要时）
  - Sources/ClipEase/Features/HistoryWindow/HistoryWindowInputState.swift（必要时）
  - scripts/verify_history_window_interaction_toast.py
  - scripts/verify_history_card_scroll_alignment.py
- 禁止修改：
  - ClipboardMonitor / Store / PasteExecutor / Quick Look / 卡片视觉布局，除非仅为编译适配并先说明。
  - Resources/Info.plist、构建脚本、发布流程。
  - SQLite schema / Repository / JSON fallback / 数据迁移。
  - 收藏、管理模式、多选 / 批量相关功能。
- 修复目标：
  1. 搜索框展开且无内容时，搜索框内部任意位置点击不得关闭搜索框。
  2. 点击真正外部区域的关闭规则仍正确。
  3. 半露卡片点击按左右方向平移，使被点击卡片完整可见并露出下一张约 1/6。
  4. 新卡片加入必须覆盖旧横向 offset，并滚动到新卡片目标位置；不能只更新 selected/focus。
- 完成标准：给出代码级说明，解释为什么这次不是只改 selected/focus 或静态 frame，而是运行态事件路径和真实 scroll viewport 生效。

任务卡 B：
- ID：V2-CORECAPTURE-MAINT7-LINK-FILE-CAPTURE-001
- 负责 Agent：Clipboard / Link Capture 原开发 Agent + Architecture Gatekeeper 复核
- 归类：剪贴板捕获和链接标题核心路径缺陷。
- 允许修改：
  - Sources/ClipEase/Features/ClipboardMonitor/ClipboardMonitor.swift
  - Sources/ClipEase/Core/Utilities/LinkTitleFetcher.swift
  - Sources/ClipEase/Core/Storage/ClipboardHistoryStore.swift（必要时）
  - Sources/ClipEase/Core/Storage/ClipboardHistoryPersistence.swift（必要时）
  - Sources/ClipEase/Core/Models/ClipboardItem.swift（必要时；不得改 schema，除非升级）
  - scripts/verify_stage9_file_capture_first_batch.py
  - 新增链接标题抓取静态 / 功能守卫脚本（如需要）
- 禁止修改：
  - SQLite schema / migration / Repository 查询下沉，除非架构守门 Agent 明确升级并停止实施。
  - 原文件删除 / 移动 / 写入。
  - 收藏、管理模式、多选 / 批量、JSON runtime。
  - Resources/Info.plist、构建脚本、发布流程。
- 修复目标：
  1. 捕获链接卡片后后台立即抓取标题 / 图标或可用 metadata，不依赖编辑保存。
  2. 普通文件复制必须记录文件卡片，README.md 这类文件不得被忽略。
  3. 不降低现有 file URL pasteboard、self-copy guard、文件粘贴 fallback 和 Quick Look 基线。

任务卡 C：
- ID：V2-UICARD-MAINT7-CARD-VISUAL-LAYOUT-001
- 负责 Agent：UI Card Layout Bugfix Agent
- 归类：卡片视觉布局 bug。
- 允许修改：
  - Sources/ClipEase/Features/HistoryWindow/HistoryCardView.swift
  - scripts/verify_stage9_file_card_ui.py（如需要）
  - 新增卡片布局静态守卫脚本（如需要）
- 禁止修改：
  - HistoryWindow 横向滚动 / search outside observer。
  - ClipboardMonitor / Store / PasteExecutor / Repository / schema。
  - Resources/Info.plist、构建脚本、发布流程。
  - 收藏、管理模式、多选 / 批量、JSON runtime。
- 修复目标：
  1. 链接卡片标题和 URL 紧凑展示，不出现大块中间空隙。
  2. 文本卡片内容占满主要区域，下方淡化，超出显示省略。
  3. 图片卡片按比例填满图片区域：竖长图上下占满，横长图左右占满，可完整铺满时不留白。

测试 / 回归调度：
- 三张实现卡完成后，必须调度 Test Agent 回归原失败路径和关联功能守卫。
- UI 交互核心卡 A 若仍失败，升级为 HistoryWindow 滚动 / 命中测试架构缺陷分析，不再继续同文件局部补丁。
```

## 239. 维修阶段第七轮实现完成与主控联合门禁记录

```text
任务卡组：V2-MAINT7-HISTORY-LINK-FILE-CARD-20260515
时间：2026-05-15
阶段：维修阶段 / 第七轮实现完成待 Test / Review
当前会话模式：ClipEase V2 Main Controller Agent

主控边界：
- 主控只调度、记录、检查门禁，不亲自写业务代码。

实现任务卡 A：V2-COREUI-MAINT7-HISTORY-RUNTIME-INTERACTION-001
负责 Agent：UI Interaction / 原开发 Agent
状态：COMPLETED
修改文件：
- Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift
- scripts/verify_history_window_interaction_toast.py
- scripts/verify_history_card_scroll_alignment.py
修复摘要：
- 搜索框新增 live AppKit region 注册表，用当前 NSView bounds 转 screen frame 判断内部点击，避免空搜索框内部点击被 outside observer 误关。
- 卡片新增 CardDocumentFrameReader，用真实 document frame + NSScrollView viewport 计算半露卡片 reveal 的 absolute offset。
- 新卡片 focus 期间暂停普通 selection fallback，pending 保持到测量滚动和下一 runloop 校准后再清，避免旧 offset 抢回视口。

实现任务卡 B：V2-CORECAPTURE-MAINT7-LINK-FILE-CAPTURE-001
负责 Agent：Clipboard / Link Capture 原开发 Agent
状态：COMPLETED
修改文件：
- Sources/ClipEase/Core/Storage/ClipboardHistoryStore.swift
- Sources/ClipEase/Features/ClipboardMonitor/ClipboardMonitor.swift
- scripts/verify_stage9_file_capture_first_batch.py
- scripts/verify_link_title_background_fetch.py
修复摘要：
- 捕获到 link 后一律立即 fetchLinkTitle，不再只在 linkTitle == "/" 时后台抓取。
- fetchLinkTitle 使用 URL 匹配，避免旧请求覆盖编辑后的新 URL。
- localFileURLsFromPasteboard 总会尝试读取普通 string 中的本地路径，README.md 等普通文件路径可生成文件卡片；混合普通文本不会被误吞为文件。

实现任务卡 C：V2-UICARD-MAINT7-CARD-VISUAL-LAYOUT-001
负责 Agent：UI Card Layout Bugfix Agent
状态：COMPLETED
修改文件：
- Sources/ClipEase/Features/HistoryWindow/HistoryCardView.swift
- scripts/verify_maint7_card_visual_layout.py
修复摘要：
- 链接卡片标题和 URL 改为紧凑文本栈，去掉中间大间隙。
- 文本卡片内容填满 preview 区域，增加底部淡化 mask，超出 tail truncation。
- 图片卡片移除强制 padding，保持等比 scaledToFit，尽量贴满图片区域且不拉伸。

V2 测试计划 Agent：
- 任务卡：V2-TESTPLAN-MAINT7-HISTORY-LINK-FILE-CARD-REGRESSION-001
- 状态：COMPLETED
- 修改文件：docs/V2_TEST_PLAN.md
- 结果：新增 6.6 维修阶段第七轮用户反馈回归门禁，覆盖 8 项原失败路径、阻塞自动化、手工验收和未覆盖项。

主控联合门禁：
- swift build：PASS
- git diff --check：PASS
- python3 scripts/verify_history_window_interaction_toast.py：PASS
- python3 scripts/verify_history_card_scroll_alignment.py：PASS
- python3 scripts/verify_no_management_no_favorite_ui.py：PASS
- python3 scripts/verify_stage9_file_capture_first_batch.py：PASS
- python3 scripts/verify_stage9_file_pasteboard_first_batch.py：PASS
- python3 scripts/verify_stage9_file_card_ui.py：PASS
- python3 scripts/verify_link_title_background_fetch.py：PASS
- python3 scripts/verify_maint7_card_visual_layout.py：PASS

未验证项：
- 真实 UI 人工点击和视觉验收仍需用户覆盖：
  1. 空搜索框内部点击不关闭。
  2. 半露卡片点击动画距离。
  3. 第 20 条附近新增剪贴板后的新卡片视觉回位。
  4. 真实链接标题后台抓取速度与显示。
  5. Finder 复制 README.md 是否生成文件卡片。
  6. 链接 / 文本 / 图片卡片是否符合参考图。

后续动作：
- 调度 Test Agent 按 docs/V2_TEST_PLAN.md 6.6 回归原失败路径和关联功能守卫。
- Test PASS 后再进入 Review / Acceptance；最终由主控本地运行 App 交用户人工验收。
```

## 240. 维修阶段第七轮 Test PASS 记录

```text
任务卡：V2-TEST-MAINT7-HISTORY-LINK-FILE-CARD-REGRESSION-001
时间：2026-05-15
阶段：维修阶段 / 第七轮回归测试
当前会话模式：ClipEase V2 Main Controller Agent

Test Agent：
- 结论：PASS
- 修改文件：docs/V2_AGENT_RUNBOOK.md（追加测试记录）

已执行并通过：
- swift build
- git diff --check
- python3 scripts/verify_history_window_interaction_toast.py
- python3 scripts/verify_history_card_scroll_alignment.py
- python3 scripts/verify_no_management_no_favorite_ui.py
- python3 scripts/verify_stage9_file_capture_first_batch.py
- python3 scripts/verify_stage9_file_pasteboard_first_batch.py
- python3 scripts/verify_stage9_file_card_ui.py
- python3 scripts/verify_link_title_background_fetch.py
- python3 scripts/verify_maint7_card_visual_layout.py
- python3 scripts/verify_sqlite_only_baseline.py

源码核对结论：
- 空搜索框内部点击保护、外部点击规则、真实 document frame / viewport reveal、新卡片 pending 滚动校准、链接捕获后后台抓标题、README.md 等普通文件路径捕获且混合文本不误吞、链接 / 文本 / 图片卡片布局均通过核对。
- no favorite / no management / no JSON runtime 红线未发现回退。

未验证：
- 真实运行态仍需人工覆盖：空搜索框多区域点击、半露卡片动画距离、新卡片在第 20 条附近的实际回位、真实网络链接标题抓取、Finder 复制 README.md/txt/rtf/PDF/多文件、对照参考图检查链接 / 文本 / 图片卡片视觉。
```

## 241. 维修阶段第七轮 Review PASS / 红线归因风险记录

```text
任务卡：V2-REVIEW-MAINT7-HISTORY-LINK-FILE-CARD-REGRESSION-001
时间：2026-05-15
阶段：维修阶段 / 第七轮代码审查
当前会话模式：ClipEase V2 Main Controller Agent

Review Agent：
- 结论：Scoped Maint7 code review PASS。
- 未发现本轮列出实现文件中的阻塞缺陷。

已执行并通过：
- swift build
- git diff --check
- python3 scripts/smoke_check.py
- python3 scripts/verify_history_window_interaction_toast.py
- python3 scripts/verify_history_card_scroll_alignment.py
- python3 scripts/verify_stage9_file_capture_first_batch.py
- python3 scripts/verify_stage9_file_pasteboard_first_batch.py
- python3 scripts/verify_stage9_file_card_ui.py
- python3 scripts/verify_link_title_background_fetch.py
- python3 scripts/verify_maint7_card_visual_layout.py
- python3 scripts/verify_no_management_no_favorite_ui.py

审查结论：
- 1-3 使用 live AppKit search regions、真实 NSScrollView / document frame、absolute scroll offsets 和 pending scroll retries，不只是 selected/focus 静态变化。
- Search outside 逻辑保留有内容搜索外点、分组导航清空关闭、popover 排除、清空 / 筛选按钮交互。
- Link title fetch 捕获后启动，使用 URL 匹配避免覆盖编辑后的 URL。
- 文件路径捕获要求所有 path-text 行解析为存在的绝对路径，降低普通文本误判；README.md Finder 复制应被 file URL / readObjects / path string 覆盖。
- 卡片布局保持固定尺寸、链接标题 / URL 紧凑、文本淡化 / 省略和图片等比。

红线归因风险：
- Review 发现 Resources/Info.plist 在脏工作区中仍有版本号 / 构建号改动。
- 该文件不属于 Maint7 允许修改文件，runbook 历史显示它可能来自 earlier build/run；Review 未判定为本轮导致。
- 主控裁定：本轮 Maint7 可进入本地运行人工验收；不得将该状态视为正式 release / merge 放行。最终发布或合并前必须单独确认 Info.plist 版本号红线归因。

未验证：
- 真实 UI 人工验收仍需覆盖搜索点击矩阵、半露卡片动画、新卡片定位、真实链接标题抓取、Finder 文件复制和卡片视觉参考图。
```

## 242. 维修阶段第七轮 Acceptance 放行记录

```text
任务卡：V2-ACCEPT-MAINT7-HISTORY-LINK-FILE-CARD-REGRESSION-001
时间：2026-05-15
阶段：维修阶段 / 第七轮验收裁定
当前会话模式：ClipEase V2 Acceptance Agent

Acceptance Agent：
- 结论：PASS_LOCAL_USER_TEST_ALLOWED
- 放行范围：仅允许主控本地运行 App，交用户做第七轮 8 项反馈的人工验收。
- 本结论不是最终 release / merge 放行。

验收依据：
- 已读取 docs/V2_AGENT_RUNBOOK.md 第 238-241 节。
- 已读取 docs/V2_FEEDBACK_AND_GUARDS.md 的 BUG-V2-MAINT7-HISTORY-LINK-FILE-CARD-20260515。
- 已读取 docs/V2_TEST_PLAN.md 第 6.6 节。
- 第 240 节记录 Test PASS。
- 第 241 节记录 Scoped Maint7 code review PASS。

排除范围：
- 不放行正式 release、merge、版本号更新、构建号更新或发布流程改动。
- 不放行 Resources/Info.plist 版本号 / 构建号脏改归因；该红线必须在最终发布或合并前单独确认。
- 不放行 SQLite schema、Repository 查询语义、备份包格式、JSON runtime、收藏 / 管理模式 / 多选 / 批量操作回归。
- 不放行文件删除、移动、复制、覆盖或写入原文件等破坏性文件操作。

剩余人工验收项：
- 搜索框：空搜索框内部点击、搜索图标区域、窗口空白处、卡片区域、分组入口和窗口外部的开闭 / 焦点 / 内容规则。
- 半露卡片：左右半露卡片点击方向平移、完整露出被点击卡片、下一张约 1/6 露出。
- 新卡片定位：无置顶和有置顶 / 前置样本中，复制文本、链接、普通文件和图片后新卡片选中并强制滚回目标位置。
- 链接捕获：可访问网页、慢响应链接、无标题链接复制后先生成 URL，再后台更新标题或保持 URL fallback。
- 文件捕获：Finder 复制 README.md、txt、rtf、PDF 和多文件样本后生成文件卡片，且不修改原文件。
- 卡片视觉：对照用户参考图检查链接、文本、图片卡片，覆盖长标题 / 长 URL、短文本 / 长文本、横图 / 竖图 / 方图。
- 基线抽查：分组、置顶、搜索有内容时外点规则、Quick Look、文件 pasteboard fallback、SQLite-only、无收藏 / 无管理模式 / 无多选 / 无批量操作。
```

## 243. 维修阶段第七轮本地运行记录

```text
任务卡组：V2-MAINT7-HISTORY-LINK-FILE-CARD-20260515
时间：2026-05-15
阶段：维修阶段 / 第七轮本地运行待用户人工验收
当前会话模式：ClipEase V2 Main Controller Agent

前置状态：
- Test Agent PASS。
- Review Agent scoped PASS。
- Acceptance Agent PASS_LOCAL_USER_TEST_ALLOWED。

主控运行方式：
- 未调用 scripts/build-app.sh。
- 未调用 scripts/bump_version.py。
- 未修改 Resources/Info.plist。
- 使用 swift build 已生成的 debug 可执行文件：
  - .build/arm64-apple-macosx/debug/ClipEase
- 将 debug 可执行文件复制到本地测试 bundle：
  - .build/ClipEase.app/Contents/MacOS/ClipEase
- 通过 open -n .build/ClipEase.app 启动本地测试包。

运行结果：
- ClipEase PID：69034
- 本次运行只用于用户人工验收 Maint7 第七轮 8 项反馈。
- 这不是正式 release / merge 放行。
- Resources/Info.plist 版本号 / 构建号脏改仍需最终发布或合并前单独确认归因。

用户人工验收重点：
1. 搜索框展开且无内容时，点击搜索框内部任意区域不关闭。
2. 主窗口左右两侧半露卡片点击后按方向平移，完整露出选中卡片，并露出下一张约 1/6。
3. 用户滚到第 20 条左右后复制新内容，新卡片被选中并强制滚回目标位置；无置顶时滚到最左且显示左侧留白，有置顶 / 前置时露出上一张约 1/6。
4. 复制链接后，链接卡片后台自动获取标题，不需要编辑保存。
5. 链接卡片标题和 URL 紧凑展示，无中间大间隙。
6. Finder 复制 README.md 等普通文件生成文件卡片。
7. 文本卡片内容占满区域，底部淡化，超出显示省略。
8. 图片卡片按比例尽量占满图片区域，不拉伸变形。
```

## 244. 维修阶段第八轮用户反馈分诊与调度

```text
Bug ID：V2-MAINT8-USER-FEEDBACK-20260516
时间：2026-05-16
来源阶段：维修阶段 / 第八轮运行态反馈
反馈来源：用户运行态反馈
当前会话模式：ClipEase V2 Main Controller Agent

主控边界：
- 主控只记录、复现意图、归类、定级、生成 Bug 修复任务卡和调度。
- 主控不写业务代码、不亲自修 bug。
- 本轮处理前已读取 docs/V2_FEEDBACK_AND_GUARDS.md、docs/V2_AGENT_RUNBOOK.md 和 docs/V2_TEST_PLAN.md。

用户反馈：
1. 链接卡片内容区不要显示 URL 标题和 URL 地址；因为卡片底部已经有 URL，应在底部 URL 上方加 URL 标题，标题使用加粗字体。
2. 半露卡片点击后按方向平移，并露出下一张约 1/6 的问题仍未解决。
3. 无论用户横向滚动到哪里，复制新内容后，新卡片应被选中并滚回目标位置。
4. 复制单个文件经常没有加入新卡片。
5. 文本卡片内容仍未占满，底部仍有很大间隙；应参照此前参考图，内容占满、底部淡化、超出省略。
6. 从文本内容中复制文件路径文本，例如两行绝对路径，不应显示为多个文件卡片，应作为文本卡片。
7. 分组右键点击时，要和左键点击一样进入选中状态。
8. 复制富文本内容时，文本卡片内容区应显示带格式的富文本，而不是统一普通字体样式。

历史反馈关联：
- BUG-V2-MAINT7-HISTORY-LINK-FILE-CARD-20260515。
- 第 203-243 节多轮运行态反馈中，半露卡片 reveal、新卡片定位和卡片视觉已多轮返工。
- 第七轮对 plain string 路径转文件的修复与本轮第 6 项产生产品语义冲突，需改为只在具有文件语义的 pasteboard 来源中记录文件卡片。

风险等级：
- 2 / 3：高；HistoryWindow 横向滚动和新卡片定位多轮失败，升级为核心交互 / 架构级修复，不再继续普通 Bugfix 局部补丁。
- 4 / 6：高；涉及 ClipboardMonitor pasteboard 类型判定、文件语义和文本语义冲突，交 Clipboard Capture 原开发 Agent + 架构守门复核。
- 1 / 5 / 8：中高；涉及 HistoryCardView 链接 / 文本 / 富文本渲染规则，交 UI Card / Rich Text 原开发 Agent。
- 7：中；分组右键选择状态交 UI Interaction Agent，需避免破坏搜索 / 分组守卫。

关联功能守卫：
- GUARD-V2-BASELINE-001：SQLite-only 运行时基线。
- GUARD-V2-BASELINE-002：收藏 / 管理模式移除基线。
- GUARD-V2-GROUP-001：分组能力保留。
- GUARD-V2-SEARCH-001：搜索筛选交互守卫。
- GUARD-V2-UI-001：顶部轨道和分组滚动守卫。
- BUG-V2-MAINT7-HISTORY-LINK-FILE-CARD-20260515。

受影响功能：
- HistoryWindow 横向滚动、半露卡片 reveal、新卡片定位。
- ClipboardMonitor 文件捕获和文本路径捕获语义。
- HistoryCardView 链接、文本、富文本卡片展示。
- 分组按钮右键选择状态。

不得回归项：
- 不得恢复收藏、管理模式、多选、批量操作或 JSON 迁移运行时路径。
- 不得修改版本号、构建脚本或发布流程。
- 不得修改 SQLite schema / Repository / 备份格式，除非升级红线任务。
- 文件捕获修复不得删除、移动、复制或写入原文件。
- 复制文本中的文件路径必须保持为文本卡片，不得误判为多文件卡片。
- Finder 或系统文件语义复制的单个文件必须可靠生成文件卡片。
- 搜索有内容时普通外点不得关闭或清空；点击其他分组仍应关闭并清空。
- 分组、置顶、Quick Look、文件 pasteboard fallback、SQLite-only 基线不得回退。

最小回归测试：
- swift build。
- git diff --check。
- python3 scripts/smoke_check.py。
- python3 scripts/verify_history_window_interaction_toast.py。
- python3 scripts/verify_history_card_scroll_alignment.py。
- python3 scripts/verify_no_management_no_favorite_ui.py。
- python3 scripts/verify_stage9_file_capture_first_batch.py。
- python3 scripts/verify_stage9_file_pasteboard_first_batch.py。
- python3 scripts/verify_stage9_file_card_ui.py。
- python3 scripts/verify_link_title_background_fetch.py。
- python3 scripts/verify_maint7_card_visual_layout.py。
- 新增或更新 Maint8 专项守卫：HistoryWindow 运行态滚动结构、文件语义捕获、文本路径不误判、链接 / 文本 / 富文本卡片布局、分组右键选中。

任务卡 A：
- ID：V2-COREUI-MAINT8-HISTORY-RUNTIME-SCROLL-ARCH-001
- 负责 Agent：HistoryWindow Core Interaction / 原开发 Agent
- 归类：核心交互 / 架构级修复，不再作为普通 Bugfix。
- 允许修改：
  - Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift
  - Sources/ClipEase/Features/HistoryWindow/HistoryWindowController.swift（必要时）
  - Sources/ClipEase/Features/HistoryWindow/HistoryWindowInputState.swift（必要时）
  - scripts/verify_history_card_scroll_alignment.py
  - 可新增 scripts/verify_maint8_history_runtime_scroll.py
- 禁止修改：
  - ClipboardMonitor / Store / PasteExecutor / 卡片视觉布局 / RichTextEditor，除非仅为编译适配并先说明。
  - Resources/Info.plist、构建脚本、发布流程。
  - SQLite schema / Repository / JSON runtime。
  - 收藏、管理模式、多选 / 批量相关功能。
- 修复目标：
  1. 半露卡片点击后必须按方向平移，完整露出选中卡片，并露出下一张约 1/6。
  2. 无论当前横向 offset 在哪里，新内容加入后必须选中新卡片并滚回目标位置。
  3. 如果当前结构无法可靠实现，需先重构 HistoryWindow 横向滚动 coordinator / measurement 流程，而不是继续叠加局部补丁。

任务卡 B：
- ID：V2-CORECAPTURE-MAINT8-FILE-PASTEBOARD-SEMANTICS-001
- 负责 Agent：Clipboard Capture 原开发 Agent + Architecture Gatekeeper 复核
- 归类：剪贴板文件语义核心路径缺陷。
- 允许修改：
  - Sources/ClipEase/Features/ClipboardMonitor/ClipboardMonitor.swift
  - Sources/ClipEase/Core/Storage/ClipboardHistoryStore.swift（必要时）
  - scripts/verify_stage9_file_capture_first_batch.py
  - 可新增 scripts/verify_maint8_file_pasteboard_semantics.py
- 禁止修改：
  - SQLite schema / migration / Repository 查询下沉，除非停止并升级架构红线。
  - 原文件删除 / 移动 / 写入。
  - HistoryWindow 滚动 / 卡片布局 / RichText 渲染。
  - 收藏、管理模式、多选 / 批量、JSON runtime。
  - Resources/Info.plist、构建脚本、发布流程。
- 修复目标：
  1. Finder / 系统文件语义复制单个文件必须可靠生成文件卡片。
  2. 普通文本中包含一个或多行绝对路径时，必须记录为文本卡片，不得转成多文件卡片。
  3. 多文件 Finder 复制仍应生成多文件卡片。

任务卡 C：
- ID：V2-UICARD-MAINT8-LINK-TEXT-RICHTEXT-LAYOUT-001
- 负责 Agent：UI Card / Rich Text 原开发 Agent
- 归类：卡片视觉和富文本展示缺陷。
- 允许修改：
  - Sources/ClipEase/Features/HistoryWindow/HistoryCardView.swift
  - Sources/ClipEase/Features/HistoryWindow/LazyPreviewTextView.swift（必要时）
  - Sources/ClipEase/Core/Storage/ClipboardHistoryStore.swift（仅当需要读取富文本数据，先说明）
  - scripts/verify_stage9_file_card_ui.py
  - scripts/verify_maint7_card_visual_layout.py
  - 可新增 scripts/verify_maint8_card_richtext_layout.py
- 禁止修改：
  - HistoryWindow 横向滚动 / search outside observer。
  - ClipboardMonitor 文件语义。
  - Repository / schema / PasteExecutor。
  - Resources/Info.plist、构建脚本、发布流程。
  - 收藏、管理模式、多选 / 批量、JSON runtime。
- 修复目标：
  1. 链接卡片内容区不显示 URL 标题和 URL 地址；底部 URL 上方显示加粗 URL 标题。
  2. 文本卡片内容区域继续向下占满，底部淡化，超出省略，不留大空隙。
  3. 富文本复制生成的卡片内容区显示带格式富文本，不统一降级为普通字体样式。

任务卡 D：
- ID：V2-UI-MAINT8-GROUP-RIGHTCLICK-SELECTION-001
- 负责 Agent：UI Interaction Agent
- 归类：分组右键选中状态交互 bug。
- 允许修改：
  - Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift
  - scripts/verify_group_focus_and_menu_guard.py（如需要）
  - 可新增 scripts/verify_maint8_group_right_click_selection.py
- 禁止修改：
  - ClipboardMonitor / Store / Repository / schema。
  - HistoryWindow 横向滚动修复，除非和任务卡 A 协调后明确接入。
  - Resources/Info.plist、构建脚本、发布流程。
- 修复目标：
  1. 分组按钮右键点击时，和左键点击一样进入选中状态。
  2. 不破坏右键菜单、颜色 / 图标 popover、搜索有内容时分组点击关闭并清空的既有规则。

测试 / 回归调度：
- 实现完成后必须调度 Test Agent 按第八轮原失败路径和相关守卫回归。
- 2 / 3 若本轮仍失败，必须升级为 HistoryWindow 滚动架构重做 / 运行态自动化缺口专项，不再继续局部修补。
```

## 245. 维修阶段第八轮实现完成与主控联合门禁记录

```text
任务卡组：V2-MAINT8-HISTORY-FILE-GROUP-RICHTEXT-20260516
时间：2026-05-17
阶段：维修阶段 / 第八轮实现完成待 Test / Review
当前会话模式：ClipEase V2 Main Controller Agent

主控边界：
- 主控只调度、记录、检查门禁，不亲自写业务代码。

实现任务卡 A：V2-COREUI-MAINT8-HISTORY-RUNTIME-SCROLL-ARCH-001
负责 Agent：HistoryWindow Core Interaction / 原开发 Agent
状态：COMPLETED
修改文件：
- Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift
- Sources/ClipEase/Features/HistoryWindow/HistoryCardView.swift（仅 @MainActor 编译适配）
- scripts/verify_history_card_scroll_alignment.py
- scripts/verify_maint8_history_runtime_scroll.py
修复摘要：
- HistoryScrollCoordinator.update(scrollView:) 不再在 SwiftUI/AppKit 反复绑定时自动 replay 旧 saved offset，只 replay 显式 pending scroll / restore。
- 通过 NSView.boundsDidChangeNotification 观察真实 NSClipView，用户横向滚动时保存真实 document offset。
- 程序滚动统一走 scrollToOffset，最终 offset 保存，并通过 isProgrammaticScroll 避免通知回流覆盖。
- 新卡片 pending focus 期间，preview rebuild 不再恢复旧选中；新卡片先 scrollToOffset(0)，再按真实 card frame / viewport 二次对齐。

实现任务卡 B：V2-CORECAPTURE-MAINT8-FILE-PASTEBOARD-SEMANTICS-001
负责 Agent：Clipboard Capture 原开发 Agent + Architecture Gatekeeper 复核
状态：COMPLETED
修改文件：
- Sources/ClipEase/Features/ClipboardMonitor/ClipboardMonitor.swift
- scripts/verify_stage9_file_capture_first_batch.py
- scripts/verify_maint8_file_pasteboard_semantics.py
修复摘要：
- 只有 pasteboard 顶层具有文件语义时进入文件捕获：fileURL、public.file-url、NSFilenamesPboardType、file promise 相关类型。
- Finder 单文件 / 多文件复制继续通过 file URL / filename property list 生成文件卡片。
- 普通 .string 顶层内容不再解析成本地路径文件卡片；复制多行绝对路径文本会走文本捕获。

实现任务卡 C：V2-UICARD-MAINT8-LINK-TEXT-RICHTEXT-LAYOUT-001-RESUME
负责 Agent：UI Card / Rich Text 原开发 Agent
状态：COMPLETED
修改文件：
- Sources/ClipEase/Features/HistoryWindow/HistoryCardView.swift
- scripts/verify_maint8_card_richtext_layout.py
修复摘要：
- 链接卡片内容区不再渲染 URL 标题或 URL 地址，只保留居中的链接图标；footer 改为标题加粗在上、URL 在下并 middle truncation。
- 文本卡片内容区继续撑满可用高度，底部保留渐隐 mask，降低 bottom padding 和 line limit / tail truncation 以减少底部空隙。
- 富文本卡片复用 richTextFileName，从 ClipEaseStoragePaths.richTextFileURL 读取现有 RichTexts RTF 附件，用 NSAttributedString 渲染，保留字体、颜色等属性；新增轻量预览字符上限和缓存。

实现任务卡 D：V2-UI-MAINT8-GROUP-RIGHTCLICK-SELECTION-001
负责 Agent：UI Interaction Agent
状态：COMPLETED
修改文件：
- Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift
- scripts/verify_maint8_group_right_click_selection.py
修复摘要：
- 用户分组右键时先执行和左键一致的选中路径：清空并关闭搜索、切换到该分组、显示状态。
- 系统分组右键时选中该系统分组，但不在已选中时切回全部，避免右键当前分组反而取消选中。
- 右键菜单、颜色 / 图标 popover 保留；搜索有内容时分组点击仍走 closeSearchForGroupNavigation()。

V2 测试计划 Agent：
- 任务卡：V2-TESTPLAN-MAINT8-HISTORY-FILE-GROUP-RICHTEXT-REGRESSION-001
- 状态：COMPLETED
- 修改文件：docs/V2_TEST_PLAN.md
- 结果：新增 6.7 维修阶段第八轮用户反馈回归门禁。

主控联合门禁：
- swift build：PASS
- git diff --check：PASS
- python3 scripts/smoke_check.py：PASS
- python3 scripts/verify_history_window_interaction_toast.py：PASS
- python3 scripts/verify_history_card_scroll_alignment.py：PASS
- python3 scripts/verify_maint8_history_runtime_scroll.py：PASS
- python3 scripts/verify_stage9_file_capture_first_batch.py：PASS
- python3 scripts/verify_stage9_file_pasteboard_first_batch.py：PASS
- python3 scripts/verify_maint8_file_pasteboard_semantics.py：PASS
- python3 scripts/verify_stage9_file_card_ui.py：PASS
- python3 scripts/verify_maint7_card_visual_layout.py：PASS
- python3 scripts/verify_maint8_card_richtext_layout.py：PASS
- python3 scripts/verify_group_focus_and_menu_guard.py：PASS
- python3 scripts/verify_maint8_group_right_click_selection.py：PASS
- python3 scripts/verify_link_title_background_fetch.py：PASS
- python3 scripts/verify_no_management_no_favorite_ui.py：PASS
- python3 scripts/verify_sqlite_only_baseline.py：PASS

未验证项：
- 真实 UI 人工验收仍需覆盖半露卡片动画、新卡片任意 offset 回位、Finder 单文件捕获、普通路径文本卡片、链接 footer 标题 / URL、文本底部间隙、富文本格式展示、分组右键选中。

后续动作：
- 调度 Test Agent 按 docs/V2_TEST_PLAN.md 6.7 回归原失败路径和关联功能守卫。
- Test PASS 后进入 Review / Acceptance；最终由主控本地运行 App 交用户人工验收。
```

## 246. 维修阶段第八轮 Test PASS 与 Review 返工记录

```text
任务卡组：V2-MAINT8-HISTORY-FILE-GROUP-RICHTEXT-20260516
时间：2026-05-17
阶段：维修阶段 / 第八轮 Test PASS 与 Review 返工
当前会话模式：ClipEase V2 Main Controller Agent

Test Agent：
- 任务卡：V2-TEST-MAINT8-HISTORY-FILE-GROUP-RICHTEXT-REGRESSION-001
- 结论：PASS
- 修改文件：docs/V2_AGENT_RUNBOOK.md（追加测试记录）
- 已执行并通过：
  - swift build
  - git diff --check
  - python3 scripts/smoke_check.py
  - python3 scripts/verify_history_window_interaction_toast.py
  - python3 scripts/verify_history_card_scroll_alignment.py
  - python3 scripts/verify_maint8_history_runtime_scroll.py
  - python3 scripts/verify_stage9_file_capture_first_batch.py
  - python3 scripts/verify_stage9_file_pasteboard_first_batch.py
  - python3 scripts/verify_maint8_file_pasteboard_semantics.py
  - python3 scripts/verify_stage9_file_card_ui.py
  - python3 scripts/verify_maint7_card_visual_layout.py
  - python3 scripts/verify_maint8_card_richtext_layout.py
  - python3 scripts/verify_group_focus_and_menu_guard.py
  - python3 scripts/verify_maint8_group_right_click_selection.py
  - python3 scripts/verify_link_title_background_fetch.py
  - python3 scripts/verify_no_management_no_favorite_ui.py
  - python3 scripts/verify_sqlite_only_baseline.py

Review Agent：
- 任务卡：V2-REVIEW-MAINT8-HISTORY-FILE-GROUP-RICHTEXT-REGRESSION-001
- 初次结论：HOLD
- 阻塞项：
  1. P1：全部剪切板右键不会进入选中状态。
  2. P1 / 红线归属确认：Resources/Info.plist 版本号 / 构建号脏改仍存在，需要最终发布或合并前单独确认归因。

返工任务卡：V2-UI-MAINT8-GROUP-RIGHTCLICK-SELECTION-REWORK-001
负责 Agent：UI Interaction Agent
状态：COMPLETED
修改文件：
- Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift
- scripts/verify_maint8_group_right_click_selection.py
修复摘要：
- 全部剪切板右键现在进入 .all 选中状态。
- 置顶、用户分组右键选中路径保持。
- 分组导航左键仍走 closeSearchForGroupNavigation，保留搜索有内容时分组点击关闭并清空规则。

返工后主控联合门禁：
- swift build：PASS
- git diff --check：PASS
- python3 scripts/smoke_check.py：PASS
- python3 scripts/verify_history_window_interaction_toast.py：PASS
- python3 scripts/verify_history_card_scroll_alignment.py：PASS
- python3 scripts/verify_maint8_history_runtime_scroll.py：PASS
- python3 scripts/verify_stage9_file_capture_first_batch.py：PASS
- python3 scripts/verify_stage9_file_pasteboard_first_batch.py：PASS
- python3 scripts/verify_maint8_file_pasteboard_semantics.py：PASS
- python3 scripts/verify_stage9_file_card_ui.py：PASS
- python3 scripts/verify_maint7_card_visual_layout.py：PASS
- python3 scripts/verify_maint8_card_richtext_layout.py：PASS
- python3 scripts/verify_group_focus_and_menu_guard.py：PASS
- python3 scripts/verify_maint8_group_right_click_selection.py：PASS
- python3 scripts/verify_link_title_background_fetch.py：PASS
- python3 scripts/verify_no_management_no_favorite_ui.py：PASS
- python3 scripts/verify_sqlite_only_baseline.py：PASS

主控裁定：
- Review 阻塞项 1 已返工并通过门禁，需重新 Review。
- Review 阻塞项 2 属于共享工作区既有 Info.plist 红线归因风险，不属于 Maint8 允许修改范围；本轮继续排除在本地用户验收放行外，最终发布或合并前必须单独确认。
```

## 248. 维修阶段第八轮本地运行记录

```text
任务卡组：V2-MAINT8-HISTORY-FILE-GROUP-RICHTEXT-20260516
时间：2026-05-17
阶段：维修阶段 / 第八轮本地运行待用户人工验收
当前会话模式：ClipEase V2 Main Controller Agent

前置状态：
- Test Agent PASS。
- Review Agent 返工后 PASS。
- Acceptance Agent PASS_LOCAL_USER_TEST_ALLOWED。

主控运行方式：
- 未调用 scripts/build-app.sh。
- 未调用 scripts/bump_version.py。
- 未修改 Resources/Info.plist。
- 使用 swift build 已生成的 debug 可执行文件：
  - .build/arm64-apple-macosx/debug/ClipEase
- 将 debug 可执行文件复制到本地测试 bundle：
  - .build/ClipEase.app/Contents/MacOS/ClipEase
- 通过 open -n .build/ClipEase.app 启动本地测试包。

运行结果：
- ClipEase PID：96615
- 本次运行只用于用户人工验收 Maint8 第八轮 8 项反馈。
- 这不是正式 release / merge 放行。
- Resources/Info.plist 版本号 / 构建号脏改仍需最终发布或合并前单独确认归因。

用户人工验收重点：
1. 链接卡片内容区不显示 URL 标题和 URL 地址；footer URL 上方显示加粗 URL 标题。
2. 半露卡片点击后按方向平移，并露出下一张约 1/6。
3. 不管当前横向滚到哪里，复制新内容后新卡片被选中并滚回目标位置。
4. Finder / 系统文件语义复制单个文件可靠生成文件卡片。
5. 文本卡片内容占满、底部淡化、超出省略，底部不留大空隙。
6. 从文本内容复制多行文件路径时记录为文本卡片，不显示为多个文件。
7. 全部 / 置顶 / 用户分组右键点击都会进入对应选中状态，并保留右键菜单。
8. 富文本复制后，文本卡片内容区显示带格式富文本。
```

## 246. 维修阶段第八轮 Test Agent 回归门禁记录

```text
任务卡：V2-TEST-MAINT8-HISTORY-FILE-GROUP-RICHTEXT-REGRESSION-001
时间：2026-05-17
阶段：维修阶段 / 第八轮实现后 Test 回归
当前会话模式：ClipEase V2 Test Agent

测试依据：
- docs/V2_TEST_PLAN.md 6.7 维修阶段第八轮用户反馈回归门禁。
- docs/V2_FEEDBACK_AND_GUARDS.md：BUG-V2-MAINT8-HISTORY-FILE-GROUP-RICHTEXT-20260516。
- docs/V2_AGENT_RUNBOOK.md 第 244-245 节。

自动化门禁结果：
- swift build：PASS。
- git diff --check：PASS。
- python3 scripts/smoke_check.py：PASS。
- python3 scripts/verify_history_window_interaction_toast.py：PASS。
- python3 scripts/verify_history_card_scroll_alignment.py：PASS；脚本提示共享工作区存在非本任务 dirty / untracked 文件，但按脚本规则不判失败。
- python3 scripts/verify_maint8_history_runtime_scroll.py：PASS。
- python3 scripts/verify_stage9_file_capture_first_batch.py：PASS。
- python3 scripts/verify_stage9_file_pasteboard_first_batch.py：PASS。
- python3 scripts/verify_maint8_file_pasteboard_semantics.py：PASS。
- python3 scripts/verify_stage9_file_card_ui.py：PASS。
- python3 scripts/verify_maint7_card_visual_layout.py：PASS。
- python3 scripts/verify_maint8_card_richtext_layout.py：PASS。
- python3 scripts/verify_group_focus_and_menu_guard.py：PASS。
- python3 scripts/verify_maint8_group_right_click_selection.py：PASS。
- python3 scripts/verify_link_title_background_fetch.py：PASS。
- python3 scripts/verify_no_management_no_favorite_ui.py：PASS。
- python3 scripts/verify_sqlite_only_baseline.py：PASS。

源码核对结果：
1. 链接卡片：HistoryCardView.linkPreview 内容区仅显示链接图标；footer 使用 linkFooterTitle 加粗在 linkFooterURL 上方，URL middle truncation，未在内容区重复显示标题 / URL。
2. 横向滚动：HistoryScrollCoordinator.update(scrollView:) 只接入真实 scrollView 并应用 pending binding scroll，不在普通重绑时 replay 旧 saved offset；scrollToOffset 负责 pending offset、clamp、保存 offset；boundsDidChange 仅在非 programmatic scroll 时保存真实 clipView offset。
3. 新卡片定位：syncLatestItemFocusIfNeeded 对新插入项设置 pendingLatestFocusItemID，并先 saveOffset(0) / scrollToOffset(0)；渲染后通过 measured frame 再次 applyPendingItemScrollIfMeasured / scheduleSecondPendingItemScrollIfNeeded 对齐。
4. 半露卡片 reveal：partialRevealTargetOffset(for:) 分别处理左侧 frame.minX < visibleRect.minX 和右侧 frame.maxX > visibleRect.maxX，右侧使用 trailingPeekWidth / oneSixthPeekWidth，方向平移逻辑存在。
5. 文件语义：ClipboardMonitor.localFileURLsFromPasteboard() 先要求 pasteboardHasFileSemanticTypes；文件卡片只从 .fileURL / public.file-url / NSFilenamesPboardType / file promise 等文件语义类型解析；普通 .string 路径文本不会单独触发文件捕获。
6. 文本卡片：普通文本 preview 使用最大可用 frame、bottom padding 2、lineLimit 8/9、tail truncation 和 bottom gradient mask，符合减少底部空隙、淡化和超出省略的实现方向。
7. 富文本卡片：存在 richTextFileName 时走 RichTextCardPreview，使用 NSTextView isRichText=true；RichTextCardPreviewCache 从 ClipEaseStoragePaths.richTextFileURL 读取 RTF data 并以 NSAttributedString.DocumentType.rtf 解析，保留已有富文本属性并仅补默认 font / color。
8. 分组右键：系统分组 GroupMouseDownObserver.onRightMouseDown 调 selectSystemGroupForContextMenu，用户分组右键调 selectGroup；两者均保留 contextMenu / appearance popover，并沿用 closeSearchForGroupNavigation 清理搜索分组规则。
9. 红线守卫：verify_no_management_no_favorite_ui.py 和 verify_sqlite_only_baseline.py 均 PASS；未修改业务代码；本轮未触碰构建脚本、SQLite schema、Repository 查询语义或版本号。

未验证真实 UI 项：
- 未启动真实 App 录屏 / 人工验收半露卡片动画方向、下一张约 1/6 露出。
- 未在真实 Finder / 第三方文件管理器中人工复制单文件 / 多文件观察运行态卡片生成。
- 未在真实 TextEdit / 网页富文本源中人工观察卡片像素级富文本样式。
- 未人工截图核对链接 footer、长文本底部渐隐、分组右键菜单 / popover 的最终视觉。

结论：PASS。自动化门禁全通过，源码核对覆盖第八轮 8 项原失败路径和相关守卫；真实 UI 项保留为主控 / Acceptance 人工验收范围。
```

## 247. 维修阶段第八轮 Acceptance 放行记录

```text
任务卡：V2-ACCEPT-MAINT8-HISTORY-FILE-GROUP-RICHTEXT-REGRESSION-001
时间：2026-05-17
阶段：维修阶段 / 第八轮验收裁定
当前会话模式：ClipEase V2 Acceptance Agent

Acceptance Agent：
- 结论：PASS_LOCAL_USER_TEST_ALLOWED
- 放行范围：仅允许主控本地运行 App，交用户做第八轮 8 项反馈的人工验收。
- 本结论不是最终 release / merge 放行。

验收依据：
- 已读取 docs/V2_AGENT_RUNBOOK.md 第 244-246 节。
- 已读取 docs/V2_FEEDBACK_AND_GUARDS.md 的 BUG-V2-MAINT8-HISTORY-FILE-GROUP-RICHTEXT-20260516。
- 已读取 docs/V2_TEST_PLAN.md 第 6.7 节。
- 第 245 节记录四张 Maint8 实现卡完成，并记录主控联合门禁 PASS。
- 第 246 节记录 Test Agent 自动化门禁 PASS 和源码核对 PASS。
- Review 返工后 PASS 作为本次验收输入前提；Info.plist 版本号 / 构建号脏改仍按历史红线归因风险处理，不纳入 Maint8 本地验收放行范围。

排除范围：
- 不放行正式 release、merge、版本号更新、构建号更新或发布流程改动。
- 不放行 Resources/Info.plist 版本号 / 构建号脏改归因；该红线必须在最终发布或合并前单独确认。
- 不放行 SQLite schema、Repository 查询语义、备份包格式、JSON runtime、收藏 / 管理模式 / 多选 / 批量操作回归。
- 不放行文件删除、移动、复制、覆盖或写入原文件等破坏性文件操作。
- 不把自动化 / 源码核对等同于真实 UI 人工验收已完成；真实运行态视觉和交互仍需用户确认。

剩余人工验收项：
- 链接卡片：复制有标题、无标题、长标题和长 URL 链接；确认内容区不重复显示标题 / URL，底部 URL 上方加粗显示标题，URL 可读且不挤压操作区。
- 半露卡片：至少 20 条历史记录下横向滚动到左右半露位置，分别点击左侧和右侧半露卡片；确认方向平移、选中卡片完整露出、下一张约 1/6 露出。
- 新卡片定位：在无置顶样本和有置顶 / 前置样本中，先滚到较后卡片，再复制文本、链接、单文件、富文本各 1 次；确认新卡片选中且视口强制滚回目标位置。
- 文件语义：从 Finder 复制 README.md、txt、rtf、PDF 或同类普通单文件 / 多文件；确认生成文件卡片，文件名、路径和再次复制粘贴可用，原文件未被删除、移动、覆盖或写入。
- 路径文本：从文本编辑器复制一行绝对路径、两行绝对路径、路径加普通文字的混合文本；确认全部记录为文本卡片，不生成文件卡片。
- 文本视觉：准备短文本、长文本、多行文本和极长单词样本；确认内容占满、底部淡化、超出省略，且不遮挡底部操作区。
- 分组右键：在全部、置顶、用户分组、搜索有内容状态下分别右键分组；确认分组进入选中状态，右键菜单仍出现，搜索分组规则保持一致。
- 富文本：从 TextEdit、网页或支持富文本的编辑器复制粗体、斜体、标题、列表、颜色或不同字号样本；确认卡片内容区保留已支持格式，预览和再次复制粘贴不回退。
- 基线抽查：SQLite-only、无收藏 / 无管理模式 / 无多选 / 无批量操作、分组、置顶、Quick Look、文件 pasteboard fallback、搜索外点规则。
```
