import assert from "node:assert/strict";
import { once } from "node:events";
import express from "express";
import test from "node:test";
import { SignJWT } from "jose";
import { createProfilesRouter } from "../routes/profiles.js";
import { createAuthenticateBackendIndependent } from "../middleware/current_user.js";

const userId = "d1f6b1a2-c3d4-4e5f-8a9b-0c1d2e3f4a5b";
const otherId = "a1f6b1a2-c3d4-4e5f-8a9b-0c1d2e3f4a5b";

function actorAuth(req, _res, next) {
  req.user = { id: userId, email: "me@example.test", is_admin: false };
  next();
}

async function withRouter(router, callback) {
  const app = express();
  app.use(express.json());
  app.use("/api/profile", router);
  const server = app.listen(0, "127.0.0.1");
  await once(server, "listening");
  const address = server.address();
  try {
    await callback(`http://127.0.0.1:${address.port}`);
  } finally {
    await new Promise((resolve, reject) => server.close((e) => (e ? reject(e) : resolve())));
  }
}

test("GET /me returns authenticated profile fields without raw metadata/secrets", async () => {
  const queries = [];
  const database = {
    async query(sql, values) {
      queries.push({ sql, values });
      return {
        rows: [{
          id: userId,
          email: "me@example.test",
          phone: "0770000000",
          full_name: "Test User",
          display_name: "Test User",
          username: "test_user",
          avatar_url: "https://x/pic.png",
          is_admin: true
        }]
      };
    }
  };
  await withRouter(createProfilesRouter({ database, authenticate: actorAuth }), async (base) => {
    const r = await fetch(`${base}/api/profile/me`, { headers: { authorization: "Bearer t" } });
    assert.equal(r.status, 200);
    const body = await r.json();
    assert.equal(body.success, true);
    assert.deepEqual(Object.keys(body.data).sort(), ["avatar_url","display_name","email","full_name","id","is_admin","phone","username"].sort());
    assert.equal(body.data.id, userId);
    assert.equal(body.data.email, "me@example.test");
    assert.equal(body.data.phone, "0770000000");
    assert.equal(body.data.full_name, "Test User");
    assert.equal(body.data.username, "test_user");
    assert.equal(body.data.is_admin, true);
    assert.equal(JSON.stringify(body).includes("raw_user_meta_data"), false);
    assert.equal(JSON.stringify(body).includes("encrypted_password"), false);
    assert.equal(JSON.stringify(body).includes("password"), false);
    assert.match(queries[0].sql, /WHERE p\.id = \$1/);
    assert.deepEqual(queries[0].values, [userId, "me@example.test"]);
    assert.doesNotMatch(queries[0].sql, /p\.avatar_url/);
  });
});

test("GET /me resolves Supabase-authenticated profiles without an app_users row", async () => {
  const queries = [];
  const database = {
    async query(sql, values) {
      queries.push({ sql, values });
      return {
        rows: [{
          id: userId,
          email: "legacy@example.test",
          full_name: "Legacy User",
          display_name: "Legacy User",
          username: null,
          avatar_url: null,
          is_admin: false
        }]
      };
    }
  };
  const legacyAuth = (req, _res, next) => {
    req.user = { id: userId, email: "legacy@example.test" };
    next();
  };
  await withRouter(
    createProfilesRouter({ database, authenticate: legacyAuth }),
    async (base) => {
      const response = await fetch(`${base}/api/profile/me`);
      assert.equal(response.status, 200);
      const body = await response.json();
      assert.equal(body.data.id, userId);
      assert.equal(body.data.email, "legacy@example.test");
      assert.match(queries[0].sql, /FROM public\.profiles p\s+LEFT JOIN public\.app_users u/);
      assert.deepEqual(queries[0].values, [userId, "legacy@example.test"]);
    }
  );
});

test("GET /me returns 404 when profile row missing and never exposes other users", async () => {
  const database = { async query() { return { rows: [] }; } };
  await withRouter(createProfilesRouter({ database, authenticate: actorAuth }), async (base) => {
    const r = await fetch(`${base}/api/profile/me`);
    assert.equal(r.status, 404);
  });
});

