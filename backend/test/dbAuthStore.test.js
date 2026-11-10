import assert from "node:assert/strict";
import test from "node:test";
import { createDbAuthStore } from "../services/dbAuthStore.js";
import { createWalletRouter } from "../routes/wallet.js";

const userId = "d1f6b1a2-c3d4-4e5f-8a9b-0c1d2e3f4a5b";
const otherUserId = "b1f6b1a2-c3d4-4e5f-8a9b-0c1d2e3f4a5b";
const txId = "c1f6b1a2-c3d4-4e5f-8a9b-0c1d2e3f4a5b";
const otherTxId = "e1f6b1a2-c3d4-4e5f-8a9b-0c1d2e3f4a5b";
const objectKey = "d1f6b1a2-c3d4-4e5f-8a9b-0c1d2e3f4a5b/receipts/c1f6b1a2-c3d4-4e5f-8a9b-0c1d2e3f4a5b_abc12345.jpg";
const bucket = "wallet_receipts";

const norm = (sql) => String(sql).replace(/\s+/g, " ").trim();

// ------------------------------------------------------------------
// Helper: mock database that records calls and returns programmable results
// ------------------------------------------------------------------
function mockDatabase({ shouldFail = false, failMessage = "DB error", tableMissing = false, rows = [] } = {}) {
  const calls = [];
  return {
    query: async (sql, params) => {
      calls.push({ sql, params });
      if (shouldFail) {
        throw new Error(failMessage);
      }
      if (tableMissing && norm(sql).includes("upload_authorizations")) {
        throw new Error('relation "public.upload_authorizations" does not exist');
      }
      // Simulate INSERT RETURNING for create
      if (norm(sql).startsWith("INSERT INTO public.upload_authorizations")) {
        const id = params[0];
        return {
          rows: [{ id, object_key: objectKey, bucket, expires_at: params[5] }],
          rowCount: 1,
        };
      }
      // Simulate UPDATE RETURNING for consume
      if (norm(sql).startsWith("UPDATE public.upload_authorizations")) {
        const usedMatch = norm(sql).includes("SET used = TRUE");
        if (usedMatch) {
          return { rows: rows.length > 0 ? rows : [], rowCount: rows.length };
        }
        return { rows: [], rowCount: 0 };
      }
      // Simulate SELECT for get
      if (norm(sql).startsWith("SELECT") && norm(sql).includes("upload_authorizations")) {
        return { rows: rows.length > 0 ? rows : [], rowCount: rows.length };
      }
      // Simulate DELETE for revoke
      if (norm(sql).startsWith("DELETE FROM public.upload_authorizations")) {
        return { rows: [], rowCount: 1 };
      }
      return { rows: [], rowCount: 0 };
    },
    get calls() {
      return calls;
    },
  };
}

function consumeRow(userId, txId, objectKey, bucket, expiresAt) {
  return {
    user_id: userId,
    tx_id: txId,
    object_key: objectKey,
    bucket,
    expires_at: expiresAt || new Date(Date.now() + 300000).toISOString(),
  };
}

// ------------------------------------------------------------------
// Gruppo B1: dbAuthStore.create — إنشاء إذن رفع
// ------------------------------------------------------------------
test("dbAuthStore.create: ينشئ إذناً ويعيد الحقول المتوقعة", async () => {
  const db = mockDatabase();
  const store = createDbAuthStore({ database: db });
  const result = await store.create({ userId, txId, objectKey, bucket });

  assert.equal(typeof result.id, "string");
  assert.equal(result.objectKey, objectKey);
  assert.equal(result.bucket, bucket);
  assert.ok(result.expiresAt > Date.now());
  assert.equal(db.calls.length, 1);
  assert.ok(db.calls[0].sql.includes("INSERT INTO public.upload_authorizations"));
  assert.deepEqual(db.calls[0].params, [result.id, userId, txId, objectKey, bucket, result.expiresAt && new Date(result.expiresAt).toISOString()]);
});

