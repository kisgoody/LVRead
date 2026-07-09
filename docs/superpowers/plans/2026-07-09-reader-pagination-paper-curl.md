# Reader Pagination and Paper Curl Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make reader text layout deterministic and centered, eliminate missing characters between pages, and replace simulation mode with an interactive paper-curl animator.

**Architecture:** A shared `ReaderTextLayoutEngine` owns paragraph attributes, text rectangles, and CoreText pagination so measurement and drawing cannot diverge. A separate `PaperCurlAnimator` owns interactive rendering and physics, while `PageFlipAnimator` remains the mode dispatcher and reader controllers only prepare pages and forward gesture samples.

**Tech Stack:** Swift, UIKit, CoreText, CoreAnimation, XCTest, XcodeGen

## Global Constraints

- UIKit only; do not introduce SwiftUI or third-party dependencies.
- Preserve cover, slide, scroll, and no-animation page modes.
- Keep existing themes, fonts, percentage margins, watermarks, menus, and navigation.
- Use Auto Layout for persistent views; temporary animation layers may use bounds-derived frames.
- Every I/O, empty-content, zero-size, missing-page, snapshot-failure, cancellation, and cleanup path must recover safely.
- New production behavior must be introduced through a failing XCTest first.

---

## File Structure

- `LVRead/LVRead/UI/Reader/Layout/ReaderTextLayoutEngine.swift`: shared layout metrics, attributed text, safe CoreText pagination, and page-range validation.
- `LVRead/LVRead/UI/Reader/Animation/PaperCurlAnimator.swift`: gesture sampling, commit policy, spring timing, front/back page slices, lighting, and cleanup.
- `LVRead/LVRead/UI/Reader/Animation/PageFlipTypes.swift`: interaction sample and temporary animation state.
- `LVRead/LVRead/UI/Reader/Animation/PageFlipAnimator.swift`: dispatch `.simulation` to `PaperCurlAnimator`.
- `LVRead/LVRead/UI/Reader/ReaderViewController.swift`: draw through the shared layout engine and forward full pan data.
- `LVRead/LVRead/UI/Reader/ContinuousReaderViewController.swift`: paginate through the shared engine and forward full pan data.
- `LVRead/LVReadTests/ReaderTextLayoutEngineTests.swift`: range-continuity, Unicode, metrics, and alignment tests.
- `LVRead/LVReadTests/PaperCurlPhysicsTests.swift`: progress, commit, duration, and direction tests.

---

### Task 1: Shared reader text metrics

**Files:**
- Create: `LVRead/LVRead/UI/Reader/Layout/ReaderTextLayoutEngine.swift`
- Create: `LVRead/LVReadTests/ReaderTextLayoutEngineTests.swift`

**Interfaces:**
- Consumes: `ReadingSettings`, `FontManager`
- Produces:
  - `struct ReaderTextLayout`
  - `ReaderTextLayoutEngine.layout(pageSize:settings:) -> ReaderTextLayout`
  - `ReaderTextLayoutEngine.attributedString(content:settings:) -> NSAttributedString`

- [ ] **Step 1: Write the failing metrics and alignment tests**

```swift
import XCTest
@testable import LVRead

final class ReaderTextLayoutEngineTests: XCTestCase {
    func testTextRectIsHorizontallyCentered() {
        var settings = ReadingSettings.default
        settings.pageMarginHorizontal = 10
        let layout = ReaderTextLayoutEngine.layout(
            pageSize: CGSize(width: 400, height: 800),
            settings: settings
        )
        XCTAssertEqual(layout.textRect.minX, 40, accuracy: 0.001)
        XCTAssertEqual(400 - layout.textRect.maxX, 40, accuracy: 0.001)
    }

    func testParagraphUsesJustifiedAlignment() {
        let value = ReaderTextLayoutEngine.attributedString(
            content: "中文正文用于验证段落样式",
            settings: .default
        )
        let paragraph = value.attribute(
            .paragraphStyle,
            at: 0,
            effectiveRange: nil
        ) as? NSParagraphStyle
        XCTAssertEqual(paragraph?.alignment, .justified)
    }
}
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```bash
xcodebuild test -project LVRead/LVRead.xcodeproj -scheme LVRead -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:LVReadTests/ReaderTextLayoutEngineTests
```

Expected: compilation fails because `ReaderTextLayoutEngine` does not exist.

- [ ] **Step 3: Implement shared metrics and attributes**

```swift
import UIKit
import CoreText

struct ReaderTextLayout {
    let font: UIFont
    let paragraphStyle: NSParagraphStyle
    let textRect: CGRect
}

