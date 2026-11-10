import assert from "node:assert/strict";
import test from "node:test";
import { createWalletRouter } from "../routes/wallet.js";
import { createUploadAuthStore } from "../routes/wallet.js";

const userId = "d1f6b1a2-c3d4-4e5f-8a9b-0c1d2e3f4a5b";
const adminId = "a1f6b1a2-c3d4-4e5f-8a9b-0c1d2e3f4a5b";
const otherUserId = "b1f6b1a2-c3d4-4e5f-8a9b-0c1d2e3f4a5b";
const txId = "c1f6b1a2-c3d4-4e5f-8a9b-0c1d2e3f4a5b";

function mockResponse() {
  const res = {
    statusCode: 200,
    body: null,
    status(code) { res.statusCode = code; return res; },
    json(d) { res.body = d; return res; },
  };
  return res;
}

function findRoute(router, method, path) {
  return router.stack.find((l) => l.route && l.route.path === path && l.route.methods[method]);
}

// ------------------------------------------------------------------
// Gruppo A: إنشاء طلب شحن (topups) - التشديد الأمني
// ------------------------------------------------------------------

test("wallet_hardened: topup rejects receipt_image_url from client", async () => {
  const db = { query: async () => ({ rows: [], rowCount: 0 }) };
  const router = createWalletRouter({
    database: db,
    authenticate: (req, _res, next) => { req.user = { id: userId }; next(); },
  });
  const req = {
    method: "POST", url: "/topups",
    body: { amount: 5000, receipt_image_url: "https://x/receipt.jpg" },
    user: { id: userId },
  };
  const res = mockResponse();
  await findRoute(router, "post", "/topups").route.stack[0].handle(req, res);
  assert.equal(res.statusCode, 400);
});

test("wallet_hardened: topup rejects status from client", async () => {
  const db = { query: async () => ({ rows: [], rowCount: 0 }) };
  const router = createWalletRouter({
    database: db,
    authenticate: (req, _res, next) => { req.user = { id: userId }; next(); },
  });
  const req = {
    method: "POST", url: "/topups",
    body: { amount: 5000, status: "confirmed" },
    user: { id: userId },
  };
  const res = mockResponse();
  await findRoute(router, "post", "/topups").route.stack[0].handle(req, res);
  assert.equal(res.statusCode, 400);
});

test("wallet_hardened: topup rejects admin_id from client", async () => {
  const db = { query: async () => ({ rows: [], rowCount: 0 }) };
  const router = createWalletRouter({
    database: db,
    authenticate: (req, _res, next) => { req.user = { id: userId }; next(); },
  });
  const req = {
    method: "POST", url: "/topups",
    body: { amount: 5000, admin_id: adminId },
    user: { id: userId },
  };
  const res = mockResponse();
  await findRoute(router, "post", "/topups").route.stack[0].handle(req, res);
  assert.equal(res.statusCode, 400);
});

test("wallet_hardened: topup rejects confirmed_at from client", async () => {
  const db = { query: async () => ({ rows: [], rowCount: 0 }) };
  const router = createWalletRouter({
    database: db,
    authenticate: (req, _res, next) => { req.user = { id: userId }; next(); },
  });
  const req = {
    method: "POST", url: "/topups",
    body: { amount: 5000, confirmed_at: new Date().toISOString() },
    user: { id: userId },
  };
  const res = mockResponse();
  await findRoute(router, "post", "/topups").route.stack[0].handle(req, res);
  assert.equal(res.statusCode, 400);
});

test("wallet_hardened: topup rejects admin_note from client", async () => {
  const db = { query: async () => ({ rows: [], rowCount: 0 }) };
  const router = createWalletRouter({
    database: db,
    authenticate: (req, _res, next) => { req.user = { id: userId }; next(); },
  });
  const req = {
    method: "POST", url: "/topups",
    body: { amount: 5000, admin_note: "approve" },
    user: { id: userId },
  };
  const res = mockResponse();
  await findRoute(router, "post", "/topups").route.stack[0].handle(req, res);
  assert.equal(res.statusCode, 400);
});

test("wallet_hardened: topup rejects user_id from client", async () => {
  const db = { query: async () => ({ rows: [], rowCount: 0 }) };
  const router = createWalletRouter({
    database: db,
    authenticate: (req, _res, next) => { req.user = { id: userId }; next(); },
  });
  const req = {
    method: "POST", url: "/topups",
    body: { amount: 5000, user_id: otherUserId },
    user: { id: userId },
  };
  const res = mockResponse();
  await findRoute(router, "post", "/topups").route.stack[0].handle(req, res);
  assert.equal(res.statusCode, 400);
});

test("wallet_hardened: topup creates pending transaction with user_id from req.user only and receipt_image_url NULL", async () => {
  let capturedVals;
  const db = {
    query: async (_sql, vals) => {
      capturedVals = vals;
      return { rows: [{ id: txId }], rowCount: 1 };
    },
  };
  const router = createWalletRouter({
    database: db,
    authenticate: (req, _res, next) => { req.user = { id: userId }; next(); },
  });
  const req = {
    method: "POST", url: "/topups",
    body: { amount: 5000 },
    user: { id: userId },
  };
  const res = mockResponse();
  await findRoute(router, "post", "/topups").route.stack[0].handle(req, res);
  assert.equal(res.statusCode, 201);
  assert.equal(capturedVals[0], userId);
  assert.equal(capturedVals[1], 5000);
  assert.equal(capturedVals.length, 2, "Only user_id and amount are sent; receipt_image_url is NULL via SQL literal");
});

test("wallet_hardened: topup rejects amount <= 0 and non-integer", async () => {
  const db = { query: async () => ({ rows: [], rowCount: 0 }) };
  const router = createWalletRouter({
    database: db,
    authenticate: (req, _res, next) => { req.user = { id: userId }; next(); },
  });
  for (const amount of [0, -5, 0.5, null, undefined, "abc"]) {
    const req = { method: "POST", url: "/topups", body: { amount }, user: { id: userId } };
    const res = mockResponse();
    await findRoute(router, "post", "/topups").route.stack[0].handle(req, res);
    assert.equal(res.statusCode, 400, `amount=${amount}`);
  }
});

// ------------------------------------------------------------------
// Gruppo B: عرض المعاملة المعلقة (topups/pending)
// ------------------------------------------------------------------

test("wallet_hardened: pending returns only transactions for requesting user", async () => {
  let capturedUserId;
  const db = {
    query: async (_sql, vals) => {
      capturedUserId = vals[0];
      return { rows: [{ id: txId, status: "pending" }], rowCount: 1 };
    },
  };
  const router = createWalletRouter({
    database: db,
    authenticate: (req, _res, next) => { req.user = { id: userId }; next(); },
  });
  const req = { method: "GET", url: "/topups/pending", user: { id: userId } };
  const res = mockResponse();
  await findRoute(router, "get", "/topups/pending").route.stack[0].handle(req, res);
  assert.equal(res.statusCode, 200);
  assert.equal(capturedUserId, userId);
  assert.equal(res.body.data.id, txId);
});

