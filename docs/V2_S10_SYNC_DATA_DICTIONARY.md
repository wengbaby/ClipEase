# ClipEase V2 Stage 10 iCloud 同步数据字典

任务卡：`V2-S10-ICLOUD-SYNC-DATA-DICTIONARY-001`

阶段：Stage 10 iCloud 同步预研 - 同步数据字典 / 用户语义

结论：PASS 产出未来同步数据字典和用户语义说明；HOLD 任何业务代码、SQLite schema / migration、CloudKit / iCloud runtime、entitlement、同步 UI、附件上传下载、跨设备删除传播、冲突合并 runtime 和端到端加密 runtime。

## 1. 本阶段边界

- Stage 10 只做预研，不提供任何用户可见同步功能。
- 本文只定义未来同步候选、首轮正式同步候选、用户可见语义、隐私等级、跨设备可用性、冲突策略候选、E2EE 要求、schema gap 依赖和测试要求。
- 第一轮正式同步候选只考虑历史条目、分组、置顶状态、少量低风险设置。
- 图片附件、富文本附件、原文件副本、搜索索引、缩略图、缓存和备份包状态不进入第一轮正式同步。
- 文件卡片只同步路径历史和摘要，不上传原文件；跨设备路径不可用时只显示不可用状态。
- 忽略 App / 敏感遮罩配置默认不作为首轮同步，必须用户单独确认。
- 用户已确认：CloudKit private database 是未来正式同步首选候选；E2EE 是正式同步前置门槛；附件 / 删除同步暂缓；文件卡片只同步路径历史。

## 2. 隐私等级定义

| 等级 | 定义 | 同步含义 |
| --- | --- | --- |
| P0 本机派生 / 可重建 | 搜索索引、缩略图、App icon 缓存、临时状态等可由本机数据重建。 | 不作为同步数据；必要时每台设备本地重建。 |
| P1 低风险偏好 | 少量不会暴露剪贴板内容、文件路径、隐私规则或身份信息的偏好。 | 可作为首轮设置候选，但仍需 opt-in 和冲突规则。 |
| P2 使用元数据 | 分组、置顶、时间戳、来源 App 名称 / bundle id、内容类型等会透露使用行为。 | 可评估同步；正式前需要 E2EE、用户告知和 schema gap 支持。 |
| P3 内容敏感 | 文本、链接、颜色值、图片 / 富文本摘要、文件路径历史、忽略规则等可能暴露实际内容或工作上下文。 | 只有用户显式开启同步且 E2EE 方案成立后才可上传。 |
| P4 高敏感附件 / 原文件 | 图片附件、富文本附件、文件原件副本、包含私密内容的大二进制。 | 第一轮暂缓；未来必须单独确认、单独加密和单独测试。 |

## 3. 首轮正式同步候选摘要

| 数据类别 | 是否候选同步 | 是否第一轮正式同步候选 | 首轮理由 |
| --- | --- | --- | --- |
| 历史条目：text / link / color | 是 | 是 | 核心历史内容；需 E2EE、record mapping、冲突和去重策略。 |
| 历史条目：image / richText | 是 | 仅元数据 / 摘要可评估；附件暂缓 | 可同步卡片存在性和纯文本摘要，图片 / RTF 二进制暂缓。 |
| 历史条目：file | 是 | 路径历史可评估；原文件不上传 | 只保留原设备路径记录和摘要，跨设备不可用显示不可用。 |
| 分组 | 是 | 是 | 低复杂度结构化数据，但需重命名 / 删除冲突策略。 |
| 置顶状态 | 是 | 是 | 轻量状态；需置顶顺序和 last-write / 字段级策略。 |
| 保存期限 / 少量设置 | 是 | 是，仅低风险项 | 仅限不会暴露隐私规则和本机状态的设置。 |
| 忽略 App / 敏感遮罩配置 | 是 | 否 | 这些规则本身暴露用户隐私边界，必须用户单独确认。 |
| 图片附件 / 富文本附件 | 是 | 否 | P4 附件二进制暂缓；需 manifest、checksum、CKAsset、E2EE。 |
| App icon | 否 | 否 | 本机缓存 / 可重建，不作为同步数据。 |
| 文件卡片路径历史 | 是 | 是，限定路径历史 | 不上传原文件；路径属 P3 敏感字段。 |
| 原文件副本 | 否 | 否 | 不上传、不复制、不进入 CloudKit 或 iCloud Drive。 |
| 来源 App 信息 | 是 | 是，随历史条目元数据 | 用于展示和搜索；属于使用元数据。 |
| 时间戳 | 是 | 是，随记录同步 | 用于排序和冲突，但需 server time / 版本策略补强。 |
| 搜索派生数据 | 否 | 否 | 本机重建，不同步。 |
| 缩略图 / 缓存 | 否 | 否 | 本机重建，不同步。 |
| 备份包状态 | 否 | 否 | 属本机导入导出状态，不进入云同步。 |

