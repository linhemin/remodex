# Bonjour Discovery Completion Design

## Goal

Finish the missing zero-config LAN discovery path so a paired iPhone can actually browse Bonjour on the local network, prefer the discovered relay first, then fall back to remembered overlay and saved relay candidates.

## Current Gap

The current branch already has:

- LAN/overlay candidate ranking on iOS
- remembered `lastLocalRelayURL` / `lastOverlayRelayURL`
- a bridge-side local-relay advertiser helper
- local-network authorization prompting support

But it still does **not** have:

- a real Bonjour publisher on the bridge
- a real Bonjour browser on iOS
- a reconnect path that feeds live Bonjour results into candidate ranking

That is why the app may reconnect via remembered local candidates without ever demonstrating actual mDNS discovery.

## Non-Goals

- Replacing the relay protocol
- Introducing direct bridge RPC or WebRTC
- Publishing `sessionId` or any bearer-like pairing data over Bonjour
- Changing secure handshake or trusted reconnect semantics

## Recommended Architecture

### Bridge

Upgrade the local relay advertiser into a real Bonjour publisher.

Published service:

- service type: `_remodex._tcp`
- service name: stable, human-readable host label
- port: relay port derived from the configured relay URL
- TXT metadata:
  - `macDeviceId`
  - `displayName`
  - `relayPath`
  - `protocolVersion`

Never publish:

- `sessionId`
- notification secrets
- trusted-phone metadata

Publisher lifecycle:

- start after bridge config is resolved and relay URL is known
- stop on shutdown, fatal relay close, and startup error
- publication failure degrades discovery only and must not block relay service startup

### iOS

Add a real Bonjour browser that performs a short browse window before reconnect attempts that target a trusted Mac.

Discovery flow:

1. Request local-network authorization if the app does not already know the permission state
2. Browse `_remodex._tcp` for a short timeout
3. Resolve Bonjour results into relay base URLs using the published `relayPath` and endpoint host/port
4. Filter results by the preferred trusted Mac's `macDeviceId`
5. Feed the results into existing candidate ranking

Candidate priority becomes:

1. live Bonjour results
2. remembered `lastLocalRelayURL`
3. remembered `lastOverlayRelayURL`
4. saved relay URL
5. remote trusted-session resolve / QR recovery

### Overlay Retention

Overlay handling remains memory-based, not actively discovered over mDNS.

- successful `.ts.net` / `100.x` reconnects continue to refresh `lastOverlayRelayURL`
- same-Wi-Fi reconnects refresh `lastLocalRelayURL`
- Bonjour covers only current-LAN discovery; overlay remains a fallback memory layer

## Failure Handling

- Bonjour browse timeout must be short and silent
- denied local-network permission skips Bonjour and continues with overlay/saved relay
- malformed TXT records or unresolved endpoints are ignored
- secure handshake remains the trust boundary; discovery only supplies routing hints

## Security Model

- Bonjour metadata is unauthenticated and routing-only
- identity still comes from the existing trusted Mac public key handshake
- live session identifiers remain relay-only
- logs must stay free of session-bearing data

## Testing Strategy

### Bridge

- metadata builder still redacts secrets
- publisher starts/stops once
- bridge lifecycle starts/stops publisher
- publisher failure clears running state and does not poison later retries

### iOS

- Bonjour result parsing produces normalized relay URLs
- discovery filters by `macDeviceId`
- reconnect ranking prefers live Bonjour over remembered local/overlay/saved relay
- denied local-network permission skips Bonjour without breaking fallback reconnect

### Regression

- existing secure pairing tests stay green
- existing reconnect candidate tests stay green
- bridge/relay regressions stay green

