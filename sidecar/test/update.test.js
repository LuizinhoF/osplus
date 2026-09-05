const assert = require("node:assert/strict");
const fs = require("node:fs");
const http = require("node:http");
const os = require("node:os");
const path = require("node:path");
const test = require("node:test");

const {
  compareStableVersions,
  createUpdateClient,
  installedVersionCandidates,
  parseStableVersion,
  requestUpdateManifest,
  resolveUpdateUrl,
} = require("../update");

const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), "osplus-update-test-"));
test.after(() => {
  assert.ok(tempRoot.startsWith(os.tmpdir()));
  fs.rmSync(tempRoot, { recursive: true, force: true });
});

let markerCounter = 0;
function markerFile(version = "0.3.0") {
  markerCounter++;
  const file = path.join(tempRoot, `version-${markerCounter}.json`);
  fs.writeFileSync(file, JSON.stringify({ version }), "utf8");
  return file;
}

function releaseManifest(version = "0.4.0") {
  return {
    schemaVersion: 1,
    channel: "stable",
    version,
    releaseUrl: `https://github.com/LuizinhoF/osplus/releases/tag/v${version}`,
    assetUrl: `https://github.com/LuizinhoF/osplus/releases/download/v${version}/OSPlus.zip`,
    publishedAt: "2026-07-28T12:00:00.000Z",
  };
}

function makeClient({
  installedVersion = "0.3.0",
  request,
  now = Date.now,
  markerCandidates,
} = {}) {
  const events = [];
  const logs = [];
  const client = createUpdateClient({
    log: (line) => logs.push(line),
    emit: (event) => events.push(event),
    relayUrl: "ws://127.0.0.1:3000",
    config: {},
    env: {},
    markerCandidates: markerCandidates || [markerFile(installedVersion)],
    request,
    now,
  });
  return { client, events, logs };
}

test("resolves update URL from env, then config, then the relay origin", () => {
  assert.equal(resolveUpdateUrl({
    relayUrl: "wss://relay.example.test/chat?token=x",
    config: { update_url: "https://config.example.test/latest" },
    env: { OSPLUS_UPDATE_URL: "http://127.0.0.1:4444/fixture" },
  }), "http://127.0.0.1:4444/fixture");

  assert.equal(resolveUpdateUrl({
    relayUrl: "wss://relay.example.test/chat?token=x",
    config: { update_url: "https://config.example.test/latest" },
    env: {},
  }), "https://config.example.test/latest");

  assert.equal(resolveUpdateUrl({
    relayUrl: "wss://relay.example.test/chat?token=x",
    config: {},
    env: {},
  }), "https://relay.example.test/updates/latest");
});

test("uses numeric strict stable-version comparison", () => {
  assert.equal(compareStableVersions("0.10.0", "0.9.0"), 1);
  assert.equal(compareStableVersions("1.0.0", "1.0.0"), 0);
  assert.equal(compareStableVersions("1.2.2", "1.2.10"), -1);
  assert.equal(parseStableVersion("v2.3.4").text, "2.3.4");
  assert.equal(parseStableVersion("01.2.3"), null);
  assert.equal(parseStableVersion("1.2.3-beta.1"), null);
});

test("resolves the installed marker one directory above the packaged executable", () => {
  const execPath = path.join(tempRoot, "Mods", "OSPlus", "sidecar", "OSPlus.exe");
  const [packagedMarker] = installedVersionCandidates({
    execPath,
    moduleDir: path.join(tempRoot, "repo", "sidecar"),
  });
  assert.equal(
    packagedMarker,
    path.join(tempRoot, "Mods", "OSPlus", "version.json"),
  );
});

test("performs an actual HTTP manifest request and sends the cached ETag", async (t) => {
  const seenEtags = [];
  const server = http.createServer((req, res) => {
    seenEtags.push(req.headers["if-none-match"] || "");
    if (req.headers["if-none-match"] === '"release-1"') {
      res.writeHead(304, { ETag: '"release-1"' });
      res.end();
      return;
    }
    res.writeHead(200, {
      "Content-Type": "application/json",
      "ETag": '"release-1"',
    });
    res.end(JSON.stringify(releaseManifest()));
  });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  t.after(() => new Promise((resolve) => server.close(resolve)));
  const port = server.address().port;
  const url = `http://127.0.0.1:${port}/updates/latest`;

  const first = await requestUpdateManifest({ url });
  const second = await requestUpdateManifest({ url, etag: first.etag });

  assert.equal(first.status, 200);
  assert.equal(first.body.version, "0.4.0");
  assert.equal(first.etag, '"release-1"');
  assert.equal(second.status, 304);
  assert.deepEqual(seenEtags, ["", '"release-1"']);
});

test("current release emits nothing and successful cooldown avoids another request", async () => {
  let calls = 0;
  const { client, events } = makeClient({
    request: async () => {
      calls++;
      return { status: 200, body: releaseManifest("0.3.0"), etag: '"release-1"' };
    },
  });

  await client.check("startup");
  await client.handleUpdateCheck({ type: "update_check", reason: "queue_entered" });

  assert.equal(calls, 1);
  assert.deepEqual(events, []);
});