test("dbAuthStore.create: يرفض عند فقدان الحقول المطلوبة", async () => {
  const db = mockDatabase();
  const store = createDbAuthStore({ database: db });
  await assert.rejects(() => store.create({ userId, txId, objectKey: undefined, bucket }));
  await assert.rejects(() => store.create({ userId, txId: undefined, objectKey, bucket }));
  await assert.rejects(() => store.create({ txId, objectKey, bucket }));
});

// ------------------------------------------------------------------
// Gruppo B2: dbAuthStore.consume — استهلاك ذري مرة واحدة
// ------------------------------------------------------------------
test("dbAuthStore.consume: ينجح عند تطابق جميع الحقول وعدم الاستخدام والانتهاء", async () => {
  const db = mockDatabase({
    rows: [consumeRow(userId, txId, objectKey, bucket, new Date(Date.now() + 300000).toISOString())],
  });
  const store = createDbAuthStore({ database: db });
  const result = await store.consume("auth-123", { txId, userId, objectKey });

  assert.ok(result);
  assert.equal(result.userId, userId);
  assert.equal(result.txId, txId);
  assert.equal(result.objectKey, objectKey);
  assert.equal(result.used, true);
});

test("dbAuthStore.consume: يعيد null عند استخدام الإذن مسبقاً (used = TRUE)", async () => {
  const db = mockDatabase({ rows: [] }); // UPDATE يُفرغ لأن used = TRUE بالفعل
  const store = createDbAuthStore({ database: db });
  const result = await store.consume("auth-123", { txId, userId, objectKey });
  assert.equal(result, null);
});

test("dbAuthStore.consume: يعيد null عند انتهاء الصلاحية (expires_at <= NOW())", async () => {
  const db = mockDatabase({ rows: [] }); // لا صفوف تُعاد لأن الشرط expires_at > NOW() يفشل
  const store = createDbAuthStore({ database: db });
  const result = await store.consume("auth-123", { txId, userId, objectKey });
  assert.equal(result, null);
});

test("dbAuthStore.consume: يعيد null عند اختلاف user_id", async () => {
  const db = mockDatabase({ rows: [] });
  const store = createDbAuthStore({ database: db });
  const result = await store.consume("auth-123", { txId, userId: otherUserId, objectKey });
  assert.equal(result, null);
});

test("dbAuthStore.consume: يعيد null عند اختلاف tx_id", async () => {
  const db = mockDatabase({ rows: [] });
  const store = createDbAuthStore({ database: db });
  const result = await store.consume("auth-123", { txId: otherTxId, userId, objectKey });
  assert.equal(result, null);
});

test("dbAuthStore.consume: يعيد null عند اختلاف object_key", async () => {
  const db = mockDatabase({ rows: [] });
  const store = createDbAuthStore({ database: db });
  const result = await store.consume("auth-123", { txId, userId, objectKey: "different/key.jpg" });
  assert.equal(result, null);
});

test("dbAuthStore.consume: يعيد null عندما لا يوجد إذن بالمعرف المعطى", async () => {
  const db = mockDatabase({ rows: [] });
  const store = createDbAuthStore({ database: db });
  const result = await store.consume("nonexistent", { txId, userId, objectKey });
  assert.equal(result, null);
});

test("dbAuthStore.consume: يعيد سجلاً واحداً فقط عند النجاح", async () => {
  const db = mockDatabase({
    rows: [consumeRow(userId, txId, objectKey, bucket, new Date(Date.now() + 300000).toISOString())],
  });
  const store = createDbAuthStore({ database: db });
  const result = await store.consume("auth-123", { txId, userId, objectKey });
  assert.equal(result.userId, userId);
  assert.equal(result.txId, txId);
});