enum ReaderTextLayoutEngine {
    static func layout(pageSize: CGSize, settings: ReadingSettings) -> ReaderTextLayout {
        let safeSize = CGSize(width: max(pageSize.width, 1), height: max(pageSize.height, 1))
        let horizontal = CGFloat(settings.pageMarginHorizontal) * safeSize.width / 100
        let vertical = CGFloat(settings.pageMarginVertical) * safeSize.height / 100
        let font = FontManager.shared.font(
            named: settings.fontFamily,
            size: CGFloat(settings.fontSize)
        )
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = font.lineHeight * CGFloat(settings.lineSpacing - 1)
        paragraph.paragraphSpacing = font.lineHeight * CGFloat(settings.paragraphSpacing)
        paragraph.alignment = .justified
        return ReaderTextLayout(
            font: font,
            paragraphStyle: paragraph,
            textRect: CGRect(
                x: horizontal,
                y: vertical,
                width: max(safeSize.width - horizontal * 2, 1),
                height: max(safeSize.height - vertical * 2, 1)
            )
        )
    }

    static func attributedString(content: String, settings: ReadingSettings) -> NSAttributedString {
        let metrics = layout(pageSize: CGSize(width: 1, height: 1), settings: settings)
        return NSAttributedString(string: content, attributes: [
            .font: metrics.font,
            .paragraphStyle: metrics.paragraphStyle
        ])
    }
}
```

- [ ] **Step 4: Run the focused tests and verify GREEN**

Run the command from Step 2. Expected: 2 tests pass.

- [ ] **Step 5: Commit**

```bash
git add LVRead/LVRead/UI/Reader/Layout/ReaderTextLayoutEngine.swift LVRead/LVReadTests/ReaderTextLayoutEngineTests.swift
git commit -m "feat: centralize reader text metrics"
```

---

### Task 2: Lossless CoreText pagination

**Files:**
- Modify: `LVRead/LVRead/UI/Reader/Layout/ReaderTextLayoutEngine.swift`
- Modify: `LVRead/LVReadTests/ReaderTextLayoutEngineTests.swift`
- Modify: `LVRead/LVRead/UI/Reader/ContinuousReaderViewController.swift`
- Modify: `LVRead/LVRead/UI/Reader/ReaderViewController.swift`

**Interfaces:**
- Consumes: `ReaderTextLayoutEngine.layout(pageSize:settings:)`
- Produces:
  - `struct ReaderPageRange { let location: Int; let length: Int }`
  - `ReaderTextLayoutEngine.pageRanges(content:pageSize:settings:) throws -> [ReaderPageRange]`
  - `ReaderTextLayoutEngine.pages(content:chapter:chapterIndex:pageSize:settings:) throws -> [PageData]`

- [ ] **Step 1: Add failing continuity and Unicode tests**

```swift
func testPaginationPreservesEveryUTF16CodeUnit() throws {
    let content = String(repeating: "中文🙂e\u{301}，分页不可缺字。\n", count: 80)
    let pages = try ReaderTextLayoutEngine.pages(
        content: content,
        chapter: Chapter(title: "测试", startPosition: 0, endPosition: 0),
        chapterIndex: 0,
        pageSize: CGSize(width: 320, height: 480),
        settings: .default
    )
    XCTAssertEqual(pages.map(\.content).joined(), content)
    for pair in zip(pages, pages.dropFirst()) {
        XCTAssertEqual(pair.0.endCharOffset, pair.1.startCharOffset)
    }
    XCTAssertEqual(pages.last?.endCharOffset, content.utf16.count)
}

func testSmallPageNeverProducesZeroLengthRange() throws {
    var settings = ReadingSettings.default
    settings.fontSize = 32
    let ranges = try ReaderTextLayoutEngine.pageRanges(
        content: "一二三四五六七八九十",
        pageSize: CGSize(width: 80, height: 80),
        settings: settings
    )
    XCTAssertFalse(ranges.isEmpty)
    XCTAssertTrue(ranges.allSatisfy { $0.length > 0 })
}
```

- [ ] **Step 2: Run and verify RED**

Run the Task 1 test command. Expected: compilation fails because pagination APIs do not exist.

- [ ] **Step 3: Implement safe sequential ranges**

Implement a throwing loop around `CTFramesetterCreateFrame` and `CTFrameGetVisibleStringRange`. Clamp the CoreText range to `NSAttributedString.length`, reject zero progress with `ReaderTextLayoutError.noVisibleText(offset:)`, and slice content with `NSString.substring(with:)` so offsets and slices use the same UTF-16 coordinate system. Validate first offset, adjacency, positive lengths, and final offset before returning.

- [ ] **Step 4: Replace controller-local pagination**

Replace `paginateContent` and `ContinuousReaderViewController.paginate` bodies with calls to `ReaderTextLayoutEngine.pages`. Preserve their existing error-page behavior at the controller boundary. Change `PageContainerView.draw` to obtain `font`, `paragraphStyle`, and `textRect` from the engine, add foreground color to the returned attributes, and draw exactly that rectangle.

- [ ] **Step 5: Run focused and full tests**

```bash
xcodebuild test -project LVRead/LVRead.xcodeproj -scheme LVRead -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:LVReadTests/ReaderTextLayoutEngineTests
xcodebuild test -project LVRead/LVRead.xcodeproj -scheme LVRead -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

