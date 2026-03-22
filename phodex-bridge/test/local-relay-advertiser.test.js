// FILE: local-relay-advertiser.test.js
// Purpose: Verifies local relay advertisement metadata stays free of bearer-like pairing values.
// Layer: Unit test
// Exports: node:test suite
// Depends on: node:test, node:assert/strict, ../src/local-relay-advertiser

const test = require("node:test");
const assert = require("node:assert/strict");
const { buildAdvertisementMetadata } = require("../src/local-relay-advertiser");

test("buildAdvertisementMetadata omits session ids and secrets", () => {
  const metadata = buildAdvertisementMetadata({
    macDeviceId: "mac-1",
    displayName: "MacBook Pro",
    relayPort: 9000,
    sessionId: "session-secret",
    notificationSecret: "secret",
  });

  assert.equal(metadata.macDeviceId, "mac-1");
  assert.equal(metadata.displayName, "MacBook Pro");
  assert.equal(metadata.relayPort, "9000");
  assert.equal("sessionId" in metadata, false);
  assert.equal("notificationSecret" in metadata, false);
});