// طلبان متزامنان لنفس الإذن — يجب أن ينجح واحد فقط
test("dbAuthStore.consume: طلبان متزامنان لنفس authorizationId — ينجح واحد فقط", async () => {
  let firstCall = true;
  const db = {
    query: async (sql, params) => {
      if (sql.trim().startsWith("UPDATE")) {
        if (firstCall) {
          firstCall = false;
          return {
            rows: [consumeRow(userId, txId, objectKey, bucket, new Date(Date.now() + 300000).toISOString())],
            rowCount: 1,
          };
        }
        return { rows: [], rowCount: 0 }; // الاستدعاء الثاني لا يجد صفاً (تم استهلاكه)
      }
      return { rows: [], rowCount: 0 };
    },
  };
  const store = createDbAuthStore({ database: db });
  const [r1, r2] = await Promise.all([
    store.consume("auth-123", { txId, userId, objectKey }),
    store.consume("auth-123", { txId, userId, objectKey }),
  ]);
  const successes = [r1, r2].filter(Boolean);
  assert.equal(successes.length, 1, "يجب أن ينجح استهلاك واحد فقط");
});

// ------------------------------------------------------------------
// Gruppo B3: dbAuthStore.revoke و get
// ------------------------------------------------------------------
test("dbAuthStore.revoke: يحذف الإذن بالمعرف", async () => {
  const db = mockDatabase();
  const store = createDbAuthStore({ database: db });
  await store.revoke("auth-123");
  assert.equal(db.calls.length, 1);
  assert.ok(db.calls[0].sql.includes("DELETE FROM public.upload_authorizations"));
});

test("dbAuthStore.get: يعيد الإذن عند وجوده", async () => {
  const db = mockDatabase({
    rows: [{ id: "auth-1", user_id: userId, tx_id: txId, object_key: objectKey, bucket, expires_at: new Date(Date.now() + 300000).toISOString(), used: false }],
  });
  const store = createDbAuthStore({ database: db });
  const result = await store.get("auth-1");
  assert.ok(result);
  assert.equal(result.userId, userId);
  assert.equal(result.used, false);
});

test("dbAuthStore.get: يعيد null عند عدم الوجود", async () => {
  const db = mockDatabase({ rows: [] });
  const store = createDbAuthStore({ database: db });
  const result = await store.get("nonexistent");
  assert.equal(result, null);
});

// ------------------------------------------------------------------
// Gruppo B4:處錯 — غياب الجدول وفشل القاعدة
// ------------------------------------------------------------------
test("dbAuthStore.create: يطرح خطأً واضحاً عندما يكون جدول upload_authorizations غائباً", async () => {
  const db = mockDatabase({ tableMissing: true });
  const store = createDbAuthStore({ database: db });
  await assert.rejects(
    () => store.create({ userId, txId, objectKey, bucket }),
    /relation "public.upload_authorizations" does not exist/
  );
});

test("dbAuthStore.create: يطرح خطأً عند فشل قاعدة البيانات", async () => {
  const db = mockDatabase({ shouldFail: true, failMessage: "connection refused" });
  const store = createDbAuthStore({ database: db });
  await assert.rejects(() => store.create({ userId, txId, objectKey, bucket }), /connection refused/);
});

test("dbAuthStore.consume: يطرح خطأً عند فشل قاعدة البيانات", async () => {
  const db = mockDatabase({ shouldFail: true, failMessage: "connection refused" });
  const store = createDbAuthStore({ database: db });
  await assert.rejects(() => store.consume("auth-123", { txId, userId, objectKey }), /connection refused/);
});

test("dbAuthStore: يطرح خطأً عند عدم تمرير قاعدة بيانات صالحة", () => {
  assert.throws(() => createDbAuthStore({}), /a database instance with a query method is required/);
  assert.throws(() => createDbAuthStore({ database: null }), /a database instance with a query method is required/);
});

