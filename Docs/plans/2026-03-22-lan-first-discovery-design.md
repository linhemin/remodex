# LAN-First Relay Discovery Design

## Goal

Let a paired iPhone prefer local or private-overlay relay endpoints automatically, with no user configuration, while preserving the existing relay protocol and fallback path.

## User Experience

- On the same Wi-Fi, the iPhone should discover the Mac automatically and connect through the local relay endpoint first.
- On Tailscale or another private overlay, the iPhone should still prefer a private endpoint when one is known or discoverable.
- If no local or private endpoint is reachable quickly, the app should fall back to the existing relay URL and trusted reconnect flow without user intervention.
- The pairing flow should remain QR-based. Users should not have to enter IPs, hostnames, or toggle modes.

## Non-Goals

- Replacing the relay protocol with direct bridge RPC.
- Introducing WebRTC, ICE, STUN, or NAT traversal.
- Making mDNS responsible for security or trust.
- Removing the current remote relay fallback.

## Current Constraints

The current architecture is relay-centric.

- The bridge starts with one `relayUrl` and opens a WebSocket to `/relay/{sessionId}`.
- The QR payload only carries one `relay` string plus the `sessionId`.
- The iPhone reconnect path also resolves the live session through the relay's `/v1/trusted/session/resolve`.
- iOS already has a notion of "direct-preferred" transports for `.local`, private IPv4, local IPv6, Tailscale `100.64.0.0/10`, and MagicDNS hosts. That means the transport layer is already capable of preferring LAN-style endpoints if discovery can feed it the right URLs.

## Approaches Considered

### 1. Bonjour discovery plus private-overlay candidate cache

This keeps the existing relay abstraction and adds a discovery layer above it.

- The bridge publishes a Bonjour service for the local relay.
- The iPhone discovers peers by `macDeviceId`.
- The system may internally cache private-overlay candidates such as `.ts.net` or `100.x` for the same trusted Mac.
- Connection order becomes: discovered local relay, discovered private candidate, saved relay, remote trusted reconnect resolve.

Pros:

- Minimal protocol churn.
- Reuses current secure handshake and relay session semantics.
- Clean user experience.
- Good fit for same-Wi-Fi and Tailscale.

Cons:

- Requires a new discovery service on both sides.
- Tailscale still needs a non-mDNS source of candidates.

### 2. QR-only candidate list

This would extend the QR payload with local and overlay candidates and skip runtime discovery.

Pros:

- Simple implementation.
- No background discovery lifecycle.

Cons:

- Not zero-config after topology changes.
- Weak for reconnect after DHCP changes or relay port changes.
- Does not satisfy the requested UX.

### 3. Full peer-to-peer direct channel

This would make the bridge accept iPhone connections directly and reduce the relay to fallback or bootstrap only.

Pros:

- Maximum transport purity.

Cons:

- Large architecture change.
- Re-implements session coordination that the relay already handles.
- Too invasive for the problem.

## Recommended Architecture

Keep the relay protocol intact and add a LAN-first discovery layer.

### Discovery Layer

Add a bridge-side publisher that advertises a Bonjour service such as `_remodex._tcp`.

The TXT record should carry only non-secret routing metadata:

- `macDeviceId`
- `displayName`
- `relayPathPrefix` or `relayBasePath`
- `protocolVersion`
- `secureProtocolVersion`
- `supportsTrustedResolve`
- `overlayHintsVersion`

The publisher should never expose bearer-like data such as `sessionId` or notification secrets.

### Connection Layer

The iPhone should resolve connection candidates in this order:

1. Bonjour match for the preferred trusted Mac on the current local network
2. Overlay candidates already associated with that trusted Mac
3. Saved relay URL from the last successful session
4. Remote trusted-session resolve against the saved relay

Each candidate should be tried with a short fail-fast timeout. The first successful socket wins.

### Trust Model

Discovery is only for routing. Trust still comes from the existing secure handshake:

