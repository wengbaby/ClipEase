# 第二版 Agent 协作规约

本文定义第二版开发时多个 Agent 的角色、约束、风险等级、调度流程、门禁、报告和记录方式。

当前状态：第二版已进入 SQLite-only / no favorite / no management 新基线；后续任务以该基线为准。

当前基线覆盖规则：

- SQLite-only 是唯一运行时数据基线。
- 旧 JSON 数据代码、JSON Repository、JSON 到 SQLite 迁移代码不再作为后续运行时能力维护。
- 收藏、管理模式、多选和批量操作已移除，不得恢复。
- 分组、置顶、搜索、备份导入安全和主窗口单条操作继续保留。
- 阶段 8 开工任务卡必须显式写入“不得恢复收藏 / 管理模式；不得恢复 JSON 迁移运行时路径”。

## 1. 文档入口

- Agent 技能卡总览：`docs/agents/README.md`
- 用户反馈和功能守卫清单：`docs/V2_FEEDBACK_AND_GUARDS.md`
- 主控 Agent：`docs/agents/main-controller-agent.md`
- 数据层开发 Agent：`docs/agents/data-layer-agent.md`
- UI / 交互开发 Agent：`docs/agents/ui-interaction-agent.md`
- 功能增强开发 Agent：`docs/agents/feature-enhancement-agent.md`
- Bugfix Agent：`docs/agents/bugfix-agent.md`
- V2 测试计划 Agent：`docs/agents/v2-test-plan-agent.md`
- 测试 Agent：`docs/agents/test-agent.md`
- 审查 Agent：`docs/agents/review-agent.md`
- 验收 Agent：`docs/agents/acceptance-agent.md`
- 产品规则 Agent：`docs/agents/product-rules-agent.md`
- 架构守门 Agent：`docs/agents/architecture-gatekeeper-agent.md`
- 用户体验 Agent：`docs/agents/ux-agent.md`
- 文档 / 日志 Agent：`docs/agents/docs-log-agent.md`
- 专项开发 Agent：`docs/agents/specialist-dev-agent.md`

## 2. 总原则

- 第二版仍按 `docs/V2_DEVELOPMENT_PLAN.md` 小步推进。
- 主控 Agent 长期保留，负责调度、汇总、否决、返工和阶段放行。
- 主控 Agent 不写业务代码。
- 主控 Agent 不亲自修复 bug；用户反馈 bug 后，主控只负责复现、归类、定级、生成任务卡和调度修复。
- 每次阶段开始前，主控 Agent 必须先调用 V2 测试计划 Agent，确认测试 / 验收门禁是否完整。
- 每次处理 bug、返工或新增功能前，主控 Agent 必须先读取 `docs/V2_FEEDBACK_AND_GUARDS.md`。
- 主控 Agent 必须持久记录用户反馈和新增功能守卫，不能只依赖会话记忆。
- 主工作区只允许主控 Agent 负责最终集成。
- 其他 Agent 只能在明确任务卡范围内工作，不能自行扩大功能范围。
- 每个 Agent 都必须遵守对应技能卡。
- 高风险核心模块串行执行，主控 Agent 全程监控。
- 低风险模块允许多 Agent 并行执行，主控 Agent 负责冲突检测。
- Agent 可以直接沟通，但结论必须回报主控 Agent。
- 每次阶段性交付都必须留下验证结果、未验证项和机器可读摘要。
- 非阻塞项写入 `docs/V2_OPTIMIZATION_BACKLOG.md`。
- 调度、沟通、文件锁、冲突、bug 修复和功能守卫记录写入 `docs/V2_AGENT_RUNBOOK.md`。

## 2.1 主控执行方式

主控 Agent 后续执行统一按以下规则处理：

