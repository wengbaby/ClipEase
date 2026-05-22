# 第二版 RC 检查报告

## 当前结论

轻贴 ClipEase 第二版已正式切到 `2.x` 版本线。此前 V2 开发和验收包曾沿用 `1.0.x` patch 线推进，现已按项目规则完成大版本开发 `+1` 收口：`2.0.0(260519.2258)` 为 V2 大版本切线包；当前收口包为 `2.3.2(260523.0437)`。

当前结论：第二版大部分核心功能已完成并进入发布候选冻结。当前 RC 已纳入 SQLite-only 新基线、无收藏、无管理模式、备份导入安全修复、加入分组 picker、历史卡片 selection / focus / right-click / border 修复、Stage 8 主窗口体验收口、Stage 9 文件卡片 / Quick Look / 文件引用 pasteboard / 基础操作 / 拖出 / 粘贴 fallback，以及 2026-05-18 至 2026-05-19 的颜色与图标、分组重命名、App 图标和默认色板收口。用户已确认最终发布前人工 UI 验收项通过，包括颜色与图标入口、Finder / Dock 图标缓存刷新、搜索展开 / 收起、授权提示和 ESC 关闭顺序；当前也已移除主窗口更多菜单中的“开发测试”入口，并完成帮助文案与设置页保存期限选中态 polish。冻结后不再新增 V2 功能，只接受阻塞 bug、崩溃和发布包风险修复。

## 自动检查

- `swift build`：通过；Stage 9 `.file` 最小编译 fallback 后已恢复通过
- `scripts/smoke_check.py`：通过，已对齐 `2.3.2(260523.0437)`
- `python3 scripts/benchmark_history_search_performance.py`：PASS，1k / 10k 混合历史样本、中文查询、类型 / 来源过滤、分组排序和 10k source signature 构造均在阈值内
- `python3 scripts/verify_help_and_retention_polish.py`：PASS，帮助文案保持简洁，设置页保存期限选中态为统一蓝色背景
- `python3 scripts/verify_no_visible_debug_menu.py`：PASS，主窗口更多菜单不再暴露“开发测试”，设置页隐藏性能测试数据入口保留
- `python3 scripts/verify_history_search_performance_guards.py`：PASS
- `python3 scripts/verify_preview_copy_feedback.py`：PASS
- `python3 scripts/verify_stage9_file_paste_fallback.py`：PASS
- `python3 scripts/verify_stage9_file_pasteboard_first_batch.py`：PASS
- `python3 scripts/verify_stage9_file_capture_first_batch.py`：PASS
- `python3 scripts/verify_stage9_file_basic_actions.py`：PASS
- `python3 scripts/verify_stage9_file_dragout_first_batch.py`：PASS
- `python3 scripts/final_release_gate.py`：PASS，基于当前 `.build/ClipEase.app` 执行最终发布门禁，不重新编译、不递增版本；已覆盖 smoke、发布文档、帮助 / 设置、调试菜单、搜索性能、卡片点击 / 拖拽、预览、音效、Stage 9 文件卡片和 `git diff --check`
- `./scripts/build-dmg.sh`：PASS，已生成 `dist/ClipEase-2.3.2-260523.0437.dmg`，SHA-256 `e1f773a68ded47ced6f5d0d834f3f0f374a2e13c470b199da750d6aa2e29e245`
- DMG 挂载结构验收：PASS，根目录包含 `ClipEase.app` 和 `Applications` 快捷入口，`ClipEase.app` 版本为 `2.3.2 (260523.0437)`，可执行文件存在且有执行权限
- DMG 内 App 启动验收：PASS，从只读挂载卷启动 `ClipEase.app --show-settings`，进程正常存活，System Events 可见进程 `ClipEase` 和 1 个设置窗口；验收后已关闭 release App、卸载 DMG，并恢复开发包运行
- `scripts/build-app.sh --bump patch --run`：通过；当前运行包为 `2.3.2 (260523.0437)`，App bundle 启动方式已由 `scripts/build-app.sh --run` 固化；当前恢复运行 PID `27313`
- GitHub 推送：待最终确认后执行

## 手动回归

已确认：

- 用户已确认最终发布前人工 UI 验收无问题。
- `V2-OPT-UI-GROUP-APPEARANCE-POPOVER-MANUAL-ACCEPTANCE-001`：已通过，不再阻塞最终发布。
- `V2-OPT-UI-SEARCH-AUTH-ESC-MANUAL-ACCEPTANCE-001`：已通过，不再阻塞最终发布。
- DMG 结构、版本、启动和设置窗口可见性已完成自动 / 半自动验收。
- 后续只在发现阻塞 bug 时重新进入 patch 修复轮。

## 阻塞问题

- 已修复：主窗口关闭后再次打开不应回到初始横向位置。
- 已优化：主窗口显示/隐藏动画减少内容重绘压力。
- 已修复：文字搜索结果命中样式改为黄色背景，并支持多处命中。
- 若用户侧继续发现问题，只修复阻塞 bug，不新增功能。

## RC 包信息

- 当前候选版本：`2.3.2`
- 当前构建号：`260523.0437`
- 当前 build/run：`2.3.2 (260523.0437)`
- 当前运行进程：PID `27313`
- 当前 DMG：`dist/ClipEase-2.3.2-260523.0437.dmg`
- 当前 DMG SHA-256：`e1f773a68ded47ced6f5d0d834f3f0f374a2e13c470b199da750d6aa2e29e245`
- 当前 Git 提交：`55592e2 docs: record v2 dmg validation`
- 当前状态：V2 发布候选冻结；不再新增功能，只接受阻塞 bug、崩溃和发布包风险修复。后续如继续修复阻塞 bug，使用 patch 规则，并在本报告中追加记录。

## RC 修复记录

