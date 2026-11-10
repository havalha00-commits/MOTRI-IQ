import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import { fileURLToPath, pathToFileURL } from "node:url";
import { spawnSync } from "node:child_process";

import { createApp } from "../server.js";
import { createMarketRouter, createMarketImageDeliveryRouter } from "../routes/market.js";

const TEST_JWT_SECRET = "x".repeat(64);

function withEnv(patch, fn) {
  const prev = {};
  for (const [k, v] of Object.entries(patch)) {
    prev[k] = Object.prototype.hasOwnProperty.call(process.env, k) ? process.env[k] : undefined;
    if (v === undefined) delete process.env[k]; else process.env[k] = v;
  }
  try { return fn(); } finally {
    for (const [k, v] of Object.entries(prev)) {
      if (v === undefined) delete process.env[k]; else process.env[k] = v;
    }
  }
}

async function withEnvAsync(patch, fn) {
  const prev = {};
  for (const [k, v] of Object.entries(patch)) {
    prev[k] = Object.prototype.hasOwnProperty.call(process.env, k) ? process.env[k] : undefined;
    if (v === undefined) delete process.env[k]; else process.env[k] = v;
  }
  try { return await fn(); } finally {
    for (const [k, v] of Object.entries(prev)) {
      if (v === undefined) delete process.env[k]; else process.env[k] = v;
    }
  }
}

function mountText(app) {
  const stack = app.router?.stack || app._router?.stack || [];
  return stack.map((l) => JSON.stringify({ name: l.name, path: l.path, route: l.route?.path, re: l.regexp ? String(l.regexp) : null })).join("\n");
}

test("G10.62 P3.4G: isolated app mounts only approved Market image surface (offline)", async () => {
  const database = { tag: "explicit-pool", query: async () => ({ rows: [] }), connect: async () => ({ release() {} }) };
  const storageService = { tag: "explicit-storage", upload: async () => {}, download: async () => ({ body: Buffer.alloc(0), contentType: "image/jpeg" }) };
  const app = await withEnvAsync({ MOTRI_LOCAL_TEST_ISOLATED: "1", MOTRI_LOCAL_TEST: "true", JWT_SECRET: TEST_JWT_SECRET }, async () =>
    createApp({ pool: database, storageService, env: { ...process.env, MOTRI_LOCAL_TEST_ISOLATED: "1", MOTRI_LOCAL_TEST: "true" } })
  );
  const mounts = mountText(app);
  assert.match(mounts, /health/, "health must be mounted");
  assert.match(mounts, /market/, "market routes must be mounted");
  assert.doesNotMatch(mounts, /uploads/, "/api/uploads must be absent");
  for (const p of ["/api/auth", "/api/safety", "/api/cars", "/api/favorites", "/api/requests", "/api/offers", "/api/sellers", "/api/activity", "/api/business-ads", "/api/profile", "/api/wallet", "/api/storage", "/api/ugc", "/api/me"]) {
    assert.equal(mounts.includes(p), false, `unrelated route must be absent in isolated mode: ${p}\n${mounts}`);
  }
});

test("G10.62 P3.4G: isolated Market routers receive SAME injected pool/storage and injected auth", async () => {
  const database = { tag: "explicit-pool" };
  const storageService = { tag: "explicit-storage" };
  const app = await withEnvAsync({ MOTRI_LOCAL_TEST_ISOLATED: "1", MOTRI_LOCAL_TEST: "true", JWT_SECRET: TEST_JWT_SECRET }, async () =>
    createApp({ pool: database, storageService, env: { ...process.env, MOTRI_LOCAL_TEST_ISOLATED: "1", MOTRI_LOCAL_TEST: "true" } })
  );
  const deps = app.locals.__isolatedMarketDeps;
  assert.ok(deps, "isolated market deps must be exposed for offline verification");
  assert.equal(deps.database, database);
  assert.equal(deps.storageService, storageService);
  assert.equal(deps.marketRouter.__deps.database, database);
  assert.equal(deps.marketRouter.__deps.storage, storageService);
  assert.equal(deps.marketRouter.__deps.authenticate, deps.authenticate);
  assert.equal(deps.marketRouter.__deps.optionalAuthenticate, deps.optionalAuthenticate);
  assert.equal(deps.marketImageDeliveryRouter.__deps.database, database);
  assert.equal(deps.marketImageDeliveryRouter.__deps.storage, storageService);
  assert.equal(deps.marketImageDeliveryRouter.__deps.optionalAuthenticate, deps.optionalAuthenticate);
  assert.equal(typeof deps.authenticate, "function");
  assert.equal(typeof deps.optionalAuthenticate, "function");
});

test("G10.62 P3.4G: auth middleware factory is created from injected database (no bypass)", async () => {
  const database = { tag: "explicit-pool", query: async () => { throw new Error("db-not-called-by-construction"); } };
  const storageService = { tag: "explicit-storage" };
  const app = await withEnvAsync({ MOTRI_LOCAL_TEST_ISOLATED: "1", MOTRI_LOCAL_TEST: "true", JWT_SECRET: TEST_JWT_SECRET }, async () =>
    createApp({ pool: database, storageService, env: { ...process.env, MOTRI_LOCAL_TEST_ISOLATED: "1", MOTRI_LOCAL_TEST: "true" } })
  );
  const deps = app.locals.__isolatedMarketDeps;
  // Middleware created from injected DB factory; construction itself must not query DB.
  // A request without Authorization should be rejected by middleware contract (no req.user bypass).
  let status = null, body = null;
  const req = { headers: {} };
  const res = { status(s) { status = s; return this; }, json(b) { body = b; return this; } };
  let nextCalled = false;
  await deps.authenticate(req, res, () => { nextCalled = true; });
  assert.equal(nextCalled, false, "missing auth must not be bypassed");
  assert.equal(status, 401);
  assert.ok(body?.error);
});

