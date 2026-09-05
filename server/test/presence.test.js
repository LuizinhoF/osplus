const assert = require("node:assert/strict");
const fs = require("node:fs");
const http = require("node:http");
const { createRequire } = require("node:module");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");
const WebSocket = require("ws");

// Exercise the real relay and real sockets without opening its database,
// contacting GitHub, or changing process-wide environment/signal handlers.
async function startRelay(t) {
  const entry = path.resolve(__dirname, "../index.js");
  const realRequire = createRequire(entry);
  let server;
  let ready;
  const listening = new Promise((resolve) => { ready = resolve; });
  vm.runInNewContext(fs.readFileSync(entry, "utf8"), {
    require(name) {
      if (name === "http") return {
        createServer(handler) {
          server = http.createServer(handler);
          server.once("listening", ready);
          return server;
        },
      };
      if (name === "./api") return { createApi: () => ({ handleHttp: async () => false, close() {} }) };
      if (name === "./updates") return {
        DEFAULT_REPO: "LuizinhoF/osplus", DEFAULT_ASSET_NAME: "OSPlus.zip",
        DEFAULT_CACHE_TTL_MS: 300_000,
        createUpdates: () => ({ handleHttp: async () => false }),
      };
      return realRequire(name);
    },
    __dirname: path.dirname(entry),
    process: { env: { PORT: "0", HOST: "127.0.0.1" }, on() {}, uptime: () => 0 },
    console: { log() {} }, URL, setTimeout,
  }, { filename: entry });
  await listening;
  const clients = [];
  t.after(async () => {
    for (const client of clients) client.socket.terminate();
    await new Promise((resolve) => server.close(resolve));
  });
  return async function connect() {
    const socket = new WebSocket(`ws://127.0.0.1:${server.address().port}`);
    const messages = [];
    const waiters = new Set();
    socket.on("message", (raw) => {
      const message = JSON.parse(raw);
      messages.push(message);
      for (const waiter of [...waiters]) waiter();
    });
    await new Promise((resolve, reject) => {
      socket.once("open", resolve);
      socket.once("error", reject);
    });
    const client = {
      socket, messages,
      send(message) { socket.send(JSON.stringify(message)); },
      waitFor(predicate, after = 0) {
        return new Promise((resolve, reject) => {
          const timer = setTimeout(() => {
            waiters.delete(check);
            reject(new Error(`Missing expected relay message: ${JSON.stringify(messages.slice(after))}`));
          }, 2000);
          function check() {
            const found = messages.slice(after).find(predicate);
            if (found) { clearTimeout(timer); waiters.delete(check); resolve(found); }
          }
          waiters.add(check);
          check();
        });
      },
      async join(fields) {
        const start = messages.length;
        this.send({ type: "join", room: "PREGAME1", ...fields });
        const joined = await this.waitFor((msg) => msg.type === "joined", start);
        // Other members' earlier joins can still have snapshots in flight.
        // The joiner's new-context snapshot follows its own acknowledgement.
        return this.waitFor((msg) => msg.type === "presence", messages.indexOf(joined) + 1);
      },
    };
    clients.push(client);
    return client;
  };
}

function memberNames(message) {
  return message.members.split("\n").filter(Boolean).sort();
}