- QR bootstrap for first trust
- trusted reconnect for subsequent sessions
- identity validation against the paired Mac public key

If discovery returns the wrong machine, the secure handshake must reject it.

## Bridge Changes

### New bridge publisher

Add a local relay advertiser module under `phodex-bridge/src/` that:

- publishes a Bonjour service for the configured relay port
- refreshes TXT records when bridge state changes
- derives overlay hints from the host, such as `.ts.net`, `.local`, and private interface addresses
- redacts or excludes sensitive session values

### Existing bridge runtime

Update the bridge startup flow to:

- start the advertiser once the relay URL is known
- stop advertising on shutdown
- keep the published service anchored to the relay abstraction, not to Codex internals

No relay protocol changes are required for the basic LAN-first path.

## iPhone Changes

### New discovery coordinator

Add a coordinator under `CodexMobile/CodexMobile/Services/` that:

- browses Bonjour for `_remodex._tcp`
- resolves endpoints into normalized relay base URLs
- filters discovered peers by `macDeviceId`
- ranks candidates by locality and recency
- merges Bonjour and overlay candidates into one ordered candidate list

### Pairing and reconnect state

Extend trusted Mac state to retain discovery-friendly metadata:

- last successful local relay base URL
- last successful overlay relay base URL
- discovery freshness timestamps

This is internal state, not user-facing configuration. The UX remains zero-config.

### Connection orchestration

Update reconnect orchestration so it asks discovery for candidates before constructing the final WebSocket URL.

The current relay connection code can remain largely unchanged because it already accepts a concrete `ws://` or `wss://` endpoint and already prefers direct transports for local/private hosts.

## Overlay Strategy

mDNS will not cover most overlay networks. For Tailscale and similar private overlays:

- accept `.ts.net` and private `100.x` candidates as first-class private endpoints
- record the last successful overlay endpoint per trusted Mac
- prefer a fresh, verified overlay endpoint before the saved public relay
- allow remote trusted resolve to continue working when no overlay candidate is available

This gives users a zero-config experience while still using durable internal memory.

## Fallback and Failure Handling

- Discovery failure must not change pairing state.
- A local candidate timeout should be fast and silent.
- Only secure handshake mismatches should trigger re-pair requirements.
- If all local candidates fail, the reconnect path should fall through to the current saved relay and remote trusted resolve behavior.
- The winning candidate should be remembered to improve future ordering.

## Security Notes

- Do not publish `sessionId` over Bonjour.
- Do not publish notification secrets or trusted-phone metadata.
- Treat discovery output as unauthenticated routing hints only.
- Continue using the existing secure handshake as the identity boundary.
- Keep logs free of live bearer-like identifiers.

## Testing Strategy

### Bridge

- unit-test TXT record generation and redaction
- unit-test overlay candidate extraction and normalization
- unit-test advertiser lifecycle start, refresh, and stop

### iPhone

- unit-test candidate ranking and filtering by `macDeviceId`
- unit-test fallback order from Bonjour to overlay to saved relay to remote resolve
- unit-test recovery when local network permission is denied or discovery returns stale entries

### Manual verification

- same-Wi-Fi bootstrap and reconnect
- same-Wi-Fi with relay restart
- Tailscale reconnect using MagicDNS or `100.x`
- fallback to saved remote relay when no private route is reachable

## Rollout Plan

1. Add discovery metadata and advertiser on the bridge.
2. Add iPhone discovery coordinator behind a conservative reconnect path.
3. Enable candidate ordering for trusted reconnect only.
4. Extend the pairing path to remember better local candidates after success.
5. Update docs to describe LAN-first behavior and fallback.

## Open Questions

- Whether the bridge should publish a stable relay service name derived from `macDeviceId` or only use TXT filtering.
- Whether overlay candidates should be derived only from successful connections or also from local interface inspection.
- Whether the local relay launcher should expose explicit CLI flags for enabling or disabling Bonjour advertisement.
