# Background Connection Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add an opt-in-on-first-use background connection feature that uses Live Activity plus location-based keepalive to keep the iOS app connected as much as possible while backgrounded or locked, with clear user disclosure and a Settings toggle.

**Architecture:** Keep `CodexService` as the source of truth for connection state and add a thin background-connection coordinator that reacts to app lifecycle, connection state, and user preference. Isolate `CLLocationManager` and `ActivityKit` behind dedicated services so the UI and core transport logic stay decoupled and unit-testable.

**Tech Stack:** SwiftUI, Observation, CoreLocation, ActivityKit, WidgetKit, UserDefaults, existing `CodexService`, Xcode project target configuration

---

### Task 1: Add persisted preference model and service seams

**Files:**
- Create: `CodexMobile/CodexMobile/Models/BackgroundConnectionPreference.swift`
- Modify: `CodexMobile/CodexMobile/Services/CodexService.swift`
- Test: `CodexMobile/CodexMobileTests/BackgroundConnectionPreferenceTests.swift`

**Step 1: Write the failing test**

```swift
@MainActor
func testPreferenceRoundTripsFirstPromptAndEnablement() {
    let defaults = UserDefaults(suiteName: #function)!
    defaults.removePersistentDomain(forName: #function)

    var preference = BackgroundConnectionPreference.load(defaults: defaults)
    XCTAssertFalse(preference.hasPresentedFirstRunPrompt)
    XCTAssertFalse(preference.isEnabled)

    preference.hasPresentedFirstRunPrompt = true
    preference.isEnabled = true
    preference.save(defaults: defaults)

    let reloaded = BackgroundConnectionPreference.load(defaults: defaults)
    XCTAssertTrue(reloaded.hasPresentedFirstRunPrompt)
    XCTAssertTrue(reloaded.isEnabled)
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -project CodexMobile/CodexMobile.xcodeproj -scheme CodexMobile -destination 'generic/platform=iOS Simulator' -only-testing:CodexMobileTests/BackgroundConnectionPreferenceTests`
Expected: FAIL because `BackgroundConnectionPreference` does not exist yet.

Note: Per `AGENTS.md`, do not actually run Xcode build/test unless the user explicitly asks during execution.

**Step 3: Write minimal implementation**

```swift
struct BackgroundConnectionPreference: Codable, Equatable {
    var hasPresentedFirstRunPrompt: Bool
    var isEnabled: Bool

    static func load(defaults: UserDefaults) -> Self { ... }
    func save(defaults: UserDefaults) { ... }
}
```