test("POST /username rejects invalid username", async () => {
  const database = { async query() { throw new Error("should not query"); } };
  await withRouter(createProfilesRouter({ database, authenticate: actorAuth }), async (base) => {
    const r = await fetch(`${base}/api/profile/username`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ username: "x" }) });
    assert.equal(r.status, 400);
  });
});

test("POST /username updates profiles and app_users in transaction", async () => {
  const calls = [];
  const client = {
    async query(sql, values) {
      calls.push({ sql, values });
      if (sql === "BEGIN" || sql === "COMMIT" || sql === "ROLLBACK") return { rowCount: 0, rows: [] };
      if (sql.includes("FROM (") && sql.includes("UNION ALL") && sql.includes("LIMIT 1")) return { rowCount: 0, rows: [] };
      if (sql.includes("UPDATE public.profiles") && sql.includes("RETURNING")) return { rowCount: 1, rows: [{ id: userId }] };
      if (sql.includes("UPDATE public.app_users")) return { rowCount: 1, rows: [] };
      throw new Error(`unexpected: ${sql}`);
    },
    release() { calls.push({ sql: "RELEASE" }); }
  };
  const database = { connect: async () => client };
  await withRouter(createProfilesRouter({ database, authenticate: actorAuth }), async (base) => {
    const r = await fetch(`${base}/api/profile/username`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ username: "New_Name" }) });
    assert.equal(r.status, 200);
    assert.deepEqual((await r.json()).data, { username: "new_name" });
    assert.equal(calls[0].sql, "BEGIN");
    assert.ok(calls.some(c => c.sql.includes("UPDATE public.profiles") && c.values?.[1] === "new_name" && c.values?.[0] === userId));
    assert.ok(calls.some(c => c.sql.includes("UPDATE public.app_users") && c.values?.[1] === "new_name" && c.values?.[0] === userId));
    assert.ok(calls.some(c => c.sql === "COMMIT"));
    assert.ok(calls.some(c => c.sql === "RELEASE"));
  });
});

test("POST /username returns 409 on conflict and rolls back", async () => {
  const calls = [];
  const client = {
    async query(sql) {
      calls.push(sql);
      if (sql === "BEGIN" || sql === "ROLLBACK") return { rowCount: 0, rows: [] };
      if (sql.includes("UNION ALL")) return { rowCount: 1, rows: [{ "?column?": 1 }] };
      throw new Error(`unexpected: ${sql}`);
    },
    release() {}
  };
  await withRouter(createProfilesRouter({ database: { connect: async () => client }, authenticate: actorAuth }), async (base) => {
    const r = await fetch(`${base}/api/profile/username`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ username: "taken_name" }) });
    assert.equal(r.status, 409);
    assert.ok(calls.includes("ROLLBACK"));
    assert.equal(calls.some(s => s.includes("UPDATE public.profiles")), false);
  });
});

test("POST /username rolls back when app_users update fails", async () => {
  const calls = [];
  const client = {
    async query(sql) {
      calls.push(sql);
      if (sql === "BEGIN" || sql === "ROLLBACK") return { rowCount: 0, rows: [] };
      if (sql.includes("UNION ALL")) return { rowCount: 0, rows: [] };
      if (sql.includes("UPDATE public.profiles") && sql.includes("RETURNING")) return { rowCount: 1, rows: [{ id: userId }] };
      if (sql.includes("UPDATE public.app_users")) throw new Error("db fail");
      throw new Error(`unexpected: ${sql}`);
    },
    release() {}
  };
  await withRouter(createProfilesRouter({ database: { connect: async () => client }, authenticate: actorAuth }), async (base) => {
    const r = await fetch(`${base}/api/profile/username`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ username: "valid_name" }) });
    assert.equal(r.status, 500);
    assert.ok(calls.includes("ROLLBACK"));
    assert.equal(calls.includes("COMMIT"), false);
  });
});

