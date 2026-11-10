import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import {
  isLocalTestMode,
  validateLocalTestDatabaseUrl,
  assertLocalTestDatabaseConfig,
  verifyLocalTestDatabaseIdentity,
  startServerWithLocalTestDbGuard,
} from "../config/localTestDatabaseGuard.js";

const SECRET_URL = "postgres://neondb_owner:SUPER_SECRET_PASSWORD@prod-host.invalid:5432/motri_iq_test?sslmode=require";
const SECRET_FRAGMENT = "SUPER_SECRET_PASSWORD";

// Fixture hostnames only (offline tests). Approved runtime hosts are supplied via LOCAL_TEST_DB_ALLOWED_HOSTS env at runtime; never hardcoded here as production truth.
const FIXTURE_ALLOWED_HOST = "db.fixture.local";
const FIXTURE_UNLISTED_HOST = "db.unlisted.fixture";
const FIXTURE_ALLOWED_HOSTS = `127.0.0.1,localhost,${FIXTURE_ALLOWED_HOST}`;

function localEnv(overrides = {}) {
  return {
    MOTRI_LOCAL_TEST: "true",
    LOCAL_TEST_DB_ALLOWED_HOSTS: FIXTURE_ALLOWED_HOSTS,
    ...overrides,
  };
}

function mockPool({ connectImpl, queryImpl } = {}) {
  let released = 0;
  const client = {
    async query(sql) {
      if (queryImpl) return queryImpl(sql);
      return { rows: [{ db: "motri_iq_test", usr: "neondb_owner" }] };
    },
    async release() {
      released += 1;
    },
  };
  const pool = {
    async connect() {
      if (connectImpl) return connectImpl();
      return client;
    },
  };
  return { pool, client, get released() { return released; } };
}

test("G10.62 P2: local-test mode activates only when MOTRI_LOCAL_TEST=true", () => {
  assert.equal(isLocalTestMode({ MOTRI_LOCAL_TEST: "true" }), true);
  assert.equal(isLocalTestMode({ MOTRI_LOCAL_TEST: "false" }), false);
  assert.equal(isLocalTestMode({}), false);
});

test("G10.62 P2: accepts local-test DATABASE_URL for motri_iq_test/neondb_owner when host is explicitly allowlisted (no secrets in output)", () => {
  const ok = `postgres://neondb_owner@${FIXTURE_ALLOWED_HOST}:5432/motri_iq_test?sslmode=disable`;
  assert.deepEqual(validateLocalTestDatabaseUrl(ok, { env: localEnv() }), { dbName: "motri_iq_test", user: "neondb_owner" });
});

test("G10.62 P2: rejects missing/invalid/unsupported/non-URL DATABASE_URL before pool use", () => {
  const env = localEnv();
  for (const bad of [undefined, null, "", "   ", "not-a-url", "host=localhost dbname=motri_iq_test user=neondb_owner", `mysql://neondb_owner@${FIXTURE_ALLOWED_HOST}/motri_iq_test`]) {
    assert.throws(() => validateLocalTestDatabaseUrl(bad, { env }), (e) => /^LOCAL_TEST_DATABASE_/.test(String(e?.code)));
  }
});

test("G10.62 P2/P2.1: rejects wrong configured database name and wrong configured role before pool use", () => {
  const env = localEnv();
  assert.throws(() => validateLocalTestDatabaseUrl(`postgres://neondb_owner@${FIXTURE_ALLOWED_HOST}/prod_db`, { env }), (e) => e?.code === "LOCAL_TEST_DATABASE_DB_NOT_ALLOWED");
  assert.throws(() => validateLocalTestDatabaseUrl(`postgres://neondb_owner@${FIXTURE_ALLOWED_HOST}/motri_iq_migrated`, { env }), (e) => e?.code === "LOCAL_TEST_DATABASE_DB_NOT_ALLOWED");
  assert.throws(() => validateLocalTestDatabaseUrl(`postgres://other_role@${FIXTURE_ALLOWED_HOST}/motri_iq_test`, { env }), (e) => e?.code === "LOCAL_TEST_DATABASE_ROLE_NOT_ALLOWED");
  assert.throws(() => validateLocalTestDatabaseUrl(`postgres://@${FIXTURE_ALLOWED_HOST}/motri_iq_test`, { env }), (e) => e?.code === "LOCAL_TEST_DATABASE_ROLE_MISSING");
});

