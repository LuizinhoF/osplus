/**
 * Public OSPlus release-availability projection.
 * ------------------------------------------------
 * Serves GET /updates/latest without authentication. GitHub Releases remains
 * authoritative in normal operation; this module keeps only a short-lived
 * in-memory projection and never writes release state to disk.
 *
 * Failure posture is deliberately fail-open for players: a warm cache is
 * served stale when GitHub is unavailable, while a cold cache returns 503.
 * The operator-only version override exists for deterministic local testing
 * and is intentionally absent from production service configuration.
 */

const crypto = require("crypto");
const https = require("https");
const { URL } = require("url");

const DEFAULT_REPO = "LuizinhoF/osplus";
const DEFAULT_ASSET_NAME = "OSPlus.zip";
const DEFAULT_CACHE_TTL_MS = 5 * 60_000;
const DEFAULT_RETRY_AFTER_SEC = 60;
const GITHUB_TIMEOUT_MS = 10_000;
const MAX_GITHUB_BODY_BYTES = 512 * 1024;
const REPO_RE = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;
const STABLE_VERSION_RE = /^(?:v)?(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/;

function parseStableVersion(raw) {
  if (typeof raw !== "string") return null;
  const match = STABLE_VERSION_RE.exec(raw.trim());
  if (!match) return null;
  const parts = match.slice(1).map(Number);
  if (!parts.every(Number.isSafeInteger)) return null;
  return {
    major: parts[0],
    minor: parts[1],
    patch: parts[2],
    text: parts.join("."),
  };
}

function requireHttpsUrl(raw, fieldName) {
  if (typeof raw !== "string" || raw.length === 0) {
    throw new Error(`GitHub release missing ${fieldName}`);
  }
  let url;
  try { url = new URL(raw); }
  catch { throw new Error(`GitHub release has invalid ${fieldName}`); }
  if (url.protocol !== "https:") {
    throw new Error(`GitHub release ${fieldName} must use https`);
  }
  return url.toString();
}

function normalizeGithubRelease(raw, assetName = DEFAULT_ASSET_NAME) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    throw new Error("GitHub release response is not an object");
  }
  if (raw.draft !== false || raw.prerelease !== false) {
    throw new Error("GitHub latest release is not a published stable release");
  }

  const parsedVersion = parseStableVersion(raw.tag_name);
  if (!parsedVersion) {
    throw new Error("GitHub release tag is not a strict stable semantic version");
  }

  const assets = Array.isArray(raw.assets) ? raw.assets : [];
  const asset = assets.find((candidate) => candidate && candidate.name === assetName);
  if (!asset) {
    throw new Error(`GitHub release is missing required asset ${assetName}`);
  }

  if (typeof raw.published_at !== "string" || !Number.isFinite(Date.parse(raw.published_at))) {
    throw new Error("GitHub release has invalid published_at");
  }

  return {
    schemaVersion: 1,
    channel: "stable",
    version: parsedVersion.text,
    releaseUrl: requireHttpsUrl(raw.html_url, "html_url"),
    assetUrl: requireHttpsUrl(asset.browser_download_url, "asset download URL"),
    publishedAt: new Date(raw.published_at).toISOString(),
  };
}

function createOverrideManifest({ repo, assetName, version }) {
  const parsedVersion = parseStableVersion(version);
  if (!parsedVersion) {
    throw new Error("OSPLUS_RELEASE_OVERRIDE_VERSION must be a strict stable semantic version");
  }
  const tag = `v${parsedVersion.text}`;
  const encodedAsset = encodeURIComponent(assetName);
  return {
    schemaVersion: 1,
    channel: "stable",
    version: parsedVersion.text,
    releaseUrl: `https://github.com/${repo}/releases/tag/${tag}`,
    assetUrl: `https://github.com/${repo}/releases/download/${tag}/${encodedAsset}`,
    publishedAt: null,
  };
}

