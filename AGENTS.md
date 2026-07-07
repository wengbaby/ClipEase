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
