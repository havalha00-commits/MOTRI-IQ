import assert from "node:assert/strict";
import test from "node:test";
import { SignJWT } from "jose";
import { createCurrentUserAuthenticator } from "../middleware/current_user.js";

function mockRes() {
  const res = { statusCode: 200, body: null, headers: {} };
  res.status = (c) => { res.statusCode = c; return res; };
  res.json = (b) => { res.body = b; return res; };
  res.setHeader = (k, v) => { res.headers[k.toLowerCase()] = v; return res; };
  return res;
}
function run(mw, req) {
  return new Promise((resolve) => {
    const res = mockRes();
    mw(req, res, () => resolve({ next: true, req, res }));
    setTimeout(() => resolve({ next: false, req, res }), 200);
  });
}
async function foreignJwt() {
  const other = new TextEncoder().encode("x".repeat(64));
  return await new SignJWT({ sub: "u", role: "authenticated" })
    .setProtectedHeader({ alg: "HS256" })
    .setIssuer("https://foreign.example/auth/v1")
    .setAudience("authenticated")
    .setExpirationTime("1h")
    .sign(other);
}

test("M1E-ISOLATION current_user: disableSupabaseFallback=true rejects non-independent token without any fetch/fallback", async () => {
  let fetchCalls = 0;
  const fetchImpl = async () => { fetchCalls += 1; throw new Error("fetch must not be called in local test isolation"); };
  const mw = createCurrentUserAuthenticator({
    database: { query: async () => ({ rows: [] }) }, // verifyIndependentSession will not DB-hit for invalid/foreign token shape/signature
    supabaseUrl: "https://production.example",
    publishableKey: "publishable-placeholder",
    fetchImpl,
    disableSupabaseFallback: true,
  });
  const token = await foreignJwt();
  const out = await run(mw, { headers: { authorization: `Bearer ${token}` } });
  assert.equal(out.next, false);
  assert.equal(out.res.statusCode, 401);
  assert.equal(fetchCalls, 0, "Supabase fetch fallback must not run when disableSupabaseFallback=true");
});

test("M1E-ISOLATION current_user: disableSupabaseFallback=true does not use Supabase even when env/config present (missing bearer -> 401, no fetch)", async () => {
  let fetchCalls = 0;
  const mw = createCurrentUserAuthenticator({
    database: { query: async () => ({ rows: [] }) },
    supabaseUrl: "https://production.example",
    publishableKey: "publishable-placeholder",
    fetchImpl: async () => { fetchCalls += 1; return { ok: false, status: 401 }; },
    disableSupabaseFallback: true,
  });
  const out = await run(mw, { headers: {} });
  assert.equal(out.next, false);
  assert.equal(out.res.statusCode, 401);
  assert.equal(fetchCalls, 0);
});

test("M1E-ISOLATION current_user: outside isolation (disableSupabaseFallback=false) preserves Supabase fallback path for non-independent token", async () => {
  let fetchCalls = 0;
  const fetchImpl = async (url) => {
    fetchCalls += 1;
    assert.ok(String(url).includes("/auth/v1/user"), "must call Supabase user verification endpoint in legacy fallback mode");
    return { ok: false, status: 401, json: async () => ({}) };
  };
  const mw = createCurrentUserAuthenticator({
    database: { query: async () => ({ rows: [] }) },
    supabaseUrl: "https://supabase.example",
    publishableKey: "publishable-placeholder",
    fetchImpl,
    disableSupabaseFallback: false,
  });
  const token = await foreignJwt();
  const out = await run(mw, { headers: { authorization: `Bearer ${token}` } });
  assert.equal(out.next, false);
  assert.equal(out.res.statusCode, 401);
  assert.equal(fetchCalls, 1, "legacy behavior preserved outside isolation");
});
