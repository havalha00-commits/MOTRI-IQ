import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath, pathToFileURL } from "node:url";

import {
  parseEnvFileContent,
  loadExplicitEnvFile,
  applyIsolatedEnv,
  assertExplicitLocalTestEnvSource,
  validateIsolatedLocalTestEnv,
} from "../config/localTestRuntimeBootstrap.js";
import { createApp, scheduleReservationCleanup } from "../server.js";

const FIXTURE_HOST = "db.fixture.local";
const EXACT_LOCAL = "http://127.0.0.1:4566";
const SECRET = "SUPER_SECRET_VALUE_SHOULD_NOT_APPEAR";

function withProcessEnv(patch, fn) {
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

async function withProcessEnvAsync(patch, fn) {
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

function validIsolatedEnv(overrides = {}) {
  return {
    MOTRI_LOCAL_TEST: "true",
    MOTRI_LOCAL_TEST_ISOLATED: "1",
    DATABASE_URL: `postgres://neondb_owner@${FIXTURE_HOST}/motri_iq_test`,
    LOCAL_TEST_DB_ALLOWED_HOSTS: `127.0.0.1,localhost,${FIXTURE_HOST}`,
    LOCAL_S3_ENDPOINT: EXACT_LOCAL,
    LOCAL_S3_ACCESS_KEY_ID: "S3RVER",
    LOCAL_S3_SECRET_ACCESS_KEY: "S3RVER",
    LOCAL_S3_BUCKET: "cars",
    LOCAL_S3_REGION: "us-east-1",
    LOCAL_S3_PUBLIC_BASE: "",
    ...overrides,
  };
}

function withTempEnvFile(content, fn) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "motri-local-env-"));
  const file = path.join(dir, "isolated.env");
  fs.writeFileSync(file, content, "utf8");
  try {
    return fn(file);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
}

test("G10.62 P3.4A: isolated env parser loads explicit file only (no implicit .env) and fails closed on invalid input", () => {
  withTempEnvFile(
    `# comment\nMOTRI_LOCAL_TEST=true\nDATABASE_URL=postgres://neondb_owner@${FIXTURE_HOST}/motri_iq_test\nLOCAL_TEST_DB_ALLOWED_HOSTS=${FIXTURE_HOST}\nLOCAL_S3_ENDPOINT=${EXACT_LOCAL}\nLOCAL_S3_ACCESS_KEY_ID=a\nLOCAL_S3_SECRET_ACCESS_KEY=b\n`,
    (file) => {
      const env = loadExplicitEnvFile(file);
      assert.equal(env.MOTRI_LOCAL_TEST, "true");
      assert.equal(env.LOCAL_S3_ENDPOINT, EXACT_LOCAL);
      assert.equal(env.DATABASE_URL.includes("motri_iq_test"), true);
    }
  );
  assert.throws(() => loadExplicitEnvFile(""), (e) => e?.code === "LOCAL_TEST_ENV_FILE_REQUIRED");
  assert.throws(() => loadExplicitEnvFile(path.join(os.tmpdir(), "does-not-exist-motri.env")), (e) => e?.code === "LOCAL_TEST_ENV_FILE_UNREADABLE");
  assert.throws(() => parseEnvFileContent("MOTRI_LOCAL_TEST true"), (e) => e?.code === "LOCAL_TEST_ENV_INPUT_INVALID");
});

test("G10.62 P3.4A: backend/.env cannot contaminate isolated startup (explicit env source required)", async () => {
  // Contaminated process env resembling backend/.env values must not satisfy explicit-source requirement.
  const contaminated = {
    MOTRI_LOCAL_TEST: "true",
    DATABASE_URL: `postgres://neondb_owner@prod-host.invalid/prod_db`,
    LOCAL_TEST_DB_ALLOWED_HOSTS: "prod-host.invalid",
    R2_ENDPOINT: "https://r2.example.invalid",
    LOCAL_S3_ENDPOINT: "https://r2.example.invalid",
  };
  assert.throws(() => assertExplicitLocalTestEnvSource(contaminated), (e) => e?.code === "LOCAL_TEST_EXPLICIT_ENV_REQUIRED");

  // Explicit isolated env is applied and validated; uses process.env-local S3/DB controls that bypass contamination.
  await withProcessEnvAsync(validIsolatedEnv(), async () => {
    const target = { ...contaminated };
    applyIsolatedEnv(validIsolatedEnv(), target);
    assert.equal(target.MOTRI_LOCAL_TEST_ISOLATED, "1");
    await validateIsolatedLocalTestEnv(target);
  });
  await assert.rejects(() => validateIsolatedLocalTestEnv({ MOTRI_LOCAL_TEST: "true" }), (e) => e?.code === "LOCAL_TEST_EXPLICIT_ENV_REQUIRED");
});

