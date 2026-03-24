# Connection Path Status Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 在设置页显示当前实际连接路径，让用户判断当前连接是否走局域网。

**Architecture:** 在 `CodexService` 服务层新增一个只读连接路径状态，复用已有 relay host 分类逻辑生成 UI 标签。设置页只负责读取并渲染，不参与路径判断。

**Tech Stack:** Swift, SwiftUI, existing `CodexService` connection helpers, XCTest.

---

### Task 1: Add a service-level connection path status

**Files:**
- Modify: `CodexMobile/CodexMobile/Services/CodexService.swift`
- Modify: `CodexMobile/CodexMobile/Services/CodexService+Connection.swift`
- Test: `CodexMobile/CodexMobileTests/CodexServiceConnectionPathTests.swift`

**Step 1: Write the failing test**

Add tests for:
- disconnected => `未连接`
- local relay URL => `局域网直连`
- overlay relay URL => `私网 Overlay`
- remote relay URL => `远端 Relay`

**Step 2: Run test to verify it fails**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project CodexMobile/CodexMobile.xcodeproj -scheme CodexMobile -derivedDataPath /Users/linhemin/Library/Developer/Xcode/DerivedData/CodexMobile-bunfosfionynmidluyntrxljpypq -destination 'platform=iOS Simulator,OS=26.3.1,name=iPhone 17' -only-testing:CodexMobileTests/CodexServiceConnectionPathTests
```

Expected: fail because the new connection-path API does not exist yet.

**Step 3: Write minimal implementation**

- Add a small enum or computed presentation type for current connection path.
- Reuse `relayHostCategory(for:)`.
- Use current `relayUrl` and `isConnected` to derive the label.

**Step 4: Run test to verify it passes**

Run the same command and expect PASS.

### Task 2: Show the status in Settings

**Files:**
- Modify: `CodexMobile/CodexMobile/Views/SettingsView.swift`
- Test: `CodexMobile/CodexMobileTests/CodexServiceConnectionPathTests.swift`

**Step 1: Write the failing test**

Extend service-level test coverage if needed so the UI-facing label is fixed and stable.

**Step 2: Run test to verify it fails**

Run the same targeted test command and confirm the new expectation fails for the missing label.

**Step 3: Write minimal implementation**

- Add a `连接路径` row in the existing `Connection` settings card.
- Show the label only when a trusted pair summary exists or a relay URL is present.
- Keep the UI read-only and compact.

**Step 4: Run test to verify it passes**

Run the targeted iOS test command again and expect PASS.

### Task 3: Regression verification

**Files:**
- Test: `CodexMobile/CodexMobileTests/CodexServiceConnectionPathTests.swift`
- Test: `CodexMobile/CodexMobileTests/ContentViewModelReconnectTests.swift`

**Step 1: Run targeted regression tests**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project CodexMobile/CodexMobile.xcodeproj -scheme CodexMobile -derivedDataPath /Users/linhemin/Library/Developer/Xcode/DerivedData/CodexMobile-bunfosfionynmidluyntrxljpypq -destination 'platform=iOS Simulator,OS=26.3.1,name=iPhone 17' -only-testing:CodexMobileTests/CodexServiceConnectionPathTests -only-testing:CodexMobileTests/ContentViewModelReconnectTests
```

Expected: PASS with no reconnect regressions.
