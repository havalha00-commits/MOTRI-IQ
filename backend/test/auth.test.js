import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { after, before, test } from "node:test";
import bcrypt from "bcryptjs";
import express from "express";
import { SignJWT } from "jose";

process.env.JWT_SECRET = "test-secret-that-is-long-enough-for-auth-tests-0123456789-abcdefgh";

const [{ createAuthRouter }, { createAuthenticateToken }] = await Promise.all([
  import("../routes/auth.js"),
  import("../middleware/auth.js")
]);

const TEST_SECRET = process.env.JWT_SECRET;
const userId = "50ea06ad-606a-4b6f-9ab6-2a14e13e54b0";
const password = "test-account-password";
const passwordHash = await bcrypt.hash(password, 4).then((value) =>
  value.replace(/^\$2b\$/, "$2a$")
);

function hashToken(token) {
  return createHash("sha256").update(token).digest("hex");
}

function createFakeDatabase() {
  const sessions = new Map();
  let user = {
    id: userId,
    email: "member@example.test",
    username: "member_test",
    encrypted_password: passwordHash,
    email_confirmed_at: new Date(),
    banned_until: null,
    deleted_at: null,
    is_admin: false
  };

  function runQuery(sql, params = []) {
    if (sql.includes("FROM public.app_users u")) {
      const [identifier, identityColumn] = params;
      const matches =
        identityColumn === "email"
          ? user.email.toLowerCase() === identifier
          : user.username.toLowerCase() === identifier;
      return { rows: matches ? [{ ...user }] : [] };
    }

    if (sql.includes("INSERT INTO public.app_sessions")) {
      const [id, sessionUserId, refreshHash] = params;
      sessions.set(refreshHash, {
        id,
        user_id: sessionUserId,
        revoked_at: null,
        expires_at: Date.now() + 30 * 24 * 60 * 60 * 1000
      });
      return { rows: [], rowCount: 1 };
    }

    if (sql.includes("UPDATE public.app_sessions") && sql.includes("revoked_at = COALESCE")) {
      const [refreshHash] = params;
      const session = sessions.get(refreshHash);
      if (session) session.revoked_at = new Date();
      return { rows: [], rowCount: session ? 1 : 0 };
    }

    if (sql.includes("UPDATE public.app_sessions") && sql.includes("refresh_token_hash = $1")) {
      const [nextHash, sessionId] = params;
      const current = [...sessions.entries()].find(([, value]) => value.id === sessionId);
      if (!current) return { rows: [], rowCount: 0 };
      sessions.delete(current[0]);
      sessions.set(nextHash, {
        ...current[1],
        expires_at: Date.now() + 30 * 24 * 60 * 60 * 1000
      });
      return { rows: [], rowCount: 1 };
    }

    if (sql.includes("FROM public.app_sessions s") && sql.includes("WHERE s.id = $1")) {
      const [sessionId, sessionUserId] = params;
      const session = [...sessions.values()].find((value) =>
        value.id === sessionId && value.user_id === sessionUserId
      );
      if (!session || session.revoked_at || session.expires_at <= Date.now()) {
        return { rows: [] };
      }
      return {
        rows: [{
          id: user.id,
          email: user.email,
          is_admin: user.is_admin
        }]
      };
    }

    if (sql.includes("FROM public.app_sessions s")) {
      const [refreshHash] = params;
      const session = sessions.get(refreshHash);
      if (!session || session.revoked_at || session.expires_at <= Date.now()) {
        return { rows: [] };
      }
      return {
        rows: [{
          session_id: session.id,
          id: user.id,
          email: user.email,
          username: user.username,
          email_confirmed_at: user.email_confirmed_at,
          banned_until: user.banned_until,
          deleted_at: user.deleted_at,
          is_admin: user.is_admin
        }]
      };
    }

    if (sql === "BEGIN" || sql === "COMMIT" || sql === "ROLLBACK") {
      return { rows: [] };
    }

    throw new Error(`Unexpected SQL in auth test: ${sql}`);
  }

  return {
    sessions,
    setUser(nextUser) {
      user = nextUser;
    },
    async query(sql, params) {
      return runQuery(sql, params);
    },
    async connect() {
      return {
        query: async (sql, params) => runQuery(sql, params),
        release() {}
      };
    }
  };
}

const database = createFakeDatabase();
const app = express();
app.use(express.json());
app.use("/api/auth", createAuthRouter({ database, jwtSecret: TEST_SECRET }));
app.get(
  "/api/protected",
  createAuthenticateToken({ database, jwtSecret: TEST_SECRET }),
  (req, res) => res.json({ user: req.user })
);

