# LAN-First Relay Discovery Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add zero-config LAN-first relay discovery so iPhone reconnects prefer same-Wi-Fi and private-overlay relay endpoints before falling back to the existing saved relay flow.

**Architecture:** Keep the relay protocol and secure handshake unchanged. Add a bridge-side Bonjour advertiser plus overlay hint publisher, then add an iPhone-side discovery coordinator that ranks local, overlay, and fallback relay candidates before calling the existing connection flow.

**Tech Stack:** Node.js, `ws`, Bonjour/mDNS publishing on the bridge, Swift `Network` framework browsing on iOS, existing secure transport and reconnect state.

---

### Task 1: Define bridge discovery metadata and advertiser tests

**Files:**
- Create: `phodex-bridge/src/local-relay-advertiser.js`
- Test: `phodex-bridge/test/local-relay-advertiser.test.js`

**Step 1: Write the failing test**

```js
test("buildAdvertisementMetadata omits session ids and secrets", () => {
  const metadata = buildAdvertisementMetadata({
    macDeviceId: "mac-1",
    displayName: "MacBook Pro",
    relayPort: 9000,
    sessionId: "session-secret",
    notificationSecret: "secret",
  });

  assert.equal(metadata.macDeviceId, "mac-1");
  assert.equal("sessionId" in metadata, false);
  assert.equal("notificationSecret" in metadata, false);
});
```

**Step 2: Run test to verify it fails**

Run: `cd phodex-bridge && node --test ./test/local-relay-advertiser.test.js`

Expected: FAIL because `local-relay-advertiser.js` does not exist.

**Step 3: Write minimal implementation**

```js
function buildAdvertisementMetadata(input) {
  return {
    macDeviceId: input.macDeviceId,
    displayName: input.displayName,
    relayPort: String(input.relayPort),
  };
}
```

**Step 4: Run test to verify it passes**

Run: `cd phodex-bridge && node --test ./test/local-relay-advertiser.test.js`

Expected: PASS

**Step 5: Commit**

```bash
git add phodex-bridge/src/local-relay-advertiser.js phodex-bridge/test/local-relay-advertiser.test.js
git commit -m "test(lan): 增加本地中继广播元数据测试"
```

### Task 2: Publish Bonjour advertisement from the bridge lifecycle

**Files:**
- Modify: `phodex-bridge/src/bridge.js`
- Modify: `phodex-bridge/src/local-relay-advertiser.js`
- Test: `phodex-bridge/test/local-relay-advertiser.test.js`

**Step 1: Write the failing test**

```js
test("createLocalRelayAdvertiser starts and stops with bridge lifecycle", () => {
  let started = 0;
  let stopped = 0;
  const advertiser = createLocalRelayAdvertiser({
    startImpl() { started += 1; },
    stopImpl() { stopped += 1; },
  });

  advertiser.start();
  advertiser.stop();

  assert.equal(started, 1);
  assert.equal(stopped, 1);
});
```

**Step 2: Run test to verify it fails**

Run: `cd phodex-bridge && node --test ./test/local-relay-advertiser.test.js`

Expected: FAIL because advertiser lifecycle methods are missing.

**Step 3: Write minimal implementation**

```js
function createLocalRelayAdvertiser({ startImpl, stopImpl }) {
  return {
    start() { startImpl?.(); },
    stop() { stopImpl?.(); },
  };
}
```

Update `bridge.js` so startup initializes the advertiser and shutdown stops it.

**Step 4: Run test to verify it passes**

Run: `cd phodex-bridge && node --test ./test/local-relay-advertiser.test.js`

Expected: PASS

**Step 5: Run targeted bridge regression tests**

Run: `cd phodex-bridge && node --test ./test/secure-transport.test.js ./test/macos-launch-agent.test.js`

Expected: PASS

**Step 6: Commit**

```bash
git add phodex-bridge/src/bridge.js phodex-bridge/src/local-relay-advertiser.js phodex-bridge/test/local-relay-advertiser.test.js
git commit -m "feat(lan): 接入桥接端局域网广播生命周期"
```

