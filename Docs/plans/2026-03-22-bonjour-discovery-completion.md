# Bonjour Discovery Completion Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Finish real Bonjour-based LAN discovery so reconnect prefers live local-network results before remembered overlay and saved relay fallbacks.

**Architecture:** Upgrade the bridge-side advertiser into a real Bonjour publisher, add an iOS Bonjour browser that resolves relay candidates for the preferred trusted Mac, then merge those live candidates into the existing reconnect ranking path. Keep secure handshake and relay protocol unchanged.

**Tech Stack:** Node.js (`dns-sd` subprocess on macOS), Swift `NetServiceBrowser`/`NetService`, existing CodexMobile reconnect orchestration, `node:test`, XCTest.

---

### Task 1: Publish a real Bonjour service from the bridge

**Files:**
- Modify: `phodex-bridge/src/local-relay-advertiser.js`
- Modify: `phodex-bridge/src/bridge.js`
- Test: `phodex-bridge/test/local-relay-advertiser.test.js`
- Test: `phodex-bridge/test/bridge-lifecycle.test.js`

**Step 1: Write the failing tests**

Add tests that assert:

- `createLocalRelayAdvertiser` calls a real publish implementation with service type `_remodex._tcp`
- TXT metadata includes `macDeviceId`, `displayName`, `relayPath`, `protocolVersion`
- publisher failure resets `isRunning`
- bridge lifecycle still stops the publisher on shutdown/error

**Step 2: Run tests to verify they fail**

Run: `cd phodex-bridge && node --test ./test/local-relay-advertiser.test.js ./test/bridge-lifecycle.test.js`

Expected: FAIL because the advertiser is still a metadata-only stub.

**Step 3: Write minimal implementation**

- use the built-in macOS `dns-sd` publisher instead of a new Node dependency
- wrap a publisher instance inside `createLocalRelayAdvertiser`
- publish `_remodex._tcp`
- derive `relayPath` from the configured relay URL
- keep errors non-fatal to bridge startup

**Step 4: Run tests to verify they pass**

Run: `cd phodex-bridge && node --test ./test/local-relay-advertiser.test.js ./test/bridge-lifecycle.test.js`

Expected: PASS

**Step 5: Commit**

```bash
git add phodex-bridge/package.json phodex-bridge/package-lock.json phodex-bridge/src/local-relay-advertiser.js phodex-bridge/src/bridge.js phodex-bridge/test/local-relay-advertiser.test.js phodex-bridge/test/bridge-lifecycle.test.js
git commit -m "feat(lan): 接通 bridge Bonjour 广播"
```

### Task 2: Add an iOS Bonjour discovery browser

**Files:**
- Create: `CodexMobile/CodexMobile/Services/RelayBonjourBrowser.swift`
- Test: `CodexMobile/CodexMobileTests/RelayBonjourBrowserTests.swift`
- Modify: `CodexMobile/CodexMobile.xcodeproj/project.pbxproj`

**Step 1: Write the failing tests**

Add tests that assert:

- a Bonjour TXT record + endpoint become a normalized relay base URL
- results are filtered by `macDeviceId`
- malformed or incomplete TXT records are ignored

**Step 2: Run tests to verify they fail**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project CodexMobile/CodexMobile.xcodeproj -scheme CodexMobile -destination 'platform=iOS Simulator,name=iPhone 16e' -only-testing:CodexMobileTests/RelayBonjourBrowserTests`

Expected: FAIL because the browser and tests do not exist yet.

**Step 3: Write minimal implementation**

- introduce a small browser abstraction over `NetServiceBrowser` / `NetService`
- parse TXT fields into `RelayDiscoveryCandidate.bonjour(...)`
- normalize relay URLs through `RelayDiscoveryCoordinator`
- keep the browser short-lived and timeout-based

**Step 4: Run tests to verify they pass**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project CodexMobile/CodexMobile.xcodeproj -scheme CodexMobile -destination 'platform=iOS Simulator,name=iPhone 16e' -only-testing:CodexMobileTests/RelayBonjourBrowserTests`

