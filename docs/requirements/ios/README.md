# LVRead iOS 模块需求索引

当前阶段仅考虑 iOS 开发，本文档目录用于拆分 `LV_Read_APP_需求文档.md` 中的模块需求和接口。

## 文档结构

| 文件 | 范围 |
|---|---|
| `bookshelf.md` | 书架 Tab：藏书列表、继续阅读、导入、搜索、筛选、空状态 |
| `reader.md` | 阅读模块：连续页流、缓存窗口、阅读设置、评论/书签入口、异常状态 |
| `notes.md` | 笔记 Tab：评论、书签、阅读页标记、筛选、统计 |
| `profile-stats.md` | 我的 Tab：阅读统计、藏书统计、笔记统计、阅读建议 |
| `reading-advice.md` | 阅读建议：统计规则、时间段细分、优先级、95 条话术和防重复机制 |
| `interfaces.md` | iOS 模型、Repository 协议、统计服务、错误处理 |

## 全局 iOS 约束

- UIKit only，禁止 SwiftUI。
- Auto Layout + UIStackView 分层，禁止硬编码 Frame。
- iPhone 最小触控区域 44pt。
- 支持 Dynamic Type、VoiceOver、深色模式和安全区。
- 视觉参考 `UI界面/app-book-list.html` 与 `UI界面/book-list.html`。
- 生产代码颜色、间距、字号必须抽离为常量。