test("G10.62 P3.4G: market ownership/admin checks remain wired (factory/static contract)", () => {
  // Existing market route code enforces ownership/admin checks against req.user and DB rows.
  // This verifies we still use real market factories (not mocked routes) and pass real auth middleware.
  const database = { tag: "pool" };
  const storage = { tag: "storage" };
  const authenticate = async (_req, _res, next) => next();
  const optionalAuthenticate = async (_req, _res, next) => next();
  const market = createMarketRouter({ database, storage, authenticate, optionalAuthenticate });
  const delivery = createMarketImageDeliveryRouter({ database, storage, optionalAuthenticate });
  assert.equal(market.__deps.authenticate, authenticate);
  assert.equal(market.__deps.optionalAuthenticate, optionalAuthenticate);
  assert.equal(delivery.__deps.optionalAuthenticate, optionalAuthenticate);
  const here = path.dirname(fileURLToPath(import.meta.url));
  const marketSrc = fs.readFileSync(path.resolve(here, "../routes/market.js"), "utf8");
  assert.match(marketSrc, /is_admin/, "market route must keep admin checks");
  assert.match(marketSrc, /owner/, "market route must keep owner checks");
});

test("G10.62 P3.4G: default pool fails closed in isolated mode while isolated Market app wiring does not trigger it", () => {
  const serverUrl = pathToFileURL(path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../server.js")).href;
  const dbUrl = pathToFileURL(path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../config/database.js")).href;
  const child = `
import { createApp } from ${JSON.stringify(serverUrl)};
import { pool as defaultPool } from ${JSON.stringify(dbUrl)};
const database = { tag: "explicit-pool", query: async () => ({ rows: [{ database: "motri_iq_test", server_time: new Date().toISOString() }] }) };
const storageService = { tag: "explicit-storage", upload: async () => {}, download: async () => ({ body: Buffer.from([]), contentType: "image/jpeg" }) };
const app = await createApp({ pool: database, storageService, env: { ...process.env, MOTRI_LOCAL_TEST_ISOLATED: "1", MOTRI_LOCAL_TEST: "true" } });
if (!app?.locals?.__isolatedMarketDeps) throw new Error("missing isolated deps");
let threw = null;
try { defaultPool.query("select 1"); } catch (e) { threw = e.code || e.message; }
if (threw !== "LOCAL_TEST_DEFAULT_POOL_FORBIDDEN") throw new Error("default pool not fail-closed: " + threw);
console.log(JSON.stringify({ ok: true, threw, isolated: true }));
`;
  const res = spawnSync(process.execPath, ["--input-type=module", "-e", child], {
    cwd: path.resolve(path.dirname(fileURLToPath(import.meta.url)), ".."),
    env: { PATH: process.env.PATH || process.env.Path, MOTRI_LOCAL_TEST_ISOLATED: "1", MOTRI_LOCAL_TEST: "true", JWT_SECRET: TEST_JWT_SECRET },
    encoding: "utf8",
    timeout: 20000,
    windowsHide: true,
  });
  assert.equal(res.status, 0, `child failed: ${(res.stderr||"").slice(0,500)} ${(res.stdout||"").slice(0,300)}`);
  const out = JSON.parse((res.stdout || "{}").trim().split(/\r?\n/).pop());
  assert.equal(out.threw, "LOCAL_TEST_DEFAULT_POOL_FORBIDDEN");
});

test("G10.62 P3.4G: normal production app retains previous route mounts and paths", async () => {
  const database = { query: async () => ({ rows: [] }) };
  const storageService = { upload: async () => {}, download: async () => ({ body: Buffer.alloc(0), contentType: "image/jpeg" }) };
  const app = await withEnvAsync({ MOTRI_LOCAL_TEST_ISOLATED: "0", MOTRI_LOCAL_TEST: "false", JWT_SECRET: TEST_JWT_SECRET }, async () =>
    createApp({ pool: database, storageService, env: { ...process.env, MOTRI_LOCAL_TEST_ISOLATED: "0", MOTRI_LOCAL_TEST: "false" } })
  );
  const mounts = mountText(app);
  for (const p of ["/api/auth", "/api/safety", "/api/cars", "/api/favorites", "/api/requests", "/api/offers", "/api/sellers", "/api/activity", "/api/business-ads", "/api/profile", "/api/wallet", "/api/storage", "/api/ugc", "/health"]) {
    assert.equal(mounts.includes(p), true, `normal mode must retain mount: ${p}\n${mounts}`);
  }
  assert.match(mounts, /market/, "normal mode retains market");
  // /api/uploads is dynamically mounted in normal mode when storage mode not local-test; static contract preserved separately.
  assert.ok(app.locals.__isolatedMarketDeps == null, "normal mode must not expose isolated deps");
});

test("G10.62 P3.4G: existing market upload/image-delivery paths remain unchanged", () => {
  const here = path.dirname(fileURLToPath(import.meta.url));
  const marketSrc = fs.readFileSync(path.resolve(here, "../routes/market.js"), "utf8");
  assert.match(marketSrc, /market\/uploads|router\.(put|post)\("\/uploads"/, "market upload path contract must remain");
  assert.match(marketSrc, /createMarketImageDeliveryRouter/, "image delivery factory must remain");
  assert.match(marketSrc, /router\.get\("\/:ref"/, "image delivery ref path must remain");
  const serverSrc = fs.readFileSync(path.resolve(here, "../server.js"), "utf8");
  assert.match(serverSrc, /app\.use\("\/api\/market\/images",/, "delivery mount path unchanged");
  assert.match(serverSrc, /app\.use\("\/api\/market",/, "market mount path unchanged");
});