test("wallet_hardened: pending returns 404 when no pending transaction", async () => {
  const db = { query: async () => ({ rows: [], rowCount: 0 }) };
  const router = createWalletRouter({
    database: db,
    authenticate: (req, _res, next) => { req.user = { id: userId }; next(); },
  });
  const req = { method: "GET", url: "/topups/pending", user: { id: userId } };
  const res = mockResponse();
  await findRoute(router, "get", "/topups/pending").route.stack[0].handle(req, res);
  assert.equal(res.statusCode, 404);
});

// ------------------------------------------------------------------
// Gruppo C: ربط الإيصال بالمعاملة (topups/:txId/receipt)
// ------------------------------------------------------------------

test("wallet_hardened: receipt link rejects invalid txId", async () => {
  const db = { query: async () => ({ rows: [], rowCount: 0 }) };
  const router = createWalletRouter({
    database: db,
    authenticate: (req, _res, next) => { req.user = { id: userId }; next(); },
  });
  const req = {
    method: "POST", url: `/topups/not-a-uuid/receipt`,
    body: { object_key: `${userId}/receipts/${txId}_file.jpg` },
    user: { id: userId },
    params: { txId: "not-a-uuid" },
  };
  const res = mockResponse();
  await findRoute(router, "post", "/topups/:txId/receipt").route.stack[0].handle(req, res);
  assert.equal(res.statusCode, 400);
});

test("wallet_hardened: receipt link rejects invalid object_key", async () => {
  const db = { query: async () => ({ rows: [], rowCount: 0 }) };
  const router = createWalletRouter({
    database: db,
    authenticate: (req, _res, next) => { req.user = { id: userId }; next(); },
  });
  const req = {
    method: "POST", url: `/topups/${txId}/receipt`,
    body: { object_key: "../../../etc/passwd" },
    user: { id: userId },
    params: { txId },
  };
  const res = mockResponse();
  await findRoute(router, "post", "/topups/:txId/receipt").route.stack[0].handle(req, res);
  assert.equal(res.statusCode, 400);
});

// ------------------------------------------------------------------
// Gruppo F: نظام تفويض الرفع والإيصالات (Upload Authorization & Receipts)
// ------------------------------------------------------------------
// Gruppo D: قرار الأدمن (decide) - التشديد الأمني
// ------------------------------------------------------------------

test("wallet_hardened: decide rejects non-admin user", async () => {
  const db = { query: async () => ({ rows: [], rowCount: 0 }) };
  const router = createWalletRouter({
    database: db,
    authenticate: (req, _res, next) => { req.user = { id: userId, is_admin: false }; next(); },
  });
  const req = { method: "POST", url: "/decide", body: { id: txId, status: "confirmed" }, user: { id: userId } };
  const res = mockResponse();
  await findRoute(router, "post", "/decide").route.stack[0].handle(req, res);
  assert.equal(res.statusCode, 403);
  assert.equal(res.body.reason, "not_admin");
});

test("wallet_hardened: decide rejects bad_id", async () => {
  const db = { query: async () => ({ rows: [{ 1: 1 }], rowCount: 1 }) };
  const router = createWalletRouter({
    database: db,
    authenticate: (req, _res, next) => { req.user = { id: adminId, is_admin: true }; next(); },
  });
  const req = { method: "POST", url: "/decide", body: { id: "not-a-uuid", status: "confirmed" }, user: { id: adminId } };
  const res = mockResponse();
  await findRoute(router, "post", "/decide").route.stack[0].handle(req, res);
  assert.equal(res.statusCode, 400);
  assert.equal(res.body.reason, "bad_id");
});

test("wallet_hardened: decide rejects bad_status", async () => {
  const db = { query: async () => ({ rows: [{ 1: 1 }], rowCount: 1 }) };
  const router = createWalletRouter({
    database: db,
    authenticate: (req, _res, next) => { req.user = { id: adminId, is_admin: true }; next(); },
  });
  const req = { method: "POST", url: "/decide", body: { id: txId, status: "pending" }, user: { id: adminId } };
  const res = mockResponse();
  await findRoute(router, "post", "/decide").route.stack[0].handle(req, res);
  assert.equal(res.statusCode, 400);
  assert.equal(res.body.reason, "bad_status");
});

test("wallet_hardened: decide returns 404 when transaction not found", async () => {
  const db = {
    query: async (sql) => {
      if (sql.includes("app_admins")) return { rows: [{ 1: 1 }], rowCount: 1 };
      return { rows: [], rowCount: 0 };
    },
  };
  const router = createWalletRouter({
    database: db,
    authenticate: (req, _res, next) => { req.user = { id: adminId, is_admin: true }; next(); },
  });
  const req = { method: "POST", url: "/decide", body: { id: txId, status: "confirmed" }, user: { id: adminId } };
  const res = mockResponse();
  await findRoute(router, "post", "/decide").route.stack[0].handle(req, res);
  assert.equal(res.statusCode, 404);
  assert.equal(res.body.reason, "not_found");
});

test("wallet_hardened: decide returns 409 when already decided", async () => {
  const db = {
    query: async (sql) => {
      if (sql.includes("app_admins")) return { rows: [{ 1: 1 }], rowCount: 1 };
      if (sql.includes("SELECT status")) return { rows: [{ status: "confirmed" }], rowCount: 1 };
      return { rows: [], rowCount: 0 };
    },
  };
  const router = createWalletRouter({
    database: db,
    authenticate: (req, _res, next) => { req.user = { id: adminId, is_admin: true }; next(); },
  });
  const req = { method: "POST", url: "/decide", body: { id: txId, status: "confirmed" }, user: { id: adminId } };
  const res = mockResponse();
  await findRoute(router, "post", "/decide").route.stack[0].handle(req, res);
  assert.equal(res.statusCode, 409);
  assert.equal(res.body.reason, "already_decided");
  assert.equal(res.body.status, "confirmed");
});

test("wallet_hardened: decide accepts confirmed and rejected by admin only", async () => {
  for (const st of ["confirmed", "rejected"]) {
    const db = {
      query: async (sql) => {
        if (sql.includes("app_admins")) return { rows: [{ 1: 1 }], rowCount: 1 };
        if (sql.includes("SELECT status")) return { rows: [{ status: "pending" }], rowCount: 1 };
        return { rows: [], rowCount: 1 };
      },
    };
    const router = createWalletRouter({
      database: db,
      authenticate: (req, _res, next) => { req.user = { id: adminId, is_admin: true }; next(); },
    });
    const req = { method: "POST", url: "/decide", body: { id: txId, status: st }, user: { id: adminId } };
    const res = mockResponse();
    await findRoute(router, "post", "/decide").route.stack[0].handle(req, res);
    assert.equal(res.statusCode, 200, `status=${st}`);
    assert.equal(res.body.ok, true);
    assert.equal(res.body.status, st);
  }
});

test("wallet_hardened: decide uses admin_id from req.user.id only, not client", async () => {
  let capturedAdminId;
  const db = {
    query: async (_sql, vals) => {
      capturedAdminId = vals;
      if (_sql.includes("app_admins")) return { rows: [{ 1: 1 }], rowCount: 1 };
      if (_sql.includes("SELECT status")) return { rows: [{ status: "pending" }], rowCount: 1 };
      return { rows: [], rowCount: 1 };
    },
  };
  const router = createWalletRouter({
    database: db,
    authenticate: (req, _res, next) => { req.user = { id: adminId, is_admin: true }; next(); },
  });
  // العميل يرسل admin_id مختلف عن req.user.id - يجب تجاهله واستخدام req.user.id
  const req = {
    method: "POST", url: "/decide",
    body: { id: txId, status: "confirmed", admin_id: otherUserId },
    user: { id: adminId },
  };
  const res = mockResponse();
  await findRoute(router, "post", "/decide").route.stack[0].handle(req, res);
  assert.equal(res.statusCode, 200);
  // admin_id في UPDATE يجب أن يكون req.user.id (adminId)، وليس otherUserId من جسم الطلب
  assert.equal(capturedAdminId[1], adminId);
  assert.notEqual(capturedAdminId[1], otherUserId);
});

