/**
 * Sidecar update-availability client.
 * -----------------------------------
 * Reads the installed OSPlus version marker, checks the relay's public
 * release projection over HTTP(S), compares numeric stable versions, and
 * emits a flat update_available event into Lua's inbox.
 *
 * Network success is cached for five minutes, but presentation is not
 * deduplicated here: Lua owns session-level notice/sound state, and the inbox
 * can be truncated during map loads. Every accepted lifecycle trigger may
 * therefore re-emit cached availability; only concurrent checks coalesce.
 * See docs/learnings/update-availability-is-durable-state.md.
 */

const fs = require("fs");
const http = require("http");
const https = require("https");
const path = require("path");
const { URL } = require("url");

const CHECK_COOLDOWN_MS = 5 * 60_000;
const REQUEST_TIMEOUT_MS = 10_000;
const MAX_RESPONSE_BYTES = 64 * 1024;
const STABLE_VERSION_RE = /^(?:v)?(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/;
const ALLOWED_REASONS = new Set(["startup", "queue_entered", "match_completed"]);

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

function compareStableVersions(left, right) {
  const a = parseStableVersion(left);
  const b = parseStableVersion(right);
  if (!a || !b) throw new Error("cannot compare malformed stable versions");
  for (const key of ["major", "minor", "patch"]) {
    if (a[key] > b[key]) return 1;
    if (a[key] < b[key]) return -1;
  }
  return 0;
}

function requireHttpUrl(raw, label) {
  if (typeof raw !== "string" || raw.trim() === "") {
    throw new Error(`${label} is empty`);
  }
  let url;
  try { url = new URL(raw.trim()); }
  catch { throw new Error(`${label} is not a valid URL`); }
  if (url.protocol !== "http:" && url.protocol !== "https:") {
    throw new Error(`${label} must use http or https`);
  }
  return url.toString();
}

function resolveUpdateUrl({ relayUrl, config = {}, env = process.env }) {
  if (typeof env.OSPLUS_UPDATE_URL === "string" && env.OSPLUS_UPDATE_URL.trim() !== "") {
    return requireHttpUrl(env.OSPLUS_UPDATE_URL, "OSPLUS_UPDATE_URL");
  }
  if (typeof config.update_url === "string" && config.update_url.trim() !== "") {
    return requireHttpUrl(config.update_url, "config.update_url");
  }

  let relay;
  try { relay = new URL(relayUrl); }
  catch { throw new Error("relay URL is invalid; cannot derive update URL"); }
  if (relay.protocol === "wss:") relay.protocol = "https:";
  else if (relay.protocol === "ws:") relay.protocol = "http:";
  else if (relay.protocol !== "http:" && relay.protocol !== "https:") {
    throw new Error(`unsupported relay protocol: ${relay.protocol}`);
  }
  relay.pathname = "/updates/latest";
  relay.search = "";
  relay.hash = "";
  return relay.toString();
}

function installedVersionCandidates({
  execPath = process.execPath,
  moduleDir = __dirname,
} = {}) {
  return [
    path.resolve(path.dirname(execPath), "..", "version.json"),
    path.resolve(moduleDir, "..", "dist", "version.json"),
  ];
}

function loadInstalledVersion({
  candidates = installedVersionCandidates(),
  readFileSync = fs.readFileSync,
  log,
}) {
  for (const candidate of candidates) {
    try {
      let raw = readFileSync(candidate, "utf8");
      if (raw.charCodeAt(0) === 0xFEFF) raw = raw.slice(1);
      const manifest = JSON.parse(raw);
      const parsed = parseStableVersion(manifest && manifest.version);
      if (!parsed) {
        log(`[UPDATES] [!] Installed marker has invalid version: ${candidate}`);
        continue;
      }
      return { version: parsed.text, path: candidate };
    } catch (err) {
      if (err && err.code === "ENOENT") continue;
      log(`[UPDATES] [!] Installed marker could not be read: ${candidate} (${err.message})`);
    }
  }
  log(`[UPDATES] [!] No valid installed version marker found; update checks disabled`);
  return null;
}

function requestUpdateManifest({ url, etag = "" }) {
  return new Promise((resolve, reject) => {
    const target = new URL(url);
    const lib = target.protocol === "https:" ? https : http;
    const headers = { "Accept": "application/json" };
    if (etag) headers["If-None-Match"] = etag;

    const req = lib.request({
      protocol: target.protocol,
      hostname: target.hostname,
      port: target.port || (target.protocol === "https:" ? 443 : 80),
      method: "GET",
      path: target.pathname + target.search,
      headers,
      timeout: REQUEST_TIMEOUT_MS,
    }, (res) => {
      if (res.statusCode === 304) {
        res.resume();
        resolve({ status: 304, body: null, etag: res.headers.etag || etag });
        return;
      }

      const chunks = [];
      let totalBytes = 0;
      res.on("data", (chunk) => {
        totalBytes += chunk.length;
        if (totalBytes > MAX_RESPONSE_BYTES) {
          req.destroy(new Error(`update response exceeded ${MAX_RESPONSE_BYTES} bytes`));
          return;
        }
        chunks.push(chunk);
      });
      res.on("end", () => {
        const raw = Buffer.concat(chunks).toString("utf8");
        let body = null;
        let parseError = false;
        if (raw.length > 0) {
          try { body = JSON.parse(raw); }
          catch { parseError = true; }
        }
        resolve({
          status: res.statusCode,
          body,
          etag: res.headers.etag || "",
          parseError,
        });
      });
      res.on("error", reject);
    });

    req.on("timeout", () => {
      req.destroy(new Error(`update request timed out after ${REQUEST_TIMEOUT_MS}ms`));
    });
    req.on("error", reject);
    req.end();
  });
}

function normalizeUpdateManifest(raw) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    throw new Error("response body is not an object");
  }
  if (raw.schemaVersion !== 1 || raw.channel !== "stable") {
    throw new Error("response has unsupported schema or channel");
  }
  const version = parseStableVersion(raw.version);
  if (!version) throw new Error("response version is not a strict stable semantic version");

  const releaseUrl = requireHttpUrl(raw.releaseUrl, "response releaseUrl");
  const assetUrl = requireHttpUrl(raw.assetUrl, "response assetUrl");
  if (
    raw.publishedAt !== null &&
    (typeof raw.publishedAt !== "string" || !Number.isFinite(Date.parse(raw.publishedAt)))
  ) {
    throw new Error("response publishedAt is invalid");
  }

  return {
    version: version.text,
    releaseUrl,
    assetUrl,
  };
}

