# Multi-Computer Pairing Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Let one iPhone pair with, manage, and switch between multiple computers while keeping only one active connection target at a time.

**Architecture:** Keep the existing trusted-host registry, add explicit active-host selection, route reconnect through the selected host, and expose that model through compact Home and Settings UI. Extend bridge and relay metadata only with backwards-compatible optional fields so Windows/macOS hosts can be presented correctly without rewriting the transport.

**Tech Stack:** SwiftUI, Observation, XCTest, Node.js bridge, Node.js relay, Keychain-backed secure store, existing Liquid Glass compatibility helpers.

---

### Task 1: Lock Down Active Host Selection Semantics

**Files:**
- Modify: `CodexMobile/CodexMobileTests/CodexSecurePairingStateTests.swift`
- Modify: `CodexMobile/CodexMobileTests/ContentViewModelReconnectTests.swift`
- Modify: `CodexMobile/CodexMobile/Services/CodexService.swift`
- Modify: `CodexMobile/CodexMobile/Services/SecureStore.swift`
- Modify: `CodexMobile/CodexMobile/Services/CodexService+SecureTransport.swift`

**Step 1: Write the failing tests**

Add tests that prove:

- an explicitly selected host wins over most-recent fallback
- scanning a QR for host B makes host B active without deleting host A
- forgetting host B preserves host A and falls back correctly

**Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme CodexMobile -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:CodexMobileTests/CodexSecurePairingStateTests -only-testing:CodexMobileTests/ContentViewModelReconnectTests`

Expected: FAIL because active-host selection helpers and persistence do not exist yet.

**Step 3: Write minimal implementation**

Add:

- a new secure store key for active host selection
- `selectedHostDeviceId` state on `CodexService`
- helper accessors that resolve explicit selection before recency fallback
- QR pairing path that preserves multiple records and promotes the scanned host to active

**Step 4: Run tests to verify they pass**

Run the same `xcodebuild test` command.

Expected: PASS.

**Step 5: Commit**

```bash
git add CodexMobile/CodexMobileTests/CodexSecurePairingStateTests.swift CodexMobile/CodexMobileTests/ContentViewModelReconnectTests.swift CodexMobile/CodexMobile/Services/CodexService.swift CodexMobile/CodexMobile/Services/SecureStore.swift CodexMobile/CodexMobile/Services/CodexService+SecureTransport.swift
git commit -m "feat(pairing): add explicit active host selection"
```

### Task 2: Add Host Platform Metadata and Presentation Models

**Files:**
- Modify: `CodexMobile/CodexMobile/Services/CodexSecureTransportModels.swift`
- Modify: `CodexMobile/CodexMobile/Services/CodexService+TrustedPairPresentation.swift`
- Modify: `CodexMobile/CodexMobile/Services/CodexService+SecureTransport.swift`
- Modify: `CodexMobile/CodexMobile/Views/QRScannerPairingValidator.swift`
- Test: `CodexMobile/CodexMobileTests/CodexSecurePairingStateTests.swift`

**Step 1: Write the failing tests**

Add tests covering:

- host records decoding when optional platform metadata is missing
- presentation choosing platform label/icon metadata correctly

**Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme CodexMobile -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:CodexMobileTests/CodexSecurePairingStateTests`

Expected: FAIL due to missing platform-aware model and presentation paths.

**Step 3: Write minimal implementation**

Add:

- optional platform field to pairing payload, trusted host record, and resolve response
- compatibility defaults for legacy payloads
- a host-summary presentation model for list UIs

**Step 4: Run tests to verify they pass**

Run the same focused test command.

Expected: PASS.

**Step 5: Commit**

```bash
git add CodexMobile/CodexMobile/Services/CodexSecureTransportModels.swift CodexMobile/CodexMobile/Services/CodexService+TrustedPairPresentation.swift CodexMobile/CodexMobile/Services/CodexService+SecureTransport.swift CodexMobile/CodexMobile/Views/QRScannerPairingValidator.swift CodexMobile/CodexMobileTests/CodexSecurePairingStateTests.swift
git commit -m "feat(pairing): add host metadata for multi-computer UI"
```

