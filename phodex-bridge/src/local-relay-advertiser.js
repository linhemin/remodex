// FILE: local-relay-advertiser.js
// Purpose: Builds safe local relay discovery metadata without bearer-like pairing values.
// Layer: Bridge helper
// Exports: buildAdvertisementMetadata

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

module.exports = {
  buildAdvertisementMetadata,
};
