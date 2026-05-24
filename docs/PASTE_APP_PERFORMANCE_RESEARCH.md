# Paste.app 性能研究记录

记录日期：2026-05-23

## 研究边界

- 研究对象：`/Applications/Paste.app`，版本 `6.3.3 (15750)`。
- 研究方式：黑盒观察、bundle 元数据、签名 / entitlements、公开动态库依赖、容器文件布局、SQLite schema / 索引 / 查询计划、进程资源和系统日志。
- 未做事项：未反编译二进制，未绕过沙盒，未复制 Paste 实现代码，未读取剪贴板条目内容字段。

## 静态结构

- App 是 `LSUIElement` 菜单栏 / 辅助应用形态，主进程 bundle id 为 `com.wiheads.paste`。
- App 开启 sandbox，entitlements 包含：
  - `com.apple.security.app-sandbox`
  - `com.apple.security.application-groups = group.com.wiheads.paste`
  - `com.apple.security.files.user-selected.read-only`
  - `com.apple.security.network.client`
- App 内置 LoginItem：`Paste Helper.app`，bundle id 为 `com.wiheads.paste.mac-helper`，`LSBackgroundOnly=1`。
- 依赖系统框架包含 `CoreData`、`CloudKit`、`SwiftUI`、`QuickLook`、`QuickLookUI`、`LinkPresentation`、`Vision`、`VisionKit`、`WebKit`、`MetricKit` 等。

## 数据布局

Paste 主容器位于：

```text
~/Library/Containers/com.wiheads.paste/Data/Library/Application Support/Paste
```

关键文件：

- `db.sqlite`：Core Data 主库，约 `29MB`。
- `index.sqlite`：独立搜索 / OCR / 队列索引库，约 `11MB`。
- `.db_SUPPORT/_EXTERNAL_DATA`：Core Data 外置大字段目录，当前约 `144MB`，`108` 个外部文件。
- `db.sqlite-wal` / `index.sqlite-wal`：运行观察中均约 `8KB`，说明空闲状态没有持续大写入。

实测容器总量约 `272MB`；主库和索引库本身远小于外置大字段。

## 主库设计

`db.sqlite` 是 Core Data 风格 schema：

- `ZITEMENTITY`：条目 metadata，包含 `ZIDENTIFIER`、`ZTIMESTAMP`、`ZRAWTYPE`、`ZSOURCEAPPLICATION`、`ZTITLE`、`ZRAWPREVIEW`。
- `ZITEMDATAENTITY`：原始 pasteboard 数据，`ZRAWPASTEBOARDITEMS` 为大 BLOB。
- `ZAPPLICATIONENTITY`：来源 App metadata 和 icon BLOB。
- `ZDEVICEENTITY`、`ZLISTENTITY`、`ZLISTMETADATAENTITY`：设备、列表、列表 metadata。
- CloudKit / history tracking 相关表：`ATRANSACTION`、`ACHANGE`、`ZOBJECT*`。

关键索引：

- `Z_ItemEntity_byIdentifier` on `ZITEMENTITY(ZIDENTIFIER)`
- `Z_ItemEntity_byChecksum` on `ZITEMENTITY(ZCHECKSUM)`
- `ZITEMENTITY_ZSOURCEAPPLICATION_INDEX`
- `ZITEMENTITY_ZDATA_INDEX`
- `ZITEMENTITY_ZLIST_INDEX`
- `ZITEMDATAENTITY_ZITEM_INDEX`

观察到一个重要点：`ZITEMENTITY ORDER BY ZTIMESTAMP DESC LIMIT 50` 在当前 schema 下会扫描并临时排序；Paste 很可能不直接用主库驱动列表首屏，而是走 `index.sqlite` 的轻量时间索引。

## 索引库设计

`index.sqlite` 是独立轻量索引库，schema 重点：