### Task 3: Extend trusted Mac models for discovery-aware candidate memory

**Files:**
- Modify: `CodexMobile/CodexMobile/Services/CodexSecureTransportModels.swift`
- Modify: `CodexMobile/CodexMobile/Services/CodexService+SecureTransport.swift`
- Test: `CodexMobile/CodexMobileTests/CodexSecurePairingStateTests.swift`

**Step 1: Write the failing test**

```swift
func testTrustedMacRecordPersistsLastSuccessfulLocalRelayURL() throws {
    var record = CodexTrustedMacRecord(
        macDeviceId: "mac-1",
        macIdentityPublicKey: "pub",
        lastPairedAt: Date()
    )

    record.lastLocalRelayURL = "ws://macbook-pro.local:9000/relay"
    XCTAssertEqual(record.lastLocalRelayURL, "ws://macbook-pro.local:9000/relay")
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -project CodexMobile/CodexMobile.xcodeproj -scheme CodexMobile -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:CodexMobileTests/CodexSecurePairingStateTests`

Expected: FAIL because the new fields do not exist.

**Step 3: Write minimal implementation**

```swift
var lastLocalRelayURL: String? = nil
var lastOverlayRelayURL: String? = nil
var lastDiscoveryAt: Date? = nil
```

Thread those fields through the secure transport persistence helpers.

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -project CodexMobile/CodexMobile.xcodeproj -scheme CodexMobile -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:CodexMobileTests/CodexSecurePairingStateTests`

Expected: PASS

**Step 5: Commit**

```bash
git add CodexMobile/CodexMobile/Services/CodexSecureTransportModels.swift CodexMobile/CodexMobile/Services/CodexService+SecureTransport.swift CodexMobile/CodexMobileTests/CodexSecurePairingStateTests.swift
git commit -m "feat(lan): 扩展受信任 Mac 发现状态模型"
```

### Task 4: Add iPhone discovery coordinator and candidate ranking tests

**Files:**
- Create: `CodexMobile/CodexMobile/Services/RelayDiscoveryCoordinator.swift`
- Create: `CodexMobile/CodexMobile/Services/RelayDiscoveryModels.swift`
- Test: `CodexMobile/CodexMobileTests/RelayDiscoveryCoordinatorTests.swift`

**Step 1: Write the failing test**

```swift
func testRankCandidatesPrefersBonjourThenOverlayThenSavedRelay() {
    let ranked = RelayDiscoveryCoordinator.rankCandidates([
        .savedRelay("wss://relay.example/relay"),
        .overlay("ws://mac-1.ts.net:9000/relay"),
        .bonjour("ws://macbook-pro.local:9000/relay")
    ])

    XCTAssertEqual(ranked.map(\.url.absoluteString), [
        "ws://macbook-pro.local:9000/relay",
        "ws://mac-1.ts.net:9000/relay",
        "wss://relay.example/relay"
    ])
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -project CodexMobile/CodexMobile.xcodeproj -scheme CodexMobile -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:CodexMobileTests/RelayDiscoveryCoordinatorTests`

Expected: FAIL because the coordinator does not exist.

**Step 3: Write minimal implementation**

```swift
enum RelayDiscoverySource: Int {
    case bonjour = 0
    case overlay = 1
    case savedRelay = 2
    case remoteResolve = 3
}
```

Implement ranking, filtering by `macDeviceId`, and URL normalization in the new coordinator.

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -project CodexMobile/CodexMobile.xcodeproj -scheme CodexMobile -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:CodexMobileTests/RelayDiscoveryCoordinatorTests`

Expected: PASS

**Step 5: Commit**

```bash
git add CodexMobile/CodexMobile/Services/RelayDiscoveryCoordinator.swift CodexMobile/CodexMobile/Services/RelayDiscoveryModels.swift CodexMobile/CodexMobileTests/RelayDiscoveryCoordinatorTests.swift
git commit -m "feat(lan): 增加 iOS 局域网发现协调器"
```

### Task 5: Route pairing and reconnect through ranked discovery candidates

**Files:**
- Modify: `CodexMobile/CodexMobile/Views/Home/ContentViewModel.swift`
- Modify: `CodexMobile/CodexMobile/Services/CodexService+Connection.swift`
- Modify: `CodexMobile/CodexMobile/Services/CodexService+TrustedPairPresentation.swift`
- Modify: `CodexMobile/CodexMobileTests/ContentViewModelReconnectTests.swift`
- Modify: `CodexMobile/CodexMobileTests/CodexServiceConnectionErrorTests.swift`

**Step 1: Write the failing test**

```swift
func testPreferredReconnectURLUsesBonjourCandidateBeforeSavedRelay() async {
    let codex = CodexService()
    let model = ContentViewModel()

    codex.discoveryTestOverride = [
        URL(string: "ws://macbook-pro.local:9000/relay")!,
        URL(string: "wss://relay.example/relay")!
    ]

    let url = await model.preferredReconnectURL(codex: codex)
    XCTAssertEqual(url, "ws://macbook-pro.local:9000/relay/live-session-1")
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -project CodexMobile/CodexMobile.xcodeproj -scheme CodexMobile -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:CodexMobileTests/ContentViewModelReconnectTests -only-testing:CodexMobileTests/CodexServiceConnectionErrorTests`

Expected: FAIL because reconnect still uses the single saved relay path.

**Step 3: Write minimal implementation**

```swift
let candidates = await codex.rankReconnectCandidates()
for candidate in candidates {
    if let fullURL = codex.buildReconnectURL(baseRelayURL: candidate.absoluteString) {
        return fullURL
    }
}
```

Make the first successful candidate update the remembered trusted Mac metadata.

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -project CodexMobile/CodexMobile.xcodeproj -scheme CodexMobile -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:CodexMobileTests/ContentViewModelReconnectTests -only-testing:CodexMobileTests/CodexServiceConnectionErrorTests`

Expected: PASS

**Step 5: Commit**

```bash
git add CodexMobile/CodexMobile/Views/Home/ContentViewModel.swift CodexMobile/CodexMobile/Services/CodexService+Connection.swift CodexMobile/CodexMobile/Services/CodexService+TrustedPairPresentation.swift CodexMobile/CodexMobileTests/ContentViewModelReconnectTests.swift CodexMobile/CodexMobileTests/CodexServiceConnectionErrorTests.swift
git commit -m "feat(lan): 让重连路径优先使用发现到的本地候选"
```

### Task 6: Document behavior and run end-to-end regression checks

**Files:**
- Modify: `CONTRIBUTING.md`
- Modify: `README.md`
- Test: `phodex-bridge/test/local-relay-advertiser.test.js`
- Test: `CodexMobile/CodexMobileTests/RelayDiscoveryCoordinatorTests.swift`

**Step 1: Write the failing doc checklist**

```md
- [ ] README explains LAN-first reconnect behavior
- [ ] CONTRIBUTING explains Bonjour advertisement and fallback order
- [ ] Manual verification covers same-Wi-Fi, Tailscale, and remote fallback
```

**Step 2: Update docs with the minimal explanation**

Add:

- how Bonjour advertisement works
- that private-overlay candidates are remembered internally
- that remote relay remains the fallback path

**Step 3: Run bridge regression tests**

Run: `cd phodex-bridge && node --test ./test/*.test.js`

Expected: PASS

**Step 4: Run relay regression tests**

Run: `cd relay && node --test ./*.test.js`

Expected: PASS

**Step 5: Run iOS targeted tests**

Run: `xcodebuild test -project CodexMobile/CodexMobile.xcodeproj -scheme CodexMobile -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:CodexMobileTests/CodexSecurePairingStateTests -only-testing:CodexMobileTests/RelayDiscoveryCoordinatorTests -only-testing:CodexMobileTests/ContentViewModelReconnectTests -only-testing:CodexMobileTests/CodexServiceConnectionErrorTests`

Expected: PASS

**Step 6: Commit**

```bash
git add README.md CONTRIBUTING.md
git commit -m "docs(lan): 补充局域网优先发现与回退说明"
```
