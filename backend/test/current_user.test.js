import assert from "node:assert/strict";
import test from "node:test";
import { createCurrentUserAuthenticator } from "../middleware/current_user.js";

const userId = "d1f6b1a2-c3d4-4e5f-8a9b-0c1d2e3f4a5b";

function mockResponse() {
  const res = {
    statusCode: 200,
    body: null,
    status(code) {
      res.statusCode = code;
      return res;
    },
    json(data) {
      res.body = data;
      return res;
    }
  };
  return res;
}

function mockFetch(userData, { status = 200 } = {}) {
  return async (url, options) => {
    assert.match(url, /\/auth\/v1\/user$/);
    assert.equal(options.headers.authorization, "Bearer test-access-token");
    if (status !== 200) {
      return new Response(JSON.stringify({ error: "Invalid session" }), { status });
    }
    return new Response(JSON.stringify(userData), { status: 200 });
  };
}

test("current_user: old user present in app_users", async () => {
  let executedQuery = null;
  const authenticate = createCurrentUserAuthenticator({
    database: {
      async query(sql, values) {
        executedQuery = { sql, values };
        return {
          rows: [
            {
              id: userId,
              email: "old_user@example.test",
              is_admin: false,
              is_deleted: false,
              is_banned: false
            }
          ]
        };
      }
    },
    supabaseUrl: "https://example.supabase.co",
    publishableKey: "test-anon-key",
    fetchImpl: mockFetch({ id: userId, email: "old_user@example.test" })
  });

  const req = { headers: { authorization: "Bearer test-access-token" } };
  const res = mockResponse();
  let nextCalled = false;

  await authenticate(req, res, () => {
    nextCalled = true;
  });

  assert.equal(nextCalled, true);
  assert.equal(req.user.id, userId);
  assert.equal(req.user.email, "old_user@example.test");
  assert.equal(req.user.role, "authenticated");
  assert.equal(req.user.is_admin, false);
  assert.equal(executedQuery.values[0], userId);
});

test("current_user: new user not in app_users but has profile", async () => {
  const newUserId = "a2f6b1a2-c3d4-4e5f-8a9b-0c1d2e3f4a5b";
  const authenticate = createCurrentUserAuthenticator({
    database: {
      async query(sql, values) {
        return {
          rows: [
            {
              id: newUserId,
              email: "new_user@example.test",
              is_admin: false,
              is_deleted: false,
              is_banned: false
            }
          ]
        };
      }
    },
    supabaseUrl: "https://example.supabase.co",
    publishableKey: "test-anon-key",
    fetchImpl: mockFetch({ id: newUserId, email: "new_user@example.test" })
  });

  const req = { headers: { authorization: "Bearer test-access-token" } };
  const res = mockResponse();
  let nextCalled = false;

  await authenticate(req, res, () => {
    nextCalled = true;
  });

  assert.equal(nextCalled, true);
  assert.equal(req.user.id, newUserId);
  assert.equal(req.user.email, "new_user@example.test");
  assert.equal(req.user.is_admin, false);
});

test("current_user: verified user with no profile", async () => {
  const noProfileId = "b3f6b1a2-c3d4-4e5f-8a9b-0c1d2e3f4a5b";
  const authenticate = createCurrentUserAuthenticator({
    database: {
      async query(sql, values) {
        return {
          rows: [
            {
              id: noProfileId,
              email: "noprofile@example.test",
              is_admin: false,
              is_deleted: false,
              is_banned: false
            }
          ]
        };
      }
    },
    supabaseUrl: "https://example.supabase.co",
    publishableKey: "test-anon-key",
    fetchImpl: mockFetch({ id: noProfileId, email: "noprofile@example.test" })
  });

  const req = { headers: { authorization: "Bearer test-access-token" } };
  const res = mockResponse();
  let nextCalled = false;

  await authenticate(req, res, () => {
    nextCalled = true;
  });

  assert.equal(nextCalled, true);
  assert.equal(req.user.id, noProfileId);
  assert.equal(req.user.email, "noprofile@example.test");
  assert.equal(req.user.is_admin, false);
});

test("current_user: banned user in database rejected", async () => {
  const authenticate = createCurrentUserAuthenticator({
    database: {
      async query() {
        return {
          rows: [
            {
              id: userId,
              email: "banned@example.test",
              is_admin: false,
              is_deleted: false,
              is_banned: true
            }
          ]
        };
      }
    },
    supabaseUrl: "https://example.supabase.co",
    publishableKey: "test-anon-key",
    fetchImpl: mockFetch({ id: userId, email: "banned@example.test" })
  });

  const req = { headers: { authorization: "Bearer test-access-token" } };
  const res = mockResponse();
  let nextCalled = false;

  await authenticate(req, res, () => {
    nextCalled = true;
  });

  assert.equal(nextCalled, false);
  assert.equal(res.statusCode, 401);
  assert.equal(res.body.error, "Account is unavailable");
});