test("every accepted trigger re-emits cached newer availability during cooldown", async () => {
  let calls = 0;
  const clock = 1_785_236_400_000;
  const { client, events } = makeClient({
    now: () => clock,
    request: async () => {
      calls++;
      return { status: 200, body: releaseManifest("0.4.0"), etag: '"release-1"' };
    },
  });

  await client.check("startup");
  await client.handleUpdateCheck({ type: "update_check", reason: "queue_entered" });
  await client.handleUpdateCheck({ type: "update_check", reason: "match_completed" });

  assert.equal(calls, 1);
  assert.equal(events.length, 3);
  assert.deepEqual(events[0], {
    type: "update_available",
    installedVersion: "0.3.0",
    latestVersion: "0.4.0",
    releaseUrl: "https://github.com/LuizinhoF/osplus/releases/tag/v0.4.0",
    assetUrl: "https://github.com/LuizinhoF/osplus/releases/download/v0.4.0/OSPlus.zip",
    ts: 1_785_236_400,
  });
  assert.deepEqual(events[1], events[0]);
  assert.deepEqual(events[2], events[0]);
});

test("coalesces concurrent checks into one request and one inbox event", async () => {
  let calls = 0;
  let resolveRequest;
  const pending = new Promise((resolve) => { resolveRequest = resolve; });
  const { client, events } = makeClient({
    request: async () => {
      calls++;
      return pending;
    },
  });

  const startup = client.check("startup");
  const queued = client.check("queue_entered");
  assert.equal(calls, 1);

  resolveRequest({ status: 200, body: releaseManifest("0.4.0"), etag: '"release-1"' });
  await Promise.all([startup, queued]);

  assert.equal(calls, 1);
  assert.equal(events.length, 1);
});

test("revalidates after cooldown with ETag and re-emits a cached 304 result", async () => {
  let clock = 1_000;
  let calls = 0;
  const etags = [];
  const { client, events } = makeClient({
    now: () => clock,
    request: async ({ etag }) => {
      calls++;
      etags.push(etag);
      if (calls === 1) {
        return { status: 200, body: releaseManifest("0.4.0"), etag: '"release-1"' };
      }
      return { status: 304, body: null, etag: '"release-1"' };
    },
  });

  await client.check("startup");
  clock += 300_001;
  await client.check("match_completed");

  assert.equal(calls, 2);
  assert.deepEqual(etags, ["", '"release-1"']);
  assert.equal(events.length, 2);
});

test("warm refresh failure re-emits previously validated newer release", async () => {
  let clock = 1_000;
  let calls = 0;
  const { client, events } = makeClient({
    now: () => clock,
    request: async () => {
      calls++;
      if (calls === 1) {
        return { status: 200, body: releaseManifest("0.4.0"), etag: '"release-1"' };
      }
      throw new Error("relay offline");
    },
  });

  await client.check("startup");
  clock += 300_001;
  const result = await client.check("match_completed");

  assert.equal(calls, 2);
  assert.equal(events.length, 2);
  assert.equal(result.available, true);
  assert.equal(result.stale, true);
  assert.equal(result.error, "transport");
});

test("cold request failure emits nothing and the next trigger retries", async () => {
  let calls = 0;
  const { client, events } = makeClient({
    request: async () => {
      calls++;
      throw new Error("relay offline");
    },
  });

  await client.check("startup");
  await client.check("queue_entered");

  assert.equal(calls, 2);
  assert.deepEqual(events, []);
});

test("cold malformed response emits nothing and does not start cooldown", async () => {
  let calls = 0;
  const { client, events } = makeClient({
    request: async () => {
      calls++;
      return { status: 200, body: { version: "banana" }, etag: "" };
    },
  });

  await client.check("startup");
  await client.check("match_completed");

  assert.equal(calls, 2);
  assert.deepEqual(events, []);
});

test("invalid reasons are dropped before network work", async () => {
  let calls = 0;
  const { client, events } = makeClient({
    request: async () => {
      calls++;
      return { status: 200, body: releaseManifest(), etag: "" };
    },
  });

  const result = await client.handleUpdateCheck({
    type: "update_check",
    reason: "button_clicked",
  });

  assert.equal(result.error, "invalid-reason");
  assert.equal(calls, 0);
  assert.deepEqual(events, []);
});

test("missing installed marker disables checks without a request or event", async () => {
  let calls = 0;
  const missing = path.join(tempRoot, "does-not-exist.json");
  const { client, events } = makeClient({
    markerCandidates: [missing],
    request: async () => {
      calls++;
      return { status: 200, body: releaseManifest(), etag: "" };
    },
  });

  const result = await client.check("startup");

  assert.equal(client._enabled, false);
  assert.equal(result.error, "disabled");
  assert.equal(calls, 0);
  assert.deepEqual(events, []);
});
