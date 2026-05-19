# ClipEase V2 Stage 10 iCloud 同步 Schema Gap 清单

任务卡：`V2-S10-ICLOUD-SCHEMA-GAP-001`

阶段：Stage 10 iCloud 同步预研 - Schema gap 清单

结论：PASS 产出未来同步 schema gap 清单；HOLD 任何 schema 变更、迁移、业务代码、CloudKit runtime、entitlement、同步 UI、附件上传下载、跨设备删除传播、冲突合并 runtime 和端到端加密 runtime。

## 1. 本阶段边界

- Stage 10 只做预研，不实现正式同步。
- 本文只列当前模型 / 存储与未来同步之间的 schema gap。
- 本阶段不新增表、不新增字段、不修改 SQLite schema version、不写迁移、不新增 runtime。
- 本阶段不接入 CloudKit / iCloud，不新增 entitlement、container、record schema、同步调度、设备表、sync state 表或 UI。
- 用户已确认：CloudKit private database 是未来首选候选；E2EE 是正式同步前置门槛；附件 / 删除同步暂缓；文件卡片只同步路径历史，不上传原文件。

## 2. 只读核对范围

- `Sources/ClipEase/Core/Models/ClipboardItem.swift`
- `Sources/ClipEase/Core/Models/ClipboardGroup.swift`
- `Sources/ClipEase/Core/Storage/SQLiteClipboardStore.swift`
- `Sources/ClipEase/Core/Storage/ClipboardHistoryStore.swift`
- `Sources/ClipEase/Core/Storage/ClipboardHistoryPersistence.swift`
- `docs/V2_TECHNICAL_PLAN.md`
- `docs/V2_DEVELOPMENT_PLAN.md`
- `docs/V2_AGENT_RUNBOOK.md`
- `docs/V2_S10_ICLOUD_RISK_MATRIX.md`

## 3. 当前已具备的同步基础

| 能力 | 当前状态 | 同步价值 | 注意事项 |
| --- | --- | --- | --- |
| 稳定 UUID | `clipboard_items`、`item_assets`、`clipboard_item_files`、`groups`、`group_items` 使用 UUID；Swift model 的 item / group / file reference 也使用 UUID。 | 可作为本地稳定身份和未来 client record id 候选基础。 | 仍缺 origin id / remote record id / device id，不能直接表达跨设备来源和幂等上传。 |
| 创建时间 | item、group、asset、file reference、group item 均有 `created_at` 或 model `createdAt`。 | 可用于排序、首次捕获时间、备份恢复和冲突 fixture。 | 本机时间可能不可信；正式同步需区分 client time 和 server time。 |
| 更新时间预留 | SQLite `clipboard_items.updated_at`、`groups.updated_at` 存在。 | 可作为未来变更检测基础。 | `ClipboardItem` model 未暴露 `updatedAt`；多处本地修改仍用 snapshot 重写，当前不足以表达增量同步和字段级冲突。 |
| 分组归属 | `groups` + `group_items` 建模，item model 暴露 `groupID` / `groupedAt`。 | 未来可同步分组、分组关系和置顶 / 分组组合状态。 | 删除分组当前可连带删除内容；跨设备前必须拆清操作语义和 tombstone。 |
| 置顶状态 | `ClipboardItem.isPinned` / `pinnedAt` 和 SQLite `is_pinned` / `pinned_at` 已存在。 | 可作为未来轻量同步候选。 | 缺少置顶排序冲突策略、修改来源和字段版本。 |
| 来源 App | `source_app_name`、`source_bundle_id`、`source_icon_name`、`source_icon_file_name` 已记录。 | 可辅助展示、搜索、重复判断和跨设备重建图标。 | App icon 文件是本地缓存，不应作为首批关键同步资产。 |
| 附件索引 | `item_assets` 保存图片 / 富文本附件文件名、尺寸、创建时间；实际文件在 `Images` / `RichTexts`。 | 支持未来把附件元数据与二进制策略拆开。 | 缺少 manifest、checksum、远端 asset id、上传状态和加密元数据；图片 / 富文本附件同步已暂缓。 |
| 文件卡片引用 | `clipboard_item_files` 保存路径、显示顺序、文件名、扩展名、content type、大小、修改时间、目录 / alias、`path_status`、`last_checked_at`。 | 支持同步“路径历史”和文件摘要。 | 只记录本机绝对路径，不记录 bookmark，不复制原文件；跨设备默认不可访问。 |
| 附件路径 | 图片 / 富文本以本地附件目录相对文件名引用；文件卡片保存原文件绝对路径。 | 可区分 App 管理附件和外部文件路径。 | App 管理附件和外部原文件语义不同，正式同步前必须在数据字典中分开。 |
| 软删除字段预留 | SQLite `clipboard_items.is_deleted` 存在，加载时过滤 `is_deleted = 0`。 | 可作为未来 tombstone 设计的起点。 | 当前删除路径仍从内存移除并重写 snapshot，且会清理本地附件；不是完整 soft delete / tombstone。 |

