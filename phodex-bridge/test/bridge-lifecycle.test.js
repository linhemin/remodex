// FILE: bridge-lifecycle.test.js
// Purpose: Verifies the bridge stops local relay advertising before fatal exit paths.
// Layer: Unit test
// Exports: node:test suite
// Depends on: node:test, node:assert/strict, node:module, path, ../src/bridge

const test = require("node:test");
const assert = require("node:assert/strict");
const Module = require("module");
const path = require("path");

test("startBridge stops the local relay advertiser before exiting on codex error", () => {
  const state = loadBridgeWithStubs();
  try {
    const bridge = requireFreshBridge();

    assert.doesNotThrow(() => {
      bridge.startBridge({
        config: {
          relayUrl: "ws://relay.local:9000/relay",
          refreshEnabled: false,
          refreshDebounceMs: 0,
          refreshCommand: "",
          codexBundleId: "com.example.codex",
          codexAppPath: "/Applications/Codex.app",
          pushServiceUrl: "",
          pushPreviewMaxChars: 0,
          codexEndpoint: "",
        },
        printPairingQr: false,
        onBridgeStatus() {},
      });
    });

    assert.ok(typeof state.onError === "function", "expected codex onError handler to be registered");

    assert.throws(
      () => state.onError(new Error("codex failed")),
      /process\.exit:1/
    );

    assert.deepEqual(state.events.slice(0, 3), [
      "start",
      "stop",
      "exit:1",
    ]);
  } finally {
    state.restore();
  }
});

test("startBridge stops the local relay advertiser before exiting on fatal relay close", () => {
  const state = loadBridgeWithStubs();
  try {
    const bridge = requireFreshBridge();

    assert.doesNotThrow(() => {
      bridge.startBridge({
        config: {
          relayUrl: "ws://relay.local:9000/relay",
          refreshEnabled: false,
          refreshDebounceMs: 0,
          refreshCommand: "",
          codexBundleId: "com.example.codex",
          codexAppPath: "/Applications/Codex.app",
          pushServiceUrl: "",
          pushPreviewMaxChars: 0,
          codexEndpoint: "",
        },
        printPairingQr: false,
        onBridgeStatus() {},
      });
    });

    assert.ok(state.sockets.length > 0, "expected relay socket to be created");
    const socket = state.sockets[0];
    assert.ok(typeof socket.handlers.get("close") === "function", "expected relay close handler to be registered");

    assert.throws(
      () => socket.handlers.get("close")(4000),
      /process\.exit:0/
    );

    assert.deepEqual(state.events.slice(0, 3), [
      "start",
      "stop",
      "exit:0",
    ]);
  } finally {
    state.restore();
  }
});