test("G10.62 P3.4A: invalid DB config fails closed before pool creation path", async () => {
  await withProcessEnvAsync(validIsolatedEnv(), async () => {
    const badDb = validIsolatedEnv({ DATABASE_URL: `postgres://neondb_owner@${FIXTURE_HOST}/prod_db` });
    await assert.rejects(() => validateIsolatedLocalTestEnv(badDb), (e) => e?.code === "LOCAL_TEST_DATABASE_DB_NOT_ALLOWED");
    const badRole = validIsolatedEnv({ DATABASE_URL: `postgres://other_role@${FIXTURE_HOST}/motri_iq_test` });
    await assert.rejects(() => validateIsolatedLocalTestEnv(badRole), (e) => e?.code === "LOCAL_TEST_DATABASE_ROLE_NOT_ALLOWED");
    const noAllow = validIsolatedEnv({ LOCAL_TEST_DB_ALLOWED_HOSTS: "" });
    await assert.rejects(() => validateIsolatedLocalTestEnv(noAllow), (e) => e?.code === "LOCAL_TEST_DB_HOST_ALLOWLIST_MISSING");
  });
});

test("G10.62 P3.4A: invalid storage config fails closed before service creation path", async () => {
  await withProcessEnvAsync(validIsolatedEnv({ LOCAL_S3_ENDPOINT: "https://r2.example.invalid" }), async () => {
    const badEp = validIsolatedEnv({ LOCAL_S3_ENDPOINT: "https://r2.example.invalid" });
    await assert.rejects(() => validateIsolatedLocalTestEnv(badEp), (e) => e?.code === "LOCAL_TEST_STORAGE_ENDPOINT_NOT_LOCAL");
  });
  await withProcessEnvAsync(validIsolatedEnv({ LOCAL_S3_ENDPOINT: "", LOCAL_S3_ACCESS_KEY_ID: "", LOCAL_S3_SECRET_ACCESS_KEY: "" }), async () => {
    const missing = validIsolatedEnv({ LOCAL_S3_ENDPOINT: "", LOCAL_S3_ACCESS_KEY_ID: "", LOCAL_S3_SECRET_ACCESS_KEY: "" });
    await assert.rejects(() => validateIsolatedLocalTestEnv(missing), (e) => e?.code === "LOCAL_TEST_STORAGE_CONFIG_MISSING" || e?.code === "LOCAL_TEST_STORAGE_CREDENTIALS_MISSING");
  });
});

test("G10.62 P3.4A: reservation cleanup disabled by default and never schedules immediate query", () => {
  let intervalCalls = 0;
  const orig = globalThis.setInterval;
  globalThis.setInterval = () => { intervalCalls += 1; return { unref() {} }; };
  try {
    const t1 = scheduleReservationCleanup({ RESERVATION_CLEANUP_INTERVAL_MS: "0" }, { database: { query() { throw new Error("must not query"); } } });
    assert.equal(t1, null);
    const t2 = scheduleReservationCleanup({}, { database: { query() { throw new Error("must not query"); } } });
    assert.equal(t2, null);
    assert.equal(intervalCalls, 0);
    const t3 = scheduleReservationCleanup({ RESERVATION_CLEANUP_INTERVAL_MS: "60000" }, { database: { query() { throw new Error("callback not invoked"); } } });
    assert.ok(t3);
    assert.equal(intervalCalls, 1);
  } finally {
    globalThis.setInterval = orig;
  }
});