test("G10.62 P2: non-local mode leaves existing config behavior unchanged (no URL allowlist enforcement)", () => {
  assert.deepEqual(assertLocalTestDatabaseConfig({ MOTRI_LOCAL_TEST: "false", DATABASE_URL: "postgres://u@h/any_db" }), { active: false });
  assert.deepEqual(assertLocalTestDatabaseConfig({ DATABASE_URL: "" }), { active: false });
  // Non-local direct validation must not require LOCAL_TEST_DB_ALLOWED_HOSTS.
  assert.deepEqual(validateLocalTestDatabaseUrl("postgres://neondb_owner@remote.example.invalid/motri_iq_test"), { dbName: "motri_iq_test", user: "neondb_owner" });
});

test("G10.62 P2.1: local-test mode rejects missing or empty hostname allowlist", () => {
  const url = `postgres://neondb_owner@${FIXTURE_ALLOWED_HOST}/motri_iq_test`;
  assert.throws(() => validateLocalTestDatabaseUrl(url, { env: { MOTRI_LOCAL_TEST: "true" } }), (e) => e?.code === "LOCAL_TEST_DB_HOST_ALLOWLIST_MISSING");
  assert.throws(() => validateLocalTestDatabaseUrl(url, { env: { MOTRI_LOCAL_TEST: "true", LOCAL_TEST_DB_ALLOWED_HOSTS: "   , ;  " } }), (e) => e?.code === "LOCAL_TEST_DB_HOST_ALLOWLIST_MISSING");
});

test("G10.62 P2.1: local-test mode accepts explicitly allowlisted hostname and rejects unlisted hostname", () => {
  const env = localEnv();
  assert.deepEqual(validateLocalTestDatabaseUrl(`postgres://neondb_owner@${FIXTURE_ALLOWED_HOST}/motri_iq_test`, { env }), { dbName: "motri_iq_test", user: "neondb_owner" });
  assert.deepEqual(validateLocalTestDatabaseUrl(`postgres://neondb_owner@LOCALHOST/motri_iq_test`, { env }), { dbName: "motri_iq_test", user: "neondb_owner" });
  assert.throws(() => validateLocalTestDatabaseUrl(`postgres://neondb_owner@${FIXTURE_UNLISTED_HOST}/motri_iq_test`, { env }), (e) => e?.code === "LOCAL_TEST_DB_HOST_NOT_ALLOWED");
});

test("G10.62 P2.1: host allowlist failures return fixed codes and never expose connection details", () => {
  const logs = [];
  let exitCode = null;
  assert.throws(
    () => validateLocalTestDatabaseUrl(SECRET_URL, { env: { MOTRI_LOCAL_TEST: "true", LOCAL_TEST_DB_ALLOWED_HOSTS: FIXTURE_ALLOWED_HOSTS } }),
    (e) => e?.code === "LOCAL_TEST_DB_HOST_NOT_ALLOWED" && !String(e?.message).includes(SECRET_FRAGMENT) && !String(e?.message).includes("prod-host"),
  );
  // startup path also logs fixed refusal code only
  const pool = { async connect() { throw new Error("should not connect"); } };
  return startServerWithLocalTestDbGuard({
    app: {},
    pool,
    port: 3000,
    env: { MOTRI_LOCAL_TEST: "true", LOCAL_TEST_DB_ALLOWED_HOSTS: FIXTURE_ALLOWED_HOSTS, DATABASE_URL: SECRET_URL },
    listen: () => { throw new Error("must not listen"); },
    exit: (c) => { exitCode = c; },
    log: (m) => logs.push(String(m)),
  }).then(() => {
    assert.equal(exitCode, 1);
    assert.ok(logs.some((m) => m.includes("LOCAL_TEST_DB_GUARD_REFUSED")));
    assert.ok(logs.every((m) => !m.includes(SECRET_FRAGMENT) && !m.includes("prod-host.invalid") && !m.includes("SUPER_SECRET_PASSWORD")));
  });
});