1. 主控 Agent 不写业务代码。
2. 主控 Agent 不亲自修 bug。
3. 用户反馈 bug 后，主控只负责记录、复现、归类、定级、生成 Bug 修复任务卡和调度。
4. 小范围 bug 交给 Bugfix Agent。
5. 原模块核心逻辑缺陷退回原开发 Agent。
6. 架构、schema、Repository、性能问题交给架构守门 Agent + 原开发 Agent。
7. 产品规则冲突交给产品规则 Agent + 用户确认。
8. 测试缺口交给测试 Agent。
9. `docs/V2_TEST_PLAN.md` 的维护交给 V2 测试计划 Agent。
10. 每次阶段开始前，先调用 V2 测试计划 Agent 检查测试 / 验收门禁是否完整。
11. 每次处理 bug、返工或新增功能前，必须读取 `docs/V2_FEEDBACK_AND_GUARDS.md`。
12. Bug 修复任务卡必须包含关联历史反馈、关联功能守卫、受影响功能、不得回归项和最小回归测试。
13. 修复后测试 Agent 必须回归原失败路径和相关功能守卫。
14. 非阻塞项写入 `docs/V2_OPTIMIZATION_BACKLOG.md`。
15. 调度、沟通、文件锁、冲突、bug 修复和功能守卫记录写入 `docs/V2_AGENT_RUNBOOK.md`。

## 3. 冲突优先级

当用户、文档、主控 Agent、专项 Agent 意见冲突时，按以下顺序处理：

1. 用户。
2. 已确认文档。
3. 主控 Agent。
4. 专项 Agent。

如果已确认文档之间互相冲突：

- 大冲突暂停实现，交给主控 Agent 和用户确认。
- 小冲突可由主控 Agent 临时合并处理，但必须记录到 `docs/V2_AGENT_RUNBOOK.md`。
- 冲突处理后由文档 / 日志 Agent 统一整合文档。

如果文档与代码现状冲突：

- 小冲突可由负责 Agent 自行适配并记录。
- 大冲突必须暂停任务并报告主控 Agent。
- 冲突必须记录到 Agent 调度日志和 `docs/V2_AGENT_RUNBOOK.md`。

## 4. Agent 队伍

长期保留角色：

- 主控 Agent。
- 数据层开发 Agent。
- UI / 交互开发 Agent。
- 功能增强开发 Agent。
- Bugfix Agent。
- V2 测试计划 Agent。
- 测试 Agent。
- 审查 Agent。
- 验收 Agent。
- 产品规则 Agent。
- 架构守门 Agent。
- 用户体验 Agent。
- 文档 / 日志 Agent。

临时角色：

- 专项开发 Agent 按阶段或任务卡创建。
- 如果同一阶段还有相关任务，可以复用上下文。
- 高风险任务在 Agent 闲置时需要记录快照要点，便于复用或回滚。

## 5. 风险等级

第二版任务使用四级风险：

| 等级 | 定义 | 默认门禁 |
| --- | --- | --- |
| 低 | 文档、小范围 UI、无数据影响 | 简查 + 主控复核 |
| 中 | 普通功能改动、局部 UI / 数据接口变化 | 测试 Agent 验证 + 审查 Agent 综合审查 |
| 高 | 数据层、跨模块、性能、迁移、复杂交互 | 完整四步门禁：开发完成 → 测试验证 → 审查 → 验收放行 |
| 红线 | 破坏性或不可轻易恢复操作 | 完整四步门禁 + 用户确认 + 调度日志记录 |

## 6. 红线操作

以下操作属于红线级：

- 删除 JSON。
- 恢复 JSON Repository 或 JSON 到 SQLite 迁移运行时路径。
- 删除附件。
- 清空 SQLite。
- 导入备份。
- 数据迁移。
- 数据健康修复。
- 批量删除。
- 修改保存期限清理逻辑。
- 修改分组删除逻辑。
- 恢复收藏字段、收藏 UI、收藏快捷键、管理模式、多选或批量操作。
- 修改版本号。
- 修改构建脚本。
- 修改发布流程。

红线确认策略：

- 破坏性操作每次执行前都必须问用户。
- 非破坏性高风险操作可按阶段确认，但主控 Agent 必须明确记录确认范围。
- 自动化门禁和用户确认提示必须不可绕过。

红线确认格式：

```text
红线确认请求：
任务卡 ID：
操作：
影响：
可恢复性：
替代方案：
自动化门禁：
需要用户确认的问题：
```

确认记录应包含用户确认时间、操作人和任务卡 ID。

## 7. 任务卡

主控 Agent 调用其他 Agent 前必须生成任务卡。

- 高风险和红线任务必须使用完整任务卡。
- 中低风险任务可简化，但必须包含目标、范围、完成标准和验证要求。

完整任务卡模板：