test("G10.62 P3.4A: startup static ordering/contracts (no services started)", () => {
  const here = path.dirname(fileURLToPath(import.meta.url));
  const server = fs.readFileSync(path.resolve(here, "../server.js"), "utf8");
  const db = fs.readFileSync(path.resolve(here, "../config/database.js"), "utf8");
  const storage = fs.readFileSync(path.resolve(here, "../services/objectStorage.js"), "utf8");
  const bootstrap = fs.readFileSync(path.resolve(here, "../scripts/start-local-test-runtime.js"), "utf8");
  const pkg = JSON.parse(fs.readFileSync(path.resolve(here, "../package.json"), "utf8"));

  assert.ok(!server.startsWith('import "dotenv/config";'));
  assert.ok(db.includes('MOTRI_LOCAL_TEST_ISOLATED'));
  assert.ok(storage.includes('MOTRI_LOCAL_TEST_ISOLATED'));
  assert.ok(bootstrap.includes("validateIsolatedLocalTestEnv"));
  const validateIdx = bootstrap.indexOf("validateIsolatedLocalTestEnv(process.env)");
  const poolIdx = bootstrap.indexOf('await import("../config/database.js")');
  const storageIdx = bootstrap.indexOf('await import("../services/objectStorage.js")');
  const startIdx = bootstrap.indexOf("startIsolatedLocalTestServer");
  assert.ok(validateIdx >= 0 && poolIdx > validateIdx && storageIdx > validateIdx, "DB/storage modules imported only after env validation");
  assert.ok(startIdx > storageIdx, "server start occurs after pool/storage creation");
  assert.ok(bootstrap.includes('RESERVATION_CLEANUP_INTERVAL_MS') && bootstrap.includes('"0"'));

  assert.ok(server.includes("startServerWithLocalTestDbGuard"));
  assert.ok(server.includes("onVerified: () =>"));
  assert.ok(server.includes("scheduleReservationCleanup"));
  assert.ok(pkg.scripts["start:local-test"]?.includes("start-local-test-runtime.js"));
  assert.ok(pkg.scripts.start === "node server.js");
});

test("G10.62 P3.4C: isolated app does NOT mount Supabase-backed /api/uploads (offline, static wiring)", () => {
  const here = path.dirname(fileURLToPath(import.meta.url));
  const server = fs.readFileSync(path.resolve(here, "../server.js"), "utf8");
  assert.ok(!server.includes('import uploadsRouter from "./routes/uploads.js";'), "top-level uploads import would eagerly load Supabase proxy");
  assert.ok(server.includes('if (!isLocalTestStorageMode(env))'), "uploads mount must be gated by local-test storage mode");
  assert.ok(server.includes('await import("./routes/uploads.js")'), "uploads route must be dynamically imported only in non-local-test branch");
  assert.ok(server.includes('app.use("/api/uploads", uploadsRouter);'));
  assert.ok(server.includes('createMarketImageDeliveryRouter({ database: pool, storage: storageService })'));
  assert.ok(server.includes('createMarketRouter({ database: pool, storage: storageService })'));
});

test("G10.62 P3.4C: normal (non-local-test) app still mounts /api/uploads path (offline static contract)", () => {
  const here = path.dirname(fileURLToPath(import.meta.url));
  const server = fs.readFileSync(path.resolve(here, "../server.js"), "utf8");
  assert.ok(server.includes('await import("./routes/uploads.js")'), "uploads route must be dynamically imported only in non-local-test branch");
  assert.ok(server.includes('app.use("/api/uploads", uploadsRouter);'));
  assert.ok(server.includes('if (!isLocalTestStorageMode(env))'), "uploads mount must be gated by local-test storage mode");
  assert.ok(server.includes('app.use("/api/market", createMarketRouter'), "market path preserved");
});