// ------------------------------------------------------------------
// Gruppo B5: عدم الاعتماد على Map — لا يوجد تخزين مؤقت
// ------------------------------------------------------------------
test("dbAuthStore: لا يحتوي على خاصية size أو cleanupExpired (ليس Map)", () => {
  const db = mockDatabase();
  const store = createDbAuthStore({ database: db });
  assert.equal(typeof store.size, "undefined");
  assert.equal(typeof store.cleanupExpired, "undefined");
  assert.equal(typeof store.create, "function");
  assert.equal(typeof store.consume, "function");
  assert.equal(typeof store.revoke, "function");
  assert.equal(typeof store.get, "function");
});

// ------------------------------------------------------------------
// Gruppo C: اختبارات المسار (route-level) مع mock database و mock storage
// ------------------------------------------------------------------

function mockRouter({ db, storage, authenticate = (req, _res, next) => { req.user = { id: userId, is_admin: false }; next(); } } = {}) {
  return createWalletRouter({ database: db, authenticate, uploadAuthStore: createDbAuthStore({ database: db }), storageBucket: bucket });
}

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
  const targetSegments = String(path).split("/").filter(Boolean);
  return router.stack.find((l) => {
    if (!l.route || !l.route.methods[method]) return false;
    const patternSegments = String(l.route.path).split("/").filter(Boolean);
    if (patternSegments.length !== targetSegments.length) return false;
    return patternSegments.every((seg, i) => {
      if (seg.startsWith(":")) return true;
      return seg === targetSegments[i];
    });
  });
}

function invokeRoute(route, req, res) {
  if (!req.params) req.params = {};
  const patternSegments = String(route.route.path).split("/").filter(Boolean);
  const urlSegments = String((req.url || "").split("?")[0]).split("/").filter(Boolean);
  patternSegments.forEach((seg, i) => {
    if (seg.startsWith(":")) req.params[seg.slice(1)] = urlSegments[i];
  });
  return route.route.stack[0].handle(req, res);
}

// فشل التخزين
test("route: receipt linking يفشل عندما يتوقف التخزين (storage download error)", async () => {
  const db = {
    query: async (sql) => {
      const q = norm(sql);
      if (q.includes("SELECT status, user_id, receipt_image_url FROM public.wallet_transactions") && q.includes("FOR UPDATE")) {
        return { rows: [{ status: "pending", user_id: userId, receipt_image_url: null }], rowCount: 1 };
      }
      if (q.includes("UPDATE public.upload_authorizations SET used = TRUE")) {
        return {
          rows: [consumeRow(userId, txId, objectKey, bucket, new Date(Date.now() + 300000).toISOString())],
          rowCount: 1,
        };
      }
      if (q.includes("UPDATE public.wallet_transactions SET receipt_image_url")) {
        return { rows: [{ id: txId }], rowCount: 1 };
      }
      return { rows: [], rowCount: 0 };
    },
  };
  const storage = {
    download: async () => { const e = new Error("R2 unavailable"); e.statusCode = 503; throw e; },
  };
  const router = mockRouter({ db, storage });

  // Pre-create a matching pending authorization via the same db-backed store contract
  // so the receipt-link route can validate/get/consume it before storage verification.
  await db.query(
    `INSERT INTO public.upload_authorizations (id, user_id, tx_id, object_key, bucket, expires_at, used)
     VALUES ($1, $2, $3, $4, $5, $6, FALSE)`,
    ["auth-123", userId, txId, objectKey, bucket, new Date(Date.now() + 300000).toISOString()]
  );

  // Route uses db-backed store get/consume; provide explicit responses for this auth id.
  const authDb = {
    query: async (sql, params) => {
      const q = norm(sql);
      if (q.includes("SELECT status, user_id, receipt_image_url FROM public.wallet_transactions") && q.includes("FOR UPDATE")) {
        return { rows: [{ status: "pending", user_id: userId, receipt_image_url: null }], rowCount: 1 };
      }
      if (q.startsWith("SELECT") && q.includes("FROM public.upload_authorizations") && q.includes("WHERE id = $1") && !q.includes("UPDATE")) {
        return { rows: [{ id: "auth-123", user_id: userId, tx_id: txId, object_key: objectKey, bucket, expires_at: new Date(Date.now() + 300000).toISOString(), used: false }], rowCount: 1 };
      }
      if (q.startsWith("UPDATE public.upload_authorizations") && q.includes("SET used = TRUE")) {
        return { rows: [consumeRow(userId, txId, objectKey, bucket, new Date(Date.now() + 300000).toISOString())], rowCount: 1 };
      }
      return { rows: [], rowCount: 0 };
    },
  };
  const router2 = mockRouter({ db: authDb, storage });

  const req = {
    method: "POST", url: `/topups/${txId}/receipt`,
    body: { authorizationId: "auth-123" },
    user: { id: userId },
    app: { locals: { storageService: storage } },
  };
  const res = mockResponse();
  const route = findRoute(router2, "post", `/topups/${txId}/receipt`);
  await invokeRoute(route, req, res);
  assert.equal(res.statusCode, 503);
  assert.ok(res.body.error);
});