test("POST /username rolls back when profile missing (no other-user mutation path)", async () => {
  const calls = [];
  const client = {
    async query(sql) {
      calls.push(sql);
      if (sql === "BEGIN" || sql === "ROLLBACK") return { rowCount: 0, rows: [] };
      if (sql.includes("UNION ALL")) return { rowCount: 0, rows: [] };
      if (sql.includes("UPDATE public.profiles") && sql.includes("RETURNING")) return { rowCount: 0, rows: [] };
      throw new Error(`unexpected: ${sql}`);
    },
    release() {}
  };
  await withRouter(createProfilesRouter({ database: { connect: async () => client }, authenticate: actorAuth }), async (base) => {
    const r = await fetch(`${base}/api/profile/username`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ username: "valid_name" }) });
    assert.equal(r.status, 404);
    assert.ok(calls.includes("ROLLBACK"));
    assert.equal(calls.some(s => s.includes("UPDATE public.app_users")), false);
  });
});

test("G6 POST /username ignores user_id in body/query (mutates only req.user.id)", async () => {
  const calls = [];
  const client = {
    async query(sql, values) {
      calls.push({ sql, values });
      if (sql === "BEGIN" || sql === "COMMIT" || sql === "ROLLBACK") return { rowCount: 0, rows: [] };
      if (sql.includes("FROM (") && sql.includes("UNION ALL") && sql.includes("LIMIT 1")) return { rowCount: 0, rows: [] };
      if (sql.includes("UPDATE public.profiles") && sql.includes("RETURNING")) return { rowCount: 1, rows: [{ id: userId }] };
      if (sql.includes("UPDATE public.app_users")) return { rowCount: 1, rows: [] };
      throw new Error(`unexpected: ${sql}`);
    },
    release() {}
  };
  const database = { connect: async () => client };
  await withRouter(createProfilesRouter({ database, authenticate: actorAuth }), async (base) => {
    const r = await fetch(`${base}/api/profile/username?user_id=${otherId}&id=${otherId}`, {
      method: "POST", headers: { "content-type": "application/json" },
      body: JSON.stringify({ username: "safe_name", user_id: otherId, id: otherId, target_user_id: otherId })
    });
    assert.equal(r.status, 200);
    assert.equal(calls.some(c => c.values?.[0] === otherId), false);
    assert.ok(calls.some(c => c.sql.includes("UPDATE public.profiles") && c.values?.[0] === userId));
    assert.ok(calls.some(c => c.sql.includes("UPDATE public.app_users") && c.values?.[0] === userId));
  });
});

// --- G6 isolation: backend-independent only (no Supabase fallback) ---
const TEST_SECRET = process.env.JWT_SECRET && process.env.JWT_SECRET.length >= 64 ? process.env.JWT_SECRET : "s".repeat(64);
const enc = new TextEncoder().encode(TEST_SECRET);
async function signBackendToken({ sub = userId, sid = "22222222-2222-4222-8222-222222222222", expSec = 3600 } = {}) {
  return await new SignJWT({ sub, sid, role: "authenticated" })
    .setProtectedHeader({ alg: "HS256" })
    .setIssuer("motri-iq-api")
    .setAudience("authenticated")
    .setExpirationTime(Math.floor(Date.now() / 1000) + expSec)
    .sign(enc);
}
async function signForeignToken() {
  const other = new TextEncoder().encode("x".repeat(64));
  return await new SignJWT({ sub: userId, role: "authenticated" })
    .setProtectedHeader({ alg: "HS256" })
    .setIssuer("https://supabase.example/auth/v1")
    .setAudience("authenticated")
    .setExpirationTime("1h")
    .sign(other);
}
function dbSession(userRow) { return { query: async () => ({ rows: userRow ? [userRow] : [] }), connect: async () => ({ async query(){ return {rowCount:0,rows:[]}; }, release(){} }) }; }
function dbSessionTracked() {
  let sessionQueries = 0;
  return {
    get sessionQueries() { return sessionQueries; },
    query: async (sql) => {
      if (sql.includes("app_sessions")) sessionQueries += 1;
      return { rows: [] };
    },
    connect: async () => ({ async query() { return { rowCount: 0, rows: [] }; }, release() {} })
  };
}
function realAuth(db) { return createAuthenticateBackendIndependent({ database: db }); }