function loadBridgeWithStubs() {
  const bridgePath = require.resolve("../src/bridge");
  delete require.cache[bridgePath];

  const originalLoad = Module._load;
  const originalExit = process.exit;
  const originalOn = process.on;
  const originalSetTimeout = global.setTimeout;
  const originalConsoleError = console.error;
  const originalConsoleLog = console.log;
  const state = {
    events: [],
    onError: null,
    sockets: [],
  };

  const fakeWebSocket = class FakeWebSocket {
    static OPEN = 1;
    static CONNECTING = 0;

    constructor(url, options) {
      this.url = url;
      this.options = options;
      this.readyState = FakeWebSocket.CONNECTING;
      this.handlers = new Map();
      state.sockets.push(this);
    }

    on(event, handler) {
      this.handlers.set(event, handler);
    }

    send() {}

    close() {
      this.readyState = FakeWebSocket.OPEN;
    }
  };

  const fakes = {
    ws: fakeWebSocket,
    "./codex-desktop-refresher": {
      CodexDesktopRefresher: class {
        handleOutbound() {}
        handleInbound() {}
        handleTransportReset() {}
      },
      readBridgeConfig() {
        return {};
      },
    },
    "./codex-transport": {
      createCodexTransport() {
        return {
          describe() {
            return "codex app-server";
          },
          onError(handler) {
            state.onError = handler;
          },
          onMessage() {},
          onClose() {},
          send() {},
          shutdown() {},
        };
      },
    },
    "./rollout-watch": {
      createThreadRolloutActivityWatcher() {
        return { stop() {} };
      },
    },
    "./qr": {
      printQR() {},
    },
    "./session-state": {
      rememberActiveThread() {},
    },
    "./desktop-handler": {
      handleDesktopRequest() {
        return false;
      },
    },
    "./git-handler": {
      handleGitRequest() {
        return false;
      },
    },
    "./thread-context-handler": {
      handleThreadContextRequest() {
        return false;
      },
    },
    "./workspace-handler": {
      handleWorkspaceRequest() {
        return false;
      },
    },
    "./notifications-handler": {
      createNotificationsHandler() {
        return {
          handleNotificationsRequest() {
            return false;
          },
        };
      },
    },
    "./voice-handler": {
      createVoiceHandler() {
        return {
          handleVoiceRequest() {
            return false;
          },
        };
      },
      resolveVoiceAuth() {
        return null;
      },
    },
    "./account-status": {
      composeSanitizedAuthStatusFromSettledResults() {
        return {};
      },
    },
    "./push-notification-service-client": {
      createPushNotificationServiceClient() {
        return {
          logUnavailable() {},
        };
      },
    },
    "./push-notification-tracker": {
      createPushNotificationTracker() {
        return {
          handleOutbound() {},
        };
      },
    },
    "./secure-device-state": {
      loadOrCreateBridgeDeviceState() {
        return {
          macDeviceId: "mac-1",
          macIdentityPublicKey: "pub",
          trustedPhones: {},
        };
      },
      resolveBridgeRelaySession(deviceState) {
        return {
          deviceState,
          sessionId: "session-1",
        };
      },
    },
    "./secure-transport": {
      createBridgeSecureTransport() {
        return {
          createPairingPayload() {
            return {
              v: 1,
              relay: "ws://relay.local:9000/relay",
              sessionId: "session-1",
              macDeviceId: "mac-1",
              macIdentityPublicKey: "pub",
              expiresAt: Date.now() + 60_000,
            };
          },
          bindLiveSendWireMessage() {},
          queueOutboundApplicationMessage() {},
          handleIncomingWireMessage() {
            return false;
          },
        };
      },
    },
    "./local-relay-advertiser": {
      buildAdvertisementMetadata(metadata) {
        return metadata;
      },
      createLocalRelayAdvertiser({ metadata } = {}) {
        return {
          start() {
            state.events.push("start");
          },
          stop() {
            state.events.push("stop");
          },
          get metadata() {
            return metadata;
          },
        };
      },
    },
    "./rollout-live-mirror": {
      createRolloutLiveMirrorController() {
        return {
          stopAll() {},
          observeInbound() {},
        };
      },
    },
  };

  Module._load = function patchedLoad(request, parent, isMain) {
    if (Object.prototype.hasOwnProperty.call(fakes, request)) {
      return fakes[request];
    }

    return originalLoad.apply(this, arguments);
  };

  process.exit = (code) => {
    state.events.push(`exit:${code}`);
    throw new Error(`process.exit:${code}`);
  };
  process.on = () => process;
  global.setTimeout = (callback) => {
    callback();
    return 0;
  };
  console.error = () => {};
  console.log = () => {};

  state.restore = () => {
    Module._load = originalLoad;
    process.exit = originalExit;
    process.on = originalOn;
    global.setTimeout = originalSetTimeout;
    console.error = originalConsoleError;
    console.log = originalConsoleLog;
    delete require.cache[bridgePath];
  };

  return state;
}

function requireFreshBridge() {
  const bridgePath = path.join(__dirname, "../src/bridge");
  delete require.cache[require.resolve(bridgePath)];
  return require(bridgePath);
}