test("G10.62 P2: actual identity verification rejects wrong current_database/current_user and query failure; releases client", async () => {
  const wrongDb = mockPool({ queryImpl: async () => ({ rows: [{ db: "other_db", usr: "neondb_owner" }] }) });
  await assert.rejects(() => verifyLocalTestDatabaseIdentity(wrongDb.pool), (e) => e?.code === "LOCAL_TEST_DATABASE_IDENTITY_DB_MISMATCH");
  assert.equal(wrongDb.released, 1);

  const wrongUsr = mockPool({ queryImpl: async () => ({ rows: [{ db: "motri_iq_test", usr: "other_usr" }] }) });
  await assert.rejects(() => verifyLocalTestDatabaseIdentity(wrongUsr.pool), (e) => e?.code === "LOCAL_TEST_DATABASE_IDENTITY_ROLE_MISMATCH");
  assert.equal(wrongUsr.released, 1);

  const queryFail = mockPool({ queryImpl: async () => { throw new Error(`db fail ${SECRET_URL}`); } });
  await assert.rejects(() => verifyLocalTestDatabaseIdentity(queryFail.pool), (e) => e?.code === "LOCAL_TEST_DATABASE_IDENTITY_QUERY_FAILED");
  assert.equal(queryFail.released, 1);
});

test("G10.62 P2: successful identity verification releases client", async () => {
  const ok = mockPool();
  await verifyLocalTestDatabaseIdentity(ok.pool);
  assert.equal(ok.released, 1);
});

test("G10.62 P2: local-test startup refuses wrong config before pool.connect and before listen", async () => {
  let connectCalls = 0;
  let listenCalls = 0;
  let exitCode = null;
  const logs = [];
  const pool = { async connect() { connectCalls += 1; return { async query(){}, async release(){} }; } };
  await startServerWithLocalTestDbGuard({
    app: {},
    pool,
    port: 3000,
    env: localEnv({ DATABASE_URL: `postgres://neondb_owner@${FIXTURE_ALLOWED_HOST}/wrong_db` }),
    listen: () => { listenCalls += 1; },
    exit: (c) => { exitCode = c; },
    log: (m) => logs.push(String(m)),
  });
  assert.equal(connectCalls, 0);
  assert.equal(listenCalls, 0);
  assert.equal(exitCode, 1);
  assert.ok(logs.some((m) => m.includes("LOCAL_TEST_DB_GUARD_REFUSED")));
  assert.ok(logs.every((m) => !m.includes(SECRET_FRAGMENT) && !m.includes("postgres://") && !m.includes("prod-host")));
});

test("G10.62 P2: local-test startup refuses wrong actual identity and does not listen; releases client", async () => {
  let listenCalls = 0;
  let exitCode = null;
  const logs = [];
  const mocked = mockPool({ queryImpl: async () => ({ rows: [{ db: "motri_iq_test", usr: "wrong" }] }) });
  await startServerWithLocalTestDbGuard({
    app: {},
    pool: mocked.pool,
    port: 3000,
    env: localEnv({ DATABASE_URL: `postgres://neondb_owner@${FIXTURE_ALLOWED_HOST}/motri_iq_test` }),
    listen: () => { listenCalls += 1; },
    exit: (c) => { exitCode = c; },
    log: (m) => logs.push(String(m)),
  });
  assert.equal(listenCalls, 0);
  assert.equal(exitCode, 1);
  assert.equal(mocked.released, 1);
  assert.ok(logs.every((m) => !m.includes(SECRET_FRAGMENT)));
});

test("G10.62 P2: local-test startup query failure prevents listen and releases client", async () => {
  let listenCalls = 0;
  let exitCode = null;
  const mocked = mockPool({ queryImpl: async () => { throw new Error(`boom ${SECRET_URL}`); } });
  await startServerWithLocalTestDbGuard({
    app: {},
    pool: mocked.pool,
    port: 3000,
    env: localEnv({ DATABASE_URL: `postgres://neondb_owner@${FIXTURE_ALLOWED_HOST}/motri_iq_test` }),
    listen: () => { listenCalls += 1; },
    exit: (c) => { exitCode = c; },
    log: () => {},
  });
  assert.equal(listenCalls, 0);
  assert.equal(exitCode, 1);
  assert.equal(mocked.released, 1);
});

test("G10.62 P2: successful local-test verification permits listen after verification", async () => {
  let listenCalls = 0;
  let verified = false;
  const logs = [];
  const mocked = mockPool();
  await startServerWithLocalTestDbGuard({
    app: {},
    pool: mocked.pool,
    port: 3000,
    env: localEnv({ DATABASE_URL: `postgres://neondb_owner@${FIXTURE_ALLOWED_HOST}/motri_iq_test` }),
    listen: (_p, cb) => { listenCalls += 1; cb?.(); return { ok: true }; },
    exit: (c) => { throw new Error(`should not exit ${c}`); },
    log: (m) => logs.push(String(m)),
    onVerified: () => { verified = true; },
  });
  assert.equal(mocked.released, 1);
  assert.equal(verified, true);
  assert.equal(listenCalls, 1);
  assert.ok(logs.some((m) => m.includes("local-test DB verified")));
  assert.ok(logs.every((m) => !m.includes(SECRET_FRAGMENT)));
});