test("pregame presence keeps opponents, unknown players, and spectators out of teammate lists", async (t) => {
  const connect = await startRelay(t);
  const alice = await connect();
  const ally = await connect();
  const bob = await connect();
  const beryl = await connect();
  const unknown = await connect();
  await alice.join({ username: "Alice", team: 0, presenceRevision: 11 });
  await ally.join({ username: "Ally", team: 0, presenceRevision: 21 });
  await bob.join({ username: "Bob", team: 1, presenceRevision: 31 });
  await beryl.join({ username: "Beryl", team: 1, presenceRevision: 41 });
  const selfOnly = await unknown.join({ username: "Unknown", presenceRevision: 51 });
  assert.deepEqual(memberNames(selfOnly), ["Unknown"]);
  assert.equal(selfOnly.revealOpponents, false);
  assert.equal(selfOnly.presenceRevision, 51);
  assert.deepEqual(memberNames(await alice.waitFor((msg) => msg.type === "presence" && msg.members.includes("Ally"))), ["Alice", "Ally"]);
  assert.deepEqual(memberNames(await bob.waitFor((msg) => msg.type === "presence" && msg.members.includes("Beryl"))), ["Beryl", "Bob"]);
  const withoutUnknown = await alice.join({ username: "Alice", team: 0, presenceRevision: 12 });
  assert.deepEqual(memberNames(withoutUnknown), ["Alice", "Ally"]);

  const spectator = await unknown.join({ username: "Caster", team: 0, spectator: true, presenceRevision: 52 });
  assert.deepEqual(memberNames(spectator), ["Caster"]);
  const aliceRefresh = await alice.join({ username: "Alice", team: 0, presenceRevision: 13 });
  assert.deepEqual(memberNames(aliceRefresh), ["Alice", "Ally"]);
  assert.equal(aliceRefresh.presenceRevision, 13);
});

test("gameplay disclosure is per recipient and rejoining can restrict or change team context", async (t) => {
  const connect = await startRelay(t);
  const alice = await connect();
  const ally = await connect();
  const bob = await connect();
  const spectator = await connect();
  await alice.join({ username: "Alice", team: 0, presenceRevision: 1 });
  await ally.join({ username: "Ally", team: 0, presenceRevision: 1 });
  await bob.join({ username: "Bob", team: 1, presenceRevision: 1 });
  await spectator.join({ username: "Caster", spectator: true, presenceRevision: 1 });
  const unlocked = await alice.join({ username: "Alice", team: 0, revealOpponents: true, presenceRevision: 2 });
  assert.deepEqual(memberNames(unlocked), ["Alice", "Ally", "Bob", "Caster"]);
  assert.equal(unlocked.revealOpponents, true);
  assert.equal(unlocked.presenceRevision, 2);
  const stillRestricted = await bob.join({ username: "Bob", team: 1, presenceRevision: 2 });
  assert.deepEqual(memberNames(stillRestricted), ["Bob"]);
  assert.equal(stillRestricted.revealOpponents, false);
  const changedTeam = await alice.join({ username: "Renamed", team: 1, revealOpponents: false, presenceRevision: 3 });
  assert.deepEqual(memberNames(changedTeam), ["Bob", "Renamed"]);
  assert.equal(changedTeam.presenceRevision, 3);
  const spectatorUnlocked = await spectator.join({ username: "Caster", spectator: true, revealOpponents: true, presenceRevision: 2 });
  assert.deepEqual(memberNames(spectatorUnlocked), ["Ally", "Bob", "Caster", "Renamed"]);
});

test("legacy or malformed disclosure metadata defaults to restricted presence", async (t) => {
  const connect = await startRelay(t);
  const enemy = await connect();
  await enemy.join({ username: "Enemy", team: 1, revealOpponents: true, presenceRevision: 7 });
  const values = [undefined, "true", 1, "1", {}, null];
  for (const value of values) {
    const client = await connect();
    const result = await client.join({ username: "Local", team: 0, revealOpponents: value, presenceRevision: value });
    assert.deepEqual(memberNames(result), ["Local"]);
    assert.equal(result.revealOpponents, false);
    assert.equal(result.presenceRevision, value === 1 ? 1 : 0);
    client.socket.close();
    await new Promise((resolve) => client.socket.once("close", resolve));
  }
});