```sql
CREATE TABLE items (
  rowid INTEGER PRIMARY KEY AUTOINCREMENT,
  id TEXT NOT NULL UNIQUE,
  app TEXT NOT NULL,
  timestamp INTEGER NOT NULL,
  type TEXT NOT NULL,
  title TEXT NOT NULL,
  content TEXT NOT NULL,
  device TEXT NOT NULL
);

CREATE INDEX idx_items_id ON items(id);
CREATE INDEX idx_items_timestamp ON items(timestamp);

CREATE VIRTUAL TABLE items_fts USING fts5(
  app, type, title, content, device,
  content=items,
  content_rowid=rowid,
  tokenize='unicode61 tokenchars ''#${}[]'''
);

CREATE TABLE fts_queue(id TEXT PRIMARY KEY, added_at REAL DEFAULT (julianday('now')));
CREATE TABLE ocr_queue(id TEXT PRIMARY KEY, added_at REAL DEFAULT (julianday('now')));
CREATE TABLE items_ocr(item_id TEXT PRIMARY KEY, metadata BLOB NOT NULL);
CREATE VIRTUAL TABLE vocabulary USING spellfix1;
```

触发器：

- `items_ai`：insert 后增量写入 FTS。
- `items_au`：update 后删除旧 FTS row 并写入新 row。
- `items_ad`：delete 后从 FTS 删除。

当前样本行数：

- `items`: `1587`
- `items_ocr`: `88`
- `fts_queue`: `0`
- `ocr_queue`: `0`
- `vocabulary_vocab`: `10125`

索引库查询计划：

- 最近列表：`ORDER BY timestamp DESC LIMIT 50` 使用 `idx_items_timestamp`。
- 按 id 查询：使用 `items.id` unique index。
- FTS 搜索：先扫 `items_fts` 虚表，再按 rowid 回表 `items`，最终按 timestamp 排序并限制结果。

这说明 Paste 把搜索和列表首屏约束在轻量 metadata / FTS 索引上，而不是每次打开 UI 都加载完整 payload。

## 运行态观察

启动 Paste 后观察：

- 进程：`/Applications/Paste.app/Contents/MacOS/Paste`
- 空闲 CPU：`0.0%`
- RSS：约 `83MB`
- `sample` 空闲主线程停在 AppKit event loop / mach_msg。
- sample physical footprint：约 `23.7MB`，peak `24.0MB`。
- `lsof` 显示进程打开 `db.sqlite`、`index.sqlite` 及其 WAL/SHM，但没有持续打开 `_EXTERNAL_DATA` 中的大字段文件。

这支持一个判断：Paste 常驻时只保持数据库连接和轻量索引，不把完整历史内容、外置 BLOB、缩略图或预览全部加载进内存。

## 预览窗口打开行为

2026-05-24 对 Paste 预览弹层做了补充黑盒观察：

- 可见符号包含 `PasteStackWindowController`、`PasteStackWindow`、`ItemPreviewWindowManager`、`ItemPreviewWindow`、`PreviewPopover`、`ItemPreviewView`、`PreviewHeader`。
- Accessibility 树中预览以独立 `AXPopover` / 弹出窗口形式出现，内部包含标题、关闭、置顶、分享、编辑、内容滚动区和底部统计信息。
- 视觉上预览不是让历史卡片自身变形，也不是从极小点位展开，而是整张圆角预览面板逐渐等比放大并淡入。
- 预览容器的出现和具体内容加载是分离的：容器先稳定出现，文本、文件、图片等内容在容器内部填充，避免打开阶段因为重内容初始化导致窗口闪烁。
- 预览关闭也更像整张面板逐渐缩小 / 淡出，而不是整窗 frame 大幅移动。

迁移到轻贴的动画原则：

- 预览 panel 的最终 frame 先计算并就位。
- 动画只作用于内容层，避免主窗口 / 列表卡片重新布局。
- 初始 transform 应使用等比 zoom，例如 `0.86 x 0.86` 放大到 `1.0 x 1.0`，而不是 `0.12 x 0.04` 的点状展开，也不是带位移的抬起。
- 打开时长控制在约 `0.24s - 0.28s`，关闭控制在约 `0.16s - 0.18s`，重点是稳定、轻微、有层级，而不是强形变。
- 文件 / 图片等重内容继续按需加载，但不要让内容加载改变预览容器的首帧几何。

