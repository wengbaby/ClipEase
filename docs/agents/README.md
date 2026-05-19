# 第二版 Agent 技能卡总览

本文是第二版多 Agent 协作的快速导航。完整调度规则见 `docs/V2_AGENT_COLLABORATION.md`。

当前状态：待命。用户在主控 Agent 中明确发起“开始开发第二版”前，不调用开发 Agent，不编写功能代码。

## Agent 状态表

| Agent | 技能卡 | 状态 | 主要职责 | 默认风险关注 |
| --- | --- | --- | --- | --- |
| 主控 Agent | `main-controller-agent.md` | 长期保留 | 调度、汇总、否决、返工、阶段放行 | 阶段失控、任务越界、未验证放行 |
| 数据层开发 Agent | `data-layer-agent.md` | 长期保留 | SQLite、迁移、Repository、备份底层 | 数据丢失、附件误删、迁移失败 |
| UI / 交互开发 Agent | `ui-interaction-agent.md` | 长期保留 | 主窗口、搜索、设置页、快捷键、提示层 | 焦点冲突、状态不一致、主线程卡顿 |
| 功能增强开发 Agent | `feature-enhancement-agent.md` | 长期保留 | 文件卡片、Quick Look、富文本、敏感遮罩、编辑 | 路径失效、权限、格式破坏、验证失败 |
| Bugfix Agent | `bugfix-agent.md` | 长期保留 | 阶段门禁失败、用户反馈 bug、测试失败和小范围回归修复 | 修复范围扩大、跳过回归、触碰红线 |
| V2 测试计划 Agent | `v2-test-plan-agent.md` | 长期保留 | 维护 `docs/V2_TEST_PLAN.md`，按阶段补齐测试 / 验收门禁 | 测试计划落后、漏掉回归、未覆盖红线 |
| 测试 Agent | `test-agent.md` | 长期保留 | 测试清单、样本、自动检查、手动项 | 漏测、样本不足、结论不可复现 |
| 审查 Agent | `review-agent.md` | 长期保留 | 数据安全审查、架构审查、UI 审查、测试覆盖审查 | 阻塞问题漏判、无关重构建议 |
| 验收 Agent | `acceptance-agent.md` | 长期保留 | 对照完成标准放行阶段 | 把未验证项误判为通过 |
| 产品规则 Agent | `product-rules-agent.md` | 长期保留 | 检查产品规则、交互规则、文案和边界行为 | 偏离已确认产品规则 |
| 架构守门 Agent | `architecture-gatekeeper-agent.md` | 长期保留 | 技术方案、模块边界、性能、扩展性 | 不合理架构、隐性耦合 |
| 用户体验 Agent | `ux-agent.md` | 长期保留 | 交互方案、焦点、快捷键、窗口层级、空状态 | 可用性退化、体验不一致 |
| 文档 / 日志 Agent | `docs-log-agent.md` | 长期保留 | 文档整合、日志、调度记录、格式统一 | 文档与事实不一致 |
| 专项开发 Agent | `specialist-dev-agent.md` | 按阶段创建 | 阶段专项切片开发 | 范围蔓延、上下文不足 |

## 使用规则

- 主控 Agent 调用其他 Agent 前，必须按风险等级决定任务卡完整度。
- 高风险核心模块串行执行，低风险模块允许并行。
- 高风险文件同一时间只能有一个写入者，锁状态记录到调度日志。
- Agent 之间可以直接沟通，但必须记录问题、回答、结论和影响，并回报主控 Agent。
- 开发 Agent 可以修改与任务直接相关的文档片段；文档 / 日志 Agent 负责全局整合与格式统一。
- 用户在主控 Agent 反馈 bug 后，主控 Agent 只负责复现、归类、定级和调度；修复由 Bugfix Agent 或原开发 Agent 执行。
- `docs/V2_TEST_PLAN.md` 的阶段性维护优先交给 V2 测试计划 Agent；具体测试执行仍交给测试 Agent。