## 4. 数据字典

| 数据类别 | 是否候选同步 | 是否第一轮正式同步候选 | 用户可见语义 | 隐私等级 | 跨设备可用性 | 冲突策略候选 | 是否需要 E2EE | 是否需要 schema gap 支持 | 测试要求 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 历史条目：text | 是 | 是 | 用户复制过的纯文本历史在开启同步后可出现在其他设备。 | P3 内容敏感 | 高；文本可直接跨设备使用。 | record version + field-level merge；最小方案可评估 last-write-wins，但不得静默覆盖编辑。 | 是 | remote record id、change tag、deviceID、originDeviceID、sync state、encryption metadata、field modified metadata。 | 双设备新增 / 编辑 / 离线重试 / 重复文本去重 / 大文本 / E2EE 往返 / 关闭同步残留。 |
| 历史条目：link | 是 | 是 | 链接作为历史内容同步；其他设备可复制或打开链接。 | P3 内容敏感 | 高；但内网链接、登录态链接可能不可用。 | 同 text；额外需要 content hash / canonicalization spike 防重复。 | 是 | 同 text；可增加 link metadata 版本。 | URL 编码、长链接、内网链接不可用、重复链接、source app 保留、隐私文案。 |
| 历史条目：color | 是 | 是 | 颜色值和卡片类型同步，其他设备可复制颜色值。 | P3 内容敏感 | 高；颜色值本身可跨设备使用。 | last-write-wins 或 field-level merge。 | 是 | record mapping、type schema、encryption metadata、version。 | hex / RGB / alpha 一致性、颜色编辑冲突、排序、重复颜色。 |
| 历史条目：image | 是 | 第一轮只评估记录元数据 / 摘要；图片附件暂缓 | 其他设备最多知道曾有图片卡片；未同步附件时显示附件不可用 / 暂未同步。 | P4 高敏感附件；元数据为 P3 | 低到中；没有图片二进制时不可完整使用。 | 元数据可用 record version；附件需 manifest 后再设计。 | 是 | attachment manifest、checksum、remote asset id、upload state、cache state、encryption metadata。 | 无附件降级展示、图片附件缺失、备份导入交叉、不得上传图片二进制、E2EE 附件 spike。 |
| 历史条目：richText | 是 | 第一轮只评估纯文本摘要 / 记录元数据；RTF 附件暂缓 | 其他设备可看到纯文本摘要；原格式附件未同步时不承诺可恢复格式。 | P4 高敏感附件；摘要为 P3 | 摘要可用，完整富文本不可用。 | 摘要字段级策略；RTF 编辑冲突暂缓。 | 是 | attachment manifest、RTF checksum、remote asset id、field modified metadata、encryption metadata。 | 摘要同步、RTF 缺失提示、格式不丢失声明防误解、富文本编辑冲突 fixture。 |
| 历史条目：file | 是 | 是，限定路径历史和摘要 | 其他设备只看到原设备路径记录；本机不可访问时显示不可用，不暗示文件已同步。 | P3 内容敏感；原文件为 P4 | 低；只有同路径且本机校验可访问时才可用。 | file reference append / field-level merge；禁止用相同路径自动认定同一文件。 | 是 | originDeviceID、file path availability per device、file reference version、path status、encryption metadata。 | 跨设备路径不可用、部分文件失效、同路径不同文件、iCloud placeholder、权限拒绝、不可上传原文件断言。 |
| 分组 | 是 | 是 | 用户创建的分组名称、颜色、图标和排序可在设备间一致。 | P2 使用元数据；名称可能 P3 | 高；结构化数据可跨设备使用。 | field-level merge；重命名可用 server version；删除分组需 tombstone，首轮删除同步暂缓。 | 是 | remote record id、record version、group tombstone、sort order metadata、deviceID。 | 重名分组、重命名冲突、排序冲突、删除分组不传播内容删除、备份恢复合并。 |
| 置顶状态 | 是 | 是 | 置顶历史在设备间保持；置顶顺序需有清晰规则。 | P2 使用元数据 | 高；依赖目标历史条目存在。 | field-level merge；置顶布尔可 last-write-wins，顺序需独立 sort/version。 | 是 | pinnedAt、pin sort order、field modified metadata、record version。 | 双设备置顶 / 取消置顶、置顶顺序冲突、目标记录缺失、时钟偏差。 |
| 保存期限 / 少量低风险设置 | 是 | 是，仅低风险项 | 用户选择的低风险偏好可跨设备一致，例如非敏感保留策略。 | P1 到 P2 | 中；不同设备可能需要本机覆盖。 | last-write-wins + per-setting scope；必要时本机优先。 | 是，若会影响历史内容保留 | settings sync scope、setting version、device override 标记。 | 设置白名单、不在白名单不上传、冲突覆盖、关闭同步后本机设置保持。 |
| 忽略 App 配置 | 是 | 否 | 用户选择不记录哪些 App；该规则本身会暴露用户隐私偏好。 | P3 内容敏感 | 中；跨设备 App bundle 可能不存在。 | 用户单独确认后 per-rule merge；本机 App 不存在时保留但不生效。 | 是 | settings sync scope、rule id、bundle id normalization、device applicability。 | 默认不上传、单独确认、App 不存在、bundle id 变更、隐私文案。 |
| 敏感遮罩配置 | 是 | 否 | 遮罩规则用于本机展示保护；不同步时每台设备独立配置。 | P3 内容敏感 | 中；规则可能可跨设备，但风险高。 | 用户单独确认后 field-level merge；冲突保守取更严格规则。 | 是 | settings sync scope、rule version、encryption metadata、local-only flag。 | 默认不上传、严格规则优先、规则泄露评估、搜索索引不上传。 |
| 图片附件 | 是 | 否 | 图片二进制暂不随历史同步；其他设备不承诺显示原图。 | P4 高敏感附件 | 低；未上传附件不可用。 | 暂缓；未来需 asset manifest + upload state。 | 是 | attachment manifest、checksum、remote asset id、upload / download state、encrypted asset metadata。 | 不上传断言、缺失附件 UI、附件完整性、配额失败、E2EE 附件。 |
| 富文本附件 | 是 | 否 | RTF / 富文本文件暂不随历史同步；只可评估纯文本摘要。 | P4 高敏感附件 | 低到中；摘要可用，格式不可用。 | 暂缓；未来需附件版本和编辑冲突策略。 | 是 | attachment manifest、checksum、remote asset id、conflict status、encrypted asset metadata。 | 不上传断言、摘要可用、RTF 缺失、编辑冲突、备份导入。 |
| App icon | 否 | 否 | 图标由本机根据来源 App 尽量重建；缺失时使用默认图标。 | P0 本机派生 / 可重建 | 中；同一 App 在其他设备可能存在也可能不存在。 | 不适用。 | 否 | 不需要；可保留 bundle id / icon cache policy。 | 图标缓存缺失、bundle id 重建、App 不存在 fallback、不得作为同步资产。 |
| 文件卡片路径历史 | 是 | 是，限定路径历史 | 同步原设备路径、文件名、类型、大小、修改时间等摘要；本机不可用时显示不可用。 | P3 内容敏感 | 低到中；路径通常只在原设备可用。 | per-file record version；path status 为 per-device 派生，不能互相覆盖。 | 是 | originDeviceID、per-device availability、file reference id、path status metadata、encryption metadata。 | 多文件顺序、部分失效、原设备标识、路径含用户名、跨设备不可用提示、不可上传原文件。 |
| 原文件副本 | 否 | 否 | ClipEase 不上传文件卡片指向的原文件，不提供跨设备文件副本。 | P4 高敏感附件 / 原文件 | 不可用；需回原设备或原存储位置。 | 不适用。 | 若未来评估则必须 | 当前不需要；未来需独立 file asset manifest、授权、配额、清理和 E2EE。 | 确认备份 / 同步均不含原文件、删除历史不删除原文件、文案不得暗示已同步文件。 |
| 来源 App 信息 | 是 | 是，随历史条目 | 其他设备可看到来源 App 名称 / bundle id；图标本机重建。 | P2 使用元数据 | 中；来源 App 可能不存在。 | 随历史 record；field-level merge，通常创建后不改。 | 是 | source app fields、origin device、record version。 | App 名称 / bundle id 保留、App 不存在 fallback、图标不上传、隐私文案。 |
| 时间戳 | 是 | 是，随记录同步 | 保留创建、修改、置顶、加入分组等时间，用于排序和解释历史。 | P2 使用元数据 | 高；但本机时钟可能不可信。 | server time + client time；冲突使用 server version / change tag。 | 是 | server timestamp、client timestamp、version、clock skew handling。 | 时钟偏差、离线创建、排序稳定性、备份导入旧时间、server time 覆盖。 |
| 搜索派生数据 | 否 | 否 | 每台设备本地根据可用内容重建搜索索引。 | P0 本机派生；索引内容可能 P3 | 本机可用；不同设备因附件缺失而不同。 | 不适用。 | 不上传；本机索引仍应保护 | 不需要同步 schema；需要明确 index invalidation。 | 不出现在同步 payload、附件缺失时索引降级、重建性能、敏感遮罩不生成远端索引。 |
| 缩略图 / 缓存 | 否 | 否 | 缩略图和缓存是本机性能资产，可删除可重建。 | P0 本机派生；内容可能 P4 | 本机可用；跨设备重建或缺失。 | 不适用。 | 不上传；若未来上传缩略图则必须 | 不需要同步 schema；未来附件策略可另评估。 | 缓存清理、缺失重建、不上传断言、图片附件暂缓时无缩略图同步。 |
| 备份包状态 | 否 | 否 | 备份导出 / 导入结果、最近备份状态不随 iCloud 同步。 | P2 本机操作元数据 | 低；每台设备独立。 | 不适用。 | 否 | 不需要；但 backup x sync spike 需定义导入后 merge 行为。 | 备份导入不携带 sync cursor、remote id 策略明确、导入后不误触发上传。 |