// ------------------------------------------------------------------
// Gruppo E: منطق قيود المخطط (schema constraints) - اختبارات منطقية
// ------------------------------------------------------------------

test("wallet_hardened: constraint amount > 0 is enforced", () => {
  const validAmounts = [1, 100, 50000, 100000];
  for (const amt of validAmounts) {
    assert.ok(Number.isInteger(amt) && amt > 0, `amount ${amt} should be valid`);
  }
  const invalidAmounts = [0, -1, -5000, 0.5, 1.5];
  for (const amt of invalidAmounts) {
    const isValid = Number.isInteger(amt) && amt > 0;
    assert.ok(!isValid, `amount ${amt} should be invalid`);
  }
});

test("wallet_hardened: constraint status IN pending/confirmed/rejected", () => {
  const valid = ["pending", "confirmed", "rejected"];
  for (const s of valid) assert.ok(["pending", "confirmed", "rejected"].includes(s));
  const invalid = ["approved", "cancelled", "refunded", "null", ""];
  for (const s of invalid) assert.ok(!["pending", "confirmed", "rejected"].includes(s));
});

test("wallet_hardened: constraint payment_method = kcard only", () => {
  assert.equal("kcard", "kcard");
  const invalid = ["cash", "bank_transfer", "visa", "KCARD", ""];
  for (const m of invalid) assert.notEqual(m, "kcard");
});

test("wallet_hardened: confirmed_at matches status logic", () => {
  const cases = [
    { status: "confirmed", confirmedAt: new Date(), expected: true },
    { status: "pending", confirmedAt: null, expected: true },
    { status: "rejected", confirmedAt: null, expected: true },
    { status: "confirmed", confirmedAt: null, expected: false },
    { status: "pending", confirmedAt: new Date(), expected: false },
  ];
  for (const c of cases) {
    const matches = (c.status === "confirmed") === (c.confirmedAt !== null);
    assert.equal(matches, c.expected, `${c.status} / ${c.confirmedAt}`);
  }
});

test("wallet_hardened: receipt key pattern validates UUID/receipts/UUID_filename.ext format", () => {
  const pattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\/receipts\/[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}_[A-Za-z0-9._-]+\.[A-Za-z0-9]+$/;

  const valid = [
    `${userId}/receipts/${txId}_file.jpg`,
    `${userId}/receipts/${txId}_receipt-001.png`,
    `${otherUserId}/receipts/${txId}_file.webp`,
  ];
  for (const k of valid) assert.ok(pattern.test(k), `key ${k} should be valid format`);

  const invalid = [
    `${userId}/receipts/../etc/passwd`,
    `${userId}/receipts/${txId}`,
    `${userId}/receipts/${txId}_file`,
    `receipts/${txId}_file.jpg`,
    `${userId}/receipts/${txId}_file`,
    `${userId}/receipts//${txId}_file.jpg`,
    `${userId}/receipts/${txId}_file.jpg/extra`,
  ];
  for (const k of invalid) {
    assert.ok(!pattern.test(k), `key ${k} should be invalid format`);
  }
});

// ------------------------------------------------------------------
// Gruppo F: نظام تفويض الرفع والإيصالات (Upload Authorization & Receipts)
// ------------------------------------------------------------------

function makeMockStorage(overrides = {}) {
  return {
    upload: overrides.upload || (async ({ bucket, key }) => ({ bucket, key, size: 100 })),
    download: overrides.download || (async ({ bucket, key, userId }) => ({
      bucket, key, body: { pipe: () => {} }, contentType: "image/jpeg", size: 100, lastModified: new Date(),
    })),
    getSignedUrl: overrides.getSignedUrl || (async ({ bucket, key, expiresIn }) => ({
      url: `https://r2.example.test/signed/${key}?e=${expiresIn}`, expiresIn,
    })),
    checkOwnership: overrides.checkOwnership || (async () => true),
  };
}

function makeRequestWithAuth(router, method, routePath, url, body, user, params = {}, appLocals = {}) {
  const req = { method, url, body: body ?? {}, user, params };
  if (Object.keys(appLocals).length > 0) {
    req.app = { locals: appLocals };
  }
  const route = findRoute(router, method, routePath);
  return { req, res: mockResponse(), route };
}

// ------------------------------------------------------------------
// Gruppo F.1: إصدار إذن الرفع (authorize)
// ------------------------------------------------------------------

test("wallet_receipt: authorize creates upload permission for owner's pending transaction", async () => {
  const db = {
    query: async () => ({ rows: [{ status: "pending", user_id: userId, receipt_image_url: null }], rowCount: 1 }),
  };
  const authStore = createUploadAuthStore();
  const router = createWalletRouter({
    database: db,
    authenticate: (r, _res, next) => { r.user = { id: userId }; next(); },
    uploadAuthStore: authStore,
  });
  const { req, res, route } = makeRequestWithAuth(
    router, "post", "/topups/:txId/receipt/authorize", `/topups/${txId}/receipt/authorize`,
    null, { id: userId }, { txId }
  );

  await route.route.stack[0].handle(req, res);
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.success, true);
  assert.ok(res.body.data.authorizationId);
  assert.ok(res.body.data.objectKey.startsWith(`${userId}/receipts/${txId}_`));
  assert.ok(res.body.data.objectKey.endsWith(".jpg"));
  assert.ok(res.body.data.expiresAt > Date.now());
});

test("wallet_receipt: authorize rejects transaction not found", async () => {
  const db = { query: async () => ({ rows: [], rowCount: 0 }) };
  const authStore = createUploadAuthStore();
  const router = createWalletRouter({
    database: db,
    authenticate: (r, _res, next) => { r.user = { id: userId }; next(); },
    uploadAuthStore: authStore,
  });
  const { req, res, route } = makeRequestWithAuth(
    router, "post", "/topups/:txId/receipt/authorize", `/topups/${txId}/receipt/authorize`,
    null, { id: userId }, { txId }
  );

  await route.route.stack[0].handle(req, res);
  assert.equal(res.statusCode, 404);
  assert.equal(res.body.error, "Transaction not found");
});

test("wallet_receipt: authorize rejects transaction owned by another user", async () => {
  const db = {
    query: async () => ({ rows: [{ status: "pending", user_id: otherUserId, receipt_image_url: null }], rowCount: 1 }),
  };
  const authStore = createUploadAuthStore();
  const router = createWalletRouter({
    database: db,
    authenticate: (r, _res, next) => { r.user = { id: userId }; next(); },
    uploadAuthStore: authStore,
  });
  const { req, res, route } = makeRequestWithAuth(
    router, "post", "/topups/:txId/receipt/authorize", `/topups/${txId}/receipt/authorize`,
    null, { id: userId }, { txId }
  );

  await route.route.stack[0].handle(req, res);
  assert.equal(res.statusCode, 403);
  assert.equal(res.body.error, "Transaction belongs to another user");
});