test("G6 GET /me: valid backend JWT reads own profile", async () => {
  const sessionDb = { query: async (sql) => sql.includes("app_sessions") ? { rows: [{ id: userId, email: "me@example.test", is_admin: false }] } : { rows: [{ id: userId, email: "me@example.test", phone: "077", full_name: "T", display_name: "T", username: "tuser", avatar_url: null, is_admin: false }] } };
  await withRouter(createProfilesRouter({ database: sessionDb, authenticate: realAuth(sessionDb) }), async (base) => {
    const token = await signBackendToken();
    const r = await fetch(`${base}/api/profile/me`, { headers: { authorization: `Bearer ${token}` } });
    assert.equal(r.status, 200);
    const body = await r.json();
    assert.equal(body.data.id, userId);
  });
});

test("G6 POST /username: valid backend JWT updates own username (existing rules)", async () => {
  const calls = [];
  const client = {
    async query(sql, values) {
      calls.push({ sql, values });
      if (sql === "BEGIN" || sql === "COMMIT" || sql === "ROLLBACK") return { rowCount: 0, rows: [] };
      if (sql.includes("FROM (") && sql.includes("UNION ALL") && sql.includes("LIMIT 1")) return { rowCount: 0, rows: [] };
      if (sql.includes("UPDATE public.profiles") && sql.includes("RETURNING")) return { rowCount: 1, rows: [{ id: userId }] };
      if (sql.includes("UPDATE public.app_users")) return { rowCount: 1, rows: [] };
      return { rowCount: 0, rows: [] };
    }, release() {}
  };
  const db = {
    connect: async () => client,
    async query(sql) { if (sql.includes("app_sessions")) return { rows: [{ id: userId, email: "me@example.test", is_admin: false }] }; return { rows: [] }; }
  };
  await withRouter(createProfilesRouter({ database: db, authenticate: realAuth(db) }), async (base) => {
    const token = await signBackendToken();
    const r = await fetch(`${base}/api/profile/username`, { method: "POST", headers: { authorization: `Bearer ${token}`, "content-type": "application/json" }, body: JSON.stringify({ username: "new_name" }) });
    assert.equal(r.status, 200);
    assert.ok(calls.some(c => c.sql.includes("UPDATE public.profiles") && c.values?.[0] === userId));
  });
});

test("G6 GET /me: Supabase/foreign JWT alone -> 401 (no fallback)", async () => {
  const db = dbSession(null);
  await withRouter(createProfilesRouter({ database: db, authenticate: realAuth(db) }), async (base) => {
    const r = await fetch(`${base}/api/profile/me`, { headers: { authorization: `Bearer ${await signForeignToken()}` } });
    assert.equal(r.status, 401);
  });
});
test("G6 POST /username: Supabase/foreign JWT alone -> 401 (no fallback)", async () => {
  const db = dbSession(null);
  await withRouter(createProfilesRouter({ database: db, authenticate: realAuth(db) }), async (base) => {
    const r = await fetch(`${base}/api/profile/username`, { method: "POST", headers: { authorization: `Bearer ${await signForeignToken()}`, "content-type": "application/json" }, body: JSON.stringify({ username: "abc" }) });
    assert.equal(r.status, 401);
  });
});
test("G6: missing token -> 401 for /me and /username", async () => {
  const db = dbSession(null);
  await withRouter(createProfilesRouter({ database: db, authenticate: realAuth(db) }), async (base) => {
    assert.equal((await fetch(`${base}/api/profile/me`)).status, 401);
    assert.equal((await fetch(`${base}/api/profile/username`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ username: "abc" }) })).status, 401);
  });
});
test("G6: expired backend JWT -> 401 for /me and /username", async () => {
  const db = dbSession(null);
  const token = await signBackendToken({ expSec: -60 });
  await withRouter(createProfilesRouter({ database: db, authenticate: realAuth(db) }), async (base) => {
    assert.equal((await fetch(`${base}/api/profile/me`, { headers: { authorization: `Bearer ${token}` } })).status, 401);
    assert.equal((await fetch(`${base}/api/profile/username`, { method: "POST", headers: { authorization: `Bearer ${token}`, "content-type": "application/json" }, body: JSON.stringify({ username: "abc" }) })).status, 401);
  });
});
test("G6: revoked/invalid session -> 401 for /me and /username", async () => {
  const db = dbSession(null); // session lookup returns empty
  const token = await signBackendToken();
  await withRouter(createProfilesRouter({ database: db, authenticate: realAuth(db) }), async (base) => {
    assert.equal((await fetch(`${base}/api/profile/me`, { headers: { authorization: `Bearer ${token}` } })).status, 401);
    assert.equal((await fetch(`${base}/api/profile/username`, { method: "POST", headers: { authorization: `Bearer ${token}`, "content-type": "application/json" }, body: JSON.stringify({ username: "abc" }) })).status, 401);
  });
});

