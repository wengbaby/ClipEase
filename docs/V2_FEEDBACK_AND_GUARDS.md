# 第二版用户反馈和功能守卫清单

本文用于长期记录用户反馈过的问题、新增功能、已确认行为和不得回归的守卫项。

主控 Agent 在处理任何 bug、返工或阶段切片前，必须先读取本文，并把相关守卫项写入任务卡的“回归要求”和“禁止修改”。

## 1. 使用规则

- 用户每次反馈 bug 后，主控 Agent 必须把问题摘要、影响范围、修复任务卡和回归要求记录到本文或 `docs/V2_AGENT_RUNBOOK.md`。
- Bug 修复任务卡必须包含关联历史反馈、关联功能守卫、受影响功能、不得回归项和最小回归测试。
- 每次新增功能完成后，主控 Agent 必须判断是否需要新增功能守卫，避免后续修 bug 时破坏该功能。
- Bugfix Agent 或原开发 Agent 修复 bug 前，必须查看相关守卫项。
- 测试 Agent 回归时，必须覆盖本次 bug 的原失败路径和相关功能守卫。
- V2 测试计划 Agent 应把高频或高风险守卫沉淀到 `docs/V2_TEST_PLAN.md`。

## 2. Bug 记忆模板

```text
Bug ID：
反馈时间：
来源阶段：
用户反馈：
复现路径：
影响范围：
根因摘要：
修复任务卡：
负责 Agent：
回归要求：
关联守卫：
受影响功能：
不得回归项：
最小回归测试：
状态：
```

## 3. 功能守卫模板

```text
守卫 ID：
功能名称：
来源阶段：
已确认行为：
涉及文件 / 模块：
不得回归：
最小回归测试：
关联测试计划：
状态：
```

## 4. 当前基线守卫

### GUARD-V2-BASELINE-001：SQLite-only 运行时基线

- 来源阶段：第二版 SQLite 主存储收口。
- 已确认行为：SQLite-only 是唯一运行时数据基线。
- 不得回归：
  - 不得恢复 JSON Repository。
  - 不得恢复 JSON 到 SQLite 迁移运行时路径。
  - 不得把 JSON 作为运行时主存储或 fallback。
- 最小回归测试：
  - 启动、记录、搜索、预览、粘贴均走 SQLite 当前路径。
  - smoke check 不应要求 JSON 运行时路径存在。

### GUARD-V2-BASELINE-002：收藏 / 管理模式移除基线

- 来源阶段：第二版 SQLite-only / no favorite / no management 新基线。
- 已确认行为：收藏、管理模式、多选和批量操作已移除，不得恢复。
- 不得回归：
  - 不得恢复收藏字段、收藏 UI、收藏快捷键。
  - 不得恢复管理模式入口、多选状态或批量操作。
  - 不得在修复主窗口、搜索、分组或卡片 bug 时引入旧收藏 / 管理模式代码。
- 最小回归测试：
  - 主窗口无收藏入口。
  - 卡片无收藏星标和多选框。
  - 菜单无收藏 / 批量管理入口。

### GUARD-V2-GROUP-001：分组能力保留

- 来源阶段：第二版分组基础。
- 已确认行为：分组、置顶、搜索、备份导入安全和主窗口单条操作继续保留。
- 不得回归：
  - 分组展示、选择、新建、重命名和删除入口不得被 bug 修复误删。
  - 置顶系统分组和用户分组的选择逻辑不得被搜索或主窗口修复破坏。
  - 分组相关备份导入安全边界不得降低。
- 最小回归测试：
  - 切换分组后列表正确过滤。
  - 新建 / 重命名 / 删除分组基础路径可用。
  - 修复搜索或窗口焦点 bug 后仍能保持分组选择。

### GUARD-V2-SEARCH-001：搜索筛选交互守卫

- 来源阶段：第二版搜索 / 筛选。
- 已确认行为：搜索框、筛选 token、筛选 popover 和主窗口关闭行为必须保持一致。
- 不得回归：
  - 点击 App 自身 popover / 面板窗口不得关闭主窗口。
  - Esc 层级不得绕过搜索 / 筛选状态直接关闭主窗口。
  - token 删除、清空和焦点行为不得因修复分组或窗口点击问题被破坏。
  - 搜索框展开且无内容时，点击搜索框外部区域应关闭搜索框。
  - 搜索框展开且有内容时，点击普通外部区域不得关闭搜索框，也不得清空内容。
  - 搜索框展开且有内容时，点击其他分组应关闭搜索框并清空内容。