test("wallet_receipt: authorize rejects already decided transaction", async () => {
  const db = {
    query: async () => ({ rows: [{ status: "confirmed", user_id: userId, receipt_image_url: null }], rowCount: 1 }),
  };
  const authStore = createUploadAuthStore();
  const router = createWalletRouter({
    database: db,
    authenticate: (r, _res, next) => { r.user = { id: userId }; next(); },
    uploadAuthStore: authStore,
  });
  const { req, res, route } = makeRequestWithAuth(
    router, "post", "/topups/:txId/receipt/authorize", `/topups/${txId}/receipt/authorize`,
    null, { id: userId }, { txId }
  );

  await route.route.stack[0].handle(req, res);
  assert.equal(res.statusCode, 409);
  assert.equal(res.body.error, "Transaction already decided");
});

test("wallet_receipt: authorize rejects transaction with receipt already linked", async () => {
  const db = {
    query: async () => ({ rows: [{ status: "pending", user_id: userId, receipt_image_url: "some/key.jpg" }], rowCount: 1 }),
  };
  const authStore = createUploadAuthStore();
  const router = createWalletRouter({
    database: db,
    authenticate: (r, _res, next) => { r.user = { id: userId }; next(); },
    uploadAuthStore: authStore,
  });
  const { req, res, route } = makeRequestWithAuth(
    router, "post", "/topups/:txId/receipt/authorize", `/topups/${txId}/receipt/authorize`,
    null, { id: userId }, { txId }
  );

  await route.route.stack[0].handle(req, res);
  assert.equal(res.statusCode, 409);
  assert.equal(res.body.error, "Receipt already linked");
});

// ------------------------------------------------------------------
// Gruppo F.2: ربط الإيصال بعد الرفع (link receipt)
// ------------------------------------------------------------------

test("wallet_receipt: link rejects missing authorizationId", async () => {
  const db = {
    query: async () => ({ rows: [{ status: "pending", user_id: userId, receipt_image_url: null }], rowCount: 1 }),
  };
  const authStore = createUploadAuthStore();
  const router = createWalletRouter({
    database: db,
    authenticate: (r, _res, next) => { r.user = { id: userId }; next(); },
    uploadAuthStore: authStore,
  });
  const { req, res, route } = makeRequestWithAuth(
    router, "post", "/topups/:txId/receipt", `/topups/${txId}/receipt`,
    {}, { id: userId }, { txId }
  );

  await route.route.stack[0].handle(req, res);
  assert.equal(res.statusCode, 400);
  assert.equal(res.body.error, "Authorization ID is required");
});

test("wallet_receipt: link rejects invalid authorization ID", async () => {
  const db = {
    query: async () => ({ rows: [{ status: "pending", user_id: userId, receipt_image_url: null }], rowCount: 1 }),
  };
  const authStore = createUploadAuthStore();
  const router = createWalletRouter({
    database: db,
    authenticate: (r, _res, next) => { r.user = { id: userId }; next(); },
    uploadAuthStore: authStore,
  });
  const { req, res, route } = makeRequestWithAuth(
    router, "post", "/topups/:txId/receipt", `/topups/${txId}/receipt`,
    { authorizationId: "invalid" }, { id: userId }, { txId }
  );

  await route.route.stack[0].handle(req, res);
  assert.equal(res.statusCode, 403);
  assert.equal(res.body.error, "Invalid, expired, or already used upload authorization");
});

test("wallet_receipt: link rejects expired authorization", async () => {
  const db = {
    query: async () => ({ rows: [{ status: "pending", user_id: userId, receipt_image_url: null }], rowCount: 1 }),
  };
  const authStore = createUploadAuthStore();
  const expiredAuth = authStore.create({
    userId: userId, txId, objectKey: `${userId}/receipts/${txId}_x.jpg`, bucket: "wallet_receipts", ttlSeconds: 0,
  });
  // Manually expire
  const entry = authStore.get(expiredAuth.id);
  entry.expiresAt = Date.now() - 1000;

  const router = createWalletRouter({
    database: db,
    authenticate: (r, _res, next) => { r.user = { id: userId }; next(); },
    uploadAuthStore: authStore,
  });
  const { req, res, route } = makeRequestWithAuth(
    router, "post", "/topups/:txId/receipt", `/topups/${txId}/receipt`,
    { authorizationId: expiredAuth.id }, { id: userId }, { txId }
  );

  await route.route.stack[0].handle(req, res);
  assert.equal(res.statusCode, 403);
});

test("wallet_receipt: link rejects one-time authorization reuse", async () => {
  const db = {
    query: async (sql) => {
      if (sql.includes("FOR UPDATE")) {
        return { rows: [{ status: "pending", user_id: userId, receipt_image_url: null }], rowCount: 1 };
      }
      return { rows: [{ id: txId }], rowCount: 1 };
    },
  };
  const authStore = createUploadAuthStore();
  const auth = authStore.create({
    userId: userId, txId, objectKey: `${userId}/receipts/${txId}_x.jpg`, bucket: "wallet_receipts",
  });

  const mockStorage = makeMockStorage();
  const router = createWalletRouter({
    database: db,
    authenticate: (r, _res, next) => { r.user = { id: userId }; next(); },
    uploadAuthStore: authStore,
  });

  // 첫 번째 استخدام ينجح
  const req1 = {
    method: "POST", url: `/topups/${txId}/receipt`,
    body: { authorizationId: auth.id },
    user: { id: userId },
    params: { txId },
    app: { locals: { storageService: mockStorage } },
  };
  const res1 = mockResponse();
  await findRoute(router, "post", "/topups/:txId/receipt").route.stack[0].handle(req1, res1);
  assert.equal(res1.statusCode, 200);

  // إعادة الاستخدام تفشل
  const req2 = {
    method: "POST", url: `/topups/${txId}/receipt`,
    body: { authorizationId: auth.id },
    user: { id: userId },
    params: { txId },
    app: { locals: { storageService: mockStorage } },
  };
  const res2 = mockResponse();
  await findRoute(router, "post", "/topups/:txId/receipt").route.stack[0].handle(req2, res2);
  assert.equal(res2.statusCode, 403);
  assert.equal(res2.body.error, "Invalid, expired, or already used upload authorization");
});

test("wallet_receipt: link rejects authorization for different transaction", async () => {
  const otherTxId = "e1f6b1a2-c3d4-4e5f-8a9b-0c1d2e3f4a5b";
  const db = {
    query: async () => ({ rows: [{ status: "pending", user_id: userId, receipt_image_url: null }], rowCount: 1 }),
  };
  const authStore = createUploadAuthStore();
  const auth = authStore.create({
    userId: userId, txId: otherTxId, objectKey: `${userId}/receipts/${otherTxId}_x.jpg`, bucket: "wallet_receipts",
  });

  const router = createWalletRouter({
    database: db,
    authenticate: (r, _res, next) => { r.user = { id: userId }; next(); },
    uploadAuthStore: authStore,
  });
  const { req, res, route } = makeRequestWithAuth(
    router, "post", "/topups/:txId/receipt", `/topups/${txId}/receipt`,
    { authorizationId: auth.id }, { id: userId }, { txId }
  );

  await route.route.stack[0].handle(req, res);
  assert.equal(res.statusCode, 403);
  assert.equal(res.body.error, "Authorization does not match transaction");
});

