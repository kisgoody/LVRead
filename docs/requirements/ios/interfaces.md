# iOS 内部接口与数据模型

## 需求拆解

本文档定义书架、阅读、笔记、我的统计在 iOS 阶段需要的内部模型和 Repository 协议。LVRead 为纯本地应用，不依赖远程服务端。

## 模型

```swift
struct ReadingComment: Equatable, Codable {
    let id: String
    let bookId: String
    let chapterId: String
    let pageIndex: Int
    let paragraphIndex: Int
    let selectedText: String
    let commentText: String
    let progressPercent: Double
    let createdAt: Date
    let updatedAt: Date
}

struct ReadingBookmark: Equatable, Codable {
    let id: String
    let bookId: String
    let chapterId: String
    let pageIndex: Int
    let paragraphIndex: Int?
    let progressPercent: Double
    let excerpt: String
    let createdAt: Date
}

struct ReadingStatsEntry: Equatable, Codable {
    let id: String
    let bookId: String
    let date: String
    let durationSeconds: Int
    let wordCount: Int
    let pageCount: Int
    let sessionCount: Int
    let firstReadAt: Date
    let lastReadAt: Date
    let isLateNight: Bool
}

enum StatsPeriod: String, Codable {
    case day
    case month
    case year
}

struct ReaderPageKey: Hashable, Codable {
    let bookId: String
    let chapterIndex: Int
    let pageIndex: Int
}

struct ReaderPage: Equatable, Codable {
    let key: ReaderPageKey
    let chapterId: String
    let chapterTitle: String
    let startCharOffset: Int
    let endCharOffset: Int
    let content: String
    let progressPercent: Double
}

struct ReaderWindow: Equatable, Codable {
    let center: ReaderPageKey
    let pages: [ReaderPage]
    let hasPreviousPage: Bool
    let hasNextPage: Bool
}

struct ReadingSession: Equatable {
    let bookId: String
    let startedAt: Date
    let endedAt: Date
    let effectiveDurationSeconds: Int
    let uniqueWordCount: Int
    let uniquePageCount: Int
    let isLateNight: Bool
    let dateKey: String
}
```

## Repository 协议

```swift
protocol NotesRepository {
    func addComment(_ comment: ReadingComment) -> Result<ReadingComment, LVError>
    func updateComment(_ comment: ReadingComment) -> Result<ReadingComment, LVError>
    func deleteComment(commentId: String) -> Result<Void, LVError>
    func comments(bookId: String?) -> Result<[ReadingComment], LVError>

    func toggleBookmark(_ bookmark: ReadingBookmark) -> Result<Bool, LVError>
    func deleteBookmark(bookmarkId: String) -> Result<Void, LVError>
    func bookmarks(bookId: String?) -> Result<[ReadingBookmark], LVError>
}

protocol ReaderPagingService {
    func loadInitialWindow(bookId: String, chapterIndex: Int, pageIndex: Int) -> Result<ReaderWindow, LVError>
    func loadNextPage(from key: ReaderPageKey) -> Result<ReaderWindow, LVError>
    func loadPreviousPage(from key: ReaderPageKey) -> Result<ReaderWindow, LVError>
    func jumpToChapter(bookId: String, chapterIndex: Int) -> Result<ReaderWindow, LVError>
    func jumpToProgress(bookId: String, progressPercent: Double) -> Result<ReaderWindow, LVError>
    func clearWindow(bookId: String) -> Result<Void, LVError>
}

protocol ReadingProgressRepository {
    func saveProgress(bookId: String, key: ReaderPageKey, progressPercent: Double) -> Result<Void, LVError>
    func loadProgress(bookId: String) -> Result<ReaderPageKey?, LVError>
}

protocol ReadingStatsRepository {
    func recordSession(_ entry: ReadingStatsEntry) -> Result<Void, LVError>
    func stats(period: StatsPeriod, from startDate: Date, to endDate: Date) -> Result<[ReadingStatsEntry], LVError>
    func collectionSummary() -> Result<CollectionSummary, LVError>
    func noteSummary() -> Result<NoteSummary, LVError>
}

struct CollectionSummary: Equatable {
    let totalBooks: Int
    let readingBooks: Int
    let queuedBooks: Int
    let finishedBooks: Int
    let formatDistribution: [String: Int]
    let sourceDistribution: [String: Int]
}

struct NoteSummary: Equatable {
    let commentCount: Int
    let bookmarkCount: Int
    let mostAnnotatedBookIds: [String]
    let latestActivityAt: Date?
}
```