## 4. Schema Gap 明细

| Gap | 用途 | 当前影响 | 正式同步前是否必须补 | Schema 变更风险 | 迁移 / 备份影响 | 测试要求 |
| --- | --- | --- | --- | --- | --- | --- |
| soft delete / tombstone 机制 | 表达跨设备删除、旧设备复活防护、远端保留和清理。 | 现有 `is_deleted` 只是预留列；本地删除仍硬删内存记录并可能删除附件，无法让离线设备知道记录已删除。 | 必须。即使首批继续暂缓删除同步，也必须在允许删除传播前补齐。 | 高。涉及删除语义、附件清理、分组删除、保留期限和隐私残留。 | 旧记录需默认非删除；备份需定义是否包含 tombstone、是否导入已删除记录和 tombstone 过期策略。 | 离线旧设备复活、删除后重登、tombstone 过期、分组删除 vs 内容删除、附件清理与撤销样本。 |
| `deletedAt` | 记录删除发生时间，用于排序、保留期限、远端清理和冲突判断。 | 只有 `is_deleted` 无法判断删除新旧，也无法解释关闭同步后的残留期限。 | 必须，用于任何跨设备删除或 tombstone 清理。 | 中高。需定义本机时间、server time 和迁移默认值。 | 备份恢复时不能把缺失 `deletedAt` 的旧记录误判为刚删除；导入需保留或丢弃策略。 | 设备时钟偏差、server time 覆盖、过期清理、备份导入已删除记录。 |
| `deviceID` / 本机安装实例 ID | 标识本机安装实例，支撑幂等上传、冲突审计和设备级状态。 | 无法区分哪台设备创建 / 修改 / 删除，重复捕获和重试上传难以去重。 | 必须。 | 中。可能需要 device table 或 settings store，并处理重装、迁移和备份恢复。 | 备份不应把旧设备 ID 直接克隆成新设备身份；恢复后需生成新安装实例 ID 或明确继承规则。 | 重装、换机、备份恢复、同 Apple ID 多设备、设备名变化、设备 ID 重置。 |
| `originDeviceID` | 记录条目首次捕获设备。 | 文件卡片路径、source app 和捕获时间无法标明来自哪台设备，跨设备不可用文案缺少依据。 | 必须，至少对历史条目和文件卡片路径历史必须有。 | 中。需新增字段并回填旧记录为 unknown / local legacy。 | 备份导入旧记录应标记为 imported / unknown origin，避免误写成本机捕获。 | 跨设备展示原设备、备份导入、重复捕获、文件路径不可用提示。 |
| `modifiedByDeviceID` / `deletedByDeviceID` | 审计最后修改 / 删除来源，支持冲突解释和安全提示。 | 冲突只能看时间，无法向用户解释“哪台设备覆盖了什么”。 | 删除同步前必须；字段级冲突前建议必须。 | 中。涉及每个可同步 record 的修改路径。 | 备份可能不保留或脱敏设备名；导入时需处理未知设备。 | 并发编辑、远端删除、设备重命名、未知设备 fallback。 |
| sync version / vector clock | 记录本地逻辑版本或多设备版本向量，用于离线并发编辑检测。 | last-write-wins 会静默覆盖文本、分组、置顶和设置；设备时钟偏差会放大误判。 | 必须选一种版本策略。首批可用单调 local version + server version，复杂编辑再评估 vector clock。 | 高。版本策略会影响所有同步记录和冲突算法。 | 旧记录需初始化版本；备份恢复需防止版本倒退或误覆盖远端。 | 双设备离线编辑、时钟偏差、重复提交、版本倒退、旧备份恢复后同步。 |
| record change tag / server version | 映射 CloudKit `recordChangeTag` 或服务端版本，做乐观并发和冲突检测。 | 无法安全保存 CloudKit 更新；远端有新版本时本地可能覆盖。 | 必须。 | 中高。需为每类 remote record 保存 tag，并处理 tag 失效。 | 备份默认不应携带可直接复用的 change tag，除非恢复策略明确。 | stale tag、server reject、change token 失效、旧客户端保存、partial failure。 |
| remote record id / zone id | 本地记录与 CloudKit record / zone 的映射。 | 无法增量同步，也无法区分本地 UUID 与远端 record 命名策略。 | 必须。 | 中。可选择 UUID 即 record name，但仍需 zone / owner / record type 版本。 | 备份恢复时 remote id 是否保留会影响 merge / duplicate；需确认。 | 同 UUID record、导入备份再开启同步、zone 重建、record type 迁移。 |
| sync state / dirty flag | 标记本地待上传、上传中、已同步、失败、冲突、只读等状态。 | 当前只有全量 snapshot 保存；无法断点恢复、重试或显示错误。 | 必须。 | 高。可能需要 sync state 表，影响保存路径和错误恢复。 | 备份包需决定是否包含 sync state；一般建议不包含运行中队列，只保留可合并数据。 | 上传失败重试、App 退出恢复、partial failure、断网恢复、重复上传幂等。 |
| zone change token / sync cursor | 保存 CloudKit 增量拉取游标。 | 每次只能全量扫描，性能和冲突风险高；无法恢复 token 失效。 | 必须。 | 中。通常放 sync state 表，需按 zone / record type 管理。 | 备份恢复后 cursor 通常应失效并重新拉取，不能直接信任旧 token。 | token 正常增量、token 失效、zone 删除、账号切换、全量重建。 |
| field-level modified metadata | 支持字段级合并，例如文本、置顶、分组、标题、颜色分别处理。 | `updated_at` 无法判断不同字段是否可合并；不同设备改不同字段也可能互相覆盖。 | 正式同步历史编辑 / 分组 / 置顶前必须；极窄首批可暂缓但需明确范围。 | 高。可能需要 per-field timestamp、operation log 或 event table。 | 旧记录需默认字段修改时间；备份体积和兼容性增加。 | 不同字段并发修改、同字段冲突、分组重命名 + 置顶、文本编辑 + path status。 |
| conflict status | 标记本地 record 处于冲突、待用户选择、自动合并成功或被远端覆盖。 | 冲突只能静默解决或失败；无法进入用户可理解的恢复流程。 | 正式支持可见冲突前必须；首批若强制自动策略仍需内部错误状态。 | 中。可能涉及 UI，但本任务只列 gap。 | 备份是否保存未解决冲突需明确；导入冲突记录可能污染新库。 | 自动冲突、手动冲突、冲突后备份、冲突恢复、旧客户端忽略冲突状态。 |
| attachment manifest | 记录一个 item 的附件清单、类型、相对路径、大小、content type、用途和是否必须存在。 | `item_assets` 只有基本行；无法判断附件完整性、上传完成度和记录是否可用。 | 图片 / 富文本附件同步前必须；首批附件暂缓可先列 gap。 | 中高。涉及附件生命周期和备份格式。 | 备份需要校验 manifest 与文件是否一致；导入缺失附件要可报告。 | 缺失图片、缺失 RTF、manifest 多余文件、附件重命名、导入部分附件。 |
| attachment checksum | 校验附件内容完整性、去重、加密前后验证和断点恢复。 | 图片有 `imageHash` 但并非通用 asset checksum；富文本和文件引用缺少统一 checksum。 | 附件上传前必须。 | 中。需计算成本和旧附件回填策略。 | 备份导出 / 导入可做完整性校验；旧备份缺 checksum 时需 fallback。 | hash 回填、大附件 hash、损坏附件检测、重复附件去重、hash 不一致。 |
| attachment remote asset id / upload state | 映射 CKAsset 或远端对象，记录上传 / 下载 / 缓存状态。 | 无法知道附件是否已上传、是否可下载、是否为本地缓存。 | 附件同步前必须。 | 高。涉及 CKAsset 生命周期、重试、缓存清理。 | 备份一般不应携带短期上传状态；如携带 remote id 需避免跨账号误用。 | 上传中断、下载失败、缓存删除、远端 asset 缺失、账号切换。 |
| encryption metadata | 记录加密版本、算法、key id、nonce / salt、AAD 版本和密文校验。 | 用户已要求 E2EE 为正式同步前置；当前 schema 无法描述客户端加密记录。 | 必须。 | 高。影响所有可同步敏感字段和附件，且需密钥恢复策略。 | 备份需定义明文 / 密文、key id 是否随包保存、换机恢复流程。 | 加解密往返、密钥轮换、忘记密钥、换机、旧版本密文兼容、附件加密。 |
| settings sync scope | 标记哪些设置可同步、哪些本机私有、哪些需要用户确认。 | 目前设置散落在 UserDefaults / 本机状态；没有同步范围和隐私分类。 | 同步设置前必须；若首批不同步设置可暂缓。 | 中。可能需要 settings record schema 或数据字典先行。 | 备份导入设置与同步设置可能冲突，需定义优先级。 | 低风险设置同步、本机私有设置不上传、备份恢复设置、冲突覆盖。 |
| file path availability per device | 表达文件卡片路径在当前设备是否可访问、原设备路径、最后检查设备和检查时间。 | 当前 `path_status` 是本机路径状态，跨设备后语义不明确。 | 文件卡片路径历史同步前必须。 | 中。可能扩展 file reference 或另建 per-device 状态。 | 备份路径历史不能被导入设备误判为可访问；需保留原设备路径。 | 跨设备路径不可用、同路径但不同文件、部分文件失效、iCloud placeholder、权限拒绝。 |