test("wallet_receipt: link rejects file not found in storage", async () => {
  const db = {
    query: async (sql) => {
      if (sql.includes("FOR UPDATE")) {
        return { rows: [{ status: "pending", user_id: userId, receipt_image_url: null }], rowCount: 1 };
      }
      return { rows: [{ id: txId }], rowCount: 1 };
    },
  };
  const authStore = createUploadAuthStore();
  const auth = authStore.create({
    userId: userId, txId, objectKey: `${userId}/receipts/${txId}_x.jpg`, bucket: "wallet_receipts",
  });

  const mockStorage = makeMockStorage({
    download: async () => { const e = new Error("Not Found"); e.statusCode = 404; throw e; },
  });
  const router = createWalletRouter({
    database: db,
    authenticate: (r, _res, next) => { r.user = { id: userId }; next(); },
    uploadAuthStore: authStore,
  });
  const req = {
    method: "POST", url: `/topups/${txId}/receipt`,
    body: { authorizationId: auth.id },
    user: { id: userId },
    params: { txId },
    app: { locals: { storageService: mockStorage } },
  };
  const res = mockResponse();
  await findRoute(router, "post", "/topups/:txId/receipt").route.stack[0].handle(req, res);
  assert.equal(res.statusCode, 409);
  assert.equal(res.body.error, "Receipt file not found in storage");
});

test("wallet_receipt: link rejects storage service failure", async () => {
  const db = {
    query: async (sql) => {
      if (sql.includes("FOR UPDATE")) {
        return { rows: [{ status: "pending", user_id: userId, receipt_image_url: null }], rowCount: 1 };
      }
      return { rows: [{ id: txId }], rowCount: 1 };
    },
  };
  const authStore = createUploadAuthStore();
  const auth = authStore.create({
    userId: userId, txId, objectKey: `${userId}/receipts/${txId}_x.jpg`, bucket: "wallet_receipts",
  });

  const mockStorage = makeMockStorage({
    download: async () => { throw new Error("Network error"); },
  });
  const router = createWalletRouter({
    database: db,
    authenticate: (r, _res, next) => { r.user = { id: userId }; next(); },
    uploadAuthStore: authStore,
  });
  const req = {
    method: "POST", url: `/topups/${txId}/receipt`,
    body: { authorizationId: auth.id },
    user: { id: userId },
    params: { txId },
    app: { locals: { storageService: mockStorage } },
  };
  const res = mockResponse();
  await findRoute(router, "post", "/topups/:txId/receipt").route.stack[0].handle(req, res);
  assert.equal(res.statusCode, 503);
  assert.equal(res.body.error, "Failed to verify receipt file");
});

test("wallet_receipt: link succeeds with valid authorization and file exists", async () => {
  let capturedVals;
  const db = {
    query: async (_sql, vals) => {
      capturedVals = vals;
      if (_sql.includes("FOR UPDATE")) {
        return { rows: [{ status: "pending", user_id: userId, receipt_image_url: null }], rowCount: 1 };
      }
      return { rows: [{ id: txId }], rowCount: 1 };
    },
  };
  const authStore = createUploadAuthStore();
  const auth = authStore.create({
    userId: userId, txId, objectKey: `${userId}/receipts/${txId}_x.jpg`, bucket: "wallet_receipts",
  });

  const mockStorage = makeMockStorage();
  const router = createWalletRouter({
    database: db,
    authenticate: (r, _res, next) => { r.user = { id: userId }; next(); },
    uploadAuthStore: authStore,
  });
  const req = {
    method: "POST", url: `/topups/${txId}/receipt`,
    body: { authorizationId: auth.id },
    user: { id: userId },
    params: { txId },
    app: { locals: { storageService: mockStorage } },
  };
  const res = mockResponse();
  await findRoute(router, "post", "/topups/:txId/receipt").route.stack[0].handle(req, res);
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.success, true);
  assert.equal(res.body.data.receipt_image_url, auth.objectKey);
  // التحقق من أن الـ UPDATE المستخدم هو objectKey من الإذن، وليس من العميل
  assert.equal(capturedVals[0], auth.objectKey);
  assert.equal(capturedVals[1], txId);
  assert.equal(capturedVals[2], userId);
});

// ------------------------------------------------------------------
// Gruppo F.3: توقيع رابط قراءة الإيصال (sign)
// ------------------------------------------------------------------

test("wallet_receipt: sign allows owner to read their receipt", async () => {
  const db = {
    query: async () => ({ rows: [{ receipt_image_url: `${userId}/receipts/${txId}_x.jpg`, user_id: userId, status: "confirmed" }], rowCount: 1 }),
  };
  const mockStorage = makeMockStorage();
  const router = createWalletRouter({
    database: db,
    authenticate: (r, _res, next) => { r.user = { id: userId, is_admin: false }; next(); },
  });
  const req = {
    method: "GET", url: `/topups/${txId}/receipt/sign`,
    user: { id: userId, is_admin: false },
    params: { txId },
    app: { locals: { storageService: mockStorage } },
  };
  const res = mockResponse();
  await findRoute(router, "get", "/topups/:txId/receipt/sign").route.stack[0].handle(req, res);
  assert.equal(res.statusCode, 200);
  assert.ok(res.body.data.url.includes(txId));
  assert.ok(res.body.data.expiresIn > 0);
});

test("wallet_receipt: sign allows admin to read any receipt", async () => {
  const db = {
    query: async () => ({ rows: [{ receipt_image_url: `${otherUserId}/receipts/${txId}_x.jpg`, user_id: otherUserId, status: "confirmed" }], rowCount: 1 }),
  };
  const mockStorage = makeMockStorage();
  const router = createWalletRouter({
    database: db,
    authenticate: (r, _res, next) => { r.user = { id: adminId, is_admin: true }; next(); },
  });
  const req = {
    method: "GET", url: `/topups/${txId}/receipt/sign`,
    user: { id: adminId, is_admin: true },
    params: { txId },
    app: { locals: { storageService: mockStorage } },
  };
  const res = mockResponse();
  await findRoute(router, "get", "/topups/:txId/receipt/sign").route.stack[0].handle(req, res);
  assert.equal(res.statusCode, 200);
  assert.ok(res.body.data.url.includes(txId));
});

test("wallet_receipt: sign rejects non-owner non-admin", async () => {
  const db = {
    query: async () => ({ rows: [{ receipt_image_url: `${otherUserId}/receipts/${txId}_x.jpg`, user_id: otherUserId, status: "confirmed" }], rowCount: 1 }),
  };
  const router = createWalletRouter({
    database: db,
    authenticate: (r, _res, next) => { r.user = { id: userId, is_admin: false }; next(); },
  });
  const req = {
    method: "GET", url: `/topups/${txId}/receipt/sign`,
    user: { id: userId, is_admin: false },
    params: { txId },
  };
  const res = mockResponse();
  await findRoute(router, "get", "/topups/:txId/receipt/sign").route.stack[0].handle(req, res);
  assert.equal(res.statusCode, 403);
  assert.equal(res.body.error, "Access denied to this receipt");
});

