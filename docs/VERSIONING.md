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
- 构建号：`CFBundleVersion`，格式为 `YYMMDD.HHMM`，任何一次打包都会自动更新为当前时间。

## 产品版本递增

产品版本按发布性质手动递增：

- `major`：大版本 +1，例如 `1.4.2 -> 2.0.0`。
- `minor`：小版本 +0.1，例如 `1.4.2 -> 1.5.0`。
- `patch`：修补 +0.0.1，例如 `1.4.2 -> 1.4.3`。
- `none`：产品版本不变，但时间戳仍然更新。

第一版维护和常规开发默认使用：

- 每次正式打包 `.app`：默认递增 `patch`，并更新时间戳构建号。
- 完成一个较完整功能阶段：手动使用 `--bump minor`。
- 重大体验或架构变化：手动使用 `--bump major`。
- 仅需要重打包且不希望改变产品版本时：手动使用 `--bump none`，但时间戳仍然更新。
- 第一版可用发布：从 `0.x.x` 进入 `1.0.0`。
- 第二版正式开始实现：从当前第一版稳定版本进入 `2.0.0(时间戳)`。

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

只更新时间戳、不改变产品版本：

```bash
scripts/build-app.sh --bump none
```