let server;
let baseUrl;

before(async () => {
  server = app.listen(0);
  await new Promise((resolve) => server.once("listening", resolve));
  baseUrl = `http://127.0.0.1:${server.address().port}`;
});

after(async () => {
  await new Promise((resolve, reject) =>
    server.close((error) => error ? reject(error) : resolve())
  );
});

async function post(path, body) {
  return fetch(`${baseUrl}${path}`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body)
  });
}

test("logs in with email or username and protects session with app_sessions", async () => {
  const response = await post("/api/auth/login", {
    identifier: "MEMBER_TEST",
    password
  });
  assert.equal(response.status, 200);
  const payload = await response.json();
  assert.equal(payload.authenticated, true);
  assert.equal(payload.user.id, userId);
  assert.equal(payload.user.username, "member_test");
  assert.ok(Object.hasOwn(payload.user, "full_name"));
  assert.ok(Object.hasOwn(payload.user, "phone"));
  assert.ok(Object.hasOwn(payload.user, "avatar_url"));
  assert.equal(JSON.stringify(payload).includes("encrypted_password"), false);
  assert.equal(database.sessions.size, 1);

  const protectedResponse = await fetch(`${baseUrl}/api/protected`, {
    headers: { authorization: `Bearer ${payload.access_token}` }
  });
  assert.equal(protectedResponse.status, 200);
  assert.equal((await protectedResponse.json()).user.id, userId);
});

test("rotates refresh tokens and rejects the previous token", async () => {
  const login = await post("/api/auth/login", {
    email: "member@example.test",
    password
  });
  const initial = await login.json();

  const refreshed = await post("/api/auth/refresh", {
    refresh_token: initial.refresh_token
  });
  assert.equal(refreshed.status, 200);
  const next = await refreshed.json();
  assert.notEqual(next.refresh_token, initial.refresh_token);
  assert.equal(database.sessions.has(hashToken(next.refresh_token)), true);
  assert.equal(database.sessions.has(hashToken(initial.refresh_token)), false);

  const replay = await post("/api/auth/refresh", {
    refresh_token: initial.refresh_token
  });
  assert.equal(replay.status, 401);
});

test("logout revokes refresh token and session-bound access tokens", async () => {
  const login = await post("/api/auth/login", {
    email: "member@example.test",
    password
  });
  const tokens = await login.json();

  const logout = await post("/api/auth/logout", {
    refresh_token: tokens.refresh_token
  });
  assert.equal(logout.status, 200);

  const refresh = await post("/api/auth/refresh", {
    refresh_token: tokens.refresh_token
  });
  assert.equal(refresh.status, 401);

  const protectedResponse = await fetch(`${baseUrl}/api/protected`, {
    headers: { authorization: `Bearer ${tokens.access_token}` }
  });
  assert.equal(protectedResponse.status, 401);
});

test("rejects access tokens without a session id", async () => {
  const token = await new SignJWT({ role: "authenticated" })
    .setProtectedHeader({ alg: "HS256" })
    .setSubject(userId)
    .setIssuer("motri-iq-api")
    .setAudience("authenticated")
    .setExpirationTime("1m")
    .sign(new TextEncoder().encode(TEST_SECRET));

  const response = await fetch(`${baseUrl}/api/protected`, {
    headers: { authorization: `Bearer ${token}` }
  });
  assert.equal(response.status, 401);
});

test("keeps passwords and account state checks enforced", async () => {
  const wrongPassword = await post("/api/auth/login", {
    email: "member@example.test",
    password: "wrong"
  });
  assert.equal(wrongPassword.status, 401);

  database.setUser({
    id: userId,
    email: "member@example.test",
    username: "member_test",
    encrypted_password: passwordHash,
    email_confirmed_at: null,
    banned_until: null,
    deleted_at: null,
    is_admin: false
  });
  const unconfirmed = await post("/api/auth/login", {
    email: "member@example.test",
    password
  });
  assert.equal(unconfirmed.status, 403);
});

async function signBackendAccessToken({
  sub = userId,
  sid = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
  issuer = "motri-iq-api",
  audience = "authenticated",
  alg = "HS256",
  key = TEST_SECRET,
  expSec = 60
} = {}) {
  const token = new SignJWT({ role: "authenticated", sid })
    .setProtectedHeader({ alg })
    .setSubject(sub)
    .setIssuer(issuer)
    .setAudience(audience)
    .setIssuedAt();
  token.setExpirationTime(Math.floor(Date.now() / 1000) + expSec);
  return token.sign(new TextEncoder().encode(key));
}