### Task 3: Route Trusted Reconnect Through the Selected Host

**Files:**
- Modify: `CodexMobile/CodexMobile/Views/Home/ContentViewModel.swift`
- Modify: `CodexMobile/CodexMobile/Services/CodexService+Connection.swift`
- Modify: `CodexMobile/CodexMobile/Services/CodexService+SecureTransport.swift`
- Test: `CodexMobile/CodexMobileTests/ContentViewModelReconnectTests.swift`

**Step 1: Write the failing tests**

Add tests proving:

- reconnect resolves the selected host first
- offline selected host preserves selection and surfaces correct message
- saved relay session fallback does not silently switch to another remembered host

**Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme CodexMobile -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:CodexMobileTests/ContentViewModelReconnectTests`

Expected: FAIL because reconnect still depends on implicit preferred-host behavior.

**Step 3: Write minimal implementation**

Update reconnect helpers so:

- selected host drives trusted resolve
- clearing a dead saved relay session stays scoped to that host
- forgetting one host does not destabilize other records

**Step 4: Run tests to verify they pass**

Run the same test command.

Expected: PASS.

**Step 5: Commit**

```bash
git add CodexMobile/CodexMobile/Views/Home/ContentViewModel.swift CodexMobile/CodexMobile/Services/CodexService+Connection.swift CodexMobile/CodexMobile/Services/CodexService+SecureTransport.swift CodexMobile/CodexMobileTests/ContentViewModelReconnectTests.swift
git commit -m "feat(pairing): reconnect through selected host"
```

### Task 4: Build Shared Multi-Computer UI Components

**Files:**
- Create: `CodexMobile/CodexMobile/Views/Shared/PairedComputerRowView.swift`
- Create: `CodexMobile/CodexMobile/Views/Shared/PairedComputersSheet.swift`
- Modify: `CodexMobile/CodexMobile/Views/Shared/TrustedPairSummaryView.swift`
- Modify: `CodexMobile/CodexMobile/Views/Shared/AdaptiveGlassModifier.swift`
- Test: `CodexMobile/CodexMobileTests/` existing or new focused UI-state tests as needed

**Step 1: Write the failing tests**

Add targeted tests where practical for:

- summary model exposing switch affordance state
- list ordering with selected host first

If no existing UI test harness fits, write model-level tests for the ordering and selection state that back these views.

**Step 2: Run tests to verify they fail**

Run the relevant focused `xcodebuild test` command for the added model/UI-state tests.

Expected: FAIL because shared paired-computer presentation logic is missing.

**Step 3: Write minimal implementation**

Create:

- a reusable paired computer row
- a native sheet listing paired computers
- restrained glass styling using `adaptiveGlass` only on high-value summary elements

**Step 4: Run tests to verify they pass**

Run the same focused test command.

Expected: PASS.

**Step 5: Commit**

```bash
git add CodexMobile/CodexMobile/Views/Shared/PairedComputerRowView.swift CodexMobile/CodexMobile/Views/Shared/PairedComputersSheet.swift CodexMobile/CodexMobile/Views/Shared/TrustedPairSummaryView.swift CodexMobile/CodexMobile/Views/Shared/AdaptiveGlassModifier.swift
git commit -m "feat(pairing): add shared paired-computer switcher UI"
```

### Task 5: Wire Home, Settings, and Sidebar to the New Host Model

**Files:**
- Modify: `CodexMobile/CodexMobile/Views/Home/HomeEmptyStateView.swift`
- Modify: `CodexMobile/CodexMobile/Views/SettingsView.swift`
- Modify: `CodexMobile/CodexMobile/Views/SidebarView.swift`
- Modify: `CodexMobile/CodexMobile/Services/CodexService+TrustedPairPresentation.swift`
- Possibly modify: `CodexMobile/CodexMobile/Views/Sidebar/SidebarFloatingSettingsButton.swift`

**Step 1: Write the failing tests**

Add model-level tests that prove:

- Home uses the selected host summary
- Settings lists multiple paired hosts and keeps the selected one first
- forgetting one host only removes that host from presentation

**Step 2: Run tests to verify they fail**

Run the relevant focused `xcodebuild test` command.

Expected: FAIL because the views still assume a single visible pair.

**Step 3: Write minimal implementation**

Update:

- Home to show current computer + switch sheet
- Settings to show `Paired Computers` management section
- Sidebar footer to reflect the selected computer cleanly

Keep copy neutral: use `Computer` instead of `Mac` in user-facing surfaces where reasonable.

**Step 4: Run tests to verify they pass**

Run the same focused test command.

Expected: PASS.

**Step 5: Commit**

```bash
git add CodexMobile/CodexMobile/Views/Home/HomeEmptyStateView.swift CodexMobile/CodexMobile/Views/SettingsView.swift CodexMobile/CodexMobile/Views/SidebarView.swift CodexMobile/CodexMobile/Services/CodexService+TrustedPairPresentation.swift CodexMobile/CodexMobile/Views/Sidebar/SidebarFloatingSettingsButton.swift
git commit -m "feat(pairing): expose multi-computer controls in app UI"
```

### Task 6: Extend Bridge and Relay Metadata Without Breaking Compatibility

**Files:**
- Modify: `phodex-bridge/src/secure-transport.js`
- Modify: `phodex-bridge/src/bridge.js`
- Modify: `relay/relay.js`
- Modify: `relay/server.test.js`
- Modify: `phodex-bridge/test/secure-device-state.test.js` only if needed

**Step 1: Write the failing tests**

Add tests showing:

- QR payload includes optional platform metadata
- relay resolve response includes display name and platform metadata
- legacy requests without platform still behave correctly

**Step 2: Run tests to verify they fail**

Run: `npm test --prefix relay`

Expected: FAIL for new metadata expectations.

Run if needed: `npm test --prefix phodex-bridge`

Expected: FAIL if bridge payload tests were added there.

**Step 3: Write minimal implementation**

Add optional metadata only:

- bridge QR payload includes host platform and display hint
- relay registration/resolve flow forwards platform data
- keep old clients safe when fields are absent

**Step 4: Run tests to verify they pass**

Run the same `npm test --prefix relay` and, if used, `npm test --prefix phodex-bridge`.

Expected: PASS.

**Step 5: Commit**

```bash
git add phodex-bridge/src/secure-transport.js phodex-bridge/src/bridge.js relay/relay.js relay/server.test.js phodex-bridge/test/secure-device-state.test.js
git commit -m "feat(pairing): extend bridge and relay host metadata"
```

### Task 7: Device Verification on Lin's iPhone

**Files:**
- Modify only if required by signing/runtime issues discovered during verification

**Step 1: Prepare the app for device run**

Use Xcode automatic signing and the available local team/account setup. Do not change project signing settings more than necessary.

**Step 2: Install and run on `Lin's iPhone`**

Open the project in Xcode and run the app on the connected device.

Expected: app installs and launches under direct development signing.

**Step 3: Manual verification**

Check:

1. pair macOS host
2. pair Windows host
3. switch active computer from Home
4. switch and manage computers from Settings
5. relaunch app and confirm selected host reconnect path
6. forget one host and confirm the other remains

**Step 4: Fix only the blocking runtime issues**

If signing or runtime errors block installation, make the smallest targeted changes necessary and re-run.

**Step 5: Final verification**

Re-run the focused automated tests and then repeat the shortest manual device path to confirm no regression.

**Step 6: Commit**

```bash
git add -A
git commit -m "feat(pairing): verify multi-computer flow on device"
```