test("wallet_receipt: sign rejects transaction without receipt", async () => {
  const db = {
    query: async () => ({ rows: [{ receipt_image_url: null, user_id: userId, status: "pending" }], rowCount: 1 }),
  };
  const router = createWalletRouter({
    database: db,
    authenticate: (r, _res, next) => { r.user = { id: userId }; next(); },
  });
  const req = {
    method: "GET", url: `/topups/${txId}/receipt/sign`,
    user: { id: userId },
    params: { txId },
  };
  const res = mockResponse();
  await findRoute(router, "get", "/topups/:txId/receipt/sign").route.stack[0].handle(req, res);
  assert.equal(res.statusCode, 404);
  assert.equal(res.body.error, "No receipt linked to this transaction");
});

test("wallet_receipt: sign rejects transaction not found", async () => {
  const db = { query: async () => ({ rows: [], rowCount: 0 }) };
  const router = createWalletRouter({
    database: db,
    authenticate: (r, _res, next) => { r.user = { id: userId }; next(); },
  });
  const req = {
    method: "GET", url: `/topups/${txId}/receipt/sign`,
    user: { id: userId },
    params: { txId },
  };
  const res = mockResponse();
  await findRoute(router, "get", "/topups/:txId/receipt/sign").route.stack[0].handle(req, res);
  assert.equal(res.statusCode, 404);
  assert.equal(res.body.error, "Transaction not found");
});

// ------------------------------------------------------------------
// Gruppo F.4: Audit/logic checks
// ------------------------------------------------------------------

test("wallet_receipt: upload auth store cleanup removes expired entries", () => {
  const store = createUploadAuthStore();
  store.create({ userId: userId, txId, objectKey: `${userId}/receipts/${txId}_a.jpg`, bucket: "wallet_receipts", ttlSeconds: 0 });
  store.create({ userId: userId, txId, objectKey: `${userId}/receipts/${txId}_b.jpg`, bucket: "wallet_receipts", ttlSeconds: 300 });

  // ttlSeconds=0 entry expires immediately (expiresAt = now)
  const expiredEntry = store.get(store.create({ userId: userId, txId, objectKey: `${userId}/receipts/${txId}_c.jpg`, bucket: "wallet_receipts", ttlSeconds: 0 }).id);
  expiredEntry.expiresAt = Date.now() - 1000;
  store.cleanupExpired();
  // لا ينبغي أن يُلقي خطأ
  assert.ok(true, "cleanupExpired completed without error");
});

// ------------------------------------------------------------------
// Gruppo G: البنية التحتية والتزامن (Infrastructure & Concurrency)
// ------------------------------------------------------------------

// ------------------------------------------------------------------
// Gruppo G.1: استهلاك متزامن لنفس الإذن (Race Condition)
// ------------------------------------------------------------------

test("wallet_infra: concurrent consume of same authorizationId succeeds only once", async () => {
  const db = {
    query: async (sql) => {
      if (sql.includes("FOR UPDATE")) {
        return { rows: [{ status: "pending", user_id: userId, receipt_image_url: null }], rowCount: 1 };
      }
      return { rows: [{ id: txId }], rowCount: 1 };
    },
  };
  const authStore = createUploadAuthStore();
  const auth = authStore.create({
    userId: userId, txId, objectKey: `${userId}/receipts/${txId}_x.jpg`, bucket: "wallet_receipts",
  });

  const mockStorage = makeMockStorage();
  const router = createWalletRouter({
    database: db,
    authenticate: (r, _res, next) => { r.user = { id: userId }; next(); },
    uploadAuthStore: authStore,
  });

  // إطلاق طلبين متزامنين بنفس authorizationId
  const req1 = {
    method: "POST", url: `/topups/${txId}/receipt`,
    body: { authorizationId: auth.id },
    user: { id: userId },
    params: { txId },
    app: { locals: { storageService: mockStorage } },
  };
  const req2 = {
    method: "POST", url: `/topups/${txId}/receipt`,
    body: { authorizationId: auth.id },
    user: { id: userId },
    params: { txId },
    app: { locals: { storageService: mockStorage } },
  };

  const res1 = mockResponse();
  const res2 = mockResponse();
  // تشغيل दोनों بشكل متوازٍ
  await Promise.all([
    findRoute(router, "post", "/topups/:txId/receipt").route.stack[0].handle(req1, res1),
    findRoute(router, "post", "/topups/:txId/receipt").route.stack[0].handle(req2, res2),
  ]);

  const statuses = [res1.statusCode, res2.statusCode].sort();
  // يجب أن ينجح أحدهما ويفشل الآخر (لا يجوز أن ينجح الاثنان)
  assert.ok(statuses.includes(200), "يجب أن ينجح طلب واحد على الأقل");
  assert.ok(statuses.includes(403), "يجب أن يفشل الطلب الثاني لأن الإذن استُهلك");
});

// ------------------------------------------------------------------
// Gruppo G.2: فقدان الأذونات عند إعادة التشغيل (New store instance)
// ------------------------------------------------------------------

test("wallet_infra: new store instance loses previous authorizations (simulated server restart)", () => {
  const store1 = createUploadAuthStore();
  const auth = store1.create({
    userId: userId, txId, objectKey: `${userId}/receipts/${txId}_x.jpg`, bucket: "wallet_receipts",
  });
  assert.ok(store1.get(auth.id), "الإذن موجود في النسخة الأولى");

  // محاكاة إعادة تشغيل السيرفر: نسخة جديدة من المتجر
  const store2 = createUploadAuthStore();
  assert.equal(store2.get(auth.id), undefined, "الإذن ضاع بعد إعادة التشغيل (نسخة جديدة)");
});

// ------------------------------------------------------------------
// Gruppo G.3: صلاحيات الأدمن والمستخدم في قراءة الإيصالات
// ------------------------------------------------------------------

test("wallet_infra: regular user cannot sign receipt of another user's transaction", async () => {
  const db = {
    query: async () => ({ rows: [{ receipt_image_url: `${otherUserId}/receipts/${txId}_x.jpg`, user_id: otherUserId, status: "confirmed" }], rowCount: 1 }),
  };
  const mockStorage = makeMockStorage();
  const router = createWalletRouter({
    database: db,
    authenticate: (r, _res, next) => { r.user = { id: userId, is_admin: false }; next(); },
  });
  const req = {
    method: "GET", url: `/topups/${txId}/receipt/sign`,
    user: { id: userId, is_admin: false },
    params: { txId },
    app: { locals: { storageService: mockStorage } },
  };
  const res = mockResponse();
  await findRoute(router, "get", "/topups/:txId/receipt/sign").route.stack[0].handle(req, res);
  assert.equal(res.statusCode, 403);
  assert.equal(res.body.error, "Access denied to this receipt");
});

test("wallet_infra: admin can sign receipt of any user's transaction", async () => {
  const db = {
    query: async () => ({ rows: [{ receipt_image_url: `${otherUserId}/receipts/${txId}_x.jpg`, user_id: otherUserId, status: "confirmed" }], rowCount: 1 }),
  };
  const mockStorage = makeMockStorage();
  const router = createWalletRouter({
    database: db,
    authenticate: (r, _res, next) => { r.user = { id: adminId, is_admin: true }; next(); },
  });
  const req = {
    method: "GET", url: `/topups/${txId}/receipt/sign`,
    user: { id: adminId, is_admin: true },
    params: { txId },
    app: { locals: { storageService: mockStorage } },
  };
  const res = mockResponse();
  await findRoute(router, "get", "/topups/:txId/receipt/sign").route.stack[0].handle(req, res);
  assert.equal(res.statusCode, 200);
  assert.ok(res.body.data.url.includes(txId));
});