// عدم ربط الإيصال عند فشل استهلاك الإذن (already used)
test("route: لا يُربط الإيصال عند فشل استهلاك الإذن (مستخدم مسبقاً)", async () => {
  const db = {
    query: async (sql) => {
      const q = norm(sql);
      if (q.includes("SELECT status, user_id, receipt_image_url FROM public.wallet_transactions") && q.includes("FOR UPDATE")) {
        return { rows: [{ status: "pending", user_id: userId, receipt_image_url: null }], rowCount: 1 };
      }
      if (q.includes("UPDATE public.upload_authorizations SET used = TRUE")) {
        return { rows: [], rowCount: 0 }; // الاستهلاك فشل — الإذن مستخدم مسبقاً أو منتهي
      }
      return { rows: [], rowCount: 0 };
    },
  };
  const storage = { download: async () => ({ size: 100 }) };
  const router = mockRouter({ db, storage });

  const req = {
    method: "POST", url: `/topups/${txId}/receipt`,
    body: { authorizationId: "auth-used" },
    user: { id: userId },
    app: { locals: { storageService: storage } },
  };
  const res = mockResponse();
  const route = findRoute(router, "post", `/topups/${txId}/receipt`);
  await invokeRoute(route, req, res);
  assert.equal(res.statusCode, 403);
  assert.ok(res.body.error);
});

// الاحتفاظ بالإيصال بعد confirmed — /decide لا يمسح receipt_image_url
test("route: يحتفظ بالإيصال بعد تأكيد المعاملة (confirmed)", async () => {
  const db = {
    query: async (sql) => {
      if (sql.includes("SELECT 1 FROM public.app_admins WHERE user_id = $1")) {
        return { rows: [{ 1: 1 }], rowCount: 1 };
      }
      if (sql.includes("SELECT status FROM public.wallet_transactions WHERE id = $1")) {
        return { rows: [{ status: "pending" }], rowCount: 1 };
      }
      if (sql.includes("UPDATE public.wallet_transactions SET status = $1")) {
        // التأكد من أن الـ UPDATE لا يتضمن receipt_image_url
        assert.ok(!sql.includes("receipt_image_url"), "الـ UPDATE لـ /decide لا يجب أن يمسح receipt_image_url");
        return { rows: [], rowCount: 1 };
      }
      return { rows: [], rowCount: 0 };
    },
  };
  const router = mockRouter({ db });

  const req = {
    method: "POST", url: "/decide",
    body: { id: txId, status: "confirmed" },
    user: { id: userId, is_admin: true },
  };
  const res = mockResponse();
  const route = findRoute(router, "post", "/decide");
  await invokeRoute(route, req, res);
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.ok, true);
});