Expected: all tests pass and joined page text equals source text.

- [ ] **Step 6: Commit**

```bash
git add LVRead/LVRead/UI/Reader/Layout/ReaderTextLayoutEngine.swift LVRead/LVRead/UI/Reader/ReaderViewController.swift LVRead/LVRead/UI/Reader/ContinuousReaderViewController.swift LVRead/LVReadTests/ReaderTextLayoutEngineTests.swift
git commit -m "fix: make reader pagination lossless"
```

---

### Task 3: Paper curl physics policy

**Files:**
- Create: `LVRead/LVRead/UI/Reader/Animation/PaperCurlAnimator.swift`
- Create: `LVRead/LVReadTests/PaperCurlPhysicsTests.swift`

**Interfaces:**
- Produces:
  - `struct PaperCurlSample`
  - `enum PaperCurlPhysics`
  - `progress(translationX:pageWidth:) -> CGFloat`
  - `shouldCommit(progress:velocityX:direction:) -> Bool`
  - `completionDuration(progress:velocityX:pageWidth:) -> TimeInterval`

- [ ] **Step 1: Write failing policy tests**

```swift
import XCTest
@testable import LVRead

final class PaperCurlPhysicsTests: XCTestCase {
    func testShortSlowDragReturnsToCurrentPage() {
        XCTAssertFalse(PaperCurlPhysics.shouldCommit(
            progress: 0.20,
            velocityX: -200,
            direction: .next
        ))
    }

    func testFastVelocityInCorrectDirectionCommits() {
        XCTAssertTrue(PaperCurlPhysics.shouldCommit(
            progress: 0.10,
            velocityX: -700,
            direction: .next
        ))
    }

    func testOppositeVelocityDoesNotCommit() {
        XCTAssertFalse(PaperCurlPhysics.shouldCommit(
            progress: 0.10,
            velocityX: 700,
            direction: .next
        ))
    }
}
```

- [ ] **Step 2: Run and verify RED**

Run:

```bash
xcodebuild test -project LVRead/LVRead.xcodeproj -scheme LVRead -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:LVReadTests/PaperCurlPhysicsTests
```

Expected: compilation fails because `PaperCurlPhysics` does not exist.

- [ ] **Step 3: Implement deterministic physics**

Implement clamped progress, a `0.24` distance threshold, a `650 pt/s` directional velocity threshold, and completion duration clamped to `0.18...0.48` seconds based on remaining distance and absolute velocity.

- [ ] **Step 4: Run and verify GREEN**

Run the Step 2 command. Expected: all physics tests pass.

- [ ] **Step 5: Commit**

```bash
git add LVRead/LVRead/UI/Reader/Animation/PaperCurlAnimator.swift LVRead/LVReadTests/PaperCurlPhysicsTests.swift
git commit -m "feat: add paper curl physics"
```

---

### Task 4: Interactive front, back, and lighting renderer

**Files:**
- Modify: `LVRead/LVRead/UI/Reader/Animation/PaperCurlAnimator.swift`
- Modify: `LVRead/LVRead/UI/Reader/Animation/PageFlipTypes.swift`
- Modify: `LVRead/LVRead/UI/Reader/Animation/PageFlipAnimator.swift`

**Interfaces:**
- Consumes: `PaperCurlSample`, `PageFlipDirection`, current/next page views
- Produces:
  - `PaperCurlAnimator.beginInteractive(from:to:direction:container:state:)`
  - `PaperCurlAnimator.updateInteractive(sample:state:)`
  - `PaperCurlAnimator.finishInteractive(velocityX:state:completion:)`

- [ ] **Step 1: Add a failing cleanup regression test**

Add an XCTest that creates `PageFlipState`, attaches temporary views/layers, calls `cleanup()` twice, and verifies all references are `nil`, both page transforms are identity, current page alpha is `1`, and the completion guard cannot fire twice.

- [ ] **Step 2: Run and verify RED**

Run the paper-curl test target. Expected: the new state properties or restoration behavior are missing.

