import assert from "node:assert/strict";
import { once } from "node:events";
import express from "express";
import { test } from "node:test";
import { SignJWT } from "jose";

// G10.16/G10.17 (TEST-ONLY assertions, scoped production migration in G10.17):
// favorites route auth using REAL middleware factory (createAuthenticateBackendIndependent)
// and REAL production favorites router (createFavoritesRouter). G10.17 migrated the
// router's default auth to authenticateBackendIndependent (backend JWT only, no
// Supabase fallback). Tests use injected mock DB + local Express; no Neon/real DB,
// no network, no production route changes beyond favorites auth wiring.
//
// IMPORTANT: current_user.js reads JWT_SECRET at module load (signingKey). We set
// test env BEFORE dynamic imports. DATABASE_URL is dummy to satisfy config/database
// if imported; injected database is used, so Pool is never exercised.
const TEST_SECRET =
  process.env.JWT_SECRET && process.env.JWT_SECRET.length >= 64
    ? process.env.JWT_SECRET
    : "s".repeat(64);
process.env.JWT_SECRET = TEST_SECRET;
process.env.DATABASE_URL =
  process.env.DATABASE_URL ||
  "postgresql://testuser:testpass@127.0.0.1:1/test_no_connect";
process.env.NODE_ENV = "test";

const { createAuthenticateBackendIndependent } = await import(
  "../middleware/current_user.js"
);
const { createFavoritesRouter } = await import("../routes/favorites.js");

const userId = "50ea06ad-606a-4b6f-9ab6-2a14e13e54b0";
const otherUserId = "11111111-1111-4111-8111-111111111111";
const sessionId = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const carId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";