function mockRes() {
  return {
    statusCode: 200,
    body: null,
    status(code) { this.statusCode = code; return this; },
    json(data) { this.body = data; return this; }
  };
}

test("G10.9 auth middleware: rejects JWT with wrong signature (no session lookup)", async () => {
  let sessionQueries = 0;
  const scopedDb = {
    query: async (sql) => {
      if (sql.includes("FROM public.app_sessions s") && sql.includes("WHERE s.id = $1")) sessionQueries += 1;
      return { rows: [] };
    }
  };
  const mw = createAuthenticateToken({ database: scopedDb, jwtSecret: TEST_SECRET });
  const token = await signBackendAccessToken({ key: "x".repeat(64) });
  const req = { headers: { authorization: `Bearer ${token}` } };
  const res = mockRes();
  let next = false;
  await mw(req, res, () => { next = true; });
  assert.equal(next, false);
  assert.equal(res.statusCode, 401);
  assert.equal(res.body.error, "Invalid or expired authentication token");
  assert.equal(sessionQueries, 0);
});

test("G10.9 auth middleware: rejects JWT with wrong issuer (no session lookup)", async () => {
  let sessionQueries = 0;
  const scopedDb = {
    query: async (sql) => {
      if (sql.includes("FROM public.app_sessions s") && sql.includes("WHERE s.id = $1")) sessionQueries += 1;
      return { rows: [] };
    }
  };
  const mw = createAuthenticateToken({ database: scopedDb, jwtSecret: TEST_SECRET });
  const token = await signBackendAccessToken({ issuer: "https://supabase.example/auth/v1" });
  const req = { headers: { authorization: `Bearer ${token}` } };
  const res = mockRes();
  let next = false;
  await mw(req, res, () => { next = true; });
  assert.equal(next, false);
  assert.equal(res.statusCode, 401);
  assert.equal(res.body.error, "Invalid or expired authentication token");
  assert.equal(sessionQueries, 0);
});

test("G10.9 auth middleware: rejects JWT with wrong audience (no session lookup)", async () => {
  let sessionQueries = 0;
  const scopedDb = {
    query: async (sql) => {
      if (sql.includes("FROM public.app_sessions s") && sql.includes("WHERE s.id = $1")) sessionQueries += 1;
      return { rows: [] };
    }
  };
  const mw = createAuthenticateToken({ database: scopedDb, jwtSecret: TEST_SECRET });
  const token = await signBackendAccessToken({ audience: "anon" });
  const req = { headers: { authorization: `Bearer ${token}` } };
  const res = mockRes();
  let next = false;
  await mw(req, res, () => { next = true; });
  assert.equal(next, false);
  assert.equal(res.statusCode, 401);
  assert.equal(res.body.error, "Invalid or expired authentication token");
  assert.equal(sessionQueries, 0);
});

test("G10.9 auth middleware: rejects JWT with disallowed algorithm (no session lookup)", async () => {
  let sessionQueries = 0;
  const scopedDb = {
    query: async (sql) => {
      if (sql.includes("FROM public.app_sessions s") && sql.includes("WHERE s.id = $1")) sessionQueries += 1;
      return { rows: [] };
    }
  };
  const mw = createAuthenticateToken({ database: scopedDb, jwtSecret: TEST_SECRET });
  const token = await signBackendAccessToken({ alg: "HS384" });
  const req = { headers: { authorization: `Bearer ${token}` } };
  const res = mockRes();
  let next = false;
  await mw(req, res, () => { next = true; });
  assert.equal(next, false);
  assert.equal(res.statusCode, 401);
  assert.equal(res.body.error, "Invalid or expired authentication token");
  assert.equal(sessionQueries, 0);
});

test("G10.9 auth middleware: rejects expired backend JWT (no session lookup)", async () => {
  let sessionQueries = 0;
  const scopedDb = {
    query: async (sql) => {
      if (sql.includes("FROM public.app_sessions s") && sql.includes("WHERE s.id = $1")) sessionQueries += 1;
      return { rows: [] };
    }
  };
  const mw = createAuthenticateToken({ database: scopedDb, jwtSecret: TEST_SECRET });
  const token = await signBackendAccessToken({ expSec: -60 });
  const req = { headers: { authorization: `Bearer ${token}` } };
  const res = mockRes();
  let next = false;
  await mw(req, res, () => { next = true; });
  assert.equal(next, false);
  assert.equal(res.statusCode, 401);
  assert.equal(res.body.error, "Invalid or expired authentication token");
  assert.equal(sessionQueries, 0);
});