function createEtag(manifest) {
  const digest = crypto
    .createHash("sha256")
    .update(JSON.stringify(manifest))
    .digest("base64url");
  return `"${digest}"`;
}

function etagMatches(rawHeader, expected) {
  if (typeof rawHeader !== "string") return false;
  const normalizedExpected = expected.replace(/^W\//, "");
  return rawHeader.split(",").some((candidate) => {
    const token = candidate.trim();
    return token === "*" || token.replace(/^W\//, "") === normalizedExpected;
  });
}

function requestLatestGithubRelease({
  repo,
  token = "",
  previousEtag = "",
}) {
  return new Promise((resolve, reject) => {
    const url = new URL(`https://api.github.com/repos/${repo}/releases/latest`);
    const headers = {
      "Accept": "application/vnd.github+json",
      "User-Agent": "osplus-relay",
      "X-GitHub-Api-Version": "2022-11-28",
    };
    if (token) headers.Authorization = `Bearer ${token}`;
    if (previousEtag) headers["If-None-Match"] = previousEtag;

    const req = https.request({
      protocol: url.protocol,
      hostname: url.hostname,
      port: 443,
      method: "GET",
      path: url.pathname,
      headers,
      timeout: GITHUB_TIMEOUT_MS,
    }, (res) => {
      if (res.statusCode === 304) {
        res.resume();
        resolve({ status: 304, body: null, etag: res.headers.etag || previousEtag });
        return;
      }

      const chunks = [];
      let totalBytes = 0;
      res.on("data", (chunk) => {
        totalBytes += chunk.length;
        if (totalBytes > MAX_GITHUB_BODY_BYTES) {
          req.destroy(new Error(`GitHub response exceeded ${MAX_GITHUB_BODY_BYTES} bytes`));
          return;
        }
        chunks.push(chunk);
      });
      res.on("end", () => {
        const raw = Buffer.concat(chunks).toString("utf8");
        if (res.statusCode !== 200) {
          reject(new Error(`GitHub latest release returned HTTP ${res.statusCode}`));
          return;
        }
        let body;
        try { body = JSON.parse(raw); }
        catch {
          reject(new Error("GitHub latest release returned malformed JSON"));
          return;
        }
        resolve({ status: 200, body, etag: res.headers.etag || "" });
      });
      res.on("error", reject);
    });

    req.on("timeout", () => {
      req.destroy(new Error(`GitHub request timed out after ${GITHUB_TIMEOUT_MS}ms`));
    });
    req.on("error", reject);
    req.end();
  });
}

function createUpdates({
  log,
  repo = DEFAULT_REPO,
  assetName = DEFAULT_ASSET_NAME,
  cacheTtlMs = DEFAULT_CACHE_TTL_MS,
  githubToken = "",
  overrideVersion = "",
  fetchLatest = requestLatestGithubRelease,
  now = Date.now,
} = {}) {
  if (typeof log !== "function") throw new Error("createUpdates requires log");
  if (!REPO_RE.test(repo)) throw new Error(`invalid OSPlus release repo: ${repo}`);
  if (typeof assetName !== "string" || assetName.trim() === "") {
    throw new Error("OSPlus release asset name must not be empty");
  }
  if (!Number.isSafeInteger(cacheTtlMs) || cacheTtlMs <= 0) {
    throw new Error("OSPlus release cache TTL must be a positive integer");
  }

  const cleanAssetName = assetName.trim();
  let cached = null;
  let refreshInFlight = null;
  let staleRetryAfter = 0;
  let overrideEntry = null;

  if (overrideVersion) {
    const manifest = createOverrideManifest({
      repo,
      assetName: cleanAssetName,
      version: overrideVersion,
    });
    overrideEntry = {
      manifest,
      body: JSON.stringify(manifest),
      etag: createEtag(manifest),
      checkedAt: now(),
      upstreamEtag: "",
    };
    log(`[UPDATES] [!] Operator override active at v${manifest.version}; GitHub will not be queried`);
  } else {
    log(`[UPDATES] Source: GitHub ${repo}, asset ${cleanAssetName}, cache ${cacheTtlMs}ms`);
  }

  async function refresh() {
    try {
      const response = await fetchLatest({
        repo,
        assetName: cleanAssetName,
        token: githubToken,
        previousEtag: cached ? cached.upstreamEtag : "",
      });

      if (response.status === 304) {
        if (!cached) throw new Error("GitHub returned 304 without a cached release");
        cached.checkedAt = now();
        staleRetryAfter = 0;
        log(`[UPDATES] GitHub cache revalidated at v${cached.manifest.version}`);
        return { entry: cached, stale: false };
      }
      if (response.status !== 200) {
        throw new Error(`GitHub latest release returned unexpected status ${response.status}`);
      }

      const manifest = normalizeGithubRelease(response.body, cleanAssetName);
      cached = {
        manifest,
        body: JSON.stringify(manifest),
        etag: createEtag(manifest),
        checkedAt: now(),
        upstreamEtag: typeof response.etag === "string" ? response.etag : "",
      };
      staleRetryAfter = 0;
      log(`[UPDATES] Cached stable release v${manifest.version}`);
      return { entry: cached, stale: false };
    } catch (err) {
      log(`[UPDATES] [ERR] Refresh failed: ${err.message}`);
      if (cached) {
        staleRetryAfter = now() + DEFAULT_RETRY_AFTER_SEC * 1000;
        return { entry: cached, stale: true };
      }
      throw err;
    }
  }

  async function getLatest() {
    if (overrideEntry) return { entry: overrideEntry, stale: false };
    if (cached && now() - cached.checkedAt < cacheTtlMs) {
      return { entry: cached, stale: false };
    }
    if (cached && now() < staleRetryAfter) {
      return { entry: cached, stale: true };
    }
    if (!refreshInFlight) {
      refreshInFlight = refresh().finally(() => {
        refreshInFlight = null;
      });
    }
    return refreshInFlight;
  }

  async function handleHttp(req, res) {
    let url;
    try { url = new URL(req.url, "http://x"); }
    catch { return false; }
    if (url.pathname !== "/updates/latest") return false;

    if (req.method !== "GET") {
      writeJson(res, 405, { error: "method not allowed" }, { Allow: "GET" });
      return true;
    }

    let result;
    try {
      result = await getLatest();
    } catch {
      writeJson(
        res,
        503,
        { error: "update service unavailable" },
        { "Cache-Control": "no-store", "Retry-After": String(DEFAULT_RETRY_AFTER_SEC) },
      );
      return true;
    }

    const headers = {
      "Cache-Control": `public, max-age=${Math.floor(cacheTtlMs / 1000)}, stale-if-error=86400`,
      "ETag": result.entry.etag,
    };
    if (result.stale) headers.Warning = '110 - "Response is stale"';

    if (etagMatches(req.headers && req.headers["if-none-match"], result.entry.etag)) {
      res.writeHead(304, headers);
      res.end();
      return true;
    }

    res.writeHead(200, {
      ...headers,
      "Content-Type": "application/json",
      "Content-Length": Buffer.byteLength(result.entry.body),
    });
    res.end(result.entry.body);
    return true;
  }

  return { handleHttp, _getLatest: getLatest };
}

function writeJson(res, status, body, extraHeaders = {}) {
  const raw = JSON.stringify(body);
  res.writeHead(status, {
    "Content-Type": "application/json",
    "Content-Length": Buffer.byteLength(raw),
    ...extraHeaders,
  });
  res.end(raw);
}

module.exports = {
  DEFAULT_ASSET_NAME,
  DEFAULT_CACHE_TTL_MS,
  DEFAULT_REPO,
  createOverrideManifest,
  createUpdates,
  etagMatches,
  normalizeGithubRelease,
  parseStableVersion,
  requestLatestGithubRelease,
};
