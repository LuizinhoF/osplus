const assert = require("node:assert/strict");
const test = require("node:test");

const {
  createUpdates,
  normalizeGithubRelease,
} = require("../updates");

function githubRelease(overrides = {}) {
  return {
    tag_name: "v0.4.0",
    draft: false,
    prerelease: false,
    html_url: "https://github.com/LuizinhoF/osplus/releases/tag/v0.4.0",
    published_at: "2026-07-28T12:00:00Z",
    assets: [{
      name: "OSPlus.zip",
      browser_download_url: "https://github.com/LuizinhoF/osplus/releases/download/v0.4.0/OSPlus.zip",
    }],
    ...overrides,
  };
}

function fakeResponse() {
  return {
    status: null,
    headers: {},
    body: "",
    writeHead(status, headers = {}) {
      this.status = status;
      this.headers = Object.fromEntries(
        Object.entries(headers).map(([key, value]) => [key.toLowerCase(), value]),
      );
    },
    end(body = "") {
      this.body = body == null ? "" : String(body);
    },
  };
}

async function invoke(handler, {
  method = "GET",
  url = "/updates/latest",
  headers = {},
} = {}) {
  const req = { method, url, headers };
  const res = fakeResponse();
  const handled = await handler(req, res);
  return { handled, res };
}

test("normalizes a published stable GitHub release with the required asset", () => {
  assert.deepEqual(normalizeGithubRelease(githubRelease()), {
    schemaVersion: 1,
    channel: "stable",
    version: "0.4.0",
    releaseUrl: "https://github.com/LuizinhoF/osplus/releases/tag/v0.4.0",
    assetUrl: "https://github.com/LuizinhoF/osplus/releases/download/v0.4.0/OSPlus.zip",
    publishedAt: "2026-07-28T12:00:00.000Z",
  });
});

test("rejects prereleases, non-strict tags, and releases without OSPlus.zip", async (t) => {
  await t.test("prerelease", () => {
    assert.throws(
      () => normalizeGithubRelease(githubRelease({ prerelease: true })),
      /not a published stable release/,
    );
  });
  await t.test("non-strict tag", () => {
    assert.throws(
      () => normalizeGithubRelease(githubRelease({ tag_name: "v0.4" })),
      /strict stable semantic version/,
    );
  });
  await t.test("missing asset", () => {
    assert.throws(
      () => normalizeGithubRelease(githubRelease({ assets: [] })),
      /missing required asset/,
    );
  });
});

test("serves a fresh cached projection without another GitHub request", async () => {
  let calls = 0;
  const updates = createUpdates({
    log() {},
    fetchLatest: async () => {
      calls++;
      return { status: 200, body: githubRelease(), etag: '"github-1"' };
    },
  });

  const first = await invoke(updates.handleHttp);
  const second = await invoke(updates.handleHttp);

  assert.equal(first.res.status, 200);
  assert.equal(second.res.status, 200);
  assert.equal(calls, 1);
  assert.equal(JSON.parse(second.res.body).version, "0.4.0");
  assert.match(second.res.headers["cache-control"], /max-age=300/);
});

test("coalesces concurrent cold-cache refreshes", async () => {
  let calls = 0;
  let releaseFetch;
  const waiting = new Promise((resolve) => { releaseFetch = resolve; });
  const updates = createUpdates({
    log() {},
    fetchLatest: async () => {
      calls++;
      return waiting;
    },
  });

  const first = invoke(updates.handleHttp);
  const second = invoke(updates.handleHttp);
  await Promise.resolve();
  assert.equal(calls, 1);

  releaseFetch({ status: 200, body: githubRelease(), etag: '"github-1"' });
  const [firstResult, secondResult] = await Promise.all([first, second]);
  assert.equal(firstResult.res.status, 200);
  assert.equal(secondResult.res.status, 200);
  assert.equal(calls, 1);
});

test("returns 304 for a matching client ETag", async () => {
  const updates = createUpdates({
    log() {},
    fetchLatest: async () => ({ status: 200, body: githubRelease(), etag: '"github-1"' }),
  });
  const first = await invoke(updates.handleHttp);
  const etag = first.res.headers.etag;
  const second = await invoke(updates.handleHttp, {
    headers: { "if-none-match": `W/${etag}` },
  });

  assert.equal(second.res.status, 304);
  assert.equal(second.res.body, "");
  assert.equal(second.res.headers.etag, etag);
});