- 最小回归测试：
  - 打开筛选 popover 后点击 popover 内容，主窗口不关闭。
  - 有 token 无文字时 Backspace 先选中再删除最后一个 token。
  - 清空搜索后焦点和主窗口状态符合测试计划。
  - 分别覆盖无内容外点、有内容外点、有内容点击分组三条搜索收起路径。

### GUARD-V2-UI-001：顶部轨道和分组滚动守卫

- 来源阶段：第二版主窗口顶部轨道返工。
- 已确认行为：顶部搜索 / 筛选 / 分组 / 新建分组位于同一横向轨道；内容不足居中，内容超出后可横向滚动。
- 不得回归：
  - 不得恢复独立置顶 / 收藏圆形图标按钮。
  - 不得把分组截断到固定前几个或强制塞入更多菜单。
  - 顶部分组滚动不得污染卡片横向滚动记忆。
- 最小回归测试：
  - 分组较少时顶部轨道居中。
  - 分组较多时横向滚动可用。
  - 关闭重开后最后选中分组保持或按规则回退。

## 5. 待补充反馈记录

### BUG-V2-MAINT7-HISTORY-LINK-FILE-CARD-20260515

Bug ID：BUG-V2-MAINT7-HISTORY-LINK-FILE-CARD-20260515
反馈时间：2026-05-15
来源阶段：维修阶段 / 第七轮运行态反馈
用户反馈：
- 搜索框展开且无内容时，点击搜索框内部会关闭搜索框。
- 主窗口左右两侧半露卡片点击未按方向平移，未完整露出选中卡片和下一张约 1/6。
- 新卡片加入后只选中但未强制滚动到新卡片目标视口。
- 链接卡片捕获后未立即后台获取标题。
- 链接卡片标题和 URL 间距过大。
- 复制 README.md 等普通文件不会记录文件卡片。
- 文本卡片内容未充分占满区域，底部淡化和超出省略表现不符合参考图。
- 图片卡片未按图片比例尽量占满图片区域。
复现路径：
- 展开空搜索框后点击搜索框内部。
- 横向滚动主窗口，让左右两侧出现半露卡片后点击半露卡片。
- 横向滚动到较后卡片后复制新内容，观察新卡片选中和滚动定位。
- 复制链接后观察链接卡片标题是否无需编辑保存即可后台获取。
- 复制 README.md 文件后观察是否生成文件卡片。
- 对照用户参考图检查链接、文本、图片卡片布局。
影响范围：
- HistoryWindow 搜索命中、横向滚动和新卡片定位。
- ClipboardMonitor 链接和文件捕获。
- LinkTitleFetcher / 链接 metadata 更新路径。
- HistoryCardView 链接、文本、图片卡片布局。
根因摘要：待执行 Agent 返回。
修复任务卡：
- V2-COREUI-MAINT7-HISTORY-RUNTIME-INTERACTION-001
- V2-CORECAPTURE-MAINT7-LINK-FILE-CAPTURE-001
- V2-UICARD-MAINT7-CARD-VISUAL-LAYOUT-001
负责 Agent：
- UI Interaction / 原开发 Agent
- Clipboard / Link Capture 原开发 Agent + Architecture Gatekeeper 复核
- UI Card Layout Bugfix Agent
回归要求：
- 测试 Agent 必须回归原失败路径 1-8。
- 1-3 若再次失败，升级为 HistoryWindow 运行态测试架构缺陷分析，不再继续局部补丁。
关联守卫：
- GUARD-V2-BASELINE-001
- GUARD-V2-BASELINE-002
- GUARD-V2-GROUP-001
- GUARD-V2-SEARCH-001
- GUARD-V2-UI-001
受影响功能：
- 搜索框展开 / 内外部点击。
- 主窗口卡片横向滚动、半露卡片 reveal、新卡片定位。
- 链接卡片捕获、标题抓取和展示。
- 文件卡片捕获，尤其普通文件 README.md。
- 文本、链接、图片卡片视觉布局。
不得回归项：
- 不得恢复收藏、管理模式、多选、批量操作或 JSON 迁移运行时路径。
- 不得修改版本号、构建脚本或发布流程。
- 不得修改 SQLite schema / Repository / 备份格式，除非升级红线任务。
- 文件捕获修复不得删除、移动、复制或写入原文件。
- 搜索有内容时普通外点不得关闭或清空；点击其他分组仍应关闭并清空。
- 分组、置顶、文件卡片、Quick Look、文件 pasteboard fallback 不得回退。
最小回归测试：
- swift build
- git diff --check
- python3 scripts/verify_history_window_interaction_toast.py
- python3 scripts/verify_history_card_scroll_alignment.py
- python3 scripts/verify_no_management_no_favorite_ui.py
- python3 scripts/verify_stage9_file_capture_first_batch.py
- python3 scripts/verify_stage9_file_pasteboard_first_batch.py
- python3 scripts/verify_stage9_file_card_ui.py 或等价卡片布局守卫
状态：调度中。

