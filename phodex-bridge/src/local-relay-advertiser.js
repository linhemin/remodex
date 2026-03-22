// FILE: local-relay-advertiser.js
// Purpose: Builds safe local relay discovery metadata without bearer-like pairing values.
// Layer: Bridge helper
// Exports: buildAdvertisementMetadata, createLocalRelayAdvertiser

const { spawn } = require("child_process");

const REMODEX_BONJOUR_SERVICE_TYPE = "_remodex._tcp";
const REMODEX_BONJOUR_DOMAIN = "local.";

function buildAdvertisementMetadata({
  macDeviceId,
  displayName,
  relayPort,
  relayPath,
  protocolVersion,
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

  if (typeof relayPath === "string" && relayPath.trim()) {
    metadata.relayPath = relayPath.trim();
  }

  if (protocolVersion !== undefined && protocolVersion !== null) {
    metadata.protocolVersion = String(protocolVersion);
  }

  return metadata;
}

function buildDnsSdRegistrationArgs(metadata = {}) {
  const displayName = normalizeDisplayName(metadata);
  const relayPort = normalizeNonEmptyString(metadata.relayPort);
  if (!displayName || !relayPort) {
    return null;
  }

  const txtRecord = [
    formatTxtRecord("macDeviceId", metadata.macDeviceId),
    formatTxtRecord("displayName", displayName),
    formatTxtRecord("relayPath", metadata.relayPath || "/relay"),
    formatTxtRecord("protocolVersion", metadata.protocolVersion || "1"),
  ].filter(Boolean);

  return [
    "-R",
    displayName,
    REMODEX_BONJOUR_SERVICE_TYPE,
    REMODEX_BONJOUR_DOMAIN,
    relayPort,
    ...txtRecord,
  ];
}

function createDnsSdPublisher(metadata = {}, {
  spawnImpl = spawn,
  onError = defaultAdvertiserWarning,
} = {}) {
  let childProcess = null;

  return {
    start() {
      if (childProcess) {
        return;
      }

      const args = buildDnsSdRegistrationArgs(metadata);
      if (!args) {
        return;
      }

      try {
        childProcess = spawnImpl("dns-sd", args, {
          stdio: "ignore",
        });
      } catch (error) {
        childProcess = null;
        onError(`[remodex] Failed to start Bonjour advertising: ${error.message}`);
        return;
      }

      childProcess.once?.("error", (error) => {
        onError(`[remodex] Bonjour advertising is unavailable: ${error.message}`);
      });
      childProcess.once?.("exit", () => {
        childProcess = null;
      });
    },
    stop() {
      if (!childProcess) {
        return;
      }

      childProcess.kill("SIGTERM");
      childProcess = null;
    },
  };
}

function createLocalRelayAdvertiser({
  metadata = {},
  startImpl = null,
  stopImpl = null,
  publisherFactory = null,
} = {}) {
  let isRunning = false;
  let publisher = null;
  const normalizedMetadata = metadata && typeof metadata === "object" ? metadata : {};

  function resolvePublisher() {
    if (publisher) {
      return publisher;
    }

    if (typeof publisherFactory === "function") {
      publisher = publisherFactory(normalizedMetadata);
      return publisher;
    }

    if (!startImpl && !stopImpl) {
      publisher = createDnsSdPublisher(normalizedMetadata);
      return publisher;
    }

    return null;
  }

  return {
    start() {
      if (isRunning) {
        return;
      }

      const resolvedPublisher = resolvePublisher();
      if (resolvedPublisher && typeof resolvedPublisher.start === "function") {
        resolvedPublisher.start();
      } else if (typeof startImpl === "function") {
        startImpl(normalizedMetadata);
      }
      isRunning = true;
    },
    stop() {
      if (!isRunning) {
        return;
      }

      isRunning = false;
      const resolvedPublisher = publisher;
      if (resolvedPublisher && typeof resolvedPublisher.stop === "function") {
        resolvedPublisher.stop();
      } else if (typeof stopImpl === "function") {
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

function normalizeNonEmptyString(value) {
  if (typeof value !== "string") {
    return "";
  }

  return value.trim();
}

function normalizeDisplayName(metadata) {
  return normalizeNonEmptyString(metadata.displayName)
    || normalizeNonEmptyString(metadata.macDeviceId)
    || "Remodex";
}

function formatTxtRecord(key, value) {
  const normalizedValue = normalizeNonEmptyString(String(value ?? ""));
  if (!normalizedValue) {
    return null;
  }

  return `${key}=${normalizedValue}`;
}

function defaultAdvertiserWarning(message) {
  console.warn(message);
}

module.exports = {
  buildAdvertisementMetadata,
  buildDnsSdRegistrationArgs,
  createDnsSdPublisher,
  createLocalRelayAdvertiser,
};
