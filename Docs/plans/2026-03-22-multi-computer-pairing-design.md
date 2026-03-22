# Multi-Computer Pairing Design

Date: 2026-03-22

## Goal

Allow one iPhone to pair with and switch between multiple computers while keeping the current transport model single-active-host. The first implementation must support:

- multiple remembered computers on iPhone
- one explicitly selected active computer at a time
- explicit switching from Home and Settings
- compatibility with macOS and Windows hosts
- clean future expansion toward multiple simultaneously online hosts

## Constraints

- Do not regress the current QR bootstrap -> trusted reconnect flow.
- Do not reintroduce hosted-service assumptions; keep the repo local-first.
- Do not require a relay protocol rewrite for this phase.
- Keep existing QR payloads compatible when optional metadata is missing.
- Do not make Xcode build/test the default verification path; prefer unit tests and targeted device install steps.

## Current State

The repo already stores trusted computers as a registry on iPhone:

- `CodexTrustedMacRegistry.records` stores multiple records keyed by device id.
- reconnect logic still collapses to `preferredTrustedMacRecord`.
- UI surfaces only one visible pair summary and one destructive "Forget Pair" action.

The relay already resolves trusted reconnect per host device id:

- `POST /v1/trusted/session/resolve` accepts a specific `macDeviceId`
- relay tracks live sessions by host device id

The bridge currently limits the inverse direction:

- one host trusts one iPhone identity at a time

That asymmetry is acceptable for this phase.

## Product Model

### Stable Host Registry

Introduce a clearer host model in iPhone presentation and selection layers:

- one registry entry per paired computer
- one explicit active selection
- one live relay session reused only for the selected host

The persisted host record should support future expansion:

- stable identity: device id, identity public key
- display metadata: display name, platform
- connection hints: relay URL, last resolved session id, timestamps
- capability flags for platform-specific behavior

The wire format may continue to use `mac*` field names for compatibility in this phase. App-level naming and UI should shift to `host` / `computer`.

### Active Host Selection

Persist an explicit active host selection instead of inferring from "last used" alone.

Selection rules:

1. manual switch wins
2. fresh QR scan of a host sets that host active
3. fallback to most recently used paired host only when no explicit selection exists

This removes hidden drift between remembered hosts and reconnect target.

## Architecture

### iPhone Service Layer

Split current logic into three concerns:

1. host registry
2. active host selection
3. live relay session state for the selected host

Practical implementation can stay inside `CodexService` first, but helpers should be organized so a later extraction is straightforward:

- host registry helpers
- active host selection helpers
- host presentation helpers
- trusted reconnect resolution using selected host id

This keeps future "multi-online" expansion additive rather than destructive.

### Bridge and Relay

No phase-one relay topology change is needed.

Bridge changes:

- add optional host metadata to pairing payload
- keep registration updates sending display name
- optionally add normalized platform metadata

Relay changes:

- keep `macDeviceId -> live session` map
- extend resolve response with optional platform metadata when available
- avoid breaking older clients if fields are absent

### Windows Support

The repo docs already state the core bridge works on Windows and Linux, with macOS-only daemon conveniences. The pairing UI and service model should therefore refer to "computer" or "host", not "Mac", while still tolerating legacy wire field names.

## UI Design

### Home

Home remains fast and compact:

- current active computer card remains the primary summary
- add a clear switch affordance
- present a native sheet listing paired computers
- allow selecting another computer or scanning a new one

The list row content:

- display name
- platform icon + platform label
- current/connected badge
- recent-use metadata

### Settings

Settings becomes the management surface:

- add `Paired Computers` section
- show current active computer first
- show full paired computer list
- actions: rename, make active, forget this computer, pair new computer

### Visual Style

Use system design first, custom glass second.

Relevant Apple guidance:

- Liquid Glass overview:
  `https://developer.apple.com/documentation/technologyoverviews/liquid-glass`
- SwiftUI `glassEffect`:
  `https://developer.apple.com/documentation/SwiftUI/View/glassEffect%28_%3Ain%3AisEnabled%3A%29`
- Toolbar guidance via Landmarks sample:
  `https://developer.apple.com/documentation/SwiftUI/Landmarks-Refining-the-system-provided-glass-effect-in-toolbars`
- WWDC25 new design session:
  `https://developer.apple.com/videos/play/wwdc2025/284/`

Application of that guidance:

- let navigation bars, toolbars, sheets, and standard controls inherit system glass naturally
- use custom glass only for a few summary cards and current-selection highlights
- keep management lists readable and mostly non-glass
- preserve existing `AdaptiveGlassModifier` as the single compatibility layer for iOS < 26

## Data Model Changes

Planned iPhone additions:

- add platform field to trusted host record
- add persisted active host selection key
- add helper that enumerates host summaries for UI

Planned wire additions:

- optional `hostPlatform` in QR payload
- optional `hostPlatform` in trusted resolve response

If absent, iPhone falls back to:

- infer `macOS` for legacy records when existing display/bridge context strongly implies it
- otherwise use `unknown`

## Error Handling

- Switching active computer must be explicit and visible.
- If selected host is offline, preserve selection and show offline state.
- If a host trust becomes invalid, clear only that host's trust record, not the whole registry.
- Saved relay session invalidation must stay scoped to the selected host.
- Fresh QR scans must still force bootstrap mode even when the host is already remembered.

## Testing Strategy

### iPhone Unit Tests

Add or extend tests for:

- active host selection fallback and persistence
- reconnect choosing selected host rather than implicit most-recent host
- forgetting one host without removing others
- Home/Settings presentation showing correct current host
- legacy records without platform metadata

### Bridge / Relay Tests

Add tests for:

- optional platform metadata in pairing payload
- resolve response carrying display and platform metadata
- backwards compatibility when optional metadata is absent

### Manual Device Validation

Primary target device:

- `Lin's iPhone`

Because a paid Apple Developer account is not assumed, the path should rely on Xcode automatic signing with the user's available account/team setup and direct on-device run. Official Apple references to keep handy:

- registered device / automatic signing notes:
  `https://developer.apple.com/help/account/devices/register-a-single-device`

Manual checks on device:

1. pair one macOS host
2. pair one Windows host
3. verify both appear in Home switcher and Settings list
4. switch active host without re-pairing
5. reconnect to the selected host after app relaunch
6. forget one host and confirm the other remains usable

## Non-Goals For This Phase

- simultaneous live connections to multiple hosts
- per-host parallel timelines in one iPhone session
- relay-side host fanout redesign
- daemon/service management parity across all desktop OSes

## Migration Notes

- Existing trusted records remain readable.
- Existing `lastTrustedMacDeviceId` becomes an input to active selection migration.
- Existing `trustedMacRegistry` storage remains the backing store for phase one.
- Naming cleanup from `Mac` to `Host` should focus on UI/presentation and new helper APIs first; protocol compatibility can remain on legacy field names.
