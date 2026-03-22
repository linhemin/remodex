// FILE: local-relay-advertiser.js
// Purpose: Builds safe local relay discovery metadata without bearer-like pairing values.
// Layer: Bridge helper
// Exports: buildAdvertisementMetadata, createLocalRelayAdvertiser

function buildAdvertisementMetadata({
  macDeviceId,
  displayName,
  relayPort,
} = {}) {
  const metadata = {};

  if (typeof macDeviceId === "string" && macDeviceId.trim()) {
    metadata.macDeviceId = macDeviceId.trim();
  }

  if (typeof displayName === "string" && displayName.trim()) {
    metadata.displayName = displayName.trim();
  }

  if (relayPort !== undefined && relayPort !== null) {
    metadata.relayPort = String(relayPort);
  }

  return metadata;
}

function createLocalRelayAdvertiser({
  metadata = {},
  startImpl = null,
  stopImpl = null,
} = {}) {
  let isRunning = false;
  const normalizedMetadata = metadata && typeof metadata === "object" ? metadata : {};

  return {
    start() {
      if (isRunning) {
        return;
      }

      isRunning = true;
      if (typeof startImpl === "function") {
        startImpl(normalizedMetadata);
      }
    },
    stop() {
      if (!isRunning) {
        return;
      }

      isRunning = false;
      if (typeof stopImpl === "function") {
        stopImpl(normalizedMetadata);
      }
    },
    get isRunning() {
      return isRunning;
    },
    get metadata() {
      return normalizedMetadata;
    },
  };
}

module.exports = {
  buildAdvertisementMetadata,
  createLocalRelayAdvertiser,
};
