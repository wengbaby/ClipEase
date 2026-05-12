# 版本规则

轻贴的完整版本显示格式为：

```text
x.x.x(YYMMDD.HHMM)
```

例如：

```text
1.0.0(260510.2202)
```

其中：

- 产品版本：`CFBundleShortVersionString`，格式为 `主版本.小版本.修复版本`，例如 `0.1.0`。
- 构建号：`CFBundleVersion`，格式为 `YYMMDD.HHMM`，每次正式打包 `.app` 自动更新为当前时间。

## 产品版本递增

产品版本按发布性质手动递增：

- `major`：重大版本，例如架构大改、核心体验大改，`1.4.2 -> 2.0.0`。
- `minor`：功能版本，例如新增剪贴板图片记录、搜索、设置页，`1.4.2 -> 1.5.0`。
- `patch`：修复版本，例如修 bug、微调样式，`1.4.2 -> 1.4.3`。
- `none`：只增加构建号，不改变产品版本。

当前开发期默认使用：

- 每次正式打包 `.app`：默认递增 `patch`，并更新时间戳构建号。
- 完成一个较完整功能阶段：手动使用 `--bump minor`。
- 重大体验或架构变化：手动使用 `--bump major`。
- 仅需要重打包且不希望改变产品版本时：手动使用 `--bump none`。
- 第一版可用发布：从 `0.x.x` 进入 `1.0.0`。

## 命令

默认递增修复版本并打包：

```bash
scripts/build-app.sh
```

增加小版本并打包：

```bash
scripts/build-app.sh --bump minor
```

增加修复版本并打包：

```bash
scripts/build-app.sh --bump patch
```

增加大版本并打包：

```bash
scripts/build-app.sh --bump major
```

打包并重启本地 App：

```bash
scripts/build-app.sh --run
```

该命令会先关闭旧的 ClipEase 进程，再打开新的 `.app`，避免测试时出现多个菜单栏实例。

只更新时间戳构建号、不改变产品版本：

```bash
scripts/build-app.sh --bump none
```