- [ ] **Step 3: Implement the renderer**

Build 16–24 front slices based on page width. For every gesture sample:

- calculate fold position from horizontal progress;
- calculate vertical curl center from the touch Y coordinate;
- apply perspective (`m34`), Y rotation, horizontal translation, and bounded vertical displacement per slice;
- create mirrored back-face slices from the same rendered image at `0.42...0.68` opacity over the current paper color;
- position a narrow high-light gradient at the fold;
- position a darker crease gradient beside it;
- project a wider soft shadow onto the already-rendered next page;
- keep the target page below all curl layers.

Use `UIViewPropertyAnimator` with spring timing for cancellation and distance/velocity duration for commit. Respect `UIAccessibility.isReduceMotionEnabled` with a short crossfade fallback. Snapshot failure must restore both pages and call completion once.

- [ ] **Step 4: Route simulation mode to the new file**

Replace all `SimulationAnimator` dispatch branches in `PageFlipAnimator` with `PaperCurlAnimator`. Keep `SimulationAnimator.swift` unreferenced for one compatibility cycle; do not delete it in this task.

- [ ] **Step 5: Run focused tests and build**

```bash
xcodebuild test -project LVRead/LVRead.xcodeproj -scheme LVRead -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:LVReadTests/PaperCurlPhysicsTests
xcodebuild build -project LVRead/LVRead.xcodeproj -scheme LVRead -sdk iphonesimulator -configuration Debug
```

Expected: tests pass and Debug build exits 0.

- [ ] **Step 6: Commit**

```bash
git add LVRead/LVRead/UI/Reader/Animation/PaperCurlAnimator.swift LVRead/LVRead/UI/Reader/Animation/PageFlipTypes.swift LVRead/LVRead/UI/Reader/Animation/PageFlipAnimator.swift LVRead/LVReadTests/PaperCurlPhysicsTests.swift
git commit -m "feat: render interactive paper curl"
```

---

### Task 5: Controller gesture integration and final verification

**Files:**
- Modify: `LVRead/LVRead/UI/Reader/ReaderViewController.swift`
- Modify: `LVRead/LVRead/UI/Reader/ContinuousReaderViewController.swift`
- Modify: `LVRead/LVRead/UI/Reader/Animation/PageFlipAnimator.swift`
- Modify: `LVRead/project.yml` only if source discovery does not include the new directories

**Interfaces:**
- Consumes: `PaperCurlSample(location:translation:velocity:containerSize:)`
- Produces: complete tap and pan behavior in `.simulation` mode

- [ ] **Step 1: Update interactive dispatcher signatures**

Make `PageFlipAnimator.updateInteractive` accept a full `PaperCurlSample` and pass it only to `.simulation`; cover and slide continue using `sample.progress`. Make finish accept horizontal velocity so simulation uses `PaperCurlPhysics`, while other modes retain the controller-provided commit decision.

- [ ] **Step 2: Forward full gesture samples from both controllers**

At `.began`, render and lay out the target page before snapshotting. At `.changed`, pass location, translation, velocity, and container size. At `.ended`/`.cancelled`, pass final velocity and force cancellation for `.cancelled`. Set and clear `isPageFlipping` on every success, cancellation, missing-page, and snapshot-failure path.

- [ ] **Step 3: Verify new files belong to both targets**

Run `xcodegen generate --spec LVRead/project.yml` only if the checked-in project does not discover new source/test files. Review the generated project diff and ensure no unrelated project settings changed.

- [ ] **Step 4: Run fresh full verification**

```bash
xcodebuild test -project LVRead/LVRead.xcodeproj -scheme LVRead -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
xcodebuild build -project LVRead/LVRead.xcodeproj -scheme LVRead -sdk iphonesimulator -configuration Debug
git diff --check
```

Expected: all tests pass, build exits 0, and `git diff --check` produces no output.

- [ ] **Step 5: Perform simulator interaction checks**

Verify simulation mode with slow drag, fast flick, insufficient drag, reversal, cancellation, previous-page drag, first/last page, font-size change, margin change, portrait/landscape, light/dark themes, and Reduce Motion. Confirm adjacent page text joins without missing or duplicated characters and that no blank frame appears.

- [ ] **Step 6: Commit**

```bash
git add LVRead/LVRead/UI/Reader/ReaderViewController.swift LVRead/LVRead/UI/Reader/ContinuousReaderViewController.swift LVRead/LVRead/UI/Reader/Animation/PageFlipAnimator.swift LVRead/LVRead.xcodeproj/project.pbxproj LVRead/project.yml
git commit -m "feat: integrate gesture-driven paper turns"
```
