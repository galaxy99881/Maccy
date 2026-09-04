# Maccy 纯文本无限历史增强版

> [!IMPORTANT]
> 这是 [Maccy](https://github.com/p0deje/Maccy) 的个人增强分支，不是官方发行版。官方项目和唯一官方网站分别是 [p0deje/Maccy](https://github.com/p0deje/Maccy) 和 [maccy.app](https://maccy.app)。

> [!WARNING]
> 通过 Homebrew 或官方 Releases 安装的是官方版，不包含本仓库的增强功能。请警惕仿冒 Maccy 的恶意网站。

[中文](#中文) · [English](#english)

---

## 中文

### 项目定位

本分支为需要长期保留大量文本片段的使用场景设计。核心思路是：无限保留纯文本，分页加载，减少图片和富文本带来的内存、磁盘与界面压力。

它保留 Maccy 原有的菜单栏体验、搜索、方向键导航、回车选择、置顶和自动粘贴等能力。

### 与官方版的主要区别

| 功能 | 官方 Maccy | 本增强分支 |
| --- | --- | --- |
| 历史上限 | 设置界面上限为 999 | 增加“无限纯文本”模式，`historySize = 0` 表示无限 |
| 无限模式存储 | 无专用无限模式 | 仅保存纯文本；丢弃新图片、文件、HTML 和 RTF；跳过超过 10 MB 的文本 |
| 大历史加载 | 基于官方默认历史模型 | 启动只加载全部置顶项和最近 200 条，滚动时分页读取更旧记录 |
| 搜索 | 搜索当前历史集合 | 无限模式从数据库按需取候选项，避免先加载全部记录 |
| 条目快捷键 | 为最近项和置顶项显示数字/字母快捷键 | 已移除这套显示、映射和按键监听；保留全局唤出及方向键/回车操作 |
| 置顶区 | 直接展示置顶项 | 超过 8 条后使用独立限高滚动区和懒加载，支持自动滚动到键盘选中项 |
| 置顶管理 | 修改单条置顶内容及键位 | 增加搜索、多选、全选、批量取消置顶和批量删除 |
| 备份与恢复 | 无内置完整历史导出/导入流程 | 增加“导出备份”和“导入并恢复”，备份使用 SQLite 一致性快照并附带版本信息 |
| 历史清理 | 主要支持清空历史 | 增加“清除全部图片”和“仅保留纯文本”，执行前强提醒备份 |
| 自动粘贴 | 依赖 macOS 辅助功能权限 | 增加权限提示、原应用焦点恢复和短延迟，降低模拟 `⌘V` 发给 Maccy 自己的概率 |
| 旧数据修复 | 依赖官方版本实现 | 启动时清理孤立内容并修正可能导致 CoreText 卡死的旧标题 |
| Xcode 兼容 | 以官方当前开发环境为准 | 对 macOS 26 专用视觉 API 做条件编译，可使用 Xcode 16.4 构建 |

### 清理操作说明

- **清除全部图片**：混合记录保留纯文本并移除图片数据；没有纯文本的图片记录会整条删除。
- **仅保留纯文本**：移除图片、文件、HTML、RTF 和其他格式；没有纯文本的记录会整条删除。
- 这些操作无法撤销。请先在“偏好设置 → 存储 → 备份”中导出完整备份。

### 安装与构建

本仓库目前以源码形式提供增强版。

```sh
git clone https://github.com/galaxy99881/Maccy.git
cd Maccy
open Maccy.xcodeproj
```

使用 Xcode 选择 `Maccy` scheme 后构建。项目要求 macOS 14 或更高版本。

> [!CAUTION]
> 本分支当前仍使用官方 Bundle ID `org.p0deje.Maccy`。不要把官方版、测试版和本分支同时放在 `/Applications` 中，否则 macOS 可能把辅助功能权限关联到错误副本。建议只保留一个 `/Applications/Maccy.app`，其他副本移到单独的备份目录。

### 使用

1. 使用 <kbd>⇧</kbd> + <kbd>⌘</kbd> + <kbd>C</kbd> 打开 Maccy，或点击菜单栏图标。
2. 输入关键词搜索，用方向键选择。
3. 按 <kbd>Return</kbd> 或点击记录。开启“自动粘贴”后会直接粘贴到原应用。
4. 用 <kbd>⌥</kbd> + <kbd>P</kbd> 置顶或取消置顶。
5. 按 <kbd>⌘</kbd> + <kbd>,</kbd> 打开偏好设置。

自动粘贴需要在“系统设置 → 隐私与安全性 → 辅助功能”中允许当前 `/Applications/Maccy.app`。

---

## English

### Project scope

This is a personal enhanced fork for users who want to retain a large, long-lived collection of text snippets. Its central design is unlimited plain-text history with paged loading, while avoiding the memory, disk, and UI cost of images and rich clipboard formats.

It retains Maccy's menu-bar experience, search, arrow-key navigation, Return selection, pins, and automatic paste.

### Main differences from official Maccy

| Feature | Official Maccy | This enhanced fork |
| --- | --- | --- |
| History limit | Settings UI is capped at 999 items | Adds Unlimited Plain Text mode; `historySize = 0` is the unlimited sentinel |
| Unlimited-mode storage | No dedicated unlimited mode | Stores plain text only; discards new images, files, HTML, and RTF; skips text larger than 10 MB |
| Large-history loading | Uses the official default history model | Loads all pins plus only the 200 most recent items at launch, then fetches older pages while scrolling |
| Search | Searches the active history collection | Fetches database candidates on demand in unlimited mode instead of loading the entire history first |
| Per-item shortcuts | Shows number/letter shortcuts for recent and pinned items | Removes their display, mapping, and key handling; global popup and arrow/Return controls remain |
| Pinned area | Displays pinned items directly | Uses a lazy, height-limited scroll area after 8 pins and scrolls to keyboard selections |
| Pin management | Edits an individual pin and its key | Adds search, multiple selection, Select All, bulk unpin, and bulk delete |
| Backup and restore | No built-in full-history export/import workflow | Adds Export Backup and Import & Restore using a consistent SQLite snapshot and versioned manifest |
| History cleanup | Primarily clears history as a whole | Adds Remove All Images and Keep Plain Text Only, with a strong backup warning |
| Automatic paste | Relies on macOS Accessibility permission | Adds permission prompting, previous-app focus restoration, and a short delay before simulated `⌘V` |
| Legacy-store repair | Depends on the official release implementation | Cleans orphaned content and sanitizes legacy titles that can hang CoreText |
| Xcode compatibility | Follows the official current development environment | Conditionally compiles macOS 26-only visual APIs so the app builds with Xcode 16.4 |

### Cleanup behavior

- **Remove All Images** keeps plain text in mixed entries and removes their image data. Image entries without plain text are deleted entirely.
- **Keep Plain Text Only** removes images, files, HTML, RTF, and other formats. Entries without plain text are deleted entirely.
- These operations cannot be undone. Export a complete backup from **Preferences → Storage → Backup** first.

### Install and build

The enhanced edition is currently distributed as source code in this repository.

```sh
git clone https://github.com/galaxy99881/Maccy.git
cd Maccy
open Maccy.xcodeproj
```

Select the `Maccy` scheme in Xcode and build. The project targets macOS 14 or later.

> [!CAUTION]
> This fork currently retains the official bundle identifier, `org.p0deje.Maccy`. Do not keep the official app, a test build, and this fork together in `/Applications`; macOS may attach Accessibility permission to the wrong copy. Keep only one `/Applications/Maccy.app` and move other copies to a separate backup directory.

### Usage

1. Press <kbd>⇧</kbd> + <kbd>⌘</kbd> + <kbd>C</kbd>, or click the menu-bar icon, to open Maccy.
2. Type to search and use the arrow keys to navigate.
3. Press <kbd>Return</kbd> or click an item. With Paste automatically enabled, it is pasted into the previously active app.
4. Press <kbd>⌥</kbd> + <kbd>P</kbd> to pin or unpin the selected item.
5. Press <kbd>⌘</kbd> + <kbd>,</kbd> to open Preferences.

Automatic paste requires the current `/Applications/Maccy.app` to be enabled in **System Settings → Privacy & Security → Accessibility**.

## Upstream and license

Maccy was created and is maintained upstream by [Alex Rodionov (p0deje)](https://github.com/p0deje). This fork builds on that work and remains available under the [MIT License](./LICENSE).

For official downloads, documentation, support, and releases, use:

- [Official repository: p0deje/Maccy](https://github.com/p0deje/Maccy)
- [Official website: maccy.app](https://maccy.app)