## 5. 用户语义红线

- “同步历史条目”不等于同步所有附件；图片和富文本附件第一轮暂缓。
- “同步文件卡片”只表示同步路径历史，不表示上传原文件、不表示其他设备可打开原文件。
- 文件卡片跨设备路径不可用时，只能显示不可用 / 原设备路径语义；不能自动伪装为可打开。
- 原文件副本不上传，不复制到 CloudKit，不复制到 iCloud Drive，不写入 SQLite。
- 忽略 App 和敏感遮罩配置默认不进入首轮同步；若未来同步，必须有独立确认和隐私说明。
- 搜索索引、缩略图、App icon 缓存和其他缓存不作为同步数据。
- 删除同步仍暂缓；本数据字典不放行跨设备删除传播。
- E2EE 是正式同步前置门槛；CloudKit private database 不等同于 App 已完成端到端加密。

## 6. 后续 spike 建议

- `Sync payload whitelist spike`：把本文首轮候选转成严格白名单，默认拒绝未列字段。
- `User semantics copy spike`：为文件路径历史、附件暂缓、E2EE、关闭同步和删除暂缓设计用户文案。
- `Settings scope spike`：定义低风险设置白名单、忽略 App / 敏感遮罩单独确认流程和本机覆盖规则。
- `File path availability spike`：定义 per-device path status、原设备显示、同路径不同文件和不可用状态。
- `Attachment exclusion test spike`：确保图片 / 富文本附件、缩略图、原文件副本不会进入首轮同步 payload。
- `E2EE payload classification spike`：把 P2 / P3 / P4 字段映射到加密 envelope、key id 和恢复策略。