```text
任务卡 ID：
任务名称：
所属阶段：
风险等级：
负责 Agent：
依赖 Agent：
目标：
相关文档：
预计影响文件：
允许修改：
禁止修改：
完成标准：
必须验证：
回滚策略：
用户确认点：
并行冲突点：
人工验收项：
交付格式：
风险提示：
关联历史反馈：
关联功能守卫：
不得回归项：
```

机器可读摘要：

```json
{
  "task_card_id": "",
  "stage": "",
  "risk_level": "low|medium|high|redline",
  "owner_agent": "",
  "dependent_agents": [],
  "allowed_paths": [],
  "forbidden_paths": [],
  "acceptance_criteria": [],
  "verification_required": [],
  "user_confirmation_required": false,
  "linked_feedback": [],
  "linked_guards": [],
  "regression_guards": []
}
```

## 8. Agent 交付

每个 Agent 完成任务时，必须同时给出人类摘要和机器可读摘要。

人类摘要模板：

```text
完成内容：
修改文件：
验证结果：
未验证项：
发现风险：
建议下一步：
```

机器可读摘要模板：

```json
{
  "agent": "",
  "task_card_id": "",
  "status": "completed|blocked|needs_review",
  "changed_files": [],
  "verification": {
    "passed": [],
    "failed": [],
    "not_run": []
  },
  "risks": [],
  "open_items": [],
  "next_steps": []
}
```

## 9. Agent 沟通记录

Agent 之间可以直接沟通，但必须记录：

```text
沟通记录：
来源 Agent：
目标 Agent：
问题：
回答：
结论：
影响任务：
影响文件：
是否阻塞：
预计风险等级：
```

沟通结论必须回报主控 Agent。跨模块沟通和高风险沟通必须写入 `docs/V2_AGENT_RUNBOOK.md`。

## 10. 文件锁和所有权

高风险文件建立所有权表。所有权表包含：

- 文件路径。
- 默认负责 Agent。
- 允许协作 Agent。
- 修改前确认要求。
- 风险原因。
- 典型改动类型。
- 禁止改动类型。
- 最后修改时间。
- 最近负责 Agent。

文件锁规则：

- 高风险文件允许多人读，但只能一人写。
- 写锁必须由主控 Agent 发放和解除。
- 锁状态记录到调度日志。
- 可设置锁超时机制或优先级队列，防止长时间占用。

初始高风险文件：

| 文件 / 目录 | 默认负责 Agent | 风险原因 |
| --- | --- | --- |
| `Sources/ClipEase/Core/Storage/` | 数据层开发 Agent | 主存储、迁移、导入导出 |
| `Sources/ClipEase/Core/Models/ClipboardItem.swift` | 数据层开发 Agent | 数据模型影响全局 |
| `Sources/ClipEase/Features/Settings/SettingsView.swift` | UI / 交互开发 Agent | 设置页聚合大量数据操作入口 |
| `Sources/ClipEase/Features/HistoryWindow/` | UI / 交互开发 Agent | 主窗口核心交互 |
| `Package.swift` | 主控 Agent 授权后指定 | 构建依赖和目标结构 |
| `Resources/Info.plist` | 主控 Agent 授权后指定 | App 元数据和权限 |
| `scripts/build-app.sh` | 主控 Agent 授权后指定 | 构建和版本流程 |

当前阶段 8 建议文件锁：

| 文件 / 目录 | 默认负责 Agent | 允许改动 | 禁止改动 |
| --- | --- | --- | --- |
| `Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift` | UI / 交互开发 Agent | 主窗口布局、搜索框状态、提示层挂载、单条选择体验 | 恢复收藏 / 管理模式 / 多选 / 批量入口；改 schema / Store 语义 |
| `Sources/ClipEase/Features/HistoryWindow/HistoryWindowController.swift` | UI / 交互开发 Agent | 窗口层级、显示隐藏、焦点和外部点击处理 | 数据迁移、备份导入、附件删除 |
| `Sources/ClipEase/Features/HistoryWindow/HistoryCardView.swift` | UI / 交互开发 Agent | 卡片选中态、右键目标、边框和视觉状态 | 收藏星标、管理模式选择框、批量状态 |
| `Sources/ClipEase/Features/HistoryWindow/HistoryWindowInputState.swift` | UI / 交互开发 Agent | 搜索展开、清空、Esc、键盘焦点状态 | Repository / SQLite 查询下沉 |
| `Sources/ClipEase/Core/Storage/` | 数据层开发 Agent | 阶段 8 首批默认不修改 | 任何未单独确认的 schema、migration、backup、import、attachment lifecycle 改动 |
| `Sources/ClipEase/Core/Models/ClipboardItem.swift` | 数据层开发 Agent | 阶段 8 首批默认不修改 | 恢复 favorite 字段；新增未确认数据字段 |

