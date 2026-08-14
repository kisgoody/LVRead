# iOS Notes Profile Bookshelf Design

## Design Brief

LVRead 当前阶段仅考虑 iOS 开发。一级导航固定为底部三栏：书架、笔记、我的。阅读页保持沉浸式全屏，不作为底部 Tab；评论与书签从阅读页触发，并在笔记 Tab 汇总。

## Visual Source

UI 参考 `UI界面/app-book-list.html` 与 `UI界面/book-list.html`：暖纸色背景、墨绿主色、克制卡片、书籍封面信息密度、8px 圆角、适合阅读类产品的安静质感。

## Architecture

- 主需求文档保留总览、全局约束、版本规划和验收基线。
- iOS 模块需求拆到 `docs/requirements/ios/`，按书架、笔记、我的统计、接口分文件维护。
- UI 原型放在 `UI界面/`，分别覆盖 iPhone、iPad、Web 参考布局，并提供有内容/无内容状态切换。

## Module Scope

### Bookshelf

书架是默认 Tab，负责本地藏书管理、继续阅读、导入、搜索、筛选、排序和编辑。空状态必须给出导入本地文件主 CTA，并保留同网传输次级入口。

### Notes

笔记 Tab 统计评论与书签。评论由阅读页长按段落触发，保存后在段落侧边显示评论标记。书签由阅读页下拉触发，再次下拉取消，并在阅读页显示书签标识。

### Profile

我的 Tab 展示阅读统计、藏书统计、笔记统计。阅读统计按日/月/年聚合阅读时长、阅读字数、阅读书籍数，并生成总结、夜读提醒和阅读建议。

## iOS Constraints

- UIKit only；禁止 SwiftUI。
- Auto Layout + UIStackView 分层，不硬编码 frame。
- MVC/MVVM 边界清晰，ViewController 只做调度。
- SF Symbols 用于 iOS 图标。
- 最小触控区域 44pt。
- 支持 Dynamic Type、深色模式、安全区、iPhone 和 iPad。

## Review

- 无未定义模块。
- 当前阶段明确排除 Android 实现。
- 评论、书签、统计、底部导航均有需求文档与接口落点。
- UI 原型覆盖有内容和空状态。
