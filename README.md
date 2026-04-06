<div align="center">

# RepoMonitor

**A lightweight macOS menu-bar app that watches all your Git repositories and tells you what needs attention — at a glance.**

[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-lightgrey?logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/swift-5.9-F05138?logo=swift&logoColor=white)](https://swift.org)
[![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-0063EB?logo=swift&logoColor=white)](https://developer.apple.com/xcode/swiftui/)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

[English](#english) · [中文](#中文)

</div>

---

<a name="english"></a>

## Table of Contents

- [What it does](#what-it-does)
- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Configuration](#configuration)
- [Usage](#usage)
- [Project Layout](#project-layout)
- [Contributing](#contributing)
- [License](#license)

---

## What it does

RepoMonitor sits in your menu bar and periodically scans your Git repositories. It runs `git fetch` automatically and surfaces three kinds of status:

| Status | Meaning |
|--------|---------|
| 🔴 **Behind** | Remote has commits you haven't pulled |
| 🟡 **Dirty** | Uncommitted local changes exist |
| 🟢 **Ahead** | Local commits not yet pushed |

Open the dashboard for a full sortable table with one-click actions per repo.

---

## Features

| Feature | Description |
|---------|-------------|
| **Menu bar icon** | Changes to reflect worst-case repo status at a glance |
| **Dashboard** | Sortable table: repo name, path, branch, ahead/behind counts, last scan time |
| **Auto-scan** | Runs on a configurable interval (default: 10 min) |
| **Quick actions** | Per-row buttons to open in Terminal, VS Code, or Finder |
| **macOS notifications** | Alerts when repos fall behind or go dirty (rate-limited) |
| **Skip current repo** | Interrupt a long-running fetch without cancelling the full scan |
| **Persistent state** | Remembers last scan results across restarts |
| **Flexible config** | Scan entire folder trees (`children`) or individual paths (`self`) via JSON |

---

## Requirements

- macOS 13 Ventura or later
- Xcode Command Line Tools (`xcode-select --install`) or full Xcode
- Git available in `$PATH`

---

## Installation

### Option A — Build from source (recommended)

```bash
git clone https://github.com/Humsweet/RepoMonitor.git
cd RepoMonitor
bash scripts/bundle.sh
open build/RepoMonitor.app
```

Move `build/RepoMonitor.app` to `/Applications` for a persistent installation.

> **First launch note:** macOS Gatekeeper may block the app because it isn't code-signed. Right-click → **Open** → **Open** to bypass the warning.

### Option B — Xcode

```bash
git clone https://github.com/Humsweet/RepoMonitor.git
```

Open `RepoMonitor.xcodeproj`, select the **RepoMonitor** scheme, and press **⌘R**.

---

## Configuration

On first launch, RepoMonitor creates a default config at:

```
~/.config/repo-monitor/config.json
```

Edit it to tell the app which folders to watch. A fully annotated example is in [`config.example.json`](config.example.json).

### Full config reference

```jsonc
{
  "roots": [
    // Scan every direct child of this folder as a separate repo
    { "path": "~/Projects", "mode": "children" },
    // Treat this exact path itself as a single repo
    { "path": "~/dotfiles", "mode": "self" }
  ],
  "unwatchedPaths": [
    // Absolute paths to exclude from all scans
    "~/Projects/archived-repo"
  ],
  "git": {
    "fetchBeforeCompare": true,   // run `git fetch` before checking status
    "fetchTimeoutSeconds": 30,    // per-repo fetch timeout
    "hostCredentials": [
      // Optional HTTPS host credentials. Token/app password is stored in macOS Keychain.
      { "host": "bitbucket.org", "username": "your-bitbucket-username" }
    ]
  },
  "notifications": {
    "enabled": true,
    "mode": "behindAndDirty",     // "errors" | "behind" | "behindAndDirty"
    "minimumIntervalMinutes": 30  // minimum time between notification bursts
  },
  "desktop": {
    "scanIntervalMinutes": 10     // background auto-scan interval
  },
  "state": {
    "filePath": "state.json"      // persisted scan state (relative to config dir)
  },
  "logging": {
    "filePath": "repo-monitor-runtime.log"
  }
}
```

> **Tip:** Config changes are picked up automatically on the next scan. No restart needed.
>
> **HTTPS auth:** If a remote uses HTTPS and cannot prompt interactively, save its host credential once in Settings. RepoMonitor stores the token/app password in macOS Keychain and reuses it for future scans.

---

## Usage

1. **Launch** the app — a monitor icon appears in the menu bar.
2. **Click the icon** to see a live summary (total repos, behind count, dirty count, warnings).
3. **Open Dashboard** — click any column header to sort; hover a row to reveal quick-action buttons.
4. **Scan now** — click **Scan** in the menu bar popover to trigger an immediate full scan.
5. **Skip a repo** — click **Skip Current Repo** during a scan to skip a slow or hanging fetch.
6. **Edit config** — click **Edit Config** to open `config.json` directly in your default editor.

---

## Project Layout

```
RepoMonitor/
├── Models/
│   ├── MonitorConfig.swift      # All config structs (roots, git, notifications…)
│   └── RepoSnapshot.swift       # Per-repo state: branch, ahead/behind, dirty, errors
├── Services/
│   ├── GitCLI.swift             # Actor wrapping git subprocess calls
│   ├── ConfigLoader.swift       # JSON config & state persistence
│   ├── NotificationService.swift
│   └── RepoMonitorService.swift # Scan orchestration & state management
├── ViewModels/
│   └── DashboardViewModel.swift # Observable bridge: scan results → UI
├── Views/
│   ├── MenuBarView.swift        # Popover shown on menu bar click
│   ├── DashboardView.swift      # Full dashboard window
│   ├── RepoTableView.swift      # Sortable repo table
│   ├── RepoRowView.swift        # Individual row with quick actions
│   ├── RepoDetailView.swift     # Detail sheet for a single repo
│   ├── SettingsView.swift       # In-app settings panel
│   ├── StatsCardView.swift      # Summary stats cards
│   └── Theme.swift              # Shared colors & typography
└── RepoMonitorApp.swift         # App entry point & window scene setup

scripts/
└── bundle.sh                    # Release build → .app bundle
config.example.json              # Annotated config template
```

---

## Contributing

Issues and pull requests are welcome!

- Follow the conventions in [`AGENTS.md`](AGENTS.md).
- Write short, imperative commit subjects: `Fix fetch timeout on slow remotes`, `Add dirty filter to dashboard`.
- Include manual test steps for UI changes (menu bar behavior, notification triggers, settings persistence).
- There is no test target yet — XCTest coverage under `RepoMonitorTests/` is encouraged for new `Models/` or `Services/` logic.

---

## Security

- RepoMonitor never reads or stores Git credentials.
- Remote URLs are sanitized before display/logging to strip embedded usernames/passwords.
- No network requests are made except `git fetch` to your configured remotes.

---

## License

MIT — see [LICENSE](LICENSE) for details.

---

<a name="中文"></a>

<div align="center">

# 中文说明

**RepoMonitor — 轻量 macOS 菜单栏应用，帮你一眼掌握所有 Git 仓库的状态。**

</div>

---

## 目录

- [它能做什么](#它能做什么)
- [功能一览](#功能一览)
- [系统要求](#系统要求)
- [安装方式](#安装方式)
- [配置说明](#配置说明)
- [使用步骤](#使用步骤)
- [项目结构](#项目结构)
- [参与贡献](#参与贡献)
- [许可证](#许可证)

---

## 它能做什么

RepoMonitor 常驻菜单栏，定时扫描你的 Git 仓库，自动执行 `git fetch` 并检测三类状态：

| 状态 | 含义 |
|------|------|
| 🔴 **Behind（落后）** | 远端有你还没 pull 的提交 |
| 🟡 **Dirty（有改动）** | 有未提交的本地修改 |
| 🟢 **Ahead（超前）** | 有本地提交还没 push |

打开 Dashboard 可查看完整的可排序表格，并对每个仓库执行快捷操作。

---

## 功能一览

| 功能 | 说明 |
|------|------|
| **菜单栏图标** | 实时反映所有仓库中最严重的状态 |
| **Dashboard 面板** | 可排序表格：仓库名、路径、分支、ahead/behind 数量、最近扫描时间 |
| **自动扫描** | 按可配置的间隔自动运行（默认 10 分钟） |
| **快捷操作** | 每行提供按钮，一键在终端/VS Code/Finder 中打开 |
| **macOS 通知** | 仓库落后或有脏文件时推送通知（有频率限制，避免刷屏） |
| **跳过当前仓库** | 扫描时可中断慢速或卡住的 fetch，不影响整体扫描 |
| **状态持久化** | 重启后保留上次扫描结果 |
| **灵活配置** | 通过 JSON 指定扫描整个目录树（`children`）或单个路径（`self`） |

---

## 系统要求

- macOS 13 Ventura 及以上
- Xcode Command Line Tools（`xcode-select --install`）或完整 Xcode
- Git 在 `$PATH` 中可用

---

## 安装方式

### 方式一：从源码构建（推荐）

```bash
git clone https://github.com/Humsweet/RepoMonitor.git
cd RepoMonitor
bash scripts/bundle.sh
open build/RepoMonitor.app
```

如需长期使用，将 `build/RepoMonitor.app` 拷贝到 `/Applications`。

> **首次启动提示：** 由于应用未代码签名，macOS Gatekeeper 可能会阻止运行。右键点击 → **打开** → **打开** 即可绕过提示。

### 方式二：Xcode

```bash
git clone https://github.com/Humsweet/RepoMonitor.git
```

打开 `RepoMonitor.xcodeproj`，选择 **RepoMonitor** Scheme，按 **⌘R** 运行。

---

## 配置说明

首次启动后，应用会在以下路径创建默认配置文件：

```
~/.config/repo-monitor/config.json
```

编辑该文件告诉应用要监控哪些目录。完整示例见 [`config.example.json`](config.example.json)。

### 完整配置字段说明

```jsonc
{
  "roots": [
    // 扫描该目录下的所有直接子目录（每个子目录视为一个独立仓库）
    { "path": "~/Projects", "mode": "children" },
    // 将该路径本身视为一个仓库
    { "path": "~/dotfiles", "mode": "self" }
  ],
  "unwatchedPaths": [
    // 需要从扫描中排除的绝对路径
    "~/Projects/archived-repo"
  ],
  "git": {
    "fetchBeforeCompare": true,   // 检测前先执行 git fetch
    "fetchTimeoutSeconds": 30,    // 每个仓库的 fetch 超时时间（秒）
    "hostCredentials": [
      // 可选的 HTTPS 主机凭证。token / app password 保存在 macOS 钥匙串里。
      { "host": "bitbucket.org", "username": "your-bitbucket-username" }
    ]
  },
  "notifications": {
    "enabled": true,
    "mode": "behindAndDirty",     // 可选值："errors" | "behind" | "behindAndDirty"
    "minimumIntervalMinutes": 30  // 两次通知之间的最短间隔（避免轰炸）
  },
  "desktop": {
    "scanIntervalMinutes": 10     // 后台自动扫描间隔（分钟）
  },
  "state": {
    "filePath": "state.json"      // 持久化扫描状态文件（相对于配置目录）
  },
  "logging": {
    "filePath": "repo-monitor-runtime.log"
  }
}
```

> **提示：** 配置修改后会在下一次扫描时生效，无需重启。
>
> **HTTPS 认证：** 如果某个 remote 使用 HTTPS 且无法交互式登录，请在 Settings 中为对应 host 保存一次凭证。RepoMonitor 会把 token / app password 存到 macOS 钥匙串，并在后续扫描时自动复用。

---

## 使用步骤

1. 启动应用，菜单栏出现监控图标。
2. 点击图标查看实时摘要（仓库总数、落后数量、脏文件数量、警告数量）。
3. 点击 **Open Dashboard** 打开完整面板；点击列标题排序；悬停行查看快捷操作按钮。
4. 点击菜单栏弹窗中的 **Scan** 立即触发全量扫描。
5. 扫描进行中可点击 **Skip Current Repo** 跳过当前慢速仓库。
6. 点击 **Edit Config** 直接在默认编辑器中打开 `config.json`。

---

## 项目结构

```
RepoMonitor/
├── Models/
│   ├── MonitorConfig.swift      # 所有配置结构体（roots、git、notifications…）
│   └── RepoSnapshot.swift       # 单仓库状态：分支、ahead/behind、脏文件、错误
├── Services/
│   ├── GitCLI.swift             # 封装 git 子进程调用的 Actor
│   ├── ConfigLoader.swift       # JSON 配置与状态持久化
│   ├── NotificationService.swift
│   └── RepoMonitorService.swift # 扫描调度与状态管理
├── ViewModels/
│   └── DashboardViewModel.swift # 可观察对象：扫描结果 → UI
├── Views/
│   ├── MenuBarView.swift        # 菜单栏点击后的弹出窗口
│   ├── DashboardView.swift      # 完整 Dashboard 窗口
│   ├── RepoTableView.swift      # 可排序仓库表格
│   ├── RepoRowView.swift        # 单行视图 + 快捷操作
│   ├── RepoDetailView.swift     # 单仓库详情面板
│   ├── SettingsView.swift       # 应用内设置面板
│   ├── StatsCardView.swift      # 统计摘要卡片
│   └── Theme.swift              # 共享颜色与排版
└── RepoMonitorApp.swift         # 应用入口 + 窗口场景配置

scripts/
└── bundle.sh                    # Release 构建 → .app Bundle
config.example.json              # 带注释的配置模板
```

---

## 参与贡献

欢迎提 Issue 和 PR！

- 请参考 [`AGENTS.md`](AGENTS.md) 中的代码规范。
- 使用简短的祈使句式提交信息：`Fix fetch timeout on slow remotes`、`Add dirty filter to dashboard`。
- UI 相关改动请附上手动测试步骤（菜单栏行为、通知触发、设置持久化等）。
- 暂无测试目标 — 欢迎在 `RepoMonitorTests/` 下为 `Models/` 或 `Services/` 逻辑添加 XCTest 覆盖。

---

## 安全说明

- RepoMonitor 不读取、不存储任何 Git 凭据。
- 远端 URL 在显示和记录日志前会自动去除内嵌的用户名/密码。
- 除对已配置远端执行 `git fetch` 外，应用不发起任何网络请求。

---

## 许可证

MIT，详见 [LICENSE](LICENSE)。