test("revalidates an expired entry with GitHub ETag", async () => {
  let clock = 1_000;
  let calls = 0;
  const previousEtags = [];
  const updates = createUpdates({
    log() {},
    now: () => clock,
    fetchLatest: async ({ previousEtag }) => {
      calls++;
      previousEtags.push(previousEtag);
      if (calls === 1) return { status: 200, body: githubRelease(), etag: '"github-1"' };
      return { status: 304, body: null, etag: '"github-1"' };
    },
  });

  await invoke(updates.handleHttp);
  clock += 300_001;
  const revalidated = await invoke(updates.handleHttp);

  assert.equal(revalidated.res.status, 200);
  assert.equal(calls, 2);
  assert.deepEqual(previousEtags, ["", '"github-1"']);
});

test("serves warm cache stale with a warning when refresh fails", async () => {
  let clock = 1_000;
  let fail = false;
  let calls = 0;
  const updates = createUpdates({
    log() {},
    now: () => clock,
    fetchLatest: async () => {
      calls++;
      if (fail) throw new Error("upstream unavailable");
      return { status: 200, body: githubRelease(), etag: '"github-1"' };
    },
  });

  await invoke(updates.handleHttp);
  fail = true;
  clock += 300_001;
  const firstStale = await invoke(updates.handleHttp);
  const secondStale = await invoke(updates.handleHttp);

  assert.equal(firstStale.res.status, 200);
  assert.equal(secondStale.res.status, 200);
  assert.equal(JSON.parse(firstStale.res.body).version, "0.4.0");
  assert.equal(firstStale.res.headers.warning, '110 - "Response is stale"');
  assert.equal(secondStale.res.headers.warning, '110 - "Response is stale"');
  assert.equal(calls, 2);
});

test("returns cold-cache 503 with Retry-After when GitHub is unavailable", async () => {
  const updates = createUpdates({
    log() {},
    fetchLatest: async () => { throw new Error("offline"); },
  });
  const result = await invoke(updates.handleHttp);

  assert.equal(result.res.status, 503);
  assert.equal(result.res.headers["retry-after"], "60");
  assert.equal(result.res.headers["cache-control"], "no-store");
  assert.deepEqual(JSON.parse(result.res.body), { error: "update service unavailable" });
});

test("operator override is deterministic and never calls GitHub", async () => {
  let calls = 0;
  const logs = [];
  const updates = createUpdates({
    log: (line) => logs.push(line),
    overrideVersion: "0.4.0",
    fetchLatest: async () => {
      calls++;
      throw new Error("must not be called");
    },
  });

  const result = await invoke(updates.handleHttp);
  const body = JSON.parse(result.res.body);

  assert.equal(result.res.status, 200);
  assert.equal(calls, 0);
  assert.equal(body.version, "0.4.0");
  assert.equal(body.releaseUrl, "https://github.com/LuizinhoF/osplus/releases/tag/v0.4.0");
  assert.equal(body.assetUrl, "https://github.com/LuizinhoF/osplus/releases/download/v0.4.0/OSPlus.zip");
  assert.equal(body.publishedAt, null);
  assert.match(logs.join("\n"), /Operator override active/);
  assert.throws(
    () => createUpdates({ log() {}, overrideVersion: "0.4-beta" }),
    /strict stable semantic version/,
  );
});

test("leaves unrelated routes alone and rejects non-GET update requests", async () => {
  const updates = createUpdates({
    log() {},
    overrideVersion: "0.4.0",
  });

  const unrelated = await invoke(updates.handleHttp, { url: "/api/profiles/example" });
  const wrongMethod = await invoke(updates.handleHttp, { method: "POST" });

  assert.equal(unrelated.handled, false);
  assert.equal(unrelated.res.status, null);
  assert.equal(wrongMethod.handled, true);
  assert.equal(wrongMethod.res.status, 405);
  assert.equal(wrongMethod.res.headers.allow, "GET");
});