async function signBackendAccessToken({
  sub = userId,
  sid = sessionId,
  iss = "motri-iq-api",
  aud = "authenticated",
  alg = "HS256",
  key = TEST_SECRET,
  expSec = 60,
} = {}) {
  const token = new SignJWT({ sub, sid, role: "authenticated" })
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

function validSessionRow(id = userId) {
  return { id, email: "member@example.test", is_admin: false };
}

function makeDb({
  sessionRow = validSessionRow(),
  sessionQueries = [],
  dataQueries = [],
  favoriteExists = false,
} = {}) {
  return {
    async query(sql, params) {
      if (sql.includes("FROM public.app_sessions s")) {
        sessionQueries.push({ sql, params });
        return { rows: sessionRow ? [sessionRow] : [], rowCount: sessionRow ? 1 : 0 };
      }
      dataQueries.push({ sql, params });
      if (sql.includes("FROM public.favorites") && sql.includes("ORDER BY created_at DESC")) {
        return {
          rows: [
            {
              id: "fav-1",
              user_id: userId,
              item_type: "car",
              item_id: carId,
              car_id: carId,
              created_at: "2026-01-01T00:00:00.000Z",
            },
          ],
          rowCount: 1,
        };
      }
      if (sql.includes("SELECT id FROM public.favorites")) {
        return { rows: favoriteExists ? [{ id: "fav-existing" }] : [], rowCount: favoriteExists ? 1 : 0 };
      }
      return { rows: [], rowCount: 0 };
    },
    async connect() {
      return {
        async query(sql, params) {
          dataQueries.push({ sql, params, tx: true });
          if (sql.includes("SELECT id FROM public.favorites")) {
            return { rows: favoriteExists ? [{ id: "fav-existing" }] : [], rowCount: favoriteExists ? 1 : 0 };
          }
          return { rows: [], rowCount: 0 };
        },
        release() {},
      };
    },
  };
}

async function withFavoritesServer(database, callback) {
  const app = express();
  app.use(express.json());
  const authenticate = createAuthenticateBackendIndependent({ database });
  // Real router, injected backend-independent auth (target contract) + injected mock DB.
  const router = createFavoritesRouter({ database, authenticate });
  app.use("/api/favorites", router);
  const server = app.listen(0, "127.0.0.1");
  await once(server, "listening");
  const { port } = server.address();
  try {
    await callback(`http://127.0.0.1:${port}`);
  } finally {
    await new Promise((resolve, reject) =>
      server.close((e) => (e ? reject(e) : resolve()))
    );
  }
}

async function reqJson(base, method, path, { token, body } = {}) {
  const headers = { "content-type": "application/json" };
  if (token !== undefined) headers.authorization = `Bearer ${token}`;
  const res = await fetch(`${base}${path}`, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  let json = null;
  try {
    json = await res.json();
  } catch {}
  return { res, json };
}

test("G10.16 favorites GET: valid backend JWT + valid session returns user data", async () => {
  const sessionQueries = [];
  const dataQueries = [];
  const db = makeDb({ sessionQueries, dataQueries });
  await withFavoritesServer(db, async (base) => {
    const token = await signBackendAccessToken();
    const { res, json } = await reqJson(base, "GET", "/api/favorites", { token });
    assert.equal(res.status, 200);
    assert.equal(json.success, true);
    assert.equal(Array.isArray(json.data), true);
    assert.equal(json.data[0].user_id, userId);
  });
  assert.ok(sessionQueries.some((q) => q.params?.[0] === sessionId && q.params?.[1] === userId));
  const read = dataQueries.find((q) => q.sql.includes("ORDER BY created_at DESC"));
  assert.ok(read);
  assert.deepEqual(read.params, [userId]);
});

test("G10.16 favorites GET: missing token -> 401", async () => {
  const sessionQueries = [];
  const dataQueries = [];
  await withFavoritesServer(makeDb({ sessionQueries, dataQueries }), async (base) => {
    const { res, json } = await reqJson(base, "GET", "/api/favorites");
    assert.equal(res.status, 401);
    assert.equal(json.error, "Authentication token required");
  });
  assert.equal(sessionQueries.length, 0);
  assert.equal(dataQueries.length, 0);
});

test("G10.16 favorites GET: Supabase-like JWT rejected, no fallback, no session lookup", async () => {
  const sessionQueries = [];
  const dataQueries = [];
  await withFavoritesServer(makeDb({ sessionQueries, dataQueries }), async (base) => {
    const { res, json } = await reqJson(base, "GET", "/api/favorites", {
      token: await signSupabaseLikeJwt(),
    });
    assert.equal(res.status, 401);
    assert.ok(
      json.error === "Invalid or expired authentication token" ||
        json.error === "Session is invalid or revoked"
    );
  });
  assert.equal(sessionQueries.length, 0);
  assert.equal(dataQueries.length, 0);
});

for (const [name, opts] of [
  ["wrong signature", { key: "x".repeat(64) }],
  ["wrong issuer", { iss: "https://example.supabase.co/auth/v1" }],
  ["wrong audience", { aud: "anon" }],
  ["disallowed algorithm", { alg: "HS384" }],
  ["expired JWT", { expSec: -60 }],
]) {
  test(`G10.16 favorites GET: ${name} -> 401, no session lookup`, async () => {
    const sessionQueries = [];
    const dataQueries = [];
    await withFavoritesServer(makeDb({ sessionQueries, dataQueries }), async (base) => {
      const { res, json } = await reqJson(base, "GET", "/api/favorites", {
        token: await signBackendAccessToken(opts),
      });
      assert.equal(res.status, 401);
      assert.equal(json.error, "Invalid or expired authentication token");
    });
    assert.equal(sessionQueries.length, 0);
    assert.equal(dataQueries.length, 0);
  });

  test(`G10.16 favorites PUT: ${name} -> 401, no session/data lookup`, async () => {
    const sessionQueries = [];
    const dataQueries = [];
    await withFavoritesServer(makeDb({ sessionQueries, dataQueries }), async (base) => {
      const { res } = await reqJson(base, "PUT", `/api/favorites/${carId}`, {
        token: await signBackendAccessToken(opts),
        body: { favorite: true, user_id: otherUserId },
      });
      assert.equal(res.status, 401);
    });
    assert.equal(sessionQueries.length, 0);
    assert.equal(dataQueries.length, 0);
  });
}

test("G10.16 favorites GET: invalid/revoked session -> 401 after session lookup", async () => {
  const sessionQueries = [];
  await withFavoritesServer(
    makeDb({ sessionRow: null, sessionQueries }),
    async (base) => {
      const { res, json } = await reqJson(base, "GET", "/api/favorites", {
        token: await signBackendAccessToken(),
      });
      assert.equal(res.status, 401);
      // createAuthenticateBackendIndependent (real middleware, target contract)
      // returns this message for invalid/expired tokens and invalid/revoked sessions.
      assert.equal(json.error, "Invalid or expired authentication token");
    }
  );
  assert.ok(sessionQueries.length >= 1);
});

test("G10.16 favorites PUT: valid backend JWT inserts with req.user.id only (ignores client user_id)", async () => {
  const sessionQueries = [];
  const dataQueries = [];
  await withFavoritesServer(makeDb({ sessionQueries, dataQueries }), async (base) => {
    const { res, json } = await reqJson(base, "PUT", `/api/favorites/${carId}`, {
      token: await signBackendAccessToken(),
      body: { favorite: true, user_id: otherUserId, item_id: otherUserId },
    });
    assert.equal(res.status, 200);
    assert.deepEqual(json, { success: true, car_id: carId, favorite: true });
  });
  assert.ok(sessionQueries.length >= 1);
  const insert = dataQueries.find((q) => q.sql.includes("INSERT INTO public.favorites"));
  assert.ok(insert, "expected insert after backend-independent auth");
  assert.equal(insert.params[0], userId);
  assert.equal(insert.params[1], carId);
  assert.equal(insert.params.includes(otherUserId), false);
});

test("G10.16 favorites PUT: missing token -> 401, no data mutation", async () => {
  const dataQueries = [];
  await withFavoritesServer(makeDb({ dataQueries }), async (base) => {
    const { res } = await reqJson(base, "PUT", `/api/favorites/${carId}`, {
      body: { favorite: true },
    });
    assert.equal(res.status, 401);
  });
  assert.equal(dataQueries.length, 0);
});

test("G10.16 favorites PUT: Supabase-like JWT rejected, no fallback, no mutation", async () => {
  const sessionQueries = [];
  const dataQueries = [];
  await withFavoritesServer(makeDb({ sessionQueries, dataQueries }), async (base) => {
    const { res } = await reqJson(base, "PUT", `/api/favorites/${carId}`, {
      token: await signSupabaseLikeJwt(),
      body: { favorite: true, user_id: otherUserId },
    });
    assert.equal(res.status, 401);
  });
  assert.equal(sessionQueries.length, 0);
  assert.equal(dataQueries.length, 0);
});

test("G10.16 favorites PUT: invalid/revoked session -> 401, no mutation", async () => {
  const sessionQueries = [];
  const dataQueries = [];
  await withFavoritesServer(
    makeDb({ sessionRow: null, sessionQueries, dataQueries }),
    async (base) => {
      const { res, json } = await reqJson(base, "PUT", `/api/favorites/${carId}`, {
        token: await signBackendAccessToken(),
        body: { favorite: true },
      });
      assert.equal(res.status, 401);
      assert.equal(json.error, "Invalid or expired authentication token");
    }
  );
  assert.ok(sessionQueries.length >= 1);
  assert.equal(
    dataQueries.filter((q) => q.sql.includes("INSERT") || q.sql.includes("DELETE")).length,
    0
  );
});

test("G10.17 production router default: uses backend-independent auth (rejects Supabase-like JWT, no fallback, no DB data)", async () => {
  // Mount createFavoritesRouter() with DEFAULT auth (production path after G10.17).
  // Supabase-like JWT must be rejected by backend-independent verification before any
  // session/data DB lookup; proves no Supabase fallback on the default router.
  const sessionQueries = [];
  const dataQueries = [];
  const app = express();
  app.use(express.json());
  app.use("/api/favorites", createFavoritesRouter({ database: makeDb({ sessionQueries, dataQueries }) }));
  const server = app.listen(0, "127.0.0.1");
  await once(server, "listening");
  const { port } = server.address();
  try {
    const { res } = await reqJson(`http://127.0.0.1:${port}`, "GET", "/api/favorites", {
      token: await signSupabaseLikeJwt(),
    });
    assert.equal(res.status, 401);
  } finally {
    await new Promise((resolve, reject) => server.close((e) => (e ? reject(e) : resolve())));
  }
  assert.equal(dataQueries.length, 0);
});

test("G10.17 production router: real router + real backend-independent middleware accepts valid backend JWT (mock DB)", async () => {
  // Proves the real createFavoritesRouter works with the real backend-only middleware
  // (the production auth contract). The fully-default exported auth constant is bound
  // to the process pool at module load; this isolated test injects mock DB into the
  // same real factory to avoid real DB/network while exercising the real stack.
  const db = makeDb();
  const app = express();
  app.use(express.json());
  app.use(
    "/api/favorites",
    createFavoritesRouter({
      database: db,
      authenticate: createAuthenticateBackendIndependent({ database: db }),
    })
  );
  const server = app.listen(0, "127.0.0.1");
  await once(server, "listening");
  const { port } = server.address();
  try {
    const { res, json } = await reqJson(`http://127.0.0.1:${port}`, "GET", "/api/favorites", {
      token: await signBackendAccessToken(),
    });
    assert.equal(res.status, 200);
    assert.equal(json.success, true);
  } finally {
    await new Promise((resolve, reject) => server.close((e) => (e ? reject(e) : resolve())));
  }
});

test("G10.16 favorites GET: identity scoped to req.user.id only", async () => {
  const dataQueries = [];
  await withFavoritesServer(makeDb({ dataQueries }), async (base) => {
    const { res } = await reqJson(base, "GET", `/api/favorites?user_id=${otherUserId}`, {
      token: await signBackendAccessToken(),
    });
    assert.equal(res.status, 200);
  });
  const read = dataQueries.find((q) => q.sql.includes("ORDER BY created_at DESC"));
  assert.ok(read);
  assert.deepEqual(read.params, [userId]);
  assert.equal(read.params.includes(otherUserId), false);
});