// الاحتفاظ بالإيصال بعد rejected — /decide لا يمسح receipt_image_url
test("route: يحتفظ بالإيصال بعد رفض المعاملة (rejected)", async () => {
  const db = {
    query: async (sql) => {
      if (sql.includes("SELECT 1 FROM public.app_admins WHERE user_id = $1")) {
        return { rows: [{ 1: 1 }], rowCount: 1 };
      }
      if (sql.includes("SELECT status FROM public.wallet_transactions WHERE id = $1")) {
        return { rows: [{ status: "pending" }], rowCount: 1 };
      }
      if (sql.includes("UPDATE public.wallet_transactions SET status = $1")) {
        assert.ok(!sql.includes("receipt_image_url"), "الـ UPDATE لـ /decide لا يجب أن يمسح receipt_image_url");
        return { rows: [], rowCount: 1 };
      }
      return { rows: [], rowCount: 0 };
    },
  };
  const router = mockRouter({ db });

  const req = {
    method: "POST", url: "/decide",
    body: { id: txId, status: "rejected" },
    user: { id: userId, is_admin: true },
  };
  const res = mockResponse();
  const route = findRoute(router, "post", "/decide");
  await invokeRoute(route, req, res);
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.ok, true);
});

// عدم السماح بربط إيصال بمعاملة غير pending
test("route: يرفض ربط إيصال لمعاملة غير pending (محسومة مسبقاً)", async () => {
  const db = {
    query: async (sql) => {
      const q = norm(sql);
      if (q.includes("SELECT status, user_id, receipt_image_url FROM public.wallet_transactions") && q.includes("FOR UPDATE")) {
        return { rows: [{ status: "confirmed", user_id: userId, receipt_image_url: "old-receipt.jpg" }], rowCount: 1 };
      }
      return { rows: [], rowCount: 0 };
    },
  };
  const storage = { download: async () => ({ size: 100 }) };
  const router = mockRouter({ db, storage });

  const req = {
    method: "POST", url: `/topups/${txId}/receipt`,
    body: { authorizationId: "auth-123" },
    user: { id: userId },
    app: { locals: { storageService: storage } },
  };
  const res = mockResponse();
  const route = findRoute(router, "post", `/topups/${txId}/receipt`);
  await invokeRoute(route, req, res);
  assert.equal(res.statusCode, 409);
  assert.ok(res.body.error);
});

// لا يُسمح بتغيير إيصال معاملة محسومة عبر authorize
test("route: يرفض إصدار إذن رفع لمعاملة محسومة مسبقاً", async () => {
  const db = {
    query: async (sql) => {
      const q = norm(sql);
      if (q.includes("SELECT status, user_id") && q.includes("FROM public.wallet_transactions")) {
        return { rows: [{ status: "confirmed", user_id: userId }], rowCount: 1 };
      }
      return { rows: [], rowCount: 0 };
    },
  };
  const router = mockRouter({ db });

  const req = {
    method: "POST", url: `/topups/${txId}/receipt/authorize`,
    user: { id: userId },
  };
  const res = mockResponse();
  const route = findRoute(router, "post", `/topups/${txId}/receipt/authorize`);
  await invokeRoute(route, req, res);
  assert.equal(res.statusCode, 409);
  assert.ok(res.body.error);
});

// خطأ واضح عندما يكون جدول upload_authorizations غائباً
test("route: خطأ واضح عندما يكون جدول upload_authorizations غائباً", async () => {
  const db = {
    query: async (sql) => {
      const q = norm(sql);
      if (q.includes("SELECT status, user_id") && q.includes("FROM public.wallet_transactions")) {
        return { rows: [{ status: "pending", user_id: userId, receipt_image_url: null }], rowCount: 1 };
      }
      if (q.includes("INSERT INTO public.upload_authorizations")) {
        throw new Error('relation "public.upload_authorizations" does not exist');
      }
      return { rows: [], rowCount: 0 };
    },
  };
  const router = mockRouter({ db });

  const req = {
    method: "POST", url: `/topups/${txId}/receipt/authorize`,
    user: { id: userId },
  };
  const res = mockResponse();
  const route = findRoute(router, "post", `/topups/${txId}/receipt/authorize`);
  await invokeRoute(route, req, res);
  assert.equal(res.statusCode, 500);
  assert.ok(res.body.error);
});