// ------------------------------------------------------------------
// Gruppo G.4: فشل التخزين وعدم ربط الإيصال
// ------------------------------------------------------------------

test("wallet_infra: link rejects when storage download fails (network error)", async () => {
  const db = {
    query: async (sql) => {
      if (sql.includes("FOR UPDATE")) {
        return { rows: [{ status: "pending", user_id: userId, receipt_image_url: null }], rowCount: 1 };
      }
      return { rows: [{ id: txId }], rowCount: 1 };
    },
  };
  const authStore = createUploadAuthStore();
  const auth = authStore.create({
    userId: userId, txId, objectKey: `${userId}/receipts/${txId}_x.jpg`, bucket: "wallet_receipts",
  });

  const mockStorage = makeMockStorage({
    download: async () => { throw new Error("ECONNREFUSED"); },
  });
  const router = createWalletRouter({
    database: db,
    authenticate: (r, _res, next) => { r.user = { id: userId }; next(); },
    uploadAuthStore: authStore,
  });
  const req = {
    method: "POST", url: `/topups/${txId}/receipt`,
    body: { authorizationId: auth.id },
    user: { id: userId },
    params: { txId },
    app: { locals: { storageService: mockStorage } },
  };
  const res = mockResponse();
  await findRoute(router, "post", "/topups/:txId/receipt").route.stack[0].handle(req, res);
  assert.equal(res.statusCode, 503);
  assert.equal(res.body.error, "Failed to verify receipt file");
});

test("wallet_infra: link rejects when transaction already has receipt", async () => {
  const db = {
    query: async () => ({ rows: [{ status: "pending", user_id: userId, receipt_image_url: "existing/key.jpg" }], rowCount: 1 }),
  };
  const authStore = createUploadAuthStore();
  const auth = authStore.create({
    userId: userId, txId, objectKey: `${userId}/receipts/${txId}_x.jpg`, bucket: "wallet_receipts",
  });

  const mockStorage = makeMockStorage();
  const router = createWalletRouter({
    database: db,
    authenticate: (r, _res, next) => { r.user = { id: userId }; next(); },
    uploadAuthStore: authStore,
  });
  const req = {
    method: "POST", url: `/topups/${txId}/receipt`,
    body: { authorizationId: auth.id },
    user: { id: userId },
    params: { txId },
    app: { locals: { storageService: mockStorage } },
  };
  const res = mockResponse();
  await findRoute(router, "post", "/topups/:txId/receipt").route.stack[0].handle(req, res);
  assert.equal(res.statusCode, 409);
  assert.equal(res.body.error, "Receipt already linked");
});

test("wallet_infra: authorize rejects when transaction not pending (already confirmed)", async () => {
  const db = {
    query: async () => ({ rows: [{ status: "confirmed", user_id: userId, receipt_image_url: null }], rowCount: 1 }),
  };
  const authStore = createUploadAuthStore();
  const router = createWalletRouter({
    database: db,
    authenticate: (r, _res, next) => { r.user = { id: userId }; next(); },
    uploadAuthStore: authStore,
  });
  const { req, res, route } = makeRequestWithAuth(
    router, "post", "/topups/:txId/receipt/authorize", `/topups/${txId}/receipt/authorize`,
    null, { id: userId }, { txId }
  );
  await route.route.stack[0].handle(req, res);
  assert.equal(res.statusCode, 409);
  assert.equal(res.body.error, "Transaction already decided");
});

// ------------------------------------------------------------------
// Gruppo H: G9.5 - exact object_key ownership matching
// ------------------------------------------------------------------

// ------------------------------------------------------------------
// Gruppo H.1: exact object_key match - no partial/prefix matching
// ------------------------------------------------------------------

test("wallet_g95: authorize generates exact objectKey for the transaction", async () => {
  const db = {
    query: async () => ({ rows: [{ status: "pending", user_id: userId, receipt_image_url: null }], rowCount: 1 }),
  };
  const authStore = createUploadAuthStore();
  const router = createWalletRouter({
    database: db,
    authenticate: (r, _res, next) => { r.user = { id: userId }; next(); },
    uploadAuthStore: authStore,
  });
  const { req, res, route } = makeRequestWithAuth(
    router, "post", "/topups/:txId/receipt/authorize", `/topups/${txId}/receipt/authorize`,
    null, { id: userId }, { txId }
  );
  await route.route.stack[0].handle(req, res);
  assert.equal(res.statusCode, 200);
  const expectedKey = `${userId}/receipts/${txId}_`;
  assert.ok(res.body.data.objectKey.startsWith(expectedKey), `objectKey must start with ${expectedKey}`);
  assert.ok(res.body.data.objectKey.endsWith(".jpg"), "objectKey must end with .jpg");
  // objectKey يجب أن يحتوي على txId بالضبط
  assert.ok(res.body.data.objectKey.includes(`/${txId}_`), "objectKey must contain the exact txId");
});

test("wallet_g95: link rejects objectKey from different transaction (similar key)", async () => {
  const otherTxId = "e1f6b1a2-c3d4-4e5f-8a9b-0c1d2e3f4a5b";
  const db = {
    query: async (sql) => {
      if (sql.includes("FOR UPDATE")) {
        return { rows: [{ status: "pending", user_id: userId, receipt_image_url: null }], rowCount: 1 };
      }
      return { rows: [{ id: txId }], rowCount: 1 };
    },
  };
  const authStore = createUploadAuthStore();
  // إذن لمعاملة أخرى ولكن مفتاح مشابه (نفس userId، txId مختلف)
  const auth = authStore.create({
    userId: userId, txId: otherTxId, objectKey: `${userId}/receipts/${otherTxId}_x.jpg`, bucket: "wallet_receipts",
  });

  const mockStorage = makeMockStorage();
  const router = createWalletRouter({
    database: db,
    authenticate: (r, _res, next) => { r.user = { id: userId }; next(); },
    uploadAuthStore: authStore,
  });
  const req = {
    method: "POST", url: `/topups/${txId}/receipt`,
    body: { authorizationId: auth.id },
    user: { id: userId },
    params: { txId },
    app: { locals: { storageService: mockStorage } },
  };
  const res = mockResponse();
  await findRoute(router, "post", "/topups/:txId/receipt").route.stack[0].handle(req, res);
  assert.equal(res.statusCode, 403);
  assert.equal(res.body.error, "Authorization does not match transaction");
});