## 7. PASS / HOLD

PASS：

- 已覆盖历史条目 text / link / color / image / richText / file。
- 已覆盖分组、置顶状态、保存期限 / 少量设置、忽略 App / 敏感遮罩配置。
- 已覆盖图片附件、富文本附件、App icon、文件卡片路径历史、原文件副本。
- 已覆盖来源 App 信息、时间戳、搜索派生数据、缩略图 / 缓存、备份包状态。
- 已明确第一轮候选只考虑历史条目、分组、置顶状态和少量低风险设置。
- 已明确文件卡片只同步路径历史，不上传原文件；跨设备路径不可用只显示不可用状态。
- 已明确图片 / 富文本附件暂缓；原文件副本不上传。
- 已明确忽略 App / 敏感遮罩配置默认不作为首轮同步，需用户单独确认。
- 已明确搜索索引、缩略图和缓存不作为同步数据。

HOLD：

- HOLD 任何业务代码、同步 UI、runtime、CloudKit / iCloud 接入、entitlement、schema 迁移或 record schema。
- HOLD 任何附件上传下载、图片 / 富文本附件同步、文件原件上传、原文件副本同步或 CKAsset 实现。
- HOLD 任何跨设备删除传播、冲突合并 runtime、端到端加密 runtime、密钥管理或同步调度实现。