test("malformed teams stay unknown and invalid revision shapes normalize to zero", async (t) => {
  const connect = await startRelay(t);
  const teamZero = await connect();
  const teamOne = await connect();
  await teamZero.join({ username: "TeamZero", team: 0, presenceRevision: 1 });
  await teamOne.join({ username: "TeamOne", team: 1, presenceRevision: 1 });
  for (const team of [undefined, null, false, true, {}, [], "", " ", 2]) {
    const client = await connect();
    const result = await client.join({ username: "Unknown", team, presenceRevision: 1 });
    assert.deepEqual(memberNames(result), ["Unknown"]);
    client.socket.close();
    await new Promise((resolve) => client.socket.once("close", resolve));
  }
  for (const [team, peer] of [["0", "TeamZero"], ["1", "TeamOne"]]) {
    const client = await connect();
    const result = await client.join({ username: "NumericString", team, presenceRevision: 1 });
    assert.deepEqual(memberNames(result), ["NumericString", peer]);
    client.socket.close();
    await new Promise((resolve) => client.socket.once("close", resolve));
  }
  for (const presenceRevision of [-1, 0, 1.5, Number.MAX_SAFE_INTEGER + 1, "2"]) {
    const client = await connect();
    const result = await client.join({ username: "InvalidRevision", team: 0, presenceRevision });
    assert.equal(result.presenceRevision, 0);
    client.socket.close();
    await new Promise((resolve) => client.socket.once("close", resolve));
  }
});

test("room switches, leave, and reconnect do not retain old presence metadata", async (t) => {
  const connect = await startRelay(t);
  const client = await connect();
  const peer = await connect();
  await peer.join({ username: "Peer", team: 1, presenceRevision: 1 });
  await client.join({ username: "Local", team: 0, revealOpponents: true, presenceRevision: 8 });
  const otherRoom = await client.join({ room: "NEXTROOM", username: "Local", team: 0, presenceRevision: 9 });
  assert.equal(otherRoom.room, "NEXTROOM");
  assert.deepEqual(memberNames(otherRoom), ["Local"]);
  assert.equal(otherRoom.revealOpponents, false);
  const beforeLeave = client.messages.length;
  client.send({ type: "leave" });
  await client.waitFor((msg) => msg.type === "left", beforeLeave);
  const legacy = await client.join({ username: "Local", team: 0 });
  assert.equal(legacy.presenceRevision, 0);
  assert.equal(legacy.revealOpponents, false);
  client.socket.close();
  await new Promise((resolve) => client.socket.once("close", resolve));
  const reconnected = await connect();
  const restored = await reconnected.join({ username: "Local", team: 0, revealOpponents: true, presenceRevision: 10 });
  assert.deepEqual(memberNames(restored), ["Local", "Peer"]);
  assert.equal(restored.presenceRevision, 10);
});

test("team and all-player chat routing is unchanged by presence privacy", async (t) => {
  const connect = await startRelay(t);
  const alice = await connect();
  const ally = await connect();
  const bob = await connect();
  const caster = await connect();
  await alice.join({ username: "Alice", team: 0, presenceRevision: 1 });
  await ally.join({ username: "Ally", team: 0, presenceRevision: 1 });
  await bob.join({ username: "Bob", team: 1, presenceRevision: 1 });
  await caster.join({ username: "Caster", spectator: true, presenceRevision: 1 });
  alice.send({ type: "chat", text: "team only", audience: "team", targetTeam: 0 });
  await ally.waitFor((msg) => msg.type === "chat" && msg.text === "team only");
  alice.send({ type: "chat", text: "everyone", audience: "all" });
  await Promise.all([ally, bob, caster].map((client) => client.waitFor((msg) => msg.type === "chat" && msg.text === "everyone")));
  assert.equal(bob.messages.some((msg) => msg.text === "team only"), false);
  assert.equal(caster.messages.some((msg) => msg.text === "team only"), false);
  alice.send({ type: "chat", text: "forbidden", audience: "team", targetTeam: 1 });
  await alice.waitFor((msg) => msg.type === "error" && msg.error === "players cannot target the other team");
  caster.send({ type: "chat", text: "caster team two", audience: "team", targetTeam: 1 });
  await bob.waitFor((msg) => msg.type === "chat" && msg.text === "caster team two");
  assert.equal(ally.messages.some((msg) => msg.text === "caster team two"), false);
});
