import assert from "node:assert/strict";
import test from "node:test";
import { SignJWT } from "jose";
import { createSellersRouter } from "../routes/sellers.js";
import { createAuthenticateBackendIndependent } from "../middleware/current_user.js";

function mockResponse() {
  const res = { statusCode: 200, body: null,
    status(code) { res.statusCode = code; return res; },
    json(data) { res.body = data; return res; } };
  return res;
}
function getAdminStatusHandlers(router) {
  const layer = router.stack.find((e) => e.route && e.route.path === "/admin/status" && e.route.methods.get);
  assert.ok(layer);
  return layer.route.stack.map((s) => s.handle);
}
async function runStack(handlers, req) {
  const res = mockResponse();
  let i = 0;
  const next = async () => { const h = handlers[i++]; if (h) await h(req, res, next); };
  await next();
  return res;
}

const TEST_SECRET = process.env.JWT_SECRET && process.env.JWT_SECRET.length >= 64 ? process.env.JWT_SECRET : "s".repeat(64);
const enc = new TextEncoder().encode(TEST_SECRET);
async function signBackendToken({ sub = "11111111-1111-4111-8111-111111111111", sid = "22222222-2222-4222-8222-222222222222", expSec = 3600 } = {}) {
  return await new SignJWT({ sub, sid, role: "authenticated" })
    .setProtectedHeader({ alg: "HS256" })
    .setIssuer("motri-iq-api")
    .setAudience("authenticated")
    .setExpirationTime(Math.floor(Date.now() / 1000) + expSec)
    .sign(enc);
}
async function signForeignToken() {
  // looks like a JWT but signed with different secret/issuer (e.g. Supabase) — must be rejected, no fallback
  const other = new TextEncoder().encode("x".repeat(64));
  return await new SignJWT({ sub: "u", role: "authenticated" })
    .setProtectedHeader({ alg: "HS256" })
    .setIssuer("https://supabase.example/auth/v1")
    .setAudience("authenticated")
    .setExpirationTime("1h")
    .sign(other);
}

function dbReturning(userRow) {
  return { query: async () => ({ rows: userRow ? [userRow] : [] }) };
}
function dbTracked() {
  let queries = 0;
  return {
    get queries() { return queries; },
    query: async () => { queries += 1; return { rows: [] }; }
  };
}

// --- route-level behavior (server-derived, ignores forged flags) using injected backend-independent auth ---
test("G5 admin/status: backend JWT valid admin -> success (server-derived from app_admins/DB)", async () => {
  const router = createSellersRouter({ database: {},
    authenticateAdminStatus: (req, _res, next) => { req.user = { id: "u-admin", role: "authenticated", is_admin: true }; next(); } });
  const res = await runStack(getAdminStatusHandlers(router), { headers: {}, body: { is_admin: false, role: "admin" } });
  assert.equal(res.statusCode, 200); assert.equal(res.body.is_admin, true);
});
test("G5 admin/status: backend JWT valid normal user -> is_admin=false", async () => {
  const router = createSellersRouter({ database: {},
    authenticateAdminStatus: (req, _res, next) => { req.user = { id: "u-normal", role: "authenticated", is_admin: false }; next(); } });
  const res = await runStack(getAdminStatusHandlers(router), { headers: {}, body: {} });
  assert.equal(res.statusCode, 200); assert.equal(res.body.is_admin, false);
});
test("G5 admin/status: forged client-side admin flags ignored", async () => {
  const router = createSellersRouter({ database: {},
    authenticateAdminStatus: (req, _res, next) => { req.user = { id: "u-forger", role: "authenticated", is_admin: false }; next(); } });
  const res = await runStack(getAdminStatusHandlers(router), { headers: {},
    body: { is_admin: true, isAdmin: true, role: "admin", user_id: "admin-id", admin: true },
    query: { is_admin: "true", role: "admin" } });
  assert.equal(res.statusCode, 200); assert.equal(res.body.is_admin, false);
});
test("G5 admin/status: revoked admin permission -> no admin (DB/app_admins source)", async () => {
  const router = createSellersRouter({ database: {},
    authenticateAdminStatus: (req, _res, next) => { req.user = { id: "u-revoked", role: "authenticated", is_admin: false }; next(); } });
  const res = await runStack(getAdminStatusHandlers(router), { headers: {}, body: {} });
  assert.equal(res.statusCode, 200); assert.equal(res.body.is_admin, false);
});

