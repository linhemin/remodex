// FILE: local-relay-advertiser.test.js
// Purpose: Verifies local relay advertisement metadata stays free of bearer-like pairing values.
// Layer: Unit test
// Exports: node:test suite
// Depends on: node:test, node:assert/strict, ../src/local-relay-advertiser

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  buildAdvertisementMetadata,
  buildDnsSdRegistrationArgs,
  createLocalRelayAdvertiser,
} = require("../src/local-relay-advertiser");

test("buildAdvertisementMetadata omits session ids and secrets", () => {
  const metadata = buildAdvertisementMetadata({
    macDeviceId: "mac-1",
    displayName: "MacBook Pro",
    relayPort: 9000,
    relayPath: "/relay",
    protocolVersion: 1,
    sessionId: "session-secret",
    notificationSecret: "secret",
  });

  assert.equal(metadata.macDeviceId, "mac-1");
  assert.equal(metadata.displayName, "MacBook Pro");
  assert.equal(metadata.relayPort, "9000");
  assert.equal(metadata.relayPath, "/relay");
  assert.equal(metadata.protocolVersion, "1");
  assert.equal("sessionId" in metadata, false);
  assert.equal("notificationSecret" in metadata, false);
});

test("buildDnsSdRegistrationArgs builds a safe remodex bonjour registration", () => {
  const args = buildDnsSdRegistrationArgs({
    macDeviceId: "mac-1",
    displayName: "Desk Mac",
    relayPort: "9000",
    relayPath: "/relay",
    protocolVersion: "1",
  });

  assert.deepEqual(args, [
    "-R",
    "Desk Mac",
    "_remodex._tcp",
    "local.",
    "9000",
    "macDeviceId=mac-1",
    "displayName=Desk Mac",
    "relayPath=/relay",
    "protocolVersion=1",
  ]);
});

test("createLocalRelayAdvertiser starts once and stops once", () => {
  const calls = [];
  const metadata = {
    macDeviceId: "mac-1",
    displayName: "MacBook Pro",
    relayPort: "9000",
  };
  const advertiser = createLocalRelayAdvertiser({
    metadata,
    startImpl(advertisementMetadata) {
      calls.push(["start", advertisementMetadata]);
    },
    stopImpl(advertisementMetadata) {
      calls.push(["stop", advertisementMetadata]);
    },
  });

  advertiser.start();
  advertiser.start();
  advertiser.stop();
  advertiser.stop();

  assert.deepEqual(calls, [
    ["start", metadata],
    ["stop", metadata],
  ]);
});

test("createLocalRelayAdvertiser creates and controls a publisher once", () => {
  const calls = [];
  const metadata = {
    macDeviceId: "mac-1",
    displayName: "MacBook Pro",
    relayPort: "9000",
    relayPath: "/relay",
    protocolVersion: "1",
  };
  const advertiser = createLocalRelayAdvertiser({
    metadata,
    publisherFactory(advertisementMetadata) {
      calls.push(["factory", advertisementMetadata]);
      return {
        start() {
          calls.push(["publisher:start", advertisementMetadata]);
        },
        stop() {
          calls.push(["publisher:stop", advertisementMetadata]);
        },
      };
    },
  });

  advertiser.start();
  advertiser.start();
  advertiser.stop();
  advertiser.stop();

  assert.deepEqual(calls, [
    ["factory", metadata],
    ["publisher:start", metadata],
    ["publisher:stop", metadata],
  ]);
});

test("createLocalRelayAdvertiser clears running state when startImpl throws", () => {
  const calls = [];
  const advertiser = createLocalRelayAdvertiser({
    startImpl() {
      calls.push("start");
      throw new Error("boom");
    },
  });

  assert.throws(() => advertiser.start(), /boom/);
  assert.equal(advertiser.isRunning, false);

  assert.throws(() => advertiser.start(), /boom/);
  assert.equal(advertiser.isRunning, false);
  assert.deepEqual(calls, ["start", "start"]);
});