function createUpdateClient({
  log,
  emit,
  relayUrl,
  config = {},
  env = process.env,
  markerCandidates,
  request = requestUpdateManifest,
  now = Date.now,
  cooldownMs = CHECK_COOLDOWN_MS,
} = {}) {
  if (typeof log !== "function") throw new Error("createUpdateClient requires log");
  if (typeof emit !== "function") throw new Error("createUpdateClient requires emit");
  if (!Number.isSafeInteger(cooldownMs) || cooldownMs <= 0) {
    throw new Error("update cooldown must be a positive integer");
  }

  let updateUrl = null;
  try {
    updateUrl = resolveUpdateUrl({ relayUrl, config, env });
  } catch (err) {
    log(`[UPDATES] [!] Update URL configuration is invalid: ${err.message}; checks disabled`);
  }

  const installed = loadInstalledVersion({
    candidates: markerCandidates || installedVersionCandidates(),
    log,
  });
  const enabled = Boolean(updateUrl && installed);

  let latest = null;
  let etag = "";
  let lastSuccessAt = null;
  let inFlight = null;

  if (enabled) {
    log(`[UPDATES] Installed v${installed.version} from ${installed.path}`);
    log(`[UPDATES] Endpoint: ${updateUrl}`);
  }

  function emitIfNewer(release, reason) {
    if (compareStableVersions(release.version, installed.version) <= 0) {
      log(`[UPDATES] ${reason}: installed v${installed.version} is current (latest v${release.version})`);
      return { available: false, version: release.version };
    }

    const event = {
      type: "update_available",
      installedVersion: installed.version,
      latestVersion: release.version,
      releaseUrl: release.releaseUrl,
      assetUrl: release.assetUrl,
      ts: Math.floor(now() / 1000),
    };
    emit(event);
    log(`[UPDATES] ${reason}: emitted update_available for v${release.version}`);
    return { available: true, version: release.version };
  }

  function useCachedAfterFailure(reason, error) {
    if (!latest) return { available: false, error };
    log(`[UPDATES] ${reason}: retaining previously validated v${latest.version}`);
    return { ...emitIfNewer(latest, reason), stale: true, error };
  }

  async function fetchAndCompare(reason) {
    let response;
    try {
      response = await request({ url: updateUrl, etag });
    } catch (err) {
      log(`[UPDATES] ${reason}: request failed (${err.message})`);
      return useCachedAfterFailure(reason, "transport");
    }

    if (response.status === 304) {
      if (!latest) {
        log(`[UPDATES] ${reason}: ignored 304 without a cached release`);
        return { available: false, error: "invalid-304" };
      }
      if (typeof response.etag === "string" && response.etag) etag = response.etag;
      lastSuccessAt = now();
      return emitIfNewer(latest, reason);
    }

    if (response.status !== 200) {
      log(`[UPDATES] ${reason}: endpoint returned HTTP ${response.status}`);
      return useCachedAfterFailure(reason, `http-${response.status}`);
    }
    if (response.parseError) {
      log(`[UPDATES] ${reason}: endpoint returned malformed JSON`);
      return useCachedAfterFailure(reason, "malformed-json");
    }

    let normalized;
    try { normalized = normalizeUpdateManifest(response.body); }
    catch (err) {
      log(`[UPDATES] ${reason}: invalid release data (${err.message})`);
      return useCachedAfterFailure(reason, "invalid-release");
    }

    latest = normalized;
    etag = typeof response.etag === "string" ? response.etag : "";
    lastSuccessAt = now();
    return emitIfNewer(latest, reason);
  }

  function check(reason) {
    if (!ALLOWED_REASONS.has(reason)) {
      log(`[UPDATES] [!] Ignored update check with invalid reason: ${String(reason)}`);
      return Promise.resolve({ available: false, error: "invalid-reason" });
    }
    if (!enabled) {
      return Promise.resolve({ available: false, error: "disabled" });
    }
    if (inFlight) {
      log(`[UPDATES] ${reason}: coalesced with in-flight check`);
      return inFlight;
    }

    if (latest && lastSuccessAt !== null && now() - lastSuccessAt < cooldownMs) {
      log(`[UPDATES] ${reason}: using cached release v${latest.version}`);
      return Promise.resolve(emitIfNewer(latest, reason));
    }

    inFlight = fetchAndCompare(reason).finally(() => {
      inFlight = null;
    });
    return inFlight;
  }

  function handleUpdateCheck(rawMsg) {
    if (!rawMsg || typeof rawMsg !== "object") {
      log(`[UPDATES] [!] update_check dropped: not an object`);
      return Promise.resolve({ available: false, error: "invalid-message" });
    }
    return check(rawMsg.reason);
  }

  return {
    check,
    handleUpdateCheck,
    _enabled: enabled,
    _installedVersion: installed ? installed.version : null,
    _updateUrl: updateUrl,
  };
}

module.exports = {
  ALLOWED_REASONS,
  CHECK_COOLDOWN_MS,
  compareStableVersions,
  createUpdateClient,
  installedVersionCandidates,
  loadInstalledVersion,
  normalizeUpdateManifest,
  parseStableVersion,
  requestUpdateManifest,
  resolveUpdateUrl,
};