## 11. 文档和日志

开发 Agent 只能修改与自己任务直接相关的文档片段。

文档 / 日志 Agent 负责：

- 全局整合。
- 格式统一。
- 调度记录。
- 优化 backlog。
- 开发日志。

主控 Agent 定期审查并解决冲突，最终落地版本以主控 Agent 审查后的文档为准。

新增记录文件：

- `docs/V2_OPTIMIZATION_BACKLOG.md`：非阻塞优化任务归档。
- `docs/V2_AGENT_RUNBOOK.md`：Agent 调度记录、沟通记录、文件锁、冲突和阶段演练记录。

## 12. 优化 Backlog

验收 Agent 或审查 Agent 发现非阻塞项时，必须生成优化任务卡。

优化任务卡写入 `docs/V2_OPTIMIZATION_BACKLOG.md`，未来可同步到 GitHub Issues，但文档是统一归档来源。

模板：

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

## 13. 报告格式

最终报告以 Markdown 为主，并嵌入 JSON 代码块，兼顾人工阅读和自动化解析。

JSON 顶层字段：

```json
{
  "report_version": "1.0",
  "timestamp": "",
  "stage": "",
  "phase_owner": "main-controller",
  "summary": "",
  "changed_files": [],
  "verification": {
    "passed": [],
    "failed": [],
    "not_run": []
  },
  "agents": [],
  "risks": [],
  "open_items": [],
  "next_steps": [],
  "blocking_items": [],
  "non_blocking_items": [],
  "user_confirmation_required": false
}
```

## 14. 阶段门禁

每个功能完成后必须经过：

1. 开发完成。
2. 测试 Agent 验证。
3. 审查 Agent 审查。
4. 验收 Agent 放行。

放行标准：

- 阻塞项必须修复。
- 阻塞项和用户反馈 bug 不能由主控 Agent 亲自修复。
- 小范围 bug 交给 Bugfix Agent。
- 原模块核心逻辑缺陷退回原开发 Agent。
- 架构问题交给架构守门 Agent 和原开发 Agent。
- 产品规则冲突交给产品规则 Agent，并向用户确认。
- 非阻塞项可记录后放行，但必须生成优化任务卡，由下一迭代处理。
- 自动检查已执行，或明确说明无法执行的原因。
- 手动测试项已列出。
- 开发日志已更新。
- 主控 Agent 明确给出进入下一阶段建议。

V2 测试计划 Agent 介入规则：

- 每个阶段开始前，主控 Agent 应优先调用 V2 测试计划 Agent 检查 `docs/V2_TEST_PLAN.md` 是否覆盖当前阶段。
- 如果测试计划缺少当前阶段门禁，先由 V2 测试计划 Agent 补齐计划，再调用测试 Agent 执行。
- 测试失败或用户反馈 bug 后，V2 测试计划 Agent 负责补充回归范围；Bugfix Agent 或原开发 Agent 负责修复。
- 阶段结束前，验收 Agent 应参考 V2 测试计划 Agent 输出的测试 / 验收矩阵。

## 15. Bug 反馈和修复流程

用户在主控 Agent 中反馈 bug 后，必须按以下流程处理：