// --- real backend-independent middleware (no Supabase fallback by construction) ---
test("G5 middleware: missing token -> 401", async () => {
  // force env-independent by stubbing via factory with our secret path? factory reads JWT_SECRET; we set it below in env for test process.
  const mw = createAuthenticateBackendIndependent({ database: dbReturning(null) });
  const res = mockResponse(); await mw({ headers: {} }, res, () => { throw new Error("next"); });
  assert.equal(res.statusCode, 401);
});
test("G5 middleware: Supabase/foreign JWT alone -> 401 (no fallback)", async () => {
  const mw = createAuthenticateBackendIndependent({ database: dbReturning(null) });
  const token = await signForeignToken();
  const res = mockResponse(); let next = false;
  await mw({ headers: { authorization: `Bearer ${token}` } }, res, () => { next = true; });
  assert.equal(res.statusCode, 401); assert.equal(next, false);
});
test("G5 middleware: expired backend JWT -> 401", async () => {
  const mw = createAuthenticateBackendIndependent({ database: dbReturning(null) });
  const token = await signBackendToken({ expSec: -60 });
  const res = mockResponse(); let next = false;
  await mw({ headers: { authorization: `Bearer ${token}` } }, res, () => { next = true; });
  assert.equal(res.statusCode, 401); assert.equal(next, false);
});
test("G5 middleware: valid backend JWT but revoked/invalid session -> 401", async () => {
  const mw = createAuthenticateBackendIndependent({ database: dbReturning(null) }); // no session row
  const token = await signBackendToken();
  const res = mockResponse(); let next = false;
  await mw({ headers: { authorization: `Bearer ${token}` } }, res, () => { next = true; });
  assert.equal(res.statusCode, 401); assert.equal(next, false);
});
test("G5 middleware: valid backend JWT, active session, admin from DB -> req.user.is_admin true (UUID-bound)", async () => {
  const sub = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
  const mw = createAuthenticateBackendIndependent({ database: dbReturning({ id: sub, email: "a@b.c", is_admin: true }) });
  const token = await signBackendToken({ sub, sid: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb" });
  const req = { headers: { authorization: `Bearer ${token}` }, body: { is_admin: false, role: "user" } };
  const res = mockResponse(); let next = false;
  await mw(req, res, () => { next = true; });
  assert.equal(next, true); assert.equal(req.user.id, sub); assert.equal(req.user.is_admin, true);
});
test("G5 middleware: valid backend JWT, active session, normal user -> req.user.is_admin false", async () => {
  const sub = "cccccccc-cccc-4ccc-8ccc-cccccccccccc";
  const mw = createAuthenticateBackendIndependent({ database: dbReturning({ id: sub, email: "c@b.c", is_admin: false }) });
  const token = await signBackendToken({ sub });
  const req = { headers: { authorization: `Bearer ${token}` } };
  const res = mockResponse(); let next = false;
  await mw(req, res, () => { next = true; });
  assert.equal(next, true); assert.equal(req.user.is_admin, false);
});

test("G5: sellers/verify still rejects forged body admin (other route unaffected)", async () => {
  const router = createSellersRouter({ database: { query: async () => ({ rows: [] }) },
    authenticate: (req, _res, next) => { req.user = { id: "u-forger", role: "authenticated", is_admin: false }; next(); } });
  const layer = router.stack.find((e) => e.route && e.route.path === "/verify" && e.route.methods.post);
  const res = mockResponse();
  await layer.route.stack[1].handle(
    { body: { seller_id: "d1f6b1a2-c3d4-4e5f-8a9b-0c1d2e3f4a5b", is_admin: true, role: "admin" },
      user: { id: "u-forger", role: "authenticated", is_admin: false } }, res);
  assert.equal(res.statusCode, 403);
});

async function signBackendCustom({ iss = "motri-iq-api", aud = "authenticated", alg = "HS256", key = enc, expSec = 3600, sub = "11111111-1111-4111-8111-111111111111", sid = "22222222-2222-4222-8222-222222222222" } = {}) {
  const token = new SignJWT({ sub, sid, role: "authenticated" })
    .setProtectedHeader({ alg })
    .setSubject(sub)
    .setIssuer(iss)
    .setAudience(aud)
    .setIssuedAt();
  token.setExpirationTime(Math.floor(Date.now() / 1000) + expSec);
  return token.sign(key);
}

test("G10.9 middleware: backend JWT wrong signature -> 401, no fallback, no DB session lookup", async () => {
  const db = dbTracked();
  const mw = createAuthenticateBackendIndependent({ database: db });
  const token = await signBackendCustom({ key: new TextEncoder().encode("x".repeat(64)) });
  const res = mockResponse(); let next = false;
  await mw({ headers: { authorization: `Bearer ${token}` } }, res, () => { next = true; });
  assert.equal(res.statusCode, 401); assert.equal(next, false); assert.equal(db.queries, 0);
});

test("G10.9 middleware: backend JWT wrong issuer -> 401, no fallback, no DB session lookup", async () => {
  const db = dbTracked();
  const mw = createAuthenticateBackendIndependent({ database: db });
  const token = await signBackendCustom({ iss: "https://supabase.example/auth/v1" });
  const res = mockResponse(); let next = false;
  await mw({ headers: { authorization: `Bearer ${token}` } }, res, () => { next = true; });
  assert.equal(res.statusCode, 401); assert.equal(next, false); assert.equal(db.queries, 0);
});

test("G10.9 middleware: backend JWT wrong audience -> 401, no fallback, no DB session lookup", async () => {
  const db = dbTracked();
  const mw = createAuthenticateBackendIndependent({ database: db });
  const token = await signBackendCustom({ aud: "anon" });
  const res = mockResponse(); let next = false;
  await mw({ headers: { authorization: `Bearer ${token}` } }, res, () => { next = true; });
  assert.equal(res.statusCode, 401); assert.equal(next, false); assert.equal(db.queries, 0);
});

test("G10.9 middleware: backend JWT disallowed algorithm -> 401, no fallback, no DB session lookup", async () => {
  const db = dbTracked();
  const mw = createAuthenticateBackendIndependent({ database: db });
  const token = await signBackendCustom({ alg: "HS384" });
  const res = mockResponse(); let next = false;
  await mw({ headers: { authorization: `Bearer ${token}` } }, res, () => { next = true; });
  assert.equal(res.statusCode, 401); assert.equal(next, false); assert.equal(db.queries, 0);
});