Expected: PASS

**Step 5: Commit**

```bash
git add CodexMobile/CodexMobile/Services/RelayBonjourBrowser.swift CodexMobile/CodexMobileTests/RelayBonjourBrowserTests.swift CodexMobile/CodexMobile.xcodeproj/project.pbxproj
git commit -m "feat(lan): 增加 iOS Bonjour 发现浏览器"
```

### Task 3: Feed live Bonjour candidates into reconnect orchestration

**Files:**
- Modify: `CodexMobile/CodexMobile/Services/CodexService.swift`
- Modify: `CodexMobile/CodexMobile/Views/Home/ContentViewModel.swift`
- Modify: `CodexMobile/CodexMobile/Services/CodexService+Connection.swift`
- Test: `CodexMobile/CodexMobileTests/ContentViewModelReconnectTests.swift`
- Test: `CodexMobile/CodexMobileTests/CodexServiceConnectionErrorTests.swift`

**Step 1: Write the failing tests**

Add tests that assert:

- live Bonjour results rank ahead of remembered `lastLocalRelayURL`
- denied local-network permission skips Bonjour and still falls back to overlay/saved relay

**Step 2: Run tests to verify they fail**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project CodexMobile/CodexMobile.xcodeproj -scheme CodexMobile -destination 'platform=iOS Simulator,name=iPhone 16e' -only-testing:CodexMobileTests/ContentViewModelReconnectTests -only-testing:CodexMobileTests/CodexServiceConnectionErrorTests`

Expected: FAIL because reconnect still has no live Bonjour browse source.

**Step 3: Write minimal implementation**

- add a short-lived browser call before reconnect ranking
- merge live Bonjour candidates with remembered candidates
- keep fallback order and secure-session behavior unchanged

**Step 4: Run tests to verify they pass**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project CodexMobile/CodexMobile.xcodeproj -scheme CodexMobile -destination 'platform=iOS Simulator,name=iPhone 16e' -only-testing:CodexMobileTests/ContentViewModelReconnectTests -only-testing:CodexMobileTests/CodexServiceConnectionErrorTests`

Expected: PASS

**Step 5: Commit**

```bash
git add CodexMobile/CodexMobile/Services/CodexService.swift CodexMobile/CodexMobile/Views/Home/ContentViewModel.swift CodexMobile/CodexMobile/Services/CodexService+Connection.swift CodexMobile/CodexMobileTests/ContentViewModelReconnectTests.swift CodexMobile/CodexMobileTests/CodexServiceConnectionErrorTests.swift
git commit -m "feat(lan): 让重连优先使用实时 Bonjour 结果"
```

### Task 4: Run full regressions and update docs

**Files:**
- Modify: `README.md`
- Modify: `CONTRIBUTING.md`

**Step 1: Update docs**

Document that:

- bridge now publishes `_remodex._tcp`
- iOS now actively browses Bonjour before reconnect
- overlay candidates remain memory-based fallback

**Step 2: Run bridge regressions**

Run: `cd phodex-bridge && node --test ./test/*.test.js`

Expected: PASS

**Step 3: Run relay regressions**

Run: `cd relay && node --test ./*.test.js`

Expected: PASS

**Step 4: Run iOS targeted regressions**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project CodexMobile/CodexMobile.xcodeproj -scheme CodexMobile -destination 'platform=iOS Simulator,name=iPhone 16e' -only-testing:CodexMobileTests/CodexSecurePairingStateTests -only-testing:CodexMobileTests/RelayDiscoveryCoordinatorTests -only-testing:CodexMobileTests/RelayBonjourBrowserTests -only-testing:CodexMobileTests/ContentViewModelReconnectTests -only-testing:CodexMobileTests/CodexServiceConnectionErrorTests`

Expected: PASS

**Step 5: Commit**

```bash
git add README.md CONTRIBUTING.md
git commit -m "docs(lan): 补充 Bonjour 自动发现说明"
```