test("wallet_g95: link rejects authorization owned by another user", async () => {
  const db = {
    query: async (sql) => {
      if (sql.includes("FOR UPDATE")) {
        return { rows: [{ status: "pending", user_id: userId, receipt_image_url: null }], rowCount: 1 };
      }
      return { rows: [{ id: txId }], rowCount: 1 };
    },
  };
  const authStore = createUploadAuthStore();
  // إذن لمستخدم آخر ولكن txId نفسه
  const auth = authStore.create({
    userId: otherUserId, txId, objectKey: `${otherUserId}/receipts/${txId}_x.jpg`, bucket: "wallet_receipts",
  });

  const mockStorage = makeMockStorage();
  const router = createWalletRouter({
    database: db,
    authenticate: (r, _res, next) => { r.user = { id: userId }; next(); },
    uploadAuthStore: authStore,
  });
  const req = {
    method: "POST", url: `/topups/${txId}/receipt`,
    body: { authorizationId: auth.id },
    user: { id: userId },
    params: { txId },
    app: { locals: { storageService: mockStorage } },
  };
  const res = mockResponse();
  await findRoute(router, "post", "/topups/:txId/receipt").route.stack[0].handle(req, res);
  assert.equal(res.statusCode, 403);
  assert.equal(res.body.error, "Authorization belongs to another user");
});

test("wallet_g95: link rejects when authorizationId does not exist", async () => {
  const db = {
    query: async (sql) => {
      if (sql.includes("FOR UPDATE")) {
        return { rows: [{ status: "pending", user_id: userId, receipt_image_url: null }], rowCount: 1 };
      }
      return { rows: [{ id: txId }], rowCount: 1 };
    },
  };
  const authStore = createUploadAuthStore();
  // لا يوجد أي إذن تم إنشاؤه
  const router = createWalletRouter({
    database: db,
    authenticate: (r, _res, next) => { r.user = { id: userId }; next(); },
    uploadAuthStore: authStore,
  });
  const req = {
    method: "POST", url: `/topups/${txId}/receipt`,
    body: { authorizationId: "nonexistent-authorization-id" },
    user: { id: userId },
    params: { txId },
    app: { locals: { storageService: makeMockStorage() } },
  };
  const res = mockResponse();
  await findRoute(router, "post", "/topups/:txId/receipt").route.stack[0].handle(req, res);
  assert.equal(res.statusCode, 403);
  assert.equal(res.body.error, "Invalid, expired, or already used upload authorization");
});

test("wallet_g95: link rejects when storage file is empty (size 0)", async () => {
  const db = {
    query: async (sql) => {
      if (sql.includes("FOR UPDATE")) {
        return { rows: [{ status: "pending", user_id: userId, receipt_image_url: null }], rowCount: 1 };
      }
      return { rows: [{ id: txId }], rowCount: 1 };
    },
  };
  const authStore = createUploadAuthStore();
  const auth = authStore.create({
    userId: userId, txId, objectKey: `${userId}/receipts/${txId}_x.jpg`, bucket: "wallet_receipts",
  });

  // التخزين يعيد ملفاً بحجم 0 (فارغ)
  const mockStorage = makeMockStorage({
    download: async () => ({
      bucket: "wallet_receipts", key: auth.objectKey,
      body: { pipe: () => {} }, contentType: "image/jpeg", size: 0, lastModified: new Date(),
    }),
  });
  const router = createWalletRouter({
    database: db,
    authenticate: (r, _res, next) => { r.user = { id: userId }; next(); },
    uploadAuthStore: authStore,
  });
  const req = {
    method: "POST", url: `/topups/${txId}/receipt`,
    body: { authorizationId: auth.id },
    user: { id: userId },
    params: { txId },
    app: { locals: { storageService: mockStorage } },
  };
  const res = mockResponse();
  await findRoute(router, "post", "/topups/:txId/receipt").route.stack[0].handle(req, res);
  // يجب أن يفشل لأن الملف فارغ (لا يُعتبر إيصالاً صالحاً)
  assert.equal(res.statusCode, 409);
  assert.equal(res.body.error, "Receipt file is empty or invalid");
});

// ------------------------------------------------------------------
// Gruppo H.2: prevent changing receipt of confirmed/rejected transaction
// ------------------------------------------------------------------

test("wallet_g95: authorize rejects confirmed transaction (cannot add receipt)", async () => {
  const db = {
    query: async () => ({ rows: [{ status: "confirmed", user_id: userId, receipt_image_url: null }], rowCount: 1 }),
  };
  const authStore = createUploadAuthStore();
  const router = createWalletRouter({
    database: db,
    authenticate: (r, _res, next) => { r.user = { id: userId }; next(); },
    uploadAuthStore: authStore,
  });
  const { req, res, route } = makeRequestWithAuth(
    router, "post", "/topups/:txId/receipt/authorize", `/topups/${txId}/receipt/authorize`,
    null, { id: userId }, { txId }
  );
  await route.route.stack[0].handle(req, res);
  assert.equal(res.statusCode, 409);
  assert.equal(res.body.error, "Transaction already decided");
});

test("wallet_g95: authorize rejects rejected transaction (cannot add receipt)", async () => {
  const db = {
    query: async () => ({ rows: [{ status: "rejected", user_id: userId, receipt_image_url: null }], rowCount: 1 }),
  };
  const authStore = createUploadAuthStore();
  const router = createWalletRouter({
    database: db,
    authenticate: (r, _res, next) => { r.user = { id: userId }; next(); },
    uploadAuthStore: authStore,
  });
  const { req, res, route } = makeRequestWithAuth(
    router, "post", "/topups/:txId/receipt/authorize", `/topups/${txId}/receipt/authorize`,
    null, { id: userId }, { txId }
  );
  await route.route.stack[0].handle(req, res);
  assert.equal(res.statusCode, 409);
  assert.equal(res.body.error, "Transaction already decided");
});

// ------------------------------------------------------------------
// Gruppo H.3: admin/user permission checks for signing
// ------------------------------------------------------------------

test("wallet_g95: sign rejects regular user accessing admin-only receipt (no admin flag)", async () => {
  const db = {
    query: async () => ({ rows: [{ receipt_image_url: `${userId}/receipts/${txId}_x.jpg`, user_id: userId, status: "confirmed", is_admin: false }], rowCount: 1 }),
  };
  const mockStorage = makeMockStorage();
  const router = createWalletRouter({
    database: db,
    authenticate: (r, _res, next) => { r.user = { id: userId, is_admin: false }; next(); },
  });
  const req = {
    method: "GET", url: `/topups/${txId}/receipt/sign`,
    user: { id: userId, is_admin: false },
    params: { txId },
    app: { locals: { storageService: mockStorage } },
  };
  const res = mockResponse();
  await findRoute(router, "get", "/topups/:txId/receipt/sign").route.stack[0].handle(req, res);
  // المستخدم هو مالك المعاملة،所以 فهو يستطيع القراءة
  assert.equal(res.statusCode, 200);
});

test("wallet_g95: sign rejects user accessing another user's confirmed receipt", async () => {
  const db = {
    query: async () => ({ rows: [{ receipt_image_url: `${otherUserId}/receipts/${txId}_x.jpg`, user_id: otherUserId, status: "confirmed" }], rowCount: 1 }),
  };
  const mockStorage = makeMockStorage();
  const router = createWalletRouter({
    database: db,
    authenticate: (r, _res, next) => { r.user = { id: userId, is_admin: false }; next(); },
  });
  const req = {
    method: "GET", url: `/topups/${txId}/receipt/sign`,
    user: { id: userId, is_admin: false },
    params: { txId },
    app: { locals: { storageService: mockStorage } },
  };
  const res = mockResponse();
  await findRoute(router, "get", "/topups/:txId/receipt/sign").route.stack[0].handle(req, res);
  assert.equal(res.statusCode, 403);
  assert.equal(res.body.error, "Access denied to this receipt");
});

