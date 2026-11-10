import assert from "node:assert/strict";
import { once } from "node:events";
import { after, before, test } from "node:test";
import express from "express";
import { SignJWT } from "jose";
import { createAuthenticateToken } from "../middleware/auth.js";

// Contract under test (read from backend/server.js:89-94):
// app.get("/api/me", authenticateToken, (req, res) => {
//   res.json({ authenticated: true, user: req.user });
// });
//
// Test strategy (no production changes, no DB/network, no Supabase fallback):
// - server.js wires app.listen/pool/imports at module load (not testable in isolation).
// - We mount the REAL createAuthenticateToken() factory with an injected mock DB
//   and the EXACT /api/me handler shape from server.js on a local HTTP server.
//   Requests traverse the real middleware + real route handler.
const TEST_SECRET =
  process.env.JWT_SECRET && process.env.JWT_SECRET.length >= 64
    ? process.env.JWT_SECRET
    : "s".repeat(64);

const userId = "50ea06ad-606a-4b6f-9ab6-2a14e13e54b0";
const sessionId = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const otherUserId = "11111111-1111-4111-8111-111111111111";

function registerMeRoute(app, { database }) {
  const authenticateToken = createAuthenticateToken({ database, jwtSecret: TEST_SECRET });
  // Exact handler contract from server.js
  app.get("/api/me", authenticateToken, (req, res) => {
    res.json({ authenticated: true, user: req.user });
  });
}

async function withMeServer(database, callback) {
  const app = express();
  registerMeRoute(app, { database });
  const server = app.listen(0, "127.0.0.1");
  await once(server, "listening");
  const { port } = server.address();
  try {
    await callback(`http://127.0.0.1:${port}`);
  } finally {
    await new Promise((resolve, reject) => server.close((e) => (e ? reject(e) : resolve())));
  }
}

async function signBackendAccessToken({
  sub = userId,
  sid = sessionId,
  iss = "motri-iq-api",
  aud = "authenticated",
  alg = "HS256",
  key = TEST_SECRET,
  expSec = 60,
  role = "authenticated",
} = {}) {
  const payload = { role };
  if (sid !== undefined) payload.sid = sid;
  const token = new SignJWT(payload)
    .setProtectedHeader({ alg })
    .setSubject(sub)
    .setIssuer(iss)
    .setAudience(aud)
    .setIssuedAt();
  token.setExpirationTime(Math.floor(Date.now() / 1000) + expSec);
  return token.sign(new TextEncoder().encode(key));
}

async function signSupabaseLikeJwt() {
  const other = new TextEncoder().encode("x".repeat(64));
  return new SignJWT({ sub: userId, sid: sessionId, role: "authenticated" })
    .setProtectedHeader({ alg: "HS256" })
    .setIssuer("https://example.supabase.co/auth/v1")
    .setAudience("authenticated")
    .setExpirationTime("1h")
    .sign(other);
}

function sessionDb({ row = null, onQuery } = {}) {
  return {
    async query(sql, params) {
      onQuery?.(sql, params);
      return { rows: row ? [row] : [] };
    },
  };
}

async function get(base, token, extraHeaders = {}) {
  const headers = { ...extraHeaders };
  if (token !== undefined) headers.authorization = `Bearer ${token}`;
  return fetch(`${base}/api/me`, { headers });
}

test("GET /api/me: valid backend JWT + valid session returns current contract", async () => {
  const queries = [];
  const db = sessionDb({
    row: { id: userId, email: "member@example.test", is_admin: false },
    onQuery: (sql, params) => queries.push({ sql, params }),
  });
  await withMeServer(db, async (base) => {
    const token = await signBackendAccessToken();
    const res = await get(base, token);
    assert.equal(res.status, 200);
    assert.deepEqual(await res.json(), {
      authenticated: true,
      user: { id: userId, role: "authenticated", email: "member@example.test", is_admin: false },
    });
  });
  const sessionLookup = queries.find((q) => q.sql.includes("FROM public.app_sessions s") && q.sql.includes("WHERE s.id = $1"));
  assert.ok(sessionLookup, "route should reach real middleware session lookup");
  assert.deepEqual(sessionLookup.params, [sessionId, userId]);
});

test("GET /api/me: missing Authorization -> 401, no session lookup", async () => {
  let sessionQueries = 0;
  const db = sessionDb({ onQuery: (sql) => { if (sql.includes("app_sessions")) sessionQueries++; } });
  await withMeServer(db, async (base) => {
    const res = await fetch(`${base}/api/me`);
    assert.equal(res.status, 401);
    assert.deepEqual(await res.json(), { error: "Authentication token required" });
  });
  assert.equal(sessionQueries, 0);
});