## 可迁移到轻贴的设计原则

这些是基于黑盒证据的工程结论，不涉及 Paste 代码实现：

1. 存储分层
   - 主库保存完整条目和原始 payload。
   - 独立索引库保存列表 / 搜索需要的轻量字段。
   - 大字段外置文件化，列表和搜索不触碰大字段。

2. 列表首屏只读 metadata
   - 列表数据源应从 `createdAt/timestamp` 索引分页读取。
   - 打开窗口只取首屏和少量 buffer，不构建全量 `HistoryPreviewItem`。
   - 大内容、富文本、图片、OCR、文件预览只在选中 / hover / 可见时按需加载。

3. 搜索走增量索引
   - 维护独立 `search_index` 表和 FTS5 虚表。
   - 新增 / 删除 / 更新通过事务和触发器或明确增量任务维护索引。
   - 搜索只返回 top N / page ids，再按 ids 回表取列表 metadata。

4. 后台队列显式化
   - FTS 和 OCR 都有 queue 表，说明重任务可恢复、可批处理、可延迟。
   - 轻贴可以采用 `search_index_queue`、`preview_cache_queue`、`ocr_queue`，避免在 UI 生命周期中补索引。

5. UI 不绑定全量数组
   - Paste 的低空闲占用说明它没有用 UI 状态保存完整 payload。
   - 轻贴当前问题主要是打开 / 搜索 / 重开窗口时反复构建 11 万条 preview item，并让 SwiftUI/Accessibility 处理大结果切换。
   - 下一阶段应把 HistoryWindow 数据源改为 paged data source，而不是继续优化全量数组。

6. 可验证指标
   - 打开窗口：首屏 metadata query < `50ms`，不触发全量 preview rebuild。
   - 空闲：CPU `0%`，主线程 latency < `1ms`。
   - 搜索：FTS query + top N ids < `50ms`，UI apply < `5ms`。
   - 预览：只在选中 / hover 后加载 payload，并可取消。

## 对轻贴的建议分阶段方案

### Phase 1：停止重复全量预览构建

- 如果 Store item identity / count / latest timestamp 没变，重新打开历史窗口不再 full rebuild。
- 隐藏窗口后保留轻量 preview cache，只保留可见窗口和最近若干条。
- 这一步不改 schema，风险最低。

### Phase 2：引入轻量列表索引表

- 新增 `clipboard_item_index`：
  - `id`
  - `createdAt`
  - `type`
  - `sourceAppName`
  - `sourceBundleIdentifier`
  - `title`
  - `previewTextPrefix`
  - `hasPayload`
  - `searchVersion`
- 建索引：`createdAt DESC`、`type`、`sourceAppName`、`id UNIQUE`。
- 启动只查最近 page，不加载完整 payload。

### Phase 3：独立 FTS5 搜索索引

- 新增 `clipboard_search_index` + FTS5。
- normalizedText / tokenText 在新增或后台任务中生成一次。
- 搜索返回 top `500` 或分页 ids，再回表取 metadata。

### Phase 4：payload 和预览按需化

- 列表 item 只持有 metadata。
- 文本预览限制长度；图片 / RTF / HTML / 文件 preview 均按需异步加载。
- 用 `id -> preview cache`，支持取消和内存上限。

### Phase 5：后台队列和恢复

- 新增 `index_queue`、`ocr_queue`、`thumbnail_queue`。
- 批量事务处理，失败可恢复。
- UI 只展示现有索引结果，不等待补索引完成。

## 结论

Paste 的不卡顿核心不是某一个动画细节，而是数据路径设计：

- UI 首屏不依赖完整历史 payload。
- 搜索不在 UI 中扫描全量 item。
- 大字段外置并按需加载。
- 搜索 / OCR / FTS 是持久化索引和队列，而不是打开窗口时临时构建。
- 常驻状态只保持轻量连接和索引，空闲主线程停在事件循环。

轻贴要接近这个体验，下一步应停止继续围绕 11 万条全量 SwiftUI 数组做微调，转向轻量索引库、分页数据源和按需 payload。