## 5. 文件卡片路径历史跨设备语义

当前文件卡片只保存外部原文件路径和元数据，不复制原文件、不保存 security-scoped bookmark、不把原文件放入 `Images` / `RichTexts` 附件目录，也不上传原文件。

未来若同步文件卡片，第一批只能同步“路径历史”：

- 同步内容可以包括原设备 ID、原设备显示名、原始绝对路径、显示名、扩展名、content type、大小、修改时间、目录 / alias 标记和捕获顺序。
- 不能上传原文件内容，不能暗示其他设备可打开原文件。
- 其他设备默认应显示“原设备路径 / 本机不可访问”语义，除非本机重新检查后确认同一路径可访问。
- 即使另一台设备存在相同绝对路径，也不能默认认为是同一个文件；正式同步前至少需要 checksum、file id 或用户确认策略，且本阶段不实现。
- 文件卡片路径可能暴露用户名、项目名、客户名或内部目录结构；同步数据字典必须把路径标为敏感字段，并纳入 E2EE 范围。
- 多文件卡片允许部分路径可访问、部分路径不可访问；需要 per-file、per-device path status，不能只用 item 级状态。

结论：文件卡片路径历史是未来元数据同步候选，但原文件上传、远端下载、自动修复路径、bookmark 同步和 CKAsset 文件副本都不进入 Stage 10，也不进入第一轮正式同步默认范围。