test("GET /api/me: Supabase-like JWT rejected, no Supabase fallback, no session lookup", async () => {
  let sessionQueries = 0;
  const db = sessionDb({ onQuery: (sql) => { if (sql.includes("app_sessions")) sessionQueries++; } });
  await withMeServer(db, async (base) => {
    const res = await get(base, await signSupabaseLikeJwt());
    assert.equal(res.status, 401);
    assert.deepEqual(await res.json(), { error: "Invalid or expired authentication token" });
  });
  assert.equal(sessionQueries, 0);
});

test("GET /api/me: wrong signature -> 401, no session lookup", async () => {
  let sessionQueries = 0;
  const db = sessionDb({ onQuery: (sql) => { if (sql.includes("app_sessions")) sessionQueries++; } });
  await withMeServer(db, async (base) => {
    const res = await get(base, await signBackendAccessToken({ key: "x".repeat(64) }));
    assert.equal(res.status, 401);
    assert.deepEqual(await res.json(), { error: "Invalid or expired authentication token" });
  });
  assert.equal(sessionQueries, 0);
});

test("GET /api/me: wrong issuer -> 401, no session lookup", async () => {
  let sessionQueries = 0;
  const db = sessionDb({ onQuery: (sql) => { if (sql.includes("app_sessions")) sessionQueries++; } });
  await withMeServer(db, async (base) => {
    const res = await get(base, await signBackendAccessToken({ iss: "https://example.supabase.co/auth/v1" }));
    assert.equal(res.status, 401);
    assert.deepEqual(await res.json(), { error: "Invalid or expired authentication token" });
  });
  assert.equal(sessionQueries, 0);
});

test("GET /api/me: wrong audience -> 401, no session lookup", async () => {
  let sessionQueries = 0;
  const db = sessionDb({ onQuery: (sql) => { if (sql.includes("app_sessions")) sessionQueries++; } });
  await withMeServer(db, async (base) => {
    const res = await get(base, await signBackendAccessToken({ aud: "anon" }));
    assert.equal(res.status, 401);
    assert.deepEqual(await res.json(), { error: "Invalid or expired authentication token" });
  });
  assert.equal(sessionQueries, 0);
});

test("GET /api/me: disallowed algorithm -> 401, no session lookup", async () => {
  let sessionQueries = 0;
  const db = sessionDb({ onQuery: (sql) => { if (sql.includes("app_sessions")) sessionQueries++; } });
  await withMeServer(db, async (base) => {
    const res = await get(base, await signBackendAccessToken({ alg: "HS384" }));
    assert.equal(res.status, 401);
    assert.deepEqual(await res.json(), { error: "Invalid or expired authentication token" });
  });
  assert.equal(sessionQueries, 0);
});

test("GET /api/me: expired JWT -> 401, no session lookup", async () => {
  let sessionQueries = 0;
  const db = sessionDb({ onQuery: (sql) => { if (sql.includes("app_sessions")) sessionQueries++; } });
  await withMeServer(db, async (base) => {
    const res = await get(base, await signBackendAccessToken({ expSec: -60 }));
    assert.equal(res.status, 401);
    assert.deepEqual(await res.json(), { error: "Invalid or expired authentication token" });
  });
  assert.equal(sessionQueries, 0);
});

test("GET /api/me: invalid/revoked session (no session row) -> 401 after session lookup", async () => {
  let sessionQueries = 0;
  const db = sessionDb({ onQuery: (sql) => { if (sql.includes("app_sessions")) sessionQueries++; } });
  await withMeServer(db, async (base) => {
    const res = await get(base, await signBackendAccessToken());
    assert.equal(res.status, 401);
    assert.deepEqual(await res.json(), { error: "Session is invalid or revoked" });
  });
  assert.ok(sessionQueries >= 1);
});

test("GET /api/me: identity comes from JWT/session, not client-supplied user_id", async () => {
  const queries = [];
  const db = sessionDb({
    row: { id: userId, email: "member@example.test", is_admin: false },
    onQuery: (sql, params) => queries.push({ sql, params }),
  });
  await withMeServer(db, async (base) => {
    const token = await signBackendAccessToken();
    // GET /api/me (per server.js) does not read req.body; client cannot supply user_id
    // through a supported contract. We still send misleading query/header values and
    // assert the real middleware resolves identity only from verified token (sid, sub).
    const res = await fetch(`${base}/api/me?user_id=${otherUserId}&id=${otherUserId}`, {
      headers: { authorization: `Bearer ${token}`, "x-user-id": otherUserId },
    });
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.user.id, userId);
    assert.notEqual(body.user.id, otherUserId);
  });
  const sessionLookup = queries.find((q) => q.sql.includes("WHERE s.id = $1"));
  assert.ok(sessionLookup);
  assert.deepEqual(sessionLookup.params, [sessionId, userId]);
  assert.equal(sessionLookup.params.includes(otherUserId), false);
});
