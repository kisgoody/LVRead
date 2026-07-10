# iOS Notes Profile Bookshelf Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Document and prototype the iOS-only bottom navigation, notes, and profile statistics scope for LV Read.

**Architecture:** Keep `LV_Read_APP_需求文档.md` as the product overview. Add focused iOS module documents under `docs/requirements/ios/`. Add static UI references under `UI界面/` for iPhone, iPad, and Web so implementation can validate content and empty states before UIKit work starts.

**Tech Stack:** Markdown requirements, static HTML/CSS/vanilla JS prototypes, iOS UIKit implementation target.

## Global Constraints

- Current implementation scope is iOS only.
- UIKit only; SwiftUI is not allowed for native app implementation.
- Use Auto Layout and UIStackView in production iOS code.
- Use SF Symbols for native iOS icons.
- Minimum iOS touch target is 44pt.
- UI must support Dynamic Type, dark mode, safe areas, iPhone, and iPad.
- Static prototypes must not introduce third-party dependencies.

---

### Task 1: Update Main Product Requirements

**Files:**
- Modify: `LV_Read_APP_需求文档.md`

**Interfaces:**
- Consumes: existing product overview and reference UI files.
- Produces: v1.4 iOS-only navigation, modules, data models, and documentation entry points.

- [x] **Step 1: Update version and scope**

Set the document to v1.4, date 2026-07-08, and status `iOS 单端迭代中（当前阶段仅考虑 iOS）`.

- [x] **Step 2: Add bottom navigation baseline**

Add the three primary tabs: 书架、笔记、我的. Keep 阅读 as an immersive full-screen flow outside the bottom Tab bar.

- [x] **Step 3: Add data models**

Add `ReadingComment`, `ReadingBookmark`, and `ReadingStats` model contracts.

### Task 2: Add iOS Module Requirements

**Files:**
- Create: `docs/requirements/ios/bookshelf.md`
- Create: `docs/requirements/ios/notes.md`
- Create: `docs/requirements/ios/profile-stats.md`
- Create: `docs/requirements/ios/interfaces.md`
- Create: `docs/requirements/ios/README.md`

**Interfaces:**
- Consumes: v1.4 overview.
- Produces: module-scoped iOS requirements and repository protocols.

- [x] **Step 1: Split bookshelf requirements**

Document content state, empty state, interactions, and iOS acceptance criteria.

- [x] **Step 2: Split notes requirements**

Document comment and bookmark flows, reader marks, filters, empty states, and acceptance criteria.

- [x] **Step 3: Split profile statistics requirements**

Document reading, collection, and notes statistics plus late-night reading advice.

- [x] **Step 4: Split iOS interfaces**

Document Swift model contracts and Repository protocols.

### Task 3: Add Static UI References

**Files:**
- Create: `UI界面/lvread-ios-phone.html`
- Create: `UI界面/lvread-ios-pad.html`
- Create: `UI界面/lvread-ios-web.html`

**Interfaces:**
- Consumes: `UI界面/app-book-list.html` and `UI界面/book-list.html`.
- Produces: responsive static references for iPhone, iPad, and Web with content and empty states.

- [x] **Step 1: Build phone prototype**

Create a 390px-class phone shell with three bottom tabs and state toggles.

- [x] **Step 2: Build iPad prototype**

Create a split layout with sidebar navigation and detail panels.

- [x] **Step 3: Build Web prototype**

Create a wider responsive management view with top navigation and empty-state toggles.

### Task 4: Verify Artifacts

**Files:**
- Verify: all changed Markdown and HTML files.

**Interfaces:**
- Consumes: generated artifacts.
- Produces: final validation summary.

- [x] **Step 1: Run file listing**

Run: `find docs UI界面 -maxdepth 3 -type f -print`

- [x] **Step 2: Search for unresolved unfinished markers**

Run: `rg -n "(TO)(DO)|T[B]D|待[补]充|占[位]" LV_Read_APP_需求文档.md docs/requirements UI界面/lvread-ios-*.html`

- [x] **Step 3: Check git diff**

Run: `git diff --stat`