### BUG-V2-MAINT8-HISTORY-FILE-GROUP-RICHTEXT-20260516

Bug ID：BUG-V2-MAINT8-HISTORY-FILE-GROUP-RICHTEXT-20260516
反馈时间：2026-05-16
来源阶段：维修阶段 / 第八轮运行态反馈
用户反馈：
- 链接卡片内容区不要显示 URL 标题和 URL 地址；底部 URL 上方加粗显示 URL 标题。
- 半露卡片点击方向平移并露出下一张约 1/6 仍未解决。
- 不管当前横向滚到哪里，复制新内容后新卡片应被选中并滚回目标位置。
- 复制单个文件经常没有加入新卡片。
- 文本卡片内容仍未占满，底部有较大间隙。
- 普通文本中复制多行文件路径时应记录为文本卡片，不应显示为多个文件卡片。
- 分组右键点击应和左键点击一样进入选中状态。
- 富文本复制后，文本卡片内容区应显示带格式富文本，不应统一普通字体。
复现路径：
- 对链接、长文本、富文本、单文件、多文件路径文本、分组右键、半露卡片和新卡片定位做运行态验证。
影响范围：
- HistoryWindow 横向滚动和新卡片定位。
- ClipboardMonitor 文件 pasteboard 语义判定。
- HistoryCardView 链接 / 文本 / 富文本渲染。
- 分组按钮右键交互。
根因摘要：待执行 Agent 返回。
修复任务卡：
- V2-COREUI-MAINT8-HISTORY-RUNTIME-SCROLL-ARCH-001
- V2-CORECAPTURE-MAINT8-FILE-PASTEBOARD-SEMANTICS-001
- V2-UICARD-MAINT8-LINK-TEXT-RICHTEXT-LAYOUT-001
- V2-UI-MAINT8-GROUP-RIGHTCLICK-SELECTION-001
负责 Agent：
- HistoryWindow Core Interaction / 原开发 Agent
- Clipboard Capture 原开发 Agent + Architecture Gatekeeper 复核
- UI Card / Rich Text 原开发 Agent
- UI Interaction Agent
回归要求：
- 测试 Agent 必须回归本轮 8 项原失败路径。
- 半露卡片 reveal 和新卡片定位若再次失败，升级为 HistoryWindow 滚动架构重做 / 运行态自动化缺口专项。
关联守卫：
- GUARD-V2-BASELINE-001
- GUARD-V2-BASELINE-002
- GUARD-V2-GROUP-001
- GUARD-V2-SEARCH-001
- GUARD-V2-UI-001
- BUG-V2-MAINT7-HISTORY-LINK-FILE-CARD-20260515
受影响功能：
- 半露卡片 reveal、新卡片定位、分组右键选择、文件捕获、文本路径捕获、链接 / 文本 / 富文本卡片展示。
不得回归项：
- 不得恢复收藏、管理模式、多选、批量操作或 JSON 迁移运行时路径。
- 不得修改版本号、构建脚本或发布流程。
- 不得修改 SQLite schema / Repository / 备份格式，除非升级红线任务。
- Finder / 系统文件语义复制单文件必须生成文件卡片；普通文本中的路径必须保留为文本卡片。
- 文件捕获修复不得删除、移动、复制或写入原文件。
- 搜索有内容时普通外点不得关闭或清空；点击其他分组仍应关闭并清空。
最小回归测试：
- swift build
- git diff --check
- python3 scripts/smoke_check.py
- python3 scripts/verify_history_window_interaction_toast.py
- python3 scripts/verify_history_card_scroll_alignment.py
- python3 scripts/verify_no_management_no_favorite_ui.py
- python3 scripts/verify_stage9_file_capture_first_batch.py
- python3 scripts/verify_stage9_file_pasteboard_first_batch.py
- python3 scripts/verify_stage9_file_card_ui.py
- python3 scripts/verify_link_title_background_fetch.py
- python3 scripts/verify_maint7_card_visual_layout.py
- 第八轮新增专项守卫脚本
状态：调度中。

后续用户反馈 bug 时从这里追加，或在 `docs/V2_AGENT_RUNBOOK.md` 记录详细过程后，在本文添加对应守卫摘要。