## 6. 正式同步前建议拆分

- `CloudKit record mapping spike`：定义 record type、zone、remote id、change tag、server version 和兼容策略。
- `Tombstone lifecycle spike`：定义 soft delete、`deletedAt`、删除来源设备、保留期限、远端清理和旧设备复活防护。
- `Device identity spike`：定义安装实例 ID、origin device、modified / deleted device、设备显示名和备份恢复行为。
- `Conflict fixture spike`：定义 version / vector clock、字段级修改元数据、冲突状态和自动 / 手动合并策略。
- `Attachment manifest spike`：定义图片 / 富文本 manifest、checksum、远端 asset id、upload state 和缓存状态。
- `File path history spike`：定义原设备路径、per-device path status、跨设备不可用文案和路径敏感性。
- `E2EE metadata spike`：定义加密字段、key id、nonce / salt、算法版本、密钥恢复和附件加密边界。
- `Backup x sync spike`：定义备份是否携带 remote id / sync state / tombstone / device id，以及导入后 merge / replace / keep local 策略。

## 7. PASS / HOLD

PASS：

- 当前模型 / 存储已具备 UUID、createdAt / updatedAt 预留、groupID / 分组关系、isPinned、sourceApp、fileReferences 和附件路径等未来同步基础。
- 已列出正式同步前必须补齐的 tombstone、device、version、record mapping、sync state、attachment manifest、conflict、remote id 和 encryption metadata gap。
- 已明确文件卡片只同步路径历史，不上传原文件，跨设备默认不可用。

HOLD：

- HOLD 任何新增表 / 字段 / schema version / migration。
- HOLD 任何 soft delete、device table、sync state table、CloudKit record mapping runtime。
- HOLD 任何附件上传下载、文件原件上传、跨设备删除传播、冲突合并 runtime 或 E2EE runtime。