1. 主控 Agent 记录用户反馈。
2. 主控 Agent 读取 `docs/V2_FEEDBACK_AND_GUARDS.md` 和 `docs/V2_AGENT_RUNBOOK.md`，查找历史反馈、类似 bug 和相关功能守卫。
3. 主控 Agent 尝试复现或要求补充复现信息。
4. 主控 Agent 归类：小 bug、原模块逻辑缺陷、架构问题、产品规则冲突、测试缺口、文档不一致或红线风险。
5. 主控 Agent 生成 bug 修复任务卡，并写明关联历史反馈、关联功能守卫、受影响功能和不得回归项。
6. 主控 Agent 按分诊结果调度 Bugfix Agent、原开发 Agent、架构守门 Agent、产品规则 Agent、测试 Agent 或文档 / 日志 Agent。
7. 修复完成后，测试 Agent 回归原失败路径和关联功能守卫。
8. 审查 Agent 复查修复影响，重点检查是否破坏其他已确认功能。
9. 验收 Agent 确认 bug 是否关闭。
10. V2 测试计划 Agent 判断是否需要把回归项沉淀到 `docs/V2_TEST_PLAN.md`。
11. 主控 Agent 汇总结果，并更新 `docs/V2_AGENT_RUNBOOK.md`、`docs/V2_FEEDBACK_AND_GUARDS.md` 和当天开发日志。

Bug 修复任务卡模板：

```text
Bug 任务卡 ID：
来源阶段：
反馈来源：
问题描述：
复现步骤：
期望结果：
实际结果：
风险等级：
归类：
负责 Agent：
允许修改：
禁止修改：
回归要求：
完成标准：
是否涉及红线：
关联历史反馈：
关联功能守卫：
受影响功能：
不得回归项：
```

分诊规则：

| 问题类型 | 负责 Agent |
| --- | --- |
| 小范围 bug、边界条件、小交互、小编译错误 | Bugfix Agent |
| 原模块核心逻辑缺陷 | 原开发 Agent |
| 架构、schema、Repository、性能问题 | 架构守门 Agent + 原开发 Agent |
| 产品规则冲突 | 产品规则 Agent + 用户确认 |
| 测试缺口 | 测试 Agent |
| 文档不一致 | 文档 / 日志 Agent |
| 红线风险 | 主控 Agent 先向用户确认 |

## 16. 用户反馈记忆和功能守卫

为避免修复一个 bug 时破坏其他已确认功能，第二版使用持久化功能守卫，而不是依赖会话记忆。

主控 Agent 必须维护：

- `docs/V2_AGENT_RUNBOOK.md`：记录完整 bug 反馈、修复、回归、审查和验收过程。
- `docs/V2_FEEDBACK_AND_GUARDS.md`：记录用户反馈摘要、新增功能守卫、不得回归项和最小回归测试。
- `docs/V2_TEST_PLAN.md`：由 V2 测试计划 Agent 沉淀高风险或高频回归门禁。

每次 bug 修复任务卡必须包含：

- 原 bug 复现路径。
- 关联历史反馈。
- 关联功能守卫。
- 受影响功能。
- 不得回归项。
- 最小回归测试。

每次新增功能完成后，主控 Agent 必须判断是否新增守卫：

- 用户明确确认过的体验或行为，需要新增守卫。
- 影响主窗口、数据层、搜索、分组、备份、删除、导入导出、窗口层级的能力，默认需要守卫。
- 一次性文案或低风险视觉微调可不新增守卫，但必须在阶段报告中说明。

## 17. 阶段 1 初始调度剧本

当用户发起“开始开发第二版”后，阶段 1 SQLite 基础和迁移验证第一批调用：

1. V2 测试计划 Agent。
2. 测试 Agent。
3. 数据层开发 Agent。
4. 架构守门 Agent。
5. 审查 Agent。
6. 验收 Agent。

阶段 1 的 UI Agent 可并行工作，但必须锁定接口契约：

- 允许做迁移进度和设置页迁移结果 UI。
- 必须等数据层接口契约确认后再接真实数据。
- 涉及 `SettingsView.swift` 写入前需要主控 Agent 发放文件锁。

## 18. Demo / 演练

协作规约完善后，允许先做阶段性 Demo 或测试闭环，验证协作规约和 Agent 执行流程是否合理。

Demo 限制：

- 不写业务代码。
- 不执行红线操作。
- 使用模拟任务卡、模拟交付和模拟验收。
- 结果记录到 `docs/V2_AGENT_RUNBOOK.md`。

## 19. 当前待命状态

在用户发起“开始开发第二版”之前：

- 不调用开发 Agent。
- 不实现 SQLite。
- 不修改业务代码。
- 只允许继续完善方案、协作规约、技能卡、测试计划、调度记录和日志。