Also add the smallest `CodexService` projection needed for the future coordinator, such as a readonly snapshot exposing `isConnected`, `connectionPhase`, `hasAnyRunningTurn`, and `isAppInForeground`.

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -project CodexMobile/CodexMobile.xcodeproj -scheme CodexMobile -destination 'generic/platform=iOS Simulator' -only-testing:CodexMobileTests/BackgroundConnectionPreferenceTests`
Expected: PASS.

**Step 5: Commit**

```bash
git add CodexMobile/CodexMobile/Models/BackgroundConnectionPreference.swift CodexMobile/CodexMobile/Services/CodexService.swift CodexMobile/CodexMobileTests/BackgroundConnectionPreferenceTests.swift
git commit -m "feat(background): 增加后台连接偏好模型"
```

### Task 2: Add the location keepalive service

**Files:**
- Create: `CodexMobile/CodexMobile/Services/BackgroundLocationKeepaliveService.swift`
- Test: `CodexMobile/CodexMobileTests/BackgroundLocationKeepaliveServiceTests.swift`

**Step 1: Write the failing test**

```swift
@MainActor
func testStartKeepaliveConfiguresManagerForBackgroundUpdates() {
    let manager = FakeLocationManager()
    let service = BackgroundLocationKeepaliveService(manager: manager)

    service.startKeepaliveIfPossible()

    XCTAssertTrue(manager.allowsBackgroundLocationUpdates)
    XCTAssertFalse(manager.pausesLocationUpdatesAutomatically)
    XCTAssertEqual(manager.startUpdatingLocationCallCount, 1)
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -project CodexMobile/CodexMobile.xcodeproj -scheme CodexMobile -destination 'generic/platform=iOS Simulator' -only-testing:CodexMobileTests/BackgroundLocationKeepaliveServiceTests`
Expected: FAIL because the service and fake manager do not exist yet.

Note: Per `AGENTS.md`, do not actually run Xcode build/test unless the user explicitly asks during execution.

**Step 3: Write minimal implementation**

```swift
protocol BackgroundLocationManaging: AnyObject {
    var authorizationStatus: CLAuthorizationStatus { get }
    var allowsBackgroundLocationUpdates: Bool { get set }
    var pausesLocationUpdatesAutomatically: Bool { get set }
    func requestWhenInUseAuthorization()
    func requestAlwaysAuthorization()
    func startUpdatingLocation()
    func stopUpdatingLocation()
    func startMonitoringSignificantLocationChanges()
    func stopMonitoringSignificantLocationChanges()
}

@MainActor
final class BackgroundLocationKeepaliveService: NSObject {
    func requestFullAuthorization() { ... }
    func startKeepaliveIfPossible() { ... }
    func stopKeepalive() { ... }
}
```

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -project CodexMobile/CodexMobile.xcodeproj -scheme CodexMobile -destination 'generic/platform=iOS Simulator' -only-testing:CodexMobileTests/BackgroundLocationKeepaliveServiceTests`
Expected: PASS.

**Step 5: Commit**

```bash
git add CodexMobile/CodexMobile/Services/BackgroundLocationKeepaliveService.swift CodexMobile/CodexMobileTests/BackgroundLocationKeepaliveServiceTests.swift
git commit -m "feat(background): 增加定位保活服务"
```

### Task 3: Add the Live Activity domain model and service

**Files:**
- Create: `CodexMobile/CodexMobile/Models/BackgroundConnectionLiveActivityAttributes.swift`
- Create: `CodexMobile/CodexMobile/Services/LiveActivityService.swift`
- Create: `CodexMobile/RemodexBackgroundActivity/RemodexBackgroundActivityBundle.swift`
- Create: `CodexMobile/RemodexBackgroundActivity/RemodexBackgroundConnectionWidget.swift`
- Modify: `CodexMobile/CodexMobile.xcodeproj/project.pbxproj`

**Step 1: Write the failing test**

```swift
@MainActor
func testLiveActivityStateMapsConnectedBackgroundKeepalive() {
    let state = BackgroundConnectionLiveActivityState.make(
        isConnected: true,
        isKeepingAliveInBackground: true,
        hasPermissionIssue: false
    )

    XCTAssertEqual(state.title, "Keeping alive in background")
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -project CodexMobile/CodexMobile.xcodeproj -scheme CodexMobile -destination 'generic/platform=iOS Simulator' -only-testing:CodexMobileTests/BackgroundConnectionLiveActivityStateTests`
Expected: FAIL because the state model does not exist yet.

Note: Per `AGENTS.md`, do not actually run Xcode build/test unless the user explicitly asks during execution.

**Step 3: Write minimal implementation**

```swift
struct BackgroundConnectionLiveActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var title: String
        var detail: String
        var isConnected: Bool
    }

    var name: String
}

@MainActor
final class LiveActivityService {
    func startOrUpdate(state: BackgroundConnectionLiveActivityAttributes.ContentState) async { ... }
    func end() async { ... }
}
```

Add a Widget Extension target at `CodexMobile/RemodexBackgroundActivity` and wire it in `project.pbxproj`.

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -project CodexMobile/CodexMobile.xcodeproj -scheme CodexMobile -destination 'generic/platform=iOS Simulator' -only-testing:CodexMobileTests/BackgroundConnectionLiveActivityStateTests`
Expected: PASS.

**Step 5: Commit**

```bash
git add CodexMobile/CodexMobile/Models/BackgroundConnectionLiveActivityAttributes.swift CodexMobile/CodexMobile/Services/LiveActivityService.swift CodexMobile/RemodexBackgroundActivity CodexMobile/CodexMobile.xcodeproj/project.pbxproj
git commit -m "feat(background): 增加实时活动展示"
```

### Task 4: Add the background connection coordinator

**Files:**
- Create: `CodexMobile/CodexMobile/Services/BackgroundConnectionCoordinator.swift`
- Modify: `CodexMobile/CodexMobile/CodexMobileApp.swift`
- Modify: `CodexMobile/CodexMobile/ContentView.swift`
- Modify: `CodexMobile/CodexMobile/Services/CodexService.swift`
- Test: `CodexMobile/CodexMobileTests/BackgroundConnectionCoordinatorTests.swift`

**Step 1: Write the failing test**

```swift
@MainActor
func testBackgroundTransitionStartsKeepaliveWhenFeatureEnabledAndConnected() async {
    let location = FakeBackgroundLocationKeepaliveService()
    let activity = FakeLiveActivityService()
    let coordinator = BackgroundConnectionCoordinator(
        preference: .init(hasPresentedFirstRunPrompt: true, isEnabled: true),
        locationService: location,
        liveActivityService: activity
    )

    await coordinator.handleSnapshot(.init(isConnected: true, hasAnyRunningTurn: true, isAppInForeground: false))

    XCTAssertTrue(location.didStartKeepalive)
    XCTAssertEqual(activity.lastState?.title, "Keeping alive in background")
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -project CodexMobile/CodexMobile.xcodeproj -scheme CodexMobile -destination 'generic/platform=iOS Simulator' -only-testing:CodexMobileTests/BackgroundConnectionCoordinatorTests`
Expected: FAIL because the coordinator does not exist yet.

Note: Per `AGENTS.md`, do not actually run Xcode build/test unless the user explicitly asks during execution.

**Step 3: Write minimal implementation**

```swift
@MainActor
final class BackgroundConnectionCoordinator {
    var shouldPresentFirstRunPrompt: Bool { ... }

    func markFirstRunPromptPresented() { ... }
    func enableFeatureAndRequestPermissions() async { ... }
    func disableFeature() async { ... }
    func handleSnapshot(_ snapshot: CodexServiceConnectionSnapshot) async { ... }
}
```

Wire the coordinator into app launch and scene phase changes, but keep all transport ownership inside `CodexService`.

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -project CodexMobile/CodexMobile.xcodeproj -scheme CodexMobile -destination 'generic/platform=iOS Simulator' -only-testing:CodexMobileTests/BackgroundConnectionCoordinatorTests`
Expected: PASS.

**Step 5: Commit**

```bash
git add CodexMobile/CodexMobile/Services/BackgroundConnectionCoordinator.swift CodexMobile/CodexMobile/CodexMobileApp.swift CodexMobile/CodexMobile/ContentView.swift CodexMobile/CodexMobile/Services/CodexService.swift CodexMobile/CodexMobileTests/BackgroundConnectionCoordinatorTests.swift
git commit -m "feat(background): 接入后台连接协调器"
```

### Task 5: Add first-run prompt and Settings UI

**Files:**
- Modify: `CodexMobile/CodexMobile/ContentView.swift`
- Modify: `CodexMobile/CodexMobile/Views/SettingsView.swift`
- Test: `CodexMobile/CodexMobileTests/SettingsBackgroundConnectionPresentationTests.swift`

**Step 1: Write the failing test**

```swift
@MainActor
func testSettingsShowsLimitedStateWhenAlwaysPermissionMissing() {
    let status = SettingsBackgroundConnectionPresentation.make(
        isEnabled: true,
        authorization: .authorizedWhenInUse,
        isKeepingAlive: false
    )

    XCTAssertEqual(status.title, "Enabled, limited")
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -project CodexMobile/CodexMobile.xcodeproj -scheme CodexMobile -destination 'generic/platform=iOS Simulator' -only-testing:CodexMobileTests/SettingsBackgroundConnectionPresentationTests`
Expected: FAIL because the presentation mapping does not exist yet.

Note: Per `AGENTS.md`, do not actually run Xcode build/test unless the user explicitly asks during execution.

**Step 3: Write minimal implementation**

```swift
enum SettingsBackgroundConnectionPresentation {
    case disabled
    case permissionRequired
    case enabledLimited
    case enabledActive
}
```

Add:

- first-run disclosure alert/sheet in `ContentView`
- Settings card with toggle, status copy, disclosure copy, and deep link to system settings

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -project CodexMobile/CodexMobile.xcodeproj -scheme CodexMobile -destination 'generic/platform=iOS Simulator' -only-testing:CodexMobileTests/SettingsBackgroundConnectionPresentationTests`
Expected: PASS.

**Step 5: Commit**

```bash
git add CodexMobile/CodexMobile/ContentView.swift CodexMobile/CodexMobile/Views/SettingsView.swift CodexMobile/CodexMobileTests/SettingsBackgroundConnectionPresentationTests.swift
git commit -m "feat(background): 增加首次提示与设置页开关"
```

### Task 6: Add Info.plist and entitlement-facing configuration

**Files:**
- Modify: `CodexMobile/BuildSupport/CodexMobile-Info.plist`
- Modify: `CodexMobile/CodexMobile.xcodeproj/project.pbxproj`

**Step 1: Write the failing test**

There is no practical isolated unit test for plist wiring. Use a configuration inspection step during execution.

**Step 2: Verify configuration is currently missing**

Run: `rg -n "NSSupportsLiveActivities|NSLocationWhenInUseUsageDescription|NSLocationAlwaysAndWhenInUseUsageDescription|<string>location</string>" CodexMobile/BuildSupport/CodexMobile-Info.plist`
Expected: no matches for the new keys before implementation.

**Step 3: Write minimal implementation**

Add:

- `NSSupportsLiveActivities`
- `NSLocationWhenInUseUsageDescription`
- `NSLocationAlwaysAndWhenInUseUsageDescription`
- `location` to `UIBackgroundModes`

Also ensure the new widget target is wired in `project.pbxproj`.

**Step 4: Verify configuration is present**

Run: `rg -n "NSSupportsLiveActivities|NSLocationWhenInUseUsageDescription|NSLocationAlwaysAndWhenInUseUsageDescription|<string>location</string>" CodexMobile/BuildSupport/CodexMobile-Info.plist`
Expected: all new keys appear exactly once and the background mode list contains `location`.

**Step 5: Commit**

```bash
git add CodexMobile/BuildSupport/CodexMobile-Info.plist CodexMobile/CodexMobile.xcodeproj/project.pbxproj
git commit -m "feat(background): 增加后台连接系统配置"
```

### Task 7: Documentation and final verification

**Files:**
- Modify: `README.md`
- Modify: `AGENTS.md`
- Modify: `CLAUDE.md`

**Step 1: Write the failing doc expectation**

Document that iOS now has an optional background-connection mode using Live Activity plus location keepalive, and that it is battery-expensive and user-controlled.

**Step 2: Verify docs are currently missing this feature**

Run: `rg -n "后台保持连接|Live Activity|定位保活|background connection" README.md AGENTS.md CLAUDE.md`
Expected: no mention of the new user-facing feature.

**Step 3: Write minimal implementation**

Update docs only if needed to reflect the new local-first iOS behavior and its guardrails. Keep wording local-first and do not add hosted-service assumptions.

**Step 4: Verify docs are updated**

Run: `rg -n "后台保持连接|Live Activity|定位保活|background connection" README.md AGENTS.md CLAUDE.md`
Expected: README mentions the feature and any repo guardrails remain aligned between `AGENTS.md` and `CLAUDE.md`.

**Step 5: Commit**

```bash
git add README.md AGENTS.md CLAUDE.md
git commit -m "docs(background): 补充后台连接说明"
```
