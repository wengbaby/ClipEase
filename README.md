# 轻贴 ClipEase

轻贴是一款 macOS 菜单栏剪贴板历史工具，副标题为“简洁好用的 macOS 粘贴板历史助手”。

当前项目处于第一版 RC 稳定性收尾阶段。实施前请先阅读 [docs/PROJECT_GUIDE.md](./docs/PROJECT_GUIDE.md)，并按文档中的开发顺序推进。

第二版已进入方案头脑风暴阶段，当前只整理和确认方案，不实施功能代码。

## 当前功能

- 菜单栏常驻和底部横向历史窗口
- 文字、图片、链接、颜色记录
- 搜索、筛选、置顶、删除、预览
- 双击、回车、`Command + 1-9` 粘贴
- 新建富文本、暂停记录、忽略 App
- 设置页、快捷键、保存期限、开机启动
- 历史导入导出、备份包、数据健康检查和清理

第一版发布前按 [第一版回归测试清单](./docs/FIRST_VERSION_TEST_CHECKLIST.md) 逐项验收。

发布资料：

- [第一版发布说明](./docs/RELEASE_NOTES.md)
- [发布候选流程](./docs/RELEASE_CANDIDATE_PROCESS.md)
- [发布候选报告](./docs/RELEASE_CANDIDATE_REPORT.md)
- [已知限制](./docs/KNOWN_ISSUES.md)
- [第二版产品方案](./docs/V2_PRODUCT_PLAN.md)
- [第二版技术方案草案](./docs/V2_TECHNICAL_PLAN.md)
- [第二版开发计划草案](./docs/V2_DEVELOPMENT_PLAN.md)
- [第二版 Agent 协作规约](./docs/V2_AGENT_COLLABORATION.md)
- [第二版 Agent 技能卡](./docs/agents/README.md)
- [第二版用户反馈和功能守卫](./docs/V2_FEEDBACK_AND_GUARDS.md)
- [第二版 Agent 调度 Runbook](./docs/V2_AGENT_RUNBOOK.md)
- [第二版优化 Backlog](./docs/V2_OPTIMIZATION_BACKLOG.md)

第二版 Agent 快速导航：

| Agent | 状态 | 技能卡 | 摘要 |
| --- | --- | --- | --- |
| 主控 Agent | 长期保留 | [main-controller-agent.md](./docs/agents/main-controller-agent.md) | 调度、汇总、否决、返工和阶段放行；不写业务代码 |
| 数据层开发 Agent | 长期保留 | [data-layer-agent.md](./docs/agents/data-layer-agent.md) | SQLite、迁移、Repository、备份底层和数据健康 |
| UI / 交互开发 Agent | 长期保留 | [ui-interaction-agent.md](./docs/agents/ui-interaction-agent.md) | 主窗口、搜索筛选、设置页、快捷键、提示层 |
| 功能增强开发 Agent | 长期保留 | [feature-enhancement-agent.md](./docs/agents/feature-enhancement-agent.md) | 文件卡片、Quick Look、富文本、敏感遮罩和编辑 |
| Bugfix Agent | 长期保留 | [bugfix-agent.md](./docs/agents/bugfix-agent.md) | 阶段门禁失败、用户反馈 bug、测试失败和小范围回归修复 |
| V2 测试计划 Agent | 长期保留 | [v2-test-plan-agent.md](./docs/agents/v2-test-plan-agent.md) | 维护第二版测试 / 验收计划，按阶段补齐门禁 |
| 测试 Agent | 长期保留 | [test-agent.md](./docs/agents/test-agent.md) | 测试清单、样本、自动检查和手动验收项 |
| 审查 Agent | 长期保留 | [review-agent.md](./docs/agents/review-agent.md) | 数据安全、架构、UI 和测试覆盖审查 |
| 验收 Agent | 长期保留 | [acceptance-agent.md](./docs/agents/acceptance-agent.md) | 对照阶段完成标准判断是否放行 |
| 产品规则 Agent | 长期保留 | [product-rules-agent.md](./docs/agents/product-rules-agent.md) | 检查产品规则、交互规则、文案和边界行为 |
| 架构守门 Agent | 长期保留 | [architecture-gatekeeper-agent.md](./docs/agents/architecture-gatekeeper-agent.md) | 检查技术方案、模块边界、性能和扩展性 |
| 用户体验 Agent | 长期保留 | [ux-agent.md](./docs/agents/ux-agent.md) | 检查复杂交互、焦点、快捷键、窗口层级和空状态 |
| 文档 / 日志 Agent | 长期保留 | [docs-log-agent.md](./docs/agents/docs-log-agent.md) | 整合文档、日志、调度记录和优化 backlog |
| 专项开发 Agent | 按阶段创建 | [specialist-dev-agent.md](./docs/agents/specialist-dev-agent.md) | 处理明确、边界较窄的阶段开发切片 |

本地打包并启动：

```bash
scripts/build-app.sh --run
```

发布前基础检查：

```bash
scripts/smoke_check.py
```