- `2.3.2(260523.0437)`：V2 发布候选冻结记录对齐。RC 报告已更新到最新提交 `55592e2` 和当前恢复运行 PID `27313`；发布状态改为冻结，不再新增 V2 功能，只接受阻塞 bug、崩溃和发布包风险修复。
- `2.3.2(260523.0437)`：DMG 发布包验收。`hdiutil verify` 通过，DMG 内包含 `ClipEase.app` 和 `Applications` 快捷入口；从 DMG 只读挂载卷启动 App，版本 / 构建号正确，进程正常存活，设置窗口可见。曾尝试用临时 `HOME` 做剪贴板捕获写入验收，但 macOS App 的 Application Support 路径未被该方式隔离，测试文本进入真实历史；已备份真实 SQLite，仅删除精确匹配测试记录 `131202DC-E5F3-4EA1-9F34-F3E7AC5B6CCD`，删除后匹配数为 0，并恢复开发包运行。因此本轮正式验收证据只采用 DMG 结构、版本、启动和窗口可见性。
- `2.3.2(260523.0437)`：第二版发布准备收尾。发布说明和发布候选流程已从第一版口径更新为 V2 口径，明确当前 RC、无 iCloud 同步、文件预览限制、版本规则、最终 gate 和 DMG 打包流程；新增 `scripts/final_release_gate.py`，基于当前已构建 `.app` 执行非编译型最终发布门禁；新增 `scripts/build-dmg.sh`，从当前 `.build/ClipEase.app` 打包 `dist/ClipEase-2.3.2-260523.0437.dmg` 并输出 SHA-256。本轮只改发布文档 / 发布脚本 / 守卫脚本，未改 App 运行代码，未触发新的 build/run。
- `2.3.2(260523.0437)`：发布前帮助与设置页 polish。帮助窗口文案压缩为用户常用操作，去除冗长实现说明；设置页保存期限改为自定义按钮组，当前选中项统一蓝色背景和白色文字；新增 `scripts/verify_help_and_retention_polish.py` 防止帮助文案和保存期限选中态回归。已执行 build/run，当前运行进程为 PID `87202`。
- `2.3.1(260523.0419)`：最终发布前收口清理。移除主窗口更多菜单中的“开发测试”可见入口，保留设置页隐藏性能测试数据入口；新增 `scripts/verify_no_visible_debug_menu.py` 防止可见调试菜单回归。同时收口 V2 backlog 旧阻塞状态：富文本再次编辑标记为已完成 / 不阻塞，搜索 SQLite LIKE / FTS 专项标记为不阻塞最终发布、仅作为后续独立性能专项保留。已执行 build/run，当前运行进程为 PID `76383`。
- `2.3.0(260523.0333)`：搜索性能专项第二阶段。新增 `scripts/benchmark_history_search_performance.py`，用固定 1,000 / 10,000 条混合历史样本量化当前内存过滤路径，覆盖常见查询、中文查询、类型 / 来源过滤、分组排序和 10k source signature 构造；当前结果均低于守卫阈值，未触发 SQLite LIKE / FTS / schema 改造门槛。已执行 build/run，当前运行进程为 PID `54262`。
- `2.2.0(260523.0302)`：搜索性能专项第一阶段。暂不修改 SQLite schema / Repository / 备份格式，先将搜索请求签名从整段 `normalizedSearchText` 改为每条卡片预生成的轻量 `searchFingerprint`，减少快速输入时对全部卡片长搜索文本的签名构造和比较成本；实际搜索匹配仍沿用 `normalizedSearchText.contains`，搜索结果语义不变。搜索性能守卫已覆盖 fingerprint 签名并禁止回退到签名携带整段 normalized search text。已执行 build/run，当前运行进程为 PID `40267`。
- `2.1.0(260523.0213)`：完成预览窗口复制按钮统一反馈体验。预览顶部复制按钮现在与主窗口复制一致，普通复制、文件引用复制、文件路径 fallback 和失败结果都会显示全局 toast；成功和 fallback 保留 Copy 音效，不改变 pasteboard 写入语义。新增 `scripts/verify_preview_copy_feedback.py` 守卫 `.copied`、`.copiedFallbackText`、`.failed` 三种结果。已执行 build/run，当前运行进程为 PID `13396`。
- `2.0.80(260523.0154)`：修复从微信等其他 App 激活场景下，快捷键唤起轻贴、按空格打开预览后，第一次按住预览标题栏只激活轻贴而不能拖动的问题。预览标题栏拖拽热区现在显式接收 inactive window 的 first mouse 事件并返回 `true`，确保第一次按下就能进入拖拽流程。预览守卫已覆盖标题栏 first mouse 接收要求。已执行 build/run，当前运行进程为 PID `98745`。
- `2.0.79(260523.0137)`：修复预览窗口顶部第一次按住拖动只脱离、不移动的问题。拖拽开始时只切换为独立窗口层级、释放附着槽位并立刻关闭主窗口；预览内容重建和倒三角隐藏延后到系统窗口拖动结束后执行，避免 SwiftUI 重建标题栏热区打断第一次系统拖动。预览守卫已覆盖脱离时返回拖动完成回调、拖动期间不重建内容，以及完成后再隐藏倒三角。已执行 build/run，当前运行进程为 PID `85362`。
- `2.0.78(260523.0027)`：独立预览窗口稳定性收口。脱离后的预览窗口初始位置会约束在当前屏幕可见区域内，避免大图、PDF 或文件预览拖出后跑出屏幕边界；独立预览设置 `390x260` 最小尺寸，防止缩到不可操作。附着弹层仍保持原有弹层尺寸策略，不继承独立窗口最小尺寸。预览守卫已覆盖独立预览最小尺寸、附着弹层尺寸复位、脱离初始 frame 可见区域约束和按可见区域交集选择屏幕。已执行 build/run，当前运行进程为 PID `43462`。
- `2.0.77(260522.2306)`：修复脱离预览窗口的 `Esc` 关闭路径。已脱离预览现在有专用本地 Esc 监听，焦点落在 Quick Look、PDF、WebView 或文本内容里时，按 `Esc` 也会关闭当前脱离预览窗口；监听作用域限定到事件窗口或当前 key window 属于已脱离预览窗口，不影响主窗口、附着预览或其他 App 窗口。预览守卫已覆盖脱离预览 Esc monitor 生命周期、关闭行为和作用域。已执行 build/run，当前运行进程为 PID `63474`。
- `2.0.76(260522.2155)`：修复预览窗口脱离后的主窗口生命周期。用户从预览标题栏拖出独立窗口后，主窗口会立刻关闭；已脱离预览继续作为普通 App 窗口保留，不被主窗口关闭流程误关。独立预览自身关闭按钮和该窗口聚焦时 `Esc` 只关闭该独立预览，不再重复触发主窗口关闭回调。预览守卫已覆盖脱离瞬间关闭主窗口，以及独立预览关闭 / `Esc` 不重复执行主窗口脱离回调。已执行 build/run，当前运行进程为 PID `38888`。
- `2.0.75(260522.1727)`：修复预览窗口标题栏过高问题，拖拽热区固定为 22pt 高度并移除重复垂直 padding，恢复原来的紧凑 header。调整预览脱离模型：已脱离预览独立保留，原附着预览槽位立即释放；用户再次预览任意卡片时仍按该卡片原位置弹出新的附着预览，每个卡片都可以继续拖出为独立预览窗口。预览守卫已覆盖 header 高度、多独立预览窗口、脱离后释放附着槽位和下一次预览回到卡片位置。已执行 build/run，当前运行进程为 PID `73546`。
- `2.0.74(260522.0311)`：预览窗口拖拽脱离最终运行包；在 `2.0.73` 基础上补齐标题栏真实拖动阈值，单击标题栏不会触发脱离，开始拖拽前保留原始窗口引用，避免 SwiftUI 重建内容后丢失系统拖动；已脱离预览被复用或按 `Esc` 关闭时会同步清理主窗口预览状态。已重新执行 build/run，当前运行进程为 PID `56099`。
- `2.0.73(260522.0303)`：新增预览窗口标题栏拖拽脱离能力。未拖动时仍保持附着弹层行为，显示下方倒三角、跟随卡片、随主窗口关闭；用户只可从顶部标题 / 来源区域拖拽脱离，内容区继续保留文本选择、复制、PDF / 图片 / 文件预览交互。拖出后预览切换为普通 App 窗口层级，隐藏倒三角，开启系统阴影，可与其他窗口正常切换；主窗口关闭 / 隐藏不会关闭已脱离预览。已脱离预览只能通过自身关闭按钮或该窗口聚焦时按 `Esc` 关闭。预览性能守卫已覆盖标题栏拖拽区域、脱离态窗口层级、倒三角隐藏、主窗口关闭不误关脱离预览和独立关闭路径。
- `2.0.72(260522.0215)`：预览窗口交互反馈优化包；OCR / 关键信息 badge 和文件预览右侧文件列表行接入轻量 hover / press 反馈，badge 使用 capsule 状态层，文件行使用圆角矩形状态层与 `0.992` 按下缩放。文件列表选中态增加 100ms opacity 过渡，切换多文件预览时不再生硬跳变。预览性能守卫已覆盖 badge、文件行按钮反馈和文件行选中态过渡。
- `2.0.71(260522.0207)`：预览窗口动画优化包；预览内容切换现在按 item / 类型 / 文件选择 / ready 状态建立内容身份，使用 140ms opacity + `0.992` scale 的轻量 crossfade，避免图片、链接、文件等重内容从 shell 切换到 ready 时出现生硬跳变。预览 header 的关闭 / 复制按钮、链接打开悬浮按钮和 OCR 识别按钮统一接入轻量 hover / press 反馈，悬停 `1.01`、按下 `0.985`，不动画宽高、不加重阴影。预览性能守卫已覆盖内容切换动画和按钮反馈，并继续守卫重内容延后加载、PDF 后台加载、关闭时卸载重内容。
- `2.0.70(260522.0149)`：修复顶部“搜索”按钮展开后再次点击不会关闭的问题。原因是搜索展开后窗口级外点监听会先把搜索关闭，随后搜索按钮自身点击又触发 `toggleSearch()` 重新打开，表现为二次点击无效。本轮将搜索按钮自身注册为搜索交互区域，避免外点监听抢先处理；同时将搜索按钮的已展开点击语义改为 `clearAndCloseSearch()`，确保再次点击明确清空并收起搜索框。搜索交互守卫已覆盖该回归路径。
- `2.0.69(260522.0131)`：交互动画优化包；顶部轨道按钮统一接入轻量 hover / press 反馈，覆盖全部剪切板、置顶、用户分组、搜索、新建分组、授权提示和更多按钮。反馈统一为 100ms hover、80ms press，只使用 opacity / scale：悬停 `1.01`，按下 `0.985`，并增加极轻白色状态层；不动画宽高、不加重阴影，避免顶部轨道滚动和搜索展开期间产生布局抖动。主窗口动画性能守卫已覆盖统一按钮样式和禁止回退到宽高 / 重阴影动画。
- `2.0.68(260522.0109)`：性能 / 动画优化收口包；主窗口顶部搜索框展开 / 收起不再直接动画宽度。搜索状态拆成布局可见和视觉可见两层，布局尺寸立即稳定，视觉层只做 opacity 和轻微 scale，收起后 120ms 再释放布局空间，避免搜索框动画期间反复挤压顶部轨道、分组按钮和结果计数。主窗口动画性能守卫已覆盖搜索框布局 / 视觉状态、搜索可见任务取消，以及禁止回退到 `isSearchVisible ? 520 : 0` 的宽度动画。
- `2.0.67(260522.0048)`：交互动画优化包；历史卡片新增轻量 hover / press 状态反馈，鼠标悬停时增加极轻白色状态层和 `1.004` 缩放，按下时使用 `0.996` 缩放与更明确的状态层，松开、移出、右键或开始拖拽都会复位。动画保持 80-120ms，仅使用 opacity / scale，不动画宽高或重阴影，避免影响横向滚动性能。卡片点击性能守卫已覆盖 hover / press 回调和 AppKit tracking area。
- `2.0.66(260522.0025)`：性能 / 动画优化收口包；后台资源预热现在复用卡片可见加载的 `HistoryCardAssetLoadGate`，图片缩略图、App 图标和富文本预览预热都走同一 3 并发资源门，避免预热与可见卡片加载同时抢磁盘 IO / 图片解码 / 富文本解析资源。预热仍保持全量 `filteredItems` 分批、低优先级、可取消处理；富文本预热复用 `RichTextCardPreviewCache.loadAttributedString`，避免维护两套解析逻辑。
- `2.0.65(260522.0002)`：性能 / 动画优化收口包；新增卡片定位 / 最新卡片滚动重试从递归创建多条 16ms MainActor 任务，改为单个可取消的 `latestFocusRetryTask` 循环。窗口隐藏或最新卡片定位完成时会取消该任务，避免连续复制、频繁开关窗口或布局未稳定时叠加多条无效滚动重试，降低抖动和主线程小任务压力。卡片点击性能守卫已扩展到该可取消重试路径。
- `2.0.64(260521.2338)`：性能 / 动画优化收口包；主窗口 `onAppear` 只保留必要的状态恢复和最新卡片焦点准备，预览列表重建与权限刷新延后到首帧后执行，减少窗口刚弹出时与 frame 动画抢主线程。后台资源预热延迟从 160ms 调整到 260ms，继续按全量分批、低优先级、可取消方式执行，避免与打开动画和新增卡片定位竞争。主窗口动画守卫已扩展到 deferred startup 和更保守预热延迟。
- `2.0.63(260521.2249)`：修复用户在其他 App 复制内容后轻贴捕获成功但没有 Copy 音效的问题。外部剪贴板捕获成功写入新卡片后会播放 Copy 音效，覆盖文本、富文本、图片和文件卡片；轻贴自身写入剪贴板产生的卡片会被 `item.isFromClipEase` 排除，避免内部复制按钮和外部捕获路径重复播放。音效守卫已扩展到 `ClipboardHistoryStore` 的外部捕获路径。
- `2.0.62(260521.2144)`：修复复制音效不响的问题，复制反馈从 `NSSound` 改为 `AVAudioPlayer` 并提前 `prepareToPlay()`，避免短音效首次播放被系统延迟或资源状态影响。复制路径仍覆盖主窗口复制、右键复制、预览复制和 OCR badge 复制；粘贴路径继续在真正执行 `Command+V` 后播放 Paste 音效。已有复制 / 粘贴音效资源继续保留在 `Resources/Sounds/`，并通过 `scripts/verify_sound_feedback_guards.py` 守卫。
- `2.0.61(260521.2114)`：交互反馈收口包；将 `Copy.aiff` 和 `Paste.aiff` 保存到项目 `Resources/Sounds/`，构建脚本打包到 `.app/Contents/Resources/Sounds/`。复制成功路径播放 Copy 音效，自动粘贴成功发出 `Command+V` 后播放 Paste 音效；授权不足时仅写入剪贴板，按复制语义播放 Copy。已覆盖主窗口复制、纯文本复制、链接 / 颜色 / 图片 / 文件路径直接复制、预览窗口复制和 OCR badge 复制路径，并新增 `scripts/verify_sound_feedback_guards.py` 防止资源路径或打包遗漏回退。
- `2.0.60(260521.2051)`：性能 / 动画优化收口包；预览窗口打开时只立即加载文本和颜色这类轻内容，图片、链接、文件等重内容延后到轻量 shell 显示后再加载，避免打开动画阶段被磁盘 IO、图片解码或 Web / 文件预览初始化挤占。PDF 预览从同步 `PDFDocument(url:)` 改为可取消的 utility 任务加载，切换文件时先卸载旧 document；关闭预览时取消待加载任务并先清空 heavy content，减少关闭动画期间的重绘和资源占用。新增 `scripts/verify_preview_window_performance_guards.py` 守卫预览窗口性能路径，已通过预览、OCR、链接、搜索、窗口动画、卡片点击守卫和 smoke。
- `2.0.59(260521.2009)`：性能 / 动画优化收口包；OCR 后台识别新增动态并发控制，空闲最多 5 个识别任务，主窗口 / 预览交互期间降到 2 个；删除卡片、清空历史、删除分组、重复项替换和过期清理都会取消对应 OCR 任务。已新增 OCR 生命周期守卫，确认已完成 OCR 结果继续持久化在 `ClipboardItem`，不会因打开主窗口而重复识别。
- `2.0.58(260521.1911)`：性能 / 动画优化收口包；链接元数据后台任务现在按 item 持有可取消任务和 generation，同一链接新抓取会取消旧任务；删除卡片、清空历史、删除分组、重复项替换和过期清理都会取消对应抓取任务，避免无用网络 / 图片解码 / 图片保存继续占用资源。链接元数据守卫已覆盖任务表、generation 清理、取消路径和限流槽释放。
- `2.0.57(260521.1848)`：性能 / 动画优化收口包；链接元数据后台抓取增加并发限流，同时最多 3 个网络 / 图片解码 / 图片保存任务，标题回写和图片下载之间显式 `Task.yield()`，主线程只做短状态合并。
- `2.0.56(260521.1840)`：链接元数据抓取速度优化；HTML 抓取完成后先回写标题，预览图复用同一次 HTML 结果继续后台下载并单独回写；链接详情预览增加加载中和失败状态，避免内嵌预览失败时空白。
- `2.0.55(260521.1834)`：链接预览图尺寸下限调整为 `52pt...96pt`，小站点图标不再过小，同时限制大图过度放大。
- `2.0.54(260521.1829)`：链接元数据图片使用不放大小图的渲染模式，普通图片卡片继续保持铺满可用区域。
- `2.0.53(260521.1808)`：修复 RTF / HTML 富文本剪贴板中的完整 URL 未走链接捕获路径的问题；URL plain text 先走 `addText` 链接路径，普通富文本继续保留格式。
- `2.0.52(260521.1656)`：新增链接卡片预览图元数据能力，复制 URL 后后台抓取标题、`og:image` / `twitter:image` 和站点图标兜底，并用现有图片附件路径保存预览图。
- `2.0.51(260521.1641)`：性能 / 动画优化收口包；新增搜索 / 筛选性能守卫，确认搜索输入走防抖、取消旧任务、后台过滤、取消传播和 generation 防旧结果覆盖，主线程只应用最新过滤结果；同时守卫大历史量搜索路径不能回退成主线程同步过滤，也不能绕过 normalized search text 缓存。
- `2.0.50(260521.1620)`：性能 / 动画优化收口包；新增主窗口打开 / 关闭动画性能守卫，确认窗口只做轻量 frame 位移动画，不回归 alpha 动画、内容层 transform 或重阴影；同时守卫预览内容交互时不被主窗口外点逻辑误关、显示完成后再安装外部点击监听、隐藏时取消后台任务。
- `2.0.49(260521.1555)`：Office / 表格类文件预览稳定性收口包；当前结论为保留格式优先，`doc/docx/xls/xlsx/csv/ppt/pptx/rtf/numbers/pages/key` 等走嵌入式 Quick Look，普通文本文件继续走可选择文本预览；移除 Office 纯文本预览和底部可复制文本区方案；确认公开 `QLPreviewView` 无法稳定强制等同 Finder 空格预览的 Office 内容选择 / 复制能力，私有 Quick Look 激活接口禁止使用。新增当前稳定性验收清单和已知限制记录，后续由用户人工验收。
- `1.0.1(260512.2154)`：修复主窗口横向滚动位置关闭后丢失，并优化主窗口显示动画的内容重绘压力。
- `1.0.2(260512.2205)`：修复文字搜索结果高亮样式，命中内容改为黄色背景。
- `1.0.3(260512.2215)`：收口第一版 RC 文档，统一发布候选流程、发布说明、测试清单和当前 RC 包信息。
- `1.0.4(260512.2222)`：增强发布前 smoke check，检查 App bundle 与源码版本一致，并校验 RC 报告同步当前版本。
- `1.0.5(260513.1607)`：第二版阶段 4 UI 验收打包运行时由构建脚本自动递增版本，保持 RC 报告与当前 bundle 一致。
- `1.0.5(260513.1624)`：第二版阶段 5 分组基础验收打包运行，构建号随打包时间刷新。
- `1.0.5(260513.1642)`：第二版阶段 5 后续分组管理验收打包运行，构建号随打包时间刷新。
- `1.0.5(260513.1703)`：第二版阶段 5 分组 UI 返工验收打包运行，构建号随打包时间刷新。
- `1.0.5(260513.1710)`：第二版阶段 5 分组栏位置修正验收打包运行，构建号随打包时间刷新。
- `1.0.5(260513.1809)`：第二版阶段 5 分组后续收口验收打包运行，构建号随打包时间刷新。
- `1.0.5(260513.1844)`：第二版阶段 5 分组栏系统分组返工验收打包运行，构建号随打包时间刷新。
- `1.0.5(260513.1850)`：第二版阶段 5 分组栏居中修正验收打包运行，构建号随打包时间刷新。
- `1.0.5(260513.1906)`：第二版阶段 5 顶部滚动轨道和分组记忆验收打包运行，构建号随打包时间刷新。
- `1.0.5(260513.1919)`：第二版阶段 6 搜索 / 筛选 UI 第一批验收打包运行，构建号随打包时间刷新。
- `1.0.5(260513.1926)`：第二版阶段 6 搜索 / 筛选交互收口验收打包运行，构建号随打包时间刷新。
- `1.0.5(260513.1955)`：第二版阶段 6 搜索 token 与分组外观编辑修复验收打包运行，构建号随打包时间刷新。
- `1.0.5(260513.2056)`：第二版阶段 6 搜索框整体滚动、多选筛选面板和 ESC 顺序修复验收打包运行，构建号随打包时间刷新。
- `1.0.5(260513.2203)`：第二版阶段 6 搜索 / 授权 / ESC bugfix 返工后阶段性放行测试包，按用户要求执行 `scripts/build-app.sh --bump none --run`，构建号随打包时间刷新。
- `1.0.5(260513.2234)`：第二版阶段 6 搜索分组与输入性能修复 build/run，按用户授权执行 `scripts/build-app.sh --bump none --run`；本轮修复已通过 Test / Review / Acceptance / 用户人工 UI 验收。阶段 6 preview rebuild stale guard bugfix 已通过 Test / Review / Acceptance 并归档；阶段 6 搜索能力当前为 Acceptance PASS / 可放行，尚不代表最终正式发布完成。
- `1.0.5(260514.0008)`：第二版阶段 7 第一批编辑闭环 build/run，按用户明确授权“构建运行 App，我测试阶段7编辑功能”执行 `scripts/build-app.sh --bump none --run`；阶段 7 第一批编辑闭环已通过 Test / Review / Acceptance，可进入用户人工 UI 验收，尚不代表最终正式发布完成。
- `1.0.5(260514.0035)`：第二版阶段 7 编辑输入框复用修复 build/run，按用户明确授权“构建运行 App，我测试编辑输入框修”执行 `scripts/build-app.sh --bump none --run`；阶段 7 编辑输入框复用修复已通过 Test / Review / Acceptance，可进入用户人工 UI 验收，尚不代表最终正式发布完成。
- `1.0.6(260514.0301)`：第二版阶段 7 下一批无删除 MVP build/run，版本来自用户授权 build-run；本 RC 包含快捷键 / 菜单一致性、管理模式多选、批量收藏 / 取消收藏 / 移动到分组。批量删除仍 HOLD / 未放行；Review HOLD 另有管理模式 Delete 快捷键仍能删除单条记录，已由主控调度 Bugfix。
- `1.0.7(260514.0340)`：第二版阶段 7 SQLite-only / 无收藏 / 无管理模式 RC 对齐包；本 RC 包含 SQLite-only 数据基线、删除 JSON repository / JSON->SQLite migration、删除收藏字段和 UI、删除管理模式 / 多选 / 批量操作、分组唯一命名、分组命名 / popover 输入焦点修复。Test 功能验证 PASS，但 smoke 曾因本报告版本未同步当前 Info.plist 形成 blocker；Review 仍 HOLD P1：JSON import 存在 orphan groupID 风险，主控已调度 `V2-BUGFIX-SQLITE-ONLY-JSON-IMPORT-GROUPID-SANITIZE-001`，待 bugfix 完成后重跑 Test / Review / Acceptance 门禁；本记录不代表最终放行。
- `1.0.8(260514.1714)`：第二版阶段 7 SQLite-only 新基线后 RC 对齐包；本 RC 包含 SQLite-only 新基线、无收藏 / 无收藏 UI、无管理模式 / 无多选 / 无批量操作、备份导入旧 SQLite schema 非破坏性修复、备份导入 symlink / 非普通文件隔离、备份导入附件路径安全修复、备份附件目录 symlink 安全修复，以及“加入分组”二级菜单稳定性修复。Test 对“加入分组”二级菜单闪烁修复的功能验证 PASS，Review PASS；smoke 因本报告未同步当前 Info.plist `1.0.8(260514.1714)` HOLD，本次已完成 RC 版本对齐，后续由 Test 重跑 smoke / 门禁；本记录不代表最终放行。
- `1.0.9(260514.1835)`：第二版阶段 7 SQLite-only 新基线后加入分组 picker RC 对齐包；本 RC 包含 SQLite-only 新基线、无收藏 / 无收藏 UI、无管理模式 / 无多选 / 无批量操作、备份导入安全修复，以及加入分组 picker 替代闪烁二级菜单。Test 对加入分组 picker 方案功能验证 PASS，Review PASS；smoke 因本报告未同步当前 Info.plist `1.0.9(260514.1835)` HOLD，本次已完成 RC 版本对齐，后续由 Test 重跑 smoke / 门禁；本记录不代表最终放行。
- `1.0.10(260514.1852)`：第二版阶段 7 SQLite-only 新基线后历史卡片 selection/focus/right-click/border 修复 RC 对齐包；本 RC 包含 SQLite-only 新基线、无收藏 / 无收藏 UI、无管理模式 / 无多选 / 无批量操作、备份导入安全修复、加入分组 picker 替代闪烁二级菜单，以及历史卡片新剪切板定位、右键更新选中目标、顶部栏不遮挡选中上边缘外框修复。`V2-BUGFIX-HISTORY-SELECTION-FOCUS-RIGHTCLICK-BORDER-001` 已完成；smoke 因本报告未同步当前 Info.plist `1.0.10(260514.1852)` HOLD，本次已完成 RC 版本对齐，后续由 Test 重跑 smoke / 门禁；本记录不代表最终放行。
- `1.0.11(260514.1916)`：第二版阶段 8 first batch 窗口体验 RC 对齐包；本 RC 包含 SQLite-only 新基线、无收藏 / 无收藏 UI、无管理模式 / 无多选 / 无批量操作、备份导入安全修复、加入分组 picker、历史卡片 selection / focus / right-click / border 修复，以及阶段 8 第一批窗口体验修复：新剪切板定位只在真实新增顶部记录时触发，无新历史按视图恢复横向位置，用户分组 / 置顶下捕获普通新剪切板后下次打开切到全部并定位新记录，预览作为 child window 并在主窗口关闭 / 隐藏 / 失焦时清理，新建文本从主窗口更多菜单打开时隐藏主窗口且保存后打开并选中新记录，分组归属使用现有 API。更多按钮为 `...`；未恢复收藏 / 管理 / 多选 / 批量入口。UI Agent `V2-S8-WINDOW-EXPERIENCE-FIRST-BATCH-001` 已完成，UX Agent 已完成，主控已调度 Test / Review；smoke 因本报告未同步当前 Info.plist `1.0.11(260514.1916)` HOLD，本次已完成 RC 版本对齐，后续由 Test 重跑 smoke / 门禁；本记录不代表最终放行。
- `1.0.12(260514.2015)`：第二版阶段 8 first batch Acceptance PASS 后主控 build/run，并作为阶段 8 第二批 RC 对齐包；本 RC 继续包含 SQLite-only 新基线、无收藏 / 无收藏 UI、无管理模式 / 无多选 / 无批量操作、备份导入安全修复、加入分组 picker、历史卡片 selection / focus / right-click / border 修复、阶段 8 第一批窗口体验修复，并纳入阶段 8 第二批 `V2-S8-TOAST-TOPBAR-SEARCH-SELECTION-001`：HistoryWindow 内 overlay toast、顶部状态简化、未授权轻量入口、新剪切板打开主窗口选中新记录且不误选置顶、搜索框打开后外点关闭、顶部最右侧更多按钮精确显示为 `...`。Test 业务命令除 smoke 版本对齐项外均 PASS；smoke 因本报告未同步当前 Info.plist `1.0.12(260514.2015)` HOLD，本次已完成 RC 版本对齐并重跑通过；Review HOLD 为脏工作树范围无法证明，主控已调度架构范围裁定；本记录不代表最终放行。
- `1.0.13(260514.2108)`：第二版阶段 8 第二批 Acceptance PASS 后主控 build/run，并作为 Stage 9 文件卡片数据基础与 `.file` 最小编译 fallback 门禁对齐包；当前 Info.plist 为 `1.0.13 (260514.2108)`。Stage 9 已纳入 `.file` 内容类型、`ClipboardFileReference`、SQLite schema v3、`clipboard_item_files` 等数据基础，并补齐 HistoryWindow / Preview / PasteExecutor / RichTextEditor 等 `.file` switch 的最小编译 fallback。该 fallback 仅用于恢复编译和维持保守占位行为，不代表 Quick Look、文件捕获、文件粘贴执行、文件卡片完整 UI 或文件内容编辑已正式实现。Architecture PASS、Review PASS，Test 除 smoke RC 对齐外 PASS；此前 smoke HOLD 的唯一原因是本报告未同步当前 Info.plist `1.0.13(260514.2108)`，本次已完成 RC 版本对齐，后续由 Test Agent 重跑 smoke / Acceptance；本记录不代表最终放行。
- `1.0.14(260514.2215)`：Stage 9 文件卡片数据基础 Acceptance PASS 后主控执行 `scripts/build-app.sh` build/run，构建脚本自动从 `1.0.13 (260514.2108)` 提升到 `1.0.14 (260514.2215)`；产物 `/Users/wpc/code/codex/ClipboardHistory/.build/ClipEase.app` 已启动，PID `38068`。本包仍只覆盖 Stage 9 数据基础与 `.file` 最小编译 fallback，可用于继续验证数据基础和保守占位行为；不代表正式 Quick Look、ClipboardMonitor 文件捕获、文件 pasteboard 粘贴、完整文件卡片 UI、文件删除 / 移动 / 复制或 security-scoped bookmark 已完成或放行。本记录不代表最终正式发布完成。
- `1.0.15(260514.2323)`：Stage 9 文件捕获第一批 Acceptance PASS 后主控执行 `scripts/build-app.sh` build/run，构建脚本自动从 `1.0.14 (260514.2215)` 提升到 `1.0.15 (260514.2323)`；产物 `/Users/wpc/code/codex/ClipboardHistory/.build/ClipEase.app` 已启动，PID `7935`。本包包含 Stage 9 文件捕获第一批：ClipboardMonitor 捕获本地 file URL -> Store `.file` -> SQLite metadata，可用于用户人工测试真实 Finder 复制文件到剪贴板的端到端路径；不代表正式 Quick Look、文件 pasteboard 粘贴执行、完整文件卡片 UI、文件操作、security-scoped bookmark、FTS / 拼音 / SQLite 路径索引已完成或放行。本记录不代表最终正式发布完成。
- `1.0.16(260514.2340)`：Stage 9 文件卡片 UI 第一批 Acceptance PASS 后主控执行 `scripts/build-app.sh` build/run，构建脚本自动从 `1.0.15 (260514.2323)` 提升到 `1.0.16 (260514.2340)`；产物 `/Users/wpc/code/codex/ClipboardHistory/.build/ClipEase.app` 已启动，PID `34910`。本包包含 Stage 9 文件卡片 UI 第一批：主窗口文件卡片展示文件图标、文件名、完整路径、单 / 多文件数量、保守路径状态、File type token，内存搜索按文件名 / 路径，可用于用户人工视觉测试单文件 / 多文件文件卡片 UI；不代表正式 Quick Look、文件 pasteboard 粘贴执行、Finder 操作、原文件复制 / 移动 / 删除、security-scoped bookmark、FTS / 拼音 / SQLite 路径索引已完成或放行。本记录不代表最终正式发布完成。
- `1.0.17(260515.0106)`：`V2-BUGFIX-HISTORY-CARD-SCROLL-ALIGN-001` Acceptance PASS 后主控执行 `scripts/build-app.sh` build/run，构建脚本自动从 `1.0.16 (260514.2340)` 提升到 `1.0.17 (260515.0106)`；产物 `/Users/wpc/code/codex/ClipboardHistory/.build/ClipEase.app` 已启动，PID `30371`。本包包含 HistoryWindow 卡片滚动 / 选中 bugfix：新剪切板卡片打开主窗口时选中并滚动；无前置 offset 归零并显示左侧 padding；有置顶 / 前置时选中新卡片并露出上一张约 1/6；左右边缘未完整卡片点击后动画 reveal 并露出下一张约 1/6。后续由用户做运行态人工视觉点击验收。本包不包含 Stage 9 Quick Look、文件粘贴执行、Storage / ClipboardMonitor / PasteExecutor 改动、收藏 / 管理 / 多选 / 批量 / JSON migration runtime。本记录不代表最终正式发布完成。
- `1.0.18(260515.0130)`：Stage 9 Quick Look / 文件预览 spike 第一批 Acceptance PASS 后主控执行 `scripts/build-app.sh` build/run，构建脚本自动从 `1.0.17 (260515.0106)` 提升到 `1.0.18 (260515.0130)`；产物 `/Users/wpc/code/codex/ClipboardHistory/.build/ClipEase.app` 已启动，PID `67250`。本包包含 Stage 9 Quick Look / 文件预览 spike 第一批：`.file` 预览内容区 embedded `QLPreviewView`、单文件优先、多文件轻量列表且只预览一个、fallback、关闭 / 切换 cleanup `previewItem = nil`。后续由用户做真实运行态 Quick Look 视觉验收。本包不包含文件 pasteboard 粘贴执行、Finder 操作、文件写入 / 复制 / 移动 / 删除、security-scoped bookmark、Storage / ClipboardMonitor / PasteExecutor 改动、FTS / 拼音 / SQLite 路径索引、收藏 / 管理 / 多选 / 批量 / JSON migration runtime。本记录不代表最终正式发布完成。
- `1.0.19(260515.0241)`：`V2-BUGFIX-S9-QUICKLOOK-CARD-WINDOW-BATCH-001` Acceptance PASS 后主控执行 `scripts/build-app.sh` build/run，构建脚本自动从 `1.0.18 (260515.0130)` 提升到 `1.0.19 (260515.0241)`；产物 `/Users/wpc/code/codex/ClipboardHistory/.build/ClipEase.app` 已启动，PID `52168`。本包包含用户 9 项反馈修复：Quick Look 右侧切换 / 选中 / 截断 / 可交互 / 无重复 caption，主窗口单 / 多文件卡片展示，搜索内部点击不关闭且外部点击清空，卡片横向滚轮，latest card selection / peek，全局独立 toast window。后续由用户做运行态人工验收。本包不包含文件 pasteboard 粘贴执行、Finder 操作、原文件写入 / 复制 / 移动 / 删除、security-scoped bookmark、Storage / ClipboardMonitor / PasteExecutor 新改动、收藏 / 管理 / 多选 / 批量 / JSON migration runtime。本记录不代表最终正式发布完成。
- `1.0.20(260515.0325)`：`V2-ACCEPT-S9-FILE-PASTEBOARD-FIRST-BATCH-001` Acceptance PASS 后主控执行 `scripts/build-app.sh --run`，构建脚本自动从 `1.0.19 (260515.0241)` 提升到 `1.0.20 (260515.0325)`；产物 `/Users/wpc/code/codex/ClipboardHistory/.build/ClipEase.app` 已启动，PID `1508`。本包包含 Stage 9 文件引用 pasteboard 第一批：文件卡片普通复制写入 file URL pasteboard 引用；文件卡片自动粘贴前同样写入 file URL pasteboard 引用；纯文本复制保留路径字符串；self-copy guard 避免 ClipEase 自写文件引用被 ClipboardMonitor 回录；toast / status 文案使用“文件引用”。专项检查 `python3 scripts/verify_stage9_file_pasteboard_first_batch.py` PASS，`python3 scripts/verify_stage9_file_capture_first_batch.py` PASS；`python3 scripts/smoke_check.py` 当前仅因本报告未同步 `1.0.20(260515.0325)` HOLD，本次已完成 RC 文档对齐。本包不包含 Finder 操作、打开文件、拖拽 provider、原文件删除 / 移动 / 复制 / 写入、security-scoped bookmark、schema / repository / model / search index、收藏 / 管理 / 多选 / 批量 / JSON runtime。剩余风险为真实 Finder / 外部 App 文件引用 pasteboard 人工验收待用户测试。本记录不代表最终正式发布完成。
- `1.0.21(260515.0351)`：`V2-ACCEPT-S9-FILE-BASIC-ACTIONS-FIRST-BATCH-001` Acceptance PASS 后主控执行 `scripts/build-app.sh --run`，构建脚本自动从 `1.0.20 (260515.0325)` 提升到 `1.0.21 (260515.0351)`；产物 `/Users/wpc/code/codex/ClipboardHistory/.build/ClipEase.app` 已启动，PID `36369`。本包包含 Stage 9 文件卡片基础操作第一批：文件卡片右键菜单“复制路径”“在 Finder 中显示”；预览窗口 `.file` action menu “在 Finder 中显示”“复制路径”；controller 回调按 `.image/.file` 正确分派；单 / 多文件路径复制与 `skipNextClipboardText`；Finder reveal 只读定位存在文件 / 目录。专项检查 `python3 scripts/verify_stage9_file_basic_actions.py` PASS，`python3 scripts/verify_stage9_file_pasteboard_first_batch.py` PASS；`python3 scripts/smoke_check.py` 当前仅因本报告未同步 `1.0.21(260515.0351)` HOLD，本次已完成 RC 文档对齐。本包明确不包含打开文件、拖出 / drag provider、原文件删除 / 移动 / 复制 / 写入、security-scoped bookmark、schema / repository / model / search index、收藏 / 管理 / 多选 / 批量 / JSON runtime。剩余风险为真实 Finder 定位、预览窗口菜单、缺失路径等运行态人工验收待用户测试。本记录不代表最终正式发布完成。
- `1.0.22(260515.0414)`：`V2-ACCEPT-S9-FILE-DRAGOUT-FIRST-BATCH-001` Acceptance PASS 后主控执行 `scripts/build-app.sh --run`，构建脚本自动从 `1.0.21 (260515.0351)` 提升到 `1.0.22 (260515.0414)`；产物 `/Users/wpc/code/codex/ClipboardHistory/.build/ClipEase.app` 已启动，PID `67501`。本包包含 Stage 9 文件卡片拖出第一批：`.file` 卡片 AppKit drag source bridge；drag pasteboard 仅写 `NSURL` file URL 引用；拖出前即时校验路径；部分失效只拖有效项；全部失效提示；不吞普通点击 / 右键 / 滚动 / 预览。专项检查 `python3 scripts/verify_stage9_file_dragout_first_batch.py` PASS，`python3 scripts/verify_stage9_file_basic_actions.py` PASS；`python3 scripts/smoke_check.py` 当前仅因本报告未同步 `1.0.22(260515.0414)` HOLD，本次已完成 RC 文档对齐。本包明确不包含临时副本、打开文件、原文件删除 / 移动 / 复制 / 写入、security-scoped bookmark、schema / repository / model / search index、收藏 / 管理 / 多选 / 批量 / JSON runtime。剩余风险为真实 Finder / 外部 App 拖出运行态人工验收待用户测试。本记录不代表最终正式发布完成。
- `1.0.23(260515.0703)`：`V2-ACCEPT-S9-FILE-PASTE-FALLBACK-FIRST-BATCH-001` Acceptance PASS 后主控执行 `scripts/build-app.sh --run`，构建脚本自动从 `1.0.22 (260515.0414)` 提升到 `1.0.23 (260515.0703)`；产物 `/Users/wpc/code/codex/ClipboardHistory/.build/ClipEase.app` 已启动，PID `41016`。本包包含 Stage 9 文件引用粘贴 fallback 收口：有效文件仍优先写 `NSURL` file URL 引用；全部文件不可用时 fallback 写路径 / 显示名 / `item.text` 文本，多文件换行；fallback 结果有独立状态，toast 显示“文件路径”语义，不误报“文件引用”；fallback 调用 `skipNextClipboardText`。专项检查 `python3 scripts/verify_stage9_file_paste_fallback.py` PASS，`python3 scripts/verify_stage9_file_pasteboard_first_batch.py` PASS；`python3 scripts/smoke_check.py` 当前仅因本报告未同步 `1.0.23(260515.0703)` HOLD，本次已完成 RC 文档对齐。本包明确不包含原文件删除 / 移动 / 复制 / 写入、临时副本、打开文件 / Finder / drag 新增、security-scoped bookmark、schema / repository / model / search index、收藏 / 管理 / 多选 / 批量 / JSON runtime。剩余风险为真实外部 App 粘贴文件引用 / 路径 fallback、路径失效文件运行态人工验收待用户测试；预览 header 复制按钮统一 toast / fallback 状态已作为非阻塞 backlog 记录。本记录不代表最终正式发布完成。
- `2.0.0(260519.2258)`：按项目版本规则将第二版正式切到大版本线，主控执行 `scripts/build-app.sh --bump major --run`，构建脚本从 `1.0.129 (260519.2057)` 提升到 `2.0.0 (260519.2258)`；源码 `Resources/Info.plist` 与 `.build/ClipEase.app/Contents/Info.plist` 均已确认版本一致。直接执行模式未保留常驻进程，后续改用 App bundle 方式启动。本包用于第二版发布前人工验收和版本线收口，不新增功能。
- `2.0.1(260519.2309)`：修复 `scripts/build-app.sh --run` 启动方式，保留 `.icns` 复制和签名流程，将运行步骤改为 `open -n "$APP_DIR"` 并检查 bundle 内可执行进程；主控执行 `scripts/build-app.sh --bump patch --run` 后，源码与 `.build/ClipEase.app` 均为 `2.0.1 (260519.2309)`，脚本已自行启动 App bundle，PID `86840`。本包只修复构建运行流程，不新增功能。
