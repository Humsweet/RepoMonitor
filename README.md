# RepoMonitor

> A lightweight macOS menu-bar app that watches all your Git repositories and tells you what needs attention — at a glance.

![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-lightgrey?logo=apple)
![Swift](https://img.shields.io/badge/swift-5.9-orange?logo=swift)
![License](https://img.shields.io/badge/license-MIT-blue)

<!-- Replace with an actual screenshot -->
<!-- ![Screenshot](screenshots/dashboard.png) -->

---

## What it does

RepoMonitor sits in your menu bar and periodically scans your Git repositories. It fetches from remote and surfaces three kinds of status:

| Status | Meaning |
|--------|---------|
| **Behind** | Remote has commits you haven't pulled |
| **Dirty** | Uncommitted local changes |
| **Ahead** | Local commits not yet pushed |

Open the dashboard for a full table view with one-click actions per repo.

---

## Features

- **Menu bar icon** — turns orange the moment any repo needs attention
- **Dashboard** — sortable table: repo name, path, ahead/behind count, last scan time
- **Auto-scan** — runs on a configurable interval (default 10 min)
- **Quick actions** — per-row buttons to scan, open in Terminal, VS Code, or Finder
- **macOS notifications** — get alerted when repos fall behind or go dirty
- **Flexible config** — scan entire folder trees or individual paths via JSON

---

## Requirements

- macOS 13 Ventura or later
- Xcode Command Line Tools (or full Xcode)
- Git available in `$PATH`

---

## Installation

### Option A — Build from source

```bash
git clone https://github.com/<your-username>/RepoMonitor.git
cd RepoMonitor
bash scripts/bundle.sh
open build/RepoMonitor.app
```

Move `build/RepoMonitor.app` to `/Applications` if you want it to persist across builds.

### Option B — Xcode

Open `RepoMonitor.xcodeproj`, select the **RepoMonitor** scheme, and hit **Run**.

---

## Configuration

On first launch RepoMonitor creates a default config file at:

```
~/.config/repo-monitor/config.json
```

Edit it to tell the app which folders to watch. A full example is in [`config.example.json`](config.example.json).

### Config reference

```jsonc
{
  "roots": [
    // Scan every direct child of this folder as a separate repo
    { "path": "~/Projects", "mode": "children" },
    // Treat this path itself as a single repo
    { "path": "~/dotfiles", "mode": "self" }
  ],
  "git": {
    "fetchBeforeCompare": true,   // run `git fetch` before checking status
    "fetchTimeoutSeconds": 30
  },
  "notifications": {
    "enabled": true,
    // "errors" | "behind" | "behindAndDirty"
    "mode": "behindAndDirty",
    "minimumIntervalMinutes": 30  // avoid notification spam
  },
  "desktop": {
    "scanIntervalMinutes": 10     // auto-scan interval
  }
}
```

> **Tip:** Changes to `config.json` are picked up automatically on the next scan. No restart needed.

---

## Usage

1. **Launch** the app — a monitor icon appears in the menu bar.
2. **Click the icon** to see a quick summary or open the dashboard.
3. **Dashboard** — click any column header to sort; hover a row for quick actions.
4. **Scan now** — hit the **Scan** button (bottom-right) to trigger an immediate full scan.
5. **Skip a repo** — click **Unwatch** in the row context menu to stop monitoring it.

---

## Building for distribution

```bash
bash scripts/bundle.sh
# Output: build/RepoMonitor.app
```

The script runs a release build via SwiftPM and packages it into a `.app` bundle. No code-signing is configured by default, so macOS may show a Gatekeeper warning on first open — right-click → Open to bypass it.

---

## Project layout

```
RepoMonitor/
├── Models/          # Data structs: RepoSnapshot, MonitorConfig
├── Services/        # Git CLI wrapper, config loader, notifications
├── ViewModels/      # DashboardViewModel — orchestrates scanning & state
├── Views/           # SwiftUI views (Dashboard, MenuBar, Settings…)
└── RepoMonitorApp.swift
scripts/
└── bundle.sh        # Release build + app bundle packaging
config.example.json  # Annotated config template
```

---

## Contributing

Issues and PRs are welcome. A few notes:

- Follow the coding conventions in [`AGENTS.md`](AGENTS.md).
- There is no test target yet — manual verification steps are appreciated in PRs.
- Keep commits focused and use short imperative subjects (`Fix fetch timeout`, `Add dirty filter`).

---

## License

MIT — see [LICENSE](LICENSE) for details.

---

---

# RepoMonitor（中文说明）

> 一款轻量的 macOS 菜单栏应用，帮你一眼掌握所有 Git 仓库的状态。

---

## 它能做什么

RepoMonitor 常驻菜单栏，定时扫描你的 Git 仓库，自动执行 `git fetch` 并检测三类状态：

| 状态 | 含义 |
|------|------|
| **Behind** | 远端有你还没 pull 的提交 |
| **Dirty** | 有未提交的本地修改 |
| **Ahead** | 有本地提交还没 push |

打开 Dashboard 可查看完整表格，并对每个仓库执行快捷操作。

---

## 功能一览

- **菜单栏图标**：有仓库需要关注时图标变橙色
- **Dashboard 面板**：可排序的仓库表格，显示名称、路径、ahead/behind 数量、最近扫描时间
- **自动扫描**：按可配置的间隔自动运行（默认 10 分钟）
- **快捷操作**：每行提供按钮，一键扫描、在终端/VS Code/Finder 中打开
- **macOS 通知**：仓库落后或有脏文件时推送通知
- **JSON 配置**：灵活指定要监控的目录树或单个路径

---

## 系统要求

- macOS 13 Ventura 及以上
- Xcode Command Line Tools 或完整 Xcode
- Git 在 `$PATH` 中可用

---

## 安装方式

### 方式一：从源码构建

```bash
git clone https://github.com/<your-username>/RepoMonitor.git
cd RepoMonitor
bash scripts/bundle.sh
open build/RepoMonitor.app
```

如需长期使用，将 `build/RepoMonitor.app` 拷贝到 `/Applications`。

### 方式二：Xcode

打开 `RepoMonitor.xcodeproj`，选择 **RepoMonitor** Scheme，点击 **Run**。

---

## 配置说明

首次启动后，应用会在以下路径创建默认配置文件：

```
~/.config/repo-monitor/config.json
```

编辑该文件告诉应用要监控哪些目录。完整示例见 [`config.example.json`](config.example.json)。

### 配置字段说明

```jsonc
{
  "roots": [
    // 扫描该目录下的所有直接子目录（每个子目录视为一个仓库）
    { "path": "~/Projects", "mode": "children" },
    // 将该路径本身视为一个仓库
    { "path": "~/dotfiles", "mode": "self" }
  ],
  "git": {
    "fetchBeforeCompare": true,   // 检测前先执行 git fetch
    "fetchTimeoutSeconds": 30
  },
  "notifications": {
    "enabled": true,
    // 可选值："errors" | "behind" | "behindAndDirty"
    "mode": "behindAndDirty",
    "minimumIntervalMinutes": 30  // 避免通知轰炸
  },
  "desktop": {
    "scanIntervalMinutes": 10     // 自动扫描间隔（分钟）
  }
}
```

> **提示**：修改 `config.json` 后无需重启，下次扫描时自动生效。

---

## 使用步骤

1. 启动应用，菜单栏出现监控图标。
2. 点击图标查看摘要，或打开 Dashboard。
3. Dashboard 中点击列标题排序；悬停行查看快捷操作按钮。
4. 点击右下角 **Scan** 按钮立即触发全量扫描。
5. 右键点击某行 → **Unwatch** 可停止监控该仓库。

---

## 项目结构

```
RepoMonitor/
├── Models/          # 数据结构：RepoSnapshot、MonitorConfig
├── Services/        # Git CLI 封装、配置加载、通知服务
├── ViewModels/      # DashboardViewModel — 扫描调度与状态管理
├── Views/           # SwiftUI 视图（Dashboard、菜单栏、设置…）
└── RepoMonitorApp.swift
scripts/
└── bundle.sh        # Release 构建 + App Bundle 打包
config.example.json  # 带注释的配置模板
```

---

## 参与贡献

欢迎提 Issue 和 PR，请参考 [`AGENTS.md`](AGENTS.md) 中的代码规范。

---

## 许可证

MIT，详见 [LICENSE](LICENSE)。