test("G10.62 P2: non-local startup preserves existing listen behavior (no identity query/connect)", async () => {
  let connectCalls = 0;
  let listenCalls = 0;
  let verified = false;
  const pool = { async connect() { connectCalls += 1; throw new Error("should not connect"); } };
  await startServerWithLocalTestDbGuard({
    app: {},
    pool,
    port: 3000,
    env: { MOTRI_LOCAL_TEST: "false", DATABASE_URL: "postgres://u@h/anything" },
    listen: (_p, cb) => { listenCalls += 1; cb?.(); return { ok: true }; },
    exit: (c) => { throw new Error(`should not exit ${c}`); },
    log: () => {},
    onVerified: () => { verified = true; },
  });
  assert.equal(connectCalls, 0);
  assert.equal(listenCalls, 1);
  assert.equal(verified, true);
});

test("G10.62 P2.1: cleanup scheduling hook runs only after successful local-test verification (never before verification/failure)", async () => {
  const events = [];
  const mocked = mockPool();
  await startServerWithLocalTestDbGuard({
    app: {},
    pool: mocked.pool,
    port: 3000,
    env: localEnv({ DATABASE_URL: `postgres://neondb_owner@${FIXTURE_ALLOWED_HOST}/motri_iq_test` }),
    listen: (_p, cb) => { events.push("listen"); cb?.(); },
    exit: (c) => { throw new Error(`should not exit ${c}`); },
    log: () => {},
    onVerified: () => { events.push("verified"); },
  });
  assert.deepEqual(events, ["verified", "listen"]);
});

test("G10.62 P2.1: failed local-test config/identity verification never invokes post-verify scheduling hook", async () => {
  let verified = 0;
  await startServerWithLocalTestDbGuard({
    app: {},
    pool: { async connect() { throw new Error("should not connect"); } },
    port: 3000,
    env: localEnv({ DATABASE_URL: `postgres://neondb_owner@${FIXTURE_ALLOWED_HOST}/wrong_db` }),
    listen: () => { throw new Error("must not listen"); },
    exit: () => {},
    log: () => {},
    onVerified: () => { verified += 1; },
  });
  assert.equal(verified, 0);

  let verified2 = 0;
  const mocked = mockPool({ queryImpl: async () => ({ rows: [{ db: "motri_iq_test", usr: "wrong" }] }) });
  await startServerWithLocalTestDbGuard({
    app: {},
    pool: mocked.pool,
    port: 3000,
    env: localEnv({ DATABASE_URL: `postgres://neondb_owner@${FIXTURE_ALLOWED_HOST}/motri_iq_test` }),
    listen: () => { throw new Error("must not listen"); },
    exit: () => {},
    log: () => {},
    onVerified: () => { verified2 += 1; },
  });
  assert.equal(verified2, 0);
});

test("G10.62 P2.1: server.js schedules reservation cleanup only from post-verification hook (no pre-guard timer)", () => {
  const here = path.dirname(fileURLToPath(import.meta.url));
  const serverPath = path.resolve(here, "../server.js");
  const src = fs.readFileSync(serverPath, "utf8");

  const guardIdx = src.indexOf("await startServerWithLocalTestDbGuard");
  const intervalIdx = src.indexOf("setInterval(() => {");
  const scheduleFnIdx = Math.max(src.indexOf("function scheduleReservationCleanup"), src.indexOf("export function scheduleReservationCleanup"));
  assert.ok(guardIdx >= 0, "guard must be awaited");
  assert.ok(scheduleFnIdx >= 0, "cleanup scheduler function must exist");
  assert.ok(intervalIdx > scheduleFnIdx, "setInterval must live inside scheduler function");
  assert.ok(src.includes("onVerified: () => {"), "guard must receive onVerified hook");
  assert.ok(/scheduleReservationCleanup\(/.test(src), "cleanup must be scheduled from onVerified hook");
  assert.ok(!/\n\s*setInterval\([\s\S]*cleanupExpiredReservations[\s\S]*\n\s*await startServerWithLocalTestDbGuard/.test(src), "cleanup timer must not be scheduled before guard");
});