test("G10.62 P3.4C: process-isolated explicit env source proves backend/.env-like values cannot override", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "motri-env-proof-"));
  const backendDir = path.join(dir, "backend");
  fs.mkdirSync(backendDir, { recursive: true });
  const envFile = path.join(dir, "explicit.env");
  fs.writeFileSync(path.join(backendDir, ".env"),
    `DATABASE_URL=postgres://neondb_owner@poison.invalid/prod_db\nLOCAL_TEST_DB_ALLOWED_HOSTS=poison.invalid\nLOCAL_S3_ENDPOINT=https://r2.poison.invalid\nR2_ENDPOINT=https://r2.poison.invalid\nPOISON_SENTINEL=from_dotenv\n`,
    "utf8");
  fs.writeFileSync(envFile,
    `MOTRI_LOCAL_TEST=true\nDATABASE_URL=postgres://neondb_owner@${FIXTURE_HOST}/motri_iq_test\nLOCAL_TEST_DB_ALLOWED_HOSTS=${FIXTURE_HOST}\nLOCAL_S3_ENDPOINT=${EXACT_LOCAL}\nLOCAL_S3_ACCESS_KEY_ID=S3RVER\nLOCAL_S3_SECRET_ACCESS_KEY=S3RVER\nLOCAL_S3_BUCKET=cars\nLOCAL_S3_REGION=us-east-1\n`,
    "utf8");

  const bootstrapUrl = pathToFileURL(path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../config/localTestRuntimeBootstrap.js")).href;
  const child = `
import fs from "node:fs";
import path from "node:path";
const { loadExplicitEnvFile, applyIsolatedEnv, validateIsolatedLocalTestEnv } = await import(${JSON.stringify(bootstrapUrl)});
const cwd = process.cwd();
const dotenvPath = path.join(cwd, ".env");
const dotenv = fs.readFileSync(dotenvPath, "utf8");
if (!dotenv.includes("POISON_SENTINEL=from_dotenv")) throw new Error("fixture missing");
// Simulate contaminated process env that might come from a shell; explicit env must win.
process.env.POISON_SENTINEL = "from_shell";
process.env.DATABASE_URL = "postgres://neondb_owner@poison.invalid/prod_db";
const explicit = loadExplicitEnvFile(${JSON.stringify(envFile)});
applyIsolatedEnv(explicit, process.env);
await validateIsolatedLocalTestEnv(process.env);
if (process.env.DATABASE_URL.includes("poison.invalid")) throw new Error("poison db leaked");
if (process.env.DATABASE_URL.includes("prod_db")) throw new Error("prod db leaked");
if (process.env.LOCAL_S3_ENDPOINT !== ${JSON.stringify(EXACT_LOCAL)}) throw new Error("endpoint changed");
if (process.env.MOTRI_LOCAL_TEST_ISOLATED !== "1") throw new Error("isolation marker missing");
console.log(JSON.stringify({ok:true,poison:process.env.POISON_SENTINEL||null}));
`;
  try {
    const res = spawnSync(process.execPath, ["--input-type=module", "-e", child], {
      cwd: backendDir,
      env: { ...process.env, DOTENV_CONFIG_PATH: path.join(backendDir, ".env") },
      encoding: "utf8",
      timeout: 15000,
      windowsHide: true,
    });
    assert.equal(res.status, 0, `child failed: ${(res.stderr||"").slice(0,300)} ${(res.stdout||"").slice(0,200)}`);
    const out = JSON.parse((res.stdout || "{}").trim().split(/\r?\n/).pop());
    assert.equal(out.ok, true);
    // Poison sentinel in process env is irrelevant to isolated config; we only prove DB/S3 controls were not overridden by dotenv-like values.
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test("G10.62 P3.4E: direct-run startup awaits async createApp before DB guard (static regression)", () => {
  const here = path.dirname(fileURLToPath(import.meta.url));
  const server = fs.readFileSync(path.resolve(here, "../server.js"), "utf8");
  assert.ok(server.includes("export async function createApp("), "createApp must be async");
  const directRunBlock = server.slice(server.indexOf('if (_isDirectRun && process.env.MOTRI_LOCAL_TEST_ISOLATED !== "1")'));
  assert.ok(directRunBlock.includes("const app = await createApp({ pool, storageService, env: process.env });"),
    "direct-run must await createApp before passing app to guard");
  assert.ok(directRunBlock.includes("startServerWithLocalTestDbGuard({"), "direct-run must still use guarded startup");
});

test("G10.62 P3.4E: isolated dependency chain skips implicit dotenv/config (child process, poisoned cwd .env)", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "motri-dotenv-proof-"));
  const cwd = path.join(dir, "backend");
  fs.mkdirSync(cwd, { recursive: true });
  fs.writeFileSync(path.join(cwd, ".env"),
    "POISON_DOTENV=loaded\nJWT_SECRET=poison-dotenv-secret\nDATABASE_URL=postgres://poison.invalid/poison\nLOCAL_S3_ENDPOINT=https://poison.invalid\n",
    "utf8");
  const here = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
  const child = `
import fs from "node:fs";
import path from "node:path";
const poison = fs.readFileSync(path.join(process.cwd(), ".env"), "utf8");
if (!poison.includes("POISON_DOTENV=loaded")) throw new Error("fixture missing");
// Simulate explicit isolated env already applied by bootstrap.
process.env.MOTRI_LOCAL_TEST_ISOLATED = "1";
process.env.MOTRI_LOCAL_TEST = "true";
process.env.JWT_SECRET = "x".repeat(64); // test-only, never printed
delete process.env.POISON_DOTENV;
delete process.env.DATABASE_URL;
const mods = [
  ${JSON.stringify(pathToFileURL(path.join(here, "middleware/auth.js")).href)},
  ${JSON.stringify(pathToFileURL(path.join(here, "middleware/current_user.js")).href)},
  ${JSON.stringify(pathToFileURL(path.join(here, "services/ugc_policy.js")).href)},
  ${JSON.stringify(pathToFileURL(path.join(here, "config/database.js")).href)},
  ${JSON.stringify(pathToFileURL(path.join(here, "services/objectStorage.js")).href)},
];
for (const m of mods) await import(m);
if (process.env.POISON_DOTENV === "loaded") throw new Error("dotenv/config loaded poison from cwd .env");
if (process.env.MOTRI_LOCAL_TEST_ISOLATED !== "1") throw new Error("isolation marker changed");
console.log(JSON.stringify({ok:true,poison:process.env.POISON_DOTENV||null}));
`;
  try {
    const res = spawnSync(process.execPath, ["--input-type=module", "-e", child], {
      cwd,
      env: { PATH: process.env.PATH || process.env.Path, MOTRI_LOCAL_TEST_ISOLATED: "1", MOTRI_LOCAL_TEST: "true" },
      encoding: "utf8",
      timeout: 15000,
      windowsHide: true,
    });
    assert.equal(res.status, 0, `child failed: ${(res.stderr||"").slice(0,400)} ${(res.stdout||"").slice(0,200)}`);
    const out = JSON.parse((res.stdout || "{}").trim().split(/\r?\n/).pop());
    assert.equal(out.ok, true);
    assert.equal(out.poison, null);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test("G10.62 P3.4E: lazy default pool is fail-closed in isolated mode and compatible in normal mode (child process)", () => {
  const dbUrl = pathToFileURL(path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../config/database.js")).href;
  // Isolated mode: importing default pool and touching query must throw fixed code, not create pool.
  const isolatedChild = `
const mod = await import(${JSON.stringify(dbUrl)});
if (mod.pool.__isLazyDefaultPool !== true) throw new Error("lazy marker missing");
let threw = null;
try { mod.pool.query("select 1"); } catch (e) { threw = e.code || e.message; }
if (threw !== "LOCAL_TEST_DEFAULT_POOL_FORBIDDEN") throw new Error("expected forbidden, got " + threw);
console.log(JSON.stringify({ok:true,threw}));
`;
  const r1 = spawnSync(process.execPath, ["--input-type=module", "-e", isolatedChild], {
    cwd: path.resolve(path.dirname(fileURLToPath(import.meta.url)), ".."),
    env: { PATH: process.env.PATH || process.env.Path, MOTRI_LOCAL_TEST_ISOLATED: "1", MOTRI_LOCAL_TEST: "true" },
    encoding: "utf8",
    timeout: 15000,
    windowsHide: true,
  });
  assert.equal(r1.status, 0, `isolated child failed: ${(r1.stderr||"").slice(0,400)} ${(r1.stdout||"").slice(0,200)}`);
  assert.equal(JSON.parse((r1.stdout||"{}").trim().split(/\r?\n/).pop()).threw, "LOCAL_TEST_DEFAULT_POOL_FORBIDDEN");

  // Normal mode: default pool exposes expected methods/properties and is lazy on import.
  const normalChild = `
const mod = await import(${JSON.stringify(dbUrl)});
const p = mod.pool;
for (const k of ["query","connect","end","on"]) if (typeof p[k] !== "function") throw new Error("missing method " + k);
if (p.__isLazyDefaultPool !== true) throw new Error("lazy marker missing");
console.log(JSON.stringify({ok:true}));
`;
  const r2 = spawnSync(process.execPath, ["--input-type=module", "-e", normalChild], {
    cwd: path.resolve(path.dirname(fileURLToPath(import.meta.url)), ".."),
    env: { PATH: process.env.PATH || process.env.Path, MOTRI_LOCAL_TEST_ISOLATED: "0", MOTRI_LOCAL_TEST: "false" },
    encoding: "utf8",
    timeout: 15000,
    windowsHide: true,
  });
  assert.equal(r2.status, 0, `normal child failed: ${(r2.stderr||"").slice(0,400)} ${(r2.stdout||"").slice(0,200)}`);
});