test("current_user: banned user at provider level rejected without query bypass", async () => {
  let dbQueried = false;
  const futureBan = new Date(Date.now() + 86400000).toISOString();
  const authenticate = createCurrentUserAuthenticator({
    database: {
      async query() {
        dbQueried = true;
        return { rows: [] };
      }
    },
    supabaseUrl: "https://example.supabase.co",
    publishableKey: "test-anon-key",
    fetchImpl: mockFetch({
      id: userId,
      email: "banned_provider@example.test",
      banned_until: futureBan
    })
  });

  const req = { headers: { authorization: "Bearer test-access-token" } };
  const res = mockResponse();
  let nextCalled = false;

  await authenticate(req, res, () => {
    nextCalled = true;
  });

  assert.equal(nextCalled, false);
  assert.equal(dbQueried, false, "Database query must not be reached for provider-banned accounts");
  assert.equal(res.statusCode, 401);
  assert.equal(res.body.error, "Account is unavailable");
});

test("current_user: deleted user in database rejected", async () => {
  const authenticate = createCurrentUserAuthenticator({
    database: {
      async query() {
        return {
          rows: [
            {
              id: userId,
              email: "deleted@example.test",
              is_admin: false,
              is_deleted: true,
              is_banned: false
            }
          ]
        };
      }
    },
    supabaseUrl: "https://example.supabase.co",
    publishableKey: "test-anon-key",
    fetchImpl: mockFetch({ id: userId, email: "deleted@example.test" })
  });

  const req = { headers: { authorization: "Bearer test-access-token" } };
  const res = mockResponse();
  let nextCalled = false;

  await authenticate(req, res, () => {
    nextCalled = true;
  });

  assert.equal(nextCalled, false);
  assert.equal(res.statusCode, 401);
  assert.equal(res.body.error, "Account is unavailable");
});

test("current_user: deleted user at provider level rejected without query bypass", async () => {
  let dbQueried = false;
  const authenticate = createCurrentUserAuthenticator({
    database: {
      async query() {
        dbQueried = true;
        return { rows: [] };
      }
    },
    supabaseUrl: "https://example.supabase.co",
    publishableKey: "test-anon-key",
    fetchImpl: mockFetch({
      id: userId,
      email: "deleted_provider@example.test",
      deleted_at: new Date().toISOString()
    })
  });

  const req = { headers: { authorization: "Bearer test-access-token" } };
  const res = mockResponse();
  let nextCalled = false;

  await authenticate(req, res, () => {
    nextCalled = true;
  });

  assert.equal(nextCalled, false);
  assert.equal(dbQueried, false, "Database query must not be reached for provider-deleted accounts");
  assert.equal(res.statusCode, 401);
  assert.equal(res.body.error, "Account is unavailable");
});

test("current_user: admin privilege is read correctly (admin vs non-admin)", async () => {
  // 1. Admin user
  const adminAuth = createCurrentUserAuthenticator({
    database: {
      async query() {
        return {
          rows: [
            {
              id: userId,
              email: "admin@example.test",
              is_admin: true,
              is_deleted: false,
              is_banned: false
            }
          ]
        };
      }
    },
    supabaseUrl: "https://example.supabase.co",
    publishableKey: "test-anon-key",
    fetchImpl: mockFetch({ id: userId, email: "admin@example.test" })
  });

  const adminReq = { headers: { authorization: "Bearer test-access-token" } };
  const adminRes = mockResponse();
  let adminNextCalled = false;
  await adminAuth(adminReq, adminRes, () => {
    adminNextCalled = true;
  });

  assert.equal(adminNextCalled, true);
  assert.equal(adminReq.user.is_admin, true);

  // 2. Non-admin user
  const nonAdminAuth = createCurrentUserAuthenticator({
    database: {
      async query() {
        return {
          rows: [
            {
              id: userId,
              email: "regular@example.test",
              is_admin: false,
              is_deleted: false,
              is_banned: false
            }
          ]
        };
      }
    },
    supabaseUrl: "https://example.supabase.co",
    publishableKey: "test-anon-key",
    fetchImpl: mockFetch({ id: userId, email: "regular@example.test" })
  });

  const nonAdminReq = { headers: { authorization: "Bearer test-access-token" } };
  const nonAdminRes = mockResponse();
  let nonAdminNextCalled = false;
  await nonAdminAuth(nonAdminReq, nonAdminRes, () => {
    nonAdminNextCalled = true;
  });

  assert.equal(nonAdminNextCalled, true);
  assert.equal(nonAdminReq.user.is_admin, false);
});