async function signBackendTokenCustom({ iss = "motri-iq-api", aud = "authenticated", alg = "HS256", key = enc, expSec = 3600 } = {}) {
  const token = new SignJWT({ sub: userId, sid: "22222222-2222-4222-8222-222222222222", role: "authenticated" })
    .setProtectedHeader({ alg })
    .setSubject(userId)
    .setIssuer(iss)
    .setAudience(aud)
    .setIssuedAt();
  token.setExpirationTime(Math.floor(Date.now() / 1000) + expSec);
  return token.sign(key);
}

test("G10.9 G6: backend JWT wrong signature -> 401, no fallback, no session lookup", async () => {
  const db = dbSessionTracked();
  const token = await signBackendTokenCustom({ key: new TextEncoder().encode("x".repeat(64)) });
  await withRouter(createProfilesRouter({ database: db, authenticate: realAuth(db) }), async (base) => {
    assert.equal((await fetch(`${base}/api/profile/me`, { headers: { authorization: `Bearer ${token}` } })).status, 401);
    assert.equal((await fetch(`${base}/api/profile/username`, { method: "POST", headers: { authorization: `Bearer ${token}`, "content-type": "application/json" }, body: JSON.stringify({ username: "abc" }) })).status, 401);
  });
  assert.equal(db.sessionQueries, 0);
});

test("G10.9 G6: backend JWT wrong issuer -> 401, no fallback, no session lookup", async () => {
  const db = dbSessionTracked();
  const token = await signBackendTokenCustom({ iss: "https://supabase.example/auth/v1" });
  await withRouter(createProfilesRouter({ database: db, authenticate: realAuth(db) }), async (base) => {
    assert.equal((await fetch(`${base}/api/profile/me`, { headers: { authorization: `Bearer ${token}` } })).status, 401);
    assert.equal((await fetch(`${base}/api/profile/username`, { method: "POST", headers: { authorization: `Bearer ${token}`, "content-type": "application/json" }, body: JSON.stringify({ username: "abc" }) })).status, 401);
  });
  assert.equal(db.sessionQueries, 0);
});

test("G10.9 G6: backend JWT wrong audience -> 401, no fallback, no session lookup", async () => {
  const db = dbSessionTracked();
  const token = await signBackendTokenCustom({ aud: "anon" });
  await withRouter(createProfilesRouter({ database: db, authenticate: realAuth(db) }), async (base) => {
    assert.equal((await fetch(`${base}/api/profile/me`, { headers: { authorization: `Bearer ${token}` } })).status, 401);
    assert.equal((await fetch(`${base}/api/profile/username`, { method: "POST", headers: { authorization: `Bearer ${token}`, "content-type": "application/json" }, body: JSON.stringify({ username: "abc" }) })).status, 401);
  });
  assert.equal(db.sessionQueries, 0);
});

test("G10.9 G6: backend JWT disallowed algorithm -> 401, no fallback, no session lookup", async () => {
  const db = dbSessionTracked();
  const token = await signBackendTokenCustom({ alg: "HS384" });
  await withRouter(createProfilesRouter({ database: db, authenticate: realAuth(db) }), async (base) => {
    assert.equal((await fetch(`${base}/api/profile/me`, { headers: { authorization: `Bearer ${token}` } })).status, 401);
    assert.equal((await fetch(`${base}/api/profile/username`, { method: "POST", headers: { authorization: `Bearer ${token}`, "content-type": "application/json" }, body: JSON.stringify({ username: "abc" }) })).status, 401);
  });
  assert.equal(db.sessionQueries, 0);
});
