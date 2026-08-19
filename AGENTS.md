# ClipEase 协作规则（最高优先级，所有 AI 必读）

> 本节是项目维护者 wengbaby 的硬性约束，优先级高于下方 Trellis / CodeGraph 块。
> Trellis 管"开发流程/任务/spec"，CodeGraph 管"代码符号图谱"，本节管"项目级铁律 + 文档纪律"。
> 三者**独立并存**，互不覆盖：Trellis 的 `.trellis/`、CodeGraph 的 `.codegraph/`、本节的 `docs/` 各自独立。

## 0. 做任何事之前：先读文档索引

**任何任务开始前，必须先打开 `./docs/INDEX.md` 检查是否已有相关文档。**
- 修 bug、做需求、执行计划、重构……无论什么事，先查索引，看有没有干过的或相关的事。
- 索引里没有的，做完后必须新建文档并登记到索引。
- 这条规则用来对抗 AI 幻觉：用文档沉淀事实，而不是靠记忆。

## 1. 硬性条件一：模块化

项目必须模块化，代码必须模块化。三条铁律：
1. **独立目录**：每个功能/模块有自己独立目录，不混在一个巨型文件里。
2. **接口通信**：模块之间通过明确接口通信，不直接越界访问内部实现。
3. **功能归位**：每个功能归位到对应模块，不散落各处。

> 当前已知违反点：`Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift` 有 8353 行，
> 是巨型 View 文件，是搜索卡顿 bug 的根因之一。后续重构必须拆分。

## 2. 硬性条件二：文档纪律

**每做一件事都要整理出文档**——包括改 bug、做需求、执行计划，无一例外。

- **位置**：统一放在 `./docs/ai/` 下，按情况新建子文件夹分类。
- **命名**：`YYYY-MM-DD-HHmmss-简短中文概括.md`（例：`2026-08-19-204700-搜索卡顿修复方案.md`）。
- **语言**：中文，让人能看懂，不要英文。
- **内容**：至少包含——文档日期、状态（草稿/进行中/已完成/归档）、约束对齐、关联记叙、目标。
  开发文档还要写明：问题现象、根因、改动点、验证方式、影响范围。
- **索引**：每份文档都要在 `./docs/INDEX.md` 里登记一行（路径 + 一句话概括 + 状态）。
- **目的**：详细记录，让下一个 AI（或人）能快速判断问题、不重复造轮子、不出现幻觉。

## 3. 与 Trellis、CodeGraph 的关系

| 工具 | 管什么 | 数据目录 | 本节是否覆盖 |
| --- | --- | --- | --- |
| 本 AGENTS.md 第 0/1/2 节 | 项目铁律 + 文档纪律 | `docs/` | — |
| Trellis | 开发流程/阶段/任务/spec | `.trellis/` | 不覆盖，并存 |
| CodeGraph | 代码符号/调用链图谱 | `.codegraph/` | 不覆盖，并存 |
| Serena | LSP 代码理解/符号操作 | `.serena/` | 不覆盖，并存 |
| Graphify | 知识图谱（可选） | `graphify-out/` | 不覆盖，并存 |

三者**必须独立并存**：不要因为用了 Trellis 就跳过 `docs/` 文档；不要因为用了 CodeGraph 就跳过文档纪律。

---

## CodeGraph 使用规则

在阅读、修改、重构已有代码前，必须优先使用 CodeGraph MCP 工具理解项目结构、相关符号、调用路径和影响范围。

优先调用 `codegraph_explore`。不要一开始就用 grep/read 盲目搜索。只有在 CodeGraph 未初始化、结果为空、目标是非源码文件、配置文件或文档文件时，才回退到普通文件读取。

修改代码前，需要先说明：
1. 当前相关入口文件；
2. 关键调用链；
3. 预计影响范围；
4. 准备修改哪些文件。
<!-- TRELLIS:START -->
# Trellis Instructions

These instructions are for AI assistants working in this project.

This project is managed by Trellis. The working knowledge you need lives under `.trellis/`:

- `.trellis/workflow.md` — development phases, when to create tasks, skill routing
- `.trellis/spec/` — package- and layer-scoped coding guidelines (read before writing code in a given layer)
- `.trellis/workspace/` — per-developer journals and session traces
- `.trellis/tasks/` — active and archived tasks (PRDs, research, jsonl context)

If a Trellis command is available on your platform (e.g. `/trellis:finish-work`, `/trellis:continue`), prefer it over manual steps. Not every platform exposes every command.

If you're using Codex or another agent-capable tool, additional project-scoped helpers may live in:
- `.agents/skills/` — reusable Trellis skills
- `.codex/agents/` — optional custom subagents

Managed by Trellis. Edits outside this block are preserved; edits inside may be overwritten by a future `trellis update`.

<!-- TRELLIS:END -->
