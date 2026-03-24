# LAN Promotion Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 让 iPhone 在已通过远端 relay 连上后，也能在后续发现同一局域网内的同一台 Mac 时自动切换到局域网连接。

**Architecture:** 在 `ContentViewModel` 中新增一条轻量的 LAN promotion 流程，仅在当前路径为 `Remote relay` 时触发短时 Bonjour 发现。命中同一 `macDeviceId` 的 LAN 候选后，复用现有 secure reconnect 逻辑主动迁移到局域网；失败时回退到原有远端路径，并通过冷却机制避免抖动。

**Tech Stack:** Swift, SwiftUI, existing `CodexService` reconnect/discovery helpers, XCTest.

---

### Task 1: Add failing promotion tests

**Files:**
- Modify: `CodexMobile/CodexMobileTests/ContentViewModelReconnectTests.swift`
- Test: `CodexMobile/CodexMobileTests/ContentViewModelReconnectTests.swift`

**Step 1: Write the failing test**

Add focused tests for:
- connected remote relay + matching Bonjour candidate => promotion reconnect uses LAN URL
- already LAN direct => no promotion attempt
- Bonjour candidate for another Mac => no promotion attempt
- LAN promotion failure => falls back to existing reconnect path

**Step 2: Run test to verify it fails**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project CodexMobile/CodexMobile.xcodeproj -scheme CodexMobile -derivedDataPath /Users/linhemin/Library/Developer/Xcode/DerivedData/CodexMobile-bunfosfionynmidluyntrxljpypq -destination 'platform=iOS Simulator,OS=26.3.1,name=iPhone 17' -only-testing:CodexMobileTests/ContentViewModelReconnectTests
```

Expected: FAIL because promotion orchestration does not exist yet.

**Step 3: Commit**

```bash
git add CodexMobile/CodexMobileTests/ContentViewModelReconnectTests.swift
git commit -m "test(ios): 为局域网自动提升补充红灯测试"
```

### Task 2: Implement minimal LAN promotion orchestration

**Files:**
- Modify: `CodexMobile/CodexMobile/Views/Home/ContentViewModel.swift`
- Modify: `CodexMobile/CodexMobile/Services/CodexService.swift`
- Modify: `CodexMobile/CodexMobile/Services/CodexService+Connection.swift`

**Step 1: Write minimal implementation**

- Add promotion guards and cooldown state
- Add `attemptLANPromotionIfNeeded`
- Trigger it after successful connect and on foreground reconnect entry points
- Reuse `discoverBonjourReconnectCandidates`, `rankReconnectCandidates`, `buildReconnectURL`, and existing connect/disconnect flow

**Step 2: Run focused tests to verify it passes**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project CodexMobile/CodexMobile.xcodeproj -scheme CodexMobile -derivedDataPath /Users/linhemin/Library/Developer/Xcode/DerivedData/CodexMobile-bunfosfionynmidluyntrxljpypq -destination 'platform=iOS Simulator,OS=26.3.1,name=iPhone 17' -only-testing:CodexMobileTests/ContentViewModelReconnectTests
```

Expected: PASS.

**Step 3: Commit**

```bash
git add CodexMobile/CodexMobile/Views/Home/ContentViewModel.swift CodexMobile/CodexMobile/Services/CodexService.swift CodexMobile/CodexMobile/Services/CodexService+Connection.swift CodexMobile/CodexMobileTests/ContentViewModelReconnectTests.swift
git commit -m "feat(ios): 支持已连接远端后的局域网自动提升"
```

### Task 3: Run targeted regression verification

**Files:**
- Test: `CodexMobile/CodexMobileTests/ContentViewModelReconnectTests.swift`
- Test: `CodexMobile/CodexMobileTests/CodexServiceConnectionErrorTests.swift`
- Test: `CodexMobile/CodexMobileTests/RelayDiscoveryCoordinatorTests.swift`

**Step 1: Run targeted regression tests**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project CodexMobile/CodexMobile.xcodeproj -scheme CodexMobile -derivedDataPath /Users/linhemin/Library/Developer/Xcode/DerivedData/CodexMobile-bunfosfionynmidluyntrxljpypq -destination 'platform=iOS Simulator,OS=26.3.1,name=iPhone 17' -only-testing:CodexMobileTests/ContentViewModelReconnectTests -only-testing:CodexMobileTests/CodexServiceConnectionErrorTests -only-testing:CodexMobileTests/RelayDiscoveryCoordinatorTests
```

Expected: PASS with no regression in reconnect ordering or connection-path labeling.