## ViewModel 输出

```swift
struct NotesViewState: Equatable {
    let isLoading: Bool
    let selectedFilter: NotesFilter
    let comments: [ReadingComment]
    let bookmarks: [ReadingBookmark]
    let errorMessage: String?
    let isEmpty: Bool
}

struct ReaderViewState: Equatable {
    let isLoading: Bool
    let currentPage: ReaderPage?
    let window: ReaderWindow?
    let isToolbarVisible: Bool
    let isBookmarked: Bool
    let commentParagraphIndexes: Set<Int>
    let errorMessage: String?
}

enum NotesFilter: String, Codable {
    case all
    case comments
    case bookmarks
}

struct ProfileStatsViewState: Equatable {
    let period: StatsPeriod
    let readingDurationSeconds: Int
    let wordCount: Int
    let activeBookCount: Int
    let summaryText: String
    let sleepReminder: String?
    let collectionSummary: CollectionSummary
    let noteSummary: NoteSummary
    let isEmpty: Bool
    let errorMessage: String?
}
```

## 异常处理

| 错误 | 触发 | 用户提示 |
|---|---|---|
| `E_COMMENT_EMPTY` | 保存空评论 | 「评论内容不能为空」 |
| `E_COMMENT_TOO_LONG` | 评论超过 1000 字 | 「评论最多 1000 字」 |
| `E_BOOKMARK_DUPLICATE` | 重复创建同页书签 | 自动取消或返回已存在状态 |
| `E_NOTE_NOT_FOUND` | 回到原文时笔记已删除 | 「该笔记已不存在」 |
| `E_READER_FILE_MISSING` | 阅读文件不存在 | 「文件已被移动或删除」 |
| `E_READER_PAGE_LOAD_FAILED` | 页面加载失败 | 「页面加载失败，请重试」 |
| `E_READER_WINDOW_EMPTY` | 当前窗口无可读页面 | 「该章节暂无可阅读内容」 |
| `E_READER_SETTINGS_INVALID` | 阅读设置参数越界 | 「阅读设置无效，已恢复默认值」 |
| `E_STATS_WRITE_FAILED` | 统计写入失败 | 「阅读统计暂未保存，将稍后重试」 |
| `E_STATS_QUERY_FAILED` | 统计查询失败 | 「统计加载失败，请稍后重试」 |

## 数据库建议

| 表 | 关键字段 |
|---|---|
| `reading_comments` | `id`, `book_id`, `chapter_id`, `page_index`, `paragraph_index`, `selected_text`, `comment_text`, `progress_percent`, `created_at`, `updated_at` |
| `reading_bookmarks` | `id`, `book_id`, `chapter_id`, `page_index`, `paragraph_index`, `progress_percent`, `excerpt`, `created_at` |
| `reading_stats_entries` | `id`, `book_id`, `date`, `duration_seconds`, `word_count`, `page_count`, `session_count`, `first_read_at`, `last_read_at`, `is_late_night` |
| `reading_progress` | `book_id`, `chapter_index`, `page_index`, `progress_percent`, `updated_at` |

## 调用示例

```swift
let result = notesRepository.toggleBookmark(bookmark)
switch result {
case .success(let isBookmarked):
    viewState = viewState.withBookmarkState(isBookmarked)
case .failure(let error):
    toast.show(error.userMessage)
}
```
